#import "CSLShortcutIcon.h"
#import "CSLDiagnostics.h"

#import <CoreText/CoreText.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <stdint.h>

static Class CSLWorkflowIconClass = Nil;
static Class CSLWorkflowIconDrawerClass = Nil;

static UIImage *CSLApplicationIconImage(NSString *bundleIdentifier);

/// Icon methods are called repeatedly while Settings and Control Center lay
/// out their cells. Log each distinct decision once so an icon probe stays
/// readable while still showing which renderer won in each process.
static void CSLLogIconDecisionOnce(NSString *surface,
                                   NSString *route,
                                   NSDictionary<NSString *, id> *entry,
                                   CGSize size) {
#if CSL_ICON_DIAGNOSTICS
    static NSMutableSet<NSString *> *loggedDecisions = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        loggedDecisions = [NSMutableSet set];
    });

    NSString *process = NSBundle.mainBundle.bundleIdentifier
        ?: NSProcessInfo.processInfo.processName;
    NSString *workflowIdentifier = [entry[@"workflowID"] isKindOfClass:[NSString class]]
        ? entry[@"workflowID"]
        : @"none";
    NSString *key = [NSString stringWithFormat:@"%@|%@|%@|%@|%.1f|%.1f",
        process,
        surface,
        route,
        workflowIdentifier,
        size.width,
        size.height];

    @synchronized (loggedDecisions) {
        if ([loggedDecisions containsObject:key]) {
            return;
        }
        [loggedDecisions addObject:key];
    }

    NSLog(@"[CCShortcutLauncher][Icon] RENDER process=%@ surface=%@ route=%@ workflowID=%@ name=\"%@\" glyph=%@ color=%@ appBundleID=%@ size=%.1fx%.1f",
          process,
          surface,
          route,
          workflowIdentifier,
          entry[@"name"] ?: @"",
          entry[@"iconGlyph"] ?: @"none",
          entry[@"iconColor"] ?: @"none",
          entry[@"appBundleID"] ?: @"none",
          size.width,
          size.height);
#else
    (void)surface;
    (void)route;
    (void)entry;
    (void)size;
#endif
}

static BOOL CSLAppleRendererClassesAreReady(SEL iconInitializer,
                                            SEL drawerInitializer,
                                            SEL imageSelector) {
    return
        CSLWorkflowIconClass != Nil &&
        CSLWorkflowIconDrawerClass != Nil &&
        [CSLWorkflowIconClass instancesRespondToSelector:iconInitializer] &&
        [CSLWorkflowIconDrawerClass
            instancesRespondToSelector:drawerInitializer] &&
        [CSLWorkflowIconDrawerClass
            instancesRespondToSelector:imageSelector];
}

