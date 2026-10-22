// Skins de Delta (.deltaskin) para el mando táctil de los núcleos libretro.
// SPDX-License-Identifier: GPL-3.0-or-later
#import "OSDeltaSkin.h"
#import "OSRetroAPI.h"
#import <zlib.h>

NSString *const OSSkinStyleClassic = @"style:classic";
NSString *const OSSkinStyleNeon = @"style:neon";
NSString *const OSSkinStyleClear = @"style:clear";

// MARK: - Zip (lo justo para un .deltaskin: sin cifrar, guardado o deflate, sin zip64)

static uint16_t OSZipU16(const uint8_t *p) { return (uint16_t)(p[0] | (p[1] << 8)); }
static uint32_t OSZipU32(const uint8_t *p) { return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }

static NSData *OSZipInflate(const uint8_t *data, size_t size, size_t expected) {
    if (expected > 256u * 1024 * 1024) return nil;
    NSMutableData *output = [NSMutableData dataWithLength:MAX(expected, (size_t)1)];
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    if (inflateInit2(&stream, -MAX_WBITS) != Z_OK) return nil;
    stream.next_in = (Bytef *)data;
    stream.avail_in = (uInt)size;
    stream.next_out = output.mutableBytes;
    stream.avail_out = (uInt)output.length;
    int result = inflate(&stream, Z_FINISH);
    size_t produced = stream.total_out;
    inflateEnd(&stream);
    if (result != Z_STREAM_END || produced != expected) return nil;
    output.length = produced;
    return output;
}

/// Extrae el zip en `folder`. NO si no es un zip que se pueda leer.
static BOOL OSZipExtract(NSData *archive, NSString *folder) {
    const uint8_t *bytes = archive.bytes;
    size_t length = archive.length;
    if (length < 22) return NO;
    // Fin del directorio central (puede llevar un comentario de hasta 64 KB).
    size_t end = 0;
    BOOL found = NO;
    size_t lowest = length > 22 + 65535 ? length - 22 - 65535 : 0;
    for (size_t at = length - 22; ; at--) {
        if (OSZipU32(bytes + at) == 0x06054b50) { end = at; found = YES; break; }
        if (at == lowest) break;
    }
    if (!found) return NO;
    uint16_t entries = OSZipU16(bytes + end + 10);
    uint32_t directory = OSZipU32(bytes + end + 16);
    if (directory >= length) return NO;
    NSFileManager *files = NSFileManager.defaultManager;
    size_t at = directory;
    NSUInteger written = 0;
    for (uint16_t index = 0; index < entries; index++) {
        if (at + 46 > length || OSZipU32(bytes + at) != 0x02014b50) return NO;
        uint16_t flags = OSZipU16(bytes + at + 8);
        uint16_t method = OSZipU16(bytes + at + 10);
        uint32_t compressed = OSZipU32(bytes + at + 20);
        uint32_t uncompressed = OSZipU32(bytes + at + 24);
        uint16_t nameLength = OSZipU16(bytes + at + 28);
        uint16_t extraLength = OSZipU16(bytes + at + 30);
        uint16_t commentLength = OSZipU16(bytes + at + 32);
        uint32_t local = OSZipU32(bytes + at + 42);
        if (at + 46 + nameLength > length) return NO;
        NSString *name = [[NSString alloc] initWithBytes:bytes + at + 46 length:nameLength encoding:NSUTF8StringEncoding];
        at += 46 + (size_t)nameLength + extraLength + commentLength;
        if (name == nil || [name hasSuffix:@"/"] || [name hasPrefix:@"__MACOSX/"] || [name.lastPathComponent hasPrefix:@"._"]) continue;
        if ((flags & 1) != 0) return NO; // cifrado
        // Nada fuera de la carpeta.
        NSString *clean = name.stringByStandardizingPath;
        if (clean.length == 0 || [clean hasPrefix:@"/"] || [clean hasPrefix:@".."] || [clean containsString:@"/../"]) continue;
        if ((size_t)local + 30 > length || OSZipU32(bytes + local) != 0x04034b50) return NO;
        size_t data = (size_t)local + 30 + OSZipU16(bytes + local + 26) + OSZipU16(bytes + local + 28);
        if (data + compressed > length) return NO;
        NSData *content = nil;
        if (method == 0) {
            content = [NSData dataWithBytes:bytes + data length:compressed];
        } else if (method == 8) {
            content = OSZipInflate(bytes + data, compressed, uncompressed);
        }
        if (content == nil) return NO;
        NSString *path = [folder stringByAppendingPathComponent:clean];
        [files createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
        if (![content writeToFile:path atomically:NO]) return NO;
        written++;
    }
    return written > 0;
}

// MARK: - Skin

/// Sistema de OmniStation para el gameTypeIdentifier («com.rileytestut.delta.game.snes»…).
static NSString *OSSkinLayoutForGameType(NSString *gameType) {
    NSString *last = gameType.pathExtension.lowercaseString;
    if (last.length == 0) last = gameType.lowercaseString;
    NSDictionary<NSString *, NSString *> *known = @{
        @"nes": @"nes", @"fc": @"nes", @"snes": @"snes", @"sfc": @"snes",
        @"gbc": @"gb", @"gb": @"gb", @"gba": @"gba", @"n64": @"n64",
        @"ds": @"nds", @"nds": @"nds", @"3ds": @"3ds",
        @"psp": @"psp", @"ps1": @"ps1", @"psx": @"ps1", @"ps": @"ps1",
        @"dc": @"dc", @"dreamcast": @"dc", @"gc": @"gc", @"gamecube": @"gc", @"ngc": @"gc", @"wii": @"wii"};
    return known[last];
}

static NSString *OSSkinsFolder(void) {
    NSString *documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *folder = [documents stringByAppendingPathComponent:@"Skins"];
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    return folder;
}

@interface OSDeltaSkin ()
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *folderName;
@property (nonatomic, copy, nullable) NSString *layout;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSDictionary *info;
@end

@implementation OSDeltaSkin

+ (nullable OSDeltaSkin *)skinAtPath:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:[path stringByAppendingPathComponent:@"info.json"]];
    if (data == nil) return nil;
    NSDictionary *info = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![info isKindOfClass:NSDictionary.class] || ![info[@"representations"] isKindOfClass:NSDictionary.class]) return nil;
    OSDeltaSkin *skin = [OSDeltaSkin new];
    skin.path = path;
    skin.folderName = path.lastPathComponent;
    skin.info = info;
    skin.name = [info[@"name"] isKindOfClass:NSString.class] && [info[@"name"] length] > 0 ? info[@"name"] : path.lastPathComponent;
    NSString *gameType = [info[@"gameTypeIdentifier"] isKindOfClass:NSString.class] ? info[@"gameTypeIdentifier"] : @"";
    skin.layout = OSSkinLayoutForGameType(gameType);
    return skin;
}

