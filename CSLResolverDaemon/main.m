#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#import <sqlite3.h>
#import <stdint.h>
#import <unistd.h>

static NSString *const CSLDatabasePath =
    @"/private/var/mobile/Library/Shortcuts/Shortcuts.sqlite";
static CFStringRef const CSLPreferencesDomain =
    CFSTR("com.dinhnguyenx.ccshortcutlauncher");
static CFStringRef const CSLCatalogRequestedNotification =
    CFSTR("com.dinhnguyenx.ccshortcutlauncher/catalogRequested");

static BOOL CSLPublishResolverState(NSString *state, NSString *message) {
    CFPreferencesSetAppValue(
        CFSTR("ResolverState"),
        (__bridge CFStringRef)state,
        CSLPreferencesDomain
    );
    CFPreferencesSetAppValue(
        CFSTR("ResolverMessage"),
        message != nil ? (__bridge CFStringRef)message : NULL,
        CSLPreferencesDomain
    );
    return CFPreferencesAppSynchronize(CSLPreferencesDomain);
}

static void CSLFinishWithError(NSString *message) {
    BOOL synchronized = CSLPublishResolverState(@"error", message);
    NSLog(@"[CCShortcutLauncher][Resolver] ERROR_PUBLISHED synchronized=%d message=\"%@\"",
          synchronized,
          message);
}

static BOOL CSLTableHasColumn(sqlite3 *database, NSString *table, NSString *column) {
    NSString *pragma = [NSString stringWithFormat:@"PRAGMA table_info(%@)", table];
    sqlite3_stmt *statement = NULL;
    int result = sqlite3_prepare_v2(
        database,
        pragma.UTF8String,
        -1,
        &statement,
        NULL
    );
    if (result != SQLITE_OK) {
        return NO;
    }

    BOOL found = NO;
    while (sqlite3_step(statement) == SQLITE_ROW) {
        const unsigned char *nameText = sqlite3_column_text(statement, 1);
        if (nameText == NULL) {
            continue;
        }
        NSString *name = [NSString stringWithUTF8String:(const char *)nameText];
        if ([name caseInsensitiveCompare:column] == NSOrderedSame) {
            found = YES;
            break;
        }
    }
    sqlite3_finalize(statement);
    return found;
}

