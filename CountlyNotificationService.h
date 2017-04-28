// CountlyNotificationService.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

#if TARGET_OS_IOS
#import <UserNotifications/UserNotifications.h>
#endif
extern NSString* const kCountlyActionIdentifier;

@interface CountlyNotificationService : NSObject
#if TARGET_OS_IOS
+ (void)didReceiveNotificationRequest:(UNNotificationRequest *)request withContentHandler:(void (^)(UNNotificationContent *))contentHandler;
#endif
@end
