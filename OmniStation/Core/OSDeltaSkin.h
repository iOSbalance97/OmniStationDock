// Skins del mando táctil en el formato de Delta (.deltaskin, también el de ManicEMU): un zip con
// info.json (botones, pantalla del juego) y sus imágenes (PDF o PNG). Se importan a
// Documents/Skins y se eligen por sistema desde el menú de la partida.
// SPDX-License-Identifier: GPL-3.0-or-later
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Estilos propios de OmniStation para el mando táctil (sin skin): valores de `selectedForLayout:`.
extern NSString *const OSSkinStyleClassic; // «style:classic» (el de siempre)
extern NSString *const OSSkinStyleNeon;    // «style:neon»
extern NSString *const OSSkinStyleClear;   // «style:clear» (casi transparente)

@interface OSDeltaSkin : NSObject
@property (nonatomic, readonly, copy) NSString *name;
/// Carpeta dentro de Documents/Skins (identifica la skin).
@property (nonatomic, readonly, copy) NSString *folderName;
/// Sistema de OmniStation («snes», «n64»…) según su gameTypeIdentifier; nil si no se sabe.
@property (nonatomic, readonly, copy, nullable) NSString *layout;

/// Las instaladas para un sistema (las de otros sistemas no).
+ (NSArray<OSDeltaSkin *> *)installedSkinsForLayout:(NSString *)layout;
+ (nullable OSDeltaSkin *)skinNamed:(NSString *)folderName;
/// Importa un .deltaskin (zip). Devuelve la skin o nil con el motivo en `error`.
+ (nullable OSDeltaSkin *)importArchiveAtURL:(NSURL *)url error:(NSString * _Nullable * _Nullable)error;
+ (BOOL)removeSkin:(OSDeltaSkin *)skin;

/// Lo elegido para un sistema: un estilo («style:…») o la carpeta de una skin. Por defecto, clásico.
+ (NSString *)selectedForLayout:(NSString *)layout;
+ (void)setSelected:(NSString *)value forLayout:(NSString *)layout;

/// Representación para el iPhone en esa orientación (edgeToEdge con notch, si no standard).
- (nullable NSDictionary *)representationPortrait:(BOOL)portrait edgeToEdge:(BOOL)edgeToEdge;
@end

/// Vista del mando con una skin: dibuja la imagen y convierte los toques en botones.
@interface OSDeltaSkinView : UIView
- (instancetype)initWithSkin:(OSDeltaSkin *)skin layout:(NSString *)layout;
@property (nonatomic, readonly, strong) OSDeltaSkin *skin;
/// Prepara la representación para este tamaño. NO si la skin no tiene esta orientación.
- (BOOL)applyForSize:(CGSize)size edgeToEdge:(BOOL)edgeToEdge;
/// Dónde va la imagen del juego según la skin (CGRectNull si no lo dice).
@property (nonatomic, readonly) CGRect gameScreenFrame;
/// Pantallas por separado (NDS: la de arriba y la táctil en sitios distintos): dónde va cada una
/// (en la vista) y qué trozo del fotograma enseña (0…1). Vacío si la skin no las separa.
@property (nonatomic, readonly, copy) NSArray<NSValue *> *screenOutputs;
@property (nonatomic, readonly, copy) NSArray<NSValue *> *screenSources;
@property (nonatomic, assign) CGFloat opacity;
/// Botones pulsados: bits RETRO_DEVICE_ID_JOYPAD_* y, aparte, los C de N64 (1, 2, 4, 8).
@property (nonatomic, copy, nullable) void (^buttonsChanged)(uint32_t bits, uint32_t cBits);
/// Stick analógico (-1…1); active NO al soltar.
@property (nonatomic, copy, nullable) void (^stickChanged)(CGFloat x, CGFloat y, BOOL active);
/// Pantalla táctil de la skin (NDS): posición -1…1.
@property (nonatomic, copy, nullable) void (^pointerChanged)(CGFloat x, CGFloat y, BOOL down);
/// Botones especiales: «menu», «toggleFastForward», «fastForward», «quickSave», «quickLoad»
/// (pressed NO al soltar, para «fastForward»).
@property (nonatomic, copy, nullable) void (^special)(NSString *name, BOOL pressed);
- (void)releaseAll;
@end

NS_ASSUME_NONNULL_END
