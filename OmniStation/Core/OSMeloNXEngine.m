// MeloNX integrado en OmniStation Dock (Nintendo Switch).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Anfitrión propio de OmniStation para el runtime de MeloNX 2.7 (AGPL-3.0, https://melonx.org;
// Ryujinx, MIT). Sigue lo que hace la app MeloNX 2.7 (src/MeloNX/MeloNX/Core/Ryujinx.swift,
// RyujinxController.swift y MeloNXApp.swift) antes de jugar:
//  1. Carga el runtime de Frameworks/ (SDL3, MoltenVK, FFmpeg, BreakpointJIT y
//     Ryujinx.Library.dylib), prepara SDL y las variables de entorno y llama a initialize.
//  2. La extensión de JIT de OmniStation engancha StikJIT (script universal en iOS 26).
//  3. init_dualmapping (iOS 26), set_native_window con la CAMetalLayer, el jugador 1
//     (attach_gamepad) y main_ryujinx_sdl con OptionsNative en un hilo propio.
#import "OSMeloNXEngine.h"
#import "OSMeloNXOptions.h"
#import "OSExternalDisplay.h"
#import "OSPerfHUD.h"

#import <AVFoundation/AVFoundation.h>

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
#import <sys/mman.h>
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

/// TXM por archivo (la comprobación clásica de MeloNX).
static BOOL OSNXHasTXMClassic(void) {
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

/// Chip del iPhone según Metal («Apple A17 Pro GPU» → A, 17). Devuelve NO si no se reconoce.
static BOOL OSNXChipInfo(unichar *series, NSInteger *number) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    NSString *name = device.name.uppercaseString ?: @"";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"APPLE\\s+([MA])(\\d+)" options:0 error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:name options:0 range:NSMakeRange(0, name.length)];
    if (match == nil || match.numberOfRanges < 3) return NO;
    *series = [name characterAtIndex:[match rangeAtIndex:1].location];
    *number = [[name substringWithRange:[match rangeAtIndex:2]] integerValue];
    return *number > 0;
}

/// ¿Tiene este iPhone TXM? Igual que MeloNX 2.7: desde iOS 26.6 la comprobación por archivo
/// puede fallar y se decide por el chip (A15+ o M2+; en iOS 27, todo lo posterior al A12).
static BOOL OSNXHasTXM(void) {
    NSOperatingSystemVersion version = NSProcessInfo.processInfo.operatingSystemVersion;
    unichar series = 0;
    NSInteger number = 0;
    if (version.majorVersion >= 27) {
        if (OSNXChipInfo(&series, &number) && series == 'A') return number > 12;
        return YES;
    }
    BOOL atLeast266 = version.majorVersion > 26 || (version.majorVersion == 26 && version.minorVersion >= 6);
    if (atLeast266 && !OSNXHasTXMClassic()) {
        if (!OSNXChipInfo(&series, &number)) return NO;
        return series == 'M' ? number >= 2 : number >= 15;
    }
    return OSNXHasTXMClassic();
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
    bool (*initDualMapping)(void);
    int32_t (*mainRyujinx)(OptionsNative *options);
    void (*setNativeWindow)(void *layer);
    void (*togglePause)(bool pause);
    void (*stopEmulation)(void);
    void (*loadKeyset)(void);
    char *(*installFirmware)(const char *path);
    char *(*installedFirmwareVersion)(void);
    void (*freeFirmwareVersion)(char *text);
    void *(*attachGamepad)(const char *name, void *identifier, int32_t playerIndex, int32_t controllerType);
    void (*detachGamepad)(void *identifier);
    void (*setButtonState)(void *identifier, int32_t button, uint8_t pressed);
    void (*setStickAxis)(void *identifier, int32_t stick, float x, float y);
    void (*touchBegan)(float x, float y, int32_t index);
    void (*touchMoved)(float x, float y, int32_t index);
    void (*touchEnded)(int32_t index);
    void (*setViewSize)(int32_t width, int32_t height);
    void (*setUnboundedFps)(int32_t fps);
    void (*reportMemoryPressure)(uint8_t critical);
    void (*registerCallback)(const char *name, void (*callback)(void *data, void *userData), void *userData);
    void (*unregisterCallback)(const char *name);
} OSNXCoreAPI;

// Estadísticas que manda el núcleo («push_statistics»: FPS, ms por fotograma y FIFO).
typedef struct {
    const uint8_t *ptr;
    int32_t len;
} OSNXCallbackData;

static volatile double gOSNXFps = -1;
static volatile double gOSNXFrameTime = 0;
static volatile double gOSNXFifo = 0;

static void OSNXStatisticsCallback(void *raw, void *userData) {
    const OSNXCallbackData *data = (const OSNXCallbackData *)raw;
    if (data == NULL || data->ptr == NULL || data->len < 25) return;
    double fps = 0, frameTime = 0, fifo = 0;
    memcpy(&fps, data->ptr, sizeof(double));
    memcpy(&frameTime, data->ptr + 8, sizeof(double));
    memcpy(&fifo, data->ptr + 17, sizeof(double));
    gOSNXFps = fps;
    gOSNXFrameTime = frameTime;
    gOSNXFifo = fifo;
}

/// Ajuste de la partida (texto de Swift) como número o sí/no.
static double OSNXNumber(NSDictionary<NSString *, NSString *> *settings, NSString *key, double fallback) {
    NSString *value = settings[key];
    if (![value isKindOfClass:NSString.class] || value.length == 0 || [value isEqualToString:@"auto"]) return fallback;
    return value.doubleValue;
}

static BOOL OSNXFlag(NSDictionary<NSString *, NSString *> *settings, NSString *key, BOOL fallback) {
    NSString *value = settings[key];
    if (![value isKindOfClass:NSString.class] || value.length == 0) return fallback;
    return value.boolValue;
}

