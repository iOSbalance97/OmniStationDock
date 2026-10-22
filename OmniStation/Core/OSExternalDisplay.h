// Pantalla externa (AirPlay o HDMI) para los núcleos integrados de OmniStation Dock.
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Con una tele conectada, iOS crea una escena «pantalla externa» y se la da a
// OSExternalDisplaySceneDelegate. Mientras no haya partida, la escena no tiene ventana y la tele
// sigue duplicando el iPhone. Durante una partida, el núcleo pone en ella su pantalla de juego a
// pantalla completa y el iPhone se queda con los controles.
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Cambia al conectar o desconectar la tele (en el hilo principal).
extern NSNotificationName const OSExternalDisplayDidChangeNotification;

@interface OSExternalDisplay : NSObject

@property (class, nonatomic, readonly) OSExternalDisplay *shared;

/// Ajuste «Juego en la tele» (Ajustes → General). Si está apagado, la tele duplica el iPhone.
@property (class, nonatomic, readonly) BOOL enabled;

/// ¿Hay una tele conectada (AirPlay o HDMI) con su escena lista?
@property (nonatomic, readonly) BOOL connected;

/// Pone `view` a pantalla completa en la tele. NO si no hay tele o el ajuste está apagado.
- (BOOL)hostView:(UIView *)view;

/// Quita la ventana de la tele (la tele vuelve a duplicar el iPhone). El que llama recoloca `view`.
- (void)releaseView:(UIView *)view;

/// Escala de la pantalla de la tele (1 si no hay).
@property (nonatomic, readonly) CGFloat screenScale;

/// Cómo está la escena y la ventana de la tele (para el registro).
@property (nonatomic, readonly, copy) NSString *stateDescription;

@end

/// Lo usa AppDelegate para la escena de la pantalla externa.
@interface OSExternalDisplaySceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong, nullable) UIWindow *window;
@end

NS_ASSUME_NONNULL_END
