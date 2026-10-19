// MeloNX integrado en OmniStation Dock (Nintendo Switch).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Anfitrión propio de OmniStation para el runtime de MeloNX (AGPL-3.0, https://melonx.org;
// Ryujinx, MIT). Hace lo mismo que la app MeloNX antes de jugar:
//  1. Carga el runtime de Frameworks/ (SDL2, MoltenVK, ayudantes y el núcleo) y llama a initialize.
//  2. La extensión de JIT de OmniStation engancha StikJIT (script universal en iOS 26).
//  3. initialize-dualmapped (iOS 26), set_native_window con la CAMetalLayer, mandos y
//     main_ryujinx_sdl en un hilo propio hasta que se cierra la partida.
#import "OSMeloNXEngine.h"

#import <UIKit/UIKit.h>
#import <GameController/GameController.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <poll.h>
#import <arpa/inet.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <sys/types.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <os/proc.h>
#import <fcntl.h>
#import <unistd.h>

extern int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
extern void *SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern CFTypeRef SecTaskCopyValueForEntitlement(void *task, CFStringRef entitlement, CFErrorRef *error);

#ifndef CS_OPS_STATUS
#define CS_OPS_STATUS 0
#endif
#ifndef CS_DEBUGGED
#define CS_DEBUGGED 0x10000000
#endif

static NSString *const kOSNXJitRequestType = @"com.omnistation.dock.jit-request";
static NSTimeInterval const kOSNXConnectTimeout = 30.0;
static NSTimeInterval const kOSNXAttachTimeout = 600.0;

// MARK: - Estado del proceso

static BOOL OSNXHasEntitlement(CFStringRef name) {
    void *task = SecTaskCreateFromSelf(NULL);
    if (task == NULL) return NO;
    CFTypeRef value = SecTaskCopyValueForEntitlement(task, name, NULL);
    BOOL allowed = value == kCFBooleanTrue;
    if (value != NULL) CFRelease(value);
    CFRelease((CFTypeRef)task);
    return allowed;
}

static BOOL OSNXIsDebugged(void) {
    uint32_t flags = 0;
    if (csops(getpid(), CS_OPS_STATUS, &flags, sizeof(flags)) != 0) return NO;
    return (flags & CS_DEBUGGED) != 0;
}

static BOOL OSNXUsesScript(void) {
    return NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26;
}

static NSString *OSNXEntryWithLength(NSString *directory, NSUInteger length) {
    NSArray<NSString *> *items = [NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:nil];
    for (NSString *item in items) {
        if (item.length == length) return [directory stringByAppendingPathComponent:item];
    }
    return nil;
}

/// ¿Tiene este iPhone TXM? (La misma comprobación que hace MeloNX.)
static BOOL OSNXHasTXM(void) {
    NSString *image = @"usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4";
    NSString *boot = OSNXEntryWithLength(@"/System/Volumes/Preboot", 36);
    if (boot != nil) {
        NSString *file = OSNXEntryWithLength([boot stringByAppendingPathComponent:@"boot"], 96);
        if (file != nil) return access([file stringByAppendingPathComponent:image].fileSystemRepresentation, F_OK) == 0;
    }
    NSString *preboot = OSNXEntryWithLength(@"/private/preboot", 96);
    if (preboot == nil) return NO;
    return access([preboot stringByAppendingPathComponent:image].fileSystemRepresentation, F_OK) == 0;
}

static NSString *OSNXText(NSString *language, NSString *spanish, NSString *english) {
    return [language isEqualToString:@"en"] ? english : spanish;
}

static NSString *OSNXDocuments(void) {
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject ?: NSTemporaryDirectory();
}

// MARK: - Sesión con la extensión de JIT

@interface OSNXJitSession : NSObject
@property (nonatomic, readonly) uint16_t port;
@property (nonatomic, readonly) uint32_t nonce;
@property (nonatomic, readonly, copy) NSString *token;
@property (nonatomic, assign) BOOL usesScript;
@property (nonatomic, strong, nullable) id extensionObject;
@property (nonatomic, strong, nullable) id requestIdentifier;
@property (nonatomic, copy, nullable) void (^logHandler)(NSString *message);
- (nullable instancetype)initWithError:(NSString **)error;
- (void)startReader;
- (BOOL)waitUntilConnected:(NSTimeInterval)timeout;
- (BOOL)waitUntilAttached:(NSTimeInterval)timeout;
- (BOOL)connected;
- (BOOL)attached;
- (BOOL)finished;
- (BOOL)success;
- (BOOL)closed;
- (NSString *)finalMessage;
- (NSString *)lastLog;
- (void)close;
@end

@implementation OSNXJitSession {
    int _listener;
    int _client;
    NSCondition *_condition;
    BOOL _connected;
    BOOL _attached;
    BOOL _finished;
    BOOL _success;
    BOOL _closed;
    NSString *_finalMessage;
    NSString *_lastLog;
    dispatch_queue_t _readerQueue;
}

- (nullable instancetype)initWithError:(NSString **)error {
    self = [super init];
    if (!self) return nil;
    _client = -1;
    _listener = socket(AF_INET, SOCK_STREAM, 0);
    if (_listener < 0) {
        if (error) *error = @"No se pudo crear el canal con la extensión de JIT.";
        return nil;
    }
    int reuse = 1;
    setsockopt(_listener, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = 0;
    if (bind(_listener, (struct sockaddr *)&address, sizeof(address)) != 0 || listen(_listener, 1) != 0) {
        close(_listener);
        _listener = -1;
        if (error) *error = @"No se pudo abrir el canal con la extensión de JIT.";
        return nil;
    }
    socklen_t length = sizeof(address);
    if (getsockname(_listener, (struct sockaddr *)&address, &length) != 0) {
        close(_listener);
        _listener = -1;
        if (error) *error = @"No se pudo leer el puerto del canal de JIT.";
        return nil;
    }
    _port = ntohs(address.sin_port);
    _token = [NSUUID UUID].UUIDString;
    _nonce = arc4random_uniform(UINT32_MAX - 1) + 1;
    _condition = [NSCondition new];
    _finalMessage = @"";
    _lastLog = @"";
    _readerQueue = dispatch_queue_create("com.omnistation.dock.melonx-jit-reader", DISPATCH_QUEUE_SERIAL);
    return self;
}

- (BOOL)readFlag:(BOOL *)flag {
    [_condition lock];
    BOOL value = *flag;
    [_condition unlock];
    return value;
}

- (BOOL)connected { return [self readFlag:&_connected]; }
- (BOOL)attached { return [self readFlag:&_attached]; }
- (BOOL)finished { return [self readFlag:&_finished]; }
- (BOOL)success { return [self readFlag:&_success]; }
- (BOOL)closed { return [self readFlag:&_closed]; }

- (NSString *)finalMessage {
    [_condition lock];
    NSString *value = [_finalMessage copy];
    [_condition unlock];
    return value;
}

- (NSString *)lastLog {
    [_condition lock];
    NSString *value = [_lastLog copy];
    [_condition unlock];
    return value;
}

- (void)markFinished:(BOOL)success message:(NSString *)message {
    [_condition lock];
    _finished = YES;
    _success = success;
    _finalMessage = message ?: @"";
    [_condition broadcast];
    [_condition unlock];
}

- (void)cancelExtensionRequest {
    id extension = self.extensionObject;
    id identifier = self.requestIdentifier;
    if (!extension || !identifier) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        SEL selector = NSSelectorFromString(@"cancelExtensionRequestWithIdentifier:");
        if ([extension respondsToSelector:selector]) {
            void (*cancelMessage)(id, SEL, id) = (void (*)(id, SEL, id))objc_msgSend;
            cancelMessage(extension, selector, identifier);
        }
    });
}

