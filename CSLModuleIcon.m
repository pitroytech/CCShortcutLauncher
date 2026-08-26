#import "CSLModuleIcon.h"

#import "CSLDiagnostics.h"
#import "CSLShortcutIcon.h"
#import "CSLSlotPreferences.h"

static NSString *const CSLModuleIconIdentifierKey = @"identifier";
static NSString *const CSLModuleIconVietnameseNameKey = @"vi";
static NSString *const CSLModuleIconEnglishNameKey = @"en";

NSArray<NSDictionary<NSString *, NSString *> *> *CSLModuleIconCatalog(void) {
    static NSArray<NSDictionary<NSString *, NSString *> *> *catalog;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        catalog = @[
            @{CSLModuleIconIdentifierKey: @"sparkles", CSLModuleIconVietnameseNameKey: @"Lấp lánh", CSLModuleIconEnglishNameKey: @"Sparkles"},
            @{CSLModuleIconIdentifierKey: @"bookmark", CSLModuleIconVietnameseNameKey: @"Dấu trang", CSLModuleIconEnglishNameKey: @"Bookmark"},
            @{CSLModuleIconIdentifierKey: @"phone", CSLModuleIconVietnameseNameKey: @"Điện thoại", CSLModuleIconEnglishNameKey: @"Phone"},
            @{CSLModuleIconIdentifierKey: @"camera", CSLModuleIconVietnameseNameKey: @"Máy ảnh", CSLModuleIconEnglishNameKey: @"Camera"},
            @{CSLModuleIconIdentifierKey: @"chat", CSLModuleIconVietnameseNameKey: @"Trò chuyện", CSLModuleIconEnglishNameKey: @"Chat"},
            @{CSLModuleIconIdentifierKey: @"chats", CSLModuleIconVietnameseNameKey: @"Hội thoại", CSLModuleIconEnglishNameKey: @"Chats"},
            @{CSLModuleIconIdentifierKey: @"message", CSLModuleIconVietnameseNameKey: @"Tin nhắn", CSLModuleIconEnglishNameKey: @"Message"},
            @{CSLModuleIconIdentifierKey: @"crown", CSLModuleIconVietnameseNameKey: @"Vương miện", CSLModuleIconEnglishNameKey: @"Crown"},
            @{CSLModuleIconIdentifierKey: @"trash", CSLModuleIconVietnameseNameKey: @"Thùng rác", CSLModuleIconEnglishNameKey: @"Trash"},
            @{CSLModuleIconIdentifierKey: @"compass", CSLModuleIconVietnameseNameKey: @"La bàn", CSLModuleIconEnglishNameKey: @"Compass"},
            @{CSLModuleIconIdentifierKey: @"note", CSLModuleIconVietnameseNameKey: @"Ghi chú", CSLModuleIconEnglishNameKey: @"Note"},
            @{CSLModuleIconIdentifierKey: @"diamond", CSLModuleIconVietnameseNameKey: @"Kim cương", CSLModuleIconEnglishNameKey: @"Diamond"},
            @{CSLModuleIconIdentifierKey: @"edit", CSLModuleIconVietnameseNameKey: @"Chỉnh sửa", CSLModuleIconEnglishNameKey: @"Edit"},
            @{CSLModuleIconIdentifierKey: @"wallet", CSLModuleIconVietnameseNameKey: @"Ví", CSLModuleIconEnglishNameKey: @"Wallet"},
            @{CSLModuleIconIdentifierKey: @"document", CSLModuleIconVietnameseNameKey: @"Tài liệu", CSLModuleIconEnglishNameKey: @"Document"},
            @{CSLModuleIconIdentifierKey: @"flag", CSLModuleIconVietnameseNameKey: @"Lá cờ", CSLModuleIconEnglishNameKey: @"Flag"},
            @{CSLModuleIconIdentifierKey: @"photo", CSLModuleIconVietnameseNameKey: @"Hình ảnh", CSLModuleIconEnglishNameKey: @"Photo"},
            @{CSLModuleIconIdentifierKey: @"gift", CSLModuleIconVietnameseNameKey: @"Quà tặng", CSLModuleIconEnglishNameKey: @"Gift"},
            @{CSLModuleIconIdentifierKey: @"help", CSLModuleIconVietnameseNameKey: @"Trợ giúp", CSLModuleIconEnglishNameKey: @"Help"},
            @{CSLModuleIconIdentifierKey: @"home", CSLModuleIconVietnameseNameKey: @"Nhà", CSLModuleIconEnglishNameKey: @"Home"},
            @{CSLModuleIconIdentifierKey: @"translate", CSLModuleIconVietnameseNameKey: @"Dịch", CSLModuleIconEnglishNameKey: @"Translate"},
            @{CSLModuleIconIdentifierKey: @"heart", CSLModuleIconVietnameseNameKey: @"Trái tim", CSLModuleIconEnglishNameKey: @"Heart"},
            @{CSLModuleIconIdentifierKey: @"lock", CSLModuleIconVietnameseNameKey: @"Khóa", CSLModuleIconEnglishNameKey: @"Lock"},
            @{CSLModuleIconIdentifierKey: @"unlock", CSLModuleIconVietnameseNameKey: @"Mở khóa", CSLModuleIconEnglishNameKey: @"Unlock"},
            @{CSLModuleIconIdentifierKey: @"mail", CSLModuleIconVietnameseNameKey: @"Thư", CSLModuleIconEnglishNameKey: @"Mail"},
            @{CSLModuleIconIdentifierKey: @"megaphone", CSLModuleIconVietnameseNameKey: @"Loa thông báo", CSLModuleIconEnglishNameKey: @"Megaphone"},
            @{CSLModuleIconIdentifierKey: @"microphone", CSLModuleIconVietnameseNameKey: @"Micrô", CSLModuleIconEnglishNameKey: @"Microphone"},
            @{CSLModuleIconIdentifierKey: @"music", CSLModuleIconVietnameseNameKey: @"Âm nhạc", CSLModuleIconEnglishNameKey: @"Music"},
            @{CSLModuleIconIdentifierKey: @"location", CSLModuleIconVietnameseNameKey: @"Vị trí", CSLModuleIconEnglishNameKey: @"Location"},
            @{CSLModuleIconIdentifierKey: @"play", CSLModuleIconVietnameseNameKey: @"Phát", CSLModuleIconEnglishNameKey: @"Play"},
            @{CSLModuleIconIdentifierKey: @"briefcase", CSLModuleIconVietnameseNameKey: @"Công việc", CSLModuleIconEnglishNameKey: @"Briefcase"},
            @{CSLModuleIconIdentifierKey: @"book", CSLModuleIconVietnameseNameKey: @"Sách", CSLModuleIconEnglishNameKey: @"Book"},
            @{CSLModuleIconIdentifierKey: @"trash-slash", CSLModuleIconVietnameseNameKey: @"Không xóa", CSLModuleIconEnglishNameKey: @"No Trash"},
            @{CSLModuleIconIdentifierKey: @"search", CSLModuleIconVietnameseNameKey: @"Tìm kiếm", CSLModuleIconEnglishNameKey: @"Search"},
            @{CSLModuleIconIdentifierKey: @"send", CSLModuleIconVietnameseNameKey: @"Gửi", CSLModuleIconEnglishNameKey: @"Send"},
            @{CSLModuleIconIdentifierKey: @"settings", CSLModuleIconVietnameseNameKey: @"Cài đặt", CSLModuleIconEnglishNameKey: @"Settings"},
            @{CSLModuleIconIdentifierKey: @"star", CSLModuleIconVietnameseNameKey: @"Ngôi sao", CSLModuleIconEnglishNameKey: @"Star"},
            @{CSLModuleIconIdentifierKey: @"tag", CSLModuleIconVietnameseNameKey: @"Thẻ", CSLModuleIconEnglishNameKey: @"Tag"},
            @{CSLModuleIconIdentifierKey: @"shirt", CSLModuleIconVietnameseNameKey: @"Áo", CSLModuleIconEnglishNameKey: @"Shirt"},
            @{CSLModuleIconIdentifierKey: @"fire", CSLModuleIconVietnameseNameKey: @"Ngọn lửa", CSLModuleIconEnglishNameKey: @"Fire"},
            @{CSLModuleIconIdentifierKey: @"video", CSLModuleIconVietnameseNameKey: @"Video", CSLModuleIconEnglishNameKey: @"Video"},
            @{CSLModuleIconIdentifierKey: @"video-slash", CSLModuleIconVietnameseNameKey: @"Tắt video", CSLModuleIconEnglishNameKey: @"Video Off"},
            @{CSLModuleIconIdentifierKey: @"eye", CSLModuleIconVietnameseNameKey: @"Mắt", CSLModuleIconEnglishNameKey: @"Eye"},
            @{CSLModuleIconIdentifierKey: @"hourglass", CSLModuleIconVietnameseNameKey: @"Đồng hồ cát", CSLModuleIconEnglishNameKey: @"Hourglass"},
        ];
    });
    return catalog;
}

