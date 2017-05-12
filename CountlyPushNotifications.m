// CountlyPushNotifications.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

NSString* const kCountlyReservedEventPushOpen = @"[CLY]_push_open";
NSString* const kCountlyReservedEventPushAction = @"[CLY]_push_action";
NSString* const kCountlyTokenError = @"kCountlyTokenError";

@interface CountlyPushNotifications ()
#if TARGET_OS_IOS
@property (nonatomic, strong) NSString* token;
@property (nonatomic, copy) void (^permissionCompletion)(BOOL granted, NSError * error);
#endif
@end

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

@implementation CountlyPushNotifications

+ (instancetype)sharedInstance
{
    static CountlyPushNotifications* s_sharedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

#pragma mark ---

#if TARGET_OS_IOS

- (void)startPushNotifications
{
    UNUserNotificationCenter.currentNotificationCenter.delegate = self;

    Class appDelegateClass = UIApplication.sharedApplication.delegate.class;
    NSArray* selectors = @[@"application:didRegisterForRemoteNotificationsWithDeviceToken:",
                           @"application:didFailToRegisterForRemoteNotificationsWithError:",
                           @"application:didRegisterUserNotificationSettings:",
                           @"application:didReceiveRemoteNotification:fetchCompletionHandler:"];

    for (NSString* selectorString in selectors)
    {
        SEL originalSelector = NSSelectorFromString(selectorString);
        Method originalMethod = class_getInstanceMethod(appDelegateClass, originalSelector);

        if (originalMethod == NULL)
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

    [UIApplication.sharedApplication registerForRemoteNotifications];
}

- (void)askForNotificationPermissionWithOptions:(UNAuthorizationOptions)options completionHandler:(void (^)(BOOL granted, NSError * error))completionHandler
{
    if (NSFoundationVersionNumber > NSFoundationVersionNumber_iOS_9_x_Max)
    {
        [UNUserNotificationCenter.currentNotificationCenter requestAuthorizationWithOptions:options completionHandler:^(BOOL granted, NSError* error)
        {
            if (completionHandler)
                completionHandler(granted, error);
        }];
    }
    else
    {
        self.permissionCompletion = completionHandler;
        UIUserNotificationType userNotificationTypes = (UIUserNotificationType)options;
        UIUserNotificationSettings* settings = [UIUserNotificationSettings settingsForTypes:userNotificationTypes categories:nil];
        [UIApplication.sharedApplication registerUserNotificationSettings:settings];
    }
}

- (void)sendToken
{
    if (!self.token)
        return;

    if ([self.token isEqualToString:kCountlyTokenError])
    {
        [CountlyConnectionManager.sharedInstance sendPushToken:@""];
        return;
    }

    if (self.sendPushTokenAlways)
    {
        [CountlyConnectionManager.sharedInstance sendPushToken:self.token];
        return;
    }

    BOOL hasNotificationPermissionBefore = [CountlyPersistency.sharedInstance retrieveNotificationPermission];

    if (NSFoundationVersionNumber > NSFoundationVersionNumber_iOS_9_x_Max)
    {
        [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings* settings)
        {
            if (settings.authorizationStatus == UNAuthorizationStatusAuthorized)
            {
                [CountlyConnectionManager.sharedInstance sendPushToken:self.token];
                [CountlyPersistency.sharedInstance storeNotificationPermission:YES];
            }
            else if (hasNotificationPermissionBefore)
            {
                [CountlyConnectionManager.sharedInstance sendPushToken:@""];
                [CountlyPersistency.sharedInstance storeNotificationPermission:NO];
            }
        }];
    }
    else
    {
        if (UIApplication.sharedApplication.currentUserNotificationSettings.types != UIUserNotificationTypeNone)
        {
            [CountlyConnectionManager.sharedInstance sendPushToken:self.token];
            [CountlyPersistency.sharedInstance storeNotificationPermission:YES];
        }
        else if (hasNotificationPermissionBefore)
        {
            [CountlyConnectionManager.sharedInstance sendPushToken:@""];
            [CountlyPersistency.sharedInstance storeNotificationPermission:NO];
        }
    }
}

- (void)handleNotification:(NSDictionary *)notification
{
    COUNTLY_LOG(@"Handling remote notification %@", notification);

    NSDictionary* countlyPayload = notification[kCountlyPNKeyCountlyPayload];
    NSString* notificationID = countlyPayload[kCountlyPNKeyNotificationID];

    if (!notificationID)
    {
        COUNTLY_LOG(@"Countly payload not found in notification dictionary!");
        return;
    }

    COUNTLY_LOG(@"Countly Push Notification ID: %@", notificationID);

    [Countly.sharedInstance recordEvent:kCountlyReservedEventPushOpen segmentation:@{kCountlyPNKeyNotificationID : notificationID}];

    if (self.doNotShowAlertForNotifications)
    {
        COUNTLY_LOG(@"doNotShowAlertForNotifications flag is set!");
        return;
    }


    id alert = notification[@"aps"][@"alert"];
    NSString* message = nil;
    NSString* title = nil;

    if ([alert isKindOfClass:NSDictionary.class])
    {
        message = alert[@"body"];
        title = alert[@"title"];
    }
    else
    {
        message = (NSString*)alert;
        title = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    }

    if (!message)
    {
        COUNTLY_LOG(@"Message not found in notification dictionary!");
        return;
    }


    __block UIWindow* alertWindow = [UIWindow.alloc initWithFrame:UIScreen.mainScreen.bounds];
    alertWindow.rootViewController = CLYInternalViewController.new;
    alertWindow.windowLevel = UIWindowLevelAlert;

    UIAlertController* alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];


    CLYButton* defaultButton = nil;
    NSString* defaultURL = countlyPayload[kCountlyPNKeyDefaultURL];
    if (defaultURL)
    {
        defaultButton = [CLYButton buttonWithType:UIButtonTypeCustom];
        defaultButton.frame = alertController.view.bounds;
        defaultButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        defaultButton.onClick = ^(id sender)
        {
            [Countly.sharedInstance recordEvent:kCountlyReservedEventPushAction segmentation:@{kCountlyPNKeyNotificationID : notificationID, kCountlyPNKeyActionButtonIndex : @(0)}];

            [self openURL:defaultURL];

            [alertController dismissViewControllerAnimated:YES completion:^
            {
                alertWindow.hidden = YES;
                alertWindow = nil;
            }];
        };
        [alertController.view addSubview:defaultButton];
    }


    CLYButton* dismissButton = [CLYButton dismissAlertButton];
    dismissButton.onClick = ^(id sender)
    {
        [alertController dismissViewControllerAnimated:YES completion:^
        {
            alertWindow.hidden = YES;
            alertWindow = nil;
        }];
    };
    [alertController.view addSubview:dismissButton];


    NSArray* buttons = countlyPayload[kCountlyPNKeyButtons];
    [buttons enumerateObjectsUsingBlock:^(NSDictionary* button, NSUInteger idx, BOOL * stop)
    {
        //NOTE: space is added to force buttons to be laid out vertically
        NSString* title = [button[kCountlyPNKeyActionButtonTitle] stringByAppendingString:@"                       "];
        NSString* URL = button[kCountlyPNKeyActionButtonURL];

        UIAlertAction* visit = [UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction * action)
        {
            [Countly.sharedInstance recordEvent:kCountlyReservedEventPushAction segmentation:@{kCountlyPNKeyNotificationID : notificationID, kCountlyPNKeyActionButtonIndex : @(idx+1)}];

            [self openURL:URL];

            alertWindow.hidden = YES;
            alertWindow = nil;
        }];

        [alertController addAction:visit];
    }];

    [alertWindow makeKeyAndVisible];
    [alertWindow.rootViewController presentViewController:alertController animated:YES completion:nil];

    const float kCountlyActionButtonHeight = 44.0;
    CGRect tempFrame = defaultButton.frame;
    tempFrame.size.height -= buttons.count * kCountlyActionButtonHeight;
    defaultButton.frame = tempFrame;
}

