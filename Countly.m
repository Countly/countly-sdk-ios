// Countly.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#pragma mark - Core

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
    if (CountlyCommon.sharedInstance.hasStarted)
        return;

    CountlyCommon.sharedInstance.hasStarted = YES;
    CountlyCommon.sharedInstance.enableDebug = config.enableDebug;
    CountlyConsentManager.sharedInstance.requiresConsent = config.requiresConsent;

    if (!config.appKey.length || [config.appKey isEqualToString:@"YOUR_APP_KEY"])
        [NSException raise:@"CountlyAppKeyNotSetException" format:@"appKey property on CountlyConfig object is not set"];

    if (!config.host.length || [config.host isEqualToString:@"https://YOUR_COUNTLY_SERVER"])
        [NSException raise:@"CountlyHostNotSetException" format:@"host property on CountlyConfig object is not set"];

    COUNTLY_LOG(@"Initializing with %@ SDK v%@", kCountlySDKName, kCountlySDKVersion);

    if (!CountlyDeviceInfo.sharedInstance.deviceID || config.forceDeviceIDInitialization)
        [CountlyDeviceInfo.sharedInstance initializeDeviceID:config.deviceID];

    CountlyConnectionManager.sharedInstance.appKey = config.appKey;
    BOOL hostHasExtraSlash = [[config.host substringFromIndex:config.host.length - 1] isEqualToString:@"/"];
    CountlyConnectionManager.sharedInstance.host = hostHasExtraSlash ? [config.host substringToIndex:config.host.length - 1] : config.host;
    CountlyConnectionManager.sharedInstance.alwaysUsePOST = config.alwaysUsePOST;
    CountlyConnectionManager.sharedInstance.pinnedCertificates = config.pinnedCertificates;
    CountlyConnectionManager.sharedInstance.customHeaderFieldName = config.customHeaderFieldName;
    CountlyConnectionManager.sharedInstance.customHeaderFieldValue = config.customHeaderFieldValue;
    CountlyConnectionManager.sharedInstance.secretSalt = config.secretSalt;
    CountlyConnectionManager.sharedInstance.applyZeroIDFAFix = config.applyZeroIDFAFix;

    CountlyPersistency.sharedInstance.eventSendThreshold = config.eventSendThreshold;
    CountlyPersistency.sharedInstance.storedRequestsLimit = MAX(1, config.storedRequestsLimit);

    CountlyCommon.sharedInstance.manualSessionHandling = config.manualSessionHandling;
    CountlyCommon.sharedInstance.enableAppleWatch = config.enableAppleWatch;
    CountlyCommon.sharedInstance.enableAttribution = config.enableAttribution;

    if (!CountlyCommon.sharedInstance.manualSessionHandling)
        [CountlyConnectionManager.sharedInstance beginSession];

#if TARGET_OS_IOS
    CountlyStarRating.sharedInstance.message = config.starRatingMessage;
    CountlyStarRating.sharedInstance.sessionCount = config.starRatingSessionCount;
    CountlyStarRating.sharedInstance.disableAskingForEachAppVersion = config.starRatingDisableAskingForEachAppVersion;
    CountlyStarRating.sharedInstance.ratingCompletionForAutoAsk = config.starRatingCompletion;
    [CountlyStarRating.sharedInstance checkForAutoAsk];

    CountlyLocationManager.sharedInstance.location = CLLocationCoordinate2DIsValid(config.location) ? [NSString stringWithFormat:@"%f,%f", config.location.latitude, config.location.longitude] : nil;
    CountlyLocationManager.sharedInstance.city = config.city;
    CountlyLocationManager.sharedInstance.ISOCountryCode = config.ISOCountryCode;
    CountlyLocationManager.sharedInstance.IP = config.IP;
    [CountlyLocationManager.sharedInstance sendLocationInfo];

    CountlyCrashReporter.sharedInstance.crashSegmentation = config.crashSegmentation;
    CountlyCrashReporter.sharedInstance.crashLogLimit = MAX(1, config.crashLogLimit);
    if ([config.features containsObject:CLYCrashReporting])
    {
        CountlyCrashReporter.sharedInstance.isEnabledOnInitialConfig = YES;
        [CountlyCrashReporter.sharedInstance startCrashReporting];
    }
#endif

