#import <UIKit/UIKit.h>

@interface CSLModuleIconPickerController : UICollectionViewController

- (instancetype)initWithSlot:(NSUInteger)slot;

@property (nonatomic, readonly) NSUInteger slot;

@end
