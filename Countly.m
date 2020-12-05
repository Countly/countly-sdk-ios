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

long long appLoadStartTime;

@implementation Countly

+ (void)load
{
    [super load];

    appLoadStartTime = floor(NSDate.date.timeIntervalSince1970 * 1000);
}

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
                                               selector:@selector(applicationDidEnterBackground:)
                                                   name:UIApplicationDidEnterBackgroundNotification
                                                 object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(applicationWillEnterForeground:)
                                                   name:UIApplicationWillEnterForegroundNotification
                                                 object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(applicationWillTerminate:)
                                                   name:UIApplicationWillTerminateNotification
                                                 object:nil];
#elif (TARGET_OS_OSX)
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(applicationWillTerminate:)
                                                   name:NSApplicationWillTerminateNotification
                                                 object:nil];
#endif
    }

    return self;
}

#pragma mark ---

- (void)startWithConfig:(CountlyConfig *)config
{
    if (CountlyCommon.sharedInstance.hasStarted_)
        return;

    CountlyCommon.sharedInstance.hasStarted = YES;
    CountlyCommon.sharedInstance.enableDebug = config.enableDebug;
    CountlyCommon.sharedInstance.loggerDelegate = config.loggerDelegate;
    CountlyConsentManager.sharedInstance.requiresConsent = config.requiresConsent;

    if (!config.appKey.length || [config.appKey isEqualToString:@"YOUR_APP_KEY"])
        [NSException raise:@"CountlyAppKeyNotSetException" format:@"appKey property on CountlyConfig object is not set"];

    if (!config.host.length || [config.host isEqualToString:@"https://YOUR_COUNTLY_SERVER"])
        [NSException raise:@"CountlyHostNotSetException" format:@"host property on CountlyConfig object is not set"];

    COUNTLY_LOG(@"Initializing with %@ SDK v%@", CountlyCommon.sharedInstance.SDKName, CountlyCommon.sharedInstance.SDKVersion);

    if (!CountlyDeviceInfo.sharedInstance.deviceID || config.resetStoredDeviceID)
    {
        [self storeCustomDeviceIDState:config.deviceID];

        [CountlyDeviceInfo.sharedInstance initializeDeviceID:config.deviceID];
    }

    CountlyConnectionManager.sharedInstance.appKey = config.appKey;
    CountlyConnectionManager.sharedInstance.host = [config.host hasSuffix:@"/"] ? [config.host substringToIndex:config.host.length - 1] : config.host;
    CountlyConnectionManager.sharedInstance.alwaysUsePOST = config.alwaysUsePOST;
    CountlyConnectionManager.sharedInstance.pinnedCertificates = config.pinnedCertificates;
    CountlyConnectionManager.sharedInstance.customHeaderFieldName = config.customHeaderFieldName;
    CountlyConnectionManager.sharedInstance.customHeaderFieldValue = config.customHeaderFieldValue;
    CountlyConnectionManager.sharedInstance.secretSalt = config.secretSalt;
    CountlyConnectionManager.sharedInstance.URLSessionConfiguration = config.URLSessionConfiguration;

    CountlyPersistency.sharedInstance.eventSendThreshold = config.eventSendThreshold;
    CountlyPersistency.sharedInstance.storedRequestsLimit = MAX(1, config.storedRequestsLimit);

    CountlyCommon.sharedInstance.manualSessionHandling = config.manualSessionHandling;

    CountlyCommon.sharedInstance.enableAppleWatch = config.enableAppleWatch;

    CountlyCommon.sharedInstance.attributionID = config.attributionID;

    CountlyDeviceInfo.sharedInstance.customMetrics = config.customMetrics;

#if (TARGET_OS_IOS)
    CountlyFeedbacks.sharedInstance.message = config.starRatingMessage;
    CountlyFeedbacks.sharedInstance.sessionCount = config.starRatingSessionCount;
    CountlyFeedbacks.sharedInstance.disableAskingForEachAppVersion = config.starRatingDisableAskingForEachAppVersion;
    CountlyFeedbacks.sharedInstance.ratingCompletionForAutoAsk = config.starRatingCompletion;
    [CountlyFeedbacks.sharedInstance checkForStarRatingAutoAsk];

    [CountlyLocationManager.sharedInstance updateLocation:config.location city:config.city ISOCountryCode:config.ISOCountryCode IP:config.IP];
#endif

    if (!CountlyCommon.sharedInstance.manualSessionHandling)
        [CountlyConnectionManager.sharedInstance beginSession];

    //NOTE: If there is no consent for sessions, location info and attribution should be sent separately, as they cannot be sent with begin_session request.
    if (!CountlyConsentManager.sharedInstance.consentForSessions)
    {
        [CountlyLocationManager.sharedInstance sendLocationInfo];
        [CountlyConnectionManager.sharedInstance sendAttribution];
    }

#if (TARGET_OS_IOS || TARGET_OS_OSX)
#ifndef COUNTLY_EXCLUDE_PUSHNOTIFICATIONS
    if ([config.features containsObject:CLYPushNotifications])
    {
        CountlyPushNotifications.sharedInstance.isEnabledOnInitialConfig = YES;
        CountlyPushNotifications.sharedInstance.pushTestMode = config.pushTestMode;
        CountlyPushNotifications.sharedInstance.sendPushTokenAlways = config.sendPushTokenAlways;
        CountlyPushNotifications.sharedInstance.doNotShowAlertForNotifications = config.doNotShowAlertForNotifications;
        CountlyPushNotifications.sharedInstance.launchNotification = config.launchNotification;
        [CountlyPushNotifications.sharedInstance startPushNotifications];
    }
#endif
#endif

    CountlyCrashReporter.sharedInstance.crashSegmentation = config.crashSegmentation;
    CountlyCrashReporter.sharedInstance.crashLogLimit = MAX(1, config.crashLogLimit);
    CountlyCrashReporter.sharedInstance.crashFilter = config.crashFilter;
    CountlyCrashReporter.sharedInstance.shouldUsePLCrashReporter = config.shouldUsePLCrashReporter;
    CountlyCrashReporter.sharedInstance.shouldUseMachSignalHandler = config.shouldUseMachSignalHandler;
    CountlyCrashReporter.sharedInstance.crashOccuredOnPreviousSessionCallback = config.crashOccuredOnPreviousSessionCallback;
    CountlyCrashReporter.sharedInstance.shouldSendCrashReportCallback = config.shouldSendCrashReportCallback;
    if ([config.features containsObject:CLYCrashReporting])
    {
        CountlyCrashReporter.sharedInstance.isEnabledOnInitialConfig = YES;
        [CountlyCrashReporter.sharedInstance startCrashReporting];
    }

#if (TARGET_OS_IOS || TARGET_OS_TV)
    if ([config.features containsObject:CLYAutoViewTracking])
    {
        CountlyViewTracking.sharedInstance.isEnabledOnInitialConfig = YES;
        [CountlyViewTracking.sharedInstance startAutoViewTracking];
    }
#endif

    timer = [NSTimer timerWithTimeInterval:config.updateSessionPeriod target:self selector:@selector(onTimer:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];

    [CountlyCommon.sharedInstance startAppleWatchMatching];

    CountlyRemoteConfig.sharedInstance.isEnabledOnInitialConfig = config.enableRemoteConfig;
    CountlyRemoteConfig.sharedInstance.remoteConfigCompletionHandler = config.remoteConfigCompletionHandler;
    [CountlyRemoteConfig.sharedInstance startRemoteConfig];
    
    CountlyPerformanceMonitoring.sharedInstance.isEnabledOnInitialConfig = config.enablePerformanceMonitoring;
    [CountlyPerformanceMonitoring.sharedInstance startPerformanceMonitoring];

    [CountlyCommon.sharedInstance observeDeviceOrientationChanges];

    [CountlyConnectionManager.sharedInstance proceedOnQueue];

    if (config.consents)
        [self giveConsentForFeatures:config.consents];
}

- (void)setNewAppKey:(NSString *)newAppKey
{
    if (!newAppKey.length)
        return;

    [self suspend];

    [CountlyPerformanceMonitoring.sharedInstance clearAllCustomTraces];

    CountlyConnectionManager.sharedInstance.appKey = newAppKey;

    [self resume];
}

- (void)setCustomHeaderFieldValue:(NSString *)customHeaderFieldValue
{
    CountlyConnectionManager.sharedInstance.customHeaderFieldValue = customHeaderFieldValue.copy;
    [CountlyConnectionManager.sharedInstance proceedOnQueue];
}

- (void)flushQueues
{
    [CountlyPersistency.sharedInstance flushEvents];
    [CountlyPersistency.sharedInstance flushQueue];
}

- (void)replaceAllAppKeysInQueueWithCurrentAppKey
{
    [CountlyPersistency.sharedInstance replaceAllAppKeysInQueueWithCurrentAppKey];
}

- (void)removeDifferentAppKeysFromQueue
{
    [CountlyPersistency.sharedInstance removeDifferentAppKeysFromQueue];
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

#if (TARGET_OS_WATCH)
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

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    COUNTLY_LOG(@"App did enter background.");
    [self suspend];
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    COUNTLY_LOG(@"App will enter foreground.");
    [self resume];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    COUNTLY_LOG(@"App will terminate.");

    CountlyConnectionManager.sharedInstance.isTerminating = YES;

    [CountlyViewTracking.sharedInstance endView];

    [CountlyConnectionManager.sharedInstance sendEvents];

    [CountlyPerformanceMonitoring.sharedInstance endBackgroundTrace];

    [CountlyPersistency.sharedInstance saveToFileSync];
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



#pragma mark - Device ID

- (NSString *)deviceID
{
    return CountlyDeviceInfo.sharedInstance.deviceID.cly_URLEscaped;
}

- (CLYDeviceIDType)deviceIDType
{
    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
        return CLYDeviceIDTypeTemporary;

    if ([CountlyPersistency.sharedInstance retrieveIsCustomDeviceID])
        return CLYDeviceIDTypeCustom;

#if (TARGET_OS_IOS || TARGET_OS_TV)
    return CLYDeviceIDTypeIDFV;
#else
    return CLYDeviceIDTypeNSUUID;
#endif
}

- (void)setNewDeviceID:(NSString *)deviceID onServer:(BOOL)onServer
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return;

    if (!CountlyConsentManager.sharedInstance.hasAnyConsent)
        return;

    [self storeCustomDeviceIDState:deviceID];

    deviceID = [CountlyDeviceInfo.sharedInstance ensafeDeviceID:deviceID];

    if ([deviceID isEqualToString:CountlyDeviceInfo.sharedInstance.deviceID])
    {
        COUNTLY_LOG(@"Attempted to set the same device ID again. So, setting new device ID is aborted.");
        return;
    }

    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
    {
        COUNTLY_LOG(@"Going out of CLYTemporaryDeviceID mode and switching back to normal mode.");

        [CountlyDeviceInfo.sharedInstance initializeDeviceID:deviceID];

        [CountlyPersistency.sharedInstance replaceAllTemporaryDeviceIDsInQueueWithDeviceID:deviceID];

        [CountlyConnectionManager.sharedInstance proceedOnQueue];

        [CountlyRemoteConfig.sharedInstance startRemoteConfig];

        return;
    }

    if ([deviceID isEqualToString:CLYTemporaryDeviceID] && onServer)
    {
        COUNTLY_LOG(@"Attempted to set device ID as CLYTemporaryDeviceID with onServer option. So, onServer value is overridden as NO.");
        onServer = NO;
    }

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

- (void)storeCustomDeviceIDState:(NSString *)deviceID
{
    BOOL isCustomDeviceID = deviceID.length && ![deviceID isEqualToString:CLYTemporaryDeviceID];
    [CountlyPersistency.sharedInstance storeIsCustomDeviceID:isCustomDeviceID];
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
#ifndef COUNTLY_EXCLUDE_PUSHNOTIFICATIONS

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
#endif



#pragma mark - Location

- (void)recordLocation:(CLLocationCoordinate2D)location city:(NSString * _Nullable)city ISOCountryCode:(NSString * _Nullable)ISOCountryCode IP:(NSString * _Nullable)IP
{
    [CountlyLocationManager.sharedInstance recordLocation:location city:city ISOCountryCode:ISOCountryCode IP:IP];
}

- (void)recordLocation:(CLLocationCoordinate2D)location
{
    COUNTLY_LOG(@"recordLocation: method is deprecated. Please use recordLocation:city:countryCode:IP: method instead.");

    [CountlyLocationManager.sharedInstance recordLocation:location city:nil ISOCountryCode:nil IP:nil];
}

- (void)recordCity:(NSString *)city andISOCountryCode:(NSString *)ISOCountryCode
{
    COUNTLY_LOG(@"recordCity:andISOCountryCode: method is deprecated. Please use recordLocation:city:countryCode:IP: method instead.");

    if (!city.length && !ISOCountryCode.length)
        return;

    [CountlyLocationManager.sharedInstance recordLocation:kCLLocationCoordinate2DInvalid city:city ISOCountryCode:ISOCountryCode IP:nil];
}

- (void)recordIP:(NSString *)IP
{
    COUNTLY_LOG(@"recordIP: method is deprecated. Please use recordLocation:city:countryCode:IP: method instead.");

    if (!IP.length)
        return;

    [CountlyLocationManager.sharedInstance recordLocation:kCLLocationCoordinate2DInvalid city:nil ISOCountryCode:nil IP:IP];
}

- (void)disableLocationInfo
{
    [CountlyLocationManager.sharedInstance disableLocationInfo];
}



#pragma mark - Crash Reporting

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



#pragma mark - View Tracking

- (void)recordView:(NSString *)viewName;
{
    [CountlyViewTracking.sharedInstance startView:viewName customSegmentation:nil];
}

- (void)recordView:(NSString *)viewName segmentation:(NSDictionary *)segmentation
{
    [CountlyViewTracking.sharedInstance startView:viewName customSegmentation:segmentation];
}

#if (TARGET_OS_IOS)
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
    [self setNewDeviceID:CLYDefaultDeviceID onServer:NO];
}



#pragma mark - Star Rating
#if (TARGET_OS_IOS)

- (void)askForStarRating:(void(^)(NSInteger rating))completion
{
    [CountlyFeedbacks.sharedInstance showDialog:completion];
}

- (void)presentFeedbackWidgetWithID:(NSString *)widgetID completionHandler:(void (^)(NSError * error))completionHandler
{
    [CountlyFeedbacks.sharedInstance checkFeedbackWidgetWithID:widgetID completionHandler:completionHandler];
}

- (void)getFeedbackWidgets:(void (^)(NSArray <CountlyFeedbackWidget *> *feedbackWidgets, NSError * error))completionHandler
{
    [CountlyFeedbacks.sharedInstance getFeedbackWidgets:completionHandler];
}

#endif



#pragma mark - Attribution

- (void)recordAttributionID:(NSString *)attributionID
{
    if (!CountlyConsentManager.sharedInstance.consentForAttribution)
        return;

    CountlyCommon.sharedInstance.attributionID = attributionID;

    [CountlyConnectionManager.sharedInstance sendAttribution];
}



#pragma mark - Remote Config

- (id)remoteConfigValueForKey:(NSString *)key
{
    return [CountlyRemoteConfig.sharedInstance remoteConfigValueForKey:key];
}

- (void)updateRemoteConfigWithCompletionHandler:(void (^)(NSError * error))completionHandler
{
    [CountlyRemoteConfig.sharedInstance updateRemoteConfigForKeys:nil omitKeys:nil completionHandler:completionHandler];
}

- (void)updateRemoteConfigOnlyForKeys:(NSArray *)keys completionHandler:(void (^)(NSError * error))completionHandler
{
    [CountlyRemoteConfig.sharedInstance updateRemoteConfigForKeys:keys omitKeys:nil completionHandler:completionHandler];
}

- (void)updateRemoteConfigExceptForKeys:(NSArray *)omitKeys completionHandler:(void (^)(NSError * error))completionHandler
{
    [CountlyRemoteConfig.sharedInstance updateRemoteConfigForKeys:nil omitKeys:omitKeys completionHandler:completionHandler];
}



#pragma mark - Performance Monitoring

- (void)recordNetworkTrace:(NSString *)traceName requestPayloadSize:(NSInteger)requestPayloadSize responsePayloadSize:(NSInteger)responsePayloadSize responseStatusCode:(NSInteger)responseStatusCode startTime:(long long)startTime endTime:(long long)endTime
{
    [CountlyPerformanceMonitoring.sharedInstance recordNetworkTrace:traceName requestPayloadSize:requestPayloadSize responsePayloadSize:responsePayloadSize responseStatusCode:responseStatusCode startTime:startTime endTime:endTime];
}

- (void)startCustomTrace:(NSString *)traceName
{
    [CountlyPerformanceMonitoring.sharedInstance startCustomTrace:traceName];
}

- (void)endCustomTrace:(NSString *)traceName metrics:(NSDictionary * _Nullable)metrics
{
    [CountlyPerformanceMonitoring.sharedInstance endCustomTrace:traceName metrics:metrics];
}

- (void)cancelCustomTrace:(NSString *)traceName
{
    [CountlyPerformanceMonitoring.sharedInstance cancelCustomTrace:traceName];
}

- (void)clearAllCustomTraces
{
    [CountlyPerformanceMonitoring.sharedInstance clearAllCustomTraces];
}

- (void)appLoadingFinished
{
    long long appLoadEndTime = floor(NSDate.date.timeIntervalSince1970 * 1000);

    [CountlyPerformanceMonitoring.sharedInstance recordAppStartDurationTraceWithStartTime:appLoadStartTime endTime:appLoadEndTime];
}

@end
