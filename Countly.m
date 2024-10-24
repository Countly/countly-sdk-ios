// Countly.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface Countly ()
{
    NSTimer* timer;
    BOOL isSuspended;
}
@end

long long appLoadStartTime;
// It holds the event id of previous recorded custom event.
NSString* previousEventID;
// It holds the event name of previous recorded custom event.
NSString* previousEventName;
@implementation Countly

#pragma mark - Core

+ (void)load
{
    [super load];
    
    appLoadStartTime = floor(NSDate.date.timeIntervalSince1970 * 1000);
}

static Countly *s_sharedCountly = nil;
static dispatch_once_t onceToken;

+ (instancetype)sharedInstance
{
    dispatch_once(&onceToken, ^{s_sharedCountly = self.new;});
    return s_sharedCountly;
}

- (void)resetInstance {
    CLY_LOG_I(@"%s", __FUNCTION__);
    onceToken = 0;
    s_sharedCountly = nil;
}

- (instancetype)init
{
    if (self = [super init])
    {
#if (TARGET_OS_IOS || TARGET_OS_VISION  || TARGET_OS_TV )
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
        
        [NSNotificationCenter.defaultCenter addObserver:self 
                                               selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification
                                                 object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self 
                                               selector:@selector(applicationWillResignActive:) name:UIApplicationWillResignActiveNotification
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

- (void)startWithConfig:(CountlyConfig *)config
{
    if (CountlyCommon.sharedInstance.hasStarted_)
        return;
    
    CountlyCommon.sharedInstance.hasStarted = YES;
    CountlyCommon.sharedInstance.enableDebug = config.enableDebug;
    CountlyCommon.sharedInstance.shouldIgnoreTrustCheck = config.shouldIgnoreTrustCheck;
    CountlyCommon.sharedInstance.loggerDelegate = config.loggerDelegate;
    CountlyCommon.sharedInstance.internalLogLevel = config.internalLogLevel;
    
    config = [self checkAndFixInternalLimitsConfig:config];
    
    CountlyCommon.sharedInstance.maxKeyLength = config.sdkInternalLimits.getMaxKeyLength;
    CountlyCommon.sharedInstance.maxValueLength = config.sdkInternalLimits.getMaxValueSize;
    CountlyCommon.sharedInstance.maxSegmentationValues = config.sdkInternalLimits.getMaxSegmentationValues;
    
    // For backward compatibility, deprecated values are only set incase new values are not provided using sdkInternalLimits interface
    if(CountlyCommon.sharedInstance.maxKeyLength == kCountlyMaxKeyLength && config.maxKeyLength != kCountlyMaxKeyLength) {
        CountlyCommon.sharedInstance.maxKeyLength = config.maxKeyLength;
        CLY_LOG_I(@"%s provided 'maxKeyLength' override:[ %lu ]", __FUNCTION__, (unsigned long)config.maxKeyLength);
    }
    if(CountlyCommon.sharedInstance.maxValueLength == kCountlyMaxValueSize && config.maxValueLength != kCountlyMaxValueSize) {
        CountlyCommon.sharedInstance.maxValueLength = config.maxValueLength;
        CLY_LOG_I(@"%s provided 'maxValueLength' override:[ %lu ]", __FUNCTION__, (unsigned long)config.maxValueLength);
    }
    if(CountlyCommon.sharedInstance.maxSegmentationValues == kCountlyMaxSegmentationValues && config.maxSegmentationValues != kCountlyMaxSegmentationValues) {
        CountlyCommon.sharedInstance.maxSegmentationValues = config.maxSegmentationValues;
        CLY_LOG_I(@"%s provided 'maxSegmentationValues' override:[ %lu ]", __FUNCTION__, (unsigned long)config.maxSegmentationValues);
    }
    
    CountlyConsentManager.sharedInstance.requiresConsent = config.requiresConsent;
    
    if (!config.appKey.length || [config.appKey isEqualToString:@"YOUR_APP_KEY"])
        [NSException raise:@"CountlyAppKeyNotSetException" format:@"appKey property on CountlyConfig object is not set"];
    
    if (!config.host.length || [config.host isEqualToString:@"https://YOUR_COUNTLY_SERVER"])
        [NSException raise:@"CountlyHostNotSetException" format:@"host property on CountlyConfig object is not set"];
    
    if ([CountlyCommon.sharedInstance.SDKName isEqualToString:kCountlySDKName] && [CountlyCommon.sharedInstance.SDKVersion isEqualToString:kCountlySDKVersion])
    {
        CLY_LOG_I(@"Initializing with %@ SDK v%@ on %@ with %@ %@",
                  CountlyCommon.sharedInstance.SDKName,
                  CountlyCommon.sharedInstance.SDKVersion,
                  CountlyDeviceInfo.device,
                  CountlyDeviceInfo.osName,
                  CountlyDeviceInfo.osVersion);
    }
    else {
        CLY_LOG_I(@"Initializing with %@ SDK v%@ on %@ with %@ %@ default SDK name %@ default SDK version %@",
                  CountlyCommon.sharedInstance.SDKName,
                  CountlyCommon.sharedInstance.SDKVersion,
                  CountlyDeviceInfo.device,
                  CountlyDeviceInfo.osName,
                  CountlyDeviceInfo.osVersion,
                  kCountlySDKName,
                  kCountlySDKVersion);
    }
    
    if (!CountlyDeviceInfo.sharedInstance.deviceID || config.resetStoredDeviceID)
    {
        [self storeCustomDeviceIDState:config.deviceID];
        
        [CountlyDeviceInfo.sharedInstance initializeDeviceID:config.deviceID];
    }
    
    CountlyConnectionManager.sharedInstance.appKey = config.appKey;
    CountlyConnectionManager.sharedInstance.host = config.host;
    CountlyConnectionManager.sharedInstance.alwaysUsePOST = config.alwaysUsePOST;
    CountlyConnectionManager.sharedInstance.pinnedCertificates = config.pinnedCertificates;
    CountlyConnectionManager.sharedInstance.secretSalt = config.secretSalt;
    CountlyConnectionManager.sharedInstance.URLSessionConfiguration = config.URLSessionConfiguration;
    
    CountlyPersistency.sharedInstance.eventSendThreshold = config.eventSendThreshold;
    CountlyPersistency.sharedInstance.requestDropAgeHours = config.requestDropAgeHours;
    CountlyPersistency.sharedInstance.storedRequestsLimit = MAX(1, config.storedRequestsLimit);
    
    CountlyCommon.sharedInstance.manualSessionHandling = config.manualSessionHandling;
    CountlyCommon.sharedInstance.enableManualSessionControlHybridMode = config.enableManualSessionControlHybridMode;
    
    CountlyCommon.sharedInstance.attributionID = config.attributionID;
    
    NSDictionary* customMetricsTruncated = [config.customMetrics cly_truncated:@"Custom metric"];
    CountlyDeviceInfo.sharedInstance.customMetrics = [customMetricsTruncated cly_limited:@"Custom metric"];
    
    [Countly.user save];
    
    CountlyCommon.sharedInstance.enableServerConfiguration = config.enableServerConfiguration;
    
    // Fetch server configs if 'enableServerConfiguration' is true.
    if (config.enableServerConfiguration)
    {
        [CountlyServerConfig.sharedInstance fetchServerConfig];
    }
    
#if (TARGET_OS_IOS)
    CountlyFeedbacksInternal.sharedInstance.message = config.starRatingMessage;
    CountlyFeedbacksInternal.sharedInstance.sessionCount = config.starRatingSessionCount;
    CountlyFeedbacksInternal.sharedInstance.disableAskingForEachAppVersion = config.starRatingDisableAskingForEachAppVersion;
    CountlyFeedbacksInternal.sharedInstance.ratingCompletionForAutoAsk = config.starRatingCompletion;
    [CountlyFeedbacksInternal.sharedInstance checkForStarRatingAutoAsk];
#endif
    
    if(config.disableLocation)
    {
        [CountlyLocationManager.sharedInstance disableLocation];
    }
    else
    {
        [CountlyLocationManager.sharedInstance updateLocation:config.location city:config.city ISOCountryCode:config.ISOCountryCode IP:config.IP];
    }
    
    if (!CountlyCommon.sharedInstance.manualSessionHandling)
        [CountlyConnectionManager.sharedInstance beginSession];
    else
        [CountlyCommon.sharedInstance recordOrientation];
    
    //NOTE: If there is no consent for sessions, location info and attribution should be sent separately, as they cannot be sent with begin_session request.

#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_OSX )
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
    
    if(config.crashes.crashFilterCallback) {
        [CountlyCrashReporter.sharedInstance setCrashFilterCallback:config.crashes.crashFilterCallback];
    }
    
    CountlyCrashReporter.sharedInstance.crashSegmentation = config.crashSegmentation;
    CountlyCrashReporter.sharedInstance.crashLogLimit = config.sdkInternalLimits.getMaxBreadcrumbCount;
    // For backward compatibility, deprecated values are only set incase new values are not provided using sdkInternalLimits interface
    if(CountlyCrashReporter.sharedInstance.crashLogLimit == kCountlyMaxBreadcrumbCount && config.crashLogLimit != kCountlyMaxBreadcrumbCount) {
        CountlyCrashReporter.sharedInstance.crashLogLimit = MAX(1, config.crashLogLimit);
        CLY_LOG_W(@"%s provided 'maxBreadcrumbCount' override:[ %lu ]", __FUNCTION__, (unsigned long)config.crashLogLimit);
    }
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

#if (TARGET_OS_IOS || TARGET_OS_TV )
    if (config.enableAutomaticViewTracking || [config.features containsObject:CLYAutoViewTracking])
    {
        // Print deprecation flag for feature
        CountlyViewTrackingInternal.sharedInstance.isEnabledOnInitialConfig = YES;
        [CountlyViewTrackingInternal.sharedInstance startAutoViewTracking];
    }
    if (config.automaticViewTrackingExclusionList) {
        [CountlyViewTrackingInternal.sharedInstance addAutoViewTrackingExclutionList:config.automaticViewTrackingExclusionList];
    }
#endif
    
    if(config.experimental.enablePreviousNameRecording) {
        CountlyViewTrackingInternal.sharedInstance.enablePreviousNameRecording = YES;
    }
    if(config.experimental.enableVisibiltyTracking) {
        CountlyCommon.sharedInstance.enableVisibiltyTracking = YES;
    }
    if (config.globalViewSegmentation) {
        [CountlyViewTrackingInternal.sharedInstance setGlobalViewSegmentation:config.globalViewSegmentation];
    }
    timer = [NSTimer timerWithTimeInterval:config.updateSessionPeriod target:self selector:@selector(onTimer:) userInfo:nil repeats:YES];
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
    
    CountlyRemoteConfigInternal.sharedInstance.isRCAutomaticTriggersEnabled = config.enableRemoteConfigAutomaticTriggers || config.enableRemoteConfig;
    CountlyRemoteConfigInternal.sharedInstance.isRCValueCachingEnabled = config.enableRemoteConfigValueCaching;
    CountlyRemoteConfigInternal.sharedInstance.remoteConfigCompletionHandler = config.remoteConfigCompletionHandler;
    if (config.getRemoteConfigGlobalCallbacks) {
        CountlyRemoteConfigInternal.sharedInstance.remoteConfigGlobalCallbacks = config.getRemoteConfigGlobalCallbacks;
    }
    if (config.enrollABOnRCDownload) {
        CountlyRemoteConfigInternal.sharedInstance.enrollABOnRCDownload = config.enrollABOnRCDownload;
    }
    [CountlyRemoteConfigInternal.sharedInstance downloadRemoteConfigAutomatically];
    if (config.apm.getAppStartTimestampOverride) {
        appLoadStartTime = config.apm.getAppStartTimestampOverride;
    }
#if (TARGET_OS_IOS)
    if(config.content.getGlobalContentCallback) {
        CountlyContentBuilderInternal.sharedInstance.contentCallback = config.content.getGlobalContentCallback;
    }
#endif
    
    [CountlyPerformanceMonitoring.sharedInstance startWithConfig:config.apm];
    
    CountlyCommon.sharedInstance.enableOrientationTracking = config.enableOrientationTracking;
    [CountlyCommon.sharedInstance observeDeviceOrientationChanges];
    
    [CountlyConnectionManager.sharedInstance proceedOnQueue];
    
    //TODO: Should move at the top after checking the the edge cases of current implementation
    if (config.enableAllConsents)
        [self giveAllConsents];
    else if (config.consents)
        [self giveConsentForFeatures:config.consents];
    else if (config.requiresConsent)
        [CountlyConsentManager.sharedInstance sendConsents];
    
    if (!CountlyConsentManager.sharedInstance.consentForSessions)
    {
        //Send an empty location if location is disabled or location consent is not given, without checking for location consent.
        if (!CountlyConsentManager.sharedInstance.consentForLocation || CountlyLocationManager.sharedInstance.isLocationInfoDisabled)
        {
            [CountlyConnectionManager.sharedInstance sendLocationInfo];
        }
        else
        {
            [CountlyLocationManager.sharedInstance sendLocationInfo];
        }
        [CountlyConnectionManager.sharedInstance sendAttribution];
    }
    
    
    if (config.campaignType && config.campaignData)
        [self recordDirectAttributionWithCampaignType:config.campaignType andCampaignData:config.campaignData];
    
    if (config.indirectAttribution)
        [self recordIndirectAttribution:config.indirectAttribution];
}

- (CountlyConfig *) checkAndFixInternalLimitsConfig:(CountlyConfig *)config
{
    if (config.sdkInternalLimits.getMaxKeyLength == 0) {
        [config.sdkInternalLimits setMaxKeyLength:kCountlyMaxKeyLength];
        CLY_LOG_W(@"%s Ignoring provided value of %lu for 'maxKeyLength' because it's less than 1", __FUNCTION__, (unsigned long)config.sdkInternalLimits.getMaxKeyLength);
    }
    else if(config.sdkInternalLimits.getMaxKeyLength != kCountlyMaxKeyLength)
    {
        CLY_LOG_I(@"%s provided 'maxKeyLength' override:[ %lu ]", __FUNCTION__, (unsigned long)config.sdkInternalLimits.getMaxKeyLength);
    }
    
    if (config.sdkInternalLimits.getMaxValueSize == 0) {
        [config.sdkInternalLimits setMaxValueSize:kCountlyMaxValueSize];
        CLY_LOG_W(@"%s Ignoring provided value of %lu for 'maxValueSize' because it's less than 1", __FUNCTION__, (unsigned long)config.sdkInternalLimits.getMaxValueSize);
    }
    else if(config.sdkInternalLimits.getMaxValueSize != kCountlyMaxValueSize)
    {
        CLY_LOG_I(@"%s provided 'maxValueSize' override:[ %lu ]", __FUNCTION__, (unsigned long)config.sdkInternalLimits.getMaxValueSize);
    }
    
    if (config.sdkInternalLimits.getMaxSegmentationValues == 0) {
        [config.sdkInternalLimits setMaxSegmentationValues:kCountlyMaxSegmentationValues];
        CLY_LOG_W(@"%s Ignoring provided value of %lu for 'maxSegmentationValues' because it's less than 1", __FUNCTION__, (unsigned long)config.sdkInternalLimits.getMaxSegmentationValues);
    }
    else if(config.sdkInternalLimits.getMaxSegmentationValues != kCountlyMaxSegmentationValues)
    {
        CLY_LOG_I(@"%s provided 'maxSegmentationValues' override:[ %lu ]", __FUNCTION__, (unsigned long)config.sdkInternalLimits.getMaxSegmentationValues);
    }
    
    if (config.sdkInternalLimits.getMaxBreadcrumbCount == 0) {
        [config.sdkInternalLimits setMaxBreadcrumbCount:kCountlyMaxBreadcrumbCount];
        CLY_LOG_W(@"%s Ignoring provided value of %lu for 'maxBreadcrumbCount' because it's less than 1", __FUNCTION__, (unsigned long)config.sdkInternalLimits.getMaxBreadcrumbCount);
    }
    else if(config.sdkInternalLimits.getMaxBreadcrumbCount != kCountlyMaxBreadcrumbCount)
    {
        CLY_LOG_I(@"%s provided 'maxBreadcrumbCount' override:[ %lu ]", __FUNCTION__, (unsigned long)config.sdkInternalLimits.getMaxBreadcrumbCount);
    }
    
    if(config.sdkInternalLimits.getMaxStackTraceLineLength != kCountlyMaxStackTraceLinesPerThread)
    {
        CLY_LOG_W(@"%s 'maxStackTraceLineLength' is currently a placeholder and doesn't actively utilize the set values.", __FUNCTION__);
    }
    
    if(config.sdkInternalLimits.getMaxStackTraceLinesPerThread != kCountlyMaxStackTraceLineLength)
    {
        CLY_LOG_I(@"%s 'maxStackTraceLinesPerThread' is currently a placeholder and doesn't actively utilize the set values.", __FUNCTION__);
    }
    return config;
}

#pragma mark -

- (void)onTimer:(NSTimer *)timer
{
    if (isSuspended)
        return;
    
    if (!CountlyCommon.sharedInstance.manualSessionHandling)
    {
        [CountlyConnectionManager.sharedInstance updateSession];
    }
    // this condtion is called only when both manual session handling and hybrid mode is enabled.
    else if (CountlyCommon.sharedInstance.enableManualSessionControlHybridMode)
    {
        [CountlyConnectionManager.sharedInstance updateSession];
    }
    
    [CountlyConnectionManager.sharedInstance sendEventsWithSaveIfNeeded];
}

- (void)suspend
{
#if (TARGET_OS_WATCH)
    CLY_LOG_I(@"%s", __FUNCTION__);
#endif
    
    if (!CountlyCommon.sharedInstance.hasStarted)
        return;
    
    if (isSuspended)
        return;
    
    CLY_LOG_D(@"Suspending...");
    
    isSuspended = YES;
    
    [CountlyConnectionManager.sharedInstance sendEventsWithSaveIfNeeded];
    
    if (!CountlyCommon.sharedInstance.manualSessionHandling)
        [CountlyConnectionManager.sharedInstance endSession];
    
    [CountlyViewTrackingInternal.sharedInstance applicationDidEnterBackground];
    
    [CountlyPersistency.sharedInstance saveToFile];
}

- (void)resume
{
#if (TARGET_OS_WATCH)
    CLY_LOG_I(@"%s", __FUNCTION__);
#endif
    
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
    
    [CountlyViewTrackingInternal.sharedInstance applicationWillEnterForeground];
    
    isSuspended = NO;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    CLY_LOG_D(@"App enters foreground");
    [self resume];
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    CLY_LOG_D(@"App enters background");
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    CLY_LOG_D(@"App did enter background.");
    [self suspend];
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    CLY_LOG_D(@"App will enter foreground.");
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    CLY_LOG_D(@"App will terminate.");
    
    CountlyConnectionManager.sharedInstance.isTerminating = YES;
    
    [CountlyViewTrackingInternal.sharedInstance applicationWillTerminate];
    
    [CountlyConnectionManager.sharedInstance sendEventsWithSaveIfNeeded];
    
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


#pragma mark - Override Configuration

- (void)setNewHost:(NSString *)newHost
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, newHost);
    
    if (!newHost.length)
    {
        CLY_LOG_W(@"New host is invalid!");
        return;
    }
    
    CountlyConnectionManager.sharedInstance.host = newHost;
}

- (void)setNewURLSessionConfiguration:(NSURLSessionConfiguration *)newURLSessionConfiguration
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, newURLSessionConfiguration);
    
    CountlyConnectionManager.sharedInstance.URLSessionConfiguration = newURLSessionConfiguration;
}

