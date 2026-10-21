// Motor libretro de OmniStation Dock: carga un núcleo libretro (los de ManicEMU, en
// Frameworks/<nombre>.libretro.framework) y lo juega con su pantalla, sonido, mando físico y táctil,
// partidas, estados, HUD y salida a la tele, igual que los núcleos integrados de ARMSX2 y MeloNX.
// SPDX-License-Identifier: GPL-3.0-or-later
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OSLibretroEngine : NSObject

@property (class, nonatomic, readonly) OSLibretroEngine *shared;

/// ¿Trae esta compilación el núcleo `framework` («snes9x.libretro.framework»)?
+ (BOOL)coreAvailable:(NSString *)framework;

/// Hay una partida abierta.
@property (nonatomic, readonly) BOOL busy;

/// Arranca `gamePath` con el núcleo `framework`.
/// - layout: botones del mando táctil («nes», «snes», «gb», «gba», «nds»).
/// - systemDirectory: BIOS; saveDirectory: partidas (.srm) y estados (.state).
/// - coreOptions: opciones del núcleo (sus claves); las que no estén, las de por defecto del núcleo.
/// - hostOptions: de OmniStation («filter» nearest/linear, «aspect» core/stretch, «hud», «hudThermal»,
///   «hudMemory», «hudBattery», «touchPointer», «touchAlways», «touchHaptics», «map.<físico>» = botón).
/// `completion` se llama al abrir la pantalla (o si falla) y `ended` al salir del juego.
- (void)launchGameAtPath:(NSString *)gamePath
                   title:(NSString *)title
               framework:(NSString *)framework
                  layout:(NSString *)layout
         systemDirectory:(NSString *)systemDirectory
           saveDirectory:(NSString *)saveDirectory
             coreOptions:(NSDictionary<NSString *, NSString *> *)coreOptions
             hostOptions:(NSDictionary<NSString *, NSString *> *)hostOptions
                language:(NSString *)language
              completion:(void (^)(BOOL success, NSString *message))completion
                   ended:(void (^)(void))ended;

@end

NS_ASSUME_NONNULL_END