static NSDictionary<NSString *, NSString *> *CSLModuleIconEntry(
    NSString *identifier
) {
    if (identifier.length == 0) {
        return nil;
    }
    for (NSDictionary<NSString *, NSString *> *entry in CSLModuleIconCatalog()) {
        if ([entry[CSLModuleIconIdentifierKey] isEqualToString:identifier]) {
            return entry;
        }
    }
    return nil;
}

BOOL CSLModuleIconIdentifierIsValid(NSString *identifier) {
    return CSLModuleIconEntry(identifier) != nil;
}

NSString *CSLModuleIconDisplayName(NSString *identifier) {
    NSDictionary<NSString *, NSString *> *entry = CSLModuleIconEntry(identifier);
    if (entry == nil) {
        return nil;
    }
    return CSLUsesVietnamese()
        ? entry[CSLModuleIconVietnameseNameKey]
        : entry[CSLModuleIconEnglishNameKey];
}

static NSBundle *CSLModuleIconResourceBundle(void) {
    Class ownerClass = NSClassFromString(@"CCShortcutLauncherProvider");
    if (ownerClass == Nil) {
        ownerClass = NSClassFromString(@"CSLRootListController");
    }
    if (ownerClass == Nil) {
        ownerClass = NSClassFromString(@"CSLShortcutOrderController");
    }
    return ownerClass != Nil ? [NSBundle bundleForClass:ownerClass] : NSBundle.mainBundle;
}