- (void)setNewAppKey:(NSString *)newAppKey
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, newAppKey);
    
    if (!newAppKey.length)
    {
        CLY_LOG_W(@"New app key is invalid!");
        return;
    }
    
    [self suspend];
    
    [CountlyPerformanceMonitoring.sharedInstance clearAllCustomTraces];
    
    CountlyConnectionManager.sharedInstance.appKey = newAppKey;
    
    [self resume];
}



#pragma mark - Queue Operations

- (void)flushQueues
{
    CLY_LOG_I(@"%s", __FUNCTION__);
    
    [CountlyPersistency.sharedInstance flushEvents];
    [CountlyPersistency.sharedInstance flushQueue];
}

- (void)replaceAllAppKeysInQueueWithCurrentAppKey
{
    CLY_LOG_I(@"%s", __FUNCTION__);
    
    [CountlyPersistency.sharedInstance replaceAllAppKeysInQueueWithCurrentAppKey];
}

- (void)removeDifferentAppKeysFromQueue
{
    CLY_LOG_I(@"%s", __FUNCTION__);
    
    [CountlyPersistency.sharedInstance removeDifferentAppKeysFromQueue];
}

- (void)addDirectRequest:(NSDictionary<NSString *, NSString *> * _Nullable)requestParameters
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, requestParameters);
    
    [CountlyConnectionManager.sharedInstance addDirectRequest:requestParameters];
}



