#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Builds the full-colour Shortcuts tile used by popup and Settings rows.
/// Keep this independent from the Control Center module glyph renderer below:
/// Control Center has different tinting and will later support per-slot art.
UIImage *CSLShortcutIconImageForEntry(NSDictionary<NSString *, id> *entry,
                                      CGSize size);

/// Builds the default module glyph alone, without the coloured tile, as a
/// template image. Module-level icon selection belongs behind this boundary.
/// Control Center tints module glyphs itself, so a tile would render as a
/// solid block.
/// Returns nil when the entry has no usable glyph metadata.
UIImage *_Nullable CSLShortcutGlyphTemplateImageForEntry(
    NSDictionary<NSString *, id> *entry,
    CGSize size);

/// UIAlertAction has an image setter on iOS 16, but it is not public API.
/// This wrapper checks the selector and contains exceptions before using it.
void CSLSetImageForAlertActionIfSupported(UIAlertAction *action,
                                          UIImage *image);

NS_ASSUME_NONNULL_END
