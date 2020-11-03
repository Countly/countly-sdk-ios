// CountlyPushNotifications.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

NSString* const kCountlyReservedEventPushAction = @"[CLY]_push_action";
NSString* const kCountlyTokenError = @"kCountlyTokenError";

//NOTE: Push Notification Test Modes
CLYPushTestMode const CLYPushTestModeDevelopment = @"CLYPushTestModeDevelopment";
CLYPushTestMode const CLYPushTestModeTestFlightOrAdHoc = @"CLYPushTestModeTestFlightOrAdHoc";

#if (TARGET_OS_IOS || TARGET_OS_OSX)
@interface CountlyPushNotifications () <UNUserNotificationCenterDelegate>
@property (nonatomic) NSString* token;
@property (nonatomic, copy) void (^permissionCompletion)(BOOL granted, NSError * error);
#else
@interface CountlyPushNotifications ()
#endif
@end

#if (TARGET_OS_IOS)
    #define CLYApplication UIApplication
#elif (TARGET_OS_OSX)
    #define CLYApplication NSApplication
#endif

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

@implementation CountlyPushNotifications

#ifndef COUNTLY_EXCLUDE_PUSHNOTIFICATIONS

+ (instancetype)sharedInstance
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return nil;

    static CountlyPushNotifications* s_sharedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    if (self = [super init])
    {

    }

    return self;
}

#pragma mark ---

#if (TARGET_OS_IOS || TARGET_OS_OSX)
- (void)startPushNotifications
{
    if (!self.isEnabledOnInitialConfig)
        return;

    if (!CountlyConsentManager.sharedInstance.consentForPushNotifications)
        return;

    if (@available(iOS 10.0, macOS 10.14, *))
        UNUserNotificationCenter.currentNotificationCenter.delegate = self;

    [self swizzlePushNotificationMethods];

#if (TARGET_OS_IOS)
    [UIApplication.sharedApplication registerForRemoteNotifications];
#elif (TARGET_OS_OSX)
    [NSApplication.sharedApplication registerForRemoteNotificationTypes:NSRemoteNotificationTypeBadge | NSRemoteNotificationTypeAlert | NSRemoteNotificationTypeSound];

    if (@available(macOS 10.14, *))
    {
        UNNotificationResponse* notificationResponse = self.launchNotification.userInfo[NSApplicationLaunchUserNotificationKey];
        if (notificationResponse)
            [self userNotificationCenter:UNUserNotificationCenter.currentNotificationCenter didReceiveNotificationResponse:notificationResponse withCompletionHandler:^{}];
    }
#endif
}

- (void)stopPushNotifications
{
    if (!self.isEnabledOnInitialConfig)
        return;

    if (@available(iOS 10.0, macOS 10.14, *))
    {
        if (UNUserNotificationCenter.currentNotificationCenter.delegate == self)
            UNUserNotificationCenter.currentNotificationCenter.delegate = nil;
    }

    [CLYApplication.sharedApplication unregisterForRemoteNotifications];
}

- (void)swizzlePushNotificationMethods
{
    static BOOL alreadySwizzled;
    if (alreadySwizzled)
        return;

    alreadySwizzled = YES;

    Class appDelegateClass = CLYApplication.sharedApplication.delegate.class;
    NSArray* selectors =
    @[
        @"application:didRegisterForRemoteNotificationsWithDeviceToken:",
        @"application:didFailToRegisterForRemoteNotificationsWithError:",
#if (TARGET_OS_IOS)
        @"application:didRegisterUserNotificationSettings:",
        @"application:didReceiveRemoteNotification:fetchCompletionHandler:",
#elif (TARGET_OS_OSX)
        @"application:didReceiveRemoteNotification:",
#endif
    ];

    for (NSString* selectorString in selectors)
    {
        SEL originalSelector = NSSelectorFromString(selectorString);
        Method originalMethod = class_getInstanceMethod(appDelegateClass, originalSelector);

        if (originalMethod == NULL)
        {
            Method method = class_getInstanceMethod(self.class, originalSelector);
            IMP imp = method_getImplementation(method);
            const char* methodTypeEncoding = method_getTypeEncoding(method);
            class_addMethod(appDelegateClass, originalSelector, imp, methodTypeEncoding);
            originalMethod = class_getInstanceMethod(appDelegateClass, originalSelector);
        }

        SEL countlySelector = NSSelectorFromString([@"Countly_" stringByAppendingString:selectorString]);
        Method countlyMethod = class_getInstanceMethod(appDelegateClass, countlySelector);
        method_exchangeImplementations(originalMethod, countlyMethod);
    }
}