static UIImage *CSLDefaultGridIcon(CGSize size) {
    CGFloat pointSize = MAX(14.0, MIN(size.width, size.height) * 0.72);
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:pointSize
                                                        weight:UIImageSymbolWeightRegular];
    return [UIImage systemImageNamed:@"square.grid.2x2"
                   withConfiguration:configuration];
}

static UIImage *CSLScaledModuleIcon(UIImage *source, CGSize size) {
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    [source drawInRect:CGRectMake(0.0, 0.0, size.width, size.height)];
    UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return scaled;
}

/// Produces real RGBA pixels with the source alpha preserved. UIKit's tinting
/// implementation is used before scaling; filling a UIGraphics context with
/// SourceIn proved unreliable in Preferences and could turn the whole canvas
/// into an opaque square.
static UIImage *CSLTintedModuleIcon(UIImage *source, CGSize size, UIColor *color) {
    UIImage *tintedSource = [source imageWithTintColor:color
                                         renderingMode:UIImageRenderingModeAlwaysOriginal];
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGRect bounds = CGRectMake(0.0, 0.0, size.width, size.height);
    [tintedSource drawInRect:bounds];
    UIImage *tinted = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [tinted imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

/// CCSupport calls LICreateIconForImage on provider icons. A glyph-only image
/// has too little opaque artwork for that app-icon compositor and can turn
/// into a plain black tile. Give it a complete, static-colour tile instead.
static UIImage *CSLControlCenterSettingsTile(UIImage *glyph, CGSize size) {
    if (glyph == nil || size.width <= 0.0 || size.height <= 0.0) {
        return nil;
    }

    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGRect bounds = CGRectMake(0.0, 0.0, size.width, size.height);
    CGFloat cornerRadius = MIN(size.width, size.height) * 0.22;
    UIBezierPath *background =
        [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:cornerRadius];
    [[UIColor colorWithRed:88.0 / 255.0
                     green:86.0 / 255.0
                      blue:214.0 / 255.0
                     alpha:1.0] setFill];
    [background fill];

    CGFloat inset = MIN(size.width, size.height) * 0.18;
    CGRect glyphRect = CGRectInset(bounds, inset, inset);
    UIImage *whiteGlyph = CSLTintedModuleIcon(
        glyph,
        glyphRect.size,
        UIColor.whiteColor
    );
    [whiteGlyph drawInRect:glyphRect];

    UIImage *tile = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [tile imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

UIImage *CSLModulePackIcon(
    NSString *identifier,
    CGSize size,
    UIColor *tintColor,
    BOOL originalRendering
) {
    if (!CSLModuleIconIdentifierIsValid(identifier)) {
        return nil;
    }

    NSString *resourceName = [NSString stringWithFormat:@"CSLModuleIcon.%@.png", identifier];
    NSBundle *bundle = CSLModuleIconResourceBundle();
    UIImage *source = [UIImage imageNamed:resourceName
                                inBundle:bundle
           compatibleWithTraitCollection:nil];
    if (source == nil) {
        NSLog(@"[CCShortcutLauncher][Icon] MODULE_PACK_RESOURCE_MISSING identifier=%@ bundle=%@",
              identifier,
              bundle.bundlePath);
        return nil;
    }

    CSLIconDiagnosticLog(
        @"[CCShortcutLauncher][Icon] MODULE_PACK_RENDERED identifier=%@ bundle=%@ size=%.0fx%.0f original=%d",
        identifier,
        bundle.bundlePath,
        size.width,
        size.height,
        originalRendering
    );
    if (!originalRendering) {
        return [CSLScaledModuleIcon(source, size)
            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    return CSLTintedModuleIcon(
        source,
        size,
        tintColor ?: [UIColor colorWithWhite:0.58 alpha:1.0]
    );
}

UIImage *CSLModuleTemplateGlyphForSlot(
    NSUInteger slot,
    NSArray<NSDictionary<NSString *, id> *> *entries,
    CGSize size
) {
    if (entries.count == 1) {
        UIImage *shortcutGlyph = CSLShortcutGlyphTemplateImageForEntry(
            entries.firstObject,
            size
        );
        if (shortcutGlyph != nil) {
            return shortcutGlyph;
        }
    } else if (entries.count > 1) {
        UIImage *selected = CSLModulePackIcon(
            CSLSlotIconName(slot),
            size,
            nil,
            NO
        );
        if (selected != nil) {
            return selected;
        }
    }

    return [CSLDefaultGridIcon(size) imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

UIImage *CSLModuleSettingsIconForSlot(
    NSUInteger slot,
    NSArray<NSDictionary<NSString *, id> *> *entries,
    CGSize size
) {
    CSLIconDiagnosticLog(
        @"[CCShortcutLauncher][Icon] SETTINGS_ROUTE slot=%lu entries=%lu selected=%@",
        (unsigned long)slot,
        (unsigned long)entries.count,
        CSLSlotIconName(slot) ?: @"default"
    );
    return CSLModuleControlCenterSettingsIconForSlot(slot, entries, size);
}

UIImage *CSLModuleControlCenterSettingsIconForSlot(
    NSUInteger slot,
    NSArray<NSDictionary<NSString *, id> *> *entries,
    CGSize size
) {
    if (entries.count == 1) {
        UIImage *shortcutIcon = CSLShortcutIconImageForEntry(entries.firstObject, size);
        if (shortcutIcon != nil) {
            return shortcutIcon;
        }
    }

    UIImage *glyph = nil;
    if (entries.count > 1) {
        glyph = CSLModulePackIcon(
            CSLSlotIconName(slot),
            size,
            nil,
            NO
        );
    }
    if (glyph == nil) {
        glyph = [CSLDefaultGridIcon(size)
            imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }

    CSLIconDiagnosticLog(
        @"[CCShortcutLauncher][Icon] CONTROL_CENTER_TILE slot=%lu entries=%lu selected=%@",
        (unsigned long)slot,
        (unsigned long)entries.count,
        CSLSlotIconName(slot) ?: @"default"
    );
    return CSLControlCenterSettingsTile(glyph, size);
}
