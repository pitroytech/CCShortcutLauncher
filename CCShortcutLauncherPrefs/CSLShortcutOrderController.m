#import "CSLShortcutOrderController.h"
#import "../CSLShortcutIcon.h"
#import "../CSLSlotPreferences.h"

@interface CSLShortcutOrderController ()
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *catalog;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *includedEntries;
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *availableEntries;
@property (nonatomic, strong) NSMutableArray<NSString *> *selectedIdentifiers;
@property (nonatomic, weak) id psRootController;
@property (nonatomic, weak) id psParentController;
@property (nonatomic, strong) id psSpecifier;
@end

@implementation CSLShortcutOrderController

- (instancetype)initWithSlot:(NSUInteger)slot {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self != nil) {
        _slot = slot;
    }
    return self;
}

- (instancetype)initWithStyle:(UITableViewStyle)style {
    self = [super initWithStyle:style];
    if (self != nil) {
        _slot = 0;
    }
    return self;
}

#pragma mark - PSViewController compatibility

// CCSupport pushes this controller from Settings → Control Center through the
// Preferences machinery, which sets these on any pushed controller.

- (void)setRootController:(id)controller {
    self.psRootController = controller;
}

- (id)rootController {
    return self.psRootController;
}

- (void)setParentController:(id)controller {
    self.psParentController = controller;
}

- (id)parentController {
    return self.psParentController;
}

- (void)setSpecifier:(id)specifier {
    self.psSpecifier = specifier;
}

- (id)specifier {
    return self.psSpecifier;
}

#pragma mark - Lifecycle

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.allowsSelectionDuringEditing = NO;
    self.tableView.rowHeight = 58.0;
    [self setEditing:YES animated:NO];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"Rename"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(renameModule)];
    [self updateTitle];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    CSLMigrateLegacySelectionIfNeeded();
    [self updateTitle];
    [self reloadModel];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    // The module glyph and name follow the slot contents, so refresh Control
    // Center once, on the way out, instead of on every row tap.
    CSLRequestControlCenterModuleReload();
}

- (void)updateTitle {
    self.title = CSLDisplayNameForSlot(self.slot);
}

- (void)renameModule {
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"Rename Module"
                         message:@"This name is shown in Settings → Control Center and on the popup."
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = CSLSlotName(self.slot);
        textField.placeholder = CSLDisplayNameForSlot(self.slot);
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    __weak typeof(self) weakSelf = self;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Save"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        CSLSetSlotName(weakAlert.textFields.firstObject.text, weakSelf.slot);
        [weakSelf updateTitle];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Model

- (void)reloadModel {
    self.catalog = CSLShortcutCatalog();

    NSArray<NSString *> *stored = CSLShortcutIDsForSlot(self.slot);
    NSMutableSet<NSString *> *catalogIdentifiers = [NSMutableSet set];
    for (NSDictionary<NSString *, id> *entry in self.catalog) {
        [catalogIdentifiers addObject:entry[@"workflowID"]];
    }

    // Identifiers of deleted Shortcuts have to go. While they stayed in the
    // list, the rows the table showed and the identifiers behind them ran out
    // of step, so dragging a row reordered the wrong entry.
    NSMutableArray<NSString *> *live = [NSMutableArray array];
    for (NSString *identifier in stored) {
        if ([catalogIdentifiers containsObject:identifier]) {
            [live addObject:identifier];
        }
    }
    self.selectedIdentifiers = live;
    if (live.count != stored.count) {
        [self saveSelection];
    }

    [self rebuildSections];
    [self.tableView reloadData];
}

- (void)rebuildSections {
    NSMutableDictionary<NSString *, NSDictionary<NSString *, id> *> *byIdentifier =
        [NSMutableDictionary dictionary];
    for (NSDictionary<NSString *, id> *entry in self.catalog) {
        byIdentifier[entry[@"workflowID"]] = entry;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *included = [NSMutableArray array];
    NSMutableSet<NSString *> *selectedSet =
        [NSMutableSet setWithArray:self.selectedIdentifiers];
    for (NSString *identifier in self.selectedIdentifiers) {
        NSDictionary<NSString *, id> *entry = byIdentifier[identifier];
        if (entry != nil) {
            [included addObject:entry];
        }
    }
    self.includedEntries = included;

    NSMutableArray<NSDictionary<NSString *, id> *> *available = [NSMutableArray array];
    for (NSDictionary<NSString *, id> *entry in self.catalog) {
        if (![selectedSet containsObject:entry[@"workflowID"]]) {
            [available addObject:entry];
        }
    }
    self.availableEntries = available;
}

- (void)saveSelection {
    CSLSetShortcutIDs(self.selectedIdentifiers, self.slot);
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? self.includedEntries.count : self.availableEntries.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"IN THIS MODULE" : @"MORE SHORTCUTS";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0 && self.includedEntries.count == 0) {
        return @"Add at least one Shortcut below. Nothing is added automatically.";
    }
    if (section == 0 && self.includedEntries.count == 1) {
        return @"With one Shortcut the module runs it straight away, without a popup, and shows its icon in Control Center.";
    }
    if (section == 1 && self.catalog.count == 0) {
        return @"Return to CCShortcutLauncher and tap Load My Shortcuts first.";
    }
    if (section == 1 && self.availableEntries.count == 0) {
        return @"All loaded Shortcuts are already in this module.";
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
        sourceIndexPath.row == destinationIndexPath.row ||
        (NSUInteger)sourceIndexPath.row >= self.includedEntries.count) {
        return;
    }

    // Move by identifier, not by row index, so the order that gets saved is
    // the order the table is showing.
    NSString *identifier = self.includedEntries[sourceIndexPath.row][@"workflowID"];
    NSUInteger currentIndex = [self.selectedIdentifiers indexOfObject:identifier];
    if (currentIndex == NSNotFound) {
        return;
    }
    [self.selectedIdentifiers removeObjectAtIndex:currentIndex];
    NSUInteger destination =
        MIN((NSUInteger)destinationIndexPath.row, self.selectedIdentifiers.count);
    [self.selectedIdentifiers insertObject:identifier atIndex:destination];

    [self saveSelection];
    [self rebuildSections];
}

@end
