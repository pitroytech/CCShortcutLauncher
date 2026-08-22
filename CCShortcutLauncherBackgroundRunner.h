#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, CSLBackgroundStartResult) {
    CSLBackgroundStartResultSubmitted,
    CSLBackgroundStartResultPreflightFailed,
    CSLBackgroundStartResultAlreadyRunning,
};

FOUNDATION_EXPORT CSLBackgroundStartResult
CSLStartBackgroundShortcutNamed(NSString *shortcutName, NSString *workflowIdentifier);
