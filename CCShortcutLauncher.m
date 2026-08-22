#import "CCShortcutLauncher.h"
#import "CCShortcutLauncherBackgroundRunner.h"
#import "CSLShortcutIcon.h"

#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static CFStringRef const CCShortcutLauncherPreferencesDomain =
    CFSTR("com.dinhnguyenx.ccshortcutlauncher");

static id CSLObjectIvarValue(id object, const char *name) {
    if (object == nil || name == NULL) {
        return nil;
    }
    Ivar ivar = class_getInstanceVariable([object class], name);
    if (ivar == NULL) {
        return nil;
    }
    const char *type = ivar_getTypeEncoding(ivar);
    if (type == NULL || type[0] != '@') {
        return nil;
    }
    return object_getIvar(object, ivar);
}

static void CSLCollectViewControllers(
    id object,
    NSMutableArray<UIViewController *> *controllers,
    NSMutableSet<NSValue *> *visited,
    NSUInteger depth
) {
    if (object == nil || depth > 4) {
        return;
    }
    NSValue *identity = [NSValue valueWithPointer:(__bridge const void *)object];
    if ([visited containsObject:identity]) {
        return;
    }
    [visited addObject:identity];

    if ([object isKindOfClass:[UIViewController class]]) {
        [controllers addObject:(UIViewController *)object];
        return;
    }

    NSArray *children = nil;
    if ([object isKindOfClass:[NSArray class]]) {
        children = object;
    } else if ([object isKindOfClass:[NSDictionary class]]) {
        children = [(NSDictionary *)object allValues];
    } else if ([object isKindOfClass:[NSSet class]]) {
        children = [(NSSet *)object allObjects];
    } else if ([object isKindOfClass:[NSMapTable class]]) {
        children = [[(NSMapTable *)object objectEnumerator] allObjects];
    } else if ([object isKindOfClass:[NSHashTable class]]) {
        children = [(NSHashTable *)object allObjects];
    }

    for (id child in children) {
        CSLCollectViewControllers(child, controllers, visited, depth + 1);
    }
}

@interface CCShortcutLauncher ()
- (UIViewController *)popupPresenter;
- (void)presentShortcutPopup;
@end

@implementation CCShortcutLauncher

- (UIImage *)iconGlyph {
    return [UIImage systemImageNamed:@"square.grid.2x2"];
}

- (UIImage *)selectedIconGlyph {
    return [UIImage systemImageNamed:@"square.grid.2x2.fill"];
}

- (UIColor *)selectedColor {
    return [UIColor systemIndigoColor];
}

// This module is a momentary menu button, not an on/off toggle.
- (BOOL)isSelected {
    return NO;
}

- (void)setSelected:(BOOL)selected {
    if (!selected) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self presentShortcutPopup];
        [self refreshState];
    });
}

