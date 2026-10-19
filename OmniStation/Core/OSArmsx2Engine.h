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

/// ¿Puede correr en este iPhone? (iOS 18 o posterior y fuera de LiveContainer).
@property (class, nonatomic, readonly) BOOL supportedHere;

/// ¿Va la extensión de JIT dentro de la app? (SideStore puede quitarla al instalar.)
@property (class, nonatomic, readonly) BOOL helperBundled;

/// Hay una partida abierta o arrancando.
@property (nonatomic, readonly) BOOL busy;

/// Revisión de ARMSX2 del núcleo (vacía hasta que se carga).
@property (nonatomic, readonly, copy) NSString *coreRevision;

/// Arranca un juego (o la BIOS si `gamePath` es nil) a pantalla completa.
/// `progress` y `completion` llegan en el hilo principal; `ended`, al cerrar la partida.
- (void)launchGameAtPath:(nullable NSString *)gamePath
                   title:(NSString *)title
           dataDirectory:(NSString *)dataDirectory
           biosDirectory:(NSString *)biosDirectory
             pairingData:(NSData *)pairingData
                language:(NSString *)language
     touchControlsAlways:(BOOL)touchControlsAlways
                progress:(void (^)(NSString *message))progress
              completion:(void (^)(BOOL success, NSString *message))completion
                   ended:(void (^)(void))ended;

@end

NS_ASSUME_NONNULL_END