+ (NSArray<OSDeltaSkin *> *)installedSkinsForLayout:(NSString *)layout {
    NSString *folder = OSSkinsFolder();
    NSMutableArray<OSDeltaSkin *> *skins = [NSMutableArray new];
    // GameCube y Wii comparten skins.
    NSSet<NSString *> *wanted = ([layout isEqualToString:@"gc"] || [layout isEqualToString:@"wii"]) ? [NSSet setWithObjects:@"gc", @"wii", nil] : [NSSet setWithObject:layout];
    for (NSString *name in [[NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
        OSDeltaSkin *skin = [self skinAtPath:[folder stringByAppendingPathComponent:name]];
        if (skin != nil && skin.layout != nil && [wanted containsObject:skin.layout]) [skins addObject:skin];
    }
    return skins;
}

+ (nullable OSDeltaSkin *)skinNamed:(NSString *)folderName {
    if (folderName.length == 0 || [folderName containsString:@"/"]) return nil;
    return [self skinAtPath:[OSSkinsFolder() stringByAppendingPathComponent:folderName]];
}

+ (nullable OSDeltaSkin *)importArchiveAtURL:(NSURL *)url error:(NSString **)error {
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSData *archive = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil];
    if (scoped) [url stopAccessingSecurityScopedResource];
    if (archive == nil) {
        if (error) *error = @"read";
        return nil;
    }
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *temporary = [NSTemporaryDirectory() stringByAppendingPathComponent:[@"skin-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    [files createDirectoryAtPath:temporary withIntermediateDirectories:YES attributes:nil error:nil];
    if (!OSZipExtract(archive, temporary)) {
        [files removeItemAtPath:temporary error:nil];
        if (error) *error = @"zip";
        return nil;
    }
    // info.json arriba del todo o dentro de una carpeta.
    NSString *root = temporary;
    if (![files fileExistsAtPath:[root stringByAppendingPathComponent:@"info.json"]]) {
        root = nil;
        for (NSString *name in [files contentsOfDirectoryAtPath:temporary error:nil]) {
            NSString *candidate = [temporary stringByAppendingPathComponent:name];
            if ([files fileExistsAtPath:[candidate stringByAppendingPathComponent:@"info.json"]]) { root = candidate; break; }
        }
    }
    OSDeltaSkin *probe = root ? [self skinAtPath:root] : nil;
    if (probe == nil) {
        [files removeItemAtPath:temporary error:nil];
        if (error) *error = @"info";
        return nil;
    }
    if (probe.layout == nil) {
        [files removeItemAtPath:temporary error:nil];
        if (error) *error = @"system";
        return nil;
    }
    NSString *identifier = [probe.info[@"identifier"] isKindOfClass:NSString.class] ? probe.info[@"identifier"] : probe.name;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"];
    NSString *folderName = [[identifier componentsSeparatedByCharactersInSet:allowed.invertedSet] componentsJoinedByString:@"_"];
    if (folderName.length == 0) folderName = NSUUID.UUID.UUIDString;
    NSString *destination = [OSSkinsFolder() stringByAppendingPathComponent:folderName];
    [files removeItemAtPath:destination error:nil];
    if (![files moveItemAtPath:root toPath:destination error:nil]) {
        [files removeItemAtPath:temporary error:nil];
        if (error) *error = @"write";
        return nil;
    }
    [files removeItemAtPath:temporary error:nil];
    return [self skinAtPath:destination];
}

+ (BOOL)removeSkin:(OSDeltaSkin *)skin {
    for (NSString *layout in @[@"nes", @"snes", @"gb", @"gba", @"n64", @"nds", @"3ds", @"psp", @"ps1", @"dc", @"gc", @"wii"]) {
        if ([[self selectedForLayout:layout] isEqualToString:skin.folderName]) [self setSelected:OSSkinStyleClassic forLayout:layout];
    }
    return [NSFileManager.defaultManager removeItemAtPath:skin.path error:nil];
}

+ (NSString *)selectedForLayout:(NSString *)layout {
    NSString *value = [NSUserDefaults.standardUserDefaults stringForKey:[@"omniSkin." stringByAppendingString:layout]];
    return value.length > 0 ? value : OSSkinStyleClassic;
}

+ (void)setSelected:(NSString *)value forLayout:(NSString *)layout {
    [NSUserDefaults.standardUserDefaults setObject:value forKey:[@"omniSkin." stringByAppendingString:layout]];
}

- (nullable NSDictionary *)representationPortrait:(BOOL)portrait edgeToEdge:(BOOL)edgeToEdge {
    NSDictionary *representations = self.info[@"representations"];
    NSDictionary *device = [representations[@"iphone"] isKindOfClass:NSDictionary.class] ? representations[@"iphone"] : nil;
    if (device == nil) return nil;
    NSString *orientation = portrait ? @"portrait" : @"landscape";
    NSArray<NSString *> *order = edgeToEdge ? @[@"edgeToEdge", @"standard"] : @[@"standard", @"edgeToEdge"];
    for (NSString *kind in order) {
        NSDictionary *variant = [device[kind] isKindOfClass:NSDictionary.class] ? device[kind] : nil;
        NSDictionary *representation = [variant[orientation] isKindOfClass:NSDictionary.class] ? variant[orientation] : nil;
        if (representation != nil && [representation[@"items"] isKindOfClass:NSArray.class]) return representation;
    }
    return nil;
}

- (NSString *)filePath:(NSString *)name {
    if (![name isKindOfClass:NSString.class] || name.length == 0 || [name containsString:@".."]) return nil;
    return [self.path stringByAppendingPathComponent:name];
}

/// Imagen de la representación al tamaño (en puntos) que va a ocupar.
- (nullable UIImage *)imageForRepresentation:(NSDictionary *)representation size:(CGSize)size {
    NSDictionary *assets = [representation[@"assets"] isKindOfClass:NSDictionary.class] ? representation[@"assets"] : nil;
    if (assets == nil || size.width < 1 || size.height < 1) return nil;
    NSString *pdf = [self filePath:assets[@"resizable"]];
    if (pdf != nil && [NSFileManager.defaultManager fileExistsAtPath:pdf]) {
        CGPDFDocumentRef document = CGPDFDocumentCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:pdf]);
        CGPDFPageRef page = document ? CGPDFDocumentGetPage(document, 1) : NULL;
        UIImage *image = nil;
        if (page != NULL) {
            CGRect box = CGPDFPageGetBoxRect(page, kCGPDFCropBox);
            UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
            image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
                CGContextRef cg = context.CGContext;
                CGContextTranslateCTM(cg, 0, size.height);
                CGContextScaleCTM(cg, size.width / MAX(1, box.size.width), -size.height / MAX(1, box.size.height));
                CGContextTranslateCTM(cg, -box.origin.x, -box.origin.y);
                CGContextDrawPDFPage(cg, page);
            }];
        }
        if (document) CGPDFDocumentRelease(document);
        if (image) return image;
    }
    for (NSString *key in @[@"large", @"medium", @"small"]) {
        NSString *png = [self filePath:assets[key]];
        UIImage *image = png ? [UIImage imageWithContentsOfFile:png] : nil;
        if (image) return image;
    }
    return nil;
}

