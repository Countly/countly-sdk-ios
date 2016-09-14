// Countly.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#pragma mark - Countly Core

#import "CountlyCommon.h"

@interface Countly ()
{
    NSTimeInterval unsentSessionLength;
    NSTimer *timer;
    NSTimeInterval lastTime;
    BOOL isSuspended;
}

@property (nonatomic, strong) NSMutableDictionary *messageInfos;

@end

@implementation Countly

+ (instancetype)sharedInstance
{
    static Countly *s_sharedCountly = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedCountly = self.new;});
    return s_sharedCountly;
}

- (instancetype)init
{
    if (self = [super init])
    {
        timer = nil;
        isSuspended = NO;
        unsentSessionLength = 0;

        self.messageInfos = NSMutableDictionary.new;

#if (TARGET_OS_IOS  || TARGET_OS_TV)
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(didEnterBackgroundCallBack:)
                                                   name:UIApplicationDidEnterBackgroundNotification
                                                 object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(willEnterForegroundCallBack:)
                                                   name:UIApplicationWillEnterForegroundNotification
                                                 object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(willTerminateCallBack:)
                                                   name:UIApplicationWillTerminateNotification
                                                 object:nil];
#elif TARGET_OS_OSX
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(willTerminateCallBack:)
                                                   name:NSApplicationWillTerminateNotification
                                                 object:nil];
#endif
    }

    return self;
}

- (void)setNewDeviceID:(NSString *)deviceID onServer:(BOOL)onServer
{
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

#if TARGET_OS_IOS
    if([deviceID isEqualToString:CLYIDFA])
        deviceID = [CountlyDeviceInfo.sharedInstance zeroSafeIDFA];
    else if([deviceID isEqualToString:CLYIDFV])
        deviceID = UIDevice.currentDevice.identifierForVendor.UUIDString;
    else if([deviceID isEqualToString:CLYOpenUDID])
        deviceID = [Countly_OpenUDID value];
#elif TARGET_OS_OSX
    if([deviceID isEqualToString:CLYOpenUDID])
        deviceID = [Countly_OpenUDID value];
#endif

#pragma GCC diagnostic pop

    if([deviceID isEqualToString:CountlyDeviceInfo.sharedInstance.deviceID])
        return;

    if(onServer)
    {
        NSString* oldDeviceID = CountlyDeviceInfo.sharedInstance.deviceID;

        [CountlyDeviceInfo.sharedInstance initializeDeviceID:deviceID];

        [CountlyConnectionManager.sharedInstance sendOldDeviceID:oldDeviceID];
    }
    else
    {
        [Countly.sharedInstance suspend];

        [CountlyDeviceInfo.sharedInstance initializeDeviceID:deviceID];

        [Countly.sharedInstance resume];

        [CountlyPersistency.sharedInstance clearAllTimedEvents];
    }
}

- (void)setCustomHeaderFieldValue:(NSString *)customHeaderFieldValue
{
    CountlyConnectionManager.sharedInstance.customHeaderFieldValue = customHeaderFieldValue;
    [CountlyConnectionManager.sharedInstance tick];
}

#pragma mark ---

