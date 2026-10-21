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

/// ¿Tiene OmniStation JIT ahora mismo? (Depurador enganchado; en iOS 26, que siga enganchado.)
@property (class, nonatomic, readonly) BOOL jitActive;

/// Suelta el depurador enganchado con el script universal (al salir de un juego con JIT), para
/// que la próxima vez se pueda volver a enganchar sin que se cuelgue.
+ (void)detachJITDebugger;

/// JIT permanente: un bloque de memoria de JIT preparado una vez (con el depurador) que vale para
/// toda la vida de la app. Lo usan los núcleos que piden su memoria a OmniStation
/// (RETRO_ENVIRONMENT_EXEC_MEM_ALLOC), como el Dolphin de OmniStation.
@property (class, nonatomic, readonly) BOOL persistentJITReady;

/// Prepara el bloque si aún no está y hay depurador enganchado (en iOS 26). YES si ya vale.
+ (BOOL)preparePersistentJIT;

/// Cómo quedó: «ready», «» (no se ha intentado), «no-debugger», «unanswered» (el depurador no
/// contestó), «vm_remap:…», «mprotect:…», «mmap:…», «no-txm».
@property (class, nonatomic, readonly, copy) NSString *persistentJITStatus;

/// Opciones que declara un núcleo, sin abrir ningún juego (para sus ajustes). Cada una: «key»,
/// «title», «info», «category», «categoryTitle», «default» y «values» ([valor, etiqueta]).
/// nil si hay una partida abierta o el núcleo no carga. Llamar en el hilo principal.
- (nullable NSArray<NSDictionary<NSString *, id> *> *)optionsForCore:(NSString *)framework language:(NSString *)language;

/// Hay una partida abierta.
@property (nonatomic, readonly) BOOL busy;

/// Memoria (MB) que llegó a gastar la última partida, contada desde que empezó (0 si no se supo).
@property (atomic, readonly) NSUInteger lastSessionPeakMB;

/// Opciones que declaró el núcleo en la última partida (como `optionsForCore:language:`), para
/// los núcleos que solo las declaran al prepararse. nil si no se supo.
@property (atomic, readonly, copy, nullable) NSArray<NSDictionary<NSString *, id> *> *lastSessionOptions;

/// Opciones del núcleo que se pueden cambiar desde el menú de la partida (se ponen antes de
/// launchGame). Cada una: «key», «title», «group», «values» ([[valor, etiqueta]]) y «value».
@property (nonatomic, copy, nullable) NSArray<NSDictionary<NSString *, id> *> *menuOptions;

/// Si `menuOptions` iba vacío (núcleo que las declara al prepararse), se pide aquí al abrir la
/// partida (en el hilo principal), cuando ya se conocen.
@property (nonatomic, copy, nullable) NSArray<NSDictionary<NSString *, id> *> * _Nullable (^menuOptionsProvider)(void);

/// Se llama (en el hilo principal) cuando se cambia una opción desde el menú de la partida.
@property (nonatomic, copy, nullable) void (^menuOptionChanged)(NSString *key, NSString *value);

/// Arranca `gamePath` con el núcleo `framework`.
/// - layout: botones del mando táctil («nes», «snes», «gb», «gba», «nds», «ps1», «n64», «psp», «dc»).
/// - systemDirectory: BIOS; saveDirectory: partidas (.srm) y estados (.state).
/// - coreOptions: opciones del núcleo (sus claves); las que no estén, las de por defecto del núcleo.
/// - hostOptions: de OmniStation («filter» nearest/linear, «aspect» core/stretch, «hud», «hudThermal»,
///   «hudMemory», «hudBattery», «touchPointer», «touchAlways», «touchHaptics», «map.<físico>» = botón,
///   «gpu» (imagen por OpenGL ES), «jit» (dejar usar el JIT si lo hay), «frameAspect» (proporción
///   del fotograma), «orient.key», «orient.portrait», «orient.landscape» (opción del núcleo que
///   cambia al girar el iPhone)).
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
