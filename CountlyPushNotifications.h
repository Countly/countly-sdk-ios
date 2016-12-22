// CountlyPushNotifications.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

#if TARGET_OS_IOS
@interface CountlyPushNotifications : NSObject <UNUserNotificationCenterDelegate>
#else
@interface CountlyPushNotifications : NSObject
#endif

@property (nonatomic) BOOL isTestDevice;
@property (nonatomic) BOOL sendPushTokenAlways;
@property (nonatomic) BOOL doNotShowAlertForNotifications;

+ (instancetype)sharedInstance;

#if TARGET_OS_IOS
- (void)startPushNotifications;
- (void)askForNotificationPermissionWithOptions:(UNAuthorizationOptions)options completionHandler:(void (^)(BOOL granted, NSError * error))completionHandler;
#endif
@end


#if TARGET_OS_IOS
@interface UIResponder (CountlyPushNotifications)
- (void)Countly_application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken;
- (void)Countly_application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error;
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
- (void)Countly_application:(UIApplication *)application didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings;
#pragma GCC diagnostic pop

- (void)Countly_application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler;
@end
#endif