static BOOL CSLPrepareAppleWorkflowIconRenderer(void) {
    static BOOL rendererReady = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CSLWorkflowIconClass = NSClassFromString(@"WFWorkflowIcon");
        CSLWorkflowIconDrawerClass = NSClassFromString(@"WFWorkflowIconDrawer");

        SEL iconInitializer = NSSelectorFromString(
            @"initWithBackgroundColorValue:glyphCharacter:customImageData:"
        );
        SEL drawerInitializer = NSSelectorFromString(@"initWithIcon:");
        SEL imageSelector = NSSelectorFromString(@"imageWithSize:scale:");

        if (!CSLAppleRendererClassesAreReady(
                iconInitializer,
                drawerInitializer,
                imageSelector
            )) {
            NSArray<NSString *> *frameworkExecutables = @[
                @"/System/Library/PrivateFrameworks/WorkflowKit.framework/WorkflowKit",
                @"/System/Library/PrivateFrameworks/VoiceShortcutClient.framework/VoiceShortcutClient",
                @"/System/Library/PrivateFrameworks/WorkflowUICore.framework/WorkflowUICore",
            ];
            for (NSString *executablePath in frameworkExecutables) {
                void *handle = dlopen(
                    executablePath.fileSystemRepresentation,
                    RTLD_LAZY | RTLD_LOCAL
                );
                if (handle == NULL) {
                    const char *error = dlerror();
                    NSLog(@"[CCShortcutLauncher][Icon] FRAMEWORK_LOAD_FAILED framework=%@ error=%s",
                          executablePath.lastPathComponent,
                          error != NULL ? error : "unknown");
                    continue;
                }

                CSLWorkflowIconClass = NSClassFromString(@"WFWorkflowIcon");
                CSLWorkflowIconDrawerClass =
                    NSClassFromString(@"WFWorkflowIconDrawer");
                if (CSLAppleRendererClassesAreReady(
                        iconInitializer,
                        drawerInitializer,
                        imageSelector
                    )) {
                    break;
                }
            }
        }

        rendererReady = CSLAppleRendererClassesAreReady(
            iconInitializer,
            drawerInitializer,
            imageSelector
        );

        if (!rendererReady) {
            NSLog(@"[CCShortcutLauncher][Icon] APPLE_RENDERER_UNAVAILABLE iconClass=%d drawerClass=%d iconInit=%d drawerInit=%d imageScale=%d",
                  CSLWorkflowIconClass != Nil,
                  CSLWorkflowIconDrawerClass != Nil,
                  CSLWorkflowIconClass != Nil &&
                      [CSLWorkflowIconClass
                          instancesRespondToSelector:iconInitializer],
                  CSLWorkflowIconDrawerClass != Nil &&
                      [CSLWorkflowIconDrawerClass
                          instancesRespondToSelector:drawerInitializer],
                  CSLWorkflowIconDrawerClass != Nil &&
                      [CSLWorkflowIconDrawerClass
                          instancesRespondToSelector:imageSelector]);
        }
    });
    return rendererReady;
}

static void CSLLogAppleRenderFailureOnce(uint32_t glyphNumber,
                                         NSString *stage) {
    static NSMutableSet<NSString *> *loggedFailures = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        loggedFailures = [NSMutableSet set];
    });

    NSString *key = [NSString stringWithFormat:@"%u:%@", glyphNumber, stage];
    @synchronized (loggedFailures) {
        if ([loggedFailures containsObject:key]) {
            return;
        }
        [loggedFailures addObject:key];
    }
    NSLog(@"[CCShortcutLauncher][Icon] APPLE_RENDER_FAILED glyph=%u stage=%@",
          glyphNumber,
          stage);
}

static UIImage *CSLUIImageFromWorkflowImage(id renderedImage, CGFloat scale) {
    if ([renderedImage isKindOfClass:[UIImage class]]) {
        return renderedImage;
    }

    NSArray<NSString *> *imageSelectors = @[
        @"UIImage",
        @"untintedUIImage",
        @"platformImage",
    ];
    for (NSString *selectorName in imageSelectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if (![renderedImage respondsToSelector:selector]) {
            continue;
        }
        id candidate = ((id (*)(id, SEL))objc_msgSend)(renderedImage, selector);
        if ([candidate isKindOfClass:[UIImage class]]) {
            return candidate;
        }
    }

    NSArray<NSString *> *cgImageSelectors = @[
        @"CGImage",
        @"internalCGImage",
    ];
    for (NSString *selectorName in cgImageSelectors) {
        SEL selector = NSSelectorFromString(selectorName);
        if (![renderedImage respondsToSelector:selector]) {
            continue;
        }
        CGImageRef cgImage =
            ((CGImageRef (*)(id, SEL))objc_msgSend)(renderedImage, selector);
        if (cgImage != NULL) {
            return [UIImage imageWithCGImage:cgImage
                                      scale:scale
                                orientation:UIImageOrientationUp];
        }
    }

    SEL pngSelector = NSSelectorFromString(@"PNGRepresentation");
    if ([renderedImage respondsToSelector:pngSelector]) {
        NSData *pngData = ((id (*)(id, SEL))objc_msgSend)(
            renderedImage,
            pngSelector
        );
        if ([pngData isKindOfClass:[NSData class]] && pngData.length > 0) {
            return [UIImage imageWithData:pngData scale:scale];
        }
    }
    return nil;
}