#pragma mark - Sessions

- (void)beginSession
{
    CLY_LOG_I(@"%s", __FUNCTION__);
    
    if (CountlyCommon.sharedInstance.manualSessionHandling)
        [CountlyConnectionManager.sharedInstance beginSession];
}

- (void)updateSession
{
    CLY_LOG_I(@"%s", __FUNCTION__);
    
    if (CountlyCommon.sharedInstance.manualSessionHandling)
        [CountlyConnectionManager.sharedInstance updateSession];
}

- (void)endSession
{
    CLY_LOG_I(@"%s", __FUNCTION__);
    
    if (CountlyCommon.sharedInstance.manualSessionHandling)
    {
        [CountlyConnectionManager.sharedInstance sendEventsWithSaveIfNeeded];
        [CountlyConnectionManager.sharedInstance endSession];
    }
}




#pragma mark - Device ID

- (NSString *)deviceID
{
    CLY_LOG_I(@"%s", __FUNCTION__);
    
    return CountlyDeviceInfo.sharedInstance.deviceID.cly_URLEscaped;
}

- (CLYDeviceIDType)deviceIDType
{
    CLY_LOG_I(@"%s", __FUNCTION__);
    
    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
        return CLYDeviceIDTypeTemporary;
    
    if ([CountlyPersistency.sharedInstance retrieveIsCustomDeviceID])
        return CLYDeviceIDTypeCustom;

#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_TV )
    return CLYDeviceIDTypeIDFV;
#else
    return CLYDeviceIDTypeNSUUID;
#endif
}

