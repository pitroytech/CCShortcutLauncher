#import <CoreFoundation/CoreFoundation.h>
#import <Foundation/Foundation.h>

#import <fcntl.h>
#import <sqlite3.h>
#import <stdint.h>
#import <unistd.h>

static NSString *const CSLDatabaseDirectory =
    @"/private/var/mobile/Library/Shortcuts";
static NSString *const CSLDatabasePath =
    @"/private/var/mobile/Library/Shortcuts/Shortcuts.sqlite";
static CFStringRef const CSLPreferencesDomain =
    CFSTR("com.dinhnguyenx.ccshortcutlauncher");
static CFStringRef const CSLCatalogRequestedNotification =
    CFSTR("com.dinhnguyenx.ccshortcutlauncher/catalogRequested");

/// Shortcuts writes through a WAL, so a single edit produces a burst of file
/// events. Coalesce them instead of reading the database once per event.
static const int64_t CSLRefreshDebounceNanoseconds = 3 * NSEC_PER_SEC;
static const int64_t CSLWatchRearmNanoseconds = 2 * NSEC_PER_SEC;
static const int64_t CSLInitialLoadNanoseconds = 5 * NSEC_PER_SEC;
static const int64_t CSLInitialRetryNanoseconds = 30 * NSEC_PER_SEC;
static const NSUInteger CSLInitialLoadAttemptLimit = 4;

static dispatch_source_t CSLDatabaseWatchSource = nil;
static dispatch_source_t CSLDirectoryWatchSource = nil;
static uint64_t CSLRefreshGeneration = 0;

static BOOL CSLLoadShortcutCatalog(BOOL requestedByUser);
static void CSLStartWatchingDatabase(void);

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

/// Shortcuts an app donates through "Add to Siri" wear the app's icon instead
/// of a glyph, and the app is named in a column whose name moves between iOS
/// versions. Find it by shape rather than hardcoding one name.
static NSString *CSLAssociatedAppColumn(sqlite3 *database) {
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(database, "PRAGMA table_info(ZSHORTCUT)", -1, &statement, NULL)
        != SQLITE_OK) {
        return nil;
    }

    NSMutableArray<NSString *> *columns = [NSMutableArray array];
    while (sqlite3_step(statement) == SQLITE_ROW) {
        const unsigned char *nameText = sqlite3_column_text(statement, 1);
        if (nameText != NULL) {
            [columns addObject:
                [[NSString stringWithUTF8String:(const char *)nameText] uppercaseString]];
        }
    }
    sqlite3_finalize(statement);

    // Most specific first: a column naming the associated app beats a column
    // that merely happens to hold some bundle identifier.
    NSArray<NSArray<NSString *> *> *patterns = @[
        @[@"ASSOCIATEDAPP", @"BUNDLE"],
        @[@"APPBUNDLE"],
        @[@"BUNDLEIDENTIFIER"],
        @[@"BUNDLEID"],
    ];
    for (NSArray<NSString *> *pattern in patterns) {
        for (NSString *column in columns) {
            BOOL matches = YES;
            for (NSString *fragment in pattern) {
                if ([column rangeOfString:fragment].location == NSNotFound) {
                    matches = NO;
                    break;
                }
            }
            if (matches) {
                return column;
            }
        }
    }
    return nil;
}

/// Logs the column names once so a schema change is visible in the log.
static void CSLLogIconSchemaOnce(sqlite3 *database) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        for (NSString *table in @[@"ZSHORTCUT", @"ZSHORTCUTICON"]) {
            NSString *pragma =
                [NSString stringWithFormat:@"PRAGMA table_info(%@)", table];
            sqlite3_stmt *statement = NULL;
            if (sqlite3_prepare_v2(database, pragma.UTF8String, -1, &statement, NULL)
                != SQLITE_OK) {
                continue;
            }

            NSMutableArray<NSString *> *columns = [NSMutableArray array];
            while (sqlite3_step(statement) == SQLITE_ROW) {
                const unsigned char *nameText = sqlite3_column_text(statement, 1);
                if (nameText != NULL) {
                    [columns addObject:
                        [NSString stringWithUTF8String:(const char *)nameText]];
                }
            }
            sqlite3_finalize(statement);
            NSLog(@"[CCShortcutLauncher][Resolver] SCHEMA table=%@ columns=%@",
                  table,
                  [columns componentsJoinedByString:@","]);
        }
    });
}

/// Automatic refreshes must not leave an error behind: the Settings UI polls
/// ResolverState after a manual request and would read a stale failure.
static void CSLReportFailure(BOOL requestedByUser, NSString *message, NSString *reason) {
    if (requestedByUser) {
        CSLFinishWithError(message);
        return;
    }
    NSLog(@"[CCShortcutLauncher][Resolver] AUTO_REFRESH_SKIPPED reason=%@", reason);
}