- (void)startWithConfig:(CountlyConfig *)config
{
    NSAssert(config.appKey && ![config.appKey isEqualToString:@"YOUR_APP_KEY"],@"[CountlyAssert] App key in Countly configuration is not set!");
    NSAssert(config.host && ![config.host isEqualToString:@"https://YOUR_COUNTLY_SERVER"],@"[CountlyAssert] Host in Countly configuration is not set!");

    if(!CountlyDeviceInfo.sharedInstance.deviceID || config.forceDeviceIDInitialization)
    {
        [CountlyDeviceInfo.sharedInstance initializeDeviceID:config.deviceID];
    }

    CountlyPersistency.sharedInstance.eventSendThreshold = config.eventSendThreshold;
    CountlyPersistency.sharedInstance.storedRequestsLimit = config.storedRequestsLimit;
    CountlyConnectionManager.sharedInstance.updateSessionPeriod = config.updateSessionPeriod;
    CountlyCommon.sharedInstance.ISOCountryCode = config.ISOCountryCode;
    CountlyCommon.sharedInstance.city = config.city;
    CountlyCommon.sharedInstance.location = CLLocationCoordinate2DIsValid(config.location)?[NSString stringWithFormat:@"%f,%f", config.location.latitude, config.location.longitude]:nil;
    CountlyConnectionManager.sharedInstance.pinnedCertificates = config.pinnedCertificates;
    CountlyConnectionManager.sharedInstance.customHeaderFieldName = config.customHeaderFieldName;
    CountlyConnectionManager.sharedInstance.customHeaderFieldValue = config.customHeaderFieldValue;
    CountlyConnectionManager.sharedInstance.secretSalt = config.secretSalt;
    CountlyConnectionManager.sharedInstance.alwaysUsePOST = config.alwaysUsePOST;
#if TARGET_OS_IOS
    CountlyStarRating.sharedInstance.message = config.starRatingMessage;
    CountlyStarRating.sharedInstance.dismissButtonTitle = config.starRatingDismissButtonTitle;
    CountlyStarRating.sharedInstance.sessionCount = config.starRatingSessionCount;
    CountlyStarRating.sharedInstance.disableAskingForEachAppVersion = config.starRatingDisableAskingForEachAppVersion;

    [CountlyStarRating.sharedInstance checkForAutoAsk];

    [CountlyCommon.sharedInstance transferParentDeviceID];

    if([config.features containsObject:CLYMessaging])
    {
        NSAssert(![config.launchOptions isEqualToDictionary:@{@"CLYAssertion":@"forLaunchOptions"}],@"[CountlyAssert] LaunchOptions in Countly configuration is not set!");

        CountlyConnectionManager.sharedInstance.isTestDevice = config.isTestDevice;

        [self startWithMessagingUsing:config.appKey withHost:config.host andOptions:config.launchOptions];
    }
    else
    {
        [self start:config.appKey withHost:config.host];
    }

    if([config.features containsObject:CLYCrashReporting])
    {
        CountlyCrashReporter.sharedInstance.crashSegmentation = config.crashSegmentation;
        [CountlyCrashReporter.sharedInstance startCrashReporting];
    }

    if([config.features containsObject:CLYAutoViewTracking])
    {
        [CountlyViewTracking.sharedInstance startAutoViewTracking];
    }
#else
    [self start:config.appKey withHost:config.host];
#endif

    if([config.features containsObject:CLYAPM])
        [CountlyAPM.sharedInstance startAPM];

#if (TARGET_OS_WATCH)
    [CountlyCommon.sharedInstance activateWatchConnectivity];
#endif
}

- (void)start:(NSString *)appKey withHost:(NSString *)appHost
{
    timer = [NSTimer scheduledTimerWithTimeInterval:CountlyConnectionManager.sharedInstance.updateSessionPeriod target:self selector:@selector(onTimer:) userInfo:nil repeats:YES];
    lastTime = NSDate.date.timeIntervalSince1970;
    CountlyConnectionManager.sharedInstance.appKey = appKey;
    CountlyConnectionManager.sharedInstance.appHost = appHost;
    [CountlyConnectionManager.sharedInstance beginSession];
}


#if TARGET_OS_IOS
- (void)startWithMessagingUsing:(NSString *)appKey withHost:(NSString *)appHost andOptions:(NSDictionary *)options
{
    [self start:appKey withHost:appHost];

    NSDictionary *notification = [options objectForKey:UIApplicationLaunchOptionsRemoteNotificationKey];
    if (notification) {
        COUNTLY_LOG(@"Got notification on app launch: %@", notification);
        [self handleRemoteNotification:notification displayingMessage:NO];
    }
}
#endif

#pragma mark ---

- (void)onTimer:(NSTimer *)timer
{
    if (isSuspended == YES)
        return;

    NSTimeInterval currTime = NSDate.date.timeIntervalSince1970;
    unsentSessionLength += currTime - lastTime;
    lastTime = currTime;

    int duration = unsentSessionLength;
    [CountlyConnectionManager.sharedInstance updateSessionWithDuration:duration];
    unsentSessionLength -= duration;

    [CountlyConnectionManager.sharedInstance sendEvents];
}

- (void)suspend
{
    COUNTLY_LOG(@"Suspending...");

    isSuspended = YES;

    [CountlyConnectionManager.sharedInstance sendEvents];

    NSTimeInterval currTime = NSDate.date.timeIntervalSince1970;
    unsentSessionLength += currTime - lastTime;

    int duration = unsentSessionLength;
    [CountlyConnectionManager.sharedInstance endSessionWithDuration:duration];
    unsentSessionLength -= duration;

    [CountlyPersistency.sharedInstance saveToFileSync];
}

