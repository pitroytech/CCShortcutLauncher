#import "CCShortcutLauncherProvider.h"
#import "CCShortcutLauncher.h"

#import <UIKit/UIKit.h>

static NSString *const CSLModuleIdentifier =
    @"com.dinhnguyenx.ccshortcutlauncher";

@implementation CCShortcutLauncherProvider

- (NSUInteger)numberOfProvidedModules {
    return 1;
}

- (NSString *)identifierForModuleAtIndex:(NSUInteger)index {
    return index == 0 ? CSLModuleIdentifier : nil;
}

- (id)moduleInstanceForModuleIdentifier:(NSString *)identifier {
    if (![identifier isEqualToString:CSLModuleIdentifier]) {
        return nil;
    }
    return [[CCShortcutLauncher alloc] init];
}

- (NSString *)displayNameForModuleIdentifier:(NSString *)identifier {
    return @"Shortcut Launcher";
}

- (UIImage *)settingsIconForModuleIdentifier:(NSString *)identifier {
    if (![identifier isEqualToString:CSLModuleIdentifier]) {
        return nil;
    }
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    return [UIImage imageNamed:@"CCShortcutLauncherIcon"
                      inBundle:bundle
 compatibleWithTraitCollection:nil];
}

@end