- (void)startReader {
    __weak OSNXJitSession *weakSelf = self;
    dispatch_async(_readerQueue, ^{
        OSNXJitSession *strongSelf = weakSelf;
        if (strongSelf == nil) return;
        struct pollfd descriptor = {strongSelf->_listener, POLLIN, 0};
        int pollResult = poll(&descriptor, 1, (int)(kOSNXConnectTimeout * 1000.0));
        if (pollResult <= 0) {
            [strongSelf markFinished:NO message:@"La extensión de JIT no se conectó con OmniStation."];
            return;
        }
        int accepted = accept(strongSelf->_listener, NULL, NULL);
        if (accepted < 0) {
            [strongSelf markFinished:NO message:@"No se pudo aceptar el canal de la extensión de JIT."];
            return;
        }
        FILE *stream = fdopen(accepted, "r");
        if (stream == NULL) {
            close(accepted);
            [strongSelf markFinished:NO message:@"No se pudo abrir el canal de la extensión de JIT."];
            return;
        }
        [strongSelf->_condition lock];
        if (strongSelf->_closed) {
            [strongSelf->_condition unlock];
            fclose(stream);
            return;
        }
        strongSelf->_client = dup(fileno(stream));
        [strongSelf->_condition unlock];

        char buffer[65536];
        while (fgets(buffer, sizeof(buffer), stream) != NULL) {
            @autoreleasepool {
                NSString *line = [[NSString alloc] initWithUTF8String:buffer];
                line = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if (line.length == 0) continue;
                NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
                id decoded = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
                if (![decoded isKindOfClass:NSDictionary.class]) continue;
                NSDictionary *payload = (NSDictionary *)decoded;
                if (![payload[@"token"] isKindOfClass:NSString.class] ||
                    ![payload[@"token"] isEqualToString:strongSelf.token]) continue;
                NSString *event = [payload[@"event"] isKindOfClass:NSString.class] ? payload[@"event"] : @"unknown";
                NSString *message = [payload[@"message"] isKindOfClass:NSString.class] ? payload[@"message"] : @"";
                NSLog(@"[OmniStation MeloNX JIT] %@ %@", event, message);

                void (^handler)(NSString *) = nil;
                [strongSelf->_condition lock];
                if ([event isEqualToString:@"helper_connected"]) {
                    strongSelf->_connected = YES;
                } else if ([event isEqualToString:@"pid_attached"] && strongSelf->_connected) {
                    NSNumber *pid = [payload[@"targetPID"] isKindOfClass:NSNumber.class] ? payload[@"targetPID"] : nil;
                    if (pid != nil && pid.intValue == getpid()) strongSelf->_attached = YES;
                } else if ([event isEqualToString:@"log"]) {
                    if (message.length > 0) {
                        strongSelf->_lastLog = message;
                        handler = strongSelf.logHandler;
                    }
                } else if ([event isEqualToString:@"complete"]) {
                    strongSelf->_finished = YES;
                    strongSelf->_success = [payload[@"success"] boolValue];
                    strongSelf->_finalMessage = message ?: @"";
                }
                [strongSelf->_condition broadcast];
                [strongSelf->_condition unlock];
                if (handler) handler(message);
            }
            if (strongSelf.finished) break;
        }
        fclose(stream);
        if (!strongSelf.finished) {
            [strongSelf markFinished:NO message:@"La extensión de JIT se desconectó antes de terminar."];
        }
    });
}

- (void)waitFor:(BOOL (^)(void))predicate timeout:(NSTimeInterval)timeout {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    [_condition lock];
    while (!predicate()) {
        if (![_condition waitUntilDate:deadline]) break;
    }
    [_condition unlock];
}

- (BOOL)waitUntilConnected:(NSTimeInterval)timeout {
    [self waitFor:^BOOL { return self->_connected || self->_finished || self->_closed; } timeout:timeout];
    return self.connected && !self.closed;
}

- (BOOL)waitUntilAttached:(NSTimeInterval)timeout {
    [self waitFor:^BOOL { return self->_attached || self->_finished || self->_closed; } timeout:timeout];
    // Con script (iOS 26) el depurador sigue enganchado; sin script basta con que termine bien.
    return (self.attached && !self.closed && !self.finished) ||
        (!self.usesScript && self.connected && self.finished && self.success);
}

- (void)close {
    [_condition lock];
    if (_closed) {
        [_condition unlock];
        return;
    }
    _closed = YES;
    if (_listener >= 0) {
        shutdown(_listener, SHUT_RDWR);
        close(_listener);
        _listener = -1;
    }
    if (_client >= 0) {
        shutdown(_client, SHUT_RDWR);
        close(_client);
        _client = -1;
    }
    BOOL finished = _finished;
    [_condition broadcast];
    [_condition unlock];
    if (!finished) [self cancelExtensionRequest];
}

- (void)dealloc {
    [self close];
}

@end

static NSString *OSNXHelperBundleIdentifier(void) {
    NSURL *plugins = NSBundle.mainBundle.builtInPlugInsURL;
    if (plugins == nil) return nil;
    NSArray<NSURL *> *entries = [NSFileManager.defaultManager contentsOfDirectoryAtURL:plugins
                                                            includingPropertiesForKeys:nil
                                                                               options:0
                                                                                 error:nil];
    for (NSURL *entry in entries) {
        if (![entry.pathExtension.lowercaseString isEqualToString:@"appex"]) continue;
        NSBundle *bundle = [NSBundle bundleWithURL:entry];
        id marker = [bundle objectForInfoDictionaryKey:@"OmniStationJITHelper"];
        if ([marker isKindOfClass:NSString.class] && [marker isEqualToString:@"1"] && bundle.bundleIdentifier.length > 0) {
            return bundle.bundleIdentifier;
        }
    }
    return nil;
}

static BOOL OSNXLaunchHelper(OSNXJitSession *session, NSData *pairingData, NSString **error) {
    NSString *identifier = OSNXHelperBundleIdentifier();
    if (identifier.length == 0) {
        if (error) *error = @"Falta la extensión de JIT de OmniStation. Al instalar con SideStore, no quites las extensiones de la app.";
        return NO;
    }
    NSDictionary *request = @{
        @"protocolVersion": @1,
        @"probeNonce": @(session.nonce),
        @"targetPID": @(getpid()),
        @"port": @(session.port),
        @"token": session.token,
        @"pairingData": [pairingData base64EncodedStringWithOptions:0],
        @"requiresCoreHandshake": @(session.usesScript),
        // MeloNX usa el script universal de StikDebug (no el de ARMSX2).
        @"script": @"universal",
    };
    NSData *requestData = [NSJSONSerialization dataWithJSONObject:request options:0 error:nil];
    if (requestData == nil) {
        if (error) *error = @"No se pudo preparar la petición de JIT.";
        return NO;
    }
    NSItemProvider *provider = [[NSItemProvider alloc] initWithItem:requestData typeIdentifier:kOSNXJitRequestType];
    NSExtensionItem *item = [NSExtensionItem new];
    item.attachments = @[provider];

    Class extensionClass = NSClassFromString(@"NSExtension");
    SEL createSelector = NSSelectorFromString(@"extensionWithIdentifier:error:");
    SEL beginSelector = NSSelectorFromString(@"beginExtensionRequestWithInputItems:completion:");
    if (extensionClass == Nil || ![extensionClass respondsToSelector:createSelector]) {
        if (error) *error = @"Este iOS no deja lanzar la extensión de JIT.";
        return NO;
    }
    NSError *__autoreleasing createError = nil;
    id (*createMessage)(id, SEL, NSString *, NSError *__autoreleasing *) =
        (id (*)(id, SEL, NSString *, NSError *__autoreleasing *))objc_msgSend;
    id extension = createMessage((id)extensionClass, createSelector, identifier, &createError);
    if (extension == nil || ![extension respondsToSelector:beginSelector]) {
        if (error) *error = createError.localizedDescription ?: @"No se pudo abrir la extensión de JIT.";
        return NO;
    }
    session.extensionObject = extension;
    __weak OSNXJitSession *weakSession = session;
    void (^completion)(id) = ^(id requestIdentifier) {
        OSNXJitSession *strongSession = weakSession;
        if (strongSession == nil) return;
        strongSession.requestIdentifier = requestIdentifier;
        if (strongSession.closed) [strongSession cancelExtensionRequest];
    };
    void (*beginMessage)(id, SEL, NSArray *, id) = (void (*)(id, SEL, NSArray *, id))objc_msgSend;
    beginMessage(extension, beginSelector, @[item], completion);
    return YES;
}