- (void)resume
{
#if TARGET_OS_WATCH
    //NOTE: skip first time to prevent double begin session because of applicationDidBecomeActive call on app lunch
    static BOOL isFirstCall = YES;

    if(isFirstCall)
    {
        isFirstCall = NO;
        return;
    }
#endif

    lastTime = NSDate.date.timeIntervalSince1970;

    [CountlyConnectionManager.sharedInstance beginSession];

    isSuspended = NO;
}

#pragma mark ---

- (void)didEnterBackgroundCallBack:(NSNotification *)notification
{
    COUNTLY_LOG(@"App did enter background.");
    [self suspend];
}

- (void)willEnterForegroundCallBack:(NSNotification *)notification
{
    COUNTLY_LOG(@"App will enter foreground.");
    [self resume];
}

- (void)willTerminateCallBack:(NSNotification *)notification
{
    COUNTLY_LOG(@"App will terminate.");

    [CountlyViewTracking.sharedInstance endView];

    [self suspend];
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self];

    if (timer)
    {
        [timer invalidate];
        timer = nil;
    }
}



#pragma mark - Countly CustomEvents
- (void)recordEvent:(NSString *)key
{
    [self recordEvent:key segmentation:nil count:1 sum:0 duration:0 timestamp:CountlyCommon.sharedInstance.uniqueTimestamp];
}

- (void)recordEvent:(NSString *)key count:(NSUInteger)count
{
    [self recordEvent:key segmentation:nil count:count sum:0 duration:0 timestamp:CountlyCommon.sharedInstance.uniqueTimestamp];
}

- (void)recordEvent:(NSString *)key sum:(double)sum
{
    [self recordEvent:key segmentation:nil count:1 sum:sum duration:0 timestamp:CountlyCommon.sharedInstance.uniqueTimestamp];
}

- (void)recordEvent:(NSString *)key duration:(NSTimeInterval)duration
{
    [self recordEvent:key segmentation:nil count:1 sum:0 duration:duration timestamp:CountlyCommon.sharedInstance.uniqueTimestamp];
}

- (void)recordEvent:(NSString *)key count:(NSUInteger)count sum:(double)sum
{
    [self recordEvent:key segmentation:nil count:count sum:sum duration:0 timestamp:CountlyCommon.sharedInstance.uniqueTimestamp];
}

- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation
{
    [self recordEvent:key segmentation:segmentation count:1 sum:0 duration:0 timestamp:CountlyCommon.sharedInstance.uniqueTimestamp];
}

- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(NSUInteger)count
{
    [self recordEvent:key segmentation:segmentation count:count sum:0 duration:0 timestamp:CountlyCommon.sharedInstance.uniqueTimestamp];
}

- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(NSUInteger)count sum:(double)sum
{
    [self recordEvent:key segmentation:segmentation count:count sum:sum duration:0 timestamp:CountlyCommon.sharedInstance.uniqueTimestamp];
}

- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(NSUInteger)count sum:(double)sum duration:(NSTimeInterval)duration
{
    [self recordEvent:key segmentation:segmentation count:count sum:sum duration:duration timestamp:CountlyCommon.sharedInstance.uniqueTimestamp];
}

- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(NSUInteger)count sum:(double)sum duration:(NSTimeInterval)duration timestamp:(NSTimeInterval)timestamp
{
    CountlyEvent *event = CountlyEvent.new;
    event.key = key;
    event.segmentation = segmentation;
    event.count = MAX(count, 1);
    event.sum = sum;
    event.timestamp = timestamp;
    event.hourOfDay = CountlyCommon.sharedInstance.hourOfDay;
    event.dayOfWeek = CountlyCommon.sharedInstance.dayOfWeek;
    event.duration = duration;

    [CountlyPersistency.sharedInstance recordEvent:event];
}

#pragma mark ---

- (void)startEvent:(NSString *)key
{
    CountlyEvent *event = CountlyEvent.new;
    event.key = key;
    event.timestamp = CountlyCommon.sharedInstance.uniqueTimestamp;
    event.hourOfDay = CountlyCommon.sharedInstance.hourOfDay;
    event.dayOfWeek = CountlyCommon.sharedInstance.dayOfWeek;

    [CountlyPersistency.sharedInstance recordTimedEvent:event];
}

- (void)endEvent:(NSString *)key
{
    [self endEvent:key segmentation:nil count:1 sum:0];
}

