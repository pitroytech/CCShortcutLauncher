#import "CSLShortcutOrderController.h"
#import "../CSLShortcutIcon.h"

#import <CoreFoundation/CoreFoundation.h>

static CFStringRef const CSLOrderPreferencesDomain =
    CFSTR("com.dinhnguyenx.ccshortcutlauncher");

@interface CSLShortcutOrderController ()
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *catalog;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *includedEntries;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *availableEntries;
@property (nonatomic, strong) NSMutableArray<NSString *> *selectedIdentifiers;
@end

@implementation CSLShortcutOrderController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Popup Shortcuts";
    self.tableView.allowsSelectionDuringEditing = NO;
    self.tableView.rowHeight = 58.0;
    [self setEditing:YES animated:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadModel];
}

- (id)preferenceValueForKey:(CFStringRef)key {
    CFPreferencesAppSynchronize(CSLOrderPreferencesDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue(key, CSLOrderPreferencesDomain);
    return value != NULL ? CFBridgingRelease(value) : nil;
}

- (NSArray<NSDictionary<NSString *, id> *> *)validatedCatalogFromValue:(id)value {
    if (![value isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *catalog =
        [NSMutableArray array];
    NSMutableSet<NSString *> *seenIdentifiers = [NSMutableSet set];
    for (id item in (NSArray *)value) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        id nameValue = ((NSDictionary *)item)[@"name"];
        id identifierValue = ((NSDictionary *)item)[@"workflowID"];
        if (![nameValue isKindOfClass:[NSString class]] ||
            ![identifierValue isKindOfClass:[NSString class]]) {
            continue;
        }

        NSString *name = [(NSString *)nameValue stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:(NSString *)identifierValue];
        if (name.length == 0 || uuid == nil ||
            [seenIdentifiers containsObject:uuid.UUIDString]) {
            continue;
        }
        [seenIdentifiers addObject:uuid.UUIDString];
        NSMutableDictionary<NSString *, id> *entry = [@{
            @"name": name,
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
    return catalog;
}

- (void)reloadModel {
    self.catalog = [self validatedCatalogFromValue:
        [self preferenceValueForKey:CFSTR("ShortcutsCatalog")]];

    NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *byIdentifier =
        [NSMutableDictionary dictionary];
    for (NSDictionary<NSString *, id> *entry in self.catalog) {
        byIdentifier[entry[@"workflowID"]] = entry;
    }

    id savedValue = [self preferenceValueForKey:CFSTR("PopupShortcutIDs")];
    BOOL hasSavedSelection = [savedValue isKindOfClass:[NSArray class]];
    NSArray *savedIdentifiers = hasSavedSelection ? savedValue : @[];
    NSMutableArray<NSString *> *selected = [NSMutableArray array];
    NSMutableSet<NSString *> *selectedSet = [NSMutableSet set];

    if (hasSavedSelection) {
        for (id value in savedIdentifiers) {
            if (![value isKindOfClass:[NSString class]]) {
                continue;
            }
            NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:(NSString *)value];
            NSString *identifier = uuid.UUIDString;
            if (identifier != nil && byIdentifier[identifier] != nil &&
                ![selectedSet containsObject:identifier]) {
                [selected addObject:identifier];
                [selectedSet addObject:identifier];
            }
        }
    } else {
        for (NSDictionary<NSString *, id> *entry in self.catalog) {
            NSString *identifier = entry[@"workflowID"];
            [selected addObject:identifier];
            [selectedSet addObject:identifier];
        }
    }
    self.selectedIdentifiers = selected;

    NSMutableArray<NSDictionary<NSString *, id> *> *included =
        [NSMutableArray array];
    for (NSString *identifier in selected) {
        NSDictionary *entry = byIdentifier[identifier];
        if (entry != nil) {
            [included addObject:entry];
        }
    }
    self.includedEntries = included;

    NSMutableArray<NSDictionary<NSString *, id> *> *available =
        [NSMutableArray array];
    for (NSDictionary<NSString *, id> *entry in self.catalog) {
        if (![selectedSet containsObject:entry[@"workflowID"]]) {
            [available addObject:entry];
        }
    }
    [available sortUsingComparator:^NSComparisonResult(
        NSDictionary<NSString *, id> *left,
        NSDictionary<NSString *, id> *right
    ) {
        NSComparisonResult nameResult =
            [left[@"name"] localizedCaseInsensitiveCompare:right[@"name"]];
        return nameResult != NSOrderedSame
            ? nameResult
            : [left[@"workflowID"] compare:right[@"workflowID"]];
    }];
    self.availableEntries = available;

    if (!hasSavedSelection || ![savedIdentifiers isEqualToArray:selected]) {
        [self saveSelection];
    }
    [self.tableView reloadData];
}

- (void)rebuildSections {
    NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *byIdentifier =
        [NSMutableDictionary dictionary];
    for (NSDictionary<NSString *, id> *entry in self.catalog) {
        byIdentifier[entry[@"workflowID"]] = entry;
    }

    NSMutableArray *included = [NSMutableArray array];
    NSMutableSet *selectedSet = [NSMutableSet setWithArray:self.selectedIdentifiers];
    for (NSString *identifier in self.selectedIdentifiers) {
        NSDictionary *entry = byIdentifier[identifier];
        if (entry != nil) {
            [included addObject:entry];
        }
    }
    self.includedEntries = included;

    NSMutableArray *available = [NSMutableArray array];
    for (NSDictionary *entry in self.catalog) {
        if (![selectedSet containsObject:entry[@"workflowID"]]) {
            [available addObject:entry];
        }
    }
    [available sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        NSComparisonResult result =
            [left[@"name"] localizedCaseInsensitiveCompare:right[@"name"]];
        return result != NSOrderedSame
            ? result
            : [left[@"workflowID"] compare:right[@"workflowID"]];
    }];
    self.availableEntries = available;
}

- (void)saveSelection {
    CFPreferencesSetAppValue(
        CFSTR("PopupShortcutIDs"),
        (__bridge CFArrayRef)self.selectedIdentifiers,
        CSLOrderPreferencesDomain
    );
    BOOL synchronized = CFPreferencesAppSynchronize(CSLOrderPreferencesDomain);
    if (!synchronized) {
        NSLog(@"[CCShortcutLauncher][Settings] POPUP_SELECTION_SAVE_FAILED count=%lu",
              (unsigned long)self.selectedIdentifiers.count);
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? self.includedEntries.count : self.availableEntries.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"INCLUDED IN POPUP" : @"MORE SHORTCUTS";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0 && self.includedEntries.count == 0) {
        return @"Add at least one Shortcut below to show it in the Control Center popup.";
    }
    if (section == 1 && self.catalog.count == 0) {
        return @"Return to Shortcut Launcher and tap Load My Shortcuts first.";
    }
    if (section == 1 && self.availableEntries.count == 0) {
        return @"All loaded Shortcuts are included in the popup.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *const reuseIdentifier = @"ShortcutCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                       reuseIdentifier:reuseIdentifier];
    }

    NSDictionary<NSString *, id> *entry = indexPath.section == 0
        ? self.includedEntries[indexPath.row]
        : self.availableEntries[indexPath.row];
    NSString *identifier = entry[@"workflowID"];
    cell.textLabel.text = entry[@"name"];
    cell.detailTextLabel.text = identifier.length >= 8
        ? [identifier substringToIndex:8]
        : identifier;
    cell.imageView.image = CSLShortcutIconImageForEntry(entry, CGSizeMake(34.0, 34.0));
    cell.imageView.tintColor = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView
           editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0
        ? UITableViewCellEditingStyleDelete
        : UITableViewCellEditingStyleInsert;
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete && indexPath.section == 0) {
        NSString *identifier = self.includedEntries[indexPath.row][@"workflowID"];
        [self.selectedIdentifiers removeObject:identifier];
    } else if (editingStyle == UITableViewCellEditingStyleInsert && indexPath.section == 1) {
        NSString *identifier = self.availableEntries[indexPath.row][@"workflowID"];
        if (![self.selectedIdentifiers containsObject:identifier]) {
            [self.selectedIdentifiers addObject:identifier];
        }
    } else {
        return;
    }

    [self saveSelection];
    [self rebuildSections];
    [tableView reloadData];
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 0;
}

- (NSIndexPath *)tableView:(UITableView *)tableView
    targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath
                         toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    if (proposedDestinationIndexPath.section == 0) {
        return proposedDestinationIndexPath;
    }
    NSInteger lastRow = MAX((NSInteger)self.includedEntries.count - 1, 0);
    return [NSIndexPath indexPathForRow:lastRow inSection:0];
}

- (void)tableView:(UITableView *)tableView
    moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
           toIndexPath:(NSIndexPath *)destinationIndexPath {
    if (sourceIndexPath.section != 0 || destinationIndexPath.section != 0 ||
        sourceIndexPath.row == destinationIndexPath.row) {
        return;
    }
    NSString *identifier = self.selectedIdentifiers[sourceIndexPath.row];
    [self.selectedIdentifiers removeObjectAtIndex:sourceIndexPath.row];
    [self.selectedIdentifiers insertObject:identifier atIndex:destinationIndexPath.row];
    [self saveSelection];
    [self rebuildSections];
}

@end