- (void)askForNotificationPermissionWithOptions:(NSUInteger)options completionHandler:(void (^)(BOOL granted, NSError * error))completionHandler
{
    if (!CountlyConsentManager.sharedInstance.consentForPushNotifications)
        return;

    if (@available(iOS 10.0, macOS 10.14, *))
    {
        if (options == 0)
            options = UNAuthorizationOptionBadge | UNAuthorizationOptionSound | UNAuthorizationOptionAlert;

        [UNUserNotificationCenter.currentNotificationCenter requestAuthorizationWithOptions:options completionHandler:^(BOOL granted, NSError* error)
        {
            if (completionHandler)
                completionHandler(granted, error);

            [self sendToken];
        }];
    }
#if (TARGET_OS_IOS)
    else
    {
        self.permissionCompletion = completionHandler;

        if (options == 0)
            options = UIUserNotificationTypeBadge | UIUserNotificationTypeSound | UIUserNotificationTypeAlert;

        UIUserNotificationType userNotificationTypes = (UIUserNotificationType)options;
        UIUserNotificationSettings* settings = [UIUserNotificationSettings settingsForTypes:userNotificationTypes categories:nil];
        [UIApplication.sharedApplication registerUserNotificationSettings:settings];
    }
#endif
}

- (void)sendToken
{
    if (!CountlyConsentManager.sharedInstance.consentForPushNotifications)
        return;

    if (!self.token)
        return;

    if ([self.token isEqualToString:kCountlyTokenError])
    {
        [self clearToken];
        return;
    }

    if (self.sendPushTokenAlways)
    {
        [CountlyConnectionManager.sharedInstance sendPushToken:self.token];
        return;
    }

    BOOL hasNotificationPermissionBefore = [CountlyPersistency.sharedInstance retrieveNotificationPermission];

    if (@available(iOS 10.0, macOS 10.14, *))
    {
        [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings* settings)
        {
            BOOL hasProvisionalPermission = NO;
            if (@available(iOS 12.0, *))
            {
                hasProvisionalPermission = settings.authorizationStatus == UNAuthorizationStatusProvisional;
            }
        
            if (settings.authorizationStatus == UNAuthorizationStatusAuthorized || hasProvisionalPermission)
            {
                [CountlyConnectionManager.sharedInstance sendPushToken:self.token];
                [CountlyPersistency.sharedInstance storeNotificationPermission:YES];
            }
            else if (hasNotificationPermissionBefore)
            {
                [self clearToken];
                [CountlyPersistency.sharedInstance storeNotificationPermission:NO];
            }
        }];
    }
#if (TARGET_OS_IOS)
    else
    {
        if (UIApplication.sharedApplication.currentUserNotificationSettings.types != UIUserNotificationTypeNone)
        {
            [CountlyConnectionManager.sharedInstance sendPushToken:self.token];
            [CountlyPersistency.sharedInstance storeNotificationPermission:YES];
        }
        else if (hasNotificationPermissionBefore)
        {
            [self clearToken];
            [CountlyPersistency.sharedInstance storeNotificationPermission:NO];
        }
    }
#endif
}

- (void)clearToken
{
    [CountlyConnectionManager.sharedInstance sendPushToken:@""];
}