// MARK: - Funciones del runtime

typedef struct {
    void (*initialize)(void);
    bool (*initializeDualMapped)(void);
    int32_t (*mainRyujinx)(int32_t argc, char **argv);
    void (*setNativeWindow)(void *layer);
    void (*pauseEmulation)(bool pause);
    void (*stopEmulation)(void);
    char *(*installFirmware)(const char *path);
    char *(*installedFirmwareVersion)(void);
    void (*freeFirmwareVersion)(char *text);
    void *(*attachGamepad)(const char *name, void *identifier);
    void (*detachGamepad)(void *identifier);
    void (*setButtonState)(void *identifier, int32_t button, uint8_t pressed);
    void (*setStickAxis)(void *identifier, int32_t stick, float x, float y);
    void (*setGamepadConfiguration)(int32_t argc, char **argv);
    void (*touchBegan)(float x, float y, int32_t index);
    void (*touchMoved)(float x, float y, int32_t index);
    void (*touchEnded)(int32_t index);
    void (*setViewSize)(int32_t width, int32_t height);
    void (*registerCallback)(NSString *identifier, void (^callback)(NSString *result));
} OSNXCoreAPI;

// Botones tal como los numera MeloNX (VirtualControllerButton).
typedef NS_ENUM(int32_t, OSNXButton) {
    OSNXButtonA = 0, OSNXButtonB, OSNXButtonX, OSNXButtonY, OSNXButtonBack, OSNXButtonGuide, OSNXButtonStart,
    OSNXButtonLeftStick, OSNXButtonRightStick, OSNXButtonLeftShoulder, OSNXButtonRightShoulder,
    OSNXButtonDPadUp, OSNXButtonDPadDown, OSNXButtonDPadLeft, OSNXButtonDPadRight,
    OSNXButtonLeftTrigger, OSNXButtonRightTrigger, OSNXButtonCount
};

/// Llama a una función del núcleo con una lista de argumentos (copias en C que se liberan después).
static int32_t OSNXCallWithArguments(NSArray<NSString *> *arguments, int32_t (^body)(int32_t, char **)) {
    int32_t count = (int32_t)arguments.count;
    char **argv = calloc((size_t)count + 1, sizeof(char *));
    if (argv == NULL) return -1;
    for (int32_t index = 0; index < count; index++) argv[index] = strdup(arguments[(NSUInteger)index].UTF8String ?: "");
    int32_t result = body(count, argv);
    for (int32_t index = 0; index < count; index++) free(argv[index]);
    free(argv);
    return result;
}

// MARK: - Mando físico → núcleo

@interface OSNXPad : NSObject
@property (nonatomic, strong) GCController *controller;
@property (nonatomic, assign) const OSNXCoreAPI *api;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, assign) BOOL suspended;
- (instancetype)initWithController:(GCController *)controller api:(const OSNXCoreAPI *)api;
- (void *)pointer;
- (void)releaseAll;
- (void)detach;
@end

@implementation OSNXPad

- (instancetype)initWithController:(GCController *)controller api:(const OSNXCoreAPI *)api {
    self = [super init];
    if (self) {
        _controller = controller;
        _api = api;
        _identifier = [NSString stringWithFormat:@"%llX", (unsigned long long)(uintptr_t)(__bridge void *)self];
        NSString *name = controller.vendorName.length ? controller.vendorName : @"OmniStation Controller";
        api->attachGamepad(name.UTF8String, (__bridge void *)self);
        [self bind];
    }
    return self;
}

- (void *)pointer {
    return (__bridge void *)self;
}

- (void)send:(OSNXButton)button pressed:(BOOL)pressed {
    if (self.suspended && pressed) return;
    self.api->setButtonState((__bridge void *)self, button, pressed ? 1 : 0);
}

- (void)bindButton:(GCControllerButtonInput *)input to:(OSNXButton)button {
    if (input == nil) return;
    __weak OSNXPad *weakSelf = self;
    input.valueChangedHandler = ^(GCControllerButtonInput *element, float value, BOOL pressed) {
        [weakSelf send:button pressed:pressed];
    };
}

- (void)bindStick:(GCControllerDirectionPad *)input stick:(int32_t)stick {
    __weak OSNXPad *weakSelf = self;
    input.valueChangedHandler = ^(GCControllerDirectionPad *element, float x, float y) {
        OSNXPad *strongSelf = weakSelf;
        if (strongSelf == nil) return;
        if (strongSelf.suspended) { x = 0; y = 0; }
        strongSelf.api->setStickAxis((__bridge void *)strongSelf, stick, x, y);
    };
}

- (void)bind {
    GCExtendedGamepad *pad = self.controller.extendedGamepad;
    if (pad == nil) return;
    [self bindButton:pad.buttonA to:OSNXButtonA];
    [self bindButton:pad.buttonB to:OSNXButtonB];
    [self bindButton:pad.buttonX to:OSNXButtonX];
    [self bindButton:pad.buttonY to:OSNXButtonY];
    [self bindButton:pad.dpad.up to:OSNXButtonDPadUp];
    [self bindButton:pad.dpad.down to:OSNXButtonDPadDown];
    [self bindButton:pad.dpad.left to:OSNXButtonDPadLeft];
    [self bindButton:pad.dpad.right to:OSNXButtonDPadRight];
    [self bindButton:pad.leftShoulder to:OSNXButtonLeftShoulder];
    [self bindButton:pad.rightShoulder to:OSNXButtonRightShoulder];
    [self bindButton:pad.leftTrigger to:OSNXButtonLeftTrigger];
    [self bindButton:pad.rightTrigger to:OSNXButtonRightTrigger];
    [self bindButton:pad.leftThumbstickButton to:OSNXButtonLeftStick];
    [self bindButton:pad.rightThumbstickButton to:OSNXButtonRightStick];
    [self bindButton:pad.buttonMenu to:OSNXButtonStart];
    [self bindButton:pad.buttonOptions to:OSNXButtonBack];
    [self bindStick:pad.leftThumbstick stick:1];
    [self bindStick:pad.rightThumbstick stick:2];
    if (pad.buttonHome != nil) {
        // Home abre el menú de OmniStation, no el de iOS.
        pad.buttonHome.preferredSystemGestureState = GCSystemGestureStateDisabled;
    }
}

- (void)releaseAll {
    for (int32_t button = 0; button < OSNXButtonCount; button++) {
        self.api->setButtonState((__bridge void *)self, button, 0);
    }
    self.api->setStickAxis((__bridge void *)self, 1, 0, 0);
    self.api->setStickAxis((__bridge void *)self, 2, 0, 0);
}

