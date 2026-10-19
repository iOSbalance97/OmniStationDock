// HUD de rendimiento de los núcleos integrados (FPS, temperatura, RAM, batería).
// SPDX-License-Identifier: GPL-3.0-or-later
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface OSPerfHUD : UILabel

@property (nonatomic, assign) BOOL showFrameTime;
@property (nonatomic, assign) BOOL showFifo;
@property (nonatomic, assign) BOOL showMemory;
@property (nonatomic, assign) BOOL showThermal;
@property (nonatomic, assign) BOOL showBattery;

/// Repinta el texto. `fps` < 0: el núcleo no da FPS (entonces no sale esa línea).
- (void)refreshWithFPS:(double)fps frameTime:(double)frameTime fifo:(double)fifo;

/// Tamaño que necesita el texto actual.
- (CGSize)fittingSize;

@end

NS_ASSUME_NONNULL_END
