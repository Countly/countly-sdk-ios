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
{
    UIAlertController* alertController;
}
@property (nonatomic, strong) UIWindow* alertWindow;
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

    if (NSFoundationVersionNumber > NSFoundationVersionNumber_iOS_9_x_Max)
    {
        [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings* settings)
        {
            if (settings.authorizationStatus == UNAuthorizationStatusAuthorized)
                [CountlyConnectionManager.sharedInstance sendPushToken:self.token];
        }];
    }
    else
    {
        if (UIApplication.sharedApplication.currentUserNotificationSettings.types != UIUserNotificationTypeNone)
            [CountlyConnectionManager.sharedInstance sendPushToken:self.token];
    }
}

- (void)handleNotification:(NSDictionary *)notification
{
    COUNTLY_LOG(@"Handling remote notification %@", notification);

    NSDictionary* countlyPayload = notification[@"c"];
    NSString* notificationID = countlyPayload[@"i"];

    if (!notificationID)
        return;

    COUNTLY_LOG(@"Countly Push Notification ID: %@", notificationID);

    [Countly.sharedInstance recordEvent:kCountlyReservedEventPushOpen segmentation:@{@"i":notificationID}];

    NSArray* buttons = countlyPayload[@"b"];

    if (!buttons && UIApplication.sharedApplication.applicationState != UIApplicationStateActive)
    {
        NSString* URL = countlyPayload[@"l"];

        if (URL)
        {
            COUNTLY_LOG(@"Redirecting to default URL: %@", notificationID);

            [Countly.sharedInstance recordEvent:kCountlyReservedEventPushAction segmentation:@{@"i":notificationID, @"b":@(0)}];

            dispatch_async(dispatch_get_main_queue(), ^{ [UIApplication.sharedApplication openURL:[NSURL URLWithString:URL]]; });

            return;
        }
    }


    if (self.doNotShowAlertForNotifications)
        return;

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
        return;

    alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];

    const float kCountlyDismissButtonSize = 30.0;
    const float kCountlyDismissButtonMargin = 10.0;
    UIButton* dismissButton = [UIButton buttonWithType:UIButtonTypeCustom];
    dismissButton.frame = (CGRect){alertController.view.bounds.size.width - kCountlyDismissButtonSize - kCountlyDismissButtonMargin, kCountlyDismissButtonMargin, kCountlyDismissButtonSize, kCountlyDismissButtonSize};
    [dismissButton setTitle:@"✕" forState:UIControlStateNormal];
    [dismissButton setTitleColor:UIColor.grayColor forState:UIControlStateNormal];
    dismissButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    [dismissButton addTarget:self action:@selector(onClick_dismiss:) forControlEvents:UIControlEventTouchUpInside ];
    [alertController.view addSubview:dismissButton];

    [buttons enumerateObjectsUsingBlock:^(NSDictionary* button, NSUInteger idx, BOOL * stop)
    {
        //NOTE: space is added to force buttons to be laid out vertically
        NSString* title = [button[@"t"] stringByAppendingString:@"                       "];
        NSString* URL = button[@"l"];

        UIAlertAction* visit = [UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction * action)
        {
            [Countly.sharedInstance recordEvent:kCountlyReservedEventPushAction segmentation:@{@"i": notificationID, @"b": @(idx+1)}];

            dispatch_async(dispatch_get_main_queue(), ^{ [UIApplication.sharedApplication openURL:[NSURL URLWithString:URL]]; });

            self.alertWindow.hidden = YES;
            self.alertWindow = nil;
        }];

        [alertController addAction:visit];
    }];

    self.alertWindow = [UIWindow.alloc initWithFrame:UIScreen.mainScreen.bounds];
    self.alertWindow.rootViewController = CLYInternalViewController.new;
    self.alertWindow.windowLevel = UIWindowLevelAlert;
    [self.alertWindow makeKeyAndVisible];
    [self.alertWindow.rootViewController presentViewController:alertController animated:YES completion:nil];
}

- (void)onClick_dismiss:(id)sender
{
    [alertController dismissViewControllerAnimated:YES completion:^
    {
        self.alertWindow.hidden = YES;
        self.alertWindow = nil;
    }];
}

#pragma mark ---

- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler
{
    COUNTLY_LOG(@"userNotificationCenter:willPresentNotification:withCompletionHandler:");

    NSDictionary* countlyPayload = notification.request.content.userInfo[@"c"];
    NSString* notificationID = countlyPayload[@"i"];

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

    NSDictionary* countlyPayload = response.notification.request.content.userInfo[@"c"];
    NSString* notificationID = countlyPayload[@"i"];

    if (notificationID)
    {
        [Countly.sharedInstance recordEvent:kCountlyReservedEventPushOpen segmentation:@{@"i":notificationID}];

        NSInteger buttonIndex = -1;
        NSString* URL = nil;

        COUNTLY_LOG(@"Action Identifier: %@", response.actionIdentifier);

        if ([response.actionIdentifier isEqualToString:UNNotificationDefaultActionIdentifier])
        {
            if (countlyPayload[@"l"])
            {
                buttonIndex = 0;
                URL = countlyPayload[@"l"];
            }
        }
        else if ([response.actionIdentifier hasPrefix:kCountlyActionIdentifier])
        {
            buttonIndex = [[response.actionIdentifier stringByReplacingOccurrencesOfString:kCountlyActionIdentifier withString:@""] integerValue];
            URL = countlyPayload[@"b"][buttonIndex - 1][@"l"];
        }

        if (buttonIndex >= 0)
        {
            [Countly.sharedInstance recordEvent:kCountlyReservedEventPushAction segmentation:@{@"i":notificationID, @"b":@(buttonIndex)}];
        }

        if (URL)
        {
            dispatch_async(dispatch_get_main_queue(), ^{ [UIApplication.sharedApplication openURL:[NSURL URLWithString:URL]]; });
        }
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