- (void)detach {
    GCExtendedGamepad *pad = self.controller.extendedGamepad;
    for (GCControllerElement *element in pad.allElements) {
        if ([element isKindOfClass:GCControllerButtonInput.class]) {
            ((GCControllerButtonInput *)element).valueChangedHandler = nil;
        } else if ([element isKindOfClass:GCControllerDirectionPad.class]) {
            ((GCControllerDirectionPad *)element).valueChangedHandler = nil;
        }
    }
    self.api->detachGamepad((__bridge void *)self);
}

@end

// MARK: - Vista del juego (CAMetalLayer para MoltenVK)

@interface OSNXMetalView : UIView
@property (nonatomic, assign) const OSNXCoreAPI *api;
@property (nonatomic, assign) BOOL touchEnabled;
@end

@implementation OSNXMetalView {
    NSMutableArray<UITouch *> *_touches;
}

+ (Class)layerClass {
    return CAMetalLayer.class;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _touches = [NSMutableArray new];
        self.multipleTouchEnabled = YES;
        self.backgroundColor = UIColor.blackColor;
        CAMetalLayer *layer = (CAMetalLayer *)self.layer;
        layer.device = MTLCreateSystemDefaultDevice();
        layer.contentsScale = UIScreen.mainScreen.nativeScale;
        layer.opaque = YES;
    }
    return self;
}

- (void)reportSize {
    if (self.api && self.api->setViewSize) {
        self.api->setViewSize((int32_t)self.bounds.size.width, (int32_t)self.bounds.size.height);
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self reportSize];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!self.touchEnabled || self.api == NULL) return;
    [self reportSize];
    for (UITouch *touch in touches) {
        CGPoint point = [touch locationInView:self];
        [_touches addObject:touch];
        self.api->touchBegan((float)point.x, (float)point.y, (int32_t)(_touches.count - 1));
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!self.touchEnabled || self.api == NULL) return;
    for (UITouch *touch in touches) {
        NSUInteger index = [_touches indexOfObject:touch];
        if (index == NSNotFound) continue;
        CGPoint point = [touch locationInView:self];
        self.api->touchMoved((float)point.x, (float)point.y, (int32_t)index);
    }
}

- (void)endTouches:(NSSet<UITouch *> *)touches {
    for (UITouch *touch in touches) {
        NSUInteger index = [_touches indexOfObject:touch];
        if (index == NSNotFound) continue;
        if (self.api) self.api->touchEnded((int32_t)index);
        [_touches removeObjectAtIndex:index];
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self endTouches:touches];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self endTouches:touches];
}

@end

// MARK: - Pantalla de juego

@interface OSNXGameViewController : UIViewController
@property (nonatomic, assign) const OSNXCoreAPI *api;
@property (nonatomic, copy) NSString *language;
@property (nonatomic, strong, readonly) OSNXMetalView *metalView;
@property (nonatomic, assign) BOOL closing;
@property (nonatomic, copy, nullable) void (^menuChanged)(BOOL open);
@property (nonatomic, copy, nullable) void (^quitRequested)(void);
- (void)showStatus:(NSString *)message sticky:(BOOL)sticky;
- (void)hideStatus;
@end

@implementation OSNXGameViewController {
    UIButton *_menuButton;
    UILabel *_statusLabel;
    UIView *_menuView;
    NSArray<UIButton *> *_menuRows;
    NSInteger _menuIndex;
    BOOL _menuVisible;
    CADisplayLink *_displayLink;
    BOOL _prevHome, _prevCombo, _prevUp, _prevDown, _prevA, _prevB;
    NSUInteger _statusToken;
}

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        _language = @"es";
        _metalView = [[OSNXMetalView alloc] initWithFrame:CGRectMake(0, 0, 16, 9)];
    }
    return self;
}

- (NSString *)t:(NSString *)spanish en:(NSString *)english {
    return OSNXText(self.language, spanish, english);
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures { return UIRectEdgeAll; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation { return UIInterfaceOrientationLandscapeRight; }

- (void)loadView {
    UIView *root = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    root.backgroundColor = UIColor.blackColor;
    self.view = root;
    self.metalView.api = self.api;
    self.metalView.touchEnabled = YES;
    [root addSubview:self.metalView];

    _menuButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _menuButton.tintColor = UIColor.whiteColor;
    _menuButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    _menuButton.layer.cornerRadius = 18;
    _menuButton.alpha = 0.6;
    [_menuButton setImage:[UIImage systemImageNamed:@"line.3.horizontal"] forState:UIControlStateNormal];
    [_menuButton addTarget:self action:@selector(openMenu) forControlEvents:UIControlEventTouchUpInside];
    [root addSubview:_menuButton];

    _statusLabel = [UILabel new];
    _statusLabel.textColor = UIColor.whiteColor;
    _statusLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    _statusLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.numberOfLines = 3;
    _statusLabel.layer.cornerRadius = 10;
    _statusLabel.clipsToBounds = YES;
    _statusLabel.alpha = 0;
    [root addSubview:_statusLabel];

    _menuView = [[UIView alloc] initWithFrame:root.bounds];
    _menuView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.72];
    _menuView.hidden = YES;
    NSMutableArray<UIButton *> *rows = [NSMutableArray new];
    NSArray<NSString *> *titles = @[[self t:@"Continuar" en:@"Resume"], [self t:@"Salir del juego" en:@"Quit game"]];
    for (NSUInteger index = 0; index < titles.count; index++) {
        UIButton *row = [UIButton buttonWithType:UIButtonTypeSystem];
        row.tag = (NSInteger)index;
        row.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
        row.layer.cornerRadius = 14;
        row.layer.borderColor = [UIColor colorWithRed:0.0 green:0.85 blue:1.0 alpha:1.0].CGColor;
        row.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
        [row setTitle:titles[index] forState:UIControlStateNormal];
        UIColor *color = index == titles.count - 1 ? [UIColor colorWithRed:1.0 green:0.55 blue:0.45 alpha:1.0] : UIColor.whiteColor;
        [row setTitleColor:color forState:UIControlStateNormal];
        [row addTarget:self action:@selector(menuRowTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_menuView addSubview:row];
        [rows addObject:row];
    }
    _menuRows = rows;
    [root addSubview:_menuView];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *root = self.view;
    CGFloat w = root.bounds.size.width;
    CGFloat h = root.bounds.size.height;
    // Pantalla 16:9 centrada (la de la Switch).
    CGFloat targetW = w;
    CGFloat targetH = floor(w * 9.0 / 16.0);
    if (targetH > h) {
        targetH = h;
        targetW = floor(h * 16.0 / 9.0);
    }
    self.metalView.frame = CGRectMake(floor((w - targetW) * 0.5), floor((h - targetH) * 0.5), targetW, targetH);
    UIEdgeInsets safe = root.safeAreaInsets;
    _menuButton.frame = CGRectMake(safe.left + 10, safe.top + 8, 36, 36);
    CGFloat labelWidth = MIN(w * 0.7, 440);
    _statusLabel.frame = CGRectMake((w - labelWidth) * 0.5, safe.top + 12, labelWidth, 58);
    _menuView.frame = root.bounds;
    CGFloat rowWidth = MIN(w - 40, 340);
    CGFloat rowHeight = 48;
    CGFloat total = rowHeight * (CGFloat)_menuRows.count + 12 * (CGFloat)(_menuRows.count - 1);
    CGFloat y = (h - total) * 0.5;
    for (UIButton *row in _menuRows) {
        row.frame = CGRectMake((w - rowWidth) * 0.5, y, rowWidth, rowHeight);
        y += rowHeight + 12;
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_displayLink == nil) {
        _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(pollController)];
        [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    UIApplication.sharedApplication.idleTimerDisabled = YES;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_displayLink invalidate];
    _displayLink = nil;
    UIApplication.sharedApplication.idleTimerDisabled = NO;
}

- (void)dealloc {
    [_displayLink invalidate];
}

- (void)showStatus:(NSString *)message sticky:(BOOL)sticky {
    if (message.length == 0) return;
    _statusToken += 1;
    NSUInteger token = _statusToken;
    _statusLabel.text = message;
    [self.view bringSubviewToFront:_statusLabel];
    [UIView animateWithDuration:0.15 animations:^{ self->_statusLabel.alpha = 1; }];
    if (sticky) return;
    __weak OSNXGameViewController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        OSNXGameViewController *strongSelf = weakSelf;
        if (!strongSelf || strongSelf->_statusToken != token) return;
        [strongSelf hideStatus];
    });
}