- (nullable UIImage *)thumbstickImage:(NSDictionary *)item {
    NSDictionary *thumbstick = [item[@"thumbstick"] isKindOfClass:NSDictionary.class] ? item[@"thumbstick"] : nil;
    NSString *path = [self filePath:thumbstick[@"name"]];
    if (path == nil) return nil;
    if ([path.pathExtension.lowercaseString isEqualToString:@"pdf"]) {
        CGFloat w = [thumbstick[@"width"] doubleValue], h = [thumbstick[@"height"] doubleValue];
        if (w < 1 || h < 1) { w = 60; h = 60; }
        CGPDFDocumentRef document = CGPDFDocumentCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path]);
        CGPDFPageRef page = document ? CGPDFDocumentGetPage(document, 1) : NULL;
        UIImage *image = nil;
        if (page) {
            CGRect box = CGPDFPageGetBoxRect(page, kCGPDFCropBox);
            CGSize size = CGSizeMake(w * 2, h * 2);
            image = [[[UIGraphicsImageRenderer alloc] initWithSize:size] imageWithActions:^(UIGraphicsImageRendererContext *context) {
                CGContextRef cg = context.CGContext;
                CGContextTranslateCTM(cg, 0, size.height);
                CGContextScaleCTM(cg, size.width / MAX(1, box.size.width), -size.height / MAX(1, box.size.height));
                CGContextTranslateCTM(cg, -box.origin.x, -box.origin.y);
                CGContextDrawPDFPage(cg, page);
            }];
        }
        if (document) CGPDFDocumentRelease(document);
        return image;
    }
    return [UIImage imageWithContentsOfFile:path];
}

