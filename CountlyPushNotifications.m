// CountlyPushNotifications.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

NSString* const kCountlyReservedEventPushAction = @"[CLY]_push_action";
NSString* const kCountlyTokenError = @"kCountlyTokenError";

NSString* const kCountlyPNKeyPlatform = @"p";
NSString* const kCountlyPNKeyiOS = @"i";
NSString* const kCountlyPNKeymacOS = @"m";

//NOTE: Push Notification Test Modes
CLYPushTestMode const CLYPushTestModeDevelopment = @"CLYPushTestModeDevelopment";
CLYPushTestMode const CLYPushTestModeTestFlightOrAdHoc = @"CLYPushTestModeTestFlightOrAdHoc";

#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_OSX)
@interface CountlyPushNotifications () <UNUserNotificationCenterDelegate>
@property (nonatomic) NSString* token;
#else
@interface CountlyPushNotifications ()
#endif
@end

#if (TARGET_OS_IOS || TARGET_OS_VISION)
    #define CLYApplication UIApplication
#elif (TARGET_OS_OSX)
    #define CLYApplication NSApplication
#endif

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

#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_OSX)
- (void)startPushNotifications
{
    CLY_LOG_I(@"%s push notifications registration requested, enabledOnInitialConfig: [%@]", __FUNCTION__, self.isEnabledOnInitialConfig ? @"YES" : @"NO");

    if (!self.isEnabledOnInitialConfig)
        return;

    if (!CountlyConsentManager.sharedInstance.consentForPushNotifications)
    {
        CLY_LOG_V(@"%s no push consent given, remote notification registration is skipped", __FUNCTION__);
        return;
    }

    UNUserNotificationCenter.currentNotificationCenter.delegate = self;

    [self swizzlePushNotificationMethods];

    [CLYApplication.sharedApplication registerForRemoteNotifications];

#if (TARGET_OS_OSX)
    UNNotificationResponse* notificationResponse = self.launchNotification.userInfo[NSApplicationLaunchUserNotificationKey];
    if (notificationResponse)
        [self userNotificationCenter:UNUserNotificationCenter.currentNotificationCenter didReceiveNotificationResponse:notificationResponse withCompletionHandler:^{}];
#endif
}

- (void)stopPushNotifications
{
    CLY_LOG_I(@"%s push notifications unregistration requested, enabledOnInitialConfig: [%@]", __FUNCTION__, self.isEnabledOnInitialConfig ? @"YES" : @"NO");

    if (!self.isEnabledOnInitialConfig)
        return;

    if (UNUserNotificationCenter.currentNotificationCenter.delegate == self)
        UNUserNotificationCenter.currentNotificationCenter.delegate = nil;

    [CLYApplication.sharedApplication unregisterForRemoteNotifications];
}

- (void)swizzlePushNotificationMethods
{
    static BOOL alreadySwizzled;
    if (alreadySwizzled)
    {
        CLY_LOG_D(@"%s app delegate methods are already swizzled, skipping", __FUNCTION__);
        return;
    }

    alreadySwizzled = YES;

    Class appDelegateClass = CLYApplication.sharedApplication.delegate.class;
    NSArray* selectors =
    @[
        @"application:didRegisterForRemoteNotificationsWithDeviceToken:",
        @"application:didFailToRegisterForRemoteNotificationsWithError:",
    ];

    for (NSString* selectorString in selectors)
    {
        SEL originalSelector = NSSelectorFromString(selectorString);
        Method originalMethod = class_getInstanceMethod(appDelegateClass, originalSelector);
        BOOL wasImplementedByHost = (originalMethod != NULL);

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

        CLY_LOG_D(@"%s app delegate method swizzled, selector: [%@], wasImplementedByHost: [%@]", __FUNCTION__, selectorString, wasImplementedByHost ? @"YES" : @"NO");
    }
}

- (void)askForNotificationPermissionWithOptions:(NSUInteger)options completionHandler:(void (^)(BOOL granted, NSError * error))completionHandler
{
    CLY_LOG_I(@"%s notification permission requested, options: [%lu], completionHandlerProvided: [%@]", __FUNCTION__, (unsigned long)options, (completionHandler != nil) ? @"YES" : @"NO");

    if (!CountlyConsentManager.sharedInstance.consentForPushNotifications)
    {
        CLY_LOG_V(@"%s no push consent given, notification permission is not requested", __FUNCTION__);
        return;
    }

    if (options == 0)
        options = UNAuthorizationOptionBadge | UNAuthorizationOptionSound | UNAuthorizationOptionAlert;

    [UNUserNotificationCenter.currentNotificationCenter requestAuthorizationWithOptions:options completionHandler:^(BOOL granted, NSError* error)
    {
        if (error)
            CLY_LOG_E(@"%s notification permission request returned an error, granted: [%@], error: [%@]", __FUNCTION__, granted ? @"YES" : @"NO", error.localizedDescription);
        else
            CLY_LOG_I(@"%s notification permission result received, granted: [%@]", __FUNCTION__, granted ? @"YES" : @"NO");

        if (completionHandler)
            completionHandler(granted, error);

        [self sendToken];
    }];
}

