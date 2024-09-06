// CountlyContentBuilder.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.


#import <Foundation/Foundation.h>
#if (TARGET_OS_IOS)
NS_ASSUME_NONNULL_BEGIN
@interface CountlyContentBuilder: NSObject
+ (instancetype)sharedInstance;

/**
 * This is an experimental feature and it can have breaking changes
 * Opt in user for the content fetching and updates
 */
- (void)enterContentZone;

/**
 * This is an experimental feature and it can have breaking changes
 * Opt out user for the content fetching and updates
 */
- (void)exitContentZone;

NS_ASSUME_NONNULL_END
@end
#else
@interface CountlyContentBuilder: NSObject
@end
#endif