#if (TARGET_OS_IOS || TARGET_OS_OSX)
    if ([config.features containsObject:CLYPushNotifications])
    {
        CountlyPushNotifications.sharedInstance.isEnabledOnInitialConfig = YES;
        CountlyPushNotifications.sharedInstance.isTestDevice = config.isTestDevice;
        CountlyPushNotifications.sharedInstance.sendPushTokenAlways = config.sendPushTokenAlways;
        CountlyPushNotifications.sharedInstance.doNotShowAlertForNotifications = config.doNotShowAlertForNotifications;
        CountlyPushNotifications.sharedInstance.launchNotification = config.launchNotification;
        [CountlyPushNotifications.sharedInstance startPushNotifications];
    }
#endif

#if (TARGET_OS_IOS || TARGET_OS_TV)
    if ([config.features containsObject:CLYAutoViewTracking])
    {
        CountlyViewTracking.sharedInstance.isEnabledOnInitialConfig = YES;
        [CountlyViewTracking.sharedInstance startAutoViewTracking];
    }
#endif

//NOTE: Disable APM feature until server completely supports it
//    if ([config.features containsObject:CLYAPM])
//        [CountlyAPM.sharedInstance startAPM];

    timer = [NSTimer scheduledTimerWithTimeInterval:config.updateSessionPeriod target:self selector:@selector(onTimer:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];

    [CountlyCommon.sharedInstance startAppleWatchMatching];

    [CountlyCommon.sharedInstance startAttribution];

    CountlyRemoteConfig.sharedInstance.isEnabledOnInitialConfig = config.enableRemoteConfig;
    CountlyRemoteConfig.sharedInstance.remoteConfigCompletionHandler = config.remoteConfigCompletionHandler;
    [CountlyRemoteConfig.sharedInstance startRemoteConfig];

    [CountlyConnectionManager.sharedInstance proceedOnQueue];
}

- (void)setNewDeviceID:(NSString *)deviceID onServer:(BOOL)onServer
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return;

    if (!CountlyConsentManager.sharedInstance.hasAnyConsent)
        return;

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

    [CountlyRemoteConfig.sharedInstance clearCachedRemoteConfig];
    [CountlyRemoteConfig.sharedInstance startRemoteConfig];
}