- (void)sendToken
{
    if (!CountlyConsentManager.sharedInstance.consentForPushNotifications)
    {
        CLY_LOG_V(@"%s no push consent given, push token is not sent", __FUNCTION__);
        return;
    }

    if (!self.token)
    {
        CLY_LOG_D(@"%s push token is not sent, no token has been received yet", __FUNCTION__);
        return;
    }

    if ([self.token isEqualToString:kCountlyTokenError])
    {
        CLY_LOG_D(@"%s push token is in error state, an empty token will be sent to the server instead", __FUNCTION__);
        [self clearToken];
        return;
    }

    if (self.sendPushTokenAlways)
    {
        CLY_LOG_I(@"%s push token is being sent without checking the permission state, tokenLength: [%lu]", __FUNCTION__, (unsigned long)self.token.length);
        [CountlyConnectionManager.sharedInstance sendPushToken:self.token];
        return;
    }

    BOOL hasNotificationPermissionBefore = [CountlyPersistency.sharedInstance retrieveNotificationPermission];

    [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings* settings)
    {
        BOOL hasProvisionalPermission = NO;
        if (@available(iOS 12.0, *))
        {
            hasProvisionalPermission = settings.authorizationStatus == UNAuthorizationStatusProvisional;
        }

        if (settings.authorizationStatus == UNAuthorizationStatusAuthorized || hasProvisionalPermission)
        {
            CLY_LOG_I(@"%s notification permission is granted, push token is being sent, tokenLength: [%lu], provisional: [%@]", __FUNCTION__, (unsigned long)self.token.length, hasProvisionalPermission ? @"YES" : @"NO");
            [CountlyConnectionManager.sharedInstance sendPushToken:self.token];
            [CountlyPersistency.sharedInstance storeNotificationPermission:YES];
        }
        else if (hasNotificationPermissionBefore)
        {
            CLY_LOG_I(@"%s notification permission has been revoked, the stored push token is being cleared, authorizationStatus: [%ld]", __FUNCTION__, (long)settings.authorizationStatus);
            [self clearToken];
            [CountlyPersistency.sharedInstance storeNotificationPermission:NO];
        }
        else
        {
            CLY_LOG_D(@"%s notification permission is not granted and was not granted before, push token is not sent, authorizationStatus: [%ld]", __FUNCTION__, (long)settings.authorizationStatus);
        }
    }];
}

- (void)clearToken
{
    CLY_LOG_D(@"%s clearing the push token on the server by sending an empty token", __FUNCTION__);

    [CountlyConnectionManager.sharedInstance sendPushToken:@""];
}

- (void)openURL:(NSString *)URLString
{
    if (!URLString)
    {
        CLY_LOG_V(@"%s no URL is attached to the notification action, nothing will be opened", __FUNCTION__);
        return;
    }

    CLY_LOG_D(@"%s opening the URL attached to the notification action, URLLength: [%lu]", __FUNCTION__, (unsigned long)URLString.length);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^
    {
#if (TARGET_OS_IOS || TARGET_OS_VISION)
        [UIApplication.sharedApplication openURL:[NSURL URLWithString:URLString] options:@{} completionHandler:nil];
#elif (TARGET_OS_OSX)
        [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:URLString]];
#endif
    });
}

- (void)recordActionForNotification:(NSDictionary *)userInfo clickedButtonIndex:(NSInteger)buttonIndex
{
    CLY_LOG_I(@"%s notification action recording requested, buttonIndex: [%ld]", __FUNCTION__, (long)buttonIndex);

    if (!CountlyConsentManager.sharedInstance.consentForPushNotifications)
    {
        CLY_LOG_V(@"%s no push consent given, notification action is not recorded", __FUNCTION__);
        return;
    }

    NSDictionary* countlyPayload = userInfo[kCountlyPNKeyCountlyPayload];
    NSString* notificationID = countlyPayload[kCountlyPNKeyNotificationID];

    [self recordActionEvent:notificationID buttonIndex:buttonIndex];
}

