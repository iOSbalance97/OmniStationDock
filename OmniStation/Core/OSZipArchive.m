// SPDX-License-Identifier: GPL-3.0-or-later
#import "OSZipArchive.h"
#import <zlib.h>

static uint16_t OSZU16(const uint8_t *p) { return (uint16_t)(p[0] | (p[1] << 8)); }
static uint32_t OSZU32(const uint8_t *p) { return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }
static uint64_t OSZU64(const uint8_t *p) { return (uint64_t)OSZU32(p) | ((uint64_t)OSZU32(p + 4) << 32); }

@interface OSZipEntry ()
@property (nonatomic, copy) NSString *path;
@property (nonatomic) uint64_t size;
@property (nonatomic) uint64_t compressed;
@property (nonatomic) uint64_t localOffset;
@property (nonatomic) uint16_t method;
@end

@implementation OSZipEntry
@end

@implementation OSZipArchive

+ (nullable NSData *)mappedDataAtPath:(NSString *)path {
    return [NSData dataWithContentsOfFile:path options:NSDataReadingMappedAlways error:nil];
}

+ (nullable NSArray<OSZipEntry *> *)entriesAtPath:(NSString *)path {
    NSData *archive = [self mappedDataAtPath:path];
    if (archive == nil) return nil;
    return [self entriesInData:archive];
}

+ (nullable NSArray<OSZipEntry *> *)entriesInData:(NSData *)archive {
    const uint8_t *bytes = archive.bytes;
    uint64_t length = archive.length;
    if (length < 22) return nil;
    // Fin del directorio central (con un comentario de hasta 64 KB detrás).
    uint64_t end = 0;
    BOOL found = NO;
    uint64_t lowest = length > 22 + 65535 ? length - 22 - 65535 : 0;
    for (uint64_t at = length - 22; ; at--) {
        if (OSZU32(bytes + at) == 0x06054b50) { end = at; found = YES; break; }
        if (at == lowest) break;
    }
    if (!found) return nil;
    uint64_t entries = OSZU16(bytes + end + 10);
    uint64_t directory = OSZU32(bytes + end + 16);
    // Zip64: el localizador va justo antes.
    if ((entries == 0xFFFF || directory == 0xFFFFFFFF) && end >= 20 && OSZU32(bytes + end - 20) == 0x07064b50) {
        uint64_t record = OSZU64(bytes + end - 20 + 8);
        if (record + 56 > length || OSZU32(bytes + record) != 0x06064b50) return nil;
        entries = OSZU64(bytes + record + 32);
        directory = OSZU64(bytes + record + 48);
    }
    if (directory >= length) return nil;
    NSMutableArray<OSZipEntry *> *list = [NSMutableArray new];
    uint64_t at = directory;
    for (uint64_t index = 0; index < entries; index++) {
        if (at + 46 > length || OSZU32(bytes + at) != 0x02014b50) return nil;
        uint16_t flags = OSZU16(bytes + at + 8);
        uint16_t method = OSZU16(bytes + at + 10);
        uint64_t compressed = OSZU32(bytes + at + 20);
        uint64_t uncompressed = OSZU32(bytes + at + 24);
        uint16_t nameLength = OSZU16(bytes + at + 28);
        uint16_t extraLength = OSZU16(bytes + at + 30);
        uint16_t commentLength = OSZU16(bytes + at + 32);
        uint64_t local = OSZU32(bytes + at + 42);
        if (at + 46 + nameLength + extraLength > length) return nil;
        NSString *name = [[NSString alloc] initWithBytes:bytes + at + 46 length:nameLength encoding:NSUTF8StringEncoding];
        if (name == nil) name = [[NSString alloc] initWithBytes:bytes + at + 46 length:nameLength encoding:NSISOLatin1StringEncoding];
        // Zip64: los tamaños y el desplazamiento grandes van en el campo extra 0x0001.
        const uint8_t *extra = bytes + at + 46 + nameLength;
        uint32_t cursor = 0;
        while (cursor + 4 <= extraLength) {
            uint16_t tag = OSZU16(extra + cursor);
            uint16_t size = OSZU16(extra + cursor + 2);
            if (cursor + 4 + size > extraLength) break;
            if (tag == 0x0001) {
                const uint8_t *field = extra + cursor + 4;
                uint32_t used = 0;
                if (uncompressed == 0xFFFFFFFF && used + 8 <= size) { uncompressed = OSZU64(field + used); used += 8; }
                if (compressed == 0xFFFFFFFF && used + 8 <= size) { compressed = OSZU64(field + used); used += 8; }
                if (local == 0xFFFFFFFF && used + 8 <= size) { local = OSZU64(field + used); used += 8; }
            }
            cursor += 4 + size;
        }
        at += 46 + (uint64_t)nameLength + extraLength + commentLength;
        if (name == nil || [name hasSuffix:@"/"] || [name hasPrefix:@"__MACOSX/"] || [name.lastPathComponent hasPrefix:@"._"] ||
            [name.lastPathComponent isEqualToString:@".DS_Store"]) continue;
        if ((flags & 1) != 0) continue; // cifrado: no se puede
        if (method != 0 && method != 8) continue;
        NSString *clean = [name stringByReplacingOccurrencesOfString:@"\\" withString:@"/"].stringByStandardizingPath;
        if (clean.length == 0 || [clean hasPrefix:@"/"] || [clean hasPrefix:@".."] || [clean containsString:@"/../"]) continue;
        OSZipEntry *entry = [OSZipEntry new];
        entry.path = clean;
        entry.size = uncompressed;
        entry.compressed = compressed;
        entry.localOffset = local;
        entry.method = method;
        [list addObject:entry];
    }
    return list;
}