- (void)setID:(NSString *)deviceID;
{
    if (deviceID == nil || !deviceID.length)
    {
        CLY_LOG_W(@"Passing `nil` or empty string as devie ID is not allowed.");
        return;
    }
    
    CLYDeviceIDType deviceIDType = [Countly.sharedInstance deviceIDType];
    if([deviceIDType isEqualToString:CLYDeviceIDTypeCustom])
    {
        [Countly.sharedInstance setIDInternal:deviceID onServer: NO];
    }
    else
    {
        [Countly.sharedInstance setIDInternal:deviceID onServer: YES];
    }
}

- (void)changeDeviceIDWithMerge:(NSString * _Nullable)deviceID {
    [self setIDInternal:deviceID onServer:YES];
}

- (void)changeDeviceIDWithoutMerge:(NSString * _Nullable)deviceID {
    [self setIDInternal:deviceID onServer:NO];
}

- (void)enableTemporaryDeviceIDMode
{
    [Countly.sharedInstance setIDInternal:CLYTemporaryDeviceID onServer:NO];
}

- (void)setNewDeviceID:(NSString *)deviceID onServer:(BOOL)onServer
{
    [Countly.sharedInstance setIDInternal:deviceID onServer:onServer];
}

- (void)setIDInternal:(NSString *)deviceID onServer:(BOOL)onServer
{
    CLY_LOG_I(@"%s %@ %d", __FUNCTION__, deviceID, onServer);

    if (!CountlyCommon.sharedInstance.hasStarted)
        return;

    if (!deviceID.length)
    {
        CLY_LOG_W(@"Passing `CLYDefaultDeviceID` or `nil` or empty string as devie ID is deprecated, and will not be allowed in the future.");
    }
    
    [self storeCustomDeviceIDState:deviceID];

    deviceID = [CountlyDeviceInfo.sharedInstance ensafeDeviceID:deviceID];

    if ([deviceID isEqualToString:CountlyDeviceInfo.sharedInstance.deviceID])
    {
        CLY_LOG_W(@"Attempted to set the same device ID again. So, setting new device ID is aborted.");
        return;
    }

    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
    {
        CLY_LOG_I(@"Going out of CLYTemporaryDeviceID mode and switching back to normal mode.");

        [CountlyDeviceInfo.sharedInstance initializeDeviceID:deviceID];

        [CountlyPersistency.sharedInstance replaceAllTemporaryDeviceIDsInQueueWithDeviceID:deviceID];

        [CountlyConnectionManager.sharedInstance proceedOnQueue];

        [CountlyRemoteConfigInternal.sharedInstance downloadRemoteConfigAutomatically];

        return;
    }

    if ([deviceID isEqualToString:CLYTemporaryDeviceID] && onServer)
    {
        CLY_LOG_W(@"Attempted to set device ID as CLYTemporaryDeviceID with onServer option. So, onServer value is overridden as NO.");
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

        [CountlyConsentManager.sharedInstance cancelConsentForAllFeaturesWithoutSendingConsentsRequest];

        [self resume];

        [CountlyPersistency.sharedInstance clearAllTimedEvents];
    }

    
    [CountlyRemoteConfigInternal.sharedInstance clearCachedRemoteConfig];
    
    if (![deviceID isEqualToString:CLYTemporaryDeviceID] )
    {
        [CountlyRemoteConfigInternal.sharedInstance downloadRemoteConfigAutomatically];
    }
}

