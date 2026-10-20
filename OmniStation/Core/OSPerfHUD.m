// HUD de rendimiento de los núcleos integrados.
// SPDX-License-Identifier: GPL-3.0-or-later
#import "OSPerfHUD.h"

#import <mach/mach.h>
#import <os/proc.h>

/// Memoria que usa OmniStation (la misma cuenta que usa iOS para cerrarla).
static uint64_t OSHUDFootprint(void) {
    task_vm_info_data_t info;
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    if (task_info(mach_task_self(), TASK_VM_INFO, (task_info_t)&info, &count) != KERN_SUCCESS) return 0;
    return info.phys_footprint;
}

static NSString *OSHUDGigabytes(uint64_t bytes) {
    return [NSString stringWithFormat:@"%.1f", (double)bytes / (1024.0 * 1024.0 * 1024.0)];
}

static BOOL OSHUDEnglish(void) {
    NSString *raw = [NSUserDefaults.standardUserDefaults stringForKey:@"appLanguage"] ?: @"system";
    if ([raw isEqualToString:@"en"]) return YES;
    if ([raw isEqualToString:@"es"]) return NO;
    return [NSLocale.preferredLanguages.firstObject hasPrefix:@"en"];
}

@implementation OSPerfHUD

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.numberOfLines = 0;
        self.textColor = UIColor.whiteColor;
        self.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightSemibold];
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
        self.layer.cornerRadius = 8;
        self.clipsToBounds = YES;
        self.userInteractionEnabled = NO;
        _showMemory = YES;
        _showThermal = YES;
        _showFrameTime = YES;
        UIDevice.currentDevice.batteryMonitoringEnabled = YES;
    }
    return self;
}

- (NSString *)thermalText {
    BOOL english = OSHUDEnglish();
    switch (NSProcessInfo.processInfo.thermalState) {
        case NSProcessInfoThermalStateNominal: return english ? @"Normal" : @"Normal";
        case NSProcessInfoThermalStateFair: return english ? @"Warm" : @"Templado";
        case NSProcessInfoThermalStateSerious: return english ? @"Hot" : @"Caliente";
        case NSProcessInfoThermalStateCritical: return english ? @"Critical" : @"Crítico";
    }
    return @"—";
}

- (void)refreshWithFPS:(double)fps frameTime:(double)frameTime fifo:(double)fifo {
    BOOL english = OSHUDEnglish();
    NSMutableArray<NSString *> *lines = [NSMutableArray new];
    if (fps >= 0) {
        NSMutableString *line = [NSMutableString stringWithFormat:@"%.0f FPS", fps];
        if (self.showFrameTime && frameTime > 0) [line appendFormat:@" · %.1f ms", frameTime];
        if (self.showFifo) [line appendFormat:@" · FIFO %.0f%%", fifo];
        [lines addObject:line];
    }
    NSMutableArray<NSString *> *system = [NSMutableArray new];
    if (self.showMemory) {
        uint64_t used = OSHUDFootprint();
        uint64_t available = (uint64_t)os_proc_available_memory();
        [system addObject:[NSString stringWithFormat:english ? @"RAM %@ GB · free %@ GB" : @"RAM %@ GB · libre %@ GB",
                           OSHUDGigabytes(used), OSHUDGigabytes(available)]];
        if (self.donatedBytes > 0) {
            [system addObject:[NSString stringWithFormat:english ? @"Donated %@ GB" : @"Donada %@ GB", OSHUDGigabytes(self.donatedBytes)]];
        }
    }
    if (self.showThermal) {
        [system addObject:[NSString stringWithFormat:english ? @"Temp. %@" : @"Temp. %@", [self thermalText]]];
    }
    if (self.showBattery) {
        float level = UIDevice.currentDevice.batteryLevel;
        if (level >= 0) [system addObject:[NSString stringWithFormat:english ? @"Battery %.0f%%" : @"Batería %.0f%%", level * 100.0f]];
    }
    if (system.count > 0) [lines addObject:[system componentsJoinedByString:@" · "]];
    NSString *text = [lines componentsJoinedByString:@"\n"];
    self.text = text.length > 0 ? [NSString stringWithFormat:@" %@ ", [text stringByReplacingOccurrencesOfString:@"\n" withString:@" \n "]] : @"";
    self.hidden = text.length == 0;
}

- (CGSize)fittingSize {
    CGSize size = [self sizeThatFits:CGSizeMake(420, 200)];
    return CGSizeMake(ceil(size.width) + 8, ceil(size.height) + 6);
}

@end
