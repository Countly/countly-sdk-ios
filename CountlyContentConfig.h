//  CountlyContentConfig.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#if (TARGET_OS_IOS)
typedef enum : NSUInteger
{
    COMPLETED,
    CLOSED,
} ContentStatus;

typedef void (^ContentCallback)(ContentStatus contentStatus, NSDictionary<NSString *, id>* contentData);
#endif

@interface CountlyContentConfig : NSObject

#if (TARGET_OS_IOS)
/**
 * This is an experimental feature and it can have breaking changes
 * Register global completion blocks to be executed on content.
 */
- (void)setGlobalContentCallback:(ContentCallback) callback;

/**
 * This is an experimental feature and it can have breaking changes
 * Get content callback
 */
- (ContentCallback) getGlobalContentCallback;

/**
 * This is an experimental feature and it can have breaking changes
 * Set the interval for the automatic content update calls
 * @param zoneTimerIntervalSeconds in seconds
 *
 */
-(void)setZoneTimerInterval:(NSUInteger)zoneTimerIntervalSeconds;

/**
 * This is an experimental feature and it can have breaking changes
 * Get zone timer interval
 */
- (NSUInteger) getZoneTimerInterval;
#endif

NS_ASSUME_NONNULL_END

@end