static BOOL CSLCatalogEqualsStoredCatalog(NSArray<NSDictionary<NSString *, id> *> *catalog) {
    CFPropertyListRef value =
        CFPreferencesCopyAppValue(CFSTR("ShortcutsCatalog"), CSLPreferencesDomain);
    if (value == NULL) {
        return NO;
    }
    id stored = CFBridgingRelease(value);
    return [stored isKindOfClass:[NSArray class]] &&
        [(NSArray *)stored isEqualToArray:catalog];
}

static BOOL CSLLoadShortcutCatalog(BOOL requestedByUser) {
    if (requestedByUser) {
        CSLPublishResolverState(@"catalog_loading", nil);
    }

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
        CSLReportFailure(
            requestedByUser,
            @"The Shortcuts database is unavailable. Unlock the device and try again.",
            @"db_open_failed"
        );
        return NO;
    }
    sqlite3_busy_timeout(database, 1000);
    CSLLogIconSchemaOnce(database);

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
    NSString *appColumn = CSLAssociatedAppColumn(database);
    NSString *appSelection = appColumn != nil
        ? [NSString stringWithFormat:@"shortcut.%@", appColumn]
        : @"NULL";
    NSMutableString *query = [NSMutableString stringWithFormat:
        @"SELECT shortcut.ZWORKFLOWID, shortcut.ZNAME, %@, %@, %@ "
         "FROM ZSHORTCUT AS shortcut ",
        glyphSelection,
        colorSelection,
        appSelection];
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
        CSLReportFailure(
            requestedByUser,
            @"Unable to read the Shortcut catalog. Try again.",
            @"db_query_prepare_failed"
        );
        return NO;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *catalog =
        [NSMutableArray array];
    NSMutableSet<NSString *> *seenIdentifiers = [NSMutableSet set];
    NSUInteger skippedRows = 0;
    NSUInteger iconMetadataRows = 0;
    NSUInteger completeIconRows = 0;
    NSUInteger appIconRows = 0;

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
        const unsigned char *appText = sqlite3_column_text(statement, 4);
        if (appText != NULL) {
            NSString *bundleIdentifier =
                [[NSString stringWithUTF8String:(const char *)appText]
                    stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (bundleIdentifier.length > 0) {
                entry[@"appBundleID"] = bundleIdentifier;
                appIconRows++;
            }
        }
        if (hasGlyphValue) {
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
        CSLReportFailure(
            requestedByUser,
            @"Unable to read the complete Shortcut catalog. Try again.",
            @"db_query_step_failed"
        );
        return NO;
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
        // An empty catalog is a real state, not a failure: the user may have
        // deleted every Shortcut. Treating it as an error used to leave the
        // previous catalog in place, so deleted Shortcuts kept showing up.
        NSLog(@"[CCShortcutLauncher][Resolver] CATALOG_EMPTY skipped=%lu",
              (unsigned long)skippedRows);
    }

    // Published so Settings can show what the read found. Reading a device log
    // needs a toolchain most users do not have.
    CFPreferencesSetAppValue(
        CFSTR("ResolverAppColumn"),
        (__bridge CFStringRef)(appColumn ?: @"none"),
        CSLPreferencesDomain
    );
    CFPreferencesSetAppValue(
        CFSTR("ResolverAppIconCount"),
        (__bridge CFNumberRef)@(appIconRows),
        CSLPreferencesDomain
    );
    CFPreferencesSetAppValue(
        CFSTR("ResolverGlyphIconCount"),
        (__bridge CFNumberRef)@(iconMetadataRows),
        CSLPreferencesDomain
    );
    CFPreferencesSetAppValue(
        CFSTR("ResolverLastLoadDate"),
        (__bridge CFDateRef)[NSDate date],
        CSLPreferencesDomain
    );

    if (CSLCatalogEqualsStoredCatalog(catalog)) {
        CSLPublishResolverState(@"catalog_ready", nil);
        NSLog(@"[CCShortcutLauncher][Resolver] CATALOG_UNCHANGED count=%lu",
              (unsigned long)catalog.count);
        return YES;
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
    NSLog(@"[CCShortcutLauncher][Resolver] CATALOG_LOADED count=%lu skipped=%lu icons=%lu completeIcons=%lu appIcons=%lu appColumn=%@ synchronized=%d",
          (unsigned long)catalog.count,
          (unsigned long)skippedRows,
          (unsigned long)iconMetadataRows,
          (unsigned long)completeIconRows,
          (unsigned long)appIconRows,
          appColumn ?: @"none",
          synchronized);
    return YES;
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
        CSLLoadShortcutCatalog(YES);
    });
}

