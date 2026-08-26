#import <Preferences/PSTableCell.h>

@class CSLModuleCountCell;

@protocol CSLModuleCountCellDelegate <NSObject>
- (void)moduleCountCellDidChange:(CSLModuleCountCell *)cell;
@end

/// Inline module-count control shown as: minus, current value, plus.
@interface CSLModuleCountCell : PSTableCell
@end