@end

// MARK: - Vista

typedef NS_ENUM(NSInteger, OSSkinItemKind) {
    OSSkinItemButtons,
    OSSkinItemDirectional, // cruceta: cuatro salidas digitales
    OSSkinItemStick,       // stick analógico
    OSSkinItemTouchScreen, // pantalla táctil (NDS)
};

@interface OSSkinItem : NSObject
@property (nonatomic, assign) OSSkinItemKind kind;
@property (nonatomic, assign) CGRect frame;   // en la vista
@property (nonatomic, assign) CGRect hitFrame; // con los bordes extendidos
@property (nonatomic, copy) NSArray<NSString *> *inputs; // botones
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *directions; // up/down/left/right → entrada
@property (nonatomic, strong, nullable) UIImageView *thumb;
/// Pantalla táctil: qué trozo del fotograma es (0…1).
@property (nonatomic, assign) CGRect source;
@end

@implementation OSSkinItem
@end

/// Botón de libretro para una entrada de Delta (-1 si no; 100+n los C de N64).
static NSInteger OSSkinRetroID(NSString *input, NSString *layout) {
    BOOL n64 = [layout isEqualToString:@"n64"];
    BOOL triggers = [layout isEqualToString:@"dc"] || [layout isEqualToString:@"gc"] || [layout isEqualToString:@"wii"];
    NSString *name = input.lowercaseString;
    if ([name isEqualToString:@"up"]) return RETRO_DEVICE_ID_JOYPAD_UP;
    if ([name isEqualToString:@"down"]) return RETRO_DEVICE_ID_JOYPAD_DOWN;
    if ([name isEqualToString:@"left"]) return RETRO_DEVICE_ID_JOYPAD_LEFT;
    if ([name isEqualToString:@"right"]) return RETRO_DEVICE_ID_JOYPAD_RIGHT;
    if ([name isEqualToString:@"start"]) return RETRO_DEVICE_ID_JOYPAD_START;
    if ([name isEqualToString:@"select"]) return RETRO_DEVICE_ID_JOYPAD_SELECT;
    // Como el mando táctil de OmniStation: en N64, A y B son B e Y de libretro y Z es L2.
    if ([name isEqualToString:@"a"]) return n64 ? RETRO_DEVICE_ID_JOYPAD_B : RETRO_DEVICE_ID_JOYPAD_A;
    if ([name isEqualToString:@"b"]) return n64 ? RETRO_DEVICE_ID_JOYPAD_Y : RETRO_DEVICE_ID_JOYPAD_B;
    if ([name isEqualToString:@"x"]) return RETRO_DEVICE_ID_JOYPAD_X;
    if ([name isEqualToString:@"y"]) return RETRO_DEVICE_ID_JOYPAD_Y;
    if ([name isEqualToString:@"z"]) return n64 ? RETRO_DEVICE_ID_JOYPAD_L2 : RETRO_DEVICE_ID_JOYPAD_R;
    if ([name isEqualToString:@"l"]) return triggers ? RETRO_DEVICE_ID_JOYPAD_L2 : RETRO_DEVICE_ID_JOYPAD_L;
    if ([name isEqualToString:@"r"]) return triggers ? RETRO_DEVICE_ID_JOYPAD_R2 : RETRO_DEVICE_ID_JOYPAD_R;
    if ([name isEqualToString:@"l1"]) return RETRO_DEVICE_ID_JOYPAD_L;
    if ([name isEqualToString:@"r1"]) return RETRO_DEVICE_ID_JOYPAD_R;
    if ([name isEqualToString:@"l2"] || [name isEqualToString:@"zl"]) return RETRO_DEVICE_ID_JOYPAD_L2;
    if ([name isEqualToString:@"r2"] || [name isEqualToString:@"zr"]) return RETRO_DEVICE_ID_JOYPAD_R2;
    if ([name isEqualToString:@"l3"]) return RETRO_DEVICE_ID_JOYPAD_L3;
    if ([name isEqualToString:@"r3"]) return RETRO_DEVICE_ID_JOYPAD_R3;
    // Mandos de PlayStation (en libretro: X, A, B, Y).
    if ([name isEqualToString:@"triangle"]) return RETRO_DEVICE_ID_JOYPAD_X;
    if ([name isEqualToString:@"circle"]) return RETRO_DEVICE_ID_JOYPAD_A;
    if ([name isEqualToString:@"cross"]) return RETRO_DEVICE_ID_JOYPAD_B;
    if ([name isEqualToString:@"square"]) return RETRO_DEVICE_ID_JOYPAD_Y;
    if ([name isEqualToString:@"cup"]) return 100;
    if ([name isEqualToString:@"cdown"]) return 101;
    if ([name isEqualToString:@"cleft"]) return 102;
    if ([name isEqualToString:@"cright"]) return 103;
    return -1;
}

