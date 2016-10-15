// CountlyPushNotifications.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

NSString* const kCountlyReservedEventPushOpen = @"[CLY]_push_open";
NSString* const kCountlyReservedEventPushAction = @"[CLY]_push_action";
NSString* const kCountlyTokenError = @"kCountlyTokenError";

#if TARGET_OS_IOS
static char kUIAlertViewAssociatedObjectKey;
#endif

@interface CountlyPushNotifications ()
@property (strong) NSString* token;
@end

@implementation CountlyPushNotifications

+ (instancetype)sharedInstance
{
    static CountlyPushNotifications* s_sharedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {

    }

    return self;
}

#pragma mark ---

#if TARGET_OS_IOS

- (void)startPushNotifications
{
    Class appDelegateClass = UIApplication.sharedApplication.delegate.class;
    NSArray* selectors = @[@"application:didRegisterForRemoteNotificationsWithDeviceToken:",
                           @"application:didFailToRegisterForRemoteNotificationsWithError:",
                           @"application:didRegisterUserNotificationSettings:",
                           @"application:didReceiveRemoteNotification:fetchCompletionHandler:"];

    for (NSString* selectorString in selectors)
    {
        SEL originalSelector = NSSelectorFromString(selectorString);
        Method originalMethod = class_getInstanceMethod(appDelegateClass, originalSelector);

        if(originalMethod == NULL)
        {
            Method method = class_getInstanceMethod(self.class, originalSelector);
            IMP imp = method_getImplementation(method);
            const char *methodTypeEncoding = method_getTypeEncoding(method);
            class_addMethod(appDelegateClass, originalSelector, imp, methodTypeEncoding);
            originalMethod = class_getInstanceMethod(appDelegateClass, originalSelector);
        }

        SEL countlySelector = NSSelectorFromString([@"Countly_" stringByAppendingString:selectorString]);
        Method countlyMethod = class_getInstanceMethod(appDelegateClass, countlySelector);
        method_exchangeImplementations(originalMethod, countlyMethod);
    }
}

- (void)sendToken
{
    if(!self.token)
        return;

#if __IPHONE_OS_VERSION_MIN_REQUIRED < __IPHONE_8_0
    BOOL userPermission = UIApplication.sharedApplication.enabledRemoteNotificationTypes != UIRemoteNotificationTypeNone;
#else
    BOOL userPermission= UIApplication.sharedApplication.currentUserNotificationSettings.types != UIUserNotificationTypeNone;
#endif

    if([self.token isEqualToString:kCountlyTokenError])
        [CountlyConnectionManager.sharedInstance sendPushToken:@""];
    else if(userPermission || self.sendPushTokenAlways)
        [CountlyConnectionManager.sharedInstance sendPushToken:self.token];
}

- (void)handleNotification:(NSDictionary *)notification
{
    COUNTLY_LOG(@"Handling remote notification %@", notification);

    NSDictionary* countlyPayload = notification[@"c"];
    NSString* countlyPushNotificationID = countlyPayload[@"i"];
    if (countlyPushNotificationID)
    {
        COUNTLY_LOG(@"Countly Push Notification ID: %@", countlyPushNotificationID);

        [Countly.sharedInstance recordEvent:kCountlyReservedEventPushOpen segmentation:@{@"i":countlyPushNotificationID}];

        NSString* message = notification[@"aps"][@"alert"];
        if(!message || self.doNotShowAlertForNotifications)
            return;

        NSString* title = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
        NSString* cancelButtonTitle = countlyPayload[@"c"];
        NSString* actionButtonTitle = nil;

        if (countlyPayload[@"l"])
        {
            if (!cancelButtonTitle) cancelButtonTitle = NSLocalizedString(@"Cancel", nil);;

            actionButtonTitle = countlyPayload[@"a"];
            if (!actionButtonTitle) actionButtonTitle = NSLocalizedString(@"Open", nil);
        }
        else
        {
            if (!cancelButtonTitle) cancelButtonTitle = NSLocalizedString(@"Dismiss", nil);;
        }

        if(UIAlertController.class)
        {
            UIAlertController* alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction* cancel = [UIAlertAction actionWithTitle:cancelButtonTitle style:UIAlertActionStyleCancel handler:nil];
            [alertController addAction:cancel];

            if(actionButtonTitle)
            {
                UIAlertAction* other = [UIAlertAction actionWithTitle:actionButtonTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * action)
                {
                    [self takeActionWithCountlyPayload:countlyPayload];
                }];

                [alertController addAction:other];
            }

            UIViewController* rvc = UIApplication.sharedApplication.keyWindow.rootViewController;
            [rvc presentViewController:alertController animated:YES completion:nil];
        }
        else
        {
            UIAlertView* alertView = [UIAlertView.alloc initWithTitle:title message:message delegate:self cancelButtonTitle:cancelButtonTitle otherButtonTitles:actionButtonTitle, nil];
            objc_setAssociatedObject(self, &kUIAlertViewAssociatedObjectKey, countlyPayload, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            [alertView show];
        }
    }
}

- (void)takeActionWithCountlyPayload:(NSDictionary *)countlyPayload
{
    [Countly.sharedInstance recordEvent:kCountlyReservedEventPushAction segmentation:@{@"i": countlyPayload[@"i"]}];

    [UIApplication.sharedApplication openURL:[NSURL URLWithString:countlyPayload[@"l"]]];
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    if (buttonIndex != alertView.cancelButtonIndex)
    {
        NSDictionary* countlyPayload = objc_getAssociatedObject(alertView, &kUIAlertViewAssociatedObjectKey);
        [self takeActionWithCountlyPayload:countlyPayload];
    }
}
#pragma mark ---

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken{}
- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error{}
- (void)application:(UIApplication *)application didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings{}
- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler
{
    completionHandler(UIBackgroundFetchResultNewData);
}
#endif
@end


#if TARGET_OS_IOS
@implementation UIResponder (CountlyPushNotifications)
- (void)Countly_application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    COUNTLY_LOG(@"App didRegisterForRemoteNotificationsWithDeviceToken: %@", deviceToken);
    const char *bytes = [deviceToken bytes];
    NSMutableString *token = NSMutableString.new;
    for (NSUInteger i = 0; i < deviceToken.length; i++)
        [token appendFormat:@"%02hhx", bytes[i]];

    CountlyPushNotifications.sharedInstance.token = token;

    [CountlyPushNotifications.sharedInstance sendToken];

    [self Countly_application:application didRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
}

- (void)Countly_application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
    COUNTLY_LOG(@"App didFailToRegisterForRemoteNotificationsWithError: %@", error);

    CountlyPushNotifications.sharedInstance.token = kCountlyTokenError;

    [CountlyPushNotifications.sharedInstance sendToken];

    [self Countly_application:application didFailToRegisterForRemoteNotificationsWithError:error];
}

- (void)Countly_application:(UIApplication *)application didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings
{
    COUNTLY_LOG(@"App didRegisterUserNotificationSettings: %@", notificationSettings);

    [CountlyPushNotifications.sharedInstance sendToken];

    [self Countly_application:application didRegisterUserNotificationSettings:notificationSettings];
}

- (void)Countly_application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler;
{
    COUNTLY_LOG(@"App didReceiveRemoteNotification:fetchCompletionHandler");

    [CountlyPushNotifications.sharedInstance handleNotification:userInfo];

    [self Countly_application:application didReceiveRemoteNotification:userInfo fetchCompletionHandler:completionHandler];
}
@end
#endif
