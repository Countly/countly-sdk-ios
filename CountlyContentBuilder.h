// CountlyContentBuilder.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#if (TARGET_OS_IOS)
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface CountlyContentBuilder: NSObject

+ (instancetype)sharedInstance;

/**
 * This is an experimental feature and it can have breaking changes
 * Opt in user for the content fetching and updates
 */
- (void)subscribeToContentBlock;

/**
 * This is an experimental feature and it can have breaking changes
 * Opt out user for the content fetching and updates
 */
- (void)exitFromContentBlock;

@end
#endif