- (void)hideStatus {
    [UIView animateWithDuration:0.25 animations:^{ self->_statusLabel.alpha = 0; }];
}

- (void)refreshMenu {
    BOOL hasController = GCController.controllers.count > 0;
    for (UIButton *row in _menuRows) {
        row.layer.borderWidth = (hasController && row.tag == _menuIndex) ? 2.5 : 0;
    }
}

- (void)openMenu {
    if (_menuVisible || self.closing) return;
    _menuVisible = YES;
    _menuIndex = 0;
    [self refreshMenu];
    _menuView.hidden = NO;
    [self.view bringSubviewToFront:_menuView];
    if (self.menuChanged) self.menuChanged(YES);
}

- (void)closeMenu {
    if (!_menuVisible) return;
    _menuVisible = NO;
    _menuView.hidden = YES;
    if (self.menuChanged) self.menuChanged(NO);
}

- (void)menuRowTapped:(UIButton *)sender {
    [self activateRow:sender.tag];
}

- (void)activateRow:(NSInteger)row {
    if (row == 0) {
        [self closeMenu];
        return;
    }
    if (self.closing) return;
    self.closing = YES;
    _menuView.hidden = YES;
    _menuVisible = NO;
    [self showStatus:[self t:@"Cerrando el juego…" en:@"Closing the game…"] sticky:YES];
    if (self.quitRequested) self.quitRequested();
}

/// Mando: Home o SELECT+START abren el menú; dentro del menú, cruceta, ✕ y ○.
- (void)pollController {
    GCController *controller = GCController.current ?: GCController.controllers.firstObject;
    GCExtendedGamepad *pad = controller.extendedGamepad;
    if (pad == nil) return;
    BOOL home = pad.buttonHome != nil && pad.buttonHome.isPressed;
    BOOL combo = pad.buttonMenu.isPressed && pad.buttonOptions != nil && pad.buttonOptions.isPressed;
    float y = pad.dpad.yAxis.value;
    if (fabsf(y) < 0.5f) y = pad.leftThumbstick.yAxis.value;
    BOOL up = y > 0.5f;
    BOOL down = y < -0.5f;
    BOOL a = pad.buttonA.isPressed;
    BOOL b = pad.buttonB.isPressed;
    if (!_menuVisible) {
        if ((home && !_prevHome) || (combo && !_prevCombo)) [self openMenu];
    } else if (!self.closing) {
        NSInteger count = (NSInteger)_menuRows.count;
        if (up && !_prevUp) { _menuIndex = (_menuIndex + count - 1) % count; [self refreshMenu]; }
        if (down && !_prevDown) { _menuIndex = (_menuIndex + 1) % count; [self refreshMenu]; }
        if (a && !_prevA) [self activateRow:_menuIndex];
        if (b && !_prevB) [self closeMenu];
    }
    _prevHome = home;
    _prevCombo = combo;
    _prevUp = up;
    _prevDown = down;
    _prevA = a;
    _prevB = b;
}

@end

// MARK: - Motor

@interface OSMeloNXEngine ()
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, strong, nullable) OSNXJitSession *session;
@property (nonatomic, strong, nullable) OSNXGameViewController *gameController;
@property (nonatomic, strong) NSMutableArray<OSNXPad *> *pads;
@property (nonatomic, copy, nullable) void (^endedHandler)(void);
@property (nonatomic, copy, nullable) NSString *helperError;
@end

@implementation OSMeloNXEngine {
    OSNXCoreAPI _api;
    BOOL _loaded;
    BOOL _dualMapped;
    dispatch_queue_t _queue;
    NSMutableArray<id> *_observers;
    void (^_exitCallback)(NSString *);
    void (^_firstFrameCallback)(NSString *);
}

+ (OSMeloNXEngine *)shared {
    static OSMeloNXEngine *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [OSMeloNXEngine new]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        memset(&_api, 0, sizeof(_api));
        _queue = dispatch_queue_create("com.omnistation.dock.melonx", DISPATCH_QUEUE_SERIAL);
        _pads = [NSMutableArray new];
        _observers = [NSMutableArray new];
    }
    return self;
}

// MARK: Información

+ (NSDictionary *)manifest {
    NSURL *url = [NSBundle.mainBundle URLForResource:@"MeloNXRuntime" withExtension:@"json"];
    NSData *data = url ? [NSData dataWithContentsOfURL:url] : nil;
    id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [object isKindOfClass:NSDictionary.class] ? (NSDictionary *)object : @{};
}

+ (NSString *)frameworksPath {
    return NSBundle.mainBundle.privateFrameworksPath ?: @"";
}

+ (NSString *)corePath {
    NSString *core = [self.manifest[@"core"] isKindOfClass:NSString.class] ? self.manifest[@"core"] : @"Ryujinx.Headless.SDL2.dylib";
    return [self.frameworksPath stringByAppendingPathComponent:core];
}

+ (BOOL)runtimeBundled {
    return [NSFileManager.defaultManager isReadableFileAtPath:[self corePath]];
}

+ (NSString *)runtimeVersion {
    if (!self.runtimeBundled) return @"";
    id version = self.manifest[@"version"];
    return [version isKindOfClass:NSString.class] ? (NSString *)version : @"";
}

+ (BOOL)supportedHere {
    if (getenv("LC_HOME_PATH") != NULL) return NO;
    return NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 18;
}

+ (BOOL)helperBundled {
    return OSNXHelperBundleIdentifier().length > 0;
}

+ (BOOL)hasIncreasedMemoryLimit {
    return OSNXHasEntitlement(CFSTR("com.apple.developer.kernel.increased-memory-limit"));
}

+ (unsigned long long)availableMemory {
    return (unsigned long long)os_proc_available_memory();
}

+ (NSString *)keysDirectory {
    return [OSNXDocuments() stringByAppendingPathComponent:@"system"];
}

+ (BOOL)keysInstalled {
    return [NSFileManager.defaultManager fileExistsAtPath:[self.keysDirectory stringByAppendingPathComponent:@"prod.keys"]];
}

+ (NSString *)logPath {
    return [[OSNXDocuments() stringByAppendingPathComponent:@"MeloNX"] stringByAppendingPathComponent:@"Registro.txt"];
}

// MARK: Carga del runtime (una vez por proceso, en el hilo principal)

- (void *)symbol:(void *)handle name:(const char *)name missing:(NSMutableArray<NSString *> *)missing {
    void *pointer = dlsym(handle, name);
    if (pointer == NULL) [missing addObject:[NSString stringWithUTF8String:name]];
    return pointer;
}

/// Lo que escriben el núcleo y SDL va a Documentos/MeloNX/Registro.txt (para ver qué falló).
- (void)redirectOutput {
    NSString *path = [OSMeloNXEngine logPath];
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    int descriptor = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (descriptor < 0) return;
    fflush(stdout);
    fflush(stderr);
    dup2(descriptor, STDOUT_FILENO);
    dup2(descriptor, STDERR_FILENO);
    close(descriptor);
    setvbuf(stdout, NULL, _IOLBF, 0);
}

