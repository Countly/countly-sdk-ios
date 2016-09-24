// CountlyPushNotifications.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

NSString* const kCountlyReservedEventPushOpen = @"[CLY]_push_open";
NSString* const kCountlyReservedEventPushAction = @"[CLY]_push_action";
static char kUIAlertViewAssociatedObjectKey;

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
    Method O_method;
    Method C_method;
    SEL selector;
    
    
    selector = @selector(application:didRegisterForRemoteNotificationsWithDeviceToken:);
    O_method = class_getInstanceMethod(appDelegateClass, selector);
    if(O_method == NULL)
    {
        Method method = class_getInstanceMethod(self.class, selector);
        IMP imp = method_getImplementation(method);
        const char *methodTypeEncoding = method_getTypeEncoding(method);
        class_addMethod(appDelegateClass, selector, imp, methodTypeEncoding);
        O_method = class_getInstanceMethod(appDelegateClass, selector);
    }
    
    C_method = class_getInstanceMethod(appDelegateClass, @selector(Countly_application:didRegisterForRemoteNotificationsWithDeviceToken:));
    method_exchangeImplementations(O_method, C_method);

    
    selector = @selector(application:didFailToRegisterForRemoteNotificationsWithError:);
    O_method = class_getInstanceMethod(appDelegateClass, selector);
    if(O_method == NULL)
    {
        Method method = class_getInstanceMethod(self.class, selector);
        IMP imp = method_getImplementation(method);
        const char *methodTypeEncoding = method_getTypeEncoding(method);
        class_addMethod(appDelegateClass, selector, imp, methodTypeEncoding);
        O_method = class_getInstanceMethod(appDelegateClass, selector);
    }
    
    C_method = class_getInstanceMethod(appDelegateClass, @selector(Countly_application:didFailToRegisterForRemoteNotificationsWithError:));
    method_exchangeImplementations(O_method, C_method);
    
    
    selector = @selector(application:didReceiveRemoteNotification:fetchCompletionHandler:);
    O_method = class_getInstanceMethod(appDelegateClass, selector);
    if(O_method == NULL)
    {
        Method method = class_getInstanceMethod(self.class, selector);
        IMP imp = method_getImplementation(method);
        const char *methodTypeEncoding = method_getTypeEncoding(method);
        class_addMethod(appDelegateClass, selector, imp, methodTypeEncoding);
        O_method = class_getInstanceMethod(appDelegateClass, selector);
    }
    
    C_method = class_getInstanceMethod(appDelegateClass, @selector(Countly_application:didReceiveRemoteNotification:fetchCompletionHandler:));
    method_exchangeImplementations(O_method, C_method);
}

- (void)handleNotification:(NSDictionary *)notification
{
    COUNTLY_LOG(@"Handling remote notification %@", notification.description);

    NSDictionary* countlyPayload = notification[@"c"];
    NSString* countlyPushNotificationID = countlyPayload[@"i"];
    if (countlyPushNotificationID)
    {
        COUNTLY_LOG(@"Countly Push Notification ID: %@", countlyPushNotificationID);
    
        [Countly.sharedInstance recordEvent:kCountlyReservedEventPushOpen segmentation:@{@"i":countlyPushNotificationID}];
    
        NSString* message = notification[@"aps"][@"alert"];
        if(!message || self.shouldNotShowAlert)
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
            if (!cancelButtonTitle) cancelButtonTitle = NSLocalizedString(@"Cancel", nil);;
        }

        if(UIAlertController.class)
        {
            UIAlertController* alertController = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
            UIAlertAction* cancel = [UIAlertAction actionWithTitle:cancelButtonTitle style:UIAlertActionStyleCancel handler:nil];
            [alertController addAction:cancel];

            if(actionButtonTitle)
            {
                UIAlertAction* other = [UIAlertAction actionWithTitle:actionButtonTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action)
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

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken{};
- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error{};
- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler
{
    completionHandler(UIBackgroundFetchResultNewData);
};
#endif
@end


#if TARGET_OS_IOS
@implementation UIResponder (CountlyPushNotifications)
- (void)Countly_application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    COUNTLY_LOG(@"App didRegisterForRemoteNotificationsWithDeviceToken: %@", deviceToken.description);
    
    const char *bytes = [deviceToken bytes];
    NSMutableString *token = NSMutableString.new;
    for (NSUInteger i = 0; i < deviceToken.length; i++)
        [token appendFormat:@"%02hhx", bytes[i]];
    
    [CountlyConnectionManager.sharedInstance sendPushToken:token];
    
    [self Countly_application:application didRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
}


- (void)Countly_application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
    COUNTLY_LOG(@"App didFailToRegisterForRemoteNotificationsWithError");
    
    [CountlyConnectionManager.sharedInstance sendPushToken:nil];

    [self Countly_application:application didFailToRegisterForRemoteNotificationsWithError:error];
}

- (void)Countly_application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler;
{
    COUNTLY_LOG(@"App didReceiveRemoteNotification:fetchCompletionHandler");

    [CountlyPushNotifications.sharedInstance handleNotification:userInfo];
    
    [self Countly_application:application didReceiveRemoteNotification:userInfo fetchCompletionHandler:completionHandler];
}
@end
#endif