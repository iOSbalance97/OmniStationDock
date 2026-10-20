// Núcleo de ARMSX2 integrado en OmniStation Dock (PlayStation 2).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Basado en el puente de ARMSX2 de NeoStation iOS (TarbleFR, GPL-3.0-or-later):
// https://github.com/TarbleFR/neostation-ios — packages/armsx2_internal_bridge.
//
// Orden de cada partida (igual que en NeoStation):
//  1. OmniStation abre un puerto local y lanza su extensión de JIT (otro proceso).
//  2. La extensión engancha StikJIT a OmniStation y avisa por el puerto.
//  3. En iOS 26, una instrucción de prueba (BRK con una clave) comprueba que el depurador
//     responde de verdad; solo entonces se carga el núcleo (dlopen), que al arrancar ya pide
//     memoria ejecutable.
//  4. prepare → request_jit_detach → la extensión se suelta → validate_jit → boot.
#import "OSArmsx2Engine.h"
#import "ARMSX2CoreABI.h"
#import "OSExternalDisplay.h"
#import "OSPerfHUD.h"

#import <AVFoundation/AVFoundation.h>

#import <UIKit/UIKit.h>
#import <GameController/GameController.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <poll.h>
#import <arpa/inet.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <sys/types.h>
#import <sys/sysctl.h>
#import <unistd.h>

// MARK: - Estado del proceso (JIT)

extern int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);
extern void *SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern CFTypeRef SecTaskCopyValueForEntitlement(void *task, CFStringRef entitlement, CFErrorRef *error);

#ifndef CS_OPS_STATUS
#define CS_OPS_STATUS 0
#endif
#ifndef CS_DEBUGGED
#define CS_DEBUGGED 0x10000000
#endif

static NSString *const kOSJitRequestType = @"com.omnistation.dock.jit-request";
static NSTimeInterval const kOSHelperConnectTimeout = 30.0;
// La primera vez puede descargar y montar la imagen de desarrollador.
static NSTimeInterval const kOSAttachTimeout = 600.0;
static NSTimeInterval const kOSDetachTimeout = 120.0;

static BOOL OSHostHasGetTaskAllow(void) {
    void *task = SecTaskCreateFromSelf(NULL);
    if (task == NULL) return NO;
    CFTypeRef value = SecTaskCopyValueForEntitlement(task, CFSTR("get-task-allow"), NULL);
    BOOL allowed = value == kCFBooleanTrue;
    if (value != NULL) CFRelease(value);
    CFRelease((CFTypeRef)task);
    return allowed;
}

static BOOL OSHostIsDebugged(void) {
    uint32_t flags = 0;
    if (csops(getpid(), CS_OPS_STATUS, &flags, sizeof(flags)) != 0) return NO;
    return (flags & CS_DEBUGGED) != 0;
}

static BOOL OSHostHasLiveDebugger(void) {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()};
    struct kinfo_proc info;
    memset(&info, 0, sizeof(info));
    size_t size = sizeof(info);
    return sysctl(mib, 4, &info, &size, NULL, 0) == 0 && size == sizeof(info) &&
        (info.kp_proc.p_flag & P_TRACED) != 0;
}

static BOOL OSRequiresCoreHandshake(void) {
    return NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26;
}

// Instrucción de prueba: el script del depurador avanza el PC, pone clave+1 en x0 y sigue.
// No reserva memoria ni toca el núcleo.
#if defined(__arm64__)
__attribute__((naked, noinline)) static uint64_t OSDebuggerProbe(uint64_t nonce) {
    __asm__("mov x16, #3\n"
            "brk #0xf00d\n"
            "ret");
}
#else
static uint64_t OSDebuggerProbe(uint64_t nonce) { return 0; }
#endif

// MARK: - Sesión con la extensión de JIT

@interface OSJitSession : NSObject
@property (nonatomic, readonly) uint16_t port;
@property (nonatomic, readonly) uint32_t probeNonce;
@property (nonatomic, readonly, copy) NSString *token;
@property (nonatomic, assign) BOOL requiresCoreHandshake;
@property (nonatomic, strong, nullable) id extensionObject;
@property (nonatomic, strong, nullable) id requestIdentifier;
@property (nonatomic, copy, nullable) void (^logHandler)(NSString *message);
- (nullable instancetype)initWithError:(NSString **)error;
- (void)startReader;
- (BOOL)waitUntilConnected:(NSTimeInterval)timeout;
- (BOOL)waitUntilAttached:(NSTimeInterval)timeout;
- (BOOL)confirmCoreLoadReady;
- (BOOL)waitUntilFinished:(NSTimeInterval)timeout;
- (BOOL)connected;
- (BOOL)attached;
- (BOOL)finished;
- (BOOL)success;
- (BOOL)coreLoadReady;
- (BOOL)closed;
- (NSString *)finalMessage;
- (NSString *)lastLog;
- (void)close;
@end