- (BOOL)loadRuntime:(NSString **)error {
    if (_loaded) return YES;
    if (![OSMeloNXEngine runtimeBundled]) {
        if (error) *error = @"Esta compilación no incluye el runtime de MeloNX.";
        return NO;
    }
    [self redirectOutput];
    NSString *frameworks = [OSMeloNXEngine frameworksPath];
    // El núcleo abre sus ayudantes por ruta relativa ("RyujinxHelper.framework/RyujinxHelper").
    chdir(frameworks.fileSystemRepresentation);

    BOOL txm = OSNXHasTXM();
    _dualMapped = OSNXUsesScript();
    setenv("HAS_TXM", txm ? "1" : "0", 1);
    setenv("DUAL_MAPPED_JIT", _dualMapped ? "1" : "0", 1);
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    BOOL tier2 = device != nil && device.argumentBuffersSupport >= MTLArgumentBuffersTier2;
    setenv("MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS", tier2 ? "1" : "0", 1);
    printf("[OmniStation] MeloNX %s · iOS %s · TXM %d · dual-mapped %d\n",
           [OSMeloNXEngine runtimeVersion].UTF8String,
           NSProcessInfo.processInfo.operatingSystemVersionString.UTF8String, txm, _dualMapped);

    void *sdl = NULL;
    void *helper = NULL;
    for (NSString *relative in @[@"SDL2.framework/SDL2", @"libMoltenVK.dylib", @"MoltenVK.framework/MoltenVK",
                                 @"RyujinxHelper.framework/RyujinxHelper", @"BreakpointJIT.framework/BreakpointJIT"]) {
        NSString *path = [frameworks stringByAppendingPathComponent:relative];
        if (![NSFileManager.defaultManager fileExistsAtPath:path]) continue;
        void *handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
        if (handle == NULL) {
            const char *detail = dlerror();
            printf("[OmniStation] No se pudo cargar %s: %s\n", relative.UTF8String, detail ? detail : "?");
            continue;
        }
        if ([relative hasPrefix:@"SDL2."]) sdl = handle;
        if ([relative hasPrefix:@"RyujinxHelper."]) helper = handle;
    }
    dlerror();
    void *core = dlopen([OSMeloNXEngine corePath].fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
    if (core == NULL) {
        const char *detail = dlerror();
        if (error) *error = [NSString stringWithFormat:@"No se pudo cargar el núcleo de MeloNX: %s", detail ? detail : "desconocido"];
        return NO;
    }
    if (sdl == NULL || helper == NULL) {
        if (error) *error = @"Faltan SDL2 o RyujinxHelper en el runtime de MeloNX.";
        return NO;
    }
    NSMutableArray<NSString *> *missing = [NSMutableArray new];
    OSNXCoreAPI api;
    memset(&api, 0, sizeof(api));
    api.initialize = (void (*)(void))[self symbol:core name:"initialize" missing:missing];
    api.mainRyujinx = (int32_t (*)(int32_t, char **))[self symbol:core name:"main_ryujinx_sdl" missing:missing];
    api.setNativeWindow = (void (*)(void *))[self symbol:core name:"set_native_window" missing:missing];
    api.pauseEmulation = (void (*)(bool))[self symbol:core name:"pause_emulation" missing:missing];
    api.stopEmulation = (void (*)(void))[self symbol:core name:"stop_emulation" missing:missing];
    api.installFirmware = (char *(*)(const char *))[self symbol:core name:"install_firmware" missing:missing];
    api.installedFirmwareVersion = (char *(*)(void))[self symbol:core name:"installed_firmware_version" missing:missing];
    api.freeFirmwareVersion = (void (*)(char *))[self symbol:core name:"free_firmware_version" missing:missing];
    api.attachGamepad = (void *(*)(const char *, void *))[self symbol:core name:"attach_gamepad" missing:missing];
    api.detachGamepad = (void (*)(void *))[self symbol:core name:"detach_gamepad" missing:missing];
    api.setButtonState = (void (*)(void *, int32_t, uint8_t))[self symbol:core name:"set_gamepad_button_state" missing:missing];
    api.setStickAxis = (void (*)(void *, int32_t, float, float))[self symbol:core name:"set_gamepad_stick_axis" missing:missing];
    api.setGamepadConfiguration = (void (*)(int32_t, char **))[self symbol:core name:"set_gamepad_configuration" missing:missing];
    api.touchBegan = (void (*)(float, float, int32_t))[self symbol:core name:"touch_began" missing:missing];
    api.touchMoved = (void (*)(float, float, int32_t))[self symbol:core name:"touch_moved" missing:missing];
    api.touchEnded = (void (*)(int32_t))[self symbol:core name:"touch_ended" missing:missing];
    api.setViewSize = (void (*)(int32_t, int32_t))[self symbol:core name:"set_view_size" missing:missing];
    if (_dualMapped) {
        api.initializeDualMapped = (bool (*)(void))[self symbol:core name:"initialize-dualmapped" missing:missing];
    }
    api.registerCallback = (void (*)(NSString *, void (^)(NSString *)))[self symbol:helper name:"RegisterCallback" missing:missing];
    void (*sdlSetMainReady)(void) = (void (*)(void))[self symbol:sdl name:"SDL_SetMainReady" missing:missing];
    void (*sdlSetEventPump)(int) = (void (*)(int))[self symbol:sdl name:"SDL_iPhoneSetEventPump" missing:missing];
    int (*sdlInit)(uint32_t) = (int (*)(uint32_t))[self symbol:sdl name:"SDL_Init" missing:missing];
    if (missing.count > 0) {
        if (error) *error = [@"El runtime de MeloNX no es compatible con esta versión de OmniStation. Falta: " stringByAppendingString:[missing componentsJoinedByString:@", "]];
        return NO;
    }
    _api = api;
    // Como MeloNX al arrancar: SDL (eventos y audio) y después el núcleo.
    sdlSetMainReady();
    sdlSetEventPump(1);
    sdlInit(0x00004000u | 0x00000010u);
    _api.initialize();
    _loaded = YES;
    return YES;
}

- (BOOL)loadRuntimeOnMain:(NSString **)error {
    __block BOOL ok = NO;
    __block NSString *failure = nil;
    void (^work)(void) = ^{
        NSString *inner = nil;
        ok = [self loadRuntime:&inner];
        failure = inner;
    };
    if (NSThread.isMainThread) {
        work();
    } else {
        dispatch_sync(dispatch_get_main_queue(), work);
    }
    if (!ok && error) *error = failure;
    return ok;
}

// MARK: Firmware

- (void)installFirmwareAtPath:(NSString *)path completion:(void (^)(BOOL, NSString *))completion {
    if (self.busy) {
        completion(NO, @"Hay una partida abierta.");
        return;
    }
    if (![OSMeloNXEngine keysInstalled]) {
        completion(NO, @"Primero importa tus claves (prod.keys).");
        return;
    }
    NSString *error = nil;
    if (![self loadRuntimeOnMain:&error]) {
        completion(NO, error ?: @"No se pudo cargar MeloNX.");
        return;
    }
    dispatch_async(_queue, ^{
        char *raw = self->_api.installFirmware(path.fileSystemRepresentation);
        NSString *text = raw ? ([NSString stringWithUTF8String:raw] ?: @"") : @"";
        if (raw) self->_api.freeFirmwareVersion(raw);
        BOOL failed = raw == NULL || [text containsString:@"✖"];
        NSCharacterSet *trim = [NSCharacterSet characterSetWithCharactersInString:@"✖✔ \n\t"];
        NSString *clean = [text stringByTrimmingCharactersInSet:trim];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(!failed, clean.length ? clean : (failed ? @"No se pudo instalar el firmware." : @"Firmware instalado."));
        });
    });
}

