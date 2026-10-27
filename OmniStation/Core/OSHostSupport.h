//
//  OSHostSupport.h
//  OmniStation Dock
//
//  Dónde se ejecuta OmniStation y dónde están sus extensiones (JIT y memoria).
//  - Instalada con SideStore: en su propio PlugIns.
//  - Integrada en LiveContainer (fork LiveContainer-OmniStation): OmniStation va en
//    LiveContainer.app/Frameworks/OmniStationApp.framework y sus extensiones en LiveContainer.app/PlugIns.
//  - Como app instalada dentro de LiveContainer: no tiene extensiones.
//

#ifndef OSHostSupport_h
#define OSHostSupport_h

#import <Foundation/Foundation.h>
#include <stdlib.h>

/// ¿OmniStation integrada en LiveContainer?
static inline BOOL OSIsBuiltIntoLiveContainer(void) {
    if (getenv("LC_HOME_PATH") == NULL) return NO;
    return [NSBundle.mainBundle.bundleURL.lastPathComponent isEqualToString:@"OmniStationApp.framework"];
}

/// ¿Como app instalada dentro de LiveContainer (sin extensiones propias)?
static inline BOOL OSIsLiveContainerGuestWithoutExtensions(void) {
    return getenv("LC_HOME_PATH") != NULL && !OSIsBuiltIntoLiveContainer();
}

/// Carpetas donde buscar las extensiones de OmniStation.
static inline NSArray<NSURL *> *OSPlugInFolders(void) {
    NSMutableArray<NSURL *> *folders = [NSMutableArray array];
    NSURL *own = NSBundle.mainBundle.builtInPlugInsURL;
    if (own != nil) [folders addObject:own];
    if (OSIsBuiltIntoLiveContainer()) {
        // .../LiveContainer.app/Frameworks/OmniStationApp.framework → .../LiveContainer.app/PlugIns
        NSURL *host = NSBundle.mainBundle.bundleURL.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent;
        [folders addObject:[host URLByAppendingPathComponent:@"PlugIns" isDirectory:YES]];
    }
    return folders;
}

#endif /* OSHostSupport_h */
