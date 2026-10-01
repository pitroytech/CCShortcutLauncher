#import "PTPreferenceStore.h"
#import <sys/file.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <stdlib.h>
#import <string.h>
#import <stdio.h>

@implementation PTPreferenceStore {
    NSArray<NSString *> *_legacyPaths;
    NSString *_lastError;
}
- (instancetype)initWithPath:(NSString *)path legacyPaths:(NSArray<NSString *> *)legacyPaths {
    if ((self = [super init])) { _path = [path copy]; _legacyPaths = [legacyPaths copy]; }
    return self;
}
- (NSString *)lastError { @synchronized(self) { return _lastError; } }
- (void)failed:(NSString *)stage error:(NSError *)error {
    _lastError = [NSString stringWithFormat:@"%@: %@", stage, error.localizedDescription ?: @"unknown error"];
    NSLog(@"[Preferences][Storage] %@: %@", _path.lastPathComponent, _lastError);
}
- (int)lockStore {
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:_path.stringByDeletingLastPathComponent
        withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error]) {
        [self failed:@"directory" error:error]; return -1;
    }
    int fd = open([_path stringByAppendingString:@".lock"].fileSystemRepresentation,
                  O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd < 0) { [self failed:@"lock open" error:[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]]; return -1; }
    // Bounded lock wait: do not hang SpringBoard if another process is stopped.
    for (unsigned i = 0; i < 50; i++) {
        if (flock(fd, LOCK_EX | LOCK_NB) == 0) return fd;
        if (errno != EWOULDBLOCK && errno != EINTR) break;
        usleep(2000);
    }
    [self failed:@"lock timeout" error:[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]];
    close(fd); return -1;
}
- (NSDictionary *)readPath:(NSString *)path missing:(BOOL *)missing {
    *missing = NO;
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) != 0) {
        if (errno == ENOENT) { *missing = YES; return nil; }
        [self failed:@"stat" error:[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]];
        return nil;
    }
    if (!S_ISREG(st.st_mode) || st.st_size > 33554432) {
        [self failed:@"invalid preference file" error:nil]; return nil;
    }
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:&error];
    id value = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:&error] : nil;
    if (![value isKindOfClass:NSDictionary.class]) {
        [self failed:@"read/parse" error:error]; return nil;
    }
    return value;
}
- (BOOL)writeSnapshot:(NSDictionary *)value {
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:value format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    if (!data || data.length > 33554432) { [self failed:@"serialize/size limit" error:error]; return NO; }
    // Same-directory temporary file + fsync + rename. Lock is a separate inode.
    char *temp = strdup([_path stringByAppendingString:@".XXXXXX"].fileSystemRepresentation);
    if (!temp) { [self failed:@"allocation" error:nil]; return NO; }
    int fd = mkstemp(temp);
    BOOL ok = fd >= 0;
    const char *bytes = data.bytes; NSUInteger left = data.length;
    while (ok && left) {
        ssize_t n = write(fd, bytes, left);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) { ok = NO; break; }
        bytes += n; left -= (NSUInteger)n;
    }
    if (ok) ok = fsync(fd) == 0;
    int failure = errno;
    if (fd >= 0 && close(fd) != 0 && ok) { ok = NO; failure = errno; }
    if (ok && rename(temp, _path.fileSystemRepresentation) != 0) { ok = NO; failure = errno; }
    if (!ok) [self failed:@"commit" error:[NSError errorWithDomain:NSPOSIXErrorDomain code:failure userInfo:nil]];
    unlink(temp); free(temp);
    if (!ok) return NO;
    BOOL missing = NO;
    if (![[self readPath:_path missing:&missing] isEqual:value]) {
        [self failed:@"disk readback mismatch" error:nil]; return NO;
    }
    return YES;
}
- (NSDictionary *)readLocked {
    BOOL missing = NO;
    NSDictionary *current = [self readPath:_path missing:&missing];
    if (!missing) return current; // Corrupt/unreadable is NOT an empty config.
    // One-time migration: canonical jailbreak path wins, never merge stale keys.
    // Legacy files remain untouched for inspection / rollback.
    NSDictionary *legacy = @{};
    for (NSString *path in _legacyPaths) {
        NSDictionary *candidate = [self readPath:path missing:&missing];
        if (!missing) { if (!candidate) return nil; legacy = candidate; break; }
    }
    return [self writeSnapshot:legacy] ? legacy : nil;
}
- (NSDictionary *)snapshot {
    @synchronized(self) {
        _lastError = nil;
        int fd = [self lockStore]; if (fd < 0) return nil;
        NSDictionary *result;
        @try { result = [self readLocked]; }
        @finally { flock(fd, LOCK_UN); close(fd); }
        return result;
    }
}
- (BOOL)update:(NSDictionary *)values removingPrefixes:(NSArray<NSString *> *)prefixes {
    @synchronized(self) {
        _lastError = nil;
        int fd = [self lockStore]; if (fd < 0) return NO;
        BOOL ok = NO;
        @try {
            NSMutableDictionary *next = [[self readLocked] mutableCopy];
            if (next) {
                for (NSString *key in next.allKeys)
                    for (NSString *prefix in prefixes)
                        if ([key hasPrefix:prefix]) { [next removeObjectForKey:key]; break; }
                for (NSString *key in values) {
                    if (values[key] == NSNull.null) [next removeObjectForKey:key];
                    else next[key] = values[key];
                }
                ok = [self writeSnapshot:next];
            }
        } @finally { flock(fd, LOCK_UN); close(fd); }
        return ok;
    }
}
@end
