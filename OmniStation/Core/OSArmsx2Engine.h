// Núcleo de ARMSX2 integrado en OmniStation Dock (PlayStation 2).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// El núcleo (ARMSX2Core.framework) se carga con dlopen solo después de que la extensión de JIT
// de OmniStation haya enganchado el depurador. Su frontera es la interfaz en C de
// ARMSX2CoreABI.h (versión 6), la misma que usa NeoStation iOS.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OSArmsx2Engine : NSObject

@property (class, nonatomic, readonly) OSArmsx2Engine *shared;

/// ¿Va el núcleo dentro de esta compilación?
@property (class, nonatomic, readonly) BOOL coreBundled;

/// ¿Va cada versión del núcleo? NeoStation (ARMSX2Core.framework) u OmniStation (ARMSX2CoreOmni.framework).
@property (class, nonatomic, readonly) BOOL neoStationCoreBundled;
@property (class, nonatomic, readonly) BOOL omniStationCoreBundled;

/// Versión que se usa: «neostation» u «omnistation» (la elegida en Ajustes si va en la app).
@property (class, nonatomic, readonly, copy) NSString *coreFlavor;

/// Versión ya cargada en este proceso (vacía si aún no se ha cargado ninguna).
@property (class, nonatomic, readonly, copy) NSString *loadedCoreFlavor;

/// Datos del núcleo de OmniStation (versión de ARMSX2 y si lleva LTO), o vacío.
@property (class, nonatomic, readonly, copy) NSString *omniStationCoreDetails;

/// ¿Puede correr en este iPhone? (iOS 18 o posterior y fuera de LiveContainer).
@property (class, nonatomic, readonly) BOOL supportedHere;

/// ¿Va la extensión de JIT dentro de la app? (SideStore puede quitarla al instalar.)
@property (class, nonatomic, readonly) BOOL helperBundled;

/// ¿La próxima partida puede ir con el JIT permanente? (Bloque preparado y con sitio para ARMSX2:
/// sin extensión, sin VPN y sin depurador en cada partida, también en LiveContainer.)
@property (class, nonatomic, readonly) BOOL permanentJITUsable;

/// La partida abierta (o la última) usa el JIT permanente.
@property (nonatomic, readonly) BOOL usingPermanentJIT;

/// Hay una partida abierta o arrancando.
@property (nonatomic, readonly) BOOL busy;

/// Revisión de ARMSX2 del núcleo (vacía hasta que se carga).
@property (nonatomic, readonly, copy) NSString *coreRevision;

/// Arranca un juego (o la BIOS si `gamePath` es nil) a pantalla completa. Los ajustes de
/// emulación ya están en Datos/inis/PCSX2.ini; `hostOptions` son los de OmniStation (HUD propio,
/// vibración del mando táctil).
/// `progress` y `completion` llegan en el hilo principal; `ended`, al cerrar la partida.
- (void)launchGameAtPath:(nullable NSString *)gamePath
                   title:(NSString *)title
           dataDirectory:(NSString *)dataDirectory
           biosDirectory:(NSString *)biosDirectory
             pairingData:(NSData *)pairingData
                language:(NSString *)language
     touchControlsAlways:(BOOL)touchControlsAlways
             hostOptions:(NSDictionary<NSString *, NSString *> *)hostOptions
                progress:(void (^)(NSString *message))progress
              completion:(void (^)(BOOL success, NSString *message))completion
                   ended:(void (^)(void))ended;

@end

NS_ASSUME_NONNULL_END