+ (BOOL)extractEntry:(OSZipEntry *)entry fromPath:(NSString *)path toFile:(NSString *)destination {
    NSData *archive = [self mappedDataAtPath:path];
    if (archive == nil) return NO;
    return [self extractEntry:entry fromData:archive toFile:destination];
}

+ (BOOL)extractEntry:(OSZipEntry *)entry fromData:(NSData *)archive toFile:(NSString *)destination {
    const uint8_t *bytes = archive.bytes;
    uint64_t length = archive.length;
    uint64_t local = entry.localOffset;
    if (local + 30 > length || OSZU32(bytes + local) != 0x04034b50) return NO;
    uint64_t start = local + 30 + OSZU16(bytes + local + 26) + OSZU16(bytes + local + 28);
    if (start + entry.compressed > length) return NO;
    [NSFileManager.defaultManager createDirectoryAtPath:destination.stringByDeletingLastPathComponent
                            withIntermediateDirectories:YES attributes:nil error:nil];
    FILE *file = fopen(destination.fileSystemRepresentation, "wb");
    if (file == NULL) return NO;
    BOOL ok = YES;
    if (entry.method == 0) {
        uint64_t written = 0;
        while (written < entry.size && ok) {
            size_t chunk = (size_t)MIN((uint64_t)(8 * 1024 * 1024), entry.size - written);
            ok = fwrite(bytes + start + written, 1, chunk, file) == chunk;
            written += chunk;
        }
    } else {
        z_stream stream;
        memset(&stream, 0, sizeof(stream));
        if (inflateInit2(&stream, -MAX_WBITS) != Z_OK) { fclose(file); return NO; }
        const size_t outSize = 1024 * 1024;
        uint8_t *output = malloc(outSize);
        uint64_t consumed = 0;
        uint64_t produced = 0;
        int result = Z_OK;
        while (ok && result != Z_STREAM_END) {
            if (stream.avail_in == 0 && consumed < entry.compressed) {
                uint64_t chunk = MIN((uint64_t)(64 * 1024 * 1024), entry.compressed - consumed);
                stream.next_in = (Bytef *)(bytes + start + consumed);
                stream.avail_in = (uInt)chunk;
                consumed += chunk;
            }
            stream.next_out = output;
            stream.avail_out = (uInt)outSize;
            result = inflate(&stream, Z_NO_FLUSH);
            if (result != Z_OK && result != Z_STREAM_END) { ok = NO; break; }
            size_t have = outSize - stream.avail_out;
            if (have > 0) {
                ok = fwrite(output, 1, have, file) == have;
                produced += have;
            }
            if (result == Z_OK && have == 0 && stream.avail_in == 0 && consumed >= entry.compressed) { ok = NO; break; }
        }
        inflateEnd(&stream);
        free(output);
        if (produced != entry.size) ok = NO;
    }
    if (fclose(file) != 0) ok = NO;
    if (!ok) [NSFileManager.defaultManager removeItemAtPath:destination error:nil];
    return ok;
}

+ (NSInteger)extractAllFromPath:(NSString *)path toFolder:(NSString *)folder stripPrefix:(nullable NSString *)stripPrefix {
    NSData *archive = [self mappedDataAtPath:path];
    if (archive == nil) return -1;
    NSArray<OSZipEntry *> *entries = [self entriesInData:archive];
    if (entries == nil) return -1;
    NSInteger count = 0;
    for (OSZipEntry *entry in entries) {
        NSString *relative = entry.path;
        if (stripPrefix.length > 0 && [relative hasPrefix:stripPrefix]) relative = [relative substringFromIndex:stripPrefix.length];
        if (relative.length == 0) continue;
        @autoreleasepool {
            if ([self extractEntry:entry fromData:archive toFile:[folder stringByAppendingPathComponent:relative]]) count++;
        }
    }
    return count;
}

@end
