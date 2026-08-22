#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Builds a Shortcuts-style tile from the cached ZSHORTCUTICON metadata.
UIImage *CSLShortcutIconImageForEntry(NSDictionary<NSString *, id> *entry,
                                      CGSize size);

/// UIAlertAction has an image setter on iOS 16, but it is not public API.
/// This wrapper checks the selector and contains exceptions before using it.
void CSLSetImageForAlertActionIfSupported(UIAlertAction *action,
                                          UIImage *image);

NS_ASSUME_NONNULL_END
