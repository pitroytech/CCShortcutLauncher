#import "PTPreferenceStore.h"
#import <sys/wait.h>
#import <spawn.h>
extern char **environ;
#define CHECK(...) do { if (!(__VA_ARGS__)) { NSLog(@"FAIL line %d: %s", __LINE__, #__VA_ARGS__); exit(1); } } while (0)
int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc == 4) {
            PTPreferenceStore *s = [[PTPreferenceStore alloc] initWithPath:@(argv[2]) legacyPaths:@[]];
            for (int n = 0; n < 12; n++) {
                NSString *key = [NSString stringWithFormat:@"writer-%s-%d", argv[3], n];
                CHECK([s update:@{key:@(n)} removingPrefixes:@[]]);
            }
            return 0;
        }
        NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        CHECK([NSFileManager.defaultManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil]);
        NSString *path = [dir stringByAppendingPathComponent:@"new.plist"];
        NSString *legacy = [dir stringByAppendingPathComponent:@"old.plist"];
        CHECK([@{@"HoldApps":@[@"test.one"], @"HoldListMode":@YES, @"RecoveryV1":@{@"v":@1}, @"App.test.one":@1}
            writeToFile:legacy atomically:YES]);
        PTPreferenceStore *a = [[PTPreferenceStore alloc] initWithPath:path legacyPaths:@[legacy]];
        CHECK([[a snapshot][@"HoldApps"] isEqual:@[@"test.one"]]);
        PTPreferenceStore *b = [[PTPreferenceStore alloc] initWithPath:path legacyPaths:@[legacy]];
        CHECK([a update:@{@"HoldApps":@[@"test.two"]} removingPrefixes:@[]]);
        CHECK([b update:@{@"LastEventReport":@"event"} removingPrefixes:@[]]);
        CHECK([[b snapshot][@"HoldApps"] isEqual:@[@"test.two"]]);
        // Legacy cache flush must not replace new settings.
        CHECK([@{@"HoldApps":@[@"stale"]} writeToFile:legacy atomically:YES]);
        CHECK([[a snapshot][@"HoldApps"] isEqual:@[@"test.two"]]);
        CHECK([a update:@{@"HoldApps":@[]} removingPrefixes:@[]]);
        CHECK([[b snapshot][@"HoldApps"] isEqual:@[]]);
        CHECK([a update:@{@"Enabled":@YES} removingPrefixes:@[@"App."]]);
        CHECK([b snapshot][@"App.test.one"] == nil);
        CHECK([b snapshot][@"RecoveryV1"] != nil);
        // Concurrent independent processes must merge disjoint key edits.
        pid_t children[3];
        for (int i = 0; i < 3; i++) {
            NSString *label = [NSString stringWithFormat:@"%d", i];
            char *args[] = {(char *)argv[0], "writer", (char *)path.fileSystemRepresentation, (char *)label.UTF8String, NULL};
            CHECK(posix_spawn(&children[i], argv[0], NULL, NULL, args, environ) == 0);
        }
        for (int i = 0; i < 3; i++) { int status; CHECK(waitpid(children[i], &status, 0) > 0); CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0); }
        NSDictionary *snapshot = [b snapshot];
        for (int i = 0; i < 3; i++) for (int n = 0; n < 12; n++)
            CHECK([snapshot[[NSString stringWithFormat:@"writer-%d-%d", i, n]] intValue] == n && snapshot[[NSString stringWithFormat:@"writer-%d-%d", i, n]] != nil);
        // Corrupt file: fail closed, never replace with defaults or old plist.
        NSData *broken = [@"broken" dataUsingEncoding:NSUTF8StringEncoding];
        CHECK([broken writeToFile:path atomically:YES]);
        CHECK([a snapshot] == nil);
        CHECK(![a update:@{@"Enabled":@YES} removingPrefixes:@[]]);
        CHECK([[NSData dataWithContentsOfFile:path] isEqual:broken]);
        CHECK(a.lastError.length > 0);
        CHECK([NSFileManager.defaultManager removeItemAtPath:dir error:nil]);
        NSLog(@"PASS: migration, cold instance, concurrent writers, legacy flush, explicit empty list, reset preservation, corrupt-file protection");
    }
    return 0;
}