// Botones tal como los numera MeloNX (VirtualControllerButton).
typedef NS_ENUM(int32_t, OSNXButton) {
    OSNXButtonA = 0, OSNXButtonB, OSNXButtonX, OSNXButtonY, OSNXButtonBack, OSNXButtonGuide, OSNXButtonStart,
    OSNXButtonLeftStick, OSNXButtonRightStick, OSNXButtonLeftShoulder, OSNXButtonRightShoulder,
    OSNXButtonDPadUp, OSNXButtonDPadDown, OSNXButtonDPadLeft, OSNXButtonDPadRight,
    OSNXButtonLeftTrigger, OSNXButtonRightTrigger, OSNXButtonCount
};

// MARK: - Mando físico → núcleo

/// Jugador 1 de OmniStation. El núcleo ve siempre este mismo mando; el mando físico que esté
/// conectado se engancha y se desengancha de él, así que se puede cambiar de mando (o volver a
/// conectarlo) en mitad de la partida sin salir.
@interface OSNXPad : NSObject
@property (nonatomic, strong, nullable) GCController *controller;
@property (nonatomic, assign) const OSNXCoreAPI *api;
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, assign) BOOL suspended;
- (instancetype)initWithAPI:(const OSNXCoreAPI *)api;
- (void)bindController:(nullable GCController *)controller;
- (void)send:(OSNXButton)button pressed:(BOOL)pressed;
- (void)moveStick:(int32_t)stick x:(float)x y:(float)y;
- (void)releaseAll;
- (void)detach;
@end

@implementation OSNXPad {
    BOOL _physical[OSNXButtonCount];
    float _stick[4];
}

- (instancetype)initWithAPI:(const OSNXCoreAPI *)api {
    self = [super init];
    if (self) {
        _api = api;
        _identifier = [NSString stringWithFormat:@"%llX", (unsigned long long)(uintptr_t)(__bridge void *)self];
        // Jugador 1 (índice 0) como mando Pro (ControllerTypeProController).
        api->attachGamepad("OmniStation Controller", (__bridge void *)self, 0, (int32_t)ControllerTypeProController);
    }
    return self;
}

- (void)send:(OSNXButton)button pressed:(BOOL)pressed {
    if (self.suspended && pressed) return;
    self.api->setButtonState((__bridge void *)self, button, pressed ? 1 : 0);
}

- (void)moveStick:(int32_t)stick x:(float)x y:(float)y {
    if (self.suspended) { x = 0; y = 0; }
    self.api->setStickAxis((__bridge void *)self, stick, x, y);
}

/// El mando se lee entero en cada cambio (manejador del propio mando, no de cada botón):
/// la interfaz de OmniStation usa los de cada botón y así no se pisan al conectar un mando.
- (void)readGamepad:(GCExtendedGamepad *)pad {
    if (pad == nil) return;
    BOOL states[OSNXButtonCount];
    memset(states, 0, sizeof(states));
    states[OSNXButtonA] = pad.buttonA.isPressed;
    states[OSNXButtonB] = pad.buttonB.isPressed;
    states[OSNXButtonX] = pad.buttonX.isPressed;
    states[OSNXButtonY] = pad.buttonY.isPressed;
    states[OSNXButtonBack] = pad.buttonOptions.isPressed;
    states[OSNXButtonStart] = pad.buttonMenu.isPressed;
    states[OSNXButtonLeftStick] = pad.leftThumbstickButton.isPressed;
    states[OSNXButtonRightStick] = pad.rightThumbstickButton.isPressed;
    states[OSNXButtonLeftShoulder] = pad.leftShoulder.isPressed;
    states[OSNXButtonRightShoulder] = pad.rightShoulder.isPressed;
    states[OSNXButtonDPadUp] = pad.dpad.up.isPressed;
    states[OSNXButtonDPadDown] = pad.dpad.down.isPressed;
    states[OSNXButtonDPadLeft] = pad.dpad.left.isPressed;
    states[OSNXButtonDPadRight] = pad.dpad.right.isPressed;
    states[OSNXButtonLeftTrigger] = pad.leftTrigger.isPressed;
    states[OSNXButtonRightTrigger] = pad.rightTrigger.isPressed;
    for (int32_t button = 0; button < OSNXButtonCount; button++) {
        // Home abre el menú de OmniStation: no va al juego.
        if (button == OSNXButtonGuide) continue;
        if (states[button] != _physical[button]) {
            _physical[button] = states[button];
            [self send:(OSNXButton)button pressed:states[button]];
        }
    }
    float lx = pad.leftThumbstick.xAxis.value, ly = pad.leftThumbstick.yAxis.value;
    float rx = pad.rightThumbstick.xAxis.value, ry = pad.rightThumbstick.yAxis.value;
    if (lx != _stick[0] || ly != _stick[1]) {
        _stick[0] = lx;
        _stick[1] = ly;
        [self moveStick:1 x:lx y:ly];
    }
    if (rx != _stick[2] || ry != _stick[3]) {
        _stick[2] = rx;
        _stick[3] = ry;
        [self moveStick:2 x:rx y:ry];
    }
}

- (void)wire:(GCExtendedGamepad *)pad enabled:(BOOL)enabled {
    if (pad == nil) return;
    memset(_physical, 0, sizeof(_physical));
    memset(_stick, 0, sizeof(_stick));
    if (!enabled) {
        pad.valueChangedHandler = nil;
        return;
    }
    __weak OSNXPad *weakSelf = self;
    pad.valueChangedHandler = ^(GCExtendedGamepad *gamepad, GCControllerElement *element) {
        [weakSelf readGamepad:gamepad];
    };
    if (pad.buttonHome != nil) {
        // Home abre el menú de OmniStation, no el de iOS.
        pad.buttonHome.preferredSystemGestureState = GCSystemGestureStateDisabled;
    }
    [self readGamepad:pad];
}

- (void)bindController:(nullable GCController *)controller {
    if (controller == self.controller) return;
    [self wire:self.controller.extendedGamepad enabled:NO];
    [self releaseAll];
    self.controller = controller;
    [self wire:controller.extendedGamepad enabled:YES];
}