@implementation OSJitSession {
    int _listener;
    int _client;
    NSCondition *_condition;
    BOOL _connected;
    BOOL _attached;
    BOOL _coreLoadReady;
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
    _probeNonce = arc4random_uniform(UINT32_MAX - 1) + 1;
    _condition = [NSCondition new];
    _finalMessage = @"";
    _lastLog = @"";
    _readerQueue = dispatch_queue_create("com.omnistation.dock.jit-reader", DISPATCH_QUEUE_SERIAL);
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
- (BOOL)coreLoadReady { return [self readFlag:&_coreLoadReady]; }
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
    __weak OSJitSession *weakSelf = self;
    dispatch_async(_readerQueue, ^{
        OSJitSession *strongSelf = weakSelf;
        if (strongSelf == nil) return;
        struct pollfd descriptor = {strongSelf->_listener, POLLIN, 0};
        int pollResult = poll(&descriptor, 1, (int)(kOSHelperConnectTimeout * 1000.0));
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
        // Copia solo para poder cortar la lectura al cerrar.
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
                NSLog(@"[OmniStation JIT] %@ %@", event, message);

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
    // Antes de iOS 26 (enganche clásico) basta con que termine bien.
    return (self.attached && !self.closed && !self.finished) ||
        (!self.requiresCoreHandshake && self.connected && self.finished && self.success);
}

- (BOOL)confirmCoreLoadReady {
    if (!self.connected || !self.attached || self.finished || self.closed || !OSHostHasLiveDebugger()) return NO;
    uint64_t response = OSDebuggerProbe(_probeNonce);
    [_condition lock];
    _coreLoadReady = response == (uint64_t)_probeNonce + 1 && !_closed && !_finished;
    BOOL ready = _coreLoadReady;
    [_condition unlock];
    return ready;
}

- (BOOL)waitUntilFinished:(NSTimeInterval)timeout {
    [self waitFor:^BOOL { return self->_finished || self->_closed; } timeout:timeout];
    return self.finished || self.closed;
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

// MARK: - Lanzar la extensión de JIT

static NSString *OSHelperBundleIdentifier(void) {
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

static BOOL OSLaunchHelper(OSJitSession *session, NSData *pairingData, NSString **error) {
    NSString *identifier = OSHelperBundleIdentifier();
    if (identifier.length == 0) {
        if (error) *error = @"Falta la extensión de JIT de OmniStation. Al instalar con SideStore, no quites las extensiones de la app.";
        return NO;
    }
    NSDictionary *request = @{
        @"protocolVersion": @1,
        @"probeNonce": @(session.probeNonce),
        @"targetPID": @(getpid()),
        @"port": @(session.port),
        @"token": session.token,
        @"pairingData": [pairingData base64EncodedStringWithOptions:0],
        @"requiresCoreHandshake": @(session.requiresCoreHandshake),
    };
    NSData *requestData = [NSJSONSerialization dataWithJSONObject:request options:0 error:nil];
    if (requestData == nil) {
        if (error) *error = @"No se pudo preparar la petición de JIT.";
        return NO;
    }
    NSItemProvider *provider = [[NSItemProvider alloc] initWithItem:requestData typeIdentifier:kOSJitRequestType];
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
    __weak OSJitSession *weakSession = session;
    void (^completion)(id) = ^(id requestIdentifier) {
        OSJitSession *strongSession = weakSession;
        if (strongSession == nil) return;
        strongSession.requestIdentifier = requestIdentifier;
        if (strongSession.closed) [strongSession cancelExtensionRequest];
    };
    void (*beginMessage)(id, SEL, NSArray *, id) = (void (*)(id, SEL, NSArray *, id))objc_msgSend;
    beginMessage(extension, beginSelector, @[item], completion);
    return YES;
}

// MARK: - Textos

static NSString *OSText(NSString *language, NSString *spanish, NSString *english) {
    return [language isEqualToString:@"en"] ? english : spanish;
}

static NSString *OSString(const char *text, NSString *fallback) {
    if (text == NULL || text[0] == 0) return fallback;
    return [NSString stringWithUTF8String:text] ?: fallback;
}

// MARK: - Mando táctil

@interface OSStickView : UIView
@property (nonatomic, copy, nullable) void (^valueChanged)(float x, float y);
@property (nonatomic, strong) UIView *knob;
@end

@implementation OSStickView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.30];
        self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.40].CGColor;
        self.layer.borderWidth = 1.0;
        _knob = [[UIView alloc] initWithFrame:CGRectZero];
        _knob.backgroundColor = [UIColor colorWithWhite:1 alpha:0.36];
        _knob.userInteractionEnabled = NO;
        [self addSubview:_knob];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        pan.maximumNumberOfTouches = 1;
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat side = MIN(self.bounds.size.width, self.bounds.size.height);
    self.layer.cornerRadius = side * 0.5;
    CGFloat knobSize = side * 0.42;
    if (CGRectEqualToRect(self.knob.frame, CGRectZero) || fabs(self.knob.bounds.size.width - knobSize) > 0.5) {
        self.knob.bounds = CGRectMake(0, 0, knobSize, knobSize);
        self.knob.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    }
    self.knob.layer.cornerRadius = knobSize * 0.5;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGFloat radius = MAX(1.0, MIN(self.bounds.size.width, self.bounds.size.height) * 0.36);
    CGPoint delta = [pan translationInView:self];
    CGFloat x = delta.x / radius;
    CGFloat y = delta.y / radius;
    CGFloat magnitude = hypot(x, y);
    if (magnitude > 1.0) {
        x /= magnitude;
        y /= magnitude;
    }
    BOOL ended = pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled ||
        pan.state == UIGestureRecognizerStateFailed;
    if (ended) {
        x = 0;
        y = 0;
    }
    self.knob.center = CGPointMake(CGRectGetMidX(self.bounds) + x * radius * 0.58,
                                   CGRectGetMidY(self.bounds) + y * radius * 0.58);
    if (self.valueChanged) self.valueChanged((float)x, (float)y);
}

@end

// MARK: - Pantalla de juego

@interface OSArmsx2GameViewController : UIViewController
@property (nonatomic, assign) const NeoARMSX2API *api;
@property (nonatomic, copy) NSString *language;
@property (nonatomic, assign) BOOL touchAlways;
@property (nonatomic, weak, nullable) UIView *coreView;
@property (nonatomic, assign) BOOL closing;
@property (nonatomic, copy, nullable) void (^menuOpened)(void);
@property (nonatomic, copy, nullable) void (^resumeRequested)(void);
@property (nonatomic, copy, nullable) void (^saveRequested)(uint32_t slot);
@property (nonatomic, copy, nullable) void (^loadRequested)(uint32_t slot);
@property (nonatomic, copy, nullable) void (^quitRequested)(void);
/// HUD de OmniStation (temperatura, RAM, batería). Los FPS los da el HUD propio de ARMSX2.
@property (nonatomic, strong, nullable) OSPerfHUD *hud;
/// Vibración al tocar los botones del mando táctil.
@property (nonatomic, assign) BOOL touchHaptics;
/// Alto/ancho de la imagen del juego (3/4 en 4:3) para centrarla en vertical.
@property (nonatomic, assign) CGFloat imageRatio;
- (void)updateExternalDisplay;
- (void)releaseExternalDisplay;
- (void)showStatus:(NSString *)message;
- (void)updateSaveMask:(uint32_t)mask;
- (void)resetInput;
- (void)openMenu;
- (void)closeMenu;
@end

@implementation OSArmsx2GameViewController {
    UIView *_controlsView;
    UIButton *_menuButton;
    UILabel *_statusLabel;
    UIView *_menuView;
    UIStackView *_menuStack;
    NSArray<UIButton *> *_menuRows;
    NSInteger _menuIndex;
    uint32_t _slot;
    uint32_t _saveMask;
    BOOL _menuVisible;
    float _leftX, _leftY, _rightX, _rightY;
    CADisplayLink *_displayLink;
    // Estado anterior del mando (para detectar pulsaciones).
    BOOL _prevHome, _prevCombo, _prevUp, _prevDown, _prevLeft, _prevRight, _prevA, _prevB;
    NSMutableArray<id> *_observers;
    UIImpactFeedbackGenerator *_haptic;
    UILabel *_tvLabel;
    UIView *_tvHost;
    BOOL _onTV;
    NSTimer *_hudTimer;
}

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        _slot = 1;
        _language = @"es";
        _observers = [NSMutableArray new];
    }
    return self;
}

