#import <UIKit/UIKit.h>

@interface CSLShortcutOrderController : UITableViewController

/// Edits the Shortcut list of one Control Center module slot.
- (instancetype)initWithSlot:(NSUInteger)slot;

@property (nonatomic, readonly) NSUInteger slot;

@end
