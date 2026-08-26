#import <Preferences/PSListController.h>
#import "CSLModuleCountCell.h"

@class UIAlertController;

@interface CSLRootListController : PSListController <CSLModuleCountCellDelegate> {
    UIAlertController *_loadingAlert;
    NSUInteger _resolveGeneration;
}
@end