- (NSString *)t:(NSString *)spanish en:(NSString *)english {
    return OSText(self.language, spanish, english);
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures { return UIRectEdgeAll; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAllButUpsideDown; }

- (UIButton *)padButton:(NSString *)title tag:(NSInteger)tag {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.tag = tag;
    button.backgroundColor = [UIColor colorWithWhite:0 alpha:0.42];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [button setTitleColor:[UIColor colorWithRed:0.4 green:0.9 blue:1.0 alpha:1.0] forState:UIControlStateHighlighted];
    button.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.40].CGColor;
    button.layer.cornerRadius = 19;
    button.exclusiveTouch = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button addTarget:self action:@selector(padDown:) forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(padUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    return button;
}

- (UIView *)pairWithFirst:(NSString *)first firstTag:(NSInteger)firstTag second:(NSString *)second secondTag:(NSInteger)secondTag {
    UIView *pair = [UIView new];
    UIButton *a = [self padButton:first tag:firstTag];
    UIButton *b = [self padButton:second tag:secondTag];
    a.frame = CGRectMake(0, 0, 50, 40);
    b.frame = CGRectMake(58, 0, 50, 40);
    a.layer.cornerRadius = 12;
    b.layer.cornerRadius = 12;
    [pair addSubview:a];
    [pair addSubview:b];
    return pair;
}

- (UIView *)crossOfButtons:(NSArray<NSString *> *)titles tags:(NSArray<NSNumber *> *)tags {
    // Orden: arriba, abajo, izquierda, derecha.
    UIView *pad = [UIView new];
    CGRect frames[4] = {CGRectMake(37, 0, 38, 38), CGRectMake(37, 74, 38, 38), CGRectMake(0, 37, 38, 38), CGRectMake(74, 37, 38, 38)};
    for (NSUInteger index = 0; index < 4; index++) {
        UIButton *button = [self padButton:titles[index] tag:tags[index].integerValue];
        button.frame = frames[index];
        [pad addSubview:button];
    }
    return pad;
}

- (void)loadView {
    UIView *root = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    root.backgroundColor = UIColor.blackColor;
    self.view = root;
    if (self.coreView) {
        self.coreView.frame = root.bounds;
        self.coreView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [root addSubview:self.coreView];
    }

    _controlsView = [[UIView alloc] initWithFrame:root.bounds];
    _controlsView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _controlsView.backgroundColor = UIColor.clearColor;
    _controlsView.multipleTouchEnabled = YES;
    [root addSubview:_controlsView];

    UIView *dpad = [self crossOfButtons:@[@"▲", @"▼", @"◀", @"▶"] tags:@[@0, @1, @2, @3]];
    dpad.tag = 1001;
    UIView *face = [self crossOfButtons:@[@"△", @"✕", @"□", @"○"] tags:@[@7, @4, @6, @5]];
    face.tag = 1002;
    OSStickView *leftStick = [[OSStickView alloc] initWithFrame:CGRectZero];
    leftStick.tag = 1003;
    OSStickView *rightStick = [[OSStickView alloc] initWithFrame:CGRectZero];
    rightStick.tag = 1004;
    UIView *leftShoulders = [self pairWithFirst:@"L1" firstTag:8 second:@"L2" secondTag:10];
    leftShoulders.tag = 1005;
    UIView *rightShoulders = [self pairWithFirst:@"R1" firstTag:9 second:@"R2" secondTag:11];
    rightShoulders.tag = 1006;
    UIButton *start = [self padButton:@"START" tag:12];
    UIButton *select = [self padButton:@"SELECT" tag:13];
    start.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    select.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    start.layer.cornerRadius = 12;
    select.layer.cornerRadius = 12;
    for (UIView *view in @[dpad, face, leftStick, rightStick, leftShoulders, rightShoulders, start, select]) {
        view.multipleTouchEnabled = YES;
        [_controlsView addSubview:view];
    }
    __weak OSArmsx2GameViewController *weakSelf = self;
    leftStick.valueChanged = ^(float x, float y) {
        OSArmsx2GameViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_leftX = x;
        strongSelf->_leftY = y;
        [strongSelf sendSticks];
    };
    rightStick.valueChanged = ^(float x, float y) {
        OSArmsx2GameViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_rightX = x;
        strongSelf->_rightY = y;
        [strongSelf sendSticks];
    };

    _tvLabel = [UILabel new];
    _tvLabel.text = [self t:@"Jugando en la tele" en:@"Playing on the TV"];
    _tvLabel.textColor = [UIColor colorWithWhite:1 alpha:0.55];
    _tvLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _tvLabel.textAlignment = NSTextAlignmentCenter;
    _tvLabel.hidden = YES;
    _tvLabel.userInteractionEnabled = NO;
    [root insertSubview:_tvLabel belowSubview:_controlsView];

    if (self.hud) {
        [root addSubview:self.hud];
        [self.hud refreshWithFPS:-1 frameTime:0 fifo:0];
    }
    if (self.touchHaptics) {
        _haptic = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [_haptic prepare];
    }

    _menuButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _menuButton.tintColor = UIColor.whiteColor;
    _menuButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    _menuButton.layer.cornerRadius = 20;
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

    [self buildMenu];
    [self updateControlsVisibility];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    __weak OSArmsx2GameViewController *weakSelf = self;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    for (NSNotificationName name in @[GCControllerDidConnectNotification, GCControllerDidDisconnectNotification]) {
        id token = [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            [weakSelf updateControlsVisibility];
        }];
        [_observers addObject:token];
    }
    id tv = [center addObserverForName:OSExternalDisplayDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        [weakSelf updateExternalDisplay];
    }];
    [_observers addObject:tv];
    id resign = [center addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        OSArmsx2GameViewController *strongSelf = weakSelf;
        if (strongSelf && !strongSelf.closing && !strongSelf->_menuVisible) [strongSelf openMenu];
    }];
    [_observers addObject:resign];
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
        __weak OSArmsx2GameViewController *weakSelf = self;
        _hudTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
            OSArmsx2GameViewController *strongSelf = weakSelf;
            if (!strongSelf || !strongSelf.hud) return;
            [strongSelf.hud refreshWithFPS:-1 frameTime:0 fifo:0];
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
    for (id token in _observers) [NSNotificationCenter.defaultCenter removeObserver:token];
    [_displayLink invalidate];
    [_hudTimer invalidate];
}

// MARK: Tele (AirPlay o HDMI)

- (void)updateExternalDisplay {
    UIView *coreView = self.coreView;
    if (coreView == nil || !self.isViewLoaded) return;
    OSExternalDisplay *display = OSExternalDisplay.shared;
    BOOL wantTV = display.connected && OSExternalDisplay.enabled && !self.closing;
    if (wantTV && !_onTV) {
        if (_tvHost == nil) {
            _tvHost = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1920, 1080)];
            _tvHost.backgroundColor = UIColor.blackColor;
        }
        coreView.frame = _tvHost.bounds;
        coreView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_tvHost addSubview:coreView];
        if ([display hostView:_tvHost]) {
            _onTV = YES;
            _tvLabel.hidden = NO;
        } else {
            [self returnCoreViewToPhone];
        }
    } else if (!wantTV && _onTV) {
        [self releaseExternalDisplay];
    }
}

- (void)returnCoreViewToPhone {
    UIView *coreView = self.coreView;
    if (coreView == nil) return;
    coreView.frame = self.view.bounds;
    coreView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view insertSubview:coreView atIndex:0];
    [self.view setNeedsLayout];
}

