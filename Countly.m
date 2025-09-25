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
    CLY_LOG_I(@"%s resetting the instance", __FUNCTION__);
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
    
    if (config.disableSDKBehaviorSettingsUpdates) {
        [CountlyServerConfig.sharedInstance disableSDKBehaviourSettings];
    }
    [CountlyServerConfig.sharedInstance retrieveServerConfigFromStorage:config];

    CountlyCommon.sharedInstance.maxKeyLength = config.sdkInternalLimits.getMaxKeyLength;
    CountlyCommon.sharedInstance.maxValueLength = config.sdkInternalLimits.getMaxValueSize;
    CountlyCommon.sharedInstance.maxSegmentationValues = config.sdkInternalLimits.getMaxSegmentationValues;
    
    // For backward compatibility, deprecated values are only set incase new values are not provided using sdkInternalLimits interface
    if(CountlyCommon.sharedInstance.maxKeyLength == kCountlyMaxKeyLength && config.maxKeyLength != kCountlyMaxKeyLength) {
        CountlyCommon.sharedInstance.maxKeyLength = config.maxKeyLength;
        CLY_LOG_I(@"%s \033[1;31m deprecated maxKeyLength provided, maxKeyLength: [%lu]", __FUNCTION__, (unsigned long)config.maxKeyLength);
    }
    if(CountlyCommon.sharedInstance.maxValueLength == kCountlyMaxValueSize && config.maxValueLength != kCountlyMaxValueSize) {
        CountlyCommon.sharedInstance.maxValueLength = config.maxValueLength;
        CLY_LOG_I(@"%s deprecated maxValueLength provided, maxValueLength: [%lu]", __FUNCTION__, (unsigned long)config.maxValueLength);
    }
    if(CountlyCommon.sharedInstance.maxSegmentationValues == kCountlyMaxSegmentationValues && config.maxSegmentationValues != kCountlyMaxSegmentationValues) {
        CountlyCommon.sharedInstance.maxSegmentationValues = config.maxSegmentationValues;
        CLY_LOG_I(@"%s deprecated maxSegmentationValues provided, maxSegmentationValues: [%lu]", __FUNCTION__, (unsigned long)config.maxSegmentationValues);
    }
    
    CountlyConsentManager.sharedInstance.requiresConsent = config.requiresConsent;
    
    if (!config.appKey.length || [config.appKey isEqualToString:@"YOUR_APP_KEY"])
        [NSException raise:@"CountlyAppKeyNotSetException" format:@"appKey property on CountlyConfig object is not set"];
    
    if (!config.host.length || [config.host isEqualToString:@"https://YOUR_COUNTLY_SERVER"])
        [NSException raise:@"CountlyHostNotSetException" format:@"host property on CountlyConfig object is not set"];
    
    CLY_LOG_I(@"%s initializing, appKey: [%@], serverUrl: [%@], sdkName: [%@], sdkVersion: [%@], device: [%@], osName: [%@], osVersion: [%@], defaultSDKName: [%@], defaultSDKVersion: [%@]",
              __FUNCTION__, config.appKey, config.host, CountlyCommon.sharedInstance.SDKName, CountlyCommon.sharedInstance.SDKVersion, CountlyDeviceInfo.device,
              CountlyDeviceInfo.osName, CountlyDeviceInfo.osVersion,kCountlySDKName, kCountlySDKVersion);

    
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
    // If something added related to server config, make sure to check CountlyServerConfig.notifySdkConfigChange
    [CountlyServerConfig.sharedInstance fetchServerConfig:config];
    
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
        CLY_LOG_W(@"%s deprecated maxBreadcrumbCount provided, maxBreadcrumbCount: [%lu]", __FUNCTION__, (unsigned long)config.crashLogLimit);
    }
    CountlyCrashReporter.sharedInstance.crashFilter = config.crashFilter;
    CountlyCrashReporter.sharedInstance.shouldUsePLCrashReporter = config.shouldUsePLCrashReporter;
    CountlyCrashReporter.sharedInstance.shouldUseMachSignalHandler = config.shouldUseMachSignalHandler;
    CountlyCrashReporter.sharedInstance.crashOccuredOnPreviousSessionCallback = config.crashOccuredOnPreviousSessionCallback;
    CountlyCrashReporter.sharedInstance.shouldSendCrashReportCallback = config.shouldSendCrashReportCallback;
    if ([config.features containsObject:CLYCrashReporting])
    {
        CountlyCrashReporter.sharedInstance.isEnabledOnInitialConfig = YES;
        if (CountlyServerConfig.sharedInstance.crashReportingEnabled)
        {
        [CountlyCrashReporter.sharedInstance startCrashReporting];
        }
    }