- (void)endEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(NSUInteger)count sum:(double)sum
{
    CountlyEvent *event = [CountlyPersistency.sharedInstance timedEventForKey:key];

    if(!event)
    {
        COUNTLY_LOG(@"Event with key '%@' not started before!", key);
        return;
    }

    event.segmentation = segmentation;
    event.count = MAX(count, 1);;
    event.sum = sum;
    event.duration = NSDate.date.timeIntervalSince1970 - event.timestamp;

    [CountlyPersistency.sharedInstance recordEvent:event];
}



#pragma mark - Countly Messaging
#if TARGET_OS_IOS

#define kPushToMessage      1
#define kPushToOpenLink     2
#define kPushToUpdate       3
#define kPushToReview       4
#define kPushEventKeyOpen   @"[CLY]_push_open"
#define kPushEventKeyAction @"[CLY]_push_action"
#define kAppIdPropertyKey   @"[CLY]_app_id"
#define kCountlyAppId       @"695261996"

#pragma mark ---

- (BOOL)handleRemoteNotification:(NSDictionary *)info withButtonTitles:(NSArray *)titles
{
    return [self handleRemoteNotification:info displayingMessage:YES withButtonTitles:titles];
}

- (BOOL)handleRemoteNotification:(NSDictionary *)info
{
    return [self handleRemoteNotification:info displayingMessage:YES];
}

- (BOOL)handleRemoteNotification:(NSDictionary *)info displayingMessage:(BOOL)displayMessage
{
    return [self handleRemoteNotification:info displayingMessage:displayMessage
                         withButtonTitles:@[@"Cancel", @"Open", @"Update", @"Review"]];
}

- (BOOL)handleRemoteNotification:(NSDictionary *)info displayingMessage:(BOOL)displayMessage withButtonTitles:(NSArray *)titles
{
    COUNTLY_LOG(@"Handling remote notification (display? %d): %@", displayMessage, info);

    NSDictionary *aps = info[@"aps"];
    NSDictionary *countly = info[@"c"];

    if (countly[@"i"]) {
        COUNTLY_LOG(@"Message id: %@", countly[@"i"]);

        [self recordPushOpenForCountlyDictionary:countly];
        NSString *appName = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
        NSString *message = [aps objectForKey:@"alert"];

        int type = 0;
        NSString *action = nil;

        if ([aps objectForKey:@"content-available"]) {
            return NO;
        } else if (countly[@"l"]) {
            type = kPushToOpenLink;
            action = titles[1];
        } else if (countly[@"r"] != nil) {
            type = kPushToReview;
            action = titles[3];
        } else if (countly[@"u"] != nil) {
            type = kPushToUpdate;
            action = titles[2];
        } else if (displayMessage) {
            type = kPushToMessage;
            action = nil;
        }

        if (type && [message length]) {
            UIAlertView *alert;
            if (action) {
                alert = [[UIAlertView alloc] initWithTitle:appName message:message delegate:self
                                         cancelButtonTitle:titles[0] otherButtonTitles:action, nil];
            } else {
                alert = [[UIAlertView alloc] initWithTitle:appName message:message delegate:self
                                         cancelButtonTitle:titles[0] otherButtonTitles:nil];
            }
            alert.tag = type;

            _messageInfos[alert.description] = info;

            [alert show];
            return YES;
        }
    }

    return NO;
}

#pragma mark ---

- (NSMutableSet *) countlyNotificationCategories
{
    return [self countlyNotificationCategoriesWithActionTitles:@[@"Cancel", @"Open", @"Update", @"Review"]];
}

