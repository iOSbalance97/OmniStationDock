// Pantalla externa (AirPlay o HDMI) para los núcleos integrados.
// SPDX-License-Identifier: GPL-3.0-or-later
#import "OSExternalDisplay.h"
#import <AVFoundation/AVFoundation.h>
#import <GameController/GameController.h>

static const NSInteger kOSTVMenuTag = 770077;

UIView *OSTVMenuContainer(UIView *tvHost, CGSize phoneSize) {
    if (tvHost == nil || phoneSize.width < 1 || phoneSize.height < 1) return nil;
    UIView *container = [tvHost viewWithTag:kOSTVMenuTag];
    if (container == nil) {
        container = [UIView new];
        container.tag = kOSTVMenuTag;
        container.backgroundColor = UIColor.clearColor;
        [tvHost addSubview:container];
    }
    CGSize tv = tvHost.bounds.size;
    CGFloat scale = MIN(tv.width / phoneSize.width, tv.height / phoneSize.height);
    if (!(scale > 0)) scale = 1;
    container.transform = CGAffineTransformIdentity;
    container.bounds = CGRectMake(0, 0, phoneSize.width, phoneSize.height);
    container.transform = CGAffineTransformMakeScale(scale, scale);
    container.center = CGPointMake(tv.width * 0.5, tv.height * 0.5);
    [tvHost bringSubviewToFront:container];
    return container;
}

BOOL OSAnyPadMenuCombo(BOOL *home) {
    BOOL combo = NO, anyHome = NO;
    for (GCController *controller in GCController.controllers) {
        GCExtendedGamepad *pad = controller.extendedGamepad;
        if (pad == nil) continue;
        if (pad.buttonHome != nil && pad.buttonHome.isPressed) anyHome = YES;
        if (pad.buttonMenu.isPressed && pad.buttonOptions != nil && pad.buttonOptions.isPressed) combo = YES;
    }
    if (home) *home = anyHome;
    return combo;
}

NSNotificationName const OSExternalDisplayDidChangeNotification = @"OSExternalDisplayDidChangeNotification";

static NSString *const kOSTVOutputKey = @"tvGameOutput";

/// Pantalla de la tele: negra, sin barras ni gestos.
@interface OSExternalRootController : UIViewController
@end

@implementation OSExternalRootController

- (void)loadView {
    UIView *root = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 1920, 1080)];
    root.backgroundColor = UIColor.blackColor;
    self.view = root;
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }

@end

@interface OSExternalDisplay ()
- (void)sceneConnected:(UIWindowScene *)scene;
- (void)sceneDisconnected:(UIWindowScene *)scene;
@end

@implementation OSExternalDisplay {
    __weak UIWindowScene *_scene;
    UIWindow *_window;
    __weak UIView *_hostedView;
    NSMutableArray<NSString *> *_events;
}

+ (void)noteSceneRequestForRole:(NSString *)role {
    [OSExternalDisplay.shared note:[NSString stringWithFormat:@"iOS pide escena %@", role]];
}

- (void)note:(NSString *)text {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"HH:mm:ss";
    NSString *line = [NSString stringWithFormat:@"%@ %@", [formatter stringFromDate:NSDate.date], text];
    dispatch_block_t block = ^{
        if (self->_events == nil) self->_events = [NSMutableArray array];
        [self->_events addObject:line];
        if (self->_events.count > 12) [self->_events removeObjectAtIndex:0];
    };
    if (NSThread.isMainThread) block(); else dispatch_async(dispatch_get_main_queue(), block);
}

/// Si iOS ya tiene una escena de pantalla externa conectada pero no pasó por el delegado
/// (otra app anfitriona, como LiveContainer), se usa igualmente.
- (void)adoptConnectedScene {
    if (_scene != nil || !NSThread.isMainThread) return;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        if (![scene.session.role isEqualToString:UIWindowSceneSessionRoleExternalDisplayNonInteractive]) continue;
        _scene = (UIWindowScene *)scene;
        [self note:@"escena de la tele adoptada (sin delegado)"];
        return;
    }
}

- (NSString *)diagnosticsDescription {
    NSMutableArray<NSString *> *roles = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        NSString *delegate = scene.delegate ? NSStringFromClass([(NSObject *)scene.delegate class]) : @"sin delegado";
        [roles addObject:[NSString stringWithFormat:@"%@ (%@)", scene.session.role, delegate]];
    }
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    NSUInteger screens = UIScreen.screens.count;
    #pragma clang diagnostic pop
    return [NSString stringWithFormat:@"%@, varias escenas %@, pantallas %lu, escenas [%@], eventos [%@]",
            [self viaAirPlay] ? @"AirPlay" : @"cable (HDMI)",
            UIApplication.sharedApplication.supportsMultipleScenes ? @"sí" : @"NO",
            (unsigned long)screens, [roles componentsJoinedByString:@"; "],
            [(_events ?: @[]) componentsJoinedByString:@"; "]];
}

+ (OSExternalDisplay *)shared {
    static OSExternalDisplay *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [OSExternalDisplay new]; });
    return instance;
}

+ (BOOL)enabled {
    id value = [NSUserDefaults.standardUserDefaults objectForKey:kOSTVOutputKey];
    return value == nil ? YES : [NSUserDefaults.standardUserDefaults boolForKey:kOSTVOutputKey];
}

- (BOOL)connected {
    [self adoptConnectedScene];
    return _scene != nil;
}

- (CGFloat)screenScale {
    UIWindowScene *scene = _scene;
    CGFloat scale = scene.screen.scale;
    return scale > 0 ? scale : 1;
}

- (NSString *)stateDescription {
    UIWindowScene *scene = _scene;
    if (scene == nil) return @"sin escena";
    NSString *activation = @[@"unattached", @"foregroundActive", @"foregroundInactive", @"background"][MAX(0, MIN(3, (NSInteger)scene.activationState + 1))];
    CGRect bounds = scene.coordinateSpace.bounds;
    UIView *root = _window.rootViewController.view;
    return [NSString stringWithFormat:@"escena %@ %.0fx%.0f @%.0fx, ventana %@ %@ %.0fx%.0f, raíz %.0fx%.0f, vista %@",
            activation, bounds.size.width, bounds.size.height, scene.screen.scale,
            _window ? @"sí" : @"no", _window.hidden ? @"oculta" : @"visible", _window.bounds.size.width, _window.bounds.size.height,
            root.bounds.size.width, root.bounds.size.height, _hostedView ? NSStringFromCGRect(_hostedView.frame) : @"-"];
}

- (void)sceneConnected:(UIWindowScene *)scene {
    [self note:[NSString stringWithFormat:@"tele conectada %.0fx%.0f", scene.coordinateSpace.bounds.size.width, scene.coordinateSpace.bounds.size.height]];
    _scene = scene;
    [NSNotificationCenter.defaultCenter postNotificationName:OSExternalDisplayDidChangeNotification object:self];
}

/// La ventana de la tele (se crea si hace falta) y se la da también al delegado de la escena.
- (UIWindow *)windowForScene:(UIWindowScene *)scene {
    if (_window == nil || _window.windowScene != scene) {
        _window.hidden = YES;
        UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
        window.backgroundColor = UIColor.blackColor;
        window.rootViewController = [OSExternalRootController new];
        _window = window;
        if ([scene.delegate isKindOfClass:OSExternalDisplaySceneDelegate.class]) {
            ((OSExternalDisplaySceneDelegate *)scene.delegate).window = window;
        }
    }
    _window.frame = scene.coordinateSpace.bounds;
    _window.hidden = NO;
    UIView *root = _window.rootViewController.view;
    root.frame = _window.bounds;
    return _window;
}

- (void)sceneDisconnected:(UIWindowScene *)scene {
    [self note:@"tele desconectada"];
    if (_scene != nil && _scene != scene) return;
    _scene = nil;
    // Primero avisa (el núcleo recupera su pantalla en el iPhone) y luego quita la ventana.
    [NSNotificationCenter.defaultCenter postNotificationName:OSExternalDisplayDidChangeNotification object:self];
    _window.hidden = YES;
    _window = nil;
    _hostedView = nil;
}

/// ¿La tele va por AirPlay? (iOS no lo dice en la escena; se mira la salida de sonido).
- (BOOL)viaAirPlay {
    for (AVAudioSessionPortDescription *port in AVAudioSession.sharedInstance.currentRoute.outputs) {
        if ([port.portType isEqualToString:AVAudioSessionPortAirPlay]) return YES;
    }
    return NO;
}

- (BOOL)hostingAvailable {
    return self.connected && OSExternalDisplay.enabled && ![self viaAirPlay];
}

- (BOOL)hostView:(UIView *)view {
    UIWindowScene *scene = _scene;
    if (scene == nil || !OSExternalDisplay.enabled) return NO;
    // Por AirPlay, iOS no enseña en la tele las ventanas propias de la app (sale en negro):
    // se deja la duplicación de pantalla, así el juego se ve en la tele igual que en el iPhone.
    if ([self viaAirPlay]) {
        [self note:@"AirPlay: se deja duplicar la pantalla"];
        return NO;
    }
    [self windowForScene:scene];
    UIView *root = _window.rootViewController.view;
    view.frame = root.bounds;
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [root addSubview:view];
    _hostedView = view;
    [self showProbeLabelIn:root];
    [_window layoutIfNeeded];
    [view setNeedsLayout];
    return YES;
}

/// Prueba: un rótulo en la tele durante 5 s. Si se ve, la ventana de la tele funciona y lo que
/// falla es la imagen del núcleo; si no se ve, iOS no está enseñando la ventana.
- (void)showProbeLabelIn:(UIView *)root {
    UILabel *label = [UILabel new];
    label.text = @"OmniStation · TV";
    label.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
    label.textColor = UIColor.cyanColor;
    label.backgroundColor = [UIColor colorWithWhite:0 alpha:0.6];
    label.textAlignment = NSTextAlignmentCenter;
    label.layer.cornerRadius = 14;
    label.layer.masksToBounds = YES;
    label.frame = CGRectMake(40, 40, 420, 64);
    label.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
    [root addSubview:label];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [label removeFromSuperview];
    });
}

- (void)releaseView:(UIView *)view {
    if (_hostedView != nil && _hostedView != view) return;
    if (view.superview == _window.rootViewController.view) [view removeFromSuperview];
    _hostedView = nil;
    _window.hidden = YES;
    _window = nil;
}

@end

@implementation OSExternalDisplaySceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions {
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    [OSExternalDisplay.shared sceneConnected:(UIWindowScene *)scene];
}

- (void)sceneDidDisconnect:(UIScene *)scene {
    if (![scene isKindOfClass:UIWindowScene.class]) return;
    [OSExternalDisplay.shared sceneDisconnected:(UIWindowScene *)scene];
}

@end