#if (TARGET_OS_IOS || TARGET_OS_TV )
    if (config.enableAutomaticViewTracking || [config.features containsObject:CLYAutoViewTracking])
    {
        // Print deprecation flag for feature
        CountlyViewTrackingInternal.sharedInstance.isEnabledOnInitialConfig = YES;
        if (CountlyServerConfig.sharedInstance.viewTrackingEnabled)
        {
            [CountlyViewTrackingInternal.sharedInstance startAutoViewTracking];
        }
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
    if(config.content.getZoneTimerInterval){
        CountlyContentBuilderInternal.sharedInstance.zoneTimerInterval = config.content.getZoneTimerInterval;
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
    
    [CountlyHealthTracker.sharedInstance sendHealthCheck];
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
    CLY_LOG_D(@"%s tick is happening sending events, manualSessions: [%d], hybridSessions: [%d], isSuspended: [%d]", __FUNCTION__, CountlyCommon.sharedInstance.manualSessionHandling, CountlyCommon.sharedInstance.enableManualSessionControlHybridMode, isSuspended);
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
    
    CLY_LOG_D(@"%s sending events, saving the state, manualSessions: [%d]", __FUNCTION__, CountlyCommon.sharedInstance.manualSessionHandling);

    isSuspended = YES;
    
    [CountlyViewTrackingInternal.sharedInstance applicationDidEnterBackground];
    
    [CountlyConnectionManager.sharedInstance sendEventsWithSaveIfNeeded];
    
    if (!CountlyCommon.sharedInstance.manualSessionHandling)
        [CountlyConnectionManager.sharedInstance endSession];
    
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
    
    CLY_LOG_D(@"%s manualSessions: [%d]", __FUNCTION__, CountlyCommon.sharedInstance.manualSessionHandling);
    
    if (!CountlyCommon.sharedInstance.manualSessionHandling)
        [CountlyConnectionManager.sharedInstance beginSession];
    
    [CountlyViewTrackingInternal.sharedInstance applicationWillEnterForeground];
    
    isSuspended = NO;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    CLY_LOG_D(@"%s app enters foreground", __FUNCTION__);
  [CountlyServerConfig.sharedInstance fetchServerConfigIfTimeIsUp];
    [self resume];
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    CLY_LOG_D(@"%s, app enters background", __FUNCTION__);
    [CountlyHealthTracker.sharedInstance saveState];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    CLY_LOG_D(@"%s, app did enter background.", __FUNCTION__);
    [CountlyHealthTracker.sharedInstance saveState];
    [self suspend];
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    CLY_LOG_D(@"%s, app will enter foreground.", __FUNCTION__);
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    CLY_LOG_D(@"%s, app will terminate.", __FUNCTION__);
    
    [CountlyHealthTracker.sharedInstance saveState];
    
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
        CLY_LOG_W(@"%s new host is invalid!", __FUNCTION__);
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
        CLY_LOG_W(@"%s new app key is invalid!", __FUNCTION__);
        return;
    }
    
    [self suspend];
    
    [CountlyPerformanceMonitoring.sharedInstance clearAllCustomTraces];
    
    CountlyConnectionManager.sharedInstance.appKey = newAppKey;
    
    [self resume];
}



#pragma mark - Queue Operations

- (void)recordMetrics:(NSDictionary<NSString *, NSString *> * _Nullable)metricsOverride
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, metricsOverride);
    [CountlyConnectionManager.sharedInstance recordMetrics:metricsOverride];
}

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
        CLY_LOG_W(@"%s Passing `nil` or empty string as devie ID is not allowed.", __FUNCTION__);
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
    CLY_LOG_I(@"%s", __FUNCTION__);
    [self setIDInternal:deviceID onServer:YES];
}

- (void)changeDeviceIDWithoutMerge:(NSString * _Nullable)deviceID {
    CLY_LOG_I(@"%s", __FUNCTION__);
    [self setIDInternal:deviceID onServer:NO];
}