- (NSMutableSet *) countlyNotificationCategoriesWithActionTitles:(NSArray *)actions
{
    UIMutableUserNotificationCategory *url = [UIMutableUserNotificationCategory new],
    *upd = [UIMutableUserNotificationCategory new],
    *rev = [UIMutableUserNotificationCategory new];

    url.identifier = @"[CLY]_url";
    upd.identifier = @"[CLY]_update";
    rev.identifier = @"[CLY]_review";

    UIMutableUserNotificationAction *cancel = [UIMutableUserNotificationAction new],
    *open = [UIMutableUserNotificationAction new],
    *update = [UIMutableUserNotificationAction new],
    *review = [UIMutableUserNotificationAction new];

    cancel.identifier = @"[CLY]_cancel";
    open.identifier   = @"[CLY]_open";
    update.identifier = @"[CLY]_update";
    review.identifier = @"[CLY]_review";

    cancel.title = actions[0];
    open.title   = actions[1];
    update.title = actions[2];
    review.title = actions[3];

    cancel.activationMode = UIUserNotificationActivationModeBackground;
    open.activationMode   = UIUserNotificationActivationModeForeground;
    update.activationMode = UIUserNotificationActivationModeForeground;
    review.activationMode = UIUserNotificationActivationModeForeground;

    cancel.destructive = NO;
    open.destructive   = NO;
    update.destructive = NO;
    review.destructive = NO;


    [url setActions:@[cancel, open] forContext:UIUserNotificationActionContextMinimal];
    [url setActions:@[cancel, open] forContext:UIUserNotificationActionContextDefault];

    [upd setActions:@[cancel, update] forContext:UIUserNotificationActionContextMinimal];
    [upd setActions:@[cancel, update] forContext:UIUserNotificationActionContextDefault];

    [rev setActions:@[cancel, review] forContext:UIUserNotificationActionContextMinimal];
    [rev setActions:@[cancel, review] forContext:UIUserNotificationActionContextDefault];

    NSMutableSet *set = [NSMutableSet setWithObjects:url, upd, rev, nil];

    return set;
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    NSDictionary *info = [_messageInfos[alertView.description] copy];
    [_messageInfos removeObjectForKey:alertView.description];

    if (alertView.tag == kPushToMessage) {
        // do nothing
    } else if (buttonIndex != alertView.cancelButtonIndex) {
        if (alertView.tag == kPushToOpenLink) {
            [self recordPushActionForCountlyDictionary:info[@"c"]];
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:info[@"c"][@"l"]]];
        } else if (alertView.tag == kPushToUpdate) {
            if ([info[@"c"][@"u"] length]) {
                [self openUpdate:info[@"c"][@"u"] forInfo:info];
            } else {
                [self withAppStoreId:^(NSString *appStoreId) {
                    [self openUpdate:appStoreId forInfo:info];
                }];
            }
        } else if (alertView.tag == kPushToReview) {
            if ([info[@"c"][@"r"] length]) {
                [self openReview:info[@"c"][@"r"] forInfo:info];
            } else {
                [self withAppStoreId:^(NSString *appStoreId) {
                    [self openReview:appStoreId forInfo:info];
                }];
            }
        }
    }
}

- (void)withAppStoreId:(void (^)(NSString *))block
{
    NSString *appStoreId = [[NSUserDefaults standardUserDefaults] stringForKey:kAppIdPropertyKey];
    if (appStoreId) {
        block(appStoreId);
    } else {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            NSString *appStoreId = nil;
            NSString *bundle = [CountlyDeviceInfo bundleId];
            NSString *appStoreCountry = [(NSLocale *)[NSLocale currentLocale] objectForKey:NSLocaleCountryCode];
            if ([appStoreCountry isEqualToString:@"150"]) {
                appStoreCountry = @"eu";
            } else if ([[appStoreCountry stringByReplacingOccurrencesOfString:@"[A-Za-z]{2}" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, 2)] length]) {
                appStoreCountry = @"us";
            }

            NSString *iTunesServiceURL = [NSString stringWithFormat:@"http://itunes.apple.com/%@/lookup", appStoreCountry];
            iTunesServiceURL = [iTunesServiceURL stringByAppendingFormat:@"?bundleId=%@", bundle];

            NSError *error = nil;
            NSURLResponse *response = nil;
            NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:iTunesServiceURL] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:10];
            NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
            NSInteger statusCode = ((NSHTTPURLResponse *)response).statusCode;
            if (data && statusCode == 200) {

                id json = [[NSJSONSerialization JSONObjectWithData:data options:(NSJSONReadingOptions)0 error:&error][@"results"] lastObject];

                if (!error && [json isKindOfClass:[NSDictionary class]]) {
                    NSString *bundleID = json[@"bundleId"];
                    if (bundleID && [bundleID isEqualToString:bundle]) {
                        appStoreId = [json[@"trackId"] stringValue];
                    }
                }
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSUserDefaults standardUserDefaults] setObject:appStoreId forKey:kAppIdPropertyKey];
                [[NSUserDefaults standardUserDefaults] synchronize];
                block(appStoreId);
            });
        });
    }

}

- (void)openUpdate:(NSString *)appId forInfo:(NSDictionary *)info
{
    if (!appId) appId = kCountlyAppId;

    NSString *urlFormat = nil;
#if TARGET_OS_IOS
    urlFormat = @"itms-apps://itunes.apple.com/app/id%@";
#else
    urlFormat = @"macappstore://itunes.apple.com/app/id%@";
#endif

    [self recordPushActionForCountlyDictionary:info[@"c"]];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:urlFormat, appId]];
    [[UIApplication sharedApplication] openURL:url];
}

