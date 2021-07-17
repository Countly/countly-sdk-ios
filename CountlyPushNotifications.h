// CountlyPushNotifications.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyPushNotifications : NSObject
#ifndef COUNTLY_EXCLUDE_PUSHNOTIFICATIONS
@property (nonatomic) BOOL isEnabledOnInitialConfig;
@property (nonatomic) NSString* pushTestMode;
@property (nonatomic) BOOL sendPushTokenAlways;
@property (nonatomic) BOOL doNotShowAlertForNotifications;
@property (nonatomic) NSNotification* launchNotification;

+ (instancetype)sharedInstance;

#if (TARGET_OS_IOS || TARGET_OS_OSX)
- (void)startPushNotifications NS_EXTENSION_UNAVAILABLE_IOS("Only available from application containers.");
- (void)stopPushNotifications NS_EXTENSION_UNAVAILABLE_IOS("Only available from application containers.");
- (void)askForNotificationPermissionWithOptions:(NSUInteger)options completionHandler:(void (^)(BOOL granted, NSError * error))completionHandler NS_EXTENSION_UNAVAILABLE_IOS("Only available from application containers.");
- (void)recordActionForNotification:(NSDictionary *)userInfo clickedButtonIndex:(NSInteger)buttonIndex NS_EXTENSION_UNAVAILABLE_IOS("Only available from application containers.");
- (void)sendToken NS_EXTENSION_UNAVAILABLE_IOS("Only available from application containers.");
- (void)clearToken NS_EXTENSION_UNAVAILABLE_IOS("Only available from application containers.");
#endif
#endif
@end