static UIImage *CSLAppleWorkflowIconImage(NSNumber *colorValue,
                                          uint32_t glyphNumber,
                                          CGSize size) {
    if (![colorValue isKindOfClass:[NSNumber class]] ||
        glyphNumber == 0 || glyphNumber > UINT16_MAX ||
        !CSLPrepareAppleWorkflowIconRenderer()) {
        return nil;
    }

    @try {
        SEL iconInitializer = NSSelectorFromString(
            @"initWithBackgroundColorValue:glyphCharacter:customImageData:"
        );
        id workflowIcon =
            ((id (*)(id, SEL, int64_t, uint16_t, id))objc_msgSend)(
                [CSLWorkflowIconClass alloc],
                iconInitializer,
                colorValue.longLongValue,
                (uint16_t)glyphNumber,
                nil
            );
        if (workflowIcon == nil) {
            CSLLogAppleRenderFailureOnce(glyphNumber, @"workflow-icon");
            return nil;
        }

        id drawer = ((id (*)(id, SEL, id))objc_msgSend)(
            [CSLWorkflowIconDrawerClass alloc],
            NSSelectorFromString(@"initWithIcon:"),
            workflowIcon
        );
        if (drawer == nil) {
            CSLLogAppleRenderFailureOnce(glyphNumber, @"drawer");
            return nil;
        }

        CGFloat scale = MAX([UIScreen mainScreen].scale, 1.0);
        id renderedImage = ((id (*)(id, SEL, CGSize, CGFloat))objc_msgSend)(
            drawer,
            NSSelectorFromString(@"imageWithSize:scale:"),
            size,
            scale
        );
        if (renderedImage == nil) {
            SEL unscaledSelector = NSSelectorFromString(@"imageWithSize:");
            if ([drawer respondsToSelector:unscaledSelector]) {
                renderedImage = ((id (*)(id, SEL, CGSize))objc_msgSend)(
                    drawer,
                    unscaledSelector,
                    size
                );
            }
        }
        if (renderedImage == nil) {
            CSLLogAppleRenderFailureOnce(glyphNumber, @"workflow-image");
            return nil;
        }

        UIImage *image = CSLUIImageFromWorkflowImage(renderedImage, scale);

        if (![image isKindOfClass:[UIImage class]] || image.size.width <= 0.0 ||
            image.size.height <= 0.0) {
            CSLLogAppleRenderFailureOnce(glyphNumber, @"ui-image");
            return nil;
        }
        return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    } @catch (NSException *exception) {
        NSLog(@"[CCShortcutLauncher][Icon] APPLE_RENDER_EXCEPTION glyph=%u exception=%@ reason=%@",
              glyphNumber,
              exception.name,
              exception.reason);
        return nil;
    }
}