- (void)handleNotification:(NSDictionary *)notification
{
#if (TARGET_OS_IOS || TARGET_OS_OSX)
    if (!CountlyConsentManager.sharedInstance.consentForPushNotifications)
        return;

    COUNTLY_LOG(@"Handling remote notification %@", notification);

    NSDictionary* countlyPayload = notification[kCountlyPNKeyCountlyPayload];
    NSString* notificationID = countlyPayload[kCountlyPNKeyNotificationID];

    if (!notificationID)
    {
        COUNTLY_LOG(@"Countly payload not found in notification dictionary!");
        return;
    }

    COUNTLY_LOG(@"Countly Push Notification ID: %@", notificationID);
#endif

#if (TARGET_OS_OSX)
    //NOTE: For macOS targets, just record action event.
    [self recordActionEvent:notificationID buttonIndex:0];
#endif

#if (TARGET_OS_IOS)
    if (self.doNotShowAlertForNotifications)
    {
        COUNTLY_LOG(@"doNotShowAlertForNotifications flag is set!");
        return;
    }

    if (@available(iOS 10.0, *))
    {
        //NOTE: On iOS10+ when a silent notification (content-available: 1) with `alert` key arrives, do not show alert here, as it is shown in UN framework delegate method
        COUNTLY_LOG(@"A silent notification (content-available: 1) with `alert` key on iOS10+.");
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

    if (!message && !title)
    {
        COUNTLY_LOG(@"Title and Message are both not found in notification dictionary!");
        return;
    }


    __block UIAlertController* alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];


    CLYButton* defaultButton = nil;
    NSString* defaultURL = countlyPayload[kCountlyPNKeyDefaultURL];
    if (defaultURL)
    {
        defaultButton = [CLYButton buttonWithType:UIButtonTypeCustom];
        defaultButton.frame = alertController.view.bounds;
        defaultButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        defaultButton.onClick = ^(id sender)
        {
            [self recordActionEvent:notificationID buttonIndex:0];

            [self openURL:defaultURL];

            [alertController dismissViewControllerAnimated:YES completion:^
            {
                alertController = nil;
            }];
        };
        [alertController.view addSubview:defaultButton];
    }


    CLYButton* dismissButton = [CLYButton dismissAlertButton];
    dismissButton.onClick = ^(id sender)
    {
        [self recordActionEvent:notificationID buttonIndex:0];

        [alertController dismissViewControllerAnimated:YES completion:^
        {
            alertController = nil;
        }];
    };
    [alertController.view addSubview:dismissButton];
    [dismissButton positionToTopRight];

    NSArray* buttons = countlyPayload[kCountlyPNKeyButtons];
    [buttons enumerateObjectsUsingBlock:^(NSDictionary* button, NSUInteger idx, BOOL * stop)
    {
        //NOTE: Add space to force buttons to be laid out vertically
        NSString* actionTitle = [button[kCountlyPNKeyActionButtonTitle] stringByAppendingString:@"                       "];
        NSString* URL = button[kCountlyPNKeyActionButtonURL];

        UIAlertAction* visit = [UIAlertAction actionWithTitle:actionTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * action)
        {
            [self recordActionEvent:notificationID buttonIndex:idx + 1];

            [self openURL:URL];

            alertController = nil;
        }];

        [alertController addAction:visit];
    }];

    [CountlyCommon.sharedInstance tryPresentingViewController:alertController];

    const CGFloat kCountlyActionButtonHeight = 44.0;
    CGRect tempFrame = defaultButton.frame;
    tempFrame.size.height -= buttons.count * kCountlyActionButtonHeight;
    defaultButton.frame = tempFrame;
#endif
}

- (void)openURL:(NSString *)URLString
{
    if (!URLString)
        return;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^
    {
#if (TARGET_OS_IOS)
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:URLString]];
#elif (TARGET_OS_OSX)
        [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:URLString]];
#endif
    });
}

- (void)recordActionForNotification:(NSDictionary *)userInfo clickedButtonIndex:(NSInteger)buttonIndex
{
    if (!CountlyConsentManager.sharedInstance.consentForPushNotifications)
        return;

    NSDictionary* countlyPayload = userInfo[kCountlyPNKeyCountlyPayload];
    NSString* notificationID = countlyPayload[kCountlyPNKeyNotificationID];

    [self recordActionEvent:notificationID buttonIndex:buttonIndex];
}

- (void)recordActionEvent:(NSString *)notificationID buttonIndex:(NSInteger)buttonIndex
{
    if (!notificationID)
        return;

    NSDictionary* segmentation =
    @{
        kCountlyPNKeyNotificationID: notificationID,
        kCountlyPNKeyActionButtonIndex: @(buttonIndex)
    };

    [Countly.sharedInstance recordReservedEvent:kCountlyReservedEventPushAction segmentation:segmentation];
}

#pragma mark ---

- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler API_AVAILABLE(ios(10.0), macos(10.14))
{
    COUNTLY_LOG(@"userNotificationCenter:willPresentNotification:withCompletionHandler:");
    COUNTLY_LOG(@"%@", notification.request.content.userInfo.description);

    if (!self.doNotShowAlertForNotifications)
    {
        NSDictionary* countlyPayload = notification.request.content.userInfo[kCountlyPNKeyCountlyPayload];
        NSString* notificationID = countlyPayload[kCountlyPNKeyNotificationID];

        if (notificationID)
            completionHandler(UNNotificationPresentationOptionAlert);
    }

    id<UNUserNotificationCenterDelegate> appDelegate = (id<UNUserNotificationCenterDelegate>)CLYApplication.sharedApplication.delegate;

    if ([appDelegate respondsToSelector:@selector(userNotificationCenter:willPresentNotification:withCompletionHandler:)])
        [appDelegate userNotificationCenter:center willPresentNotification:notification withCompletionHandler:completionHandler];
    else
        completionHandler(UNNotificationPresentationOptionNone);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)(void))completionHandler API_AVAILABLE(ios(10.0), macos(10.14))
{
    COUNTLY_LOG(@"userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:");
    COUNTLY_LOG(@"%@", response.notification.request.content.userInfo.description);

    if (CountlyConsentManager.sharedInstance.consentForPushNotifications)
    {
        NSDictionary* countlyPayload = response.notification.request.content.userInfo[kCountlyPNKeyCountlyPayload];
        NSString* notificationID = countlyPayload[kCountlyPNKeyNotificationID];

        if (notificationID)
        {
            NSInteger buttonIndex = 0;
            NSString* URL = nil;

            COUNTLY_LOG(@"Action Identifier: %@", response.actionIdentifier);

            if ([response.actionIdentifier isEqualToString:UNNotificationDefaultActionIdentifier])
            {
                URL = countlyPayload[kCountlyPNKeyDefaultURL];
            }
            else if ([response.actionIdentifier hasPrefix:kCountlyActionIdentifier])
            {
                buttonIndex = [[response.actionIdentifier stringByReplacingOccurrencesOfString:kCountlyActionIdentifier withString:@""] integerValue];
                URL = countlyPayload[kCountlyPNKeyButtons][buttonIndex - 1][kCountlyPNKeyActionButtonURL];
            }

            [self recordActionEvent:notificationID buttonIndex:buttonIndex];

            [self openURL:URL];
        }
    }

    id<UNUserNotificationCenterDelegate> appDelegate = (id<UNUserNotificationCenterDelegate>)CLYApplication.sharedApplication.delegate;

    if ([appDelegate respondsToSelector:@selector(userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:)])
        [appDelegate userNotificationCenter:center didReceiveNotificationResponse:response withCompletionHandler:completionHandler];
    else
        completionHandler();
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center openSettingsForNotification:(UNNotification *)notification API_AVAILABLE(ios(12.0), macos(10.14))
{
    if (@available(iOS 12.0, macOS 10.14, *))
    {
        id<UNUserNotificationCenterDelegate> appDelegate = (id<UNUserNotificationCenterDelegate>)CLYApplication.sharedApplication.delegate;

        if ([appDelegate respondsToSelector:@selector(userNotificationCenter:openSettingsForNotification:)])
            [appDelegate userNotificationCenter:center openSettingsForNotification:notification];
    }
}

#pragma mark ---

- (void)application:(CLYApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken{}
- (void)application:(CLYApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error{}
#if (TARGET_OS_IOS)
- (void)application:(UIApplication *)application didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings{}
- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler
{
    completionHandler(UIBackgroundFetchResultNewData);
}
#elif (TARGET_OS_OSX)
- (void)application:(NSApplication *)application didReceiveRemoteNotification:(NSDictionary<NSString *,id> *)userInfo{}
#endif
#endif
@end


@implementation NSObject (CountlyPushNotifications)
#if (TARGET_OS_IOS || TARGET_OS_OSX)
- (void)Countly_application:(CLYApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    COUNTLY_LOG(@"App didRegisterForRemoteNotificationsWithDeviceToken: %@", deviceToken);

    const char* bytes = [deviceToken bytes];
    NSMutableString *token = NSMutableString.new;
    for (NSUInteger i = 0; i < deviceToken.length; i++)
        [token appendFormat:@"%02hhx", bytes[i]];

    CountlyPushNotifications.sharedInstance.token = token;

    [CountlyPushNotifications.sharedInstance sendToken];

    [self Countly_application:application didRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
}

- (void)Countly_application:(CLYApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
    COUNTLY_LOG(@"App didFailToRegisterForRemoteNotificationsWithError: %@", error);

    CountlyPushNotifications.sharedInstance.token = kCountlyTokenError;

    [CountlyPushNotifications.sharedInstance sendToken];

    [self Countly_application:application didFailToRegisterForRemoteNotificationsWithError:error];
}
#endif

#if (TARGET_OS_IOS)
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

#elif (TARGET_OS_OSX)
- (void)Countly_application:(NSApplication *)application didReceiveRemoteNotification:(NSDictionary<NSString *,id> *)userInfo
{
    COUNTLY_LOG(@"App didReceiveRemoteNotification:");

    [CountlyPushNotifications.sharedInstance handleNotification:userInfo];

    [self Countly_application:application didReceiveRemoteNotification:userInfo];
}
#endif
#endif
@end
#pragma GCC diagnostic pop