- (void)releaseExternalDisplay {
    if (!_onTV) return;
    _onTV = NO;
    _tvLabel.hidden = YES;
    [self returnCoreViewToPhone];
    [OSExternalDisplay.shared releaseView:_tvHost];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *root = self.view;
    _controlsView.frame = root.bounds;
    UIEdgeInsets safe = root.safeAreaInsets;
    CGFloat w = root.bounds.size.width;
    CGFloat h = root.bounds.size.height;
    BOOL portrait = h > w;
    CGFloat bottomInset = safe.bottom + 14;
    if (!_onTV) {
        if (portrait) {
            // En vertical el núcleo pinta la imagen arriba del todo: la vista se ajusta a la imagen
            // y se coloca hacia el centro de la pantalla, sin pisar los controles táctiles.
            CGFloat ratio = self.imageRatio > 0 ? self.imageRatio : 0.75;
            CGFloat imageHeight = floor(w * ratio);
            CGFloat controlsTop = h - bottomInset - 276;
            CGFloat top = floor(h * 0.42 - imageHeight * 0.5);
            top = MIN(top, controlsTop - imageHeight - 8);
            top = MAX(top, safe.top);
            self.coreView.frame = CGRectMake(0, top, w, imageHeight);
        } else {
            self.coreView.frame = root.bounds;
        }
    }
    UIView *dpad = [_controlsView viewWithTag:1001];
    UIView *face = [_controlsView viewWithTag:1002];
    UIView *leftStick = [_controlsView viewWithTag:1003];
    UIView *rightStick = [_controlsView viewWithTag:1004];
    UIView *leftShoulders = [_controlsView viewWithTag:1005];
    UIView *rightShoulders = [_controlsView viewWithTag:1006];
    UIView *start = [_controlsView viewWithTag:12];
    UIView *select = [_controlsView viewWithTag:13];
    CGFloat bottom = safe.bottom + 14;
    dpad.frame = CGRectMake(safe.left + 14, h - bottom - 112, 112, 112);
    face.frame = CGRectMake(w - safe.right - 126, h - bottom - 112, 112, 112);
    if (portrait) {
        leftStick.frame = CGRectMake(safe.left + 24, h - bottom - 222, 92, 92);
        rightStick.frame = CGRectMake(w - safe.right - 116, h - bottom - 222, 92, 92);
        leftShoulders.frame = CGRectMake(safe.left + 12, h - bottom - 276, 108, 40);
        rightShoulders.frame = CGRectMake(w - safe.right - 120, h - bottom - 276, 108, 40);
    } else {
        leftStick.frame = CGRectMake(safe.left + 138, h - bottom - 96, 88, 88);
        rightStick.frame = CGRectMake(w - safe.right - 226, h - bottom - 96, 88, 88);
        leftShoulders.frame = CGRectMake(safe.left + 12, h - bottom - 162, 108, 40);
        rightShoulders.frame = CGRectMake(w - safe.right - 120, h - bottom - 162, 108, 40);
    }
    CGFloat centerY = h - bottom - 40;
    select.frame = CGRectMake(w * 0.5 - 92, centerY, 76, 34);
    start.frame = CGRectMake(w * 0.5 + 16, centerY, 76, 34);
    _menuButton.frame = CGRectMake(safe.left + 14, safe.top + 12, 40, 40);
    if (self.hud) {
        CGSize hudSize = [self.hud fittingSize];
        self.hud.frame = CGRectMake(safe.left + 62, safe.top + 12, hudSize.width, hudSize.height);
    }
    _tvLabel.frame = CGRectMake(0, h * 0.30, w, 24);
    CGFloat labelWidth = MIN(w * 0.7, 420);
    _statusLabel.frame = CGRectMake((w - labelWidth) * 0.5, safe.top + 14, labelWidth, 54);
    _menuView.frame = root.bounds;
    CGFloat menuWidth = MIN(w - 40, 360);
    CGFloat rowHeight = 46;
    CGFloat menuHeight = rowHeight * (CGFloat)_menuRows.count + 10 * (CGFloat)(_menuRows.count - 1);
    _menuStack.frame = CGRectMake((w - menuWidth) * 0.5, (h - menuHeight) * 0.5, menuWidth, menuHeight);
}

// MARK: Entrada táctil

- (void)padDown:(UIButton *)sender {
    if (_haptic) {
        [_haptic impactOccurred];
        [_haptic prepare];
    }
    if (self.api && self.api->set_button && sender.tag >= 0 && sender.tag < 16) self.api->set_button((uint32_t)sender.tag, 1);
}

- (void)padUp:(UIButton *)sender {
    if (self.api && self.api->set_button && sender.tag >= 0 && sender.tag < 16) self.api->set_button((uint32_t)sender.tag, 0);
}

- (void)sendSticks {
    if (self.api && self.api->set_sticks) self.api->set_sticks(_leftX, _leftY, _rightX, _rightY);
}

- (void)resetInput {
    if (self.api && self.api->set_button) {
        for (uint32_t index = 0; index < 16; index++) self.api->set_button(index, 0);
    }
    _leftX = 0;
    _leftY = 0;
    _rightX = 0;
    _rightY = 0;
    [self sendSticks];
}

/// Con mando conectado, los controles táctiles se ocultan (salvo que se pidan siempre).
- (void)updateControlsVisibility {
    BOOL hasController = GCController.controllers.count > 0;
    BOOL show = self.touchAlways || !hasController;
    _controlsView.hidden = !show;
}

// MARK: Menú de pausa

- (UIButton *)menuRow {
    UIButton *row = [UIButton buttonWithType:UIButtonTypeSystem];
    row.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
    row.layer.cornerRadius = 14;
    row.layer.borderWidth = 0;
    row.layer.borderColor = [UIColor colorWithRed:0.0 green:0.85 blue:1.0 alpha:1.0].CGColor;
    row.tintColor = UIColor.whiteColor;
    row.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    [row setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [row addTarget:self action:@selector(menuRowTapped:) forControlEvents:UIControlEventTouchUpInside];
    return row;
}

- (void)buildMenu {
    _menuView = [[UIView alloc] initWithFrame:self.view.bounds];
    _menuView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.72];
    _menuView.hidden = YES;
    _menuStack = [UIStackView new];
    _menuStack.axis = UILayoutConstraintAxisVertical;
    _menuStack.spacing = 10;
    _menuStack.distribution = UIStackViewDistributionFillEqually;
    NSMutableArray<UIButton *> *rows = [NSMutableArray new];
    for (NSInteger index = 0; index < 6; index++) {
        UIButton *row = [self menuRow];
        row.tag = index;
        [_menuStack addArrangedSubview:row];
        [rows addObject:row];
    }
    _menuRows = rows;
    [_menuView addSubview:_menuStack];
    [self.view addSubview:_menuView];
    [self refreshMenuTitles];
}

- (void)refreshMenuTitles {
    BOOL hasState = (_saveMask & (1u << (_slot - 1))) != 0;
    NSArray<NSString *> *titles = @[
        [self t:@"Continuar" en:@"Resume"],
        [NSString stringWithFormat:[self t:@"◀  Ranura %u  ▶" en:@"◀  Slot %u  ▶"], _slot],
        [self t:@"Guardar estado" en:@"Save state"],
        hasState ? [self t:@"Cargar estado" en:@"Load state"] : [self t:@"Cargar estado (vacía)" en:@"Load state (empty)"],
        self.touchAlways ? [self t:@"Controles táctiles: siempre" en:@"Touch controls: always"]
                         : [self t:@"Controles táctiles: sin mando" en:@"Touch controls: without controller"],
        [self t:@"Salir del juego" en:@"Quit game"],
    ];
    for (NSUInteger index = 0; index < _menuRows.count && index < titles.count; index++) {
        [_menuRows[index] setTitle:titles[index] forState:UIControlStateNormal];
        BOOL selected = (NSInteger)index == _menuIndex && GCController.controllers.count > 0;
        _menuRows[index].layer.borderWidth = selected ? 2.5 : 0;
    }
    UIColor *quitColor = [UIColor colorWithRed:1.0 green:0.55 blue:0.45 alpha:1.0];
    [_menuRows.lastObject setTitleColor:quitColor forState:UIControlStateNormal];
}

- (void)updateSaveMask:(uint32_t)mask {
    _saveMask = mask;
    [self refreshMenuTitles];
}

- (void)openMenu {
    if (_menuVisible || self.closing) return;
    _menuVisible = YES;
    _menuIndex = 0;
    [self resetInput];
    if (self.api && self.api->set_paused) self.api->set_paused(1);
    [self refreshMenuTitles];
    _menuView.hidden = NO;
    [self.view bringSubviewToFront:_menuView];
    if (self.menuOpened) self.menuOpened();
}

- (void)closeMenu {
    if (!_menuVisible) return;
    _menuVisible = NO;
    _menuView.hidden = YES;
    if (self.api && self.api->set_paused) self.api->set_paused(0);
    if (self.resumeRequested) self.resumeRequested();
}

- (void)menuRowTapped:(UIButton *)sender {
    _menuIndex = sender.tag;
    [self activateMenuRow:sender.tag];
}

- (void)changeSlot:(int)step {
    int next = (int)_slot + step;
    if (next < 1) next = 5;
    if (next > 5) next = 1;
    _slot = (uint32_t)next;
    [self refreshMenuTitles];
}

- (void)activateMenuRow:(NSInteger)row {
    switch (row) {
        case 0:
            [self closeMenu];
            break;
        case 1:
            [self changeSlot:1];
            break;
        case 2:
            if (self.saveRequested) self.saveRequested(_slot);
            break;
        case 3:
            if ((_saveMask & (1u << (_slot - 1))) == 0) {
                [self showStatus:[self t:@"Esa ranura está vacía." en:@"That slot is empty."]];
            } else if (self.loadRequested) {
                self.loadRequested(_slot);
            }
            break;
        case 4:
            self.touchAlways = !self.touchAlways;
            [NSUserDefaults.standardUserDefaults setBool:self.touchAlways forKey:@"armsx2CoreTouchAlways"];
            [self updateControlsVisibility];
            [self refreshMenuTitles];
            break;
        default:
            if (self.closing) return;
            self.closing = YES;
            _menuView.hidden = YES;
            _menuVisible = NO;
            [self resetInput];
            if (self.quitRequested) self.quitRequested();
            break;
    }
}

- (void)showStatus:(NSString *)message {
    if (message.length == 0) return;
    _statusLabel.text = message;
    [self.view bringSubviewToFront:_statusLabel];
    [UIView animateWithDuration:0.15 animations:^{ self->_statusLabel.alpha = 1; }];
    __weak OSArmsx2GameViewController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        OSArmsx2GameViewController *strongSelf = weakSelf;
        if (!strongSelf) return;
        [UIView animateWithDuration:0.25 animations:^{ strongSelf->_statusLabel.alpha = 0; }];
    });
}

// MARK: Mando físico (lo juega el propio núcleo; aquí solo se abre y maneja el menú)

- (void)pollController {
    GCController *controller = GCController.current ?: GCController.controllers.firstObject;
    GCExtendedGamepad *pad = controller.extendedGamepad;
    if (pad == nil) return;
    BOOL home = pad.buttonHome != nil && pad.buttonHome.isPressed;
    BOOL combo = pad.buttonMenu.isPressed && pad.buttonOptions != nil && pad.buttonOptions.isPressed;
    float x = pad.dpad.xAxis.value;
    float y = pad.dpad.yAxis.value;
    if (fabsf(x) < 0.5f && fabsf(y) < 0.5f) {
        x = pad.leftThumbstick.xAxis.value;
        y = pad.leftThumbstick.yAxis.value;
    }
    BOOL up = y > 0.5f;
    BOOL down = y < -0.5f;
    BOOL left = x < -0.5f;
    BOOL right = x > 0.5f;
    BOOL a = pad.buttonA.isPressed;
    BOOL b = pad.buttonB.isPressed;

    if (!_menuVisible) {
        // Botón Home o SELECT+START a la vez: menú de pausa.
        if ((home && !_prevHome) || (combo && !_prevCombo)) [self openMenu];
    } else if (!self.closing) {
        NSInteger count = (NSInteger)_menuRows.count;
        if (up && !_prevUp) {
            _menuIndex = (_menuIndex + count - 1) % count;
            [self refreshMenuTitles];
        }
        if (down && !_prevDown) {
            _menuIndex = (_menuIndex + 1) % count;
            [self refreshMenuTitles];
        }
        if (_menuIndex == 1 && left && !_prevLeft) [self changeSlot:-1];
        if (_menuIndex == 1 && right && !_prevRight) [self changeSlot:1];
        if (a && !_prevA) [self activateMenuRow:_menuIndex];
        if (b && !_prevB) [self closeMenu];
    }
    _prevHome = home;
    _prevCombo = combo;
    _prevUp = up;
    _prevDown = down;
    _prevLeft = left;
    _prevRight = right;
    _prevA = a;
    _prevB = b;
}

@end

// MARK: - Motor

@interface OSArmsx2Engine ()
@property (nonatomic, assign) const NeoARMSX2API *api;
@property (nonatomic, assign) void *coreHandle;
@property (nonatomic, strong, nullable) OSJitSession *session;
@property (nonatomic, strong, nullable) OSArmsx2GameViewController *gameController;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, copy) NSString *coreRevision;
@property (nonatomic, copy, nullable) void (^endedHandler)(void);
@property (nonatomic, copy, nullable) NSString *lastLaunchError;
@end

@implementation OSArmsx2Engine {
    dispatch_queue_t _runtimeQueue;
    uint64_t _transaction;
}

+ (OSArmsx2Engine *)shared {
    static OSArmsx2Engine *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [OSArmsx2Engine new]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _runtimeQueue = dispatch_queue_create("com.omnistation.dock.armsx2-runtime", DISPATCH_QUEUE_SERIAL);
        _coreRevision = @"";
    }
    return self;
}