- (void)readFirmwareVersion:(void (^)(NSString *))completion {
    if (![OSMeloNXEngine runtimeBundled] || ![OSMeloNXEngine keysInstalled] || self.busy) {
        completion(@"");
        return;
    }
    NSString *error = nil;
    if (![self loadRuntimeOnMain:&error]) {
        completion(@"");
        return;
    }
    dispatch_async(_queue, ^{
        char *raw = self->_api.installedFirmwareVersion();
        NSString *text = raw ? ([NSString stringWithUTF8String:raw] ?: @"") : @"";
        if (raw) self->_api.freeFirmwareVersion(raw);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(text); });
    });
}

// MARK: JIT

- (void)closeSession {
    [self.session close];
    self.session = nil;
}

- (BOOL)prepareJITWithPairing:(NSData *)pairingData progress:(void (^)(NSString *))progress error:(NSString **)error {
    if (!OSNXHasEntitlement(CFSTR("get-task-allow"))) {
        if (error) *error = @"Esta instalación no permite depurar OmniStation (falta get-task-allow). Instálala con SideStore o AltStore.";
        return NO;
    }
    NSString *sessionError = nil;
    OSNXJitSession *session = [[OSNXJitSession alloc] initWithError:&sessionError];
    if (session == nil) {
        if (error) *error = sessionError;
        return NO;
    }
    session.usesScript = OSNXUsesScript();
    session.logHandler = ^(NSString *message) {
        if ([message hasPrefix:@"StikJIT:"] && progress) progress(message);
    };
    self.session = session;
    [session startReader];
    __block BOOL launched = NO;
    self.helperError = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        NSString *innerError = nil;
        launched = OSNXLaunchHelper(session, pairingData, &innerError);
        if (!launched) self.helperError = innerError;
    });
    if (!launched) {
        NSString *launchError = self.helperError;
        [self closeSession];
        if (error) *error = launchError ?: @"No se pudo lanzar la extensión de JIT.";
        return NO;
    }
    if (![session waitUntilConnected:kOSNXConnectTimeout]) {
        NSString *message = session.finalMessage.length ? session.finalMessage : @"La extensión de JIT no se conectó.";
        [self closeSession];
        if (error) *error = message;
        return NO;
    }
    if (![session waitUntilAttached:kOSNXAttachTimeout]) {
        NSString *message = session.finalMessage.length ? session.finalMessage :
            [NSString stringWithFormat:@"StikJIT no terminó de prepararse. Último paso: %@", session.lastLog.length ? session.lastLog : @"—"];
        [self closeSession];
        if (error) *error = message;
        return NO;
    }
    if (!OSNXIsDebugged()) {
        [self closeSession];
        if (error) *error = @"StikJIT no dejó el JIT activo en OmniStation.";
        return NO;
    }
    return YES;
}

// MARK: Partida

+ (NSString *)machineName {
    struct utsname info;
    uname(&info);
    return [NSString stringWithUTF8String:info.machine] ?: @"iPhone";
}

- (NSArray<NSString *> *)inputArguments {
    NSMutableArray<NSString *> *arguments = [NSMutableArray new];
    NSUInteger slot = 1;
    for (OSNXPad *pad in self.pads) {
        if (slot > 8) break;
        [arguments addObjectsFromArray:@[[NSString stringWithFormat:@"--input-id-%lu", (unsigned long)slot], pad.identifier,
                                         [NSString stringWithFormat:@"--controller-type-%lu", (unsigned long)slot], @"ProController"]];
        slot += 1;
    }
    return arguments;
}

- (NSArray<NSString *> *)argumentsForGame:(NSString *)path size:(CGSize)size language:(NSString *)language docked:(BOOL)docked {
    BOOL english = [language isEqualToString:@"en"];
    NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithObject:path];
    [arguments addObjectsFromArray:@[@"--graphics-backend", @"Vulkan",
                                     @"--memory-manager-mode", @"HostMappedUnsafe",
                                     @"--exclusive-fullscreen", @"true",
                                     @"--exclusive-fullscreen-width", [NSString stringWithFormat:@"%d", (int)size.width],
                                     @"--exclusive-fullscreen-height", [NSString stringWithFormat:@"%d", (int)size.height],
                                     @"--device-model", [OSMeloNXEngine machineName],
                                     @"--device-display-name", UIDevice.currentDevice.model]];
    if ([OSMeloNXEngine hasIncreasedMemoryLimit]) [arguments addObject:@"--has-memory-entitlement"];
    [arguments addObjectsFromArray:@[@"--system-language", english ? @"AmericanEnglish" : @"Spanish",
                                     @"--system-region", english ? @"USA" : @"Europe",
                                     @"--aspect-ratio", @"Stretched",
                                     @"--system-timezone", NSTimeZone.localTimeZone.name,
                                     @"--correct-controller",
                                     @"--max-anisotropy", @"1.0",
                                     @"--disable-macro-hle",
                                     @"--disable-shader-cache"]];
    if (!docked) [arguments addObject:@"--disable-docked-mode"];
    [arguments addObjectsFromArray:[self inputArguments]];
    return arguments;
}

- (UIViewController *)topViewController {
    UIWindow *keyWindow = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) {
                keyWindow = window;
                break;
            }
        }
        if (keyWindow) break;
    }
    UIViewController *controller = keyWindow.rootViewController;
    while (controller.presentedViewController) controller = controller.presentedViewController;
    return controller;
}

- (void)attachConnectedPads {
    for (GCController *controller in GCController.controllers) {
        if (controller.extendedGamepad == nil) continue;
        BOOL known = NO;
        for (OSNXPad *pad in self.pads) {
            if (pad.controller == controller) known = YES;
        }
        if (!known) [self.pads addObject:[[OSNXPad alloc] initWithController:controller api:&_api]];
    }
}

- (void)reloadPads {
    NSArray<NSString *> *arguments = [self inputArguments];
    if (arguments.count == 0) return;
    const OSNXCoreAPI *api = &_api;
    OSNXCallWithArguments(arguments, ^int32_t(int32_t argc, char **argv) {
        api->setGamepadConfiguration(argc, argv);
        return 0;
    });
}

- (void)watchControllersAndApp {
    __weak OSMeloNXEngine *weakSelf = self;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [_observers addObject:[center addObserverForName:GCControllerDidConnectNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        OSMeloNXEngine *strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.busy) return;
        [strongSelf attachConnectedPads];
        [strongSelf reloadPads];
    }]];
    [_observers addObject:[center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        OSMeloNXEngine *strongSelf = weakSelf;
        if (strongSelf && strongSelf.busy && strongSelf->_api.pauseEmulation) strongSelf->_api.pauseEmulation(true);
    }]];
    [_observers addObject:[center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        OSMeloNXEngine *strongSelf = weakSelf;
        if (strongSelf && strongSelf.busy && strongSelf->_api.pauseEmulation && strongSelf.gameController.presentedViewController == nil) {
            strongSelf->_api.pauseEmulation(false);
        }
    }]];
}

- (void)stopWatching {
    for (id token in _observers) [NSNotificationCenter.defaultCenter removeObserver:token];
    [_observers removeAllObjects];
}

/// Último trozo del registro, para enseñarlo si algo falla.
+ (NSString *)logTail {
    NSString *text = [NSString stringWithContentsOfFile:[self logPath] encoding:NSUTF8StringEncoding error:nil] ?: @"";
    NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
    NSMutableArray<NSString *> *kept = [NSMutableArray new];
    for (NSString *line in lines.reverseObjectEnumerator) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (trimmed.length == 0) continue;
        [kept insertObject:trimmed atIndex:0];
        if (kept.count >= 3) break;
    }
    return [kept componentsJoinedByString:@"\n"];
}

