#import <ControlCenterUIKit/CCUIToggleModule.h>

@interface CCShortcutLauncher : CCUIToggleModule

/// Each Control Center module instance is bound to one slot and shows only the
/// Shortcuts assigned to that slot.
- (instancetype)initWithSlot:(NSUInteger)slot;

@property (nonatomic, readonly) NSUInteger slot;

@end