static BOOL OSSkinIsSpecial(NSString *input) {
    return [@[@"menu", @"toggleFastForward", @"fastForward", @"quickSave", @"quickLoad"] containsObject:input];
}

static CGRect OSSkinRect(id value) {
    if (![value isKindOfClass:NSDictionary.class]) return CGRectNull;
    NSDictionary *frame = value;
    return CGRectMake([frame[@"x"] doubleValue], [frame[@"y"] doubleValue], [frame[@"width"] doubleValue], [frame[@"height"] doubleValue]);
}

@implementation OSDeltaSkinView {
    NSString *_layout;
    UIImageView *_imageView;
    NSMutableArray<OSSkinItem *> *_items;
    NSMapTable<UITouch *, OSSkinItem *> *_touchItems;
    OSSkinItem *_stickItem;
    UITouch *_stickTouch;
    UITouch *_pointerTouch;
    OSSkinItem *_pointerItem;
    uint32_t _lastBits, _lastCBits;
    BOOL _fastForwardHeld;
    CGSize _appliedSize;
    BOOL _appliedEdge;
}

- (instancetype)initWithSkin:(OSDeltaSkin *)skin layout:(NSString *)layout {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _skin = skin;
        _layout = [layout copy];
        _items = [NSMutableArray new];
        _touchItems = [NSMapTable weakToStrongObjectsMapTable];
        _gameScreenFrame = CGRectNull;
        _opacity = 1;
        self.multipleTouchEnabled = YES;
        self.backgroundColor = UIColor.clearColor;
        _imageView = [UIImageView new];
        _imageView.userInteractionEnabled = NO;
        [self addSubview:_imageView];
    }
    return self;
}

