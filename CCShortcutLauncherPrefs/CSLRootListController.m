#import "CSLRootListController.h"
#import "CSLShortcutOrderController.h"
#import "../CSLShortcutIcon.h"
#import "../CSLSlotPreferences.h"

#import <CoreFoundation/CoreFoundation.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>

static CFStringRef const CSLPreferencesDomain =
    CFSTR("com.dinhnguyenx.ccshortcutlauncher");
static CFStringRef const CSLCatalogRequestedNotification =
    CFSTR("com.dinhnguyenx.ccshortcutlauncher/catalogRequested");
/// Declared here because the Preferences headers do not always ship it.
@interface PSListController (CSLSpecifierLookup)
- (PSSpecifier *)specifierAtIndexPath:(NSIndexPath *)indexPath;
@end

static NSString *const CSLSlotSpecifierKey = @"CSLSlot";
static NSString *const CSLDiagnosticSpecifierKey = @"CSLDiagnostic";
/// Preferences reads this property to draw the icon on the left of a row.
static NSString *const CSLSpecifierIconKey = @"iconImage";
static const CGFloat CSLSpecifierIconSide = 29.0;

@implementation CSLRootListController

- (NSArray *)specifiers {
    if (_specifiers == nil) {
        CSLMigrateLegacySelectionIfNeeded();

        NSMutableArray *specifiers =
            [[self loadSpecifiersFromPlistName:@"Root" target:self] mutableCopy];

        NSUInteger slotCount = CSLModuleSlotCount();
        for (NSUInteger slot = 0; slot < slotCount; slot++) {
            PSSpecifier *specifier =
                [PSSpecifier preferenceSpecifierNamed:CSLDisplayNameForSlot(slot)
                                               target:self
                                                  set:NULL
                                                  get:@selector(shortcutSummaryForSpecifier:)
                                               detail:Nil
                                                 cell:PSLinkCell
                                                 edit:Nil];
            specifier->action = @selector(openModuleSlot:);
            [specifier setProperty:@(slot) forKey:CSLSlotSpecifierKey];
            [specifier setProperty:[self iconForSlot:slot] forKey:CSLSpecifierIconKey];
            [specifiers addObject:specifier];
        }

        PSSpecifier *diagnosticsGroup = [PSSpecifier emptyGroupSpecifier];
        [diagnosticsGroup setProperty:@"DIAGNOSTICS" forKey:@"label"];
        [diagnosticsGroup setProperty:@"What the last read of the Shortcuts database found."
                               forKey:@"footerText"];
        [specifiers addObject:diagnosticsGroup];

        NSArray<NSArray<NSString *> *> *diagnostics = @[
            @[@"Cached Shortcuts", @"cachedShortcuts"],
            @[@"Glyph Icons", @"glyphIcons"],
            @[@"App Icons", @"appIcons"],
            @[@"App Column", @"appColumn"],
            @[@"Last Reload", @"lastReload"],
        ];
        for (NSArray<NSString *> *diagnostic in diagnostics) {
            PSSpecifier *specifier =
                [PSSpecifier preferenceSpecifierNamed:diagnostic[0]
                                               target:self
                                                  set:NULL
                                                  get:@selector(diagnosticValueForSpecifier:)
                                               detail:Nil
                                                 cell:PSTitleValueCell
                                                 edit:Nil];
            [specifier setProperty:diagnostic[1] forKey:CSLDiagnosticSpecifierKey];
            [specifiers addObject:specifier];
        }

        PSSpecifier *respringGroup = [PSSpecifier emptyGroupSpecifier];
        [respringGroup setProperty:@"Changes apply without a respring. Use this only if Control Center does not pick a change up."
                            forKey:@"footerText"];
        [specifiers addObject:respringGroup];

        PSSpecifier *respring = [PSSpecifier preferenceSpecifierNamed:@"Respring"
                                                               target:self
                                                                  set:NULL
                                                                  get:NULL
                                                               detail:Nil
                                                                 cell:PSButtonCell
                                                                 edit:Nil];
        respring->action = @selector(confirmRespring);
        [specifiers addObject:respring];

        PSSpecifier *footer = [PSSpecifier emptyGroupSpecifier];
        [footer setProperty:@"Version 1.4.5 · Run selected Shortcuts in the background from Control Center."
                     forKey:@"footerText"];
        [specifiers addObject:footer];

        _specifiers = [specifiers copy];
    }

    return _specifiers;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // The module count and the module names can both change on the pages this
    // controller pushes, so the slot rows are rebuilt on every appearance.
    [self reloadSpecifiers];
}

/// Returns NSNotFound for the rows that are not a module.
- (NSUInteger)slotForSpecifier:(PSSpecifier *)specifier {
    id slotValue = [specifier propertyForKey:CSLSlotSpecifierKey];
    if (![slotValue isKindOfClass:[NSNumber class]]) {
        return NSNotFound;
    }
    return [(NSNumber *)slotValue unsignedIntegerValue];
}

/// Mirrors what Control Center shows: a module holding one Shortcut wears that
/// Shortcut's icon, anything else falls back to the generic grid.
- (UIImage *)iconForSlot:(NSUInteger)slot {
    NSArray<NSDictionary<NSString *, id> *> *entries = CSLEntriesForSlot(slot);
    if (entries.count == 1) {
        return CSLShortcutIconImageForEntry(
            entries.firstObject,
            CGSizeMake(CSLSpecifierIconSide, CSLSpecifierIconSide)
        );
    }

    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:20.0
                                                        weight:UIImageSymbolWeightRegular];
    UIImage *symbol = [UIImage systemImageNamed:@"square.grid.2x2"
                              withConfiguration:configuration];
    return [symbol imageWithTintColor:[UIColor systemGrayColor]
                        renderingMode:UIImageRenderingModeAlwaysOriginal];
}

