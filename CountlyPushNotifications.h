// CountlyPushNotifications.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyPushNotifications : NSObject

@property (nonatomic, readwrite) BOOL isTestDevice;
@property (nonatomic, readwrite) BOOL shouldNotShowAlert;

+ (instancetype)sharedInstance;

#if TARGET_OS_IOS
- (void)startPushNotifications;
#endif
@end


#if TARGET_OS_IOS
@interface UIResponder (CountlyPushNotifications)
- (void)Countly_application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken;
- (void)Countly_application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error;
- (void)Countly_application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler;
@end
#endif