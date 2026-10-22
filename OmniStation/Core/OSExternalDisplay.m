// Pantalla externa (AirPlay o HDMI) para los núcleos integrados.
// SPDX-License-Identifier: GPL-3.0-or-later
#import "OSExternalDisplay.h"

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
    _scene = scene;
    [NSNotificationCenter.defaultCenter postNotificationName:OSExternalDisplayDidChangeNotification object:self];
}

- (void)sceneDisconnected:(UIWindowScene *)scene {
    if (_scene != nil && _scene != scene) return;
    _scene = nil;
    // Primero avisa (el núcleo recupera su pantalla en el iPhone) y luego quita la ventana.
    [NSNotificationCenter.defaultCenter postNotificationName:OSExternalDisplayDidChangeNotification object:self];
    _window.hidden = YES;
    _window = nil;
    _hostedView = nil;
}

- (BOOL)hostView:(UIView *)view {
    UIWindowScene *scene = _scene;
    if (scene == nil || !OSExternalDisplay.enabled) return NO;
    if (_window == nil || _window.windowScene != scene) {
        _window.hidden = YES;
        UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
        window.backgroundColor = UIColor.blackColor;
        window.rootViewController = [OSExternalRootController new];
        _window = window;
    }
    _window.frame = scene.coordinateSpace.bounds;
    _window.hidden = NO;
    UIView *root = _window.rootViewController.view;
    root.frame = _window.bounds;
    view.frame = root.bounds;
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [root addSubview:view];
    _hostedView = view;
    [_window layoutIfNeeded];
    [view setNeedsLayout];
    return YES;
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