// Dos núcleos posibles: el de NeoStation (ARMSX2Core.framework) y el compilado por
// OmniStation (ARMSX2CoreOmni.framework). Se elige en Ajustes; una vez cargado, no cambia
// hasta volver a abrir la app (un núcleo nunca se descarga).
static NSString *const kOSCoreFlavorKey = @"armsx2CoreFlavor";
static NSString *const kOSFlavorNeoStation = @"neostation";
static NSString *const kOSFlavorOmniStation = @"omnistation";
static NSString *gLoadedCorePath = nil;
static NSString *gLoadedFlavor = nil;

+ (NSString *)corePathForFlavor:(NSString *)flavor {
    NSString *frameworks = NSBundle.mainBundle.privateFrameworksPath ?: @"";
    NSString *folder = [flavor isEqualToString:kOSFlavorOmniStation] ? @"ARMSX2CoreOmni.framework" : @"ARMSX2Core.framework";
    return [frameworks stringByAppendingPathComponent:[folder stringByAppendingPathComponent:@"ARMSX2Core"]];
}

+ (BOOL)neoStationCoreBundled {
    return [NSFileManager.defaultManager isReadableFileAtPath:[self corePathForFlavor:kOSFlavorNeoStation]];
}

+ (BOOL)omniStationCoreBundled {
    return [NSFileManager.defaultManager isReadableFileAtPath:[self corePathForFlavor:kOSFlavorOmniStation]];
}

+ (NSString *)coreFlavor {
    if (gLoadedFlavor.length > 0) return gLoadedFlavor;
    NSString *preferred = [NSUserDefaults.standardUserDefaults stringForKey:kOSCoreFlavorKey];
    BOOL wantsOmni = [preferred isEqualToString:kOSFlavorOmniStation];
    if (wantsOmni && [self omniStationCoreBundled]) return kOSFlavorOmniStation;
    if (!wantsOmni && [self neoStationCoreBundled]) return kOSFlavorNeoStation;
    if ([self neoStationCoreBundled]) return kOSFlavorNeoStation;
    if ([self omniStationCoreBundled]) return kOSFlavorOmniStation;
    return wantsOmni ? kOSFlavorOmniStation : kOSFlavorNeoStation;
}

+ (NSString *)loadedCoreFlavor {
    return gLoadedFlavor ?: @"";
}

+ (NSString *)omniStationCoreDetails {
    NSURL *url = [NSBundle.mainBundle URLForResource:@"ARMSX2CoreOmni" withExtension:@"json"];
    NSData *data = url ? [NSData dataWithContentsOfURL:url] : nil;
    id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![object isKindOfClass:NSDictionary.class]) return @"";
    NSDictionary *info = (NSDictionary *)object;
    NSString *release = [info[@"release"] isKindOfClass:NSString.class] ? info[@"release"] : @"";
    BOOL lto = [info[@"lto"] respondsToSelector:@selector(boolValue)] && [info[@"lto"] boolValue];
    return [NSString stringWithFormat:@"%@%@", release, lto ? @" · LTO" : @""];
}

+ (NSString *)corePath {
    if (gLoadedCorePath.length > 0) return gLoadedCorePath;
    return [self corePathForFlavor:[self coreFlavor]];
}

+ (NSString *)resourcePath {
    NSString *frameworkPath = [[self corePath] stringByDeletingLastPathComponent];
    NSBundle *bundle = [NSBundle bundleWithPath:frameworkPath];
    return bundle.resourcePath ?: frameworkPath;
}

+ (BOOL)coreBundled {
    return [NSFileManager.defaultManager isReadableFileAtPath:[self corePath]];
}

+ (BOOL)helperBundled {
    return OSHelperBundleIdentifier().length > 0;
}

+ (BOOL)supportedHere {
    if (getenv("LC_HOME_PATH") != NULL) return NO;
    return NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 18;
}

/// Carga el núcleo (una vez por proceso; nunca se descarga).
- (BOOL)loadCore:(NSString **)error {
    if (self.api != NULL) return YES;
    NSString *path = [OSArmsx2Engine corePath];
    if (![NSFileManager.defaultManager isReadableFileAtPath:path]) {
        if (error) *error = @"Esta compilación no incluye el núcleo de ARMSX2.";
        return NO;
    }
    dlerror();
    void *handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (handle == NULL) {
        const char *detail = dlerror();
        if (error) *error = [NSString stringWithFormat:@"No se pudo cargar el núcleo: %s", detail ? detail : "desconocido"];
        return NO;
    }
    NeoARMSX2GetAPI getAPI = (NeoARMSX2GetAPI)dlsym(handle, "NeoARMSX2_GetAPI");
    const NeoARMSX2API *api = getAPI ? getAPI(NEO_ARMSX2_ABI_VERSION) : NULL;
    if (api == NULL || api->version != NEO_ARMSX2_ABI_VERSION || api->size < sizeof(NeoARMSX2API) ||
        !api->create_render_view || !api->release_render_view || !api->prepare || !api->request_jit_detach ||
        !api->validate_jit || !api->boot || !api->request_stop || !api->shutdown || !api->set_paused ||
        !api->set_button || !api->set_sticks || !api->has_save_state || !api->save_state || !api->load_state) {
        if (error) *error = @"El núcleo de ARMSX2 no es compatible con esta versión de OmniStation.";
        return NO;
    }
    self.coreHandle = handle;
    self.api = api;
    gLoadedCorePath = [path copy];
    gLoadedFlavor = [path containsString:@"ARMSX2CoreOmni.framework"] ? kOSFlavorOmniStation : kOSFlavorNeoStation;
    self.coreRevision = OSString(api->source_revision, @"");
    return YES;
}

- (void)abortJIT {
    [self.session close];
    self.session = nil;
}

/// Engancha el depurador a OmniStation con la extensión de JIT (bloquea; fuera del hilo principal).
- (BOOL)prepareJITWithPairing:(NSData *)pairingData progress:(void (^)(NSString *))progress error:(NSString **)error {
    if (!OSHostHasGetTaskAllow()) {
        if (error) *error = @"Esta instalación no permite depurar OmniStation (falta get-task-allow). Instálala con SideStore o AltStore.";
        return NO;
    }
    NSString *sessionError = nil;
    OSJitSession *session = [[OSJitSession alloc] initWithError:&sessionError];
    if (session == nil) {
        if (error) *error = sessionError;
        return NO;
    }
    session.requiresCoreHandshake = OSRequiresCoreHandshake();
    // Solo los pasos de preparación (VPN, imagen de desarrollador…), no cada aviso del script.
    session.logHandler = ^(NSString *message) {
        if ([message hasPrefix:@"StikJIT:"] && progress) progress(message);
    };
    self.session = session;
    [session startReader];
    __block BOOL launched = NO;
    self.lastLaunchError = nil;
    // NSExtension se usa desde el hilo principal.
    dispatch_sync(dispatch_get_main_queue(), ^{
        NSString *innerError = nil;
        launched = OSLaunchHelper(session, pairingData, &innerError);
        if (!launched) self.lastLaunchError = innerError;
    });
    if (!launched) {
        NSString *launchError = self.lastLaunchError;
        [self abortJIT];
        if (error) *error = launchError ?: @"No se pudo lanzar la extensión de JIT.";
        return NO;
    }
    if (![session waitUntilConnected:kOSHelperConnectTimeout]) {
        NSString *message = session.finalMessage.length ? session.finalMessage : @"La extensión de JIT no se conectó.";
        [self abortJIT];
        if (error) *error = message;
        return NO;
    }
    if (![session waitUntilAttached:kOSAttachTimeout]) {
        NSString *message = session.finalMessage.length ? session.finalMessage :
            [NSString stringWithFormat:@"StikJIT no terminó de prepararse. Último paso: %@", session.lastLog.length ? session.lastLog : @"—"];
        [self abortJIT];
        if (error) *error = message;
        return NO;
    }
    if (session.finished && !session.success) {
        NSString *message = session.finalMessage.length ? session.finalMessage : @"El JIT no se pudo activar.";
        [self abortJIT];
        if (error) *error = message;
        return NO;
    }
    if (!OSHostIsDebugged()) {
        [self abortJIT];
        if (error) *error = @"StikJIT se soltó sin dejar el JIT activo en OmniStation.";
        return NO;
    }
    return YES;
}