- (BOOL)applyForSize:(CGSize)size edgeToEdge:(BOOL)edgeToEdge {
    if (CGSizeEqualToSize(size, _appliedSize) && edgeToEdge == _appliedEdge && _items.count > 0) return YES;
    [self releaseAll];
    for (OSSkinItem *item in _items) [item.thumb removeFromSuperview];
    [_items removeAllObjects];
    _stickItem = nil;
    _pointerItem = nil;
    _gameScreenFrame = CGRectNull;
    _screenOutputs = @[];
    _screenSources = @[];
    _imageView.image = nil;
    _appliedSize = size;
    _appliedEdge = edgeToEdge;
    BOOL portrait = size.height > size.width;
    NSDictionary *representation = [self.skin representationPortrait:portrait edgeToEdge:edgeToEdge];
    NSDictionary *mapping = [representation[@"mappingSize"] isKindOfClass:NSDictionary.class] ? representation[@"mappingSize"] : nil;
    CGFloat mw = [mapping[@"width"] doubleValue], mh = [mapping[@"height"] doubleValue];
    if (representation == nil || mw < 1 || mh < 1 || size.width < 1 || size.height < 1) {
        _appliedSize = CGSizeZero;
        return NO;
    }
    // Como Delta: a todo el ancho y abajo; si no cabe de alto, a todo el alto (centrada).
    CGFloat scale = size.width / mw;
    if (mh * scale > size.height) scale = size.height / mh;
    CGFloat ox = floor((size.width - mw * scale) * 0.5);
    CGFloat oy = floor(size.height - mh * scale);
    CGRect (^map)(CGRect) = ^CGRect(CGRect rect) {
        return CGRectMake(ox + rect.origin.x * scale, oy + rect.origin.y * scale, rect.size.width * scale, rect.size.height * scale);
    };
    CGRect area = CGRectMake(ox, oy, mw * scale, mh * scale);
    _imageView.frame = area;
    _imageView.image = [self.skin imageForRepresentation:representation size:area.size];
    BOOL translucent = [representation[@"translucent"] boolValue];
    _imageView.alpha = translucent ? self.opacity : 1;
    NSDictionary *edges = [representation[@"extendedEdges"] isKindOfClass:NSDictionary.class] ? representation[@"extendedEdges"] : nil;
    for (NSDictionary *entry in representation[@"items"]) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        CGRect frame = OSSkinRect(entry[@"frame"]);
        if (CGRectIsNull(frame)) continue;
        OSSkinItem *item = [OSSkinItem new];
        item.frame = map(frame);
        NSDictionary *own = [entry[@"extendedEdges"] isKindOfClass:NSDictionary.class] ? entry[@"extendedEdges"] : edges;
        CGFloat top = [own[@"top"] doubleValue] * scale, bottom = [own[@"bottom"] doubleValue] * scale;
        CGFloat left = [own[@"left"] doubleValue] * scale, right = [own[@"right"] doubleValue] * scale;
        item.hitFrame = CGRectMake(item.frame.origin.x - left, item.frame.origin.y - top,
                                   item.frame.size.width + left + right, item.frame.size.height + top + bottom);
        id inputs = entry[@"inputs"];
        if ([inputs isKindOfClass:NSArray.class]) {
            item.kind = OSSkinItemButtons;
            item.inputs = inputs;
        } else if ([inputs isKindOfClass:NSDictionary.class]) {
            NSDictionary *directions = inputs;
            NSString *anyValue = [[directions allValues] firstObject];
            if ([directions[@"x"] isKindOfClass:NSString.class] && [[directions[@"x"] lowercaseString] containsString:@"touchscreen"]) {
                item.kind = OSSkinItemTouchScreen;
                _pointerItem = item;
            } else if (entry[@"thumbstick"] != nil || [[anyValue lowercaseString] hasPrefix:@"analogstick"]) {
                item.kind = OSSkinItemStick;
                _stickItem = item;
                UIImage *thumb = [self.skin thumbstickImage:entry];
                if (thumb) {
                    NSDictionary *thumbInfo = entry[@"thumbstick"];
                    CGFloat tw = [thumbInfo[@"width"] doubleValue] * scale, th = [thumbInfo[@"height"] doubleValue] * scale;
                    if (tw < 1 || th < 1) { tw = item.frame.size.width * 0.5; th = item.frame.size.height * 0.5; }
                    item.thumb = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, tw, th)];
                    item.thumb.image = thumb;
                    item.thumb.userInteractionEnabled = NO;
                    item.thumb.center = CGPointMake(CGRectGetMidX(item.frame), CGRectGetMidY(item.frame));
                    [self addSubview:item.thumb];
                }
            } else {
                item.kind = OSSkinItemDirectional;
            }
            item.directions = directions;
        } else {
            continue;
        }
        [_items addObject:item];
    }
    // Dónde va el juego: «screens» (la unión de sus salidas) o «gameScreenFrame».
    CGRect screen = CGRectNull;
    CGRect sourceBounds = CGRectNull;
    NSMutableArray<NSValue *> *outputs = [NSMutableArray new];
    NSMutableArray<NSValue *> *inputs = [NSMutableArray new];
    BOOL allInputs = YES;
    for (NSDictionary *entry in representation[@"screens"]) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        CGRect output = OSSkinRect(entry[@"outputFrame"]);
        if (CGRectIsNull(output)) continue;
        screen = CGRectIsNull(screen) ? output : CGRectUnion(screen, output);
        CGRect input = OSSkinRect(entry[@"inputFrame"]);
        if (CGRectIsNull(input) || input.size.width < 1 || input.size.height < 1) allInputs = NO;
        else sourceBounds = CGRectIsNull(sourceBounds) ? input : CGRectUnion(sourceBounds, input);
        [outputs addObject:[NSValue valueWithCGRect:map(output)]];
        [inputs addObject:[NSValue valueWithCGRect:input]];
    }
    if (CGRectIsNull(screen)) screen = OSSkinRect(representation[@"gameScreenFrame"]);
    _gameScreenFrame = CGRectIsNull(screen) ? CGRectNull : map(screen);
    if (allInputs && outputs.count > 0 && !CGRectIsNull(sourceBounds)) {
        NSMutableArray<NSValue *> *sources = [NSMutableArray new];
        for (NSValue *value in inputs) {
            CGRect input = value.CGRectValue;
            [sources addObject:[NSValue valueWithCGRect:CGRectMake((input.origin.x - sourceBounds.origin.x) / sourceBounds.size.width,
                                                                   (input.origin.y - sourceBounds.origin.y) / sourceBounds.size.height,
                                                                   input.size.width / sourceBounds.size.width,
                                                                   input.size.height / sourceBounds.size.height)]];
        }
        _screenOutputs = outputs;
        _screenSources = sources;
    }
    // La pantalla táctil es la pantalla de la skin que tiene debajo (si no, la mitad de abajo, como en NDS).
    if (_pointerItem != nil) {
        CGRect source = CGRectMake(0, 0.5, 1, 0.5);
        CGPoint center = CGPointMake(CGRectGetMidX(_pointerItem.frame), CGRectGetMidY(_pointerItem.frame));
        for (NSUInteger index = 0; index < _screenOutputs.count; index++) {
            if (CGRectContainsPoint(_screenOutputs[index].CGRectValue, center)) { source = _screenSources[index].CGRectValue; break; }
        }
        _pointerItem.source = source;
    }
    return _items.count > 0;
}

