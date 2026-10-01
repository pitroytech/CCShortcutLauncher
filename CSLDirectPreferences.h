#import "PTPreferenceStore.h"
#import <rootless.h>
#define CSL_DIRECT_PATH ROOT_PATH_NS(@"/var/mobile/Library/Preferences/com.dinhnguyenx.ccshortcutlauncher.direct.plist")
static inline PTPreferenceStore *CSLDirectStore(void) {
    static PTPreferenceStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        store = [[PTPreferenceStore alloc] initWithPath:CSL_DIRECT_PATH
            legacyPaths:@[ROOT_PATH_NS(@"/var/mobile/Library/Preferences/com.dinhnguyenx.ccshortcutlauncher.plist"),
                          @"/var/mobile/Library/Preferences/com.dinhnguyenx.ccshortcutlauncher.plist"]];
    });
    return store;
}