- (void)storeCustomDeviceIDState:(NSString *)deviceID
{
    BOOL isCustomDeviceID = deviceID.length && ![deviceID isEqualToString:CLYTemporaryDeviceID];
    [CountlyPersistency.sharedInstance storeIsCustomDeviceID:isCustomDeviceID];
}

#pragma mark - Consents
- (void)giveConsentForFeature:(NSString *)featureName
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, featureName);

    if (!featureName.length)
        return;

    [CountlyConsentManager.sharedInstance giveConsentForFeatures:@[featureName]];
}

- (void)giveConsentForFeatures:(NSArray *)features
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, features);

    [CountlyConsentManager.sharedInstance giveConsentForFeatures:features];
}

- (void)giveConsentForAllFeatures
{
    CLY_LOG_I(@"%s", __FUNCTION__);

    [CountlyConsentManager.sharedInstance giveAllConsents];
}

- (void)giveAllConsents
{
    CLY_LOG_I(@"%s", __FUNCTION__);
    
    [CountlyConsentManager.sharedInstance giveAllConsents];
}

- (void)cancelConsentForFeature:(NSString *)featureName
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, featureName);

    if (!featureName.length)
        return;

    [CountlyConsentManager.sharedInstance cancelConsentForFeatures:@[featureName]];
}

- (void)cancelConsentForFeatures:(NSArray *)features
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, features);

    [CountlyConsentManager.sharedInstance cancelConsentForFeatures:features];
}

- (void)cancelConsentForAllFeatures
{
    CLY_LOG_I(@"%s", __FUNCTION__);

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
    CLY_LOG_I(@"%s %@ %@ %lu %f %f", __FUNCTION__, key, segmentation, (unsigned long)count, sum, duration);

    if (!CountlyConsentManager.sharedInstance.consentForEvents)
    {
        CLY_LOG_W(@"Consent for events not given! Event will not be recorded.");
        return;
    }
    
    BOOL isReservedEvent = [self isReservedEvent:key];

    if (isReservedEvent)
    {
        CLY_LOG_W(@"A reserved event detected for key: '%@', event will not be recorded.", key);
        return;
    }
    
    NSDictionary* truncated = [segmentation cly_truncated:@"Event segmentation"];
    segmentation = [truncated cly_limited:@"Event segmentation"];

    [self recordEvent:key segmentation:segmentation count:count sum:sum duration:duration ID:nil timestamp:CountlyCommon.sharedInstance.uniqueTimestamp];
}

#pragma mark -

- (void)recordReservedEvent:(NSString *)key segmentation:(NSDictionary *)segmentation
{
    [self recordEvent:key segmentation:segmentation count:1 sum:0 duration:0 ID:nil timestamp:CountlyCommon.sharedInstance.uniqueTimestamp];
}

- (void)recordReservedEvent:(NSString *)key segmentation:(NSDictionary *)segmentation ID:(NSString *)ID
{
    [self recordEvent:key segmentation:segmentation count:1 sum:0 duration:0 ID:ID timestamp:CountlyCommon.sharedInstance.uniqueTimestamp];
}

- (void)recordReservedEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(NSUInteger)count sum:(double)sum duration:(NSTimeInterval)duration ID:(NSString *)ID timestamp:(NSTimeInterval)timestamp
{
    [self recordEvent:key segmentation:segmentation count:count sum:sum duration:duration ID:ID timestamp:timestamp];
}

#pragma mark -

- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(NSUInteger)count sum:(double)sum duration:(NSTimeInterval)duration ID:(NSString *)ID timestamp:(NSTimeInterval)timestamp
{
    if (key.length == 0)
        return;

    CountlyEvent *event = CountlyEvent.new;
    event.ID = ID;
    if (!event.ID.length)
    {
        event.ID = CountlyCommon.sharedInstance.randomEventID;
    }

    if ([key isEqualToString:kCountlyReservedEventView])
    {
        event.PVID = CountlyViewTrackingInternal.sharedInstance.previousViewID ?: @"";
    }
    else
    {
        event.CVID = CountlyViewTrackingInternal.sharedInstance.currentViewID ?: @"";
    }

    // Check if the event is a reserved event
    BOOL isReservedEvent = [self isReservedEvent:key];

    NSMutableDictionary *filteredSegmentations = segmentation.cly_filterSupportedDataTypes;
    
    // If the event is not reserved, assign the previous event ID and Name to the current event's PEID property, or an empty string if previousEventID is nil. Then, update previousEventID to the current event's ID.
    if (!isReservedEvent)
    {
        key = [key cly_truncatedKey:@"Event key"];
        event.PEID = previousEventID ?: @"";
        previousEventID = event.ID;
        if(CountlyViewTrackingInternal.sharedInstance.enablePreviousNameRecording) {
            filteredSegmentations[kCountlyPreviousEventName] = previousEventName ?: @"";
            previousEventName = key;
            filteredSegmentations[kCountlyCurrentView] = CountlyViewTrackingInternal.sharedInstance.currentViewName ?: @"";
        }
    }
    event.key = key;
    event.segmentation = [self processSegmentation:filteredSegmentations eventKey:key];
    event.count = MAX(count, 1);
    event.sum = sum;
    event.timestamp = timestamp;
    event.hourOfDay = CountlyCommon.sharedInstance.hourOfDay;
    event.dayOfWeek = CountlyCommon.sharedInstance.dayOfWeek;
    event.duration = duration;

    [CountlyPersistency.sharedInstance recordEvent:event];
}