static NSString *CSLWorkflowGlyphFontName(void) {
    static NSString *fontName = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray<NSString *> *candidateNames = @[
            @"WorkflowGlyphs-Regular",
            @"Workflow Glyphs",
        ];
        for (NSString *candidate in candidateNames) {
            if ([UIFont fontWithName:candidate size:20.0] != nil) {
                fontName = candidate;
                break;
            }
        }

        if (fontName != nil) {
            return;
        }

        NSMutableArray<NSString *> *candidatePaths = [NSMutableArray array];
        NSBundle *voiceShortcutBundle = [NSBundle bundleWithPath:
            @"/System/Library/PrivateFrameworks/VoiceShortcutClient.framework"];
        NSString *bundleFontPath =
            [voiceShortcutBundle pathForResource:@"WorkflowGlyphs" ofType:@"ttf"];
        if (bundleFontPath.length > 0) {
            [candidatePaths addObject:bundleFontPath];
        }
        NSBundle *workflowKitBundle = [NSBundle bundleWithPath:
            @"/System/Library/PrivateFrameworks/WorkflowKit.framework"];
        NSString *workflowKitFontPath =
            [workflowKitBundle pathForResource:@"WorkflowGlyphs" ofType:@"ttf"];
        if (workflowKitFontPath.length > 0) {
            [candidatePaths addObject:workflowKitFontPath];
        }
        [candidatePaths addObjectsFromArray:@[
            @"/System/Library/Fonts/WorkflowGlyphs.ttf",
            @"/System/Library/PrivateFrameworks/VoiceShortcutClient.framework/WorkflowGlyphs.ttf",
            @"/System/Library/PrivateFrameworks/VoiceShortcutClient.framework/Resources/WorkflowGlyphs.ttf",
            @"/System/Library/PrivateFrameworks/WorkflowKit.framework/WorkflowGlyphs.ttf",
            @"/System/Library/PrivateFrameworks/WorkflowKit.framework/Resources/WorkflowGlyphs.ttf",
        ]];

        NSFileManager *fileManager = [NSFileManager defaultManager];
        for (NSString *path in candidatePaths) {
            if (![fileManager fileExistsAtPath:path]) {
                continue;
            }

            NSURL *fontURL = [NSURL fileURLWithPath:path];
            CFErrorRef registrationError = NULL;
            CTFontManagerRegisterFontsForURL(
                (__bridge CFURLRef)fontURL,
                kCTFontManagerScopeProcess,
                &registrationError
            );
            if (registrationError != NULL) {
                CFRelease(registrationError);
            }

            for (NSString *candidate in candidateNames) {
                if ([UIFont fontWithName:candidate size:20.0] != nil) {
                    fontName = candidate;
                    break;
                }
            }
            if (fontName != nil) {
                break;
            }
        }

        if (fontName == nil) {
            NSLog(@"[CCShortcutLauncher][Icon] WORKFLOW_FONT_UNAVAILABLE using=fallback");
        }
    });
    return fontName;
}

static UIColor *CSLShortcutColorFromValue(id value) {
    if (![value isKindOfClass:[NSNumber class]]) {
        return [UIColor systemIndigoColor];
    }

    uint32_t rgba = [(NSNumber *)value unsignedIntValue];
    CGFloat red = ((rgba >> 24) & 0xFF) / 255.0;
    CGFloat green = ((rgba >> 16) & 0xFF) / 255.0;
    CGFloat blue = ((rgba >> 8) & 0xFF) / 255.0;
    CGFloat alpha = (rgba & 0xFF) / 255.0;
    if (alpha <= 0.0) {
        alpha = 1.0;
    }
    return [UIColor colorWithRed:red green:green blue:blue alpha:alpha];
}

static void CSLDrawFallbackGlyphWithRatio(CGRect bounds, CGFloat fillRatio) {
    CGFloat pointSize = MIN(CGRectGetWidth(bounds), CGRectGetHeight(bounds)) * fillRatio;
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:pointSize
                                                        weight:UIImageSymbolWeightSemibold];
    UIImage *glyph = [[UIImage systemImageNamed:@"square.grid.2x2"
                             withConfiguration:configuration]
        imageWithTintColor:[UIColor whiteColor]
             renderingMode:UIImageRenderingModeAlwaysOriginal];
    if (glyph == nil) {
        return;
    }

    CGSize glyphSize = glyph.size;
    CGRect glyphRect = CGRectMake(
        CGRectGetMidX(bounds) - glyphSize.width / 2.0,
        CGRectGetMidY(bounds) - glyphSize.height / 2.0,
        glyphSize.width,
        glyphSize.height
    );
    [glyph drawInRect:glyphRect];
}

static void CSLDrawFallbackGlyph(CGRect bounds) {
    CSLDrawFallbackGlyphWithRatio(bounds, 0.54);
}