- (void)recordActionEvent:(NSString *)notificationID buttonIndex:(NSInteger)buttonIndex
{
    if (!notificationID)
    {
        CLY_LOG_W(@"%s notification action event is dropped, the notification has no Countly notification ID", __FUNCTION__);
        return;
    }

    CLY_LOG_D(@"%s notification action taken, notificationID: [%@], buttonIndex: [%ld]", __FUNCTION__, notificationID, (long)buttonIndex);

    NSString* platform = @"unknown";
#if (TARGET_OS_IOS || TARGET_OS_VISION)
    platform = kCountlyPNKeyiOS;
#elif (TARGET_OS_OSX)
    platform = kCountlyPNKeymacOS;
#endif

    NSDictionary* segmentation =
    @{
        kCountlyPNKeyNotificationID: notificationID,
        kCountlyPNKeyActionButtonIndex: @(buttonIndex),
        kCountlyPNKeyPlatform: platform,
    };

    [Countly.sharedInstance recordReservedEvent:kCountlyReservedEventPushAction segmentation:segmentation];
}

#pragma mark ---

- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler API_AVAILABLE(ios(10.0), macos(10.14))
{
    CLY_LOG_D(@"%s notification received while the app is in the foreground, doNotShowAlertForNotifications: [%@]", __FUNCTION__, self.doNotShowAlertForNotifications ? @"YES" : @"NO");
    CLY_LOG_D(@"%s foreground notification payload detail, userInfo: [%@]", __FUNCTION__, notification.request.content.userInfo);

    if (!self.doNotShowAlertForNotifications)
    {
        NSDictionary* countlyPayload = notification.request.content.userInfo[kCountlyPNKeyCountlyPayload];
        NSString* notificationID = countlyPayload[kCountlyPNKeyNotificationID];

        if (notificationID)
        {
            UNNotificationPresentationOptions presentationOption = UNNotificationPresentationOptionNone;
            if (@available(iOS 14.0, tvOS 14.0, macOS 11.0, watchOS 7.0, *))
            {
                presentationOption = UNNotificationPresentationOptionList | UNNotificationPresentationOptionBanner;
            }
            else
            {
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
                presentationOption = UNNotificationPresentationOptionAlert;
#pragma GCC diagnostic pop
            }
            completionHandler(presentationOption);
        }
    }

    id<UNUserNotificationCenterDelegate> appDelegate = (id<UNUserNotificationCenterDelegate>)CLYApplication.sharedApplication.delegate;

    if ([appDelegate respondsToSelector:@selector(userNotificationCenter:willPresentNotification:withCompletionHandler:)])
        [appDelegate userNotificationCenter:center willPresentNotification:notification withCompletionHandler:completionHandler];
    else
        completionHandler(UNNotificationPresentationOptionNone);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)(void))completionHandler API_AVAILABLE(ios(10.0), macos(10.14))
{
    CLY_LOG_D(@"%s notification response received, actionIdentifier: [%@]", __FUNCTION__, response.actionIdentifier);
    CLY_LOG_D(@"%s notification response payload detail, userInfo: [%@]", __FUNCTION__, response.notification.request.content.userInfo);

    if (CountlyConsentManager.sharedInstance.consentForPushNotifications)
    {
        NSDictionary* countlyPayload = response.notification.request.content.userInfo[kCountlyPNKeyCountlyPayload];
        NSString* notificationID = countlyPayload[kCountlyPNKeyNotificationID];

        if (notificationID)
        {
            NSInteger buttonIndex = 0;
            NSString* URL = nil;

            CLY_LOG_D(@"%s resolving the tapped notification action, notificationID: [%@]", __FUNCTION__, notificationID);

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
    if (@available(iOS 12.0, *))
    {
        id<UNUserNotificationCenterDelegate> appDelegate = (id<UNUserNotificationCenterDelegate>)CLYApplication.sharedApplication.delegate;

        if ([appDelegate respondsToSelector:@selector(userNotificationCenter:openSettingsForNotification:)])
            [appDelegate userNotificationCenter:center openSettingsForNotification:notification];
    }
}

#pragma mark ---

- (void)application:(CLYApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken{}
- (void)application:(CLYApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error{}
#endif
@end


@implementation NSObject (CountlyPushNotifications)
#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_OSX)
- (void)Countly_application:(CLYApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    CLY_LOG_I(@"%s push device token received from the system, tokenByteLength: [%lu]", __FUNCTION__, (unsigned long)deviceToken.length);
    CLY_LOG_D(@"%s push device token detail, rawToken: [%@]", __FUNCTION__, deviceToken);

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
    CLY_LOG_E(@"%s remote notification registration failed, error: [%@]", __FUNCTION__, error.localizedDescription);

    CountlyPushNotifications.sharedInstance.token = kCountlyTokenError;

    [CountlyPushNotifications.sharedInstance sendToken];

    [self Countly_application:application didFailToRegisterForRemoteNotificationsWithError:error];
}
#endif

#endif
@end
