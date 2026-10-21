// CountlyContentBuilder.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.


#import <Foundation/Foundation.h>
#if (TARGET_OS_IOS || TARGET_OS_VISION)
#import <UIKit/UIKit.h>
#endif
NS_ASSUME_NONNULL_BEGIN
@interface CountlyContentBuilder: NSObject
#if (TARGET_OS_IOS || TARGET_OS_VISION)
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

/**
 * This is an experimental feature and it can have breaking changes
 * Previews a specific content by its ID.
 * This performs a one-time fetch for the given content
 * without starting periodic content updates.
 *
 * @param contentId the ID of the content to preview
 */
- (void)previewContent:(NSString *)contentId;

/**
 * This is an experimental feature and it can have breaking changes
 * Sets a segmentation recorded with every content and feedback widget event,
 * on top of the keys those events already report and without replacing them.
 * It is kept for as long as the app runs, including when a session ends and a
 * new one starts, and it is not restored after an app restart.
 *
 * @param segmentation the key/value pairs to add, 'nil' or empty clears them
 */
- (void)setGlobalContentSegmentation:(NSDictionary<NSString *, id> * _Nullable)segmentation;

#endif
NS_ASSUME_NONNULL_END
@end
