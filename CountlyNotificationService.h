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

extern NSString* const kCountlyPNKeyCountlyPayload;
extern NSString* const kCountlyPNKeyNotificationID;
extern NSString* const kCountlyPNKeyButtons;
extern NSString* const kCountlyPNKeyDefaultURL;
extern NSString* const kCountlyPNKeyAttachment;
extern NSString* const kCountlyPNKeyActionButtonIndex;
extern NSString* const kCountlyPNKeyActionButtonTitle;
extern NSString* const kCountlyPNKeyActionButtonURL;

@interface CountlyNotificationService : NSObject
#if TARGET_OS_IOS
+ (void)didReceiveNotificationRequest:(UNNotificationRequest *)request withContentHandler:(void (^)(UNNotificationContent *))contentHandler;
#endif
@end
