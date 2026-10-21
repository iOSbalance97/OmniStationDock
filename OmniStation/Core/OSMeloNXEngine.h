// MeloNX integrado en OmniStation Dock (Nintendo Switch).
// SPDX-License-Identifier: GPL-3.0-or-later
//
// El runtime de MeloNX (núcleo Ryujinx compilado, MoltenVK, SDL2, FFmpeg y sus ayudantes) se
// saca en el workflow de la IPA oficial de MeloNX (AGPL-3.0) y va en Frameworks/. OmniStation
// lo carga con dlopen y lo maneja con las mismas funciones en C que usa la app MeloNX.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OSMeloNXEngine : NSObject

@property (class, nonatomic, readonly) OSMeloNXEngine *shared;

/// ¿Va el runtime de MeloNX dentro de esta compilación?
@property (class, nonatomic, readonly) BOOL runtimeBundled;

/// Versión de MeloNX de la que sale el runtime (vacía si no va).
@property (class, nonatomic, readonly, copy) NSString *runtimeVersion;

/// ¿Puede correr en este iPhone? (iOS 18 o posterior y fuera de LiveContainer.)
@property (class, nonatomic, readonly) BOOL supportedHere;

/// ¿Va la extensión de JIT dentro de la app?
@property (class, nonatomic, readonly) BOOL helperBundled;

/// ¿Tiene OmniStation el permiso «Increased Memory Limit»?
@property (class, nonatomic, readonly) BOOL hasIncreasedMemoryLimit;

/// Memoria que puede usar todavía la app, en bytes (0 si no se sabe).
@property (class, nonatomic, readonly) unsigned long long availableMemory;

/// Carpeta de claves de Ryujinx (Documentos/system) y si ya está prod.keys.
@property (class, nonatomic, readonly, copy) NSString *keysDirectory;
@property (class, nonatomic, readonly) BOOL keysInstalled;

/// Registro de la última partida (Documentos/MeloNX/Registro.txt).
@property (class, nonatomic, readonly, copy) NSString *logPath;

/// Hay una partida abierta o arrancando.
@property (nonatomic, readonly) BOOL busy;

/// Instala el firmware (zip, xci o carpeta). `completion` llega en el hilo principal.
- (void)installFirmwareAtPath:(NSString *)path
                   completion:(void (^)(BOOL success, NSString *message))completion;

/// Vuelve a leer las claves (después de importarlas) si MeloNX ya está cargado.
- (void)reloadKeys;

/// Versión de firmware instalada (vacía si no hay). `completion` en el hilo principal.
- (void)readFirmwareVersion:(void (^)(NSString *version))completion;

/// DLC que hay en un archivo (.nsp) para el juego `titleID`, como los lee MeloNX al añadirlo:
/// cada elemento lleva «path» (dentro del archivo, «/….nca») y «titleId» (número). Necesita las claves.
/// En el hilo principal: los elementos, o nil y el motivo.
- (void)dlcContentsAtPath:(NSString *)path
                  titleID:(NSString *)titleID
               completion:(void (^)(NSArray<NSDictionary<NSString *, id> *> *_Nullable items, NSString *_Nullable error))completion;

/// Title ID y título de un juego tal como los ve la app MeloNX («titleId» y «titleName»), leídos
/// del archivo con este mismo núcleo: con ellos su enlace abre el juego sin escribir el nombre.
/// Necesita las claves. Síncrono: llamar fuera del hilo principal. nil si no se pudo.
- (nullable NSDictionary<NSString *, NSString *> *)identifyGameAtPath:(NSString *)path;

/// JIT para OmniStation con la extensión (para los núcleos libretro): engancha el depurador con
/// el script universal de StikDebug y lo deja enganchado hasta `releaseSharedJIT`.
/// `completion` llega en el hilo principal.
- (void)prepareSharedJITWithPairing:(NSData *)pairingData
                         completion:(void (^)(BOOL success, NSString *message))completion;

/// Suelta el depurador enganchado con `prepareSharedJITWithPairing:completion:`.
- (void)releaseSharedJIT;

/// Arranca un juego a pantalla completa. `settings`: ajustes de emulación de la partida (texto,
/// ver EmulatorConfig.swift). `progress` y `completion` llegan en el hilo principal; `ended`, al
/// cerrar la partida.
- (void)launchGameAtPath:(NSString *)gamePath
                   title:(NSString *)title
             pairingData:(NSData *)pairingData
                language:(NSString *)language
                settings:(NSDictionary<NSString *, NSString *> *)settings
                progress:(void (^)(NSString *message))progress
              completion:(void (^)(BOOL success, NSString *message))completion
                   ended:(void (^)(void))ended;

@end

NS_ASSUME_NONNULL_END