- (void)setOpacity:(CGFloat)opacity {
    _opacity = opacity;
    if (_imageView.alpha < 1) _imageView.alpha = opacity;
}

/// Fuera de los botones de la skin, el toque pasa (a la pantalla del juego, al menú…).
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || !self.userInteractionEnabled) return nil;
    return [self itemAtPoint:point] != nil ? self : nil;
}

- (nullable OSSkinItem *)itemAtPoint:(CGPoint)point {
    // El más pequeño que lo contiene (los botones sobre las zonas grandes).
    OSSkinItem *best = nil;
    CGFloat bestArea = CGFLOAT_MAX;
    for (OSSkinItem *item in _items) {
        if (!CGRectContainsPoint(item.hitFrame, point)) continue;
        CGFloat area = item.frame.size.width * item.frame.size.height;
        if (area < bestArea) { best = item; bestArea = area; }
    }
    return best;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) {
        CGPoint point = [touch locationInView:self];
        OSSkinItem *item = [self itemAtPoint:point];
        if (item == nil) continue;
        [_touchItems setObject:item forKey:touch];
        if (item.kind == OSSkinItemStick && _stickTouch == nil) _stickTouch = touch;
        if (item.kind == OSSkinItemTouchScreen && _pointerTouch == nil) _pointerTouch = touch;
        if (item.kind == OSSkinItemButtons) {
            for (NSString *input in item.inputs) {
                if (!OSSkinIsSpecial(input)) continue;
                if ([input isEqualToString:@"fastForward"]) _fastForwardHeld = YES;
                if (self.special) self.special(input, YES);
            }
        }
    }
    [self update];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) {
        OSSkinItem *current = [_touchItems objectForKey:touch];
        // Stick, cruceta y pantalla siguen con el dedo; entre botones se puede deslizar.
        if (current != nil && current.kind != OSSkinItemButtons) continue;
        OSSkinItem *item = [self itemAtPoint:[touch locationInView:self]];
        if (item != nil && item.kind == OSSkinItemButtons) [_touchItems setObject:item forKey:touch];
        else if (item == nil && current != nil && !CGRectContainsPoint(current.hitFrame, [touch locationInView:self])) [_touchItems removeObjectForKey:touch];
    }
    [self update];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) {
        OSSkinItem *item = [_touchItems objectForKey:touch];
        if (item.kind == OSSkinItemButtons && [item.inputs containsObject:@"fastForward"] && _fastForwardHeld) {
            _fastForwardHeld = NO;
            if (self.special) self.special(@"fastForward", NO);
        }
        [_touchItems removeObjectForKey:touch];
        if (touch == _stickTouch) {
            _stickTouch = nil;
            if (_stickItem.thumb) _stickItem.thumb.center = CGPointMake(CGRectGetMidX(_stickItem.frame), CGRectGetMidY(_stickItem.frame));
            if (self.stickChanged) self.stickChanged(0, 0, NO);
        }
        if (touch == _pointerTouch) {
            _pointerTouch = nil;
            if (self.pointerChanged) self.pointerChanged(0, 0, NO);
        }
    }
    [self update];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self touchesEnded:touches withEvent:event];
}

