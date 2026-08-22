#import "CSLRootListController.h"
#import "CSLShortcutOrderController.h"

#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>

static CFStringRef const CSLPreferencesDomain =
    CFSTR("com.dinhnguyenx.ccshortcutlauncher");
static CFStringRef const CSLCatalogRequestedNotification =
    CFSTR("com.dinhnguyenx.ccshortcutlauncher/catalogRequested");

@implementation CSLRootListController

- (NSArray *)specifiers {
    if (_specifiers == nil) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }

    return _specifiers;
}

- (id)preferenceValueForKey:(CFStringRef)key {
    CFPreferencesAppSynchronize(CSLPreferencesDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue(key, CSLPreferencesDomain);
    if (value == NULL) {
        return nil;
    }

    return CFBridgingRelease(value);
}

- (NSString *)preferenceStringForKey:(CFStringRef)key {
    id object = [self preferenceValueForKey:key];
    if (![object isKindOfClass:[NSString class]]) {
        return nil;
    }
    return [(NSString *)object stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (void)showMessageWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)finishLoadingWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *loadingAlert = _loadingAlert;
    _loadingAlert = nil;
    if (loadingAlert.presentingViewController != nil) {
        [loadingAlert dismissViewControllerAnimated:YES completion:^{
            [self showMessageWithTitle:title message:message];
        }];
    } else {
        [self showMessageWithTitle:title message:message];
    }
}

- (void)pollCatalogWithGeneration:(NSUInteger)generation
                          attempt:(NSUInteger)attempt {
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
        dispatch_get_main_queue(),
        ^{
            if (generation != self->_resolveGeneration) {
                return;
            }

            NSString *state = [self preferenceStringForKey:CFSTR("ResolverState")];
            id catalogValue = [self preferenceValueForKey:CFSTR("ShortcutsCatalog")];
            NSUInteger count = [catalogValue isKindOfClass:[NSArray class]]
                ? [(NSArray *)catalogValue count]
                : 0;

            if ([state isEqualToString:@"catalog_ready"] && count > 0) {
                [self finishLoadingWithTitle:@"My Shortcuts Loaded"
                                      message:[NSString stringWithFormat:
                                          @"Loaded %lu Shortcuts. Open Manage Popup Shortcuts to choose and arrange them.",
                                          (unsigned long)count]];
                return;
            }

            if ([state isEqualToString:@"error"]) {
                NSString *errorMessage =
                    [self preferenceStringForKey:CFSTR("ResolverMessage")];
                [self finishLoadingWithTitle:@"Unable to Load My Shortcuts"
                                      message:errorMessage.length > 0
                                          ? errorMessage
                                          : @"Unlock the device and try again."];
                return;
            }

            if (attempt >= 39) {
                [self finishLoadingWithTitle:@"Catalog Load Timed Out"
                                      message:@"The resolver did not respond. Check the system log and try again."];
                return;
            }

            [self pollCatalogWithGeneration:generation attempt:attempt + 1];
        }
    );
}

- (void)loadMyShortcuts {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_resolveGeneration++;
        NSUInteger generation = self->_resolveGeneration;

        CFPreferencesSetAppValue(
            CFSTR("ResolverState"),
            CFSTR("catalog_requested"),
            CSLPreferencesDomain
        );
        CFPreferencesSetAppValue(CFSTR("ResolverMessage"), NULL, CSLPreferencesDomain);
        CFPreferencesAppSynchronize(CSLPreferencesDomain);

        self->_loadingAlert = [UIAlertController alertControllerWithTitle:@"Loading My Shortcuts"
                                                                  message:@"Reading names, identifiers, and icons once\u2026"
                                                           preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:self->_loadingAlert animated:YES completion:nil];

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CSLCatalogRequestedNotification,
            NULL,
            NULL,
            true
        );
        [self pollCatalogWithGeneration:generation attempt:0];
    });
}

- (void)managePopupShortcuts {
    CSLShortcutOrderController *controller =
        [[CSLShortcutOrderController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    [self.navigationController pushViewController:controller animated:YES];
}

@end