/// Cierra la pantalla y deja todo listo para otra partida.
- (void)finishSessionWithMessage:(nullable NSString *)message
                      completion:(nullable void (^)(BOOL, NSString *))completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (OSNXPad *pad in self.pads) [pad detach];
        [self.pads removeAllObjects];
        [self stopWatching];
        [self closeSession];
        OSNXGameViewController *controller = self.gameController;
        self.gameController = nil;
        void (^done)(void) = ^{
            self.busy = NO;
            if (completion) {
                completion(NO, message ?: @"No se pudo arrancar el juego.");
            } else {
                void (^ended)(void) = self.endedHandler;
                self.endedHandler = nil;
                if (ended) ended();
            }
        };
        UIViewController *presenter = controller.presentingViewController;
        if (presenter) {
            [presenter dismissViewControllerAnimated:NO completion:done];
        } else {
            done();
        }
    });
}

- (void)launchGameAtPath:(NSString *)gamePath
                   title:(NSString *)title
             pairingData:(NSData *)pairingData
                language:(NSString *)language
                  docked:(BOOL)docked
                progress:(void (^)(NSString *))progress
              completion:(void (^)(BOOL, NSString *))completion
                   ended:(void (^)(void))ended {
    if (self.busy) {
        completion(NO, OSNXText(language, @"Ya hay una partida abierta.", @"A game is already running."));
        return;
    }
    if (![OSMeloNXEngine supportedHere]) {
        completion(NO, OSNXText(language, @"MeloNX integrado necesita iOS 18 y la app instalada con SideStore (no en LiveContainer).",
                                @"Built-in MeloNX needs iOS 18 and the app installed with SideStore (not in LiveContainer)."));
        return;
    }
    if (![OSMeloNXEngine keysInstalled]) {
        completion(NO, OSNXText(language, @"Faltan tus claves: impórtalas en Ajustes → MeloNX integrado → Claves.",
                                @"Your keys are missing: import them in Settings → Built-in MeloNX → Keys."));
        return;
    }
    if (![NSFileManager.defaultManager isReadableFileAtPath:gamePath]) {
        completion(NO, OSNXText(language, @"No se puede leer el archivo del juego.", @"The game file cannot be read."));
        return;
    }
    BOOL hasPad = NO;
    for (GCController *controller in GCController.controllers) {
        if (controller.extendedGamepad != nil) hasPad = YES;
    }
    if (!hasPad) {
        completion(NO, OSNXText(language, @"Conecta un mando para jugar a Switch.", @"Connect a controller to play Switch games."));
        return;
    }
    NSString *loadError = nil;
    if (![self loadRuntimeOnMain:&loadError]) {
        completion(NO, loadError ?: @"No se pudo cargar MeloNX.");
        return;
    }
    self.busy = YES;
    self.endedHandler = ended;
    void (^report)(NSString *) = ^(NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{ progress(message); });
    };

    dispatch_async(_queue, ^{
        NSString *error = nil;
        // Cada partida engancha el depurador de nuevo: el núcleo lo suelta al terminar de
        // reservar su memoria de JIT y para otra partida hace falta volver a hacerlo.
        report(OSNXText(language, @"Activando el JIT…", @"Enabling JIT…"));
        if (![self prepareJITWithPairing:pairingData progress:report error:&error]) {
            self.busy = NO;
            dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, error ?: @"El JIT no se pudo activar."); });
            return;
        }
        if (self->_dualMapped && self->_api.initializeDualMapped) {
            report(OSNXText(language, @"Preparando la memoria del JIT…", @"Preparing JIT memory…"));
            if (!self->_api.initializeDualMapped()) {
                [self finishSessionWithMessage:OSNXText(language, @"MeloNX no pudo preparar la memoria del JIT.",
                                                        @"MeloNX could not prepare JIT memory.")
                                    completion:completion];
                return;
            }
        }

        __block CGSize size = CGSizeZero;
        __block BOOL presented = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{
            UIViewController *root = [self topViewController];
            if (root == nil || root.view.window == nil) return;
            OSNXGameViewController *controller = [OSNXGameViewController new];
            controller.api = &self->_api;
            controller.language = language;
            controller.title = title;
            __weak OSMeloNXEngine *weakSelf = self;
            controller.menuChanged = ^(BOOL open) {
                OSMeloNXEngine *strongSelf = weakSelf;
                if (!strongSelf) return;
                for (OSNXPad *pad in strongSelf.pads) {
                    pad.suspended = open;
                    if (open) [pad releaseAll];
                }
                strongSelf->_api.pauseEmulation(open);
            };
            controller.quitRequested = ^{
                OSMeloNXEngine *strongSelf = weakSelf;
                if (strongSelf) strongSelf->_api.stopEmulation();
            };
            [controller loadViewIfNeeded];
            [root presentViewController:controller animated:NO completion:nil];
            [controller.view setNeedsLayout];
            [controller.view layoutIfNeeded];
            self.gameController = controller;
            size = controller.metalView.bounds.size;
            [self attachConnectedPads];
            [self watchControllersAndApp];
            CAMetalLayer *layer = (CAMetalLayer *)controller.metalView.layer;
            layer.drawableSize = CGSizeMake(size.width * layer.contentsScale, size.height * layer.contentsScale);
            self->_api.setNativeWindow((__bridge void *)layer);
            self->_api.setViewSize((int32_t)size.width, (int32_t)size.height);
            self->_exitCallback = ^(NSString *result) {
                OSMeloNXEngine *strongSelf = weakSelf;
                if (strongSelf) strongSelf->_api.stopEmulation();
            };
            self->_firstFrameCallback = ^(NSString *result) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    OSMeloNXEngine *strongSelf = weakSelf;
                    [strongSelf.gameController showStatus:OSNXText(language, @"Home o SELECT+START: menú", @"Home or SELECT+START: menu") sticky:NO];
                });
            };
            self->_api.registerCallback(@"exit-emulation", self->_exitCallback);
            self->_api.registerCallback(@"ran-first-frame", self->_firstFrameCallback);
            [controller showStatus:OSNXText(language, @"Cargando el juego…", @"Loading the game…") sticky:YES];
            presented = YES;
        });
        if (!presented || size.width < 1 || size.height < 1) {
            [self finishSessionWithMessage:OSNXText(language, @"No se pudo crear la pantalla del juego.", @"Could not create the game screen.")
                                completion:completion];
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(YES, @""); });

        NSArray<NSString *> *arguments = [self argumentsForGame:gamePath size:size language:language docked:docked];
        printf("[OmniStation] Argumentos: %s\n", [arguments componentsJoinedByString:@" "].UTF8String);
        const OSNXCoreAPI *api = &self->_api;
        NSThread *thread = [[NSThread alloc] initWithBlock:^{
            int32_t result = OSNXCallWithArguments(arguments, ^int32_t(int32_t argc, char **argv) {
                return api->mainRyujinx(argc, argv);
            });
            printf("[OmniStation] main_ryujinx_sdl terminó con %d\n", result);
            fflush(stdout);
            if (result != 0) {
                NSString *tail = [OSMeloNXEngine logTail];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.gameController showStatus:tail.length ? tail : @"MeloNX se cerró con un error." sticky:YES];
                });
                [NSThread sleepForTimeInterval:3.0];
            }
            [self finishSessionWithMessage:nil completion:nil];
        }];
        thread.name = @"OmniStation MeloNX";
        thread.stackSize = 16 * 1024 * 1024;
        thread.qualityOfService = NSQualityOfServiceUserInteractive;
        [thread start];
    });
}

@end