- (void)openURL:(NSString *)URLString
{
    if(!URLString)
        return;

    dispatch_async(dispatch_get_main_queue(), ^
    {
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:URLString]];
    });
}

#pragma mark ---

- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler
{
    COUNTLY_LOG(@"userNotificationCenter:willPresentNotification:withCompletionHandler:");
    COUNTLY_LOG(@"%@", notification.request.content.userInfo.description);

    NSDictionary* countlyPayload = notification.request.content.userInfo[kCountlyPNKeyCountlyPayload];
    NSString* notificationID = countlyPayload[kCountlyPNKeyNotificationID];

    if (notificationID)
        completionHandler(UNNotificationPresentationOptionAlert);

    id<UNUserNotificationCenterDelegate> appDelegate = (id<UNUserNotificationCenterDelegate>)UIApplication.sharedApplication.delegate;

    if ([appDelegate respondsToSelector:@selector(userNotificationCenter:willPresentNotification:withCompletionHandler:)])
        [appDelegate userNotificationCenter:center willPresentNotification:notification withCompletionHandler:completionHandler];
    else
        completionHandler(UNNotificationPresentationOptionNone);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)())completionHandler
{
    COUNTLY_LOG(@"userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:");
    COUNTLY_LOG(@"%@", response.notification.request.content.userInfo.description);

    NSDictionary* countlyPayload = response.notification.request.content.userInfo[kCountlyPNKeyCountlyPayload];
    NSString* notificationID = countlyPayload[kCountlyPNKeyNotificationID];

    if (notificationID)
    {
        [Countly.sharedInstance recordEvent:kCountlyReservedEventPushOpen segmentation:@{kCountlyPNKeyNotificationID : notificationID}];

        NSInteger buttonIndex = -1;
        NSString* URL = nil;

        COUNTLY_LOG(@"Action Identifier: %@", response.actionIdentifier);

        if ([response.actionIdentifier isEqualToString:UNNotificationDefaultActionIdentifier])
        {
            if (countlyPayload[kCountlyPNKeyDefaultURL])
            {
                buttonIndex = 0;
                URL = countlyPayload[kCountlyPNKeyDefaultURL];
            }
        }
        else if ([response.actionIdentifier hasPrefix:kCountlyActionIdentifier])
        {
            buttonIndex = [[response.actionIdentifier stringByReplacingOccurrencesOfString:kCountlyActionIdentifier withString:@""] integerValue];
            URL = countlyPayload[kCountlyPNKeyButtons][buttonIndex - 1][kCountlyPNKeyActionButtonURL];
        }

        if (buttonIndex >= 0)
        {
            [Countly.sharedInstance recordEvent:kCountlyReservedEventPushAction segmentation:@{kCountlyPNKeyNotificationID : notificationID, kCountlyPNKeyActionButtonIndex : @(buttonIndex)}];
        }

        [self openURL:URL];
    }

    id<UNUserNotificationCenterDelegate> appDelegate = (id<UNUserNotificationCenterDelegate>)UIApplication.sharedApplication.delegate;

    if ([appDelegate respondsToSelector:@selector(userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:)])
        [appDelegate userNotificationCenter:center didReceiveNotificationResponse:response withCompletionHandler:completionHandler];
    else
        completionHandler();
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

    BOOL granted = UIApplication.sharedApplication.currentUserNotificationSettings.types != UIUserNotificationTypeNone;

    if (CountlyPushNotifications.sharedInstance.permissionCompletion)
        CountlyPushNotifications.sharedInstance.permissionCompletion(granted, nil);

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
#pragma GCC diagnostic pop