- (void)releaseAll {
    for (int32_t button = 0; button < OSNXButtonCount; button++) {
        self.api->setButtonState((__bridge void *)self, button, 0);
    }
    self.api->setStickAxis((__bridge void *)self, 1, 0, 0);
    self.api->setStickAxis((__bridge void *)self, 2, 0, 0);
}

- (void)detach {
    [self wire:self.controller.extendedGamepad enabled:NO];
    self.controller = nil;
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
    CGSize size = self.bounds.size;
    if (size.width < 1 || size.height < 1) return;
    CAMetalLayer *layer = (CAMetalLayer *)self.layer;
    CGSize drawable = CGSizeMake(size.width * layer.contentsScale, size.height * layer.contentsScale);
    if (!CGSizeEqualToSize(layer.drawableSize, drawable)) layer.drawableSize = drawable;
    if (self.api && self.api->setViewSize) {
        self.api->setViewSize((int32_t)size.width, (int32_t)size.height);
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    // En la tele la escala es la de la tele.
    UIScreen *screen = self.window.screen ?: UIScreen.mainScreen;
    CGFloat scale = screen.nativeScale > 0 ? screen.nativeScale : screen.scale;
    if (scale > 0) {
        self.contentScaleFactor = scale;
        self.layer.contentsScale = scale;
    }
    [self setNeedsLayout];
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

// MARK: - Contenedor de la pantalla del juego

/// Ocupa toda la pantalla y centra dentro la vista 16:9 del juego. Con mando táctil, este
/// contenedor va dentro de SwiftUI (debajo del mando de MeloNX), como en la app MeloNX.
@interface OSNXGameContainer : UIView
@property (nonatomic, strong) OSNXMetalView *metalView;
+ (CGRect)gameRectInBounds:(CGRect)bounds;
@end

@implementation OSNXGameContainer

+ (CGRect)gameRectInBounds:(CGRect)bounds {
    CGFloat w = bounds.size.width;
    CGFloat h = bounds.size.height;
    CGFloat targetW = w;
    CGFloat targetH = floor(w * 9.0 / 16.0);
    if (targetH > h) {
        targetH = h;
        targetW = floor(h * 16.0 / 9.0);
    }
    return CGRectMake(floor((w - targetW) * 0.5), floor((h - targetH) * 0.5), targetW, targetH);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.bounds.size.width > 1 && self.bounds.size.height > 1) {
        self.metalView.frame = [OSNXGameContainer gameRectInBounds:self.bounds];
    }
}

@end

// Mando táctil de MeloNX (Melo-Controller). Lo crea OSNXTouchScreenFactory (Swift) por su nombre.
static UIViewController *OSNXMakeTouchScreen(UIView *gameView, void (^button)(NSInteger, BOOL), void (^stick)(BOOL, double, double)) {
    Class factory = NSClassFromString(@"OSNXTouchScreenFactory");
    SEL selector = NSSelectorFromString(@"makeWithGameView:button:stick:");
    if (factory == Nil || ![factory respondsToSelector:selector]) return nil;
    UIViewController *(*make)(id, SEL, UIView *, id, id) = (UIViewController *(*)(id, SEL, UIView *, id, id))objc_msgSend;
    return make(factory, selector, gameView, button, stick);
}

static void OSNXSetTouchVisible(UIViewController *controller, BOOL visible) {
    SEL selector = NSSelectorFromString(@"setTouchVisible:");
    if (controller == nil || ![controller respondsToSelector:selector]) return;
    void (*setVisible)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))objc_msgSend;
    setVisible(controller, selector, visible);
}

// MARK: - Pantalla de juego

@interface OSNXGameViewController : UIViewController
@property (nonatomic, assign) const OSNXCoreAPI *api;
@property (nonatomic, copy) NSString *language;
@property (nonatomic, strong, readonly) OSNXMetalView *metalView;
@property (nonatomic, strong, readonly) OSNXGameContainer *gameContainer;
@property (nonatomic, assign) BOOL closing;
@property (nonatomic, copy, nullable) void (^menuChanged)(BOOL open);
@property (nonatomic, copy, nullable) void (^quitRequested)(void);
/// Mando táctil (si va en la app) y si se enseña siempre o solo sin mando físico.
@property (nonatomic, strong, nullable) UIViewController *touchController;
@property (nonatomic, assign) BOOL touchAlways;
/// HUD de rendimiento (nil si está apagado).
@property (nonatomic, strong, nullable) OSPerfHUD *hud;
- (void)updateTouchVisibility;
/// Pone la pantalla del juego en la tele (si hay y el ajuste lo deja) o la devuelve al iPhone.
- (void)updateExternalDisplay;
/// Devuelve la pantalla al iPhone antes de cerrar.
- (void)releaseExternalDisplay;
- (void)showStatus:(NSString *)message sticky:(BOOL)sticky;
- (void)hideStatus;
- (void)openMenu;
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
    UILabel *_tvLabel;
    OSNXGameContainer *_tvContainer;
    BOOL _onTV;
    NSTimer *_hudTimer;
}

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        _language = @"es";
        _metalView = [[OSNXMetalView alloc] initWithFrame:CGRectMake(0, 0, 16, 9)];
        _gameContainer = [[OSNXGameContainer alloc] initWithFrame:UIScreen.mainScreen.bounds];
        _gameContainer.backgroundColor = UIColor.blackColor;
        _gameContainer.metalView = _metalView;
        [_gameContainer addSubview:_metalView];
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
    UIViewController *touch = self.touchController;
    if (touch != nil) {
        // El contenedor del juego ya va dentro de la vista SwiftUI del mando táctil.
        [self addChildViewController:touch];
        touch.view.frame = root.bounds;
        touch.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [root addSubview:touch.view];
        [touch didMoveToParentViewController:self];
    } else {
        self.gameContainer.frame = root.bounds;
        self.gameContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [root addSubview:self.gameContainer];
    }
    [self updateTouchVisibility];

    _tvLabel = [UILabel new];
    _tvLabel.text = [self t:@"Jugando en la tele" en:@"Playing on the TV"];
    _tvLabel.textColor = [UIColor colorWithWhite:1 alpha:0.55];
    _tvLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _tvLabel.textAlignment = NSTextAlignmentCenter;
    _tvLabel.hidden = YES;
    _tvLabel.userInteractionEnabled = NO;
    [root addSubview:_tvLabel];

    if (self.hud) {
        [root addSubview:self.hud];
        [self.hud refreshWithFPS:-1 frameTime:0 fifo:0];
    }

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
    UIEdgeInsets safe = root.safeAreaInsets;
    _menuButton.frame = CGRectMake(safe.left + 10, safe.top + 8, 36, 36);
    if (self.hud) {
        CGSize hudSize = [self.hud fittingSize];
        self.hud.frame = CGRectMake(safe.left + 54, safe.top + 8, hudSize.width, hudSize.height);
    }
    _tvLabel.frame = CGRectMake(0, h * 0.30, w, 24);
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
        // El menú no necesita más de 60 Hz: el resto del tiempo es para el juego.
        _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(30, 60, 60);
        [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    if (self.hud && _hudTimer == nil) {
        __weak OSNXGameViewController *weakSelf = self;
        _hudTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
            OSNXGameViewController *strongSelf = weakSelf;
            if (!strongSelf || !strongSelf.hud) return;
            [strongSelf.hud refreshWithFPS:gOSNXFps frameTime:gOSNXFrameTime fifo:gOSNXFifo];
            [strongSelf.view setNeedsLayout];
        }];
    }
    UIApplication.sharedApplication.idleTimerDisabled = YES;
    [self updateExternalDisplay];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_displayLink invalidate];
    _displayLink = nil;
    [_hudTimer invalidate];
    _hudTimer = nil;
    UIApplication.sharedApplication.idleTimerDisabled = NO;
}