- (NSDictionary*) processSegmentation:(NSMutableDictionary *) segmentation eventKey:(NSString *)eventKey
{
    if(CountlyViewTrackingInternal.sharedInstance.enablePreviousNameRecording) {
        if([eventKey isEqualToString:kCountlyReservedEventView]) {
            segmentation[kCountlyPreviousView] = CountlyViewTrackingInternal.sharedInstance.previousViewName ?: @"";
        }
    }
    
    if(CountlyCommon.sharedInstance.enableVisibiltyTracking) {
        segmentation[kCountlyVisibility] = @([self isAppInForeground]);
    }
    return segmentation;
}

- (BOOL)isAppInForeground {
#if TARGET_OS_IOS || TARGET_OS_TV
    UIApplicationState state = [UIApplication sharedApplication].applicationState;
    return state == UIApplicationStateActive;
#elif TARGET_OS_OSX
    NSApplication *app = [NSApplication sharedApplication];
    return app.isActive;
#elif TARGET_OS_WATCH
    WKExtension *extension = [WKExtension sharedExtension];
    return extension.applicationState == WKApplicationStateActive;
#else
    return NO;
#endif
}


- (BOOL)isReservedEvent:(NSString *)key
{
    NSArray<NSString *>* reservedEvents =
    @[
        kCountlyReservedEventOrientation,
        kCountlyReservedEventStarRating,
        kCountlyReservedEventSurvey,
        kCountlyReservedEventNPS,
        kCountlyReservedEventPushAction,
        kCountlyReservedEventView,
    ];
    
    return [reservedEvents containsObject:key];
}

#pragma mark -

- (void)startEvent:(NSString *)key
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, key);

    if (!CountlyConsentManager.sharedInstance.consentForEvents)
        return;

    CountlyEvent *event = CountlyEvent.new;
    event.key = key;
    event.timestamp = CountlyCommon.sharedInstance.uniqueTimestamp;

    [CountlyPersistency.sharedInstance recordTimedEvent:event];
}

- (void)endEvent:(NSString *)key
{
    [self endEvent:key segmentation:nil count:1 sum:0];
}

- (void)endEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(NSUInteger)count sum:(double)sum
{
    CLY_LOG_I(@"%s %@ %@ %lu %f", __FUNCTION__, key, segmentation, (unsigned long)count, sum);

    if (!CountlyConsentManager.sharedInstance.consentForEvents)
        return;

    CountlyEvent *event = [CountlyPersistency.sharedInstance timedEventForKey:key];

    if (!event)
    {
        CLY_LOG_W(@"Event with key '%@' not started yet or cancelled/ended before!", key);
        return;
    }

    NSTimeInterval duration = NSDate.date.timeIntervalSince1970 - event.timestamp;
    [self recordEvent:key segmentation:segmentation count:count sum:sum duration:duration];
}

- (void)cancelEvent:(NSString *)key
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, key);

    if (!CountlyConsentManager.sharedInstance.consentForEvents)
        return;

    CountlyEvent *event = [CountlyPersistency.sharedInstance timedEventForKey:key];

    if (!event)
    {
        CLY_LOG_W(@"Event with key '%@' not started yet or cancelled/ended before!", key);
        return;
    }

    CLY_LOG_D(@"Event with key '%@' cancelled!", key);
}


#pragma mark - Push Notifications
#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_OSX )
#ifndef COUNTLY_EXCLUDE_PUSHNOTIFICATIONS

- (void)askForNotificationPermission
{
    CLY_LOG_I(@"%s", __FUNCTION__);

    [CountlyPushNotifications.sharedInstance askForNotificationPermissionWithOptions:0 completionHandler:nil];
}

- (void)askForNotificationPermissionWithOptions:(UNAuthorizationOptions)options completionHandler:(void (^)(BOOL granted, NSError * error))completionHandler;
{
    CLY_LOG_I(@"%s %lu %@", __FUNCTION__, (unsigned long)options, completionHandler);

    [CountlyPushNotifications.sharedInstance askForNotificationPermissionWithOptions:options completionHandler:completionHandler];
}

- (void)recordActionForNotification:(NSDictionary *)userInfo clickedButtonIndex:(NSInteger)buttonIndex;
{
    CLY_LOG_I(@"%s %@ %ld", __FUNCTION__, userInfo, (long)buttonIndex);

    [CountlyPushNotifications.sharedInstance recordActionForNotification:userInfo clickedButtonIndex:buttonIndex];
}

- (void)recordPushNotificationToken
{
    CLY_LOG_I(@"%s", __FUNCTION__);

    [CountlyPushNotifications.sharedInstance sendToken];
}

- (void)clearPushNotificationToken
{
    CLY_LOG_I(@"%s", __FUNCTION__);

    [CountlyPushNotifications.sharedInstance clearToken];
}
#endif
#endif



#pragma mark - Location

- (void)recordLocation:(CLLocationCoordinate2D)location city:(NSString * _Nullable)city ISOCountryCode:(NSString * _Nullable)ISOCountryCode IP:(NSString * _Nullable)IP
{
    CLY_LOG_I(@"%s %f,%f %@ %@ %@", __FUNCTION__, location.latitude, location.longitude, city, ISOCountryCode, IP);

    [CountlyLocationManager.sharedInstance recordLocation:location city:city ISOCountryCode:ISOCountryCode IP:IP];
}

- (void)disableLocationInfo
{
    CLY_LOG_I(@"%s", __FUNCTION__);

    [CountlyLocationManager.sharedInstance disableLocationInfo];
}



#pragma mark - Crash Reporting

- (void)recordException:(NSException *)exception
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, exception);

    [CountlyCrashReporter.sharedInstance recordException:exception isFatal:NO stackTrace:nil segmentation:nil];
}

- (void)recordException:(NSException *)exception isFatal:(BOOL)isFatal
{
    CLY_LOG_I(@"%s %@ %d", __FUNCTION__, exception, isFatal);

    [CountlyCrashReporter.sharedInstance recordException:exception isFatal:isFatal stackTrace:nil segmentation:nil];
}

- (void)recordException:(NSException *)exception isFatal:(BOOL)isFatal stackTrace:(NSArray *)stackTrace segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s %@ %d %@ %@", __FUNCTION__, exception, isFatal, stackTrace, segmentation);

    [CountlyCrashReporter.sharedInstance recordException:exception isFatal:isFatal stackTrace:stackTrace segmentation:segmentation];
}