static void CSLScheduleAutomaticRefresh(void) {
    CSLRefreshGeneration++;
    uint64_t generation = CSLRefreshGeneration;
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, CSLRefreshDebounceNanoseconds),
        dispatch_get_main_queue(),
        ^{
            if (generation != CSLRefreshGeneration) {
                return;
            }
            CSLLoadShortcutCatalog(NO);
        }
    );
}

static dispatch_source_t CSLMakeVnodeSource(NSString *path,
                                            unsigned long mask,
                                            void (^handler)(unsigned long flags)) {
    int descriptor = open(path.fileSystemRepresentation, O_EVTONLY);
    if (descriptor < 0) {
        return nil;
    }

    dispatch_source_t source = dispatch_source_create(
        DISPATCH_SOURCE_TYPE_VNODE,
        (uintptr_t)descriptor,
        mask,
        dispatch_get_main_queue()
    );
    if (source == nil) {
        close(descriptor);
        return nil;
    }

    // Weak, so the source does not retain itself through its own handler.
    __weak dispatch_source_t weakSource = source;
    dispatch_source_set_event_handler(source, ^{
        dispatch_source_t liveSource = weakSource;
        if (liveSource == nil) {
            return;
        }
        handler(dispatch_source_get_data(liveSource));
    });
    dispatch_source_set_cancel_handler(source, ^{
        close(descriptor);
    });
    dispatch_resume(source);
    return source;
}

static void CSLRearmWatchLater(void) {
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, CSLWatchRearmNanoseconds),
        dispatch_get_main_queue(),
        ^{
            CSLStartWatchingDatabase();
        }
    );
}

static void CSLStartWatchingDatabase(void) {
    if (CSLDirectoryWatchSource != nil) {
        dispatch_source_cancel(CSLDirectoryWatchSource);
        CSLDirectoryWatchSource = nil;
    }
    if (CSLDatabaseWatchSource != nil) {
        dispatch_source_cancel(CSLDatabaseWatchSource);
        CSLDatabaseWatchSource = nil;
    }

    // The directory sees the WAL and shared-memory files come and go around a
    // write, and it also sees the database being replaced by a restore.
    CSLDirectoryWatchSource = CSLMakeVnodeSource(
        CSLDatabaseDirectory,
        DISPATCH_VNODE_WRITE | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME,
        ^(__unused unsigned long flags) {
            CSLScheduleAutomaticRefresh();
            if (CSLDatabaseWatchSource == nil) {
                // The database did not exist when the watch was set up.
                CSLRearmWatchLater();
            }
        }
    );

    // The database file itself sees checkpoints landing in the main file.
    CSLDatabaseWatchSource = CSLMakeVnodeSource(
        CSLDatabasePath,
        DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_ATTRIB |
            DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME,
        ^(unsigned long flags) {
            CSLScheduleAutomaticRefresh();
            if ((flags & (DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME)) != 0) {
                // This descriptor no longer points at the live database.
                CSLRearmWatchLater();
            }
        }
    );

    NSLog(@"[CCShortcutLauncher][Resolver] WATCHING directory=%d database=%d",
          CSLDirectoryWatchSource != nil,
          CSLDatabaseWatchSource != nil);
}

static void CSLPerformInitialLoad(NSUInteger attempt) {
    if (CSLLoadShortcutCatalog(NO) || attempt + 1 >= CSLInitialLoadAttemptLimit) {
        return;
    }

    // Right after boot the database can still be locked behind first unlock.
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, CSLInitialRetryNanoseconds),
        dispatch_get_main_queue(),
        ^{
            CSLPerformInitialLoad(attempt + 1);
        }
    );
}

int main(__unused int argc, __unused char *argv[]) {
    @autoreleasepool {
        NSLog(@"[CCShortcutLauncher][Resolver] START version=1.4.7 uid=%u",
              geteuid());

        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            CSLCatalogRequested,
            CSLCatalogRequestedNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately
        );

        CSLStartWatchingDatabase();
        dispatch_after(
            dispatch_time(DISPATCH_TIME_NOW, CSLInitialLoadNanoseconds),
            dispatch_get_main_queue(),
            ^{
                CSLPerformInitialLoad(0);
            }
        );

        NSLog(@"[CCShortcutLauncher][Resolver] WAITING_FOR_REQUEST");
        [[NSRunLoop currentRunLoop] run];
        return 0;
    }
}
