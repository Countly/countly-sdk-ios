// CountlyContentBuilder.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.


#import <Foundation/Foundation.h>
#if (TARGET_OS_IOS)
#import <UIKit/UIKit.h>
#endif
NS_ASSUME_NONNULL_BEGIN
@interface CountlyContentBuilder: NSObject
#if (TARGET_OS_IOS)
+ (instancetype)sharedInstance;

/**
 * Enables content fetching and updates for the user.
 * This method opts the user into receiving content updates
 * and ensures that relevant data is fetched accordingly.
 */
- (void)enterContentZone;

/**
 * Disables content fetching and updates for the user.
 * This method opts the user out of receiving content updates
 * and stops any ongoing content retrieval processes.
 */
- (void)exitContentZone;

/**
 * Triggers a manual refresh of the content zone.
 * This method forces an update by fetching the latest content,
 * ensuring the user receives the most up-to-date information.
 */
- (void)refreshContentZone;

#endif
NS_ASSUME_NONNULL_END
@end
