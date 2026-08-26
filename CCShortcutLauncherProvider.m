#import "CCShortcutLauncherProvider.h"
#import "CCShortcutLauncher.h"
#import "CSLDiagnostics.h"
#import "CSLModuleIcon.h"
#import "CSLSlotPreferences.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>

@implementation CCShortcutLauncherProvider

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            // Settings creates a provider whenever it builds the Control Center
            // module list. SpringBoard, meanwhile, still holds the module list
            // it cached at launch, so a module added right after would need a
            // respring. Nudge SpringBoard to re-read providers instead.
            BOOL isSpringBoard = [NSBundle.mainBundle.bundleIdentifier
                isEqualToString:@"com.apple.springboard"];
            if (!isSpringBoard) {
                CSLRequestControlCenterModuleReload();
            }
        });
    }
    return self;
}

/// The preference bundle owns the slot editor. Its path is derived from this
/// bundle so the code stays correct on both rootless and rootful prefixes.
- (NSBundle *)preferenceBundle {
    NSString *providerPath = [NSBundle bundleForClass:self.class].bundlePath;
    NSRange marker = [providerPath rangeOfString:@"/Library/ControlCenter/"];
    NSString *prefix = marker.location != NSNotFound
        ? [providerPath substringToIndex:marker.location]
        : @"";
    NSString *path = [prefix stringByAppendingString:
        @"/Library/PreferenceBundles/CCShortcutLauncherPrefs.bundle"];
    return [NSBundle bundleWithPath:path];
}

- (NSUInteger)numberOfProvidedModules {
    return CSLModuleSlotCount();
}

- (NSString *)identifierForModuleAtIndex:(NSUInteger)index {
    if (index >= CSLModuleSlotCount()) {
        return nil;
    }
    return CSLModuleIdentifierForSlot(index);
}

- (NSUInteger)slotForModuleIdentifier:(NSString *)identifier {
    NSUInteger slot = CSLSlotForModuleIdentifier(identifier);
    if (slot == NSNotFound || slot >= CSLModuleSlotCount()) {
        return NSNotFound;
    }
    return slot;
}

- (id)moduleInstanceForModuleIdentifier:(NSString *)identifier {
    NSUInteger slot = [self slotForModuleIdentifier:identifier];
    if (slot == NSNotFound) {
        return nil;
    }
    return [[CCShortcutLauncher alloc] initWithSlot:slot];
}

- (NSString *)displayNameForModuleIdentifier:(NSString *)identifier {
    NSUInteger slot = [self slotForModuleIdentifier:identifier];
    if (slot == NSNotFound) {
        return @"CCShortcutLauncher";
    }
    return CSLDisplayNameForSlot(slot);
}

- (UIImage *)settingsIconForModuleIdentifier:(NSString *)identifier {
    NSUInteger slot = [self slotForModuleIdentifier:identifier];
    if (slot == NSNotFound) {
        return nil;
    }

    NSArray<NSDictionary<NSString *, id> *> *entries = CSLEntriesForSlot(slot);
    CSLIconDiagnosticLog(
        @"[CCShortcutLauncher][Icon] SETTINGS_ICON_REQUEST slot=%lu entries=%lu",
        (unsigned long)slot,
        (unsigned long)entries.count
    );
    return CSLModuleControlCenterSettingsIconForSlot(
        slot,
        entries,
        CGSizeMake(29.0, 29.0)
    );
}

- (BOOL)providesListControllerForModuleIdentifier:(NSString *)identifier {
    return [self slotForModuleIdentifier:identifier] != NSNotFound;
}

- (id)listControllerForModuleIdentifier:(NSString *)identifier {
    NSUInteger slot = [self slotForModuleIdentifier:identifier];
    if (slot == NSNotFound) {
        return nil;
    }

    NSBundle *bundle = [self preferenceBundle];
    NSError *error = nil;
    if (bundle != nil && !bundle.isLoaded && ![bundle loadAndReturnError:&error]) {
        NSLog(@"[CCShortcutLauncher][Provider] PREFS_BUNDLE_LOAD_FAILED error=%@", error);
        return nil;
    }

    Class controllerClass = NSClassFromString(@"CSLShortcutOrderController");
    if (controllerClass == Nil) {
        NSLog(@"[CCShortcutLauncher][Provider] SLOT_CONTROLLER_MISSING slot=%lu",
              (unsigned long)slot);
        return nil;
    }

    id controller = [controllerClass alloc];
    SEL initializer = NSSelectorFromString(@"initWithSlot:");
    if (![controller respondsToSelector:initializer]) {
        return nil;
    }
    return ((id (*)(id, SEL, NSUInteger))objc_msgSend)(controller, initializer, slot);
}

@end
