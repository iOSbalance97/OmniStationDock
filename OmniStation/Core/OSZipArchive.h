// Zip para Importar/Exportar: leer la lista de un zip y sacar sus archivos a disco poco a poco
// (sin cargarlos enteros en memoria: valen texturas y juegos grandes). Sin cifrar, «guardado» o
// deflate; zip64 no (se avisa para descomprimirlo en Archivos).
// SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OSZipEntry : NSObject
/// Ruta dentro del zip («carpeta/archivo.png»), ya limpia.
@property (nonatomic, readonly, copy) NSString *path;
@property (nonatomic, readonly) uint64_t size;
@end

@interface OSZipArchive : NSObject
/// Los archivos del zip (sin carpetas ni basura de macOS). nil si no se puede leer.
+ (nullable NSArray<OSZipEntry *> *)entriesAtPath:(NSString *)path;
/// Saca una entrada a `destination` (crea las carpetas). NO si falla.
+ (BOOL)extractEntry:(OSZipEntry *)entry fromPath:(NSString *)path toFile:(NSString *)destination;
/// Saca todo en `folder`, quitando delante `stripPrefix` (p. ej. «SLUS-20312/») si lo tiene.
/// Devuelve cuántos archivos salieron (-1 si el zip no se puede leer).
+ (NSInteger)extractAllFromPath:(NSString *)path toFolder:(NSString *)folder stripPrefix:(nullable NSString *)stripPrefix;
@end

NS_ASSUME_NONNULL_END
