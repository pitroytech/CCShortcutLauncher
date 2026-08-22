#import <Preferences/PSListController.h>

@class UIAlertController;

@interface CSLRootListController : PSListController {
    UIAlertController *_loadingAlert;
    NSUInteger _resolveGeneration;
}
@end