- (void)enableTemporaryDeviceIDMode
{
    CLY_LOG_I(@"%s", __FUNCTION__);
    [Countly.sharedInstance setIDInternal:CLYTemporaryDeviceID onServer:NO];
}

- (void)setNewDeviceID:(NSString *)deviceID onServer:(BOOL)onServer
{
    [Countly.sharedInstance setIDInternal:deviceID onServer:onServer];
}

- (void)setIDInternal:(NSString *)deviceID onServer:(BOOL)onServer
{
    CLY_LOG_I(@"%s deviceID: [%@], onServer: [%d]", __FUNCTION__, deviceID, onServer);
    if (!CountlyCommon.sharedInstance.hasStarted)
        return;

    if (!deviceID.length)
    {
        CLY_LOG_W(@"%s Passing `CLYDefaultDeviceID` or `nil` or empty string as devie ID is deprecated, and will not be allowed in the future.", __FUNCTION__);
    }
    
    [self storeCustomDeviceIDState:deviceID];

    deviceID = [CountlyDeviceInfo.sharedInstance ensafeDeviceID:deviceID];

    if ([deviceID isEqualToString:CountlyDeviceInfo.sharedInstance.deviceID])
    {
        CLY_LOG_W(@"%s Attempted to set the same device ID again. So, setting new device ID is aborted.", __FUNCTION__);
        return;
    }

    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
    {
        CLY_LOG_I(@"%s Going out of CLYTemporaryDeviceID mode and switching back to normal mode.", __FUNCTION__);

        [CountlyDeviceInfo.sharedInstance initializeDeviceID:deviceID];
        
        [CountlyPersistency.sharedInstance replaceAllTemporaryDeviceIDsInQueueWithDeviceID:deviceID];

        [CountlyConnectionManager.sharedInstance proceedOnQueue];

        [CountlyRemoteConfigInternal.sharedInstance downloadRemoteConfigAutomatically];
        
        [CountlyHealthTracker.sharedInstance sendHealthCheck];

        return;
    }

    if ([deviceID isEqualToString:CLYTemporaryDeviceID] && onServer)
    {
        CLY_LOG_W(@"%s Attempted to set device ID as CLYTemporaryDeviceID with onServer option. So, onServer value is overridden as NO.", __FUNCTION__);
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
    CLY_LOG_I(@"%s featureName: [%@]", __FUNCTION__, featureName);

    if (!featureName.length)
        return;

    [CountlyConsentManager.sharedInstance giveConsentForFeatures:@[featureName]];
}

- (void)giveConsentForFeatures:(NSArray *)features
{
    CLY_LOG_I(@"%s features: [%@]", __FUNCTION__, features);
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
    CLY_LOG_I(@"%s featureName: [%@]", __FUNCTION__, featureName);

    if (!featureName.length)
        return;

    [CountlyConsentManager.sharedInstance cancelConsentForFeatures:@[featureName]];
}

- (void)cancelConsentForFeatures:(NSArray *)features
{
    CLY_LOG_I(@"%s features: [%@]", __FUNCTION__, features);
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
    CLY_LOG_I(@"%s key: [%@], segmentation: [%@], count: [%lu], sum: [%f], duration: [%f]", __FUNCTION__, key, segmentation, (unsigned long)count, sum, duration);

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
    if (!CountlyServerConfig.sharedInstance.customEventTrackingEnabled)
    {
        CLY_LOG_D(@"'recordEvent' is aborted: Custom Event Tracking is disabled from server config!");
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
    if (key.length == 0) {
        CLY_LOG_D(@"%s omitting the call, key is empty", __FUNCTION__);
        return;
    }

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
    if(filteredSegmentations == nil)
        filteredSegmentations = NSMutableDictionary.new;
    
    // If the event is not reserved, assign the previous event ID and Name to the current event's PEID property, or an empty string if previousEventID is nil. Then, update previousEventID to the current event's ID.
    if (!isReservedEvent)
    {
        CLY_LOG_V(@"%s will add event id and name properties because it is not a reserved event ", __FUNCTION__);
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

- (NSDictionary *)processSegmentation:(NSMutableDictionary *)segmentation eventKey:(NSString *)eventKey {
    BOOL isViewEvent = [eventKey isEqualToString:kCountlyReservedEventView];
    
    // Add previous view name if enabled and the event is a view event
    if (isViewEvent && CountlyViewTrackingInternal.sharedInstance.enablePreviousNameRecording) {
        segmentation[kCountlyPreviousView] = CountlyViewTrackingInternal.sharedInstance.previousViewName ?: @"";
    }
    
    // Add visibility tracking information if enabled
    if (CountlyCommon.sharedInstance.enableVisibiltyTracking) {
        BOOL isViewStart = [segmentation[kCountlyVTKeyVisit] isEqual:@1];
        
        // Add visibility if it's not a view event or it's a view start event
        if (!isViewEvent || isViewStart) {
            segmentation[kCountlyVisibility] = @([self isAppInForeground] ? 1 : 0);
        }
    }
    
    // Return segmentation dictionary if not empty, otherwise return nil
    return segmentation.count > 0 ? segmentation : nil;
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
    CLY_LOG_I(@"%s key: [%@]", __FUNCTION__, key);

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
    CLY_LOG_I(@"%s key: [%@], segmentation: [%@], count: [%lu], sum: [%f]", __FUNCTION__, key, segmentation, (unsigned long)count, sum);

    if (!CountlyConsentManager.sharedInstance.consentForEvents)
        return;

    CountlyEvent *event = [CountlyPersistency.sharedInstance timedEventForKey:key];

    if (!event)
    {
        CLY_LOG_W(@"%s Event with key '%@' not started yet or cancelled/ended before!", __FUNCTION__, key);
        return;
    }

    NSTimeInterval duration = NSDate.date.timeIntervalSince1970 - event.timestamp;
    [self recordEvent:key segmentation:segmentation count:count sum:sum duration:duration];
}

- (void)cancelEvent:(NSString *)key
{
    CLY_LOG_I(@"%s key: [%@]", __FUNCTION__, key);

    if (!CountlyConsentManager.sharedInstance.consentForEvents)
        return;

    CountlyEvent *event = [CountlyPersistency.sharedInstance timedEventForKey:key];

    if (!event)
    {
        CLY_LOG_W(@"%s Event with key '%@' not started yet or cancelled/ended before!", __FUNCTION__, key);
        return;
    }

    CLY_LOG_D(@"%s Event with key '%@' cancelled!", __FUNCTION__, key);
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
    CLY_LOG_I(@"%s options: [%lu], completionHandler: [%@]", __FUNCTION__, (unsigned long)options, completionHandler);
    [CountlyPushNotifications.sharedInstance askForNotificationPermissionWithOptions:options completionHandler:completionHandler];
}

- (void)recordActionForNotification:(NSDictionary *)userInfo clickedButtonIndex:(NSInteger)buttonIndex;
{
    CLY_LOG_I(@"%s userInfo: [%@], buttonIndex: [%ld]", __FUNCTION__, userInfo, (long)buttonIndex);
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
    CLY_LOG_I(@"%s lat: [%f], long: [%f], city: [%@], country: [%@], ip: [%@]", __FUNCTION__, location.latitude, location.longitude, city, ISOCountryCode, IP);
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
    CLY_LOG_I(@"%s exception: [%@]", __FUNCTION__, exception);
    [CountlyCrashReporter.sharedInstance recordException:exception isFatal:NO stackTrace:nil segmentation:nil];
}

- (void)recordException:(NSException *)exception isFatal:(BOOL)isFatal
{
    CLY_LOG_I(@"%s exception: [%@], isFatal: [%d]", __FUNCTION__, exception, isFatal);
    [CountlyCrashReporter.sharedInstance recordException:exception isFatal:isFatal stackTrace:nil segmentation:nil];
}

- (void)recordException:(NSException *)exception isFatal:(BOOL)isFatal stackTrace:(NSArray *)stackTrace segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s exception: [%@], isFatal: [%d], stackTrace: [%@], segmentation: [%@]", __FUNCTION__, exception, isFatal, stackTrace, segmentation);
    [CountlyCrashReporter.sharedInstance recordException:exception isFatal:isFatal stackTrace:stackTrace segmentation:segmentation];
}

- (void)recordError:(NSString *)errorName stackTrace:(NSArray * _Nullable)stackTrace
{
    CLY_LOG_I(@"%s errorName: [%@], stackTrace: [%@]", __FUNCTION__, errorName, stackTrace);
    [CountlyCrashReporter.sharedInstance recordError:errorName isFatal:NO stackTrace:stackTrace segmentation:nil];
}

- (void)recordError:(NSString *)errorName isFatal:(BOOL)isFatal stackTrace:(NSArray * _Nullable)stackTrace segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s errorName: [%@], isFatal: [%d], stackTrace: [%@], segmentation: [%@]", __FUNCTION__, errorName, isFatal, stackTrace, segmentation);
    [CountlyCrashReporter.sharedInstance recordError:errorName isFatal:isFatal stackTrace:stackTrace segmentation:segmentation];
}

- (void)recordHandledException:(NSException *)exception
{
    CLY_LOG_I(@"%s exception: [%@]", __FUNCTION__, exception);
    [CountlyCrashReporter.sharedInstance recordException:exception isFatal:NO stackTrace:nil segmentation:nil];
}

- (void)recordHandledException:(NSException *)exception withStackTrace:(NSArray *)stackTrace
{
    CLY_LOG_I(@"%s exception: [%@], stackTrace: [%@]", __FUNCTION__, exception, stackTrace);
    [CountlyCrashReporter.sharedInstance recordException:exception isFatal:NO stackTrace:stackTrace segmentation:nil];
}

- (void)recordUnhandledException:(NSException *)exception withStackTrace:(NSArray * _Nullable)stackTrace
{
    CLY_LOG_I(@"%s exception: [%@], stackTrace: [%@]", __FUNCTION__, exception, stackTrace);
    [CountlyCrashReporter.sharedInstance recordException:exception isFatal:YES stackTrace:stackTrace segmentation:nil];
}

- (void)recordCrashLog:(NSString *)log
{
    CLY_LOG_I(@"%s log: [%@]", __FUNCTION__, log);
    [CountlyCrashReporter.sharedInstance log:log];
}

- (void)clearCrashLogs
{
    CLY_LOG_I(@"%s", __FUNCTION__);
    [CountlyCrashReporter.sharedInstance clearCrashLogs];
}

- (void)crashLog:(NSString *)format, ...
{

}
#pragma mark - View Tracking

- (void)recordView:(NSString *)viewName;
{
    CLY_LOG_I(@"%s viewName: [%@]", __FUNCTION__, viewName);
    [CountlyViewTrackingInternal.sharedInstance startAutoStoppedView:viewName segmentation:nil];
}

- (void)recordView:(NSString *)viewName segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s viewName: [%@], segmentation: [%@]", __FUNCTION__, viewName, segmentation);

    [CountlyViewTrackingInternal.sharedInstance startAutoStoppedView:viewName segmentation:segmentation];
}

#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_TV )
- (void)addExceptionForAutoViewTracking:(NSString *)exception
{
    CLY_LOG_I(@"%s exception: [%@]", __FUNCTION__, exception);

    [CountlyViewTrackingInternal.sharedInstance addExceptionForAutoViewTracking:exception.copy];
}

- (void)removeExceptionForAutoViewTracking:(NSString *)exception
{
    CLY_LOG_I(@"%s exception: [%@]", __FUNCTION__, exception);

    [CountlyViewTrackingInternal.sharedInstance removeExceptionForAutoViewTracking:exception.copy];
}

- (void)setIsAutoViewTrackingActive:(BOOL)isAutoViewTrackingActive
{
    CLY_LOG_I(@"%s isAutoViewTrackingActive: [%d]", __FUNCTION__, isAutoViewTrackingActive);

    CountlyViewTrackingInternal.sharedInstance.isAutoViewTrackingActive = isAutoViewTrackingActive;
}

- (BOOL)isAutoViewTrackingActive
{
    CLY_LOG_I(@"%s", __FUNCTION__);
    return CountlyViewTrackingInternal.sharedInstance.isAutoViewTrackingActive;
}
#endif
#pragma mark - Star Rating
#if (TARGET_OS_IOS)

- (void)askForStarRating:(void(^)(NSInteger rating))completion
{
    CLY_LOG_I(@"%s completion: [%@]", __FUNCTION__, completion);
    [CountlyFeedbacksInternal.sharedInstance showDialog:completion];
}

- (void)presentFeedbackWidgetWithID:(NSString *)widgetID completionHandler:(void (^)(NSError * error))completionHandler
{
    CLY_LOG_I(@"%s widgetID: [%@], completionHandler: [%@]", __FUNCTION__, widgetID, completionHandler);
    
    [self presentRatingWidgetWithID:widgetID closeButtonText:nil completionHandler:completionHandler];
}

- (void)presentRatingWidgetWithID:(NSString *)widgetID completionHandler:(void (^)(NSError * error))completionHandler
{
    CLY_LOG_I(@"%s widgetID: [%@], completionHandler: [%@]", __FUNCTION__, widgetID, completionHandler);
    [self presentRatingWidgetWithID:widgetID closeButtonText:nil completionHandler:completionHandler];
}

- (void)presentRatingWidgetWithID:(NSString *)widgetID closeButtonText:(NSString * _Nullable)closeButtonText  completionHandler:(void (^)(NSError * __nullable error))completionHandler
{
    
    CLY_LOG_I(@"%s widgetID: [%@], closeButtonText: [%@], completionHandler: [%@]", __FUNCTION__, widgetID, closeButtonText, completionHandler);
    
    [CountlyFeedbacksInternal.sharedInstance presentRatingWidgetWithID:widgetID closeButtonText:closeButtonText completionHandler:completionHandler];
}

- (void)recordRatingWidgetWithID:(NSString *)widgetID rating:(NSInteger)rating email:(NSString * _Nullable)email comment:(NSString * _Nullable)comment userCanBeContacted:(BOOL)userCanBeContacted
{
    CLY_LOG_I(@"%s widgetID: [%@], rating: [%ld], email: [%@], comment: [%@], userCanBeContacted: [%d]", __FUNCTION__, widgetID, (long)rating, email, comment, userCanBeContacted);

    [CountlyFeedbacksInternal.sharedInstance recordRatingWidgetWithID:widgetID rating:rating email:email comment:comment userCanBeContacted:userCanBeContacted];
}

- (void)getFeedbackWidgets:(void (^)(NSArray <CountlyFeedbackWidget *> *feedbackWidgets, NSError * error))completionHandler
{
    CLY_LOG_I(@"%s completionHandler: [%@]", __FUNCTION__, completionHandler);
    [CountlyFeedbacksInternal.sharedInstance getFeedbackWidgets:completionHandler];
}
#endif
#pragma mark - Attribution

- (void)recordAttributionID:(NSString *)attributionID
{
    CLY_LOG_I(@"%s attributionID: [%@]", __FUNCTION__, attributionID);

    if (!CountlyConsentManager.sharedInstance.consentForAttribution)
        return;

    CountlyCommon.sharedInstance.attributionID = attributionID;

    [CountlyConnectionManager.sharedInstance sendAttribution];
}

- (void)recordDirectAttributionWithCampaignType:(NSString *)campaignType andCampaignData:(NSString *)campaignData
{
    CLY_LOG_I(@"%s campaignType: [%@], campaignData: [%@]", __FUNCTION__, campaignType, campaignData);

    if (!CountlyConsentManager.sharedInstance.consentForAttribution)
        return;

    if (!campaignType.length)
    {
        CLY_LOG_E(@"%s campaignType must be non-zero length valid string. Method execution will be aborted!", __FUNCTION__);
        return;
    }

    if (!campaignData.length)
    {
        CLY_LOG_E(@"%s campaignData must be non-zero length valid string. Method execution will be aborted!", __FUNCTION__);
        return;
    }

    if ([campaignType isEqualToString:@"_special_test"])
    {
        [CountlyConnectionManager.sharedInstance sendAttributionData:campaignData];
        return;
    }

    if (![campaignType isEqualToString:@"countly"])
    {
        CLY_LOG_W(@"%s Recording direct attribution with a type other than 'countly' is currently not supported. Method execution will be aborted!", __FUNCTION__);
        return;
    }

    NSError* error = nil;
    NSDictionary* campaignDataDictionary = [NSJSONSerialization JSONObjectWithData:[campaignData cly_dataUTF8] options:0 error:&error];
    if (error)
    {
        CLY_LOG_E(@"%s Campaign data is not in expected format. Method execution will be aborted!", __FUNCTION__);
        return;
    }

    NSString* campaignID = campaignDataDictionary[@"cid"];
    if (!campaignID.length)
    {
        CLY_LOG_E(@"%s Campaign ID must be non-zero length valid string. Method execution will be aborted!", __FUNCTION__);
        return;
    }

    NSString* campaignUserID = campaignDataDictionary[@"cuid"];
    if (!campaignUserID.length)
    {
        CLY_LOG_W(@"%s Campaign User ID must be non-zero length valid string. It will be ignored!", __FUNCTION__);
    }

    [CountlyConnectionManager.sharedInstance sendDirectAttributionWithCampaignID:campaignID andCampaignUserID:campaignUserID];
}

- (void)recordIndirectAttribution:(NSDictionary<NSString *, NSString *> *)attribution
{
    CLY_LOG_I(@"%s attribution: [%@]", __FUNCTION__, attribution);

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
    CLY_LOG_I(@"%s key: [%@]", __FUNCTION__, key);
    return [CountlyRemoteConfigInternal.sharedInstance remoteConfigValueForKey:key];
}

- (void)updateRemoteConfigWithCompletionHandler:(void (^)(NSError * error))completionHandler
{
    CLY_LOG_I(@"%s completionHandler: [%@]", __FUNCTION__, completionHandler);
    [CountlyRemoteConfigInternal.sharedInstance updateRemoteConfigForKeys:nil omitKeys:nil completionHandler:completionHandler];
}

- (void)updateRemoteConfigOnlyForKeys:(NSArray *)keys completionHandler:(void (^)(NSError * error))completionHandler
{
    CLY_LOG_I(@"%s keys: [%@], completionHandler: [%@]", __FUNCTION__, keys, completionHandler);
    [CountlyRemoteConfigInternal.sharedInstance updateRemoteConfigForKeys:keys omitKeys:nil completionHandler:completionHandler];
}

- (void)updateRemoteConfigExceptForKeys:(NSArray *)omitKeys completionHandler:(void (^)(NSError * error))completionHandler
{
    CLY_LOG_I(@"%s omitKeys: [%@], completionHandler: [%@]", __FUNCTION__, omitKeys, completionHandler);
    [CountlyRemoteConfigInternal.sharedInstance updateRemoteConfigForKeys:nil omitKeys:omitKeys completionHandler:completionHandler];
}

#pragma mark - Performance Monitoring

- (void)recordNetworkTrace:(NSString *)traceName requestPayloadSize:(NSInteger)requestPayloadSize responsePayloadSize:(NSInteger)responsePayloadSize responseStatusCode:(NSInteger)responseStatusCode startTime:(long long)startTime endTime:(long long)endTime
{
    CLY_LOG_I(@"%s traceName: [%@], requestPayloadSize: [%ld], responsePayloadSize: [%ld], responseStatusCode: [%ld], startTime: [%lld], endTime: [%lld]", __FUNCTION__, traceName, (long)requestPayloadSize, (long)responsePayloadSize, (long)responseStatusCode, startTime, endTime);

    [CountlyPerformanceMonitoring.sharedInstance recordNetworkTrace:traceName requestPayloadSize:requestPayloadSize responsePayloadSize:responsePayloadSize responseStatusCode:responseStatusCode startTime:startTime endTime:endTime];
}

- (void)startCustomTrace:(NSString *)traceName
{
    CLY_LOG_I(@"%s traceName: [%@]", __FUNCTION__, traceName);
    [CountlyPerformanceMonitoring.sharedInstance startCustomTrace:traceName];
}

- (void)endCustomTrace:(NSString *)traceName metrics:(NSDictionary * _Nullable)metrics
{
    CLY_LOG_I(@"%s traceName: [%@], metrics: [%@]", __FUNCTION__, traceName, metrics);
    [CountlyPerformanceMonitoring.sharedInstance endCustomTrace:traceName metrics:metrics];
}

- (void)cancelCustomTrace:(NSString *)traceName
{
    CLY_LOG_I(@"%s traceName: [%@]", __FUNCTION__, traceName);
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
    CLY_LOG_I(@"%s clearStorage: [%d]", __FUNCTION__, clearStorage);
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

#pragma mark - Interfaces
#if (TARGET_OS_IOS)
- (CountlyContentBuilder *) content
{
    return CountlyContentBuilder.sharedInstance;
}

- (CountlyFeedbacks *) feedback
{
    return CountlyFeedbacks.sharedInstance;
}

#endif
- (CountlyViewTracking *) views
{
    return CountlyViewTracking.sharedInstance;
}

+ (CountlyUserDetails *)user
{
    return CountlyUserDetails.sharedInstance;
}

- (CountlyRemoteConfig *) remoteConfig {
    return CountlyRemoteConfig.sharedInstance;
}

@end