/// Espera a que la extensión se suelte (después de request_jit_detach).
- (BOOL)waitForDetach:(NSString **)error {
    OSJitSession *session = self.session;
    if (session == nil) {
        if (error) *error = @"No hay ninguna sesión de JIT activa.";
        return NO;
    }
    BOOL completed = [session waitUntilFinished:kOSDetachTimeout];
    BOOL proofReady = !session.requiresCoreHandshake || session.coreLoadReady;
    BOOL ok = completed && session.success && proofReady && OSHostIsDebugged();
    if (!ok && error) {
        if (!proofReady) {
            *error = @"La comprobación del depurador no se completó.";
        } else {
            *error = session.finalMessage.length ? session.finalMessage : @"La extensión de JIT no confirmó que se soltaba.";
        }
    }
    [self abortJIT];
    return ok;
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

- (void)finishLaunch:(BOOL)success message:(NSString *)message completion:(void (^)(BOOL, NSString *))completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(success, message ?: @"");
    });
}

/// Algo falló al arrancar: se para el núcleo, se suelta el JIT y se cierra la pantalla.
- (void)failLaunch:(NSString *)message completion:(void (^)(BOOL, NSString *))completion {
    if (self.api) {
        char ignored[256];
        memset(ignored, 0, sizeof(ignored));
        self.api->request_stop();
        self.api->shutdown(30000, ignored, sizeof(ignored));
    }
    [self abortJIT];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self dismissGameWithCompletion:^{
            self.busy = NO;
            completion(NO, message ?: @"No se pudo arrancar el juego.");
        }];
    });
}

- (void)dismissGameWithCompletion:(dispatch_block_t)completion {
    OSArmsx2GameViewController *controller = self.gameController;
    self.gameController = nil;
    [controller resetInput];
    controller.closing = YES;
    [controller releaseExternalDisplay];
    void (^releaseView)(void) = ^{
        if (self.api && self.api->release_render_view) self.api->release_render_view();
        if (completion) completion();
    };
    UIViewController *presenter = controller.presentingViewController;
    if (presenter) {
        [presenter dismissViewControllerAnimated:NO completion:releaseView];
    } else {
        releaseView();
    }
}

- (void)refreshSaveMaskForController:(OSArmsx2GameViewController *)controller {
    dispatch_async(_runtimeQueue, ^{
        if (!self.api) return;
        uint32_t mask = 0;
        for (uint32_t slot = 1; slot <= 5; slot++) {
            if (self.api->has_save_state(slot)) mask |= (1u << (slot - 1));
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.gameController == controller) [controller updateSaveMask:mask];
        });
    });
}

- (void)stopSession {
    OSArmsx2GameViewController *controller = self.gameController;
    dispatch_async(_runtimeQueue, ^{
        BOOL ok = YES;
        NSString *message = @"";
        if (self.api) {
            char error[512];
            memset(error, 0, sizeof(error));
            self.api->request_stop();
            ok = self.api->shutdown(30000, error, sizeof(error)) != 0;
            if (!ok) message = OSString(error, @"ARMSX2 no terminó de cerrarse.");
        }
        [self abortJIT];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!ok) {
                controller.closing = NO;
                [controller showStatus:message];
                return;
            }
            [self dismissGameWithCompletion:^{
                self.busy = NO;
                void (^ended)(void) = self.endedHandler;
                self.endedHandler = nil;
                if (ended) ended();
            }];
        });
    });
}

- (void)configureController:(OSArmsx2GameViewController *)controller {
    __weak OSArmsx2Engine *weakSelf = self;
    __weak OSArmsx2GameViewController *weakController = controller;
    controller.menuOpened = ^{
        OSArmsx2Engine *strongSelf = weakSelf;
        OSArmsx2GameViewController *strongController = weakController;
        if (strongSelf && strongController) [strongSelf refreshSaveMaskForController:strongController];
    };
    controller.saveRequested = ^(uint32_t slot) {
        OSArmsx2Engine *strongSelf = weakSelf;
        if (!strongSelf) return;
        [weakController showStatus:OSText(weakController.language, @"Guardando…", @"Saving…")];
        dispatch_async(strongSelf->_runtimeQueue, ^{
            char error[512];
            memset(error, 0, sizeof(error));
            BOOL ok = strongSelf.api && strongSelf.api->save_state(slot, 60000, error, sizeof(error)) != 0;
            NSString *failure = OSString(error, OSText(weakController.language, @"No se pudo guardar.", @"Could not save."));
            dispatch_async(dispatch_get_main_queue(), ^{
                OSArmsx2GameViewController *strongController = weakController;
                if (!strongController) return;
                NSString *done = [NSString stringWithFormat:OSText(strongController.language, @"Guardado en la ranura %u", @"Saved to slot %u"), slot];
                [strongController showStatus:ok ? done : failure];
                [strongSelf refreshSaveMaskForController:strongController];
            });
        });
    };
    controller.loadRequested = ^(uint32_t slot) {
        OSArmsx2Engine *strongSelf = weakSelf;
        if (!strongSelf) return;
        [weakController showStatus:OSText(weakController.language, @"Cargando…", @"Loading…")];
        dispatch_async(strongSelf->_runtimeQueue, ^{
            char error[512];
            memset(error, 0, sizeof(error));
            BOOL ok = strongSelf.api && strongSelf.api->load_state(slot, 60000, error, sizeof(error)) != 0;
            NSString *failure = OSString(error, OSText(weakController.language, @"No se pudo cargar.", @"Could not load."));
            dispatch_async(dispatch_get_main_queue(), ^{
                OSArmsx2GameViewController *strongController = weakController;
                if (!strongController) return;
                if (ok) {
                    [strongController closeMenu];
                    [strongController showStatus:[NSString stringWithFormat:OSText(strongController.language, @"Ranura %u cargada", @"Slot %u loaded"), slot]];
                } else {
                    [strongController showStatus:failure];
                }
            });
        });
    };
    controller.quitRequested = ^{
        [weakSelf stopSession];
    };
}