- (id)shortcutSummaryForSpecifier:(PSSpecifier *)specifier {
    NSUInteger slot = [self slotForSpecifier:specifier];
    if (slot == NSNotFound) {
        return nil;
    }

    NSUInteger count = CSLEntriesForSlot(slot).count;
    if (count == 0) {
        return @"None";
    }
    return [NSString stringWithFormat:@"%lu Shortcut%@",
        (unsigned long)count,
        count == 1 ? @"" : @"s"];
}

- (void)tableView:(UITableView *)tableView
    willDisplayCell:(UITableViewCell *)cell
  forRowAtIndexPath:(NSIndexPath *)indexPath {
    // Preferences themes its own cells here, but do not assume the superclass
    // implements an optional delegate method.
    if ([PSListController instancesRespondToSelector:_cmd]) {
        [super tableView:tableView willDisplayCell:cell forRowAtIndexPath:indexPath];
    }

    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    NSUInteger slot = [self slotForSpecifier:specifier];
    if (slot == NSNotFound) {
        return;
    }

    // Indent the modules so they read as entries under the count above them.
    cell.indentationLevel = 1;
    cell.indentationWidth = 16.0;

    // The specifier already carries the icon and the summary, but a plain link
    // cell does not always draw them, so fill in whatever is still empty.
    if (cell.imageView.image == nil) {
        cell.imageView.image = [self iconForSlot:slot];
    }
    if (cell.detailTextLabel.text.length == 0) {
        cell.detailTextLabel.text = [self shortcutSummaryForSpecifier:specifier];
    }
}

- (id)diagnosticValueForSpecifier:(PSSpecifier *)specifier {
    id key = [specifier propertyForKey:CSLDiagnosticSpecifierKey];
    if (![key isKindOfClass:[NSString class]]) {
        return nil;
    }

    if ([key isEqualToString:@"cachedShortcuts"]) {
        return [NSString stringWithFormat:@"%lu",
            (unsigned long)CSLShortcutCatalog().count];
    }
    if ([key isEqualToString:@"glyphIcons"]) {
        return [self numberStringForKey:CFSTR("ResolverGlyphIconCount")];
    }
    if ([key isEqualToString:@"appIcons"]) {
        return [self numberStringForKey:CFSTR("ResolverAppIconCount")];
    }
    if ([key isEqualToString:@"appColumn"]) {
        NSString *column = [self preferenceStringForKey:CFSTR("ResolverAppColumn")];
        return column.length > 0 ? column : @"—";
    }
    if ([key isEqualToString:@"lastReload"]) {
        id value = [self preferenceValueForKey:CFSTR("ResolverLastLoadDate")];
        if (![value isKindOfClass:[NSDate class]]) {
            return @"Never";
        }
        return [NSDateFormatter localizedStringFromDate:(NSDate *)value
                                              dateStyle:NSDateFormatterShortStyle
                                              timeStyle:NSDateFormatterShortStyle];
    }
    return nil;
}

- (NSString *)numberStringForKey:(CFStringRef)key {
    id value = [self preferenceValueForKey:key];
    if (![value isKindOfClass:[NSNumber class]]) {
        return @"—";
    }
    return [(NSNumber *)value stringValue];
}

- (void)confirmRespring {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Respring"
                         message:@"SpringBoard restarts. Anything you have open is closed."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Respring"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *action) {
        [self respring];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

/// Settings cannot spawn sbreload, so ask the render server to restart the way
/// SpringBoard itself does.
- (void)respring {
    Class relaunchActionClass = NSClassFromString(@"SBSRelaunchAction");
    Class systemServiceClass = NSClassFromString(@"FBSSystemService");
    if (relaunchActionClass == Nil || systemServiceClass == Nil) {
        [self showMessageWithTitle:@"Respring Unavailable"
                           message:@"Restart SpringBoard from your package manager or a terminal instead."];
        return;
    }

    @try {
        id action = ((id (*)(id, SEL, id, NSUInteger, id))objc_msgSend)(
            relaunchActionClass,
            NSSelectorFromString(@"actionWithReason:options:targetURL:"),
            @"RestartRenderServer",
            4,
            nil
        );
        id service = ((id (*)(id, SEL))objc_msgSend)(
            systemServiceClass,
            NSSelectorFromString(@"sharedService")
        );
        if (action == nil || service == nil) {
            return;
        }
        ((void (*)(id, SEL, id, id))objc_msgSend)(
            service,
            NSSelectorFromString(@"sendActions:withResult:"),
            [NSSet setWithObject:action],
            nil
        );
    } @catch (NSException *exception) {
        NSLog(@"[CCShortcutLauncher][Settings] RESPRING_EXCEPTION exception=%@ reason=%@",
              exception.name,
              exception.reason);
    }
}

- (void)openModuleSlot:(PSSpecifier *)specifier {
    NSUInteger slot = [self slotForSpecifier:specifier];
    CSLShortcutOrderController *controller =
        [[CSLShortcutOrderController alloc] initWithSlot:slot == NSNotFound ? 0 : slot];
    [self.navigationController pushViewController:controller animated:YES];
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

            if ([state isEqualToString:@"catalog_ready"]) {
                // Zero is a valid result: every Shortcut may have been deleted.
                NSString *message = count > 0
                    ? [NSString stringWithFormat:
                        @"Cached %lu Shortcuts. Open a module below to choose which ones it runs.",
                        (unsigned long)count]
                    : @"No Shortcuts were found in My Shortcuts. The modules are now empty.";
                [self finishLoadingWithTitle:@"My Shortcuts Loaded" message:message];
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

@end