static BOOL CSLDrawWorkflowGlyphWithRatio(CGContextRef context,
                                          CGRect bounds,
                                          NSString *fontName,
                                          uint32_t glyphNumber,
                                          CGFloat fillRatio) {
    if (context == NULL || fontName.length == 0 ||
        glyphNumber == 0 || glyphNumber > UINT16_MAX) {
        return NO;
    }

    CTFontRef font = CTFontCreateWithName(
        (__bridge CFStringRef)fontName,
        100.0,
        NULL
    );
    if (font == NULL) {
        return NO;
    }

    UniChar character = (UniChar)glyphNumber;
    CGGlyph glyph = 0;
    BOOL mapped = CTFontGetGlyphsForCharacters(font, &character, &glyph, 1);
    CGPathRef glyphPath = mapped && glyph != 0
        ? CTFontCreatePathForGlyph(font, glyph, NULL)
        : NULL;
    CFRelease(font);
    if (glyphPath == NULL || CGPathIsEmpty(glyphPath)) {
        if (glyphPath != NULL) {
            CGPathRelease(glyphPath);
        }
        return NO;
    }

    CGRect pathBounds = CGPathGetBoundingBox(glyphPath);
    CGFloat maximumDimension = MAX(
        CGRectGetWidth(pathBounds),
        CGRectGetHeight(pathBounds)
    );
    if (maximumDimension <= 0.0) {
        CGPathRelease(glyphPath);
        return NO;
    }

    CGFloat targetDimension = MIN(
        CGRectGetWidth(bounds),
        CGRectGetHeight(bounds)
    ) * fillRatio;
    CGFloat scale = targetDimension / maximumDimension;

    CGContextSaveGState(context);
    CGContextSetFillColorWithColor(context, [UIColor whiteColor].CGColor);
    CGContextTranslateCTM(
        context,
        CGRectGetMidX(bounds),
        CGRectGetMidY(bounds)
    );
    CGContextScaleCTM(context, scale, -scale);
    CGContextTranslateCTM(
        context,
        -CGRectGetMidX(pathBounds),
        -CGRectGetMidY(pathBounds)
    );
    CGContextAddPath(context, glyphPath);
    CGContextFillPath(context);
    CGContextRestoreGState(context);
    CGPathRelease(glyphPath);
    return YES;
}

static BOOL CSLDrawWorkflowGlyph(CGContextRef context,
                                 CGRect bounds,
                                 NSString *fontName,
                                 uint32_t glyphNumber) {
    return CSLDrawWorkflowGlyphWithRatio(context, bounds, fontName, glyphNumber, 0.58);
}