- (void)recordError:(NSString *)errorName stackTrace:(NSArray * _Nullable)stackTrace
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, errorName, stackTrace);

    [CountlyCrashReporter.sharedInstance recordError:errorName isFatal:NO stackTrace:stackTrace segmentation:nil];
}

- (void)recordError:(NSString *)errorName isFatal:(BOOL)isFatal stackTrace:(NSArray * _Nullable)stackTrace segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s %@ %d %@ %@", __FUNCTION__, errorName, isFatal, stackTrace, segmentation);

    [CountlyCrashReporter.sharedInstance recordError:errorName isFatal:isFatal stackTrace:stackTrace segmentation:segmentation];
}

- (void)recordHandledException:(NSException *)exception
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, exception);

    [CountlyCrashReporter.sharedInstance recordException:exception isFatal:NO stackTrace:nil segmentation:nil];
}

- (void)recordHandledException:(NSException *)exception withStackTrace:(NSArray *)stackTrace
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, exception, stackTrace);

    [CountlyCrashReporter.sharedInstance recordException:exception isFatal:NO stackTrace:stackTrace segmentation:nil];
}

- (void)recordUnhandledException:(NSException *)exception withStackTrace:(NSArray * _Nullable)stackTrace
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, exception, stackTrace);

    [CountlyCrashReporter.sharedInstance recordException:exception isFatal:YES stackTrace:stackTrace segmentation:nil];
}

- (void)recordCrashLog:(NSString *)log
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, log);

    [CountlyCrashReporter.sharedInstance log:log];
}

- (void)clearCrashLogs
{
    [CountlyCrashReporter.sharedInstance clearCrashLogs];
}

- (void)crashLog:(NSString *)format, ...
{

}



#pragma mark - View Tracking

- (void)recordView:(NSString *)viewName;
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, viewName);

    [CountlyViewTrackingInternal.sharedInstance startAutoStoppedView:viewName segmentation:nil];
}

- (void)recordView:(NSString *)viewName segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, viewName, segmentation);

    [CountlyViewTrackingInternal.sharedInstance startAutoStoppedView:viewName segmentation:segmentation];
}

#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_TV )
- (void)addExceptionForAutoViewTracking:(NSString *)exception
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, exception);

    [CountlyViewTrackingInternal.sharedInstance addExceptionForAutoViewTracking:exception.copy];
}

- (void)removeExceptionForAutoViewTracking:(NSString *)exception
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, exception);

    [CountlyViewTrackingInternal.sharedInstance removeExceptionForAutoViewTracking:exception.copy];
}

- (void)setIsAutoViewTrackingActive:(BOOL)isAutoViewTrackingActive
{
    CLY_LOG_I(@"%s %d", __FUNCTION__, isAutoViewTrackingActive);

    CountlyViewTrackingInternal.sharedInstance.isAutoViewTrackingActive = isAutoViewTrackingActive;
}

- (BOOL)isAutoViewTrackingActive
{
    CLY_LOG_I(@"%s", __FUNCTION__);

    return CountlyViewTrackingInternal.sharedInstance.isAutoViewTrackingActive;
}
#endif

- (CountlyViewTracking *) views
{
    return CountlyViewTracking.sharedInstance;
}


#pragma mark - User Details

+ (CountlyUserDetails *)user
{
    return CountlyUserDetails.sharedInstance;
}



#pragma mark - Star Rating
#if (TARGET_OS_IOS)

- (void)askForStarRating:(void(^)(NSInteger rating))completion
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, completion);

    [CountlyFeedbacksInternal.sharedInstance showDialog:completion];
}

- (void)presentFeedbackWidgetWithID:(NSString *)widgetID completionHandler:(void (^)(NSError * error))completionHandler
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, widgetID, completionHandler);
    
    [self presentRatingWidgetWithID:widgetID closeButtonText:nil completionHandler:completionHandler];
}

- (void)presentRatingWidgetWithID:(NSString *)widgetID completionHandler:(void (^)(NSError * error))completionHandler
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, widgetID, completionHandler);
    
    [self presentRatingWidgetWithID:widgetID closeButtonText:nil completionHandler:completionHandler];
}

- (void)presentRatingWidgetWithID:(NSString *)widgetID closeButtonText:(NSString * _Nullable)closeButtonText  completionHandler:(void (^)(NSError * __nullable error))completionHandler
{
    
    CLY_LOG_I(@"%s %@ %@ %@", __FUNCTION__, widgetID, closeButtonText, completionHandler);
    
    [CountlyFeedbacksInternal.sharedInstance presentRatingWidgetWithID:widgetID closeButtonText:closeButtonText completionHandler:completionHandler];
}

- (void)recordRatingWidgetWithID:(NSString *)widgetID rating:(NSInteger)rating email:(NSString * _Nullable)email comment:(NSString * _Nullable)comment userCanBeContacted:(BOOL)userCanBeContacted
{
    CLY_LOG_I(@"%s %@ %ld %@ %@ %d", __FUNCTION__, widgetID, (long)rating, email, comment, userCanBeContacted);

    [CountlyFeedbacksInternal.sharedInstance recordRatingWidgetWithID:widgetID rating:rating email:email comment:comment userCanBeContacted:userCanBeContacted];
}

- (void)getFeedbackWidgets:(void (^)(NSArray <CountlyFeedbackWidget *> *feedbackWidgets, NSError * error))completionHandler
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, completionHandler);

    [CountlyFeedbacksInternal.sharedInstance getFeedbackWidgets:completionHandler];
}

- (CountlyContentBuilder *) content
{
    return CountlyContentBuilder.sharedInstance;
}

- (CountlyFeedbacks *) feedback
{
    return CountlyFeedbacks.sharedInstance;
}

#endif



#pragma mark - Attribution

- (void)recordAttributionID:(NSString *)attributionID
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, attributionID);

    if (!CountlyConsentManager.sharedInstance.consentForAttribution)
        return;

    CountlyCommon.sharedInstance.attributionID = attributionID;

    [CountlyConnectionManager.sharedInstance sendAttribution];
}