- (id)preferenceObjectForKey:(CFStringRef)key {
    CFPreferencesAppSynchronize(CCShortcutLauncherPreferencesDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue(
        key,
        CCShortcutLauncherPreferencesDomain
    );
    return value != NULL ? CFBridgingRelease(value) : nil;
}

- (NSArray<NSDictionary<NSString *, id> *> *)shortcutCatalog {
    id object = [self preferenceObjectForKey:CFSTR("ShortcutsCatalog")];
    if (![object isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *catalog =
        [NSMutableArray array];
    for (id item in (NSArray *)object) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }

        id nameValue = ((NSDictionary *)item)[@"name"];
        id identifierValue = ((NSDictionary *)item)[@"workflowID"];
        if (![nameValue isKindOfClass:[NSString class]] ||
            ![identifierValue isKindOfClass:[NSString class]]) {
            continue;
        }

        NSString *shortcutName =
            [(NSString *)nameValue stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:(NSString *)identifierValue];
        if (shortcutName.length == 0 || uuid == nil) {
            continue;
        }

        NSMutableDictionary<NSString *, id> *entry = [@{
            @"name": shortcutName,
            @"workflowID": uuid.UUIDString,
        } mutableCopy];
        id glyphValue = ((NSDictionary *)item)[@"iconGlyph"];
        id colorValue = ((NSDictionary *)item)[@"iconColor"];
        if ([glyphValue isKindOfClass:[NSNumber class]]) {
            entry[@"iconGlyph"] = glyphValue;
        }
        if ([colorValue isKindOfClass:[NSNumber class]]) {
            entry[@"iconColor"] = colorValue;
        }
        [catalog addObject:entry];
    }

    [catalog sortUsingComparator:^NSComparisonResult(
        NSDictionary<NSString *, id> *left,
        NSDictionary<NSString *, id> *right
    ) {
        NSComparisonResult nameResult =
            [left[@"name"] localizedCaseInsensitiveCompare:right[@"name"]];
        if (nameResult != NSOrderedSame) {
            return nameResult;
        }
        return [left[@"workflowID"] compare:right[@"workflowID"]];
    }];
    return catalog;
}

- (NSArray<NSDictionary<NSString *, id> *> *)popupCatalogFromCatalog:
    (NSArray<NSDictionary<NSString *, id> *> *)catalog {
    id savedValue = [self preferenceObjectForKey:CFSTR("PopupShortcutIDs")];
    if (![savedValue isKindOfClass:[NSArray class]]) {
        return catalog;
    }

    NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *byIdentifier =
        [NSMutableDictionary dictionary];
    for (NSDictionary<NSString *, id> *entry in catalog) {
        byIdentifier[entry[@"workflowID"]] = entry;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *popupCatalog =
        [NSMutableArray array];
    NSMutableSet<NSString *> *seenIdentifiers = [NSMutableSet set];
    for (id value in (NSArray *)savedValue) {
        if (![value isKindOfClass:[NSString class]]) {
            continue;
        }
        NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:(NSString *)value];
        NSString *identifier = uuid.UUIDString;
        NSDictionary *entry = identifier != nil ? byIdentifier[identifier] : nil;
        if (entry != nil && ![seenIdentifiers containsObject:identifier]) {
            [popupCatalog addObject:entry];
            [seenIdentifiers addObject:identifier];
        }
    }
    return popupCatalog;
}

- (void)runShortcutNamed:(NSString *)shortcutName
             workflowID:(NSString *)workflowIdentifier {
    CSLBackgroundStartResult result =
        CSLStartBackgroundShortcutNamed(shortcutName, workflowIdentifier);
    if (result != CSLBackgroundStartResultSubmitted) {
        NSLog(@"[CCShortcutLauncher][Popup] RUN_REJECTED name=\"%@\" result=%ld",
              shortcutName,
              (long)result);
    }
}

- (NSString *)displayTitleForEntry:(NSDictionary<NSString *, id> *)entry
                         nameCounts:(NSDictionary<NSString *, NSNumber *> *)nameCounts {
    NSString *shortcutName = entry[@"name"];
    NSString *countKey = shortcutName.lowercaseString;
    if (nameCounts[countKey].unsignedIntegerValue < 2) {
        return shortcutName;
    }

    NSString *identifier = entry[@"workflowID"];
    NSString *shortIdentifier = identifier.length >= 8
        ? [identifier substringToIndex:8]
        : identifier;
    return [NSString stringWithFormat:@"%@ \u00b7 %@", shortcutName, shortIdentifier];
}

- (UIViewController *)popupPresenter {
    NSMutableArray<UIViewController *> *controllers = [NSMutableArray array];
    NSMutableSet<NSValue *> *visited = [NSMutableSet set];

    @try {
        SEL contentSelector = NSSelectorFromString(@"contentViewController");
        if ([self respondsToSelector:contentSelector]) {
            id controller = ((id (*)(id, SEL))objc_msgSend)(self, contentSelector);
            CSLCollectViewControllers(controller, controllers, visited, 0);
        }

        const char *ivarNames[] = {
            "_contentViewControllers",
            "_contentViewController",
        };
        for (NSUInteger index = 0; index < sizeof(ivarNames) / sizeof(ivarNames[0]); index++) {
            id container = CSLObjectIvarValue(self, ivarNames[index]);
            if (container == nil) {
                continue;
            }
            CSLCollectViewControllers(container, controllers, visited, 0);
        }
    } @catch (NSException *exception) {
        NSLog(@"[CCShortcutLauncher][Popup] PRESENTER_DISCOVERY_EXCEPTION exception=%@ reason=%@",
              exception.name,
              exception.reason);
        return nil;
    }

    for (UIViewController *controller in controllers) {
        if (controller.isViewLoaded && controller.view.window != nil) {
            return controller;
        }
    }
    NSLog(@"[CCShortcutLauncher][Popup] PRESENTER_NOT_FOUND candidates=%lu",
          (unsigned long)controllers.count);
    return nil;
}

- (void)presentShortcutPopup {
    @try {
        UIViewController *presenter = [self popupPresenter];
        if (presenter == nil) {
            return;
        }
        if (presenter.presentedViewController != nil) {
            return;
        }

        NSArray<NSDictionary<NSString *, id> *> *loadedCatalog =
            [self shortcutCatalog];
        NSArray<NSDictionary<NSString *, id> *> *catalog =
            [self popupCatalogFromCatalog:loadedCatalog];
        NSString *message = nil;
        if (catalog.count > 0) {
            message = [NSString stringWithFormat:@"%lu Shortcut%@ included",
                (unsigned long)catalog.count,
                catalog.count == 1 ? @"" : @"s"];
        } else if (loadedCatalog.count > 0) {
            message = @"Open Settings \u2192 Shortcut Launcher \u2192 Manage Popup Shortcuts.";
        } else {
            message = @"Open Settings \u2192 Shortcut Launcher and tap Load My Shortcuts.";
        }
        UIAlertController *popup = [UIAlertController
            alertControllerWithTitle:@"My Shortcuts"
                             message:message
                      preferredStyle:UIAlertControllerStyleActionSheet];

        NSMutableDictionary<NSString *, NSNumber *> *nameCounts =
            [NSMutableDictionary dictionary];
        for (NSDictionary<NSString *, id> *entry in catalog) {
            NSString *countKey = [entry[@"name"] lowercaseString];
            nameCounts[countKey] = @(nameCounts[countKey].unsignedIntegerValue + 1);
        }

        __weak typeof(self) weakSelf = self;
        for (NSDictionary<NSString *, id> *entry in catalog) {
            NSString *title = [self displayTitleForEntry:entry nameCounts:nameCounts];
            NSString *shortcutName = entry[@"name"];
            NSString *workflowIdentifier = entry[@"workflowID"];
            UIAlertAction *shortcutAction =
                [UIAlertAction actionWithTitle:title
                                         style:UIAlertActionStyleDefault
                                       handler:^(__unused UIAlertAction *action) {
                [weakSelf runShortcutNamed:shortcutName workflowID:workflowIdentifier];
            }];
            UIImage *shortcutIcon =
                CSLShortcutIconImageForEntry(entry, CGSizeMake(28.0, 28.0));
            CSLSetImageForAlertActionIfSupported(shortcutAction, shortcutIcon);
            [popup addAction:shortcutAction];
        }

        [popup addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                 style:UIAlertActionStyleCancel
                                               handler:nil]];

        UIPopoverPresentationController *popover = popup.popoverPresentationController;
        if (popover != nil) {
            popover.sourceView = presenter.view;
            popover.sourceRect = CGRectMake(
                CGRectGetMidX(presenter.view.bounds),
                CGRectGetMidY(presenter.view.bounds),
                1.0,
                1.0
            );
            popover.permittedArrowDirections = 0;
        }

        [presenter presentViewController:popup animated:YES completion:nil];
    } @catch (NSException *exception) {
        NSLog(@"[CCShortcutLauncher][Popup] PRESENTATION_EXCEPTION exception=%@ reason=%@",
              exception.name,
              exception.reason);
    }
}

@end