static void CSLLoadShortcutCatalog(void) {
    CSLPublishResolverState(@"catalog_loading", nil);

    sqlite3 *database = NULL;
    int result = sqlite3_open_v2(
        CSLDatabasePath.fileSystemRepresentation,
        &database,
        SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
        NULL
    );
    if (result != SQLITE_OK) {
        const char *message =
            database != NULL ? sqlite3_errmsg(database) : "database handle unavailable";
        NSLog(@"[CCShortcutLauncher][Resolver] DB_OPEN_FAILED code=%d message=%s path=%@",
              result,
              message,
              CSLDatabasePath);
        if (database != NULL) {
            sqlite3_close(database);
        }
        CSLFinishWithError(
            @"The Shortcuts database is unavailable. Unlock the device and try again."
        );
        return;
    }
    sqlite3_busy_timeout(database, 1000);

    BOOL hasTombstoned = CSLTableHasColumn(database, @"ZSHORTCUT", @"ZTOMBSTONED");
    BOOL hasHiddenFromLibrary = CSLTableHasColumn(
        database,
        @"ZSHORTCUT",
        @"ZHIDDENFROMLIBRARYANDSYNC"
    );
    BOOL hasShortcutIconReference =
        CSLTableHasColumn(database, @"ZSHORTCUT", @"ZICON");
    BOOL hasIconPrimaryKey =
        CSLTableHasColumn(database, @"ZSHORTCUTICON", @"Z_PK");
    BOOL hasIconGlyph =
        CSLTableHasColumn(database, @"ZSHORTCUTICON", @"ZGLYPHNUMBER");
    BOOL hasIconColor = CSLTableHasColumn(
        database,
        @"ZSHORTCUTICON",
        @"ZBACKGROUNDCOLORVALUE"
    );
    BOOL canJoinIcon = hasShortcutIconReference && hasIconPrimaryKey;
    NSString *glyphSelection = canJoinIcon && hasIconGlyph
        ? @"icon.ZGLYPHNUMBER"
        : @"NULL";
    NSString *colorSelection = canJoinIcon && hasIconColor
        ? @"icon.ZBACKGROUNDCOLORVALUE"
        : @"NULL";
    NSMutableString *query = [NSMutableString stringWithFormat:
        @"SELECT shortcut.ZWORKFLOWID, shortcut.ZNAME, %@, %@ "
         "FROM ZSHORTCUT AS shortcut ",
        glyphSelection,
        colorSelection];
    if (canJoinIcon) {
        [query appendString:
            @"LEFT JOIN ZSHORTCUTICON AS icon ON shortcut.ZICON = icon.Z_PK "];
    }
    [query appendString:
        @"WHERE shortcut.ZWORKFLOWID IS NOT NULL "
         "AND length(shortcut.ZWORKFLOWID) > 0 "
         "AND shortcut.ZNAME IS NOT NULL "
         "AND length(trim(shortcut.ZNAME)) > 0 "];
    if (hasTombstoned) {
        [query appendString:@"AND COALESCE(shortcut.ZTOMBSTONED, 0) = 0 "];
    }
    if (hasHiddenFromLibrary) {
        [query appendString:
            @"AND COALESCE(shortcut.ZHIDDENFROMLIBRARYANDSYNC, 0) = 0 "];
    }
    sqlite3_stmt *statement = NULL;
    result = sqlite3_prepare_v2(database, query.UTF8String, -1, &statement, NULL);
    if (result != SQLITE_OK) {
        NSLog(@"[CCShortcutLauncher][Resolver] DB_QUERY_PREPARE_FAILED code=%d message=%s",
              result,
              sqlite3_errmsg(database));
        sqlite3_close(database);
        CSLFinishWithError(@"Unable to read the Shortcut catalog. Try again.");
        return;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *catalog =
        [NSMutableArray array];
    NSMutableSet<NSString *> *seenIdentifiers = [NSMutableSet set];
    NSUInteger skippedRows = 0;
    NSUInteger iconMetadataRows = 0;
    NSUInteger completeIconRows = 0;

    while ((result = sqlite3_step(statement)) == SQLITE_ROW) {
        const unsigned char *identifierText = sqlite3_column_text(statement, 0);
        const unsigned char *nameText = sqlite3_column_text(statement, 1);
        if (identifierText == NULL || nameText == NULL) {
            skippedRows++;
            continue;
        }

        NSString *identifier =
            [NSString stringWithUTF8String:(const char *)identifierText];
        NSString *shortcutName =
            [[NSString stringWithUTF8String:(const char *)nameText]
                stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:identifier];
        if (uuid == nil || shortcutName.length == 0) {
            skippedRows++;
            continue;
        }

        NSString *normalizedIdentifier = uuid.UUIDString;
        if ([seenIdentifiers containsObject:normalizedIdentifier]) {
            skippedRows++;
            continue;
        }
        [seenIdentifiers addObject:normalizedIdentifier];
        NSMutableDictionary<NSString *, id> *entry = [@{
            @"name": shortcutName,
            @"workflowID": normalizedIdentifier,
        } mutableCopy];
        BOOL hasGlyphValue = sqlite3_column_type(statement, 2) != SQLITE_NULL;
        BOOL hasColorValue = sqlite3_column_type(statement, 3) != SQLITE_NULL;
        if (hasGlyphValue) {
            sqlite3_int64 rawGlyph = sqlite3_column_int64(statement, 2);
            if (rawGlyph > 0 && rawGlyph <= UINT32_MAX) {
                entry[@"iconGlyph"] = @((uint32_t)rawGlyph);
            } else {
                hasGlyphValue = NO;
            }
        }
        if (hasColorValue) {
            sqlite3_int64 rawColor = sqlite3_column_int64(statement, 3);
            entry[@"iconColor"] = @((uint32_t)rawColor);
        }
        if (hasGlyphValue || hasColorValue) {
            iconMetadataRows++;
        }
        if (hasGlyphValue && hasColorValue) {
            completeIconRows++;
        }
        [catalog addObject:entry];
    }

    if (result != SQLITE_DONE) {
        NSLog(@"[CCShortcutLauncher][Resolver] DB_QUERY_STEP_FAILED code=%d message=%s",
              result,
              sqlite3_errmsg(database));
        sqlite3_finalize(statement);
        sqlite3_close(database);
        CSLFinishWithError(@"Unable to read the complete Shortcut catalog. Try again.");
        return;
    }

    sqlite3_finalize(statement);
    sqlite3_close(database);

    [catalog sortUsingComparator:^NSComparisonResult(
        NSDictionary<NSString *, id> *left,
        NSDictionary<NSString *, id> *right
    ) {
        NSComparisonResult nameResult =
            [left[@"name"] localizedCaseInsensitiveCompare:right[@"name"]];
        if (nameResult != NSOrderedSame) {
            return nameResult;
        }
        return [left[@"workflowID"] compare:right[@"workflowID"]];
    }];

    if (catalog.count == 0) {
        NSLog(@"[CCShortcutLauncher][Resolver] CATALOG_EMPTY skipped=%lu",
              (unsigned long)skippedRows);
        CSLFinishWithError(@"No valid Shortcuts were found in My Shortcuts.");
        return;
    }

    CFPreferencesSetAppValue(
        CFSTR("ShortcutsCatalog"),
        (__bridge CFArrayRef)catalog,
        CSLPreferencesDomain
    );
    NSNumber *catalogCount = @(catalog.count);
    CFPreferencesSetAppValue(
        CFSTR("ShortcutsCatalogCount"),
        (__bridge CFNumberRef)catalogCount,
        CSLPreferencesDomain
    );
    BOOL synchronized = CSLPublishResolverState(@"catalog_ready", nil);
    NSLog(@"[CCShortcutLauncher][Resolver] CATALOG_LOADED count=%lu skipped=%lu icons=%lu completeIcons=%lu synchronized=%d",
          (unsigned long)catalog.count,
          (unsigned long)skippedRows,
          (unsigned long)iconMetadataRows,
          (unsigned long)completeIconRows,
          synchronized);
}

static void CSLCatalogRequested(
    __unused CFNotificationCenterRef center,
    __unused void *observer,
    __unused CFStringRef name,
    __unused const void *object,
    __unused CFDictionaryRef userInfo
) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"[CCShortcutLauncher][Resolver] CATALOG_REQUESTED");
        CSLLoadShortcutCatalog();
    });
}

int main(__unused int argc, __unused char *argv[]) {
    @autoreleasepool {
        NSLog(@"[CCShortcutLauncher][Resolver] START version=1.3.0 uid=%u",
              geteuid());

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            CSLCatalogRequested,
            CSLCatalogRequestedNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );

        NSLog(@"[CCShortcutLauncher][Resolver] WAITING_FOR_REQUEST");
        [[NSRunLoop currentRunLoop] run];
        return 0;
    }
}