- (void)launchGameAtPath:(NSString *)gamePath
                   title:(NSString *)title
           dataDirectory:(NSString *)dataDirectory
           biosDirectory:(NSString *)biosDirectory
             pairingData:(NSData *)pairingData
                language:(NSString *)language
     touchControlsAlways:(BOOL)touchControlsAlways
             hostOptions:(NSDictionary<NSString *, NSString *> *)hostOptions
                progress:(void (^)(NSString *))progress
              completion:(void (^)(BOOL, NSString *))completion
                   ended:(void (^)(void))ended {
    if (self.busy) {
        completion(NO, OSText(language, @"Ya hay una partida abierta.", @"A game is already running."));
        return;
    }
    if (![OSArmsx2Engine supportedHere]) {
        completion(NO, OSText(language, @"El núcleo integrado necesita iOS 18 y la app instalada con SideStore (no en LiveContainer).",
                              @"The built-in core needs iOS 18 and the app installed with SideStore (not in LiveContainer)."));
        return;
    }
    if (gamePath.length > 0 && ![NSFileManager.defaultManager isReadableFileAtPath:gamePath]) {
        completion(NO, OSText(language, @"No se puede leer el archivo del juego.", @"The game file cannot be read."));
        return;
    }
    self.busy = YES;
    self.endedHandler = ended;
    _transaction += 1;
    uint64_t transaction = _transaction;
    void (^report)(NSString *) = ^(NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{ progress(message); });
    };

    dispatch_async(_runtimeQueue, ^{
        report(OSText(language, @"Activando el JIT…", @"Enabling JIT…"));
        NSString *error = nil;
        if (![self prepareJITWithPairing:pairingData progress:report error:&error]) {
            self.busy = NO;
            [self finishLaunch:NO message:error completion:completion];
            return;
        }
        // iOS 26: el depurador debe responder de verdad antes de cargar (o reutilizar) el núcleo.
        if (self.session.requiresCoreHandshake && ![self.session confirmCoreLoadReady]) {
            [self abortJIT];
            self.busy = NO;
            [self finishLaunch:NO message:OSText(language, @"La comprobación del depurador falló. Vuelve a intentarlo.",
                                                    @"The debugger check failed. Try again.") completion:completion];
            return;
        }
        report(OSText(language, @"Cargando el núcleo de ARMSX2…", @"Loading the ARMSX2 core…"));
        if (![self loadCore:&error]) {
            [self abortJIT];
            self.busy = NO;
            [self finishLaunch:NO message:error completion:completion];
            return;
        }

        __block OSArmsx2GameViewController *controller = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{
            UIViewController *root = [self topViewController];
            if (root == nil || root.view.window == nil) return;
            char viewError[512];
            memset(viewError, 0, sizeof(viewError));
            void *raw = self.api->create_render_view(viewError, sizeof(viewError));
            if (raw == NULL) return;
            controller = [OSArmsx2GameViewController new];
            controller.api = self.api;
            controller.language = language;
            controller.touchAlways = touchControlsAlways;
            controller.touchHaptics = [hostOptions[@"touchHaptics"] boolValue];
            NSString *aspect = hostOptions[@"aspectRatio"];
            controller.imageRatio = [aspect isEqualToString:@"16:9"] ? 9.0 / 16.0 : ([aspect isEqualToString:@"10:7"] ? 0.7 : 0.75);
            if ([hostOptions[@"hudSystem"] boolValue]) {
                OSPerfHUD *hud = [[OSPerfHUD alloc] initWithFrame:CGRectZero];
                hud.showMemory = YES;
                hud.showThermal = YES;
                hud.showBattery = [hostOptions[@"hudBattery"] boolValue];
                controller.hud = hud;
            }
            // El sonido del juego no se calla con el interruptor de silencio.
            AVAudioSession *session = AVAudioSession.sharedInstance;
            [session setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:nil];
            [session setActive:YES error:nil];
            controller.coreView = (__bridge UIView *)raw;
            controller.title = title;
            [self configureController:controller];
            [controller loadViewIfNeeded];
            [root presentViewController:controller animated:NO completion:nil];
            self.gameController = controller;
        });
        if (controller == nil) {
            [self failLaunch:OSText(language, @"No se pudo crear la pantalla del juego.", @"Could not create the game screen.") completion:completion];
            return;
        }

        [NSFileManager.defaultManager createDirectoryAtPath:dataDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *resources = [OSArmsx2Engine resourcePath];
        char coreError[2048];
        memset(coreError, 0, sizeof(coreError));
        NeoARMSX2Configuration config;
        memset(&config, 0, sizeof(config));
        config.size = sizeof(config);
        config.transaction = transaction;
        config.data_directory = dataDirectory.fileSystemRepresentation;
        config.resource_directory = resources.fileSystemRepresentation;
        config.bios_directory = biosDirectory.fileSystemRepresentation;
        config.bios_filename = "";
        config.event = NULL;
        config.context = NULL;

        report(OSText(language, @"Preparando ARMSX2…", @"Preparing ARMSX2…"));
        if (!self.api->prepare(&config, 120000, coreError, sizeof(coreError))) {
            [self failLaunch:OSString(coreError, @"ARMSX2 no se pudo preparar.") completion:completion];
            return;
        }
        memset(coreError, 0, sizeof(coreError));
        if (!self.api->request_jit_detach(coreError, sizeof(coreError))) {
            [self failLaunch:OSString(coreError, @"ARMSX2 no pudo soltar el depurador.") completion:completion];
            return;
        }
        if (![self waitForDetach:&error]) {
            [self failLaunch:error completion:completion];
            return;
        }
        memset(coreError, 0, sizeof(coreError));
        if (!self.api->validate_jit(coreError, sizeof(coreError))) {
            [self failLaunch:OSString(coreError, @"El JIT no quedó activo tras soltar el depurador.") completion:completion];
            return;
        }
        uint32_t kind = NEO_ARMSX2_BOOT_BIOS;
        const char *bootPath = "";
        if (gamePath.length > 0) {
            kind = [gamePath.pathExtension.lowercaseString isEqualToString:@"elf"] ? NEO_ARMSX2_BOOT_ELF : NEO_ARMSX2_BOOT_DISC;
            bootPath = gamePath.fileSystemRepresentation;
        }
        report(OSText(language, @"Arrancando…", @"Booting…"));
        memset(coreError, 0, sizeof(coreError));
        if (!self.api->boot(bootPath, kind, 120000, coreError, sizeof(coreError))) {
            [self failLaunch:OSString(coreError, @"ARMSX2 no pudo arrancar el juego.") completion:completion];
            return;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [controller showStatus:OSText(language, @"Home o SELECT+START: menú", @"Home or SELECT+START: menu")];
        });
        [self finishLaunch:YES message:@"" completion:completion];
    });
}

@end