- (void)setCustomHeaderFieldValue:(NSString *)customHeaderFieldValue
{
    CountlyConnectionManager.sharedInstance.customHeaderFieldValue = customHeaderFieldValue.copy;
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
    if (!CountlyCommon.sharedInstance.hasStarted)
        return;

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
    if (!CountlyCommon.sharedInstance.hasStarted)
        return;

#if TARGET_OS_WATCH
    //NOTE: Skip first time to prevent double begin session because of applicationDidBecomeActive call on launch of watchOS apps
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



#pragma mark - Consents
- (void)giveConsentForFeature:(NSString *)featureName
{
    if (!featureName.length)
        return;

    [CountlyConsentManager.sharedInstance giveConsentForFeatures:@[featureName]];
}

- (void)giveConsentForFeatures:(NSArray *)features
{
    [CountlyConsentManager.sharedInstance giveConsentForFeatures:features];
}

- (void)giveConsentForAllFeatures
{
    [CountlyConsentManager.sharedInstance giveConsentForAllFeatures];
}

- (void)cancelConsentForFeature:(NSString *)featureName
{
    if (!featureName.length)
        return;

    [CountlyConsentManager.sharedInstance cancelConsentForFeatures:@[featureName]];
}

- (void)cancelConsentForFeatures:(NSArray *)features
{
    [CountlyConsentManager.sharedInstance cancelConsentForFeatures:features];
}

- (void)cancelConsentForAllFeatures
{
    [CountlyConsentManager.sharedInstance cancelConsentForAllFeatures];
}

- (NSString *)deviceID
{
    return CountlyDeviceInfo.sharedInstance.deviceID.cly_URLEscaped;
}



#pragma mark - Events
- (void)recordEvent:(NSString *)key
{
    [self recordEvent:key segmentation:nil count:1 sum:0 duration:0];
}

- (void)recordEvent:(NSString *)key count:(NSUInteger)count
{
    [self recordEvent:key segmentation:nil count:count sum:0 duration:0];
}

- (void)recordEvent:(NSString *)key sum:(double)sum
{
    [self recordEvent:key segmentation:nil count:1 sum:sum duration:0];
}

- (void)recordEvent:(NSString *)key duration:(NSTimeInterval)duration
{
    [self recordEvent:key segmentation:nil count:1 sum:0 duration:duration];
}

- (void)recordEvent:(NSString *)key count:(NSUInteger)count sum:(double)sum
{
    [self recordEvent:key segmentation:nil count:count sum:sum duration:0];
}

- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation
{
    [self recordEvent:key segmentation:segmentation count:1 sum:0 duration:0];
}

- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(NSUInteger)count
{
    [self recordEvent:key segmentation:segmentation count:count sum:0 duration:0];
}

- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(NSUInteger)count sum:(double)sum
{
    [self recordEvent:key segmentation:segmentation count:count sum:sum duration:0];
}

- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(NSUInteger)count sum:(double)sum duration:(NSTimeInterval)duration
{
    if (!CountlyConsentManager.sharedInstance.consentForEvents)
        return;

    [self recordEvent:key segmentation:segmentation count:count sum:sum duration:duration timestamp:CountlyCommon.sharedInstance.uniqueTimestamp];
}

#pragma mark -

- (void)recordReservedEvent:(NSString *)key segmentation:(NSDictionary *)segmentation
{
    [self recordEvent:key segmentation:segmentation count:1 sum:0 duration:0 timestamp:CountlyCommon.sharedInstance.uniqueTimestamp];
}

- (void)recordReservedEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(NSUInteger)count sum:(double)sum duration:(NSTimeInterval)duration timestamp:(NSTimeInterval)timestamp
{
    [self recordEvent:key segmentation:segmentation count:count sum:sum duration:duration timestamp:timestamp];
}

#pragma mark -

- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(NSUInteger)count sum:(double)sum duration:(NSTimeInterval)duration timestamp:(NSTimeInterval)timestamp
{
    if (key.length == 0)
        return;

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
    if (!CountlyConsentManager.sharedInstance.consentForEvents)
        return;

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
    if (!CountlyConsentManager.sharedInstance.consentForEvents)
        return;

    CountlyEvent *event = [CountlyPersistency.sharedInstance timedEventForKey:key];

    if (!event)
    {
        COUNTLY_LOG(@"Event with key '%@' not started yet or cancelled/ended before!", key);
        return;
    }

    event.segmentation = segmentation;
    event.count = MAX(count, 1);
    event.sum = sum;
    event.duration = NSDate.date.timeIntervalSince1970 - event.timestamp;

    [CountlyPersistency.sharedInstance recordEvent:event];
}

- (void)cancelEvent:(NSString *)key
{
    if (!CountlyConsentManager.sharedInstance.consentForEvents)
        return;

    CountlyEvent *event = [CountlyPersistency.sharedInstance timedEventForKey:key];

    if (!event)
    {
        COUNTLY_LOG(@"Event with key '%@' not started yet or cancelled/ended before!", key);
        return;
    }

    COUNTLY_LOG(@"Event with key '%@' cancelled!", key);
}


#pragma mark - Push Notifications
#if (TARGET_OS_IOS || TARGET_OS_OSX)

- (void)askForNotificationPermission
{
    [CountlyPushNotifications.sharedInstance askForNotificationPermissionWithOptions:0 completionHandler:nil];
}

- (void)askForNotificationPermissionWithOptions:(UNAuthorizationOptions)options completionHandler:(void (^)(BOOL granted, NSError * error))completionHandler;
{
    [CountlyPushNotifications.sharedInstance askForNotificationPermissionWithOptions:options completionHandler:completionHandler];
}

- (void)recordActionForNotification:(NSDictionary *)userInfo clickedButtonIndex:(NSInteger)buttonIndex;
{
    [CountlyPushNotifications.sharedInstance recordActionForNotification:userInfo clickedButtonIndex:buttonIndex];
}

- (void)recordPushNotificationToken
{
    [CountlyPushNotifications.sharedInstance sendToken];
}

- (void)clearPushNotificationToken
{
    [CountlyPushNotifications.sharedInstance clearToken];
}
#endif



#pragma mark - Location

- (void)recordLocation:(CLLocationCoordinate2D)location
{
    [CountlyLocationManager.sharedInstance recordLocationInfo:location city:nil ISOCountryCode:nil andIP:nil];
}

- (void)recordCity:(NSString *)city andISOCountryCode:(NSString *)ISOCountryCode
{
    [CountlyLocationManager.sharedInstance recordLocationInfo:kCLLocationCoordinate2DInvalid city:city ISOCountryCode:ISOCountryCode andIP:nil];
}

- (void)recordIP:(NSString *)IP
{
    [CountlyLocationManager.sharedInstance recordLocationInfo:kCLLocationCoordinate2DInvalid city:nil ISOCountryCode:nil andIP:IP];
}

- (void)disableLocationInfo
{
    [CountlyLocationManager.sharedInstance disableLocationInfo];
}



#pragma mark - Crash Reporting

#if TARGET_OS_IOS
- (void)recordHandledException:(NSException *)exception
{
    [CountlyCrashReporter.sharedInstance recordException:exception withStackTrace:nil isFatal:NO];
}

- (void)recordHandledException:(NSException *)exception withStackTrace:(NSArray *)stackTrace
{
    [CountlyCrashReporter.sharedInstance recordException:exception withStackTrace:stackTrace isFatal:NO];
}

- (void)recordUnhandledException:(NSException *)exception withStackTrace:(NSArray * _Nullable)stackTrace
{
    [CountlyCrashReporter.sharedInstance recordException:exception withStackTrace:stackTrace isFatal:YES];
}

- (void)recordCrashLog:(NSString *)log
{
    [CountlyCrashReporter.sharedInstance log:log];
}

- (void)crashLog:(NSString *)format, ...
{

}

#endif



#pragma mark - APM

- (void)addExceptionForAPM:(NSString *)exceptionURL
{
    [CountlyAPM.sharedInstance addExceptionForAPM:exceptionURL];
}

- (void)removeExceptionForAPM:(NSString *)exceptionURL
{
    [CountlyAPM.sharedInstance removeExceptionForAPM:exceptionURL];
}



#pragma mark - View Tracking

- (void)recordView:(NSString *)viewName;
{
    [CountlyViewTracking.sharedInstance startView:viewName];
}

- (void)reportView:(NSString *)viewName
{

}

#if TARGET_OS_IOS
- (void)addExceptionForAutoViewTracking:(NSString *)exception
{
    [CountlyViewTracking.sharedInstance addExceptionForAutoViewTracking:exception.copy];
}

- (void)removeExceptionForAutoViewTracking:(NSString *)exception
{
    [CountlyViewTracking.sharedInstance removeExceptionForAutoViewTracking:exception.copy];
}

- (void)setIsAutoViewTrackingActive:(BOOL)isAutoViewTrackingActive
{
    CountlyViewTracking.sharedInstance.isAutoViewTrackingActive = isAutoViewTrackingActive;
}

- (BOOL)isAutoViewTrackingActive
{
    return CountlyViewTracking.sharedInstance.isAutoViewTrackingActive;
}
#endif



#pragma mark - User Details

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



#pragma mark - Star Rating
#if TARGET_OS_IOS

- (void)askForStarRating:(void(^)(NSInteger rating))completion
{
    [CountlyStarRating.sharedInstance showDialog:completion];
}

- (void)presentFeedbackWidgetWithID:(NSString *)widgetID completionHandler:(void (^)(NSError * error))completionHandler
{
    [CountlyStarRating.sharedInstance checkFeedbackWidgetWithID:widgetID completionHandler:completionHandler];
}

#endif



#pragma mark - Remote Config

- (id)remoteConfigValueForKey:(NSString *)key
{
    return [CountlyRemoteConfig.sharedInstance remoteConfigValueForKey:key];
}

- (void)updateRemoteConfigWithCompletionHandler:(void (^)(NSError * error))completionHandler
{
    [CountlyRemoteConfig.sharedInstance updateRemoteConfigForForKeys:nil omitKeys:nil completionHandler:completionHandler];
}

- (void)updateRemoteConfigOnlyForKeys:(NSArray *)keys completionHandler:(void (^)(NSError * error))completionHandler
{
    [CountlyRemoteConfig.sharedInstance updateRemoteConfigForForKeys:keys omitKeys:nil completionHandler:completionHandler];
}

- (void)updateRemoteConfigExceptForKeys:(NSArray *)omitKeys completionHandler:(void (^)(NSError * error))completionHandler
{
    [CountlyRemoteConfig.sharedInstance updateRemoteConfigForForKeys:nil omitKeys:omitKeys completionHandler:completionHandler];
}


@end