/// Converts artwork with a mostly uniform background into a tintable template.
/// Boundary samples choose the dominant background colour, then only pixels
/// that differ from it become opaque. App icons additionally reject masks that
/// cover most of the source, avoiding the solid white square Control Center
/// would otherwise display.
static UIImage *CSLTemplateByRemovingBackground(UIImage *rendered,
                                                CGFloat maximumCoverageFraction) {
    CGImageRef source = rendered.CGImage;
    if (source == NULL) {
        return nil;
    }

    size_t width = CGImageGetWidth(source);
    size_t height = CGImageGetHeight(source);
    if (width == 0 || height == 0 || width > SIZE_MAX / height) {
        return nil;
    }

    size_t pixelCount = width * height;
    if (pixelCount > SIZE_MAX / 4) {
        return nil;
    }
    uint8_t *pixels = calloc(pixelCount, 4);
    if (pixels == NULL) {
        return nil;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (colorSpace == NULL) {
        free(pixels);
        return nil;
    }
    CGContextRef context = CGBitmapContextCreate(
        pixels,
        width,
        height,
        8,
        width * 4,
        colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
    );
    CGColorSpaceRelease(colorSpace);
    if (context == NULL) {
        free(pixels);
        return nil;
    }

    CGContextDrawImage(context, CGRectMake(0.0, 0.0, width, height), source);

    const size_t sampleCoordinates[][2] = {
        { 4, 1 }, { 4, 7 }, { 1, 4 }, { 7, 4 },
        { 2, 1 }, { 6, 1 }, { 2, 7 }, { 6, 7 },
    };
    uint8_t samples[8][3] = {0};
    size_t sampleCount = 0;
    for (size_t index = 0; index < 8; index++) {
        size_t x = MIN(width - 1, (width * sampleCoordinates[index][0]) / 8);
        size_t y = MIN(height - 1, (height * sampleCoordinates[index][1]) / 8);
        uint8_t *sample = &pixels[(y * width + x) * 4];
        if (sample[3] <= 200) {
            continue;
        }
        samples[sampleCount][0] = sample[0];
        samples[sampleCount][1] = sample[1];
        samples[sampleCount][2] = sample[2];
        sampleCount++;
    }

    if (sampleCount == 0) {
        CGContextRelease(context);
        free(pixels);
        return nil;
    }

    // Pick the sample closest to all the others. This resists a logo crossing
    // one boundary sample better than trusting a single fixed pixel.
    size_t backgroundSample = 0;
    NSUInteger bestScore = NSUIntegerMax;
    for (size_t candidate = 0; candidate < sampleCount; candidate++) {
        NSUInteger score = 0;
        for (size_t other = 0; other < sampleCount; other++) {
            score += abs((int)samples[candidate][0] - (int)samples[other][0]);
            score += abs((int)samples[candidate][1] - (int)samples[other][1]);
            score += abs((int)samples[candidate][2] - (int)samples[other][2]);
        }
        if (score < bestScore) {
            bestScore = score;
            backgroundSample = candidate;
        }
    }
    uint8_t backgroundR = samples[backgroundSample][0];
    uint8_t backgroundG = samples[backgroundSample][1];
    uint8_t backgroundB = samples[backgroundSample][2];

    // White premultiplied by an alpha of a is (a, a, a, a), so writing the
    // coverage into all four channels keeps the buffer valid. The bounds of
    // the drawn pixels are tracked so the padding Apple leaves around the
    // glyph can be cropped away; without that the module reads far smaller
    // than the system glyphs beside it.
    size_t minX = width, maxX = 0, minY = height, maxY = 0;
    size_t opaquePixelCount = 0;
    size_t coveredPixelCount = 0;
    for (size_t y = 0; y < height; y++) {
        for (size_t x = 0; x < width; x++) {
            uint8_t *pixel = &pixels[(y * width + x) * 4];

            // Outside the rounded tile the pixels are transparent, and their
            // premultiplied zero would otherwise read as a large difference.
            int coverage = 0;
            if (pixel[3] > 200) {
                opaquePixelCount++;
                int deltaR = abs((int)pixel[0] - (int)backgroundR);
                int deltaG = abs((int)pixel[1] - (int)backgroundG);
                int deltaB = abs((int)pixel[2] - (int)backgroundB);
                coverage = MAX(MAX(deltaR, deltaG), deltaB) * 2;
                coverage = MIN(coverage, 255);
            }

            pixel[0] = pixel[1] = pixel[2] = pixel[3] = (uint8_t)coverage;

            if (coverage > 24) {
                coveredPixelCount++;
                if (x < minX) minX = x;
                if (x > maxX) maxX = x;
                if (y < minY) minY = y;
                if (y > maxY) maxY = y;
            }
        }
    }

    UIImage *template = nil;
    CGFloat coverageFraction = opaquePixelCount > 0
        ? (CGFloat)coveredPixelCount / (CGFloat)opaquePixelCount
        : 1.0;
    BOOL acceptableCoverage =
        coveredPixelCount > 0 &&
        coverageFraction <= maximumCoverageFraction;
    if (acceptableCoverage && minX <= maxX && minY <= maxY) {
        CGImageRef masked = CGBitmapContextCreateImage(context);
        if (masked != NULL) {
            CGRect glyphBounds = CGRectMake(
                minX,
                minY,
                maxX - minX + 1,
                maxY - minY + 1
            );
            CGImageRef cropped = CGImageCreateWithImageInRect(masked, glyphBounds);
            if (cropped != NULL) {
                template = [[UIImage imageWithCGImage:cropped
                                                scale:rendered.scale
                                          orientation:UIImageOrientationUp]
                    imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                CGImageRelease(cropped);
            }
            CGImageRelease(masked);
        }
    }

    CGContextRelease(context);
    free(pixels);
    return template;
}

/// Control Center tints module glyphs, so the colourful tile Apple's renderer
/// produces cannot be handed over as it is. Remove the tile background and
/// retain only the glyph shape.
static UIImage *CSLTemplateFromAppleGlyph(uint32_t glyphNumber, CGSize size) {
    UIImage *rendered = CSLAppleWorkflowIconImage(@(0x000000FF), glyphNumber, size);
    return CSLTemplateByRemovingBackground(rendered, 1.0);
}

/// Uses the same owning-app artwork as Settings, but extracts its foreground
/// into the monochrome template format required by Control Center.
static UIImage *CSLTemplateFromApplicationIcon(NSString *bundleIdentifier,
                                               CGSize size) {
    UIImage *applicationIcon = CSLApplicationIconImage(bundleIdentifier);
    if (applicationIcon == nil) {
        return nil;
    }

    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    [applicationIcon drawInRect:CGRectMake(0.0, 0.0, size.width, size.height)];
    UIImage *rendered = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return CSLTemplateByRemovingBackground(rendered, 0.60);
}

UIImage *CSLShortcutGlyphTemplateImageForEntry(NSDictionary<NSString *, id> *entry,
                                               CGSize size) {
    if (size.width <= 0.0 || size.height <= 0.0) {
        CSLLogIconDecisionOnce(@"module", @"invalid-size", entry, size);
        return nil;
    }

    NSString *bundleIdentifier =
        [entry[@"appBundleID"] isKindOfClass:[NSString class]]
            ? entry[@"appBundleID"]
            : nil;
    if (bundleIdentifier.length > 0) {
        UIImage *applicationTemplate = CSLTemplateFromApplicationIcon(
            bundleIdentifier,
            size
        );
        if (applicationTemplate != nil) {
            CSLLogIconDecisionOnce(@"module", @"app-template", entry, size);
            return applicationTemplate;
        }
        CSLLogIconDecisionOnce(@"module", @"app-template-failed", entry, size);
    }

    NSNumber *glyphValue = [entry[@"iconGlyph"] isKindOfClass:[NSNumber class]]
        ? entry[@"iconGlyph"]
        : nil;
    uint32_t glyphNumber = glyphValue.unsignedIntValue;
    if (glyphNumber == 0 || glyphNumber > UINT16_MAX) {
        CSLLogIconDecisionOnce(@"module", @"missing-glyph", entry, size);
        return nil;
    }

    // Apple's renderer first: the glyph font on disk is missing entries the
    // renderer still draws, which left those modules on the generic mark.
    UIImage *appleTemplate = CSLTemplateFromAppleGlyph(glyphNumber, size);
    if (appleTemplate != nil) {
        CSLLogIconDecisionOnce(@"module", @"apple-template", entry, size);
        return appleTemplate;
    }

    NSString *fontName = CSLWorkflowGlyphFontName();
    if (fontName.length == 0) {
        CSLLogIconDecisionOnce(@"module", @"apple-failed-no-font", entry, size);
        return nil;
    }

    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGRect bounds = CGRectMake(0.0, 0.0, size.width, size.height);
    BOOL drawn = CSLDrawWorkflowGlyphWithRatio(
        UIGraphicsGetCurrentContext(),
        bounds,
        fontName,
        glyphNumber,
        0.86
    );
    UIImage *image = drawn ? UIGraphicsGetImageFromCurrentImageContext() : nil;
    UIGraphicsEndImageContext();
    CSLLogIconDecisionOnce(
        @"module",
        drawn ? @"font-template" : @"apple-and-font-failed",
        entry,
        size
    );
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static UIImage *CSLApplicationIconImage(NSString *bundleIdentifier) {
    if (bundleIdentifier.length == 0) {
        return nil;
    }

    SEL selector =
        NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    if (![UIImage respondsToSelector:selector]) {
        return nil;
    }

    @try {
        return ((UIImage *(*)(id, SEL, NSString *, int, CGFloat))objc_msgSend)(
            [UIImage class],
            selector,
            bundleIdentifier,
            2,
            UIScreen.mainScreen.scale
        );
    } @catch (NSException *exception) {
        NSLog(@"[CCShortcutLauncher][Icon] APP_ICON_EXCEPTION bundle=%@ exception=%@",
              bundleIdentifier,
              exception.name);
        return nil;
    }
}

/// Draw the owning app's icon directly on a transparent canvas. App icons
/// already contain their own artwork and mask, so adding the Shortcut's colour
/// behind them produces an unwanted green/blue border.
static UIImage *CSLApplicationIconImageForEntry(
    NSDictionary<NSString *, id> *entry,
    CGSize size
) {
    id bundleValue = entry[@"appBundleID"];
    if (![bundleValue isKindOfClass:[NSString class]]) {
        return nil;
    }
    UIImage *appIcon = CSLApplicationIconImage((NSString *)bundleValue);
    if (appIcon == nil) {
        return nil;
    }

    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGRect bounds = CGRectMake(0.0, 0.0, size.width, size.height);
    [appIcon drawInRect:bounds];

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

UIImage *CSLShortcutIconImageForEntry(NSDictionary<NSString *, id> *entry,
                                      CGSize size) {
    if (size.width <= 0.0 || size.height <= 0.0) {
        CSLLogIconDecisionOnce(@"tile", @"invalid-size", entry, size);
        return [UIImage new];
    }

    NSNumber *glyphValue = [entry[@"iconGlyph"] isKindOfClass:[NSNumber class]]
        ? entry[@"iconGlyph"]
        : nil;
    uint32_t glyphNumber = glyphValue.unsignedIntValue;
    UIImage *applicationIcon = CSLApplicationIconImageForEntry(entry, size);
    if (applicationIcon != nil) {
        CSLLogIconDecisionOnce(@"tile", @"app-icon", entry, size);
        return applicationIcon;
    }
    if ([entry[@"appBundleID"] isKindOfClass:[NSString class]]) {
        CSLLogIconDecisionOnce(@"tile", @"app-icon-unavailable", entry, size);
    }
    NSNumber *colorValue = [entry[@"iconColor"] isKindOfClass:[NSNumber class]]
        ? entry[@"iconColor"]
        : nil;
    UIImage *appleImage = CSLAppleWorkflowIconImage(
        colorValue,
        glyphNumber,
        size
    );
    if (appleImage != nil) {
        CSLLogIconDecisionOnce(@"tile", @"apple-tile", entry, size);
        return appleImage;
    }

    NSString *fontName = glyphNumber > 0 && glyphNumber <= UINT16_MAX
        ? CSLWorkflowGlyphFontName()
        : nil;

    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGRect bounds = CGRectMake(0.0, 0.0, size.width, size.height);
    CGFloat cornerRadius = MIN(size.width, size.height) * 0.22;
    UIBezierPath *background =
        [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:cornerRadius];
    [CSLShortcutColorFromValue(entry[@"iconColor"]) setFill];
    [background fill];

    CGContextRef context = UIGraphicsGetCurrentContext();
    BOOL drewWorkflowGlyph = CSLDrawWorkflowGlyph(
        context,
        bounds,
        fontName,
        glyphNumber
    );
    if (!drewWorkflowGlyph) {
        CSLDrawFallbackGlyph(bounds);
    }

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    CSLLogIconDecisionOnce(
        @"tile",
        drewWorkflowGlyph ? @"font-tile" : @"grid-fallback-tile",
        entry,
        size
    );
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

void CSLSetImageForAlertActionIfSupported(UIAlertAction *action,
                                          UIImage *image) {
    if (action == nil || image == nil) {
        return;
    }

    SEL setter = NSSelectorFromString(@"setImage:");
    if (![action respondsToSelector:setter]) {
        return;
    }

    @try {
        ((void (*)(id, SEL, id))objc_msgSend)(action, setter, image);
    } @catch (NSException *exception) {
        NSLog(@"[CCShortcutLauncher][Icon] ALERT_IMAGE_EXCEPTION exception=%@ reason=%@",
              exception.name,
              exception.reason);
    }
}
