#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// Direct-file store, deliberately outside cfprefsd's domain files.
@interface PTPreferenceStore : NSObject
@property(nonatomic, readonly) NSString *path;
@property(nonatomic, readonly, nullable) NSString *lastError;
- (instancetype)initWithPath:(NSString *)path legacyPaths:(NSArray<NSString *> *)legacyPaths;
- (nullable NSDictionary *)snapshot;
// Always reads the latest file under a cross-process lock. NSNull removes a key.
- (BOOL)update:(NSDictionary *)values removingPrefixes:(NSArray<NSString *> *)prefixes;
@end
NS_ASSUME_NONNULL_END
