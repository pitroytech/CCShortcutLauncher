#import "CSLShortcutOrderController.h"
#import "CSLModuleIconPickerController.h"
#import "../CSLModuleIcon.h"
#import "../CSLShortcutIcon.h"
#import "../CSLSlotPreferences.h"

typedef NS_ENUM(NSInteger, CSLModuleEditorSection) {
    CSLModuleEditorSectionAppearance = 0,
    CSLModuleEditorSectionIncluded = 1,
    CSLModuleEditorSectionAvailable = 2,
};

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
    self.tableView.allowsSelectionDuringEditing = YES;
    self.tableView.rowHeight = 58.0;
    [self setEditing:YES animated:NO];
    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:CSLLocalizedText(@"Đổi tên", @"Rename")
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
        alertControllerWithTitle:CSLLocalizedText(@"Đổi tên mô-đun", @"Rename Module")
                         message:CSLLocalizedText(
                             @"Nhập tên bạn muốn hiển thị trong Cài đặt và menu phím tắt.",
                             @"Enter the name you want to see in Settings and in the Shortcut menu."
                         )
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.text = CSLSlotName(self.slot);
        textField.placeholder = CSLDisplayNameForSlot(self.slot);
        textField.clearButtonMode = UITextFieldViewModeWhileEditing;
        textField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:CSLLocalizedText(@"Hủy", @"Cancel")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    __weak typeof(self) weakSelf = self;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:CSLLocalizedText(@"Lưu", @"Save")
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
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch ((CSLModuleEditorSection)section) {
        case CSLModuleEditorSectionAppearance:
            return 1;
        case CSLModuleEditorSectionIncluded:
            return self.includedEntries.count;
        case CSLModuleEditorSectionAvailable:
            return self.availableEntries.count;
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch ((CSLModuleEditorSection)section) {
        case CSLModuleEditorSectionAppearance:
            return CSLLocalizedText(@"BIỂU TƯỢNG MÔ-ĐUN", @"MODULE ICON");
        case CSLModuleEditorSectionIncluded:
            return CSLLocalizedText(@"TRONG MÔ-ĐUN NÀY", @"IN THIS MODULE");
        case CSLModuleEditorSectionAvailable:
            return CSLLocalizedText(@"PHÍM TẮT CÓ SẴN", @"AVAILABLE SHORTCUTS");
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == CSLModuleEditorSectionAppearance) {
        if (self.includedEntries.count == 1) {
            return CSLLocalizedText(
                @"Mô-đun có một phím tắt luôn dùng biểu tượng của chính phím tắt đó.",
                @"A module with one Shortcut always uses that Shortcut's own icon."
            );
        }
        if (self.includedEntries.count > 1) {
            return CSLLocalizedText(
                @"Chạm để chọn biểu tượng dùng trong phần cài đặt và Trung tâm điều khiển.",
                @"Tap to choose the icon used in Settings and Control Center."
            );
        }
        return CSLLocalizedText(
            @"Thêm ít nhất hai phím tắt để chọn biểu tượng. Hiện tại mô-đun dùng biểu tượng mặc định.",
            @"Add at least two Shortcuts to choose an icon. The module currently uses the default icon."
        );
    }
    if (section == CSLModuleEditorSectionIncluded && self.includedEntries.count == 0) {
        return CSLLocalizedText(
            @"Chạm + bên cạnh một phím tắt phía dưới để thêm vào mô-đun này.",
            @"Tap + next to a Shortcut below to add it to this module."
        );
    }
    if (section == CSLModuleEditorSectionIncluded && self.includedEntries.count == 1) {
        return CSLLocalizedText(
            @"Chạm mô-đun trong Trung tâm điều khiển để chạy ngay phím tắt này. Thêm phím tắt khác nếu bạn muốn hiện menu lựa chọn.",
            @"Tap the Control Center module to run this Shortcut immediately. Add another Shortcut if you prefer a selection menu."
        );
    }
    if (section == CSLModuleEditorSectionIncluded && self.includedEntries.count > 1) {
        return CSLLocalizedText(
            @"Kéo tay nắm để sắp xếp thứ tự trong menu. Chạm − để xóa một phím tắt khỏi mô-đun này.",
            @"Drag the handles to choose the order shown in the menu. Tap − to remove a Shortcut from this module."
        );
    }
    if (section == CSLModuleEditorSectionAvailable && self.catalog.count == 0) {
        return CSLLocalizedText(
            @"Quay lại và chạm Tải phím tắt của tôi, sau đó trở lại đây để chọn phím tắt.",
            @"Go back and tap Load My Shortcuts, then return here to choose a Shortcut."
        );
    }
    if (section == CSLModuleEditorSectionAvailable && self.availableEntries.count == 0) {
        return CSLLocalizedText(
            @"Tất cả phím tắt có sẵn đã được thêm vào mô-đun này.",
            @"All available Shortcuts have been added to this module."
        );
    }
    if (section == CSLModuleEditorSectionAvailable) {
        return CSLLocalizedText(
            @"Chạm + để thêm một phím tắt vào mô-đun này.",
            @"Tap + to add a Shortcut to this module."
        );
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == CSLModuleEditorSectionAppearance) {
        static NSString *const appearanceIdentifier = @"ModuleIconCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:appearanceIdentifier];
        if (cell == nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                           reuseIdentifier:appearanceIdentifier];
        }
        cell.textLabel.text = CSLLocalizedText(@"Biểu tượng", @"Icon");
        cell.imageView.image = CSLModuleSettingsIconForSlot(
            self.slot,
            self.includedEntries,
            CGSizeMake(34.0, 34.0)
        );
        if (self.includedEntries.count == 1) {
            cell.detailTextLabel.text = CSLLocalizedText(@"Tự động", @"Automatic");
        } else if (self.includedEntries.count > 1) {
            cell.detailTextLabel.text = CSLModuleIconDisplayName(CSLSlotIconName(self.slot))
                ?: CSLLocalizedText(@"Mặc định", @"Default");
        } else {
            cell.detailTextLabel.text = CSLLocalizedText(@"Mặc định", @"Default");
        }
        BOOL canChoose = self.includedEntries.count > 1;
        cell.accessoryType = canChoose
            ? UITableViewCellAccessoryDisclosureIndicator
            : UITableViewCellAccessoryNone;
        cell.selectionStyle = canChoose
            ? UITableViewCellSelectionStyleDefault
            : UITableViewCellSelectionStyleNone;
        cell.textLabel.enabled = canChoose;
        cell.detailTextLabel.enabled = canChoose;
        return cell;
    }

    static NSString *const reuseIdentifier = @"ShortcutCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                       reuseIdentifier:reuseIdentifier];
    }

    NSDictionary<NSString *, id> *entry = indexPath.section == CSLModuleEditorSectionIncluded
        ? self.includedEntries[indexPath.row]
        : self.availableEntries[indexPath.row];
    cell.textLabel.text = entry[@"name"];
    cell.detailTextLabel.text = nil;
    cell.imageView.image = CSLShortcutIconImageForEntry(entry, CGSizeMake(34.0, 34.0));
    cell.imageView.tintColor = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section != CSLModuleEditorSectionAppearance;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView
           editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == CSLModuleEditorSectionAppearance) {
        return UITableViewCellEditingStyleNone;
    }
    return indexPath.section == CSLModuleEditorSectionIncluded
        ? UITableViewCellEditingStyleDelete
        : UITableViewCellEditingStyleInsert;
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete &&
        indexPath.section == CSLModuleEditorSectionIncluded) {
        NSString *identifier = self.includedEntries[indexPath.row][@"workflowID"];
        [self.selectedIdentifiers removeObject:identifier];
    } else if (editingStyle == UITableViewCellEditingStyleInsert &&
               indexPath.section == CSLModuleEditorSectionAvailable) {
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
    return indexPath.section == CSLModuleEditorSectionIncluded;
}

- (NSIndexPath *)tableView:(UITableView *)tableView
    targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)sourceIndexPath
                         toProposedIndexPath:(NSIndexPath *)proposedDestinationIndexPath {
    if (proposedDestinationIndexPath.section == CSLModuleEditorSectionIncluded) {
        return proposedDestinationIndexPath;
    }
    NSInteger lastRow = MAX((NSInteger)self.includedEntries.count - 1, 0);
    return [NSIndexPath indexPathForRow:lastRow
                              inSection:CSLModuleEditorSectionIncluded];
}

- (void)tableView:(UITableView *)tableView
    moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
           toIndexPath:(NSIndexPath *)destinationIndexPath {
    if (sourceIndexPath.section != CSLModuleEditorSectionIncluded ||
        destinationIndexPath.section != CSLModuleEditorSectionIncluded ||
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

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != CSLModuleEditorSectionAppearance ||
        self.includedEntries.count <= 1) {
        return;
    }
    CSLModuleIconPickerController *controller =
        [[CSLModuleIconPickerController alloc] initWithSlot:self.slot];
    [self.navigationController pushViewController:controller animated:YES];
}

@end