- (void)openReview:(NSString *)appId forInfo:(NSDictionary *)info
{
    if (!appId) appId = kCountlyAppId;

    NSString *urlFormat = nil;
#if TARGET_OS_IOS
    float iOSVersion = [[UIDevice currentDevice].systemVersion floatValue];
    if (iOSVersion >= 7.0f && iOSVersion < 7.1f) {
        urlFormat = @"itms-apps://itunes.apple.com/app/id%@";
    } else {
        urlFormat = @"itms-apps://itunes.apple.com/WebObjects/MZStore.woa/wa/viewContentsUserReviews?type=Purple+Software&id=%@";
    }
#else
    urlFormat = @"macappstore://itunes.apple.com/app/id%@";
#endif

    [self recordPushActionForCountlyDictionary:info[@"c"]];

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:urlFormat, appId]];
    [[UIApplication sharedApplication] openURL:url];
}

#pragma mark ---

- (void)recordPushOpenForCountlyDictionary:(NSDictionary *)c
{
    [self recordEvent:kPushEventKeyOpen segmentation:@{@"i": c[@"i"]} count:1];
}

- (void)recordPushActionForCountlyDictionary:(NSDictionary *)c
{
    [self recordEvent:kPushEventKeyAction segmentation:@{@"i": c[@"i"]} count:1];
}

- (void)recordLocation:(CLLocationCoordinate2D)coordinate
{
    [CountlyConnectionManager.sharedInstance sendLocation:coordinate];
}

#pragma mark ---

- (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    const unsigned *tokenBytes = [deviceToken bytes];
    NSString *token = [NSString stringWithFormat:@"%08x%08x%08x%08x%08x%08x%08x%08x",
                       ntohl(tokenBytes[0]), ntohl(tokenBytes[1]), ntohl(tokenBytes[2]),
                       ntohl(tokenBytes[3]), ntohl(tokenBytes[4]), ntohl(tokenBytes[5]),
                       ntohl(tokenBytes[6]), ntohl(tokenBytes[7])];
    [CountlyConnectionManager.sharedInstance sendPushToken:token];
}

- (void)didFailToRegisterForRemoteNotifications
{
    [CountlyConnectionManager.sharedInstance sendPushToken:nil];
}
#endif



#pragma mark - Countly CrashReporting

#if TARGET_OS_IOS
- (void)recordHandledException:(NSException *)exception
{
    [CountlyCrashReporter.sharedInstance recordHandledException:exception];
}

- (void)crashLog:(NSString *)format, ...
{
    va_list args;
    va_start(args, format);
    [CountlyCrashReporter.sharedInstance logWithFormat:format andArguments:args];
    va_end(args);
}
#endif



#pragma mark - Countly APM

- (void)addExceptionForAPM:(NSString *)exceptionURL
{
    [CountlyAPM.sharedInstance addExceptionForAPM:exceptionURL];
}

- (void)removeExceptionForAPM:(NSString *)exceptionURL
{
    [CountlyAPM.sharedInstance removeExceptionForAPM:exceptionURL];
}



#pragma mark - Countly AutoViewTracking

- (void)reportView:(NSString *)viewName
{
    [CountlyViewTracking.sharedInstance reportView:viewName];
}

#if TARGET_OS_IOS
- (void)addExceptionForAutoViewTracking:(Class)exceptionViewControllerSubclass
{
    [CountlyViewTracking.sharedInstance addExceptionForAutoViewTracking:exceptionViewControllerSubclass];
}

- (void)removeExceptionForAutoViewTracking:(Class)exceptionViewControllerSubclass
{
    [CountlyViewTracking.sharedInstance removeExceptionForAutoViewTracking:exceptionViewControllerSubclass];
}

- (void)setIsAutoViewTrackingEnabled:(BOOL)isAutoViewTrackingEnabled
{
    CountlyViewTracking.sharedInstance.isAutoViewTrackingEnabled = isAutoViewTrackingEnabled;
}

- (BOOL)isAutoViewTrackingEnabled
{
    return CountlyViewTracking.sharedInstance.isAutoViewTrackingEnabled;
}
#endif



#pragma mark - Countly UserDetails

+ (CountlyUserDetails *)user
{
    return CountlyUserDetails.sharedInstance;
}



#pragma mark - Countly StarRating
#if TARGET_OS_IOS

- (void)askForStarRating:(void(^)(NSInteger rating))completion
{
    [CountlyStarRating.sharedInstance showDialog:completion];
}
#endif

@end