- (void)dealloc {
    [_displayLink invalidate];
    [_hudTimer invalidate];
}

- (void)updateExternalDisplay {
    OSExternalDisplay *display = OSExternalDisplay.shared;
    BOOL wantTV = display.connected && OSExternalDisplay.enabled && !self.closing;
    if (wantTV && !_onTV) {
        if (_tvContainer == nil) {
            _tvContainer = [[OSNXGameContainer alloc] initWithFrame:CGRectMake(0, 0, 1920, 1080)];
            _tvContainer.backgroundColor = UIColor.blackColor;
        }
        // El contenedor del iPhone deja de colocar la pantalla: ahora la coloca el de la tele.
        self.gameContainer.metalView = nil;
        _tvContainer.metalView = self.metalView;
        [_tvContainer addSubview:self.metalView];
        if ([display hostView:_tvContainer]) {
            _onTV = YES;
            _tvLabel.hidden = NO;
            [_tvContainer setNeedsLayout];
        } else {
            [self returnMetalViewToPhone];
        }
    } else if (!wantTV && _onTV) {
        [self releaseExternalDisplay];
    }
}

- (void)returnMetalViewToPhone {
    _tvContainer.metalView = nil;
    self.gameContainer.metalView = self.metalView;
    [self.gameContainer addSubview:self.metalView];
    [self.gameContainer setNeedsLayout];
}

- (void)releaseExternalDisplay {
    if (!_onTV) return;
    _onTV = NO;
    _tvLabel.hidden = YES;
    [self returnMetalViewToPhone];
    [OSExternalDisplay.shared releaseView:_tvContainer];
}

/// Con mando físico conectado, el táctil se oculta (salvo que se pida siempre).
- (void)updateTouchVisibility {
    BOOL hasController = NO;
    for (GCController *controller in GCController.controllers) {
        if (controller.extendedGamepad != nil) hasController = YES;
    }
    OSNXSetTouchVisible(self.touchController, !hasController || self.touchAlways);
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
    BOOL _menuOpen;
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
    NSString *core = [self.manifest[@"core"] isKindOfClass:NSString.class] ? self.manifest[@"core"] : @"Ryujinx.Library.dylib";
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
    // El núcleo abre algunas librerías por ruta relativa ("BreakpointJIT.framework/BreakpointJIT").
    chdir(frameworks.fileSystemRepresentation);

    // Variables de entorno: las mismas que pone MeloNX 2.7 (initEnvironmentVariables).
    BOOL txm = OSNXHasTXM();
    _dualMapped = NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 19;
    setenv("MVK_CONFIG_MAX_ACTIVE_METAL_COMMAND_BUFFERS_PER_QUEUE", "32", 1);
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    BOOL tier2 = device != nil && device.argumentBuffersSupport >= MTLArgumentBuffersTier2;
    setenv("MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS", tier2 ? "1" : "0", 1);
    setenv("MVK_SUPPORTS_EXT_DYN_STATE", (device != nil && [device supportsFamily:MTLGPUFamilyApple4]) ? "1" : "0", 1);
    setenv("HAS_TXM", (_dualMapped && txm) ? "1" : "0", 1);
    setenv("DUAL_MAPPED_JIT", _dualMapped ? "1" : "0", 1);
    printf("[OmniStation] MeloNX %s · iOS %s · GPU %s · TXM %d · dual-mapped %d\n",
           [OSMeloNXEngine runtimeVersion].UTF8String,
           NSProcessInfo.processInfo.operatingSystemVersionString.UTF8String,
           device.name.UTF8String ?: "?", txm, _dualMapped);

    // Lo que la app MeloNX enlaza al arrancar: se carga antes del núcleo y con RTLD_GLOBAL, para
    // que el núcleo encuentre cada librería ya cargada (SDL3 la pide como @rpath/SDL3.framework/SDL3).
    void *sdl = NULL;
    NSArray<NSString *> *preload = @[
        @"libavutil.framework/libavutil", @"libswresample.framework/libswresample", @"libswscale.framework/libswscale",
        @"libavcodec.framework/libavcodec", @"libavformat.framework/libavformat", @"libavfilter.framework/libavfilter",
        @"libavutil.dylib", @"libavcodec.dylib", @"libMoltenVK.dylib",
        @"SDL3.framework/SDL3", @"BreakpointJIT.framework/BreakpointJIT",
    ];
    for (NSString *relative in preload) {
        NSString *path = [frameworks stringByAppendingPathComponent:relative];
        if (![NSFileManager.defaultManager fileExistsAtPath:path]) continue;
        void *handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
        if (handle == NULL) {
            const char *detail = dlerror();
            printf("[OmniStation] No se pudo cargar %s: %s\n", relative.UTF8String, detail ? detail : "?");
            continue;
        }
        if ([relative hasPrefix:@"SDL3."]) sdl = handle;
    }
    if (sdl == NULL) {
        if (error) *error = @"Falta SDL3 en el runtime de MeloNX.";
        return NO;
    }
    dlerror();
    void *core = dlopen([OSMeloNXEngine corePath].fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
    if (core == NULL) {
        const char *detail = dlerror();
        if (error) *error = [NSString stringWithFormat:@"No se pudo cargar el núcleo de MeloNX: %s", detail ? detail : "desconocido"];
        return NO;
    }
    NSMutableArray<NSString *> *missing = [NSMutableArray new];
    OSNXCoreAPI api;
    memset(&api, 0, sizeof(api));
    api.initialize = (void (*)(void))[self symbol:core name:"initialize" missing:missing];
    api.mainRyujinx = (int32_t (*)(OptionsNative *))[self symbol:core name:"main_ryujinx_sdl" missing:missing];
    api.setNativeWindow = (void (*)(void *))[self symbol:core name:"set_native_window" missing:missing];
    api.stopEmulation = (void (*)(void))[self symbol:core name:"stop_emulation" missing:missing];
    api.installFirmware = (char *(*)(const char *))[self symbol:core name:"install_firmware" missing:missing];
    api.installedFirmwareVersion = (char *(*)(void))[self symbol:core name:"installed_firmware_version" missing:missing];
    api.freeFirmwareVersion = (void (*)(char *))[self symbol:core name:"free_firmware_version" missing:missing];
    api.attachGamepad = (void *(*)(const char *, void *, int32_t, int32_t))[self symbol:core name:"attach_gamepad" missing:missing];
    api.detachGamepad = (void (*)(void *))[self symbol:core name:"detach_gamepad" missing:missing];
    api.setButtonState = (void (*)(void *, int32_t, uint8_t))[self symbol:core name:"set_gamepad_button_state" missing:missing];
    api.setStickAxis = (void (*)(void *, int32_t, float, float))[self symbol:core name:"set_gamepad_stick_axis" missing:missing];
    api.touchBegan = (void (*)(float, float, int32_t))[self symbol:core name:"touch_began" missing:missing];
    api.touchMoved = (void (*)(float, float, int32_t))[self symbol:core name:"touch_moved" missing:missing];
    api.touchEnded = (void (*)(int32_t))[self symbol:core name:"touch_ended" missing:missing];
    api.setViewSize = (void (*)(int32_t, int32_t))[self symbol:core name:"set_view_size" missing:missing];
    if (_dualMapped) {
        api.initDualMapping = (bool (*)(void))[self symbol:core name:"init_dualmapping" missing:missing];
    }
    // Opcionales: si faltan, se sigue sin ellas.
    api.togglePause = (void (*)(bool))dlsym(core, "toggle_pause_emulation");
    api.loadKeyset = (void (*)(void))dlsym(core, "load_keyset");
    api.setUnboundedFps = (void (*)(int32_t))dlsym(core, "set_unbounded_present_target_fps");
    api.reportMemoryPressure = (void (*)(uint8_t))dlsym(core, "report_memory_pressure");
    api.registerCallback = (void (*)(const char *, void (*)(void *, void *), void *))dlsym(core, "RegisterCallback");
    api.unregisterCallback = (void (*)(const char *))dlsym(core, "UnregisterCallback");
    void (*sdlSetMainReady)(void) = (void (*)(void))[self symbol:sdl name:"SDL_SetMainReady" missing:missing];
    void (*sdlSetEventPump)(bool) = (void (*)(bool))[self symbol:sdl name:"SDL_SetiOSEventPump" missing:missing];
    bool (*sdlInit)(uint32_t) = (bool (*)(uint32_t))[self symbol:sdl name:"SDL_Init" missing:missing];
    if (missing.count > 0) {
        if (error) *error = [@"El runtime de MeloNX no es compatible con esta versión de OmniStation. Falta: " stringByAppendingString:[missing componentsJoinedByString:@", "]];
        return NO;
    }
    _api = api;
    // Como MeloNX 2.7 al arrancar (AppDelegate): SDL de eventos y después el núcleo.
    sdlSetMainReady();
    sdlSetEventPump(true);
    sdlInit(0x00004000u);
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
        // MeloNX 2.7: NULL si se instaló; si no, el texto del error.
        if (self->_api.loadKeyset) self->_api.loadKeyset();
        char *raw = self->_api.installFirmware(path.fileSystemRepresentation);
        NSString *failure = nil;
        if (raw != NULL) {
            NSString *text = [NSString stringWithUTF8String:raw] ?: @"";
            self->_api.freeFirmwareVersion(raw);
            failure = [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet].firstObject;
            if (failure.length == 0) failure = @"No se pudo instalar el firmware.";
        }
        NSString *version = @"";
        if (failure == nil) {
            char *installed = self->_api.installedFirmwareVersion();
            if (installed != NULL) {
                version = [NSString stringWithUTF8String:installed] ?: @"";
                self->_api.freeFirmwareVersion(installed);
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(failure == nil, failure ?: (version.length ? version : @"Firmware instalado."));
        });
    });
}

- (void)reloadKeys {
    if (!_loaded || self.busy || _api.loadKeyset == NULL) return;
    dispatch_async(_queue, ^{ self->_api.loadKeyset(); });
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

static char *OSNXCopy(NSString *text) {
    return text.length ? strdup(text.UTF8String) : NULL;
}

/// ¿Puede reservar 4 GB de direcciones? Si no, iOS exige «Extended Virtual Addressing»
/// (la misma prueba que hace MeloNX 2.7 antes de jugar).
static BOOL OSNXNeedsExtendedVirtualAddressing(void) {
    size_t fourGB = (size_t)4 * 1024 * 1024 * 1024;
    void *address = mmap(NULL, fourGB, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
    if (address == MAP_FAILED) return YES;
    munmap(address, fourGB);
    return NO;
}

/// Opciones de la partida. El núcleo libera la estructura y sus textos con free(): todo con
/// calloc/strdup. Los valores por defecto son los de MeloNX 2.7 (Options.swift).
- (OptionsNative *)optionsForGame:(NSString *)path size:(CGSize)size language:(NSString *)language settings:(NSDictionary<NSString *, NSString *> *)settings {
    OptionsNative *options = calloc(1, sizeof(OptionsNative));
    if (options == NULL) return NULL;
    BOOL english = [language isEqualToString:@"en"];
    options->IsExclusiveFullscreen = false;
    options->ExclusiveFullscreenWidth = (int32_t)size.width;
    options->ExclusiveFullscreenHeight = (int32_t)size.height;
    options->DeviceModel = OSNXCopy([OSMeloNXEngine machineName]);
    options->MemoryEnt = [OSMeloNXEngine hasIncreasedMemoryLimit];
    options->DisplayName = OSNXCopy(UIDevice.currentDevice.model);
    options->ControllerType1 = ControllerTypeProController;
    options->ControllerType2 = ControllerTypeProController;
    options->ControllerType3 = ControllerTypeProController;
    options->ControllerType4 = ControllerTypeProController;
    options->ControllerType5 = ControllerTypeProController;
    options->ControllerType6 = ControllerTypeProController;
    options->ControllerType7 = ControllerTypeProController;
    options->ControllerType8 = ControllerTypeProController;
    options->HideCursorMode = HideCursorMode_OnIdle;
    // Ajustes de emulación (Ajustes → MeloNX y los de cada juego). Sin valor: los de MeloNX 2.7.
    int32_t vsync = (int32_t)OSNXNumber(settings, @"vsyncMode", 0);
    options->VSyncMode = vsync;
    options->DisableVSync = vsync == 1;
    options->CustomVSyncInterval = 120;
    options->DisableShaderCache = !OSNXFlag(settings, @"shaderCache", NO);
    options->EnableTextureRecompression = OSNXFlag(settings, @"textureRecompression", YES);
    options->DisableDockedMode = !OSNXFlag(settings, @"docked", NO);
    options->DisableMacroHLE = !OSNXFlag(settings, @"macroHLE", YES);
    options->EnableAsyncShaderCompilation = OSNXFlag(settings, @"asyncShaders", NO);
    options->DisablePTC = !OSNXFlag(settings, @"pptc", YES);
    options->EnableInternetAccess = OSNXFlag(settings, @"internet", NO);
    options->DisableFsIntegrityChecks = !OSNXFlag(settings, @"fsIntegrity", YES);
    options->IgnoreMissingServices = OSNXFlag(settings, @"ignoreMissingServices", NO);
    options->ExpandRAM = OSNXFlag(settings, @"expandRAM", NO);
    SystemLanguage defaultLanguage = english ? SystemLanguage_AmericanEnglish : SystemLanguage_Spanish;
    NativeRegionCode defaultRegion = english ? NativeRegionCode_USA : NativeRegionCode_Europe;
    options->SystemLanguage = (SystemLanguage)(int32_t)OSNXNumber(settings, @"systemLanguage", defaultLanguage);
    options->SystemRegion = (NativeRegionCode)(int32_t)OSNXNumber(settings, @"systemRegion", defaultRegion);
    options->SystemTimeZone = OSNXCopy(NSTimeZone.localTimeZone.name);
    int32_t memoryMode = (int32_t)OSNXNumber(settings, @"memoryManager", MemoryManagerMode_HostMappedUnsafe);
    if (memoryMode < 0 || memoryMode > 2) memoryMode = MemoryManagerMode_HostMappedUnsafe;
    options->MemoryManagerMode = (MemoryManagerMode)memoryMode;
    options->AudioVolume = (float)OSNXNumber(settings, @"audioVolume", 1.0);
    options->MultiplayerLanInterfaceId = OSNXCopy(@"0");
    options->LoggingGraphicsDebugLevel = GraphicsDebugLevel_None;
    options->ResScale = (float)OSNXNumber(settings, @"resScale", 1.0);
    if (options->ResScale <= 0) options->ResScale = 1.0f;
    options->MaxAnisotropy = (float)OSNXNumber(settings, @"maxAnisotropy", -1.0);
    options->AspectRatio = (AspectRatio)(int32_t)OSNXNumber(settings, @"aspectRatio", AspectRatio_Fixed16x9);
    // MeloNX lo fuerza a «On» al arrancar cada juego (RyujinxController.startGame).
    options->BackendThreading = BackendThreading_On;
    options->GraphicsBackend = GraphicsBackend_Vulkan;
    options->PreferredGPUVendor = OSNXCopy(@"");
    options->AntiAliasing = (AntiAliasing)(int32_t)OSNXNumber(settings, @"antiAliasing", AntiAliasing_None);
    options->ScalingFilter = (ScalingFilter)(int32_t)OSNXNumber(settings, @"scalingFilter", ScalingFilter_Bilinear);
    options->ScalingFilterLevel = (int32_t)OSNXNumber(settings, @"scalingFilterLevel", 60);
    options->MetalFxUpscaleFactor = (float)OSNXNumber(settings, @"metalFxUpscaleFactor", 2.0);
    options->EnableHostMemoryBudgetTracking = OSNXFlag(settings, @"memoryBudget", YES);
    options->InputPath = OSNXCopy(path);
    return options;
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

/// Mando físico que debe llevar al jugador 1: el actual de iOS o el primero conectado.
- (nullable GCController *)preferredController {
    GCController *current = GCController.current;
    if (current.extendedGamepad != nil) return current;
    for (GCController *controller in GCController.controllers) {
        if (controller.extendedGamepad != nil) return controller;
    }
    return nil;
}

/// Crea el jugador 1 (una vez por partida) y le engancha el mando conectado.
- (void)preparePlayerPad {
    if (self.pads.count == 0) [self.pads addObject:[[OSNXPad alloc] initWithAPI:&_api]];
    [self.pads.firstObject bindController:[self preferredController]];
}

- (void)watchControllersAndApp {
    __weak OSMeloNXEngine *weakSelf = self;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [_observers addObject:[center addObserverForName:GCControllerDidConnectNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        OSMeloNXEngine *strongSelf = weakSelf;
        OSNXPad *player = strongSelf.pads.firstObject;
        GCController *connected = [note.object isKindOfClass:GCController.class] ? (GCController *)note.object : nil;
        if (!strongSelf || !strongSelf.busy || player == nil || connected.extendedGamepad == nil) return;
        // Sin mando físico (o tras una desconexión), el que se conecta pasa a ser el jugador 1.
        if (player.controller == nil) {
            [player bindController:connected];
            [strongSelf.gameController showStatus:OSNXText(strongSelf.gameController.language, @"Mando conectado", @"Controller connected") sticky:NO];
        }
        [strongSelf.gameController updateTouchVisibility];
    }]];
    [_observers addObject:[center addObserverForName:GCControllerDidDisconnectNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        OSMeloNXEngine *strongSelf = weakSelf;
        OSNXPad *player = strongSelf.pads.firstObject;
        if (!strongSelf || !strongSelf.busy || player == nil) return;
        if (note.object == player.controller) {
            [player bindController:nil];
            GCController *other = [strongSelf preferredController];
            if (other != nil && other != note.object) {
                [player bindController:other];
            } else {
                // Sin mando físico: se sigue con el mando táctil, en el mismo jugador 1.
                [strongSelf.gameController showStatus:OSNXText(strongSelf.gameController.language, @"Mando desconectado: sigue con el táctil o vuelve a conectarlo", @"Controller disconnected: keep playing with touch or reconnect it") sticky:NO];
            }
        }
        [strongSelf.gameController updateTouchVisibility];
    }]];
    [_observers addObject:[center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        OSMeloNXEngine *strongSelf = weakSelf;
        if (strongSelf && strongSelf.busy && strongSelf->_api.togglePause) strongSelf->_api.togglePause(true);
    }]];
    [_observers addObject:[center addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        OSMeloNXEngine *strongSelf = weakSelf;
        if (strongSelf && strongSelf.busy && strongSelf->_api.togglePause && !strongSelf->_menuOpen) strongSelf->_api.togglePause(false);
    }]];
    // Tele conectada o desconectada en mitad de la partida (AirPlay o HDMI).
    [_observers addObject:[center addObserverForName:OSExternalDisplayDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        OSMeloNXEngine *strongSelf = weakSelf;
        if (strongSelf && strongSelf.busy) [strongSelf.gameController updateExternalDisplay];
    }]];
    [_observers addObject:[center addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        OSMeloNXEngine *strongSelf = weakSelf;
        if (strongSelf && strongSelf.busy && strongSelf->_api.reportMemoryPressure) strongSelf->_api.reportMemoryPressure(0);
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
        if (self->_api.unregisterCallback) self->_api.unregisterCallback("push_statistics");
        OSNXGameViewController *controller = self.gameController;
        self.gameController = nil;
        controller.closing = YES;
        [controller releaseExternalDisplay];
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
                settings:(NSDictionary<NSString *, NSString *> *)settings
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
    // Como MeloNX 2.7: si iOS no deja reservar 4 GB, hace falta «Extended Virtual Addressing».
    if (OSNXNeedsExtendedVirtualAddressing()) {
        completion(NO, OSNXText(language, @"Este iPhone necesita el permiso «Extended Virtual Addressing» para MeloNX y OmniStation no lo tiene.",
                                @"This iPhone needs the “Extended Virtual Addressing” entitlement for MeloNX and OmniStation does not have it."));
        return;
    }
    NSString *loadError = nil;
    if (![self loadRuntimeOnMain:&loadError]) {
        completion(NO, loadError ?: @"No se pudo cargar MeloNX.");
        return;
    }
    self.busy = YES;
    self.endedHandler = ended;
    _menuOpen = NO;
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
        if (self->_dualMapped && self->_api.initDualMapping) {
            report(OSNXText(language, @"Preparando la memoria del JIT…", @"Preparing JIT memory…"));
            if (!self->_api.initDualMapping()) {
                [self finishSessionWithMessage:OSNXText(language, @"MeloNX no pudo preparar la memoria del JIT.",
                                                        @"MeloNX could not prepare JIT memory.")
                                    completion:completion];
                return;
            }
        }
        if (self->_api.loadKeyset) self->_api.loadKeyset();

        __block CGSize size = CGSizeZero;
        __block BOOL presented = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{
            UIViewController *root = [self topViewController];
            if (root == nil || root.view.window == nil) return;
            // Audio como MeloNX 2.7 (configureAudioSession).
            AVAudioSession *session = AVAudioSession.sharedInstance;
            [session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:nil];
            [session setPreferredSampleRate:48000 error:nil];
            [session setPreferredIOBufferDuration:0.005 error:nil];
            [session setActive:YES error:nil];

            OSNXGameViewController *controller = [OSNXGameViewController new];
            controller.api = &self->_api;
            controller.language = language;
            controller.title = title;
            controller.touchAlways = [NSUserDefaults.standardUserDefaults boolForKey:@"melonxCoreTouchAlways"];
            // HUD de rendimiento (como el «Performance Overlay» de MeloNX).
            gOSNXFps = -1;
            gOSNXFrameTime = 0;
            gOSNXFifo = 0;
            if (OSNXFlag(settings, @"hud", NO)) {
                OSPerfHUD *hud = [[OSPerfHUD alloc] initWithFrame:CGRectZero];
                hud.showFrameTime = OSNXFlag(settings, @"hudFrameTime", YES);
                hud.showFifo = OSNXFlag(settings, @"hudFifo", NO);
                hud.showMemory = OSNXFlag(settings, @"hudMemory", YES);
                hud.showThermal = OSNXFlag(settings, @"hudThermal", YES);
                hud.showBattery = OSNXFlag(settings, @"hudBattery", NO);
                controller.hud = hud;
                if (self->_api.registerCallback) self->_api.registerCallback("push_statistics", OSNXStatisticsCallback, NULL);
            }
            __weak OSMeloNXEngine *weakSelf = self;
            __weak OSNXGameViewController *weakController = controller;
            // Mando táctil de MeloNX: va al mismo jugador 1 que el mando físico.
            controller.touchController = OSNXMakeTouchScreen(controller.gameContainer, ^(NSInteger button, BOOL pressed) {
                OSMeloNXEngine *strongSelf = weakSelf;
                OSNXPad *player = strongSelf.pads.firstObject;
                if (button == OSNXButtonGuide) {
                    if (pressed) [weakController openMenu];
                    return;
                }
                if (player != nil && button >= 0 && button < OSNXButtonCount) [player send:(OSNXButton)button pressed:pressed];
            }, ^(BOOL right, double x, double y) {
                OSNXPad *player = weakSelf.pads.firstObject;
                [player moveStick:right ? 2 : 1 x:(float)x y:(float)-y];
            });
            controller.menuChanged = ^(BOOL open) {
                OSMeloNXEngine *strongSelf = weakSelf;
                if (!strongSelf) return;
                strongSelf->_menuOpen = open;
                for (OSNXPad *pad in strongSelf.pads) {
                    pad.suspended = open;
                    if (open) [pad releaseAll];
                }
                if (strongSelf->_api.togglePause) strongSelf->_api.togglePause(open);
            };
            controller.quitRequested = ^{
                OSMeloNXEngine *strongSelf = weakSelf;
                if (strongSelf) strongSelf->_api.stopEmulation();
            };
            [self preparePlayerPad];
            [controller loadViewIfNeeded];
            [root presentViewController:controller animated:NO completion:nil];
            self.gameController = controller;
            // Tamaño de la pantalla 16:9 en horizontal (no depende de cuándo coloque SwiftUI la vista).
            CGRect screen = UIScreen.mainScreen.bounds;
            CGRect landscape = CGRectMake(0, 0, MAX(screen.size.width, screen.size.height), MIN(screen.size.width, screen.size.height));
            CGRect game = [OSNXGameContainer gameRectInBounds:landscape];
            controller.metalView.frame = game;
            size = game.size;
            [self watchControllersAndApp];
            CAMetalLayer *layer = (CAMetalLayer *)controller.metalView.layer;
            layer.framebufferOnly = NO;
            layer.drawableSize = CGSizeMake(size.width * layer.contentsScale, size.height * layer.contentsScale);
            self->_api.setNativeWindow((__bridge void *)layer);
            self->_api.setViewSize((int32_t)size.width, (int32_t)size.height);
            if (self->_api.setUnboundedFps) self->_api.setUnboundedFps((int32_t)MAX((NSInteger)1, UIScreen.mainScreen.maximumFramesPerSecond));
            BOOL noController = self.pads.firstObject.controller == nil;
            NSString *loading = noController ? OSNXText(language, @"Cargando el juego… Sin mando: usa los controles táctiles.", @"Loading the game… No controller: use the touch controls.")
                                             : OSNXText(language, @"Cargando el juego…", @"Loading the game…");
            [controller showStatus:loading sticky:YES];
            presented = YES;
        });
        if (!presented || size.width < 1 || size.height < 1) {
            [self finishSessionWithMessage:OSNXText(language, @"No se pudo crear la pantalla del juego.", @"Could not create the game screen.")
                                completion:completion];
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(YES, @""); });
        // El núcleo no avisa del primer fotograma: el aviso de carga se cambia por la ayuda del menú.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.gameController showStatus:OSNXText(language, @"Home o SELECT+START: menú", @"Home or SELECT+START: menu") sticky:NO];
            // Ya hay partida: el núcleo solo acepta el objetivo de fps con el juego en marcha.
            if (self.busy && self->_api.setUnboundedFps) self->_api.setUnboundedFps((int32_t)MAX((NSInteger)1, UIScreen.mainScreen.maximumFramesPerSecond));
        });

        OptionsNative *options = [self optionsForGame:gamePath size:size language:language settings:settings];
        if (options == NULL) {
            [self finishSessionWithMessage:@"Sin memoria para las opciones de MeloNX." completion:nil];
            return;
        }
        printf("[OmniStation] Juego: %s · %dx%d · dock %d · memoria ampliada %d\n", gamePath.UTF8String,
               (int)size.width, (int)size.height, OSNXFlag(settings, @"docked", NO), [OSMeloNXEngine hasIncreasedMemoryLimit]);
        const OSNXCoreAPI *api = &self->_api;
        NSThread *thread = [[NSThread alloc] initWithBlock:^{
            // main_ryujinx_sdl libera las opciones (y sus textos) por su cuenta.
            int32_t result = api->mainRyujinx(options);
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
