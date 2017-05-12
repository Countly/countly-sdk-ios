// Countly.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#pragma mark - Countly Core

#import "CountlyCommon.h"

@interface Countly ()
{
    NSTimer* timer;
    BOOL isSuspended;
}
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

#pragma mark ---

- (void)startWithConfig:(CountlyConfig *)config
{
    CountlyCommon.sharedInstance.enableDebug = config.enableDebug;

    NSAssert(config.appKey && ![config.appKey isEqualToString:@"YOUR_APP_KEY"], @"[CountlyAssert] App key in Countly configuration is not set!");
    NSAssert(config.host && ![config.host isEqualToString:@"https://YOUR_COUNTLY_SERVER"], @"[CountlyAssert] Host in Countly configuration is not set!");

    COUNTLY_LOG(@"Initializing with %@ SDK v%@", kCountlySDKName, kCountlySDKVersion);

    if (!CountlyDeviceInfo.sharedInstance.deviceID || config.forceDeviceIDInitialization)
        [CountlyDeviceInfo.sharedInstance initializeDeviceID:config.deviceID];

    CountlyConnectionManager.sharedInstance.appKey = config.appKey;
    BOOL hostHasExtraSlash = [[config.host substringFromIndex:config.host.length-1] isEqualToString:@"/"];
    CountlyConnectionManager.sharedInstance.host = hostHasExtraSlash ? [config.host substringToIndex:config.host.length-1] : config.host;
    CountlyConnectionManager.sharedInstance.alwaysUsePOST = config.alwaysUsePOST;
    CountlyConnectionManager.sharedInstance.pinnedCertificates = config.pinnedCertificates;
    CountlyConnectionManager.sharedInstance.customHeaderFieldName = config.customHeaderFieldName;
    CountlyConnectionManager.sharedInstance.customHeaderFieldValue = config.customHeaderFieldValue;
    CountlyConnectionManager.sharedInstance.secretSalt = config.secretSalt;

    CountlyPersistency.sharedInstance.eventSendThreshold = config.eventSendThreshold;
    CountlyPersistency.sharedInstance.storedRequestsLimit = config.storedRequestsLimit;

    CountlyCommon.sharedInstance.manualSessionHandling = config.manualSessionHandling;
    CountlyCommon.sharedInstance.enableAppleWatch = config.enableAppleWatch;
    CountlyCommon.sharedInstance.ISOCountryCode = config.ISOCountryCode;
    CountlyCommon.sharedInstance.city = config.city;
    CountlyCommon.sharedInstance.location = CLLocationCoordinate2DIsValid(config.location)?[NSString stringWithFormat:@"%f,%f", config.location.latitude, config.location.longitude]:nil;
    CountlyCommon.sharedInstance.IP = config.IP;

#if TARGET_OS_IOS
    CountlyStarRating.sharedInstance.message = config.starRatingMessage;
    CountlyStarRating.sharedInstance.sessionCount = config.starRatingSessionCount;
    CountlyStarRating.sharedInstance.disableAskingForEachAppVersion = config.starRatingDisableAskingForEachAppVersion;
    CountlyStarRating.sharedInstance.ratingCompletionForAutoAsk = config.starRatingCompletion;
    [CountlyStarRating.sharedInstance checkForAutoAsk];

    [CountlyCommon.sharedInstance transferParentDeviceID];

    if ([config.features containsObject:CLYPushNotifications])
    {
        CountlyPushNotifications.sharedInstance.isTestDevice = config.isTestDevice;
        CountlyPushNotifications.sharedInstance.sendPushTokenAlways = config.sendPushTokenAlways;
        CountlyPushNotifications.sharedInstance.doNotShowAlertForNotifications = config.doNotShowAlertForNotifications;
        [CountlyPushNotifications.sharedInstance startPushNotifications];
    }

    if ([config.features containsObject:CLYCrashReporting])
    {
        CountlyCrashReporter.sharedInstance.crashSegmentation = config.crashSegmentation;
        [CountlyCrashReporter.sharedInstance startCrashReporting];
    }
#endif

#if (TARGET_OS_IOS || TARGET_OS_TV)
    if ([config.features containsObject:CLYAutoViewTracking])
        [CountlyViewTracking.sharedInstance startAutoViewTracking];
#endif

//NOTE: Disable APM feature until server completely supports it
//    if ([config.features containsObject:CLYAPM])
//        [CountlyAPM.sharedInstance startAPM];

    timer = [NSTimer scheduledTimerWithTimeInterval:config.updateSessionPeriod target:self selector:@selector(onTimer:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];

    if (!CountlyCommon.sharedInstance.manualSessionHandling)
        [CountlyConnectionManager.sharedInstance beginSession];

#if (TARGET_OS_WATCH)
    CountlyCommon.sharedInstance.enableAppleWatch = YES;
    [CountlyCommon.sharedInstance activateWatchConnectivity];
#endif
}

- (void)setNewDeviceID:(NSString *)deviceID onServer:(BOOL)onServer
{
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

#if TARGET_OS_IOS
    if ([deviceID isEqualToString:CLYIDFA])
        deviceID = [CountlyDeviceInfo.sharedInstance zeroSafeIDFA];
    else if ([deviceID isEqualToString:CLYIDFV])
        deviceID = UIDevice.currentDevice.identifierForVendor.UUIDString;
    else if ([deviceID isEqualToString:CLYOpenUDID])
        deviceID = [Countly_OpenUDID value];
#elif TARGET_OS_OSX
    if ([deviceID isEqualToString:CLYOpenUDID])
        deviceID = [Countly_OpenUDID value];
#endif

#pragma GCC diagnostic pop

    if ([deviceID isEqualToString:CountlyDeviceInfo.sharedInstance.deviceID])
        return;

    if (onServer)
    {
        NSString* oldDeviceID = CountlyDeviceInfo.sharedInstance.deviceID;

        [CountlyDeviceInfo.sharedInstance initializeDeviceID:deviceID];

        [CountlyConnectionManager.sharedInstance sendOldDeviceID:oldDeviceID];
    }
    else
    {
        [self suspend];

        [CountlyDeviceInfo.sharedInstance initializeDeviceID:deviceID];

        [self resume];

        [CountlyPersistency.sharedInstance clearAllTimedEvents];
    }
}

- (void)setCustomHeaderFieldValue:(NSString *)customHeaderFieldValue
{
    CountlyConnectionManager.sharedInstance.customHeaderFieldValue = customHeaderFieldValue;
    [CountlyConnectionManager.sharedInstance proceedOnQueue];
}

#pragma mark ---

- (void)beginSession
{
    if (CountlyCommon.sharedInstance.manualSessionHandling)
        [CountlyConnectionManager.sharedInstance beginSession];
}

- (void)updateSession
{
    if (CountlyCommon.sharedInstance.manualSessionHandling)
        [CountlyConnectionManager.sharedInstance updateSession];
}

- (void)endSession
{
    if (CountlyCommon.sharedInstance.manualSessionHandling)
        [CountlyConnectionManager.sharedInstance endSession];
}

#pragma mark ---

- (void)onTimer:(NSTimer *)timer
{
    if (isSuspended)
        return;

    if (!CountlyCommon.sharedInstance.manualSessionHandling)
        [CountlyConnectionManager.sharedInstance updateSession];

    [CountlyConnectionManager.sharedInstance sendEvents];
}

- (void)suspend
{
    if (isSuspended)
        return;

    COUNTLY_LOG(@"Suspending...");

    isSuspended = YES;

    [CountlyConnectionManager.sharedInstance sendEvents];

    if (!CountlyCommon.sharedInstance.manualSessionHandling)
        [CountlyConnectionManager.sharedInstance endSession];

    [CountlyViewTracking.sharedInstance pauseView];

    [CountlyPersistency.sharedInstance saveToFile];
}

- (void)resume
{
#if TARGET_OS_WATCH
    //NOTE: skip first time to prevent double begin session because of applicationDidBecomeActive call on launch of watchOS apps
    static BOOL isFirstCall = YES;

    if (isFirstCall)
    {
        isFirstCall = NO;
        return;
    }
#endif

    if (!CountlyCommon.sharedInstance.manualSessionHandling)
        [CountlyConnectionManager.sharedInstance beginSession];

    [CountlyViewTracking.sharedInstance resumeView];

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

    if (!event)
    {
        COUNTLY_LOG(@"Event with key '%@' not started before!", key);
        return;
    }

    event.segmentation = segmentation;
    event.count = MAX(count, 1);
    event.sum = sum;
    event.duration = NSDate.date.timeIntervalSince1970 - event.timestamp;

    [CountlyPersistency.sharedInstance recordEvent:event];
}



#pragma mark - Countly PushNotifications
#if TARGET_OS_IOS

- (void)askForNotificationPermission
{
    UNAuthorizationOptions authorizationOptions = UNAuthorizationOptionBadge | UNAuthorizationOptionSound | UNAuthorizationOptionAlert;

    [CountlyPushNotifications.sharedInstance askForNotificationPermissionWithOptions:authorizationOptions completionHandler:nil];
}

- (void)askForNotificationPermissionWithOptions:(UNAuthorizationOptions)options completionHandler:(void (^)(BOOL granted, NSError * error))completionHandler;
{
    [CountlyPushNotifications.sharedInstance askForNotificationPermissionWithOptions:options completionHandler:completionHandler];

}

- (void)recordLocation:(CLLocationCoordinate2D)coordinate
{
    [CountlyConnectionManager.sharedInstance sendLocation:coordinate];
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
- (void)addExceptionForAutoViewTracking:(NSString *)exception
{
    [CountlyViewTracking.sharedInstance addExceptionForAutoViewTracking:exception];
}

- (void)removeExceptionForAutoViewTracking:(NSString *)exception
{
    [CountlyViewTracking.sharedInstance removeExceptionForAutoViewTracking:exception];
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

- (void)userLoggedIn:(NSString *)userID
{
    [self setNewDeviceID:userID onServer:YES];
}

- (void)userLoggedOut
{
    [self setNewDeviceID:nil onServer:NO];
}



#pragma mark - Countly StarRating
#if TARGET_OS_IOS

- (void)askForStarRating:(void(^)(NSInteger rating))completion
{
    [CountlyStarRating.sharedInstance showDialog:completion];
}
#endif

@end