/// Recalcula todo lo pulsado a partir de los dedos que hay.
- (void)update {
    uint32_t bits = 0, cBits = 0;
    for (UITouch *touch in _touchItems) {
        OSSkinItem *item = [_touchItems objectForKey:touch];
        CGPoint point = [touch locationInView:self];
        if (item.kind == OSSkinItemButtons) {
            for (NSString *input in item.inputs) {
                NSInteger retro = OSSkinRetroID(input, _layout);
                if (retro >= 100) cBits |= 1u << (uint32_t)(retro - 100);
                else if (retro >= 0) bits |= 1u << (uint32_t)retro;
            }
        } else if (item.kind == OSSkinItemDirectional) {
            CGFloat half = MAX(1, MIN(item.frame.size.width, item.frame.size.height) * 0.5);
            CGFloat dx = (point.x - CGRectGetMidX(item.frame)) / half;
            CGFloat dy = (point.y - CGRectGetMidY(item.frame)) / half;
            NSMutableArray<NSString *> *pressed = [NSMutableArray new];
            if (dy < -0.33) [pressed addObject:@"up"];
            if (dy > 0.33) [pressed addObject:@"down"];
            if (dx < -0.33) [pressed addObject:@"left"];
            if (dx > 0.33) [pressed addObject:@"right"];
            for (NSString *direction in pressed) {
                NSString *input = item.directions[direction];
                NSInteger retro = input ? OSSkinRetroID(input, _layout) : -1;
                if (retro >= 100) cBits |= 1u << (uint32_t)(retro - 100);
                else if (retro >= 0) bits |= 1u << (uint32_t)retro;
            }
        } else if (item.kind == OSSkinItemStick && touch == _stickTouch) {
            CGFloat half = MAX(1, MIN(item.frame.size.width, item.frame.size.height) * 0.5);
            CGFloat dx = (point.x - CGRectGetMidX(item.frame)) / half;
            CGFloat dy = (point.y - CGRectGetMidY(item.frame)) / half;
            CGFloat length = sqrt(dx * dx + dy * dy);
            if (length > 1) { dx /= length; dy /= length; }
            if (item.thumb) item.thumb.center = CGPointMake(CGRectGetMidX(item.frame) + dx * half, CGRectGetMidY(item.frame) + dy * half);
            if (self.stickChanged) self.stickChanged(dx, dy, YES);
        } else if (item.kind == OSSkinItemTouchScreen && touch == _pointerTouch) {
            // Al fotograma entero (el núcleo sabe qué parte es la táctil).
            CGRect frame = item.frame;
            CGFloat nx = MAX(0, MIN(1, (point.x - frame.origin.x) / MAX(1, frame.size.width)));
            CGFloat ny = MAX(0, MIN(1, (point.y - frame.origin.y) / MAX(1, frame.size.height)));
            CGRect source = item.source;
            CGFloat x = (source.origin.x + nx * source.size.width) * 2 - 1;
            CGFloat y = (source.origin.y + ny * source.size.height) * 2 - 1;
            if (self.pointerChanged) self.pointerChanged(x, y, YES);
        }
    }
    if (bits != _lastBits || cBits != _lastCBits) {
        _lastBits = bits;
        _lastCBits = cBits;
        if (self.buttonsChanged) self.buttonsChanged(bits, cBits);
    }
}

- (void)releaseAll {
    [_touchItems removeAllObjects];
    if (_stickTouch != nil && self.stickChanged) self.stickChanged(0, 0, NO);
    if (_pointerTouch != nil && self.pointerChanged) self.pointerChanged(0, 0, NO);
    if (_fastForwardHeld && self.special) self.special(@"fastForward", NO);
    _fastForwardHeld = NO;
    _stickTouch = nil;
    _pointerTouch = nil;
    if (_stickItem.thumb) _stickItem.thumb.center = CGPointMake(CGRectGetMidX(_stickItem.frame), CGRectGetMidY(_stickItem.frame));
    if (_lastBits != 0 || _lastCBits != 0) {
        _lastBits = 0;
        _lastCBits = 0;
        if (self.buttonsChanged) self.buttonsChanged(0, 0);
    }
}

@end