- (void)recordDirectAttributionWithCampaignType:(NSString *)campaignType andCampaignData:(NSString *)campaignData
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, campaignType, campaignData);

    if (!CountlyConsentManager.sharedInstance.consentForAttribution)
        return;

    if (!campaignType.length)
    {
        CLY_LOG_E(@"campaignType must be non-zero length valid string. Method execution will be aborted!");
        return;
    }

    if (!campaignData.length)
    {
        CLY_LOG_E(@"campaignData must be non-zero length valid string. Method execution will be aborted!");
        return;
    }

    if ([campaignType isEqualToString:@"_special_test"])
    {
        [CountlyConnectionManager.sharedInstance sendAttributionData:campaignData];
        return;
    }

    if (![campaignType isEqualToString:@"countly"])
    {
        CLY_LOG_W(@"Recording direct attribution with a type other than 'countly' is currently not supported. Method execution will be aborted!");
        return;
    }

    NSError* error = nil;
    NSDictionary* campaignDataDictionary = [NSJSONSerialization JSONObjectWithData:[campaignData cly_dataUTF8] options:0 error:&error];
    if (error)
    {
        CLY_LOG_E(@"Campaign data is not in expected format. Method execution will be aborted!");
        return;
    }

    NSString* campaignID = campaignDataDictionary[@"cid"];
    if (!campaignID.length)
    {
        CLY_LOG_E(@"Campaign ID must be non-zero length valid string. Method execution will be aborted!");
        return;
    }

    NSString* campaignUserID = campaignDataDictionary[@"cuid"];
    if (!campaignUserID.length)
    {
        CLY_LOG_W(@"Campaign User ID must be non-zero length valid string. It will be ignored!");
    }

    [CountlyConnectionManager.sharedInstance sendDirectAttributionWithCampaignID:campaignID andCampaignUserID:campaignUserID];
}

- (void)recordIndirectAttribution:(NSDictionary<NSString *, NSString *> *)attribution
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, attribution);

    if (!CountlyConsentManager.sharedInstance.consentForAttribution)
        return;

    NSMutableDictionary* filtered = attribution.mutableCopy;
    [attribution enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * value, BOOL * stop)
    {
        if (!value.length)
            [filtered removeObjectForKey:key];
    }];

    NSDictionary* truncated = [filtered cly_truncated:@"Indirect attribution"];
    NSDictionary* limited = [truncated cly_limited:@"Indirect attribution"];

    [CountlyConnectionManager.sharedInstance sendIndirectAttribution:limited];
}

#pragma mark - Remote Config

- (id)remoteConfigValueForKey:(NSString *)key
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, key);

    return [CountlyRemoteConfigInternal.sharedInstance remoteConfigValueForKey:key];
}

- (void)updateRemoteConfigWithCompletionHandler:(void (^)(NSError * error))completionHandler
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, completionHandler);

    [CountlyRemoteConfigInternal.sharedInstance updateRemoteConfigForKeys:nil omitKeys:nil completionHandler:completionHandler];
}

- (void)updateRemoteConfigOnlyForKeys:(NSArray *)keys completionHandler:(void (^)(NSError * error))completionHandler
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, keys, completionHandler);

    [CountlyRemoteConfigInternal.sharedInstance updateRemoteConfigForKeys:keys omitKeys:nil completionHandler:completionHandler];
}

- (void)updateRemoteConfigExceptForKeys:(NSArray *)omitKeys completionHandler:(void (^)(NSError * error))completionHandler
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, omitKeys, completionHandler);

    [CountlyRemoteConfigInternal.sharedInstance updateRemoteConfigForKeys:nil omitKeys:omitKeys completionHandler:completionHandler];
}

- (CountlyRemoteConfig *) remoteConfig {
    return CountlyRemoteConfig.sharedInstance;
}

#pragma mark - Performance Monitoring

- (void)recordNetworkTrace:(NSString *)traceName requestPayloadSize:(NSInteger)requestPayloadSize responsePayloadSize:(NSInteger)responsePayloadSize responseStatusCode:(NSInteger)responseStatusCode startTime:(long long)startTime endTime:(long long)endTime
{
    CLY_LOG_I(@"%s %@ %ld %ld %ld %lld %lld", __FUNCTION__, traceName, (long)requestPayloadSize, (long)responsePayloadSize, (long)responseStatusCode, startTime, endTime);

    [CountlyPerformanceMonitoring.sharedInstance recordNetworkTrace:traceName requestPayloadSize:requestPayloadSize responsePayloadSize:responsePayloadSize responseStatusCode:responseStatusCode startTime:startTime endTime:endTime];
}

- (void)startCustomTrace:(NSString *)traceName
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, traceName);

    [CountlyPerformanceMonitoring.sharedInstance startCustomTrace:traceName];
}

- (void)endCustomTrace:(NSString *)traceName metrics:(NSDictionary * _Nullable)metrics
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, traceName, metrics);

    [CountlyPerformanceMonitoring.sharedInstance endCustomTrace:traceName metrics:metrics];
}

- (void)cancelCustomTrace:(NSString *)traceName
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, traceName);

    [CountlyPerformanceMonitoring.sharedInstance cancelCustomTrace:traceName];
}

- (void)clearAllCustomTraces
{
    CLY_LOG_I(@"%s", __FUNCTION__);

    [CountlyPerformanceMonitoring.sharedInstance clearAllCustomTraces];
}

- (void)appLoadingFinished
{
    CLY_LOG_I(@"%s", __FUNCTION__);

    long long appLoadEndTime = floor(NSDate.date.timeIntervalSince1970 * 1000);

    [CountlyPerformanceMonitoring.sharedInstance recordAppStartDurationTraceWithStartTime:appLoadStartTime endTime:appLoadEndTime];
}

- (void)halt
{
    CLY_LOG_I(@"%s", __FUNCTION__);
    [self halt:true];
}

- (void)halt:(BOOL) clearStorage
{
    CLY_LOG_I(@"%s %d", __FUNCTION__, clearStorage);
    [CountlyConsentManager.sharedInstance resetInstance];
    [CountlyPersistency.sharedInstance resetInstance:clearStorage];
    [CountlyDeviceInfo.sharedInstance resetInstance];
    [CountlyConnectionManager.sharedInstance resetInstance];
    [self resetInstance];
    [CountlyCommon.sharedInstance resetInstance];
    
    if(clearStorage)
    {
        NSString *appDomain = [[NSBundle mainBundle] bundleIdentifier];
        [NSUserDefaults.standardUserDefaults removePersistentDomainForName:appDomain];
        [NSUserDefaults.standardUserDefaults synchronize];
    }
}

- (void)attemptToSendStoredRequests
{
    CLY_LOG_I(@"%s", __FUNCTION__);
    [CountlyConnectionManager.sharedInstance attemptToSendStoredRequests];
}

@end
