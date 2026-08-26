#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Ordered icon choices shown by the per-module picker. Each item contains an
/// identifier plus Vietnamese and English labels.
NSArray<NSDictionary<NSString *, NSString *> *> *CSLModuleIconCatalog(void);
BOOL CSLModuleIconIdentifierIsValid(NSString *_Nullable identifier);
NSString *_Nullable CSLModuleIconDisplayName(NSString *_Nullable identifier);

/// Renders one extracted pack glyph as a tintable image. Returns nil for an
/// unknown identifier or a missing resource.
UIImage *_Nullable CSLModulePackIcon(
    NSString *_Nullable identifier,
    CGSize size,
    UIColor *_Nullable tintColor,
    BOOL originalRendering
);

/// Shared icon routing for the live Control Center module.
UIImage *CSLModuleTemplateGlyphForSlot(
    NSUInteger slot,
    NSArray<NSDictionary<NSString *, id> *> *entries,
    CGSize size
);

/// Icon routing used inside the tweak's own Settings pages. It deliberately
/// matches Settings -> Control Center so module rows stay visually identical.
UIImage *CSLModuleSettingsIconForSlot(
    NSUInteger slot,
    NSArray<NSDictionary<NSString *, id> *> *entries,
    CGSize size
);

/// Icon routing for Settings -> Control Center. CCSupport sends this image
/// through LaunchServices' app-icon compositor, so non-Shortcut glyphs need a
/// complete coloured tile instead of a sparse transparent template.
UIImage *CSLModuleControlCenterSettingsIconForSlot(
    NSUInteger slot,
    NSArray<NSDictionary<NSString *, id> *> *entries,
    CGSize size
);

NS_ASSUME_NONNULL_END
