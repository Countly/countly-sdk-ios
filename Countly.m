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
    CountlyConfig* _startConfig;
}
@end

long long appLoadStartTime;
// It holds the event id of previous recorded custom event.
static NSString* previousEventID;
// It holds the event name of previous recorded custom event.
static NSString* previousEventName;
#if __has_include(<os/lock.h>)
#import <os/lock.h>
static os_unfair_lock previousEventLock = OS_UNFAIR_LOCK_INIT;
#endif
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
    // Invalidate timer to avoid callbacks to a deallocated instance between tests.
    if (timer) {
        [timer invalidate];
        timer = nil;
    }
    // Remove all notification observers to avoid duplicate registrations after re-init in tests.
    [NSNotificationCenter.defaultCenter removeObserver:self];
    // Break the previous-event chain, otherwise the first event recorded after a restart
    // carries the `peid` / `pen` of an event from the previous SDK lifetime.
#if __has_include(<os/lock.h>)
    os_unfair_lock_lock(&previousEventLock);
#endif
    previousEventID = nil;
    previousEventName = nil;
#if __has_include(<os/lock.h>)
    os_unfair_lock_unlock(&previousEventLock);
#endif
    isSuspended = NO;
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

        //NOTE: macOS has no background state, so there is no `suspend` counterpart here.
        //      `applicationDidBecomeActive:` is observed so that a `begin_session` dropped by
        //      the "app is not active" guard in `beginSession` (app launched hidden, as a login
        //      item, or opened by another app) is recovered on the first activation.
        //NOTE: Resign-active is deliberately NOT observed. Its handler saves health tracker
        //      state, which forces an NSUserDefaults synchronize, and on macOS the user
        //      switches away from the app constantly. `applicationWillTerminate:` already
        //      saves that state.
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(applicationDidBecomeActive:)
                                                   name:NSApplicationDidBecomeActiveNotification
                                                 object:nil];
#endif
    }
    
    return self;
}

- (void)startWithConfig:(CountlyConfig *)config
{
    if (CountlyCommon.sharedInstance.hasStarted_)
    {
        CLY_LOG_W(@"%s omitting the call, the SDK has already been started", __FUNCTION__);
        return;
    }
    
    CountlyCommon.sharedInstance.hasStarted = YES;
    CountlyCommon.sharedInstance.enableDebug = config.enableDebug;
    CountlyCommon.sharedInstance.shouldIgnoreTrustCheck = config.shouldIgnoreTrustCheck;
    CountlyCommon.sharedInstance.loggerDelegate = config.loggerDelegate;
    CountlyCommon.sharedInstance.internalLogLevel = config.internalLogLevel;

    config = [self checkAndFixInternalLimitsConfig:config];
    _startConfig = config;

    if (config.disableSDKBehaviorSettingsUpdates) {
        [CountlyServerConfig.sharedInstance disableSDKBehaviourSettings];
    }
    [CountlyServerConfig.sharedInstance retrieveServerConfigFromStorage:config];

    CountlyCommon.sharedInstance.maxKeyLength = config.sdkInternalLimits.getMaxKeyLength;
    CountlyCommon.sharedInstance.maxValueLength = config.sdkInternalLimits.getMaxValueSize;
    CountlyCommon.sharedInstance.maxValueLengthPicture = config.sdkInternalLimits.getMaxValueSizePicture;
    CountlyCommon.sharedInstance.maxSegmentationValues = config.sdkInternalLimits.getMaxSegmentationValues;
    
    // For backward compatibility, deprecated values are only set incase new values are not provided using sdkInternalLimits interface
    if(CountlyCommon.sharedInstance.maxKeyLength == kCountlyMaxKeyLength && config.maxKeyLength != kCountlyMaxKeyLength) {
        CountlyCommon.sharedInstance.maxKeyLength = config.maxKeyLength;
        CLY_LOG_W(@"%s deprecated 'maxKeyLength' config used, use sdkInternalLimits instead, applied: [%lu]", __FUNCTION__, (unsigned long)config.maxKeyLength);
    }
    if(CountlyCommon.sharedInstance.maxValueLength == kCountlyMaxValueSize && config.maxValueLength != kCountlyMaxValueSize) {
        CountlyCommon.sharedInstance.maxValueLength = config.maxValueLength;
        CLY_LOG_W(@"%s deprecated 'maxValueLength' config used, use sdkInternalLimits instead, applied: [%lu]", __FUNCTION__, (unsigned long)config.maxValueLength);
    }
    if(CountlyCommon.sharedInstance.maxSegmentationValues == kCountlyMaxSegmentationValues && config.maxSegmentationValues != kCountlyMaxSegmentationValues) {
        CountlyCommon.sharedInstance.maxSegmentationValues = config.maxSegmentationValues;
        CLY_LOG_W(@"%s deprecated 'maxSegmentationValues' config used, use sdkInternalLimits instead, applied: [%lu]", __FUNCTION__, (unsigned long)config.maxSegmentationValues);
    }
    
    CountlyConsentManager.sharedInstance.requiresConsent = config.requiresConsent;
    
    if (!config.appKey.length || [config.appKey isEqualToString:@"YOUR_APP_KEY"])
    {
        CLY_LOG_E(@"%s the appKey on the config object is missing or still holds the placeholder value, initialization will be aborted", __FUNCTION__);
        [NSException raise:@"CountlyAppKeyNotSetException" format:@"appKey property on CountlyConfig object is not set"];
    }
    
    if (!config.host.length || [config.host isEqualToString:@"https://YOUR_COUNTLY_SERVER"])
    {
        CLY_LOG_E(@"%s the host on the config object is missing or still holds the placeholder value, initialization will be aborted", __FUNCTION__);
        [NSException raise:@"CountlyHostNotSetException" format:@"host property on CountlyConfig object is not set"];
    }
    
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

    if (config.providedUserProperties.count > 0) {
        CLY_LOG_I(@"%s applying the user properties provided at init, count: [%lu]", __FUNCTION__, (unsigned long)config.providedUserProperties.count);
        CLY_LOG_D(@"%s provided user property detail at init, providedUserProperties: [%@]", __FUNCTION__, config.providedUserProperties);
        [Countly.sharedInstance.userProfile setProperties:config.providedUserProperties];
    }

    [Countly.sharedInstance.userProfile save];
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
    
    // Automatic session tracking is resolved through the SBS precedence chain (server can override the developer's manual session control choice)
    if (CountlyServerConfig.sharedInstance.automaticSessionTrackingEnabled)
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
        CLY_LOG_W(@"%s deprecated 'crashLogLimit' config used, use sdkInternalLimits instead, applied breadcrumb limit: [%lu]", __FUNCTION__, (unsigned long)config.crashLogLimit);
    }
    CountlyCrashReporter.sharedInstance.crashFilter = config.crashFilter;
    CountlyCrashReporter.sharedInstance.shouldUsePLCrashReporter = config.shouldUsePLCrashReporter;
    CountlyCrashReporter.sharedInstance.shouldUseMachSignalHandler = config.shouldUseMachSignalHandler;
    CountlyCrashReporter.sharedInstance.crashOccuredOnPreviousSessionCallback = config.crashOccuredOnPreviousSessionCallback;
    CountlyCrashReporter.sharedInstance.shouldSendCrashReportCallback = config.shouldSendCrashReportCallback;
    // Automatic crash reporting is resolved through the SBS precedence chain, so the server can enable it even when the developer did not
    if (CountlyServerConfig.sharedInstance.crashReportingEnabled && CountlyServerConfig.sharedInstance.automaticCrashReportingEnabled)
    {
        [CountlyCrashReporter.sharedInstance startCrashReporting];
    }

#if (TARGET_OS_IOS || TARGET_OS_TV )
    // Automatic view tracking is resolved through the SBS precedence chain, so the server can enable it even when the developer did not
    if (CountlyServerConfig.sharedInstance.viewTrackingEnabled && CountlyServerConfig.sharedInstance.automaticViewTrackingEnabled)
    {
        [CountlyViewTrackingInternal.sharedInstance startAutoViewTracking];
    }
    if (config.automaticViewTrackingExclusionList) {
        [CountlyViewTrackingInternal.sharedInstance addAutoViewTrackingExclutionList:config.automaticViewTrackingExclusionList];
    }
#endif
    
    if(config.disableViewRestartForManualRecording){
        CountlyViewTrackingInternal.sharedInstance.isManualViewRestartActive = NO;
    }
    
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
    if(config.content.getWebViewDisplayOption){
        CountlyContentBuilderInternal.sharedInstance.webViewDisplayOption = config.content.getWebViewDisplayOption;
    }
    CountlyContentBuilderInternal.sharedInstance.enableContentReloadOnStall = config.content.getEnableContentReloadOnStall;
    CountlyContentBuilderInternal.sharedInstance.contentReloadOnStallTimeout = config.content.getContentReloadOnStallTimeout / 1000.0;
    CountlyContentBuilderInternal.sharedInstance.disableZoom = config.content.getDisableZoom;
    CountlyContentBuilderInternal.sharedInstance.disableRotation = config.content.getDisableRotation;
    CountlyContentBuilderInternal.sharedInstance.contentURLHandler = config.content.getContentURLHandler;
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

    CountlyCommon.sharedInstance.hasFinishedInit = YES;

    // the request queue is usable from here on, so this is the first chance for the lines gathered during init to go out
    [CountlyCommon.sharedInstance flushSdkLogs];

    // The behavior settings response for the fetch started above can arrive before init finishes, in
    // which case it deliberately did not touch automatic tracking. Apply the resolved values now that
    // the configuration is complete, so a server side 'avt' or 'acr' is never silently dropped.
    [CountlyServerConfig.sharedInstance applyAutomaticTrackingState];
}

- (CountlyConfig *) checkAndFixInternalLimitsConfig:(CountlyConfig *)config
{
    if (config.sdkInternalLimits.getMaxKeyLength == 0) {
        [config.sdkInternalLimits setMaxKeyLength:kCountlyMaxKeyLength];
        CLY_LOG_W(@"%s ignoring the provided 'maxKeyLength' because it is less than 1, falling back to: [%lu]", __FUNCTION__, (unsigned long)config.sdkInternalLimits.getMaxKeyLength);
    }
    else if(config.sdkInternalLimits.getMaxKeyLength != kCountlyMaxKeyLength)
    {
        CLY_LOG_I(@"%s applying the 'maxKeyLength' override, maxKeyLength: [%lu]", __FUNCTION__, (unsigned long)config.sdkInternalLimits.getMaxKeyLength);
    }
    
    if (config.sdkInternalLimits.getMaxValueSize == 0) {
        [config.sdkInternalLimits setMaxValueSize:kCountlyMaxValueSize];
        CLY_LOG_W(@"%s ignoring the provided 'maxValueSize' because it is less than 1, falling back to: [%lu]", __FUNCTION__, (unsigned long)config.sdkInternalLimits.getMaxValueSize);
    }
    else if(config.sdkInternalLimits.getMaxValueSize != kCountlyMaxValueSize)
    {
        CLY_LOG_I(@"%s applying the 'maxValueSize' override, maxValueSize: [%lu]", __FUNCTION__, (unsigned long)config.sdkInternalLimits.getMaxValueSize);
    }
    
    if (config.sdkInternalLimits.getMaxSegmentationValues == 0) {
        [config.sdkInternalLimits setMaxSegmentationValues:kCountlyMaxSegmentationValues];
        CLY_LOG_W(@"%s ignoring the provided 'maxSegmentationValues' because it is less than 1, falling back to: [%lu]", __FUNCTION__, (unsigned long)config.sdkInternalLimits.getMaxSegmentationValues);
    }
    else if(config.sdkInternalLimits.getMaxSegmentationValues != kCountlyMaxSegmentationValues)
    {
        CLY_LOG_I(@"%s applying the 'maxSegmentationValues' override, maxSegmentationValues: [%lu]", __FUNCTION__, (unsigned long)config.sdkInternalLimits.getMaxSegmentationValues);
    }
    
    if (config.sdkInternalLimits.getMaxBreadcrumbCount == 0) {
        [config.sdkInternalLimits setMaxBreadcrumbCount:kCountlyMaxBreadcrumbCount];
        CLY_LOG_W(@"%s ignoring the provided 'maxBreadcrumbCount' because it is less than 1, falling back to: [%lu]", __FUNCTION__, (unsigned long)config.sdkInternalLimits.getMaxBreadcrumbCount);
    }
    else if(config.sdkInternalLimits.getMaxBreadcrumbCount != kCountlyMaxBreadcrumbCount)
    {
        CLY_LOG_I(@"%s applying the 'maxBreadcrumbCount' override, maxBreadcrumbCount: [%lu]", __FUNCTION__, (unsigned long)config.sdkInternalLimits.getMaxBreadcrumbCount);
    }
    
    if(config.sdkInternalLimits.getMaxStackTraceLineLength != kCountlyMaxStackTraceLineLength)
    {
        CLY_LOG_D(@"%s 'maxStackTraceLineLength' is a placeholder and is not applied, provided: [%lu]", __FUNCTION__, (unsigned long)config.sdkInternalLimits.getMaxStackTraceLineLength);
    }
    
    if(config.sdkInternalLimits.getMaxStackTraceLinesPerThread != kCountlyMaxStackTraceLinesPerThread)
    {
        CLY_LOG_D(@"%s 'maxStackTraceLinesPerThread' is a placeholder and is not applied, provided: [%lu]", __FUNCTION__, (unsigned long)config.sdkInternalLimits.getMaxStackTraceLinesPerThread);
    }
    return config;
}

#pragma mark -

- (void)onTimer:(NSTimer *)timer
{
    CLY_LOG_D(@"%s session timer fired, automaticSessions: [%@], hybridSessions: [%@], isSuspended: [%@]", __FUNCTION__, CountlyServerConfig.sharedInstance.automaticSessionTrackingEnabled ? @"YES" : @"NO", CountlyCommon.sharedInstance.enableManualSessionControlHybridMode ? @"YES" : @"NO", isSuspended ? @"YES" : @"NO");
    if (isSuspended)
        return;
    
    // Hybrid mode keeps the automatic session update going even when automatic session tracking is not active
    if (CountlyServerConfig.sharedInstance.automaticSessionTrackingEnabled || CountlyCommon.sharedInstance.enableManualSessionControlHybridMode)
    {
        [CountlyConnectionManager.sharedInstance updateSession];
    }
    
    [CountlyConnectionManager.sharedInstance sendEventsWithSaveIfNeeded];

    // a buffer that never reaches the batch size would otherwise sit in memory for the whole run
    [CountlyCommon.sharedInstance scheduleSdkLogsFlush];
}

- (void)suspend
{
    CLY_LOG_I(@"%s suspending the SDK, isSuspended: [%@]", __FUNCTION__, isSuspended ? @"YES" : @"NO");
    
    if (!CountlyCommon.sharedInstance.hasStarted)
    {
        CLY_LOG_D(@"%s omitting the suspend, the SDK has not been started yet", __FUNCTION__);
        return;
    }
    
    if (isSuspended)
    {
        CLY_LOG_D(@"%s the SDK is already suspended, nothing left to do", __FUNCTION__);
        return;
    }
    
    CLY_LOG_D(@"%s flushing events and saving the state before suspend, automaticSessions: [%@]", __FUNCTION__, CountlyServerConfig.sharedInstance.automaticSessionTrackingEnabled ? @"YES" : @"NO");

    isSuspended = YES;
    
    [CountlyViewTrackingInternal.sharedInstance applicationDidEnterBackground];
    
    [CountlyConnectionManager.sharedInstance sendEventsWithSaveIfNeeded];

    // nothing about the gathered lines is persisted, so the only way the tail survives the app going away is getting it out now
    [CountlyCommon.sharedInstance flushSdkLogs];
    
    if (CountlyServerConfig.sharedInstance.automaticSessionTrackingEnabled)
        [CountlyConnectionManager.sharedInstance endSession];

    [CountlyPersistency.sharedInstance saveToFile];
}

- (void)resume
{
    CLY_LOG_I(@"%s resuming the SDK, isSuspended: [%@]", __FUNCTION__, isSuspended ? @"YES" : @"NO");
    
    if (!CountlyCommon.sharedInstance.hasStarted)
    {
        CLY_LOG_D(@"%s omitting the resume, the SDK has not been started yet", __FUNCTION__);
        return;
    }
    
#if (TARGET_OS_WATCH)
    //NOTE: Skip first time to prevent double begin session because of applicationDidBecomeActive call on launch of watchOS apps
    static BOOL isFirstCall = YES;
    
    if (isFirstCall)
    {
        isFirstCall = NO;
        CLY_LOG_D(@"%s skipping the first resume on watchOS to avoid a duplicate begin session", __FUNCTION__);
        return;
    }
#endif
    
    CLY_LOG_D(@"%s restarting session handling after resume, automaticSessions: [%@]", __FUNCTION__, CountlyServerConfig.sharedInstance.automaticSessionTrackingEnabled ? @"YES" : @"NO");
    
    if (CountlyServerConfig.sharedInstance.automaticSessionTrackingEnabled)
        [CountlyConnectionManager.sharedInstance beginSession];

    [CountlyViewTrackingInternal.sharedInstance applicationWillEnterForeground];
    
    isSuspended = NO;
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    CLY_LOG_V(@"%s the app became active, checking the server config and resuming", __FUNCTION__);
  [CountlyServerConfig.sharedInstance fetchServerConfigIfTimeIsUp];
    [self resume];
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    CLY_LOG_V(@"%s the app will resign active, saving the health tracker state", __FUNCTION__);
    [CountlyHealthTracker.sharedInstance saveState];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
    CLY_LOG_D(@"%s the app did enter background, saving the state and suspending", __FUNCTION__);
    [CountlyHealthTracker.sharedInstance saveState];
    [self suspend];
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
    CLY_LOG_V(@"%s the app will enter foreground", __FUNCTION__);
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    CLY_LOG_D(@"%s the app will terminate, flushing events and saving the state synchronously", __FUNCTION__);
    
    [CountlyHealthTracker.sharedInstance saveState];
    
    CountlyConnectionManager.sharedInstance.isTerminating = YES;
    
    [CountlyViewTrackingInternal.sharedInstance applicationWillTerminate];
    
    [CountlyConnectionManager.sharedInstance sendEventsWithSaveIfNeeded];

    // the queue is not drained while terminating, but a queued tail survives to the next launch through the sync save below
    [CountlyCommon.sharedInstance flushSdkLogs];
    
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
    CLY_LOG_I(@"%s newHost: [%@]", __FUNCTION__, newHost);
    
    if (!newHost.length)
    {
        CLY_LOG_E(@"%s omitting the call, the provided host is nil or empty", __FUNCTION__);
        return;
    }
    
    CountlyConnectionManager.sharedInstance.host = newHost;
}

- (void)setNewURLSessionConfiguration:(NSURLSessionConfiguration *)newURLSessionConfiguration
{
    CLY_LOG_I(@"%s URLSessionConfiguration is overridden, configurationProvided: [%@]", __FUNCTION__, (newURLSessionConfiguration != nil) ? @"YES" : @"NO");
    
    CountlyConnectionManager.sharedInstance.URLSessionConfiguration = newURLSessionConfiguration;
}

- (void)setNewAppKey:(NSString *)newAppKey
{
    CLY_LOG_I(@"%s newAppKey: [%@]", __FUNCTION__, newAppKey);
    
    if (!newAppKey.length)
    {
        CLY_LOG_E(@"%s omitting the call, the provided app key is nil or empty", __FUNCTION__);
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
    CLY_LOG_I(@"%s overriding metrics, keys: [%@], count: [%lu]", __FUNCTION__, metricsOverride.allKeys, (unsigned long)metricsOverride.count);
    CLY_LOG_D(@"%s metrics override detail, metricsOverride: [%@]", __FUNCTION__, metricsOverride);
    [CountlyConnectionManager.sharedInstance recordMetrics:metricsOverride];
}

- (void)flushQueues
{
    CLY_LOG_I(@"%s flushing the event and the request queues", __FUNCTION__);
    
    [CountlyPersistency.sharedInstance flushEvents];
    [CountlyPersistency.sharedInstance flushQueue];
}

- (void)replaceAllAppKeysInQueueWithCurrentAppKey
{
    CLY_LOG_I(@"%s replacing all app keys in the request queue with the current app key", __FUNCTION__);
    
    [CountlyPersistency.sharedInstance replaceAllAppKeysInQueueWithCurrentAppKey];
}

- (void)removeDifferentAppKeysFromQueue
{
    CLY_LOG_I(@"%s removing the requests with a different app key from the queue", __FUNCTION__);
    
    [CountlyPersistency.sharedInstance removeDifferentAppKeysFromQueue];
}

- (void)addDirectRequest:(NSDictionary<NSString *, NSString *> * _Nullable)requestParameters
{
    CLY_LOG_I(@"%s adding a direct request, keys: [%@], count: [%lu]", __FUNCTION__, requestParameters.allKeys, (unsigned long)requestParameters.count);
    CLY_LOG_D(@"%s direct request parameter detail, requestParameters: [%@]", __FUNCTION__, requestParameters);
    
    [CountlyConnectionManager.sharedInstance addDirectRequest:requestParameters];
}

- (void)addCustomNetworkRequestHeaders:(NSDictionary<NSString *, NSString *> *_Nullable)customHeaderValues {
    CLY_LOG_I(@"%s adding custom network request headers, keys: [%@], count: [%lu]", __FUNCTION__, customHeaderValues.allKeys, (unsigned long)customHeaderValues.count);
    CLY_LOG_D(@"%s custom network request header detail, customHeaderValues: [%@]", __FUNCTION__, customHeaderValues);
    
    // Ignore nil or empty dictionary
    if (customHeaderValues == nil || customHeaderValues.count == 0) {
        CLY_LOG_W(@"%s omitting the call, no custom network request header is provided", __FUNCTION__);
        return;
    }
    
    [CountlyConnectionManager.sharedInstance addCustomNetworkRequestHeaders:customHeaderValues];
}


#pragma mark - Sessions

- (void)beginSession
{
    CLY_LOG_I(@"%s a manual session begin is requested, automaticSessions: [%@]", __FUNCTION__, CountlyServerConfig.sharedInstance.automaticSessionTrackingEnabled ? @"YES" : @"NO");

    if (CountlyServerConfig.sharedInstance.automaticSessionTrackingEnabled)
    {
        CLY_LOG_W(@"%s omitting the session begin, automatic session tracking is active", __FUNCTION__);
        return;
    }

    [CountlyConnectionManager.sharedInstance beginSession];
}

- (void)updateSession
{
    CLY_LOG_I(@"%s a manual session update is requested, automaticSessions: [%@]", __FUNCTION__, CountlyServerConfig.sharedInstance.automaticSessionTrackingEnabled ? @"YES" : @"NO");

    if (CountlyServerConfig.sharedInstance.automaticSessionTrackingEnabled)
    {
        CLY_LOG_W(@"%s omitting the session update, automatic session tracking is active", __FUNCTION__);
        return;
    }

    [CountlyConnectionManager.sharedInstance updateSession];
}

- (void)endSession
{
    CLY_LOG_I(@"%s a manual session end is requested, automaticSessions: [%@]", __FUNCTION__, CountlyServerConfig.sharedInstance.automaticSessionTrackingEnabled ? @"YES" : @"NO");

    if (CountlyServerConfig.sharedInstance.automaticSessionTrackingEnabled)
    {
        CLY_LOG_W(@"%s omitting the session end, automatic session tracking is active", __FUNCTION__);
        return;
    }

    [CountlyConnectionManager.sharedInstance sendEventsWithSaveIfNeeded];
    [CountlyConnectionManager.sharedInstance endSession];
}




#pragma mark - Device ID

- (NSString *)deviceID
{
    CLY_LOG_I(@"%s the device ID is requested", __FUNCTION__);
    
    return CountlyDeviceInfo.sharedInstance.deviceID.cly_URLEscaped;
}

- (CLYDeviceIDType)deviceIDType
{
    CLY_LOG_I(@"%s the device ID type is requested, isTemporary: [%@]", __FUNCTION__, CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary ? @"YES" : @"NO");
    
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
    CLY_LOG_I(@"%s changing the device ID, valueProvided: [%@]", __FUNCTION__, deviceID.length ? @"YES" : @"NO");

    if (deviceID == nil || !deviceID.length)
    {
        CLY_LOG_W(@"%s omitting the call, passing nil or an empty string as the device ID is not allowed", __FUNCTION__);
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
    CLY_LOG_I(@"%s changing the device ID with a server side merge, valueProvided: [%@]", __FUNCTION__, deviceID.length ? @"YES" : @"NO");
    [self setIDInternal:deviceID onServer:YES];
}

- (void)changeDeviceIDWithoutMerge:(NSString * _Nullable)deviceID {
    CLY_LOG_I(@"%s changing the device ID without a server side merge, valueProvided: [%@]", __FUNCTION__, deviceID.length ? @"YES" : @"NO");
    [self setIDInternal:deviceID onServer:NO];
}

- (void)enableTemporaryDeviceIDMode
{
    CLY_LOG_I(@"%s switching to temporary device ID mode", __FUNCTION__);
    [Countly.sharedInstance setIDInternal:CLYTemporaryDeviceID onServer:NO];
}

- (void)setNewDeviceID:(NSString *)deviceID onServer:(BOOL)onServer
{
    CLY_LOG_I(@"%s valueProvided: [%@], onServer: [%@]", __FUNCTION__, deviceID.length ? @"YES" : @"NO", onServer ? @"YES" : @"NO");
    CLY_LOG_W(@"%s deprecated API used, use 'changeDeviceIDWithMerge:' or 'changeDeviceIDWithoutMerge:' instead", __FUNCTION__);
    [Countly.sharedInstance setIDInternal:deviceID onServer:onServer];
}

- (void)setIDInternal:(NSString *)deviceID onServer:(BOOL)onServer
{
    CLY_LOG_D(@"%s applying the device ID change, valueProvided: [%@], onServer: [%@]", __FUNCTION__, deviceID.length ? @"YES" : @"NO", onServer ? @"YES" : @"NO");
    CLY_LOG_D(@"%s device ID change detail, deviceID: [%@], onServer: [%@]", __FUNCTION__, deviceID, onServer ? @"YES" : @"NO");
    if (!CountlyCommon.sharedInstance.hasStarted)
    {
        CLY_LOG_W(@"%s omitting the device ID change, the SDK has not been started yet", __FUNCTION__);
        return;
    }

    if (!deviceID.length)
    {
        CLY_LOG_W(@"%s passing 'CLYDefaultDeviceID', nil or an empty string as the device ID is deprecated and will not be allowed in the future", __FUNCTION__);
    }
    
    [self storeCustomDeviceIDState:deviceID];

    deviceID = [CountlyDeviceInfo.sharedInstance ensafeDeviceID:deviceID];

    if ([deviceID isEqualToString:CountlyDeviceInfo.sharedInstance.deviceID])
    {
        CLY_LOG_D(@"%s omitting the call, the provided device ID is identical to the current one", __FUNCTION__);
        return;
    }

    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
    {
        CLY_LOG_I(@"%s leaving temporary device ID mode and switching back to normal mode", __FUNCTION__);

        [CountlyDeviceInfo.sharedInstance initializeDeviceID:deviceID];
        
        [CountlyPersistency.sharedInstance replaceAllTemporaryDeviceIDsInQueueWithDeviceID:deviceID];

        [CountlyConnectionManager.sharedInstance proceedOnQueue];

        [CountlyServerConfig.sharedInstance fetchServerConfig:_startConfig];

        [CountlyRemoteConfigInternal.sharedInstance downloadRemoteConfigAutomatically];

        [CountlyHealthTracker.sharedInstance sendHealthCheck];

        return;
    }

    if ([deviceID isEqualToString:CLYTemporaryDeviceID] && onServer)
    {
        CLY_LOG_W(@"%s 'CLYTemporaryDeviceID' cannot be set with the onServer option, onServer is overridden as NO", __FUNCTION__);
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
    CLY_LOG_I(@"%s giving consent, featureName: [%@]", __FUNCTION__, featureName);

    if (!featureName.length)
    {
        CLY_LOG_E(@"%s omitting the call, the provided feature name is empty", __FUNCTION__);
        return;
    }

    [CountlyConsentManager.sharedInstance giveConsentForFeatures:@[featureName]];
}

- (void)giveConsentForFeatures:(NSArray *)features
{
    [CountlyConsentManager.sharedInstance giveConsentForFeatures:features];
}

- (void)giveConsentForAllFeatures
{
    CLY_LOG_I(@"%s giving consent for all features", __FUNCTION__);
    CLY_LOG_W(@"%s deprecated API used, use 'giveAllConsents' instead", __FUNCTION__);
    [CountlyConsentManager.sharedInstance giveAllConsents];
}

- (void)giveAllConsents
{
    CLY_LOG_I(@"%s giving all consents", __FUNCTION__);
    [CountlyConsentManager.sharedInstance giveAllConsents];
}

- (void)cancelConsentForFeature:(NSString *)featureName
{
    CLY_LOG_I(@"%s cancelling consent, featureName: [%@]", __FUNCTION__, featureName);

    if (!featureName.length)
    {
        CLY_LOG_E(@"%s omitting the call, the feature name to cancel consent for is empty", __FUNCTION__);
        return;
    }

    [CountlyConsentManager.sharedInstance cancelConsentForFeatures:@[featureName]];
}

- (void)cancelConsentForFeatures:(NSArray *)features
{
    [CountlyConsentManager.sharedInstance cancelConsentForFeatures:features];
}

- (void)cancelConsentForAllFeatures
{
    CLY_LOG_I(@"%s cancelling consent for all features", __FUNCTION__);
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
    CLY_LOG_I(@"%s recording an event, key: [%@], segmentation keys: [%@], segmentation key count: [%lu], count: [%lu], sum: [%f], duration: [%f]", __FUNCTION__, key, segmentation.allKeys, (unsigned long)segmentation.count, (unsigned long)count, sum, duration);
    CLY_LOG_D(@"%s event segmentation detail, key: [%@], segmentation: [%@]", __FUNCTION__, key, segmentation);

    NSNumber* isReservedEvent = [self isReservedEvent:key];

    if (isReservedEvent)
    {
        if (!isReservedEvent.boolValue)
        {
            CLY_LOG_V(@"%s no consent given for the reserved event, it will not be recorded, key: [%@]", __FUNCTION__, key);
            return;
        }
        CLY_LOG_V(@"%s specific consent is given for the reserved event, it will be recorded, key: [%@]", __FUNCTION__, key);
    } else if (!CountlyConsentManager.sharedInstance.consentForEvents) {
        CLY_LOG_V(@"%s no consent given for events, the event will not be recorded, key: [%@]", __FUNCTION__, key);
        return;
    }
    
    if (!CountlyServerConfig.sharedInstance.customEventTrackingEnabled)
    {
        CLY_LOG_D(@"%s dropping the event, custom event tracking is disabled by the server config, key: [%@]", __FUNCTION__, key);
        return;
    }

    if (![CountlyServerConfig.sharedInstance shouldRecordEvent:key])
    {
        CLY_LOG_D(@"%s dropping the event, it is filtered out by the server config event filter, key: [%@]", __FUNCTION__, key);
        return;
    }
    
    // Apply global segmentation filter (sb/sw) and event-specific segmentation filter (esb/esw)
    NSDictionary* filtered = [CountlyServerConfig.sharedInstance filterSegmentation:segmentation eventKey:key];
    filtered = [filtered cly_truncated:@"Event segmentation"];
    segmentation = [filtered cly_limited:@"Event segmentation"];

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
        CLY_LOG_E(@"%s omitting the call, the event key is nil or empty", __FUNCTION__);
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

    event.count = MAX(count, 1);
    event.sum = sum;
    event.timestamp = timestamp;
    event.hourOfDay = CountlyCommon.sharedInstance.hourOfDay;
    event.dayOfWeek = CountlyCommon.sharedInstance.dayOfWeek;
    event.duration = duration;
    
    if (!isReservedEvent)
    {
        CLY_LOG_V(@"%s adding the event id and name properties, it is not a reserved event, key: [%@]", __FUNCTION__, key);
        key = [key cly_truncatedKey:@"Event key"];
        NSString* capturedPreviousID = nil;
        NSString* capturedPreviousName = nil;
#if __has_include(<os/lock.h>)
        os_unfair_lock_lock(&previousEventLock);
#endif
        capturedPreviousID = previousEventID;
        previousEventID = event.ID; // update chain
        if(CountlyViewTrackingInternal.sharedInstance.enablePreviousNameRecording) {
            capturedPreviousName = previousEventName;
            previousEventName = key;
        }
        event.PEID = capturedPreviousID ?: @"";
        if(CountlyViewTrackingInternal.sharedInstance.enablePreviousNameRecording) {
            filteredSegmentations[kCountlyPreviousEventName] = capturedPreviousName ?: @"";
            filteredSegmentations[kCountlyCurrentView] = CountlyViewTrackingInternal.sharedInstance.currentViewName ?: @"";
        }
        event.key = key;
        event.segmentation = [self processSegmentation:filteredSegmentations eventKey:key];
        CLYRequestCallback callback = nil;
        if ([CountlyServerConfig.sharedInstance isJourneyTriggerEvent:key])
        {
            callback = [self journeyTriggerCallback];
        }
        [CountlyPersistency.sharedInstance recordEvent:event callback:callback];
#if __has_include(<os/lock.h>)
        os_unfair_lock_unlock(&previousEventLock);
#endif
    }
    else
    {
        event.key = key;
        event.segmentation = [self processSegmentation:filteredSegmentations eventKey:key];
        CLYRequestCallback callback = nil;
        // Journey trigger views mirror the journey trigger events behavior. The 'name' segmentation value is
        // matched as sent (after truncation and filtering), same as the wire format.
        if ([key isEqualToString:kCountlyReservedEventView])
        {
            NSString* viewName = event.segmentation[kCountlyVTKeyName];
            if ([viewName isKindOfClass:NSString.class] && [CountlyServerConfig.sharedInstance isJourneyTriggerView:viewName])
            {
                callback = [self journeyTriggerCallback];
            }
        }
        [CountlyPersistency.sharedInstance recordEvent:event callback:callback];
    }
}

// Callback used for both journey trigger kinds: recording an event with a callback force-flushes the event
// queue, and the content zone is refreshed once that request succeeds.
- (CLYRequestCallback)journeyTriggerCallback
{
    return ^(NSString *response, BOOL success) {
        if (success)
        {
#if (TARGET_OS_IOS)
            dispatch_async(dispatch_get_main_queue(), ^{
                [CountlyContentBuilderInternal.sharedInstance refreshContentZoneJTE];
            });
#endif
        }
    };
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
#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_VISION
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

/// This checks that given key requires any extra consent
- (NSNumber *)isReservedEvent:(NSString *)key
{
    NSDictionary <NSString *, NSNumber *>* reservedEvents =
    @{
        kCountlyReservedEventOrientation: @(CountlyConsentManager.sharedInstance.consentForUserDetails),
        kCountlyReservedEventStarRating: @(CountlyConsentManager.sharedInstance.consentForFeedback),
        kCountlyReservedEventSurvey: @(CountlyConsentManager.sharedInstance.consentForFeedback),
        kCountlyReservedEventNPS: @(CountlyConsentManager.sharedInstance.consentForFeedback),
        kCountlyReservedEventPushAction: @(CountlyConsentManager.sharedInstance.consentForPushNotifications),
        kCountlyReservedEventView: @(CountlyConsentManager.sharedInstance.consentForViewTracking),
    };

    NSNumber* aReservedEvent = reservedEvents[key];
    return aReservedEvent;
}

#pragma mark -

- (void)startEvent:(NSString *)key
{
    CLY_LOG_I(@"%s starting a timed event, key: [%@]", __FUNCTION__, key);

    if (!CountlyConsentManager.sharedInstance.consentForEvents)
    {
        CLY_LOG_V(@"%s no consent given for events, the timed event will not be started, key: [%@]", __FUNCTION__, key);
        return;
    }

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
    CLY_LOG_I(@"%s ending a timed event, key: [%@], segmentation keys: [%@], segmentation key count: [%lu], count: [%lu], sum: [%f]", __FUNCTION__, key, segmentation.allKeys, (unsigned long)segmentation.count, (unsigned long)count, sum);
    CLY_LOG_D(@"%s timed event end segmentation detail, key: [%@], segmentation: [%@]", __FUNCTION__, key, segmentation);

    if (!CountlyConsentManager.sharedInstance.consentForEvents)
    {
        CLY_LOG_V(@"%s no consent given for events, the timed event will not be ended, key: [%@]", __FUNCTION__, key);
        return;
    }

    CountlyEvent *event = [CountlyPersistency.sharedInstance timedEventForKey:key];

    if (!event)
    {
        CLY_LOG_W(@"%s omitting the call, the timed event was not started or was already ended, key: [%@]", __FUNCTION__, key);
        return;
    }

    NSTimeInterval duration = NSDate.date.timeIntervalSince1970 - event.timestamp;
    [self recordEvent:key segmentation:segmentation count:count sum:sum duration:duration];
}

- (void)cancelEvent:(NSString *)key
{
    CLY_LOG_I(@"%s cancelling a timed event, key: [%@]", __FUNCTION__, key);

    if (!CountlyConsentManager.sharedInstance.consentForEvents)
    {
        CLY_LOG_V(@"%s no consent given for events, the timed event will not be cancelled, key: [%@]", __FUNCTION__, key);
        return;
    }

    CountlyEvent *event = [CountlyPersistency.sharedInstance timedEventForKey:key];

    if (!event)
    {
        CLY_LOG_W(@"%s nothing to cancel, no timed event is running for the key, key: [%@]", __FUNCTION__, key);
        return;
    }

    CLY_LOG_D(@"%s the timed event is cancelled, key: [%@]", __FUNCTION__, key);
}


#pragma mark - Push Notifications
#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_OSX )
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
    CLY_LOG_I(@"%s recording a notification action, buttonIndex: [%ld], payloadProvided: [%@], payloadKeyCount: [%lu]", __FUNCTION__, (long)buttonIndex, userInfo ? @"YES" : @"NO", (unsigned long)userInfo.count);
    CLY_LOG_D(@"%s notification action payload detail, buttonIndex: [%ld], userInfo: [%@]", __FUNCTION__, (long)buttonIndex, userInfo);
    [CountlyPushNotifications.sharedInstance recordActionForNotification:userInfo clickedButtonIndex:buttonIndex];
}

- (void)recordPushNotificationToken
{
    CLY_LOG_I(@"%s sending the push notification token", __FUNCTION__);
    [CountlyPushNotifications.sharedInstance sendToken];
}

- (void)clearPushNotificationToken
{
    CLY_LOG_I(@"%s clearing the push notification token", __FUNCTION__);
    [CountlyPushNotifications.sharedInstance clearToken];
}
#endif
#endif



#pragma mark - Location

- (void)recordLocation:(CLLocationCoordinate2D)location city:(NSString * _Nullable)city ISOCountryCode:(NSString * _Nullable)ISOCountryCode IP:(NSString * _Nullable)IP
{
    CLY_LOG_D(@"%s location detail, latitude: [%f], longitude: [%f], city: [%@], ISOCountryCode: [%@], IP: [%@]", __FUNCTION__, location.latitude, location.longitude, city, ISOCountryCode, IP);
    [CountlyLocationManager.sharedInstance recordLocation:location city:city ISOCountryCode:ISOCountryCode IP:IP];
}

- (void)disableLocationInfo
{
    [CountlyLocationManager.sharedInstance disableLocationInfo];
}



#pragma mark - Crash Reporting

- (void)recordException:(NSException *)exception
{
    CLY_LOG_D(@"%s exception detail, exception: [%@]", __FUNCTION__, exception);
    [CountlyCrashReporter.sharedInstance recordException:exception isFatal:NO stackTrace:nil segmentation:nil];
}

- (void)recordException:(NSException *)exception isFatal:(BOOL)isFatal
{
    CLY_LOG_D(@"%s exception detail with fatality, exception: [%@], isFatal: [%@]", __FUNCTION__, exception, isFatal ? @"YES" : @"NO");
    [CountlyCrashReporter.sharedInstance recordException:exception isFatal:isFatal stackTrace:nil segmentation:nil];
}

- (void)recordException:(NSException *)exception isFatal:(BOOL)isFatal stackTrace:(NSArray *)stackTrace segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_D(@"%s exception detail with stack trace and segmentation, exception: [%@], isFatal: [%@], stackTrace: [%@], segmentation: [%@]", __FUNCTION__, exception, isFatal ? @"YES" : @"NO", stackTrace, segmentation);
    [CountlyCrashReporter.sharedInstance recordException:exception isFatal:isFatal stackTrace:stackTrace segmentation:segmentation];
}

- (void)recordError:(NSString *)errorName stackTrace:(NSArray * _Nullable)stackTrace
{
    CLY_LOG_D(@"%s error detail with stack trace, errorName: [%@], stackTrace: [%@]", __FUNCTION__, errorName, stackTrace);
    [CountlyCrashReporter.sharedInstance recordError:errorName isFatal:NO stackTrace:stackTrace segmentation:nil];
}

- (void)recordError:(NSString *)errorName isFatal:(BOOL)isFatal stackTrace:(NSArray * _Nullable)stackTrace segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_D(@"%s error detail with stack trace and segmentation, errorName: [%@], isFatal: [%@], stackTrace: [%@], segmentation: [%@]", __FUNCTION__, errorName, isFatal ? @"YES" : @"NO", stackTrace, segmentation);
    [CountlyCrashReporter.sharedInstance recordError:errorName isFatal:isFatal stackTrace:stackTrace segmentation:segmentation];
}

- (void)recordHandledException:(NSException *)exception
{
    CLY_LOG_W(@"%s deprecated API used, use 'recordException:' instead", __FUNCTION__);
    CLY_LOG_D(@"%s handled exception detail, exception: [%@]", __FUNCTION__, exception);
    [CountlyCrashReporter.sharedInstance recordException:exception isFatal:NO stackTrace:nil segmentation:nil];
}

- (void)recordHandledException:(NSException *)exception withStackTrace:(NSArray *)stackTrace
{
    CLY_LOG_W(@"%s deprecated API used, use 'recordException:isFatal:stackTrace:segmentation:' instead", __FUNCTION__);
    CLY_LOG_D(@"%s handled exception detail with stack trace, exception: [%@], stackTrace: [%@]", __FUNCTION__, exception, stackTrace);
    [CountlyCrashReporter.sharedInstance recordException:exception isFatal:NO stackTrace:stackTrace segmentation:nil];
}

- (void)recordUnhandledException:(NSException *)exception withStackTrace:(NSArray * _Nullable)stackTrace
{
    CLY_LOG_W(@"%s deprecated API used, use 'recordException:isFatal:stackTrace:segmentation:' with isFatal YES instead", __FUNCTION__);
    CLY_LOG_D(@"%s unhandled exception detail with stack trace, exception: [%@], stackTrace: [%@]", __FUNCTION__, exception, stackTrace);
    [CountlyCrashReporter.sharedInstance recordException:exception isFatal:YES stackTrace:stackTrace segmentation:nil];
}

- (void)recordCrashLog:(NSString *)log
{
    CLY_LOG_I(@"%s recording a crash breadcrumb, length: [%lu]", __FUNCTION__, (unsigned long)log.length);
    CLY_LOG_D(@"%s crash breadcrumb detail, log: [%@]", __FUNCTION__, log);
    [CountlyCrashReporter.sharedInstance log:log];
}

- (void)clearCrashLogs
{
    CLY_LOG_I(@"%s clearing the recorded crash breadcrumbs", __FUNCTION__);
    [CountlyCrashReporter.sharedInstance clearCrashLogs];
}

- (void)crashLog:(NSString *)format, ...
{
    CLY_LOG_W(@"%s this method does nothing, use 'recordCrashLog:' to record a crash breadcrumb", __FUNCTION__);
}
#pragma mark - View Tracking

- (void)recordView:(NSString *)viewName;
{
    CLY_LOG_W(@"%s deprecated API used, use '[views startAutoStoppedView:]' instead", __FUNCTION__);
    [CountlyViewTrackingInternal.sharedInstance startAutoStoppedView:viewName segmentation:nil];
}

- (void)recordView:(NSString *)viewName segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_W(@"%s deprecated API used, use '[views startAutoStoppedView:segmentation:]' instead", __FUNCTION__);
    CLY_LOG_D(@"%s recorded view segmentation detail, viewName: [%@], segmentation: [%@]", __FUNCTION__, viewName, segmentation);

    [CountlyViewTrackingInternal.sharedInstance startAutoStoppedView:viewName segmentation:segmentation];
}

#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_TV )
- (void)addExceptionForAutoViewTracking:(NSString *)exception
{
#if (TARGET_OS_IOS || TARGET_OS_TV)
    [CountlyViewTrackingInternal.sharedInstance addExceptionForAutoViewTracking:exception.copy];
#else
    CLY_LOG_W(@"%s omitting the call, automatic view tracking is not available on this platform, the exception is not added", __FUNCTION__);
#endif
}

- (void)removeExceptionForAutoViewTracking:(NSString *)exception
{
#if (TARGET_OS_IOS || TARGET_OS_TV)
    [CountlyViewTrackingInternal.sharedInstance removeExceptionForAutoViewTracking:exception.copy];
#else
    CLY_LOG_W(@"%s omitting the call, automatic view tracking is not available on this platform, the exception is not removed", __FUNCTION__);
#endif
}

- (void)setIsAutoViewTrackingActive:(BOOL)isAutoViewTrackingActive
{
    CLY_LOG_I(@"%s isAutoViewTrackingActive: [%@]", __FUNCTION__, isAutoViewTrackingActive ? @"YES" : @"NO");
    CLY_LOG_W(@"%s deprecated property used, 'isAutoViewTrackingActive' will be removed in a future release", __FUNCTION__);

#if (TARGET_OS_IOS || TARGET_OS_TV)
    CountlyViewTrackingInternal.sharedInstance.isAutoViewTrackingActive = isAutoViewTrackingActive;
#else
    CLY_LOG_W(@"%s omitting the call, automatic view tracking is not available on this platform, the state change is ignored", __FUNCTION__);
#endif
}

- (BOOL)isAutoViewTrackingActive
{
#if (TARGET_OS_IOS || TARGET_OS_TV)
    CLY_LOG_I(@"%s the auto view tracking state is requested, isActive: [%@]", __FUNCTION__, CountlyViewTrackingInternal.sharedInstance.isAutoViewTrackingActive ? @"YES" : @"NO");
    return CountlyViewTrackingInternal.sharedInstance.isAutoViewTrackingActive;
#else
    CLY_LOG_I(@"%s the auto view tracking state is requested, automatic view tracking is not available on this platform", __FUNCTION__);
    return NO;
#endif
}
#endif
#pragma mark - Star Rating
#if (TARGET_OS_IOS || TARGET_OS_VISION)

- (void)askForStarRating:(void(^)(NSInteger rating))completion
{
    [CountlyFeedbacksInternal.sharedInstance showDialog:completion];
}

- (void)presentFeedbackWidgetWithID:(NSString *)widgetID completionHandler:(void (^)(NSError * error))completionHandler
{
    CLY_LOG_W(@"%s deprecated API used, use 'presentRatingWidgetWithID:completionHandler:' instead", __FUNCTION__);
    
    [self presentRatingWidgetWithID:widgetID closeButtonText:nil completionHandler:completionHandler];
}

- (void)presentRatingWidgetWithID:(NSString *)widgetID completionHandler:(void (^)(NSError * error))completionHandler
{
    [self presentRatingWidgetWithID:widgetID closeButtonText:nil completionHandler:completionHandler];
}

- (void)presentRatingWidgetWithID:(NSString *)widgetID closeButtonText:(NSString * _Nullable)closeButtonText  completionHandler:(void (^)(NSError * __nullable error))completionHandler
{
    [CountlyFeedbacksInternal.sharedInstance presentRatingWidgetWithID:widgetID closeButtonText:closeButtonText completionHandler:completionHandler];
}

- (void)recordRatingWidgetWithID:(NSString *)widgetID rating:(NSInteger)rating email:(NSString * _Nullable)email comment:(NSString * _Nullable)comment userCanBeContacted:(BOOL)userCanBeContacted
{
    CLY_LOG_D(@"%s rating widget answer detail, widgetID: [%@], rating: [%ld], email: [%@], comment: [%@], userCanBeContacted: [%@]", __FUNCTION__, widgetID, (long)rating, email, comment, userCanBeContacted ? @"YES" : @"NO");
    [CountlyFeedbacksInternal.sharedInstance recordRatingWidgetWithID:widgetID rating:rating email:email comment:comment userCanBeContacted:userCanBeContacted];
}

- (void)getFeedbackWidgets:(void (^)(NSArray <CountlyFeedbackWidget *> *feedbackWidgets, NSError * error))completionHandler
{
    CLY_LOG_W(@"%s deprecated API used, use '[feedback getAvailableFeedbackWidgets:]' instead", __FUNCTION__);
    [CountlyFeedbacksInternal.sharedInstance getFeedbackWidgets:completionHandler];
}
#endif
#pragma mark - Attribution

- (void)recordAttributionID:(NSString *)attributionID
{
    CLY_LOG_I(@"%s attributionID: [%@]", __FUNCTION__, attributionID);
    CLY_LOG_W(@"%s deprecated API used, use 'recordDirectAttributionWithCampaignType:andCampaignData:' or 'recordIndirectAttribution:' instead", __FUNCTION__);

    if (!CountlyConsentManager.sharedInstance.consentForAttribution)
    {
        CLY_LOG_V(@"%s no consent given for attribution, the attribution ID will not be recorded", __FUNCTION__);
        return;
    }

    CountlyCommon.sharedInstance.attributionID = attributionID;

    [CountlyConnectionManager.sharedInstance sendAttribution];
}

- (void)recordDirectAttributionWithCampaignType:(NSString *)campaignType andCampaignData:(NSString *)campaignData
{
    CLY_LOG_I(@"%s recording direct attribution, campaignType: [%@], campaignDataLength: [%lu]", __FUNCTION__, campaignType, (unsigned long)campaignData.length);
    CLY_LOG_D(@"%s direct attribution campaign data detail, campaignType: [%@], campaignData: [%@]", __FUNCTION__, campaignType, campaignData);

    if (!CountlyConsentManager.sharedInstance.consentForAttribution)
    {
        CLY_LOG_V(@"%s no consent given for attribution, the direct attribution will not be recorded", __FUNCTION__);
        return;
    }

    if (!campaignType.length)
    {
        CLY_LOG_E(@"%s omitting the call, campaignType must be a non zero length string, campaignType: [%@]", __FUNCTION__, campaignType);
        return;
    }

    if (!campaignData.length)
    {
        CLY_LOG_E(@"%s omitting the call, campaignData must be a non zero length string, campaignType: [%@]", __FUNCTION__, campaignType);
        return;
    }

    if ([campaignType isEqualToString:@"_special_test"])
    {
        [CountlyConnectionManager.sharedInstance sendAttributionData:campaignData];
        return;
    }

    if (![campaignType isEqualToString:@"countly"])
    {
        CLY_LOG_W(@"%s omitting the call, direct attribution is only supported for the 'countly' campaign type, campaignType: [%@]", __FUNCTION__, campaignType);
        return;
    }

    NSError* error = nil;
    NSDictionary* campaignDataDictionary = [NSJSONSerialization JSONObjectWithData:[campaignData cly_dataUTF8] options:0 error:&error];
    if (error)
    {
        CLY_LOG_E(@"%s omitting the call, the campaign data is not valid JSON, error: [%@]", __FUNCTION__, error.localizedDescription);
        return;
    }

    NSString* campaignID = campaignDataDictionary[@"cid"];
    if (!campaignID.length)
    {
        CLY_LOG_E(@"%s omitting the call, the campaign ID in the campaign data is missing or empty", __FUNCTION__);
        return;
    }

    NSString* campaignUserID = campaignDataDictionary[@"cuid"];
    if (!campaignUserID.length)
    {
        CLY_LOG_D(@"%s the campaign user ID in the campaign data is missing or empty, it will be ignored", __FUNCTION__);
    }

    [CountlyConnectionManager.sharedInstance sendDirectAttributionWithCampaignID:campaignID andCampaignUserID:campaignUserID];
}

- (void)recordIndirectAttribution:(NSDictionary<NSString *, NSString *> *)attribution
{
    CLY_LOG_I(@"%s recording indirect attribution, keys: [%@], count: [%lu]", __FUNCTION__, attribution.allKeys, (unsigned long)attribution.count);
    CLY_LOG_D(@"%s indirect attribution parameter detail, attribution: [%@]", __FUNCTION__, attribution);

    if (!CountlyConsentManager.sharedInstance.consentForAttribution)
    {
        CLY_LOG_V(@"%s no consent given for attribution, the indirect attribution will not be recorded", __FUNCTION__);
        return;
    }

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
    CLY_LOG_I(@"%s reading a remote config value, key: [%@]", __FUNCTION__, key);
    CLY_LOG_W(@"%s deprecated API used, use '[remoteConfig getValue:]' instead", __FUNCTION__);
    return [CountlyRemoteConfigInternal.sharedInstance remoteConfigValueForKey:key];
}

- (void)updateRemoteConfigWithCompletionHandler:(void (^)(NSError * error))completionHandler
{
    CLY_LOG_I(@"%s updating all remote config values, callbackProvided: [%@]", __FUNCTION__, completionHandler ? @"YES" : @"NO");
    CLY_LOG_W(@"%s deprecated API used, use '[remoteConfig downloadKeys:]' instead", __FUNCTION__);
    [CountlyRemoteConfigInternal.sharedInstance updateRemoteConfigForKeys:nil omitKeys:nil completionHandler:completionHandler];
}

- (void)updateRemoteConfigOnlyForKeys:(NSArray *)keys completionHandler:(void (^)(NSError * error))completionHandler
{
    CLY_LOG_I(@"%s updating remote config for specific keys, keys: [%@], count: [%lu], callbackProvided: [%@]", __FUNCTION__, keys, (unsigned long)keys.count, completionHandler ? @"YES" : @"NO");
    CLY_LOG_W(@"%s deprecated API used, use '[remoteConfig downloadSpecificKeys:]' instead", __FUNCTION__);
    [CountlyRemoteConfigInternal.sharedInstance updateRemoteConfigForKeys:keys omitKeys:nil completionHandler:completionHandler];
}

- (void)updateRemoteConfigExceptForKeys:(NSArray *)omitKeys completionHandler:(void (^)(NSError * error))completionHandler
{
    CLY_LOG_I(@"%s updating remote config while omitting keys, omitKeys: [%@], count: [%lu], callbackProvided: [%@]", __FUNCTION__, omitKeys, (unsigned long)omitKeys.count, completionHandler ? @"YES" : @"NO");
    CLY_LOG_W(@"%s deprecated API used, use '[remoteConfig downloadOmittingKeys:]' instead", __FUNCTION__);
    [CountlyRemoteConfigInternal.sharedInstance updateRemoteConfigForKeys:nil omitKeys:omitKeys completionHandler:completionHandler];
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
    CLY_LOG_I(@"%s clearing all custom traces", __FUNCTION__);
    [CountlyPerformanceMonitoring.sharedInstance clearAllCustomTraces];
}

- (void)appLoadingFinished
{
    CLY_LOG_I(@"%s app loading finished, recording the app start duration trace", __FUNCTION__);

    long long appLoadEndTime = floor(NSDate.date.timeIntervalSince1970 * 1000);

    [CountlyPerformanceMonitoring.sharedInstance recordAppStartDurationTraceWithStartTime:appLoadStartTime endTime:appLoadEndTime];
}

- (void)halt
{
    [self halt:true];
}

- (void)halt:(BOOL) clearStorage
{
    CLY_LOG_I(@"%s halting the SDK, clearStorage: [%@]", __FUNCTION__, clearStorage ? @"YES" : @"NO");

    // before any singleton goes: a log batch delivery or a connection test report landing in the middle of the
    // resets below would queue a request through a recreated connection manager that has no app key yet
    CountlyCommon.sharedInstance.hasFinishedInit = NO;
    [CountlyConnectionTest.sharedInstance resetInstance];

    // Reset view tracking BEFORE halt: sharedInstance returns nil once hasStarted is false.
    // Dropping its singleton clears the recorded views and the one-way configuration flags,
    // which stopAllViews cannot do because it is gated on view tracking consent.
    [CountlyViewTrackingInternal.sharedInstance resetInstance];

    // Reset health tracker state
    [CountlyHealthTracker.sharedInstance resetInstance];

    // Clear crash logs (safe operation - just clears array or deletes file)
    if (CountlyCrashReporter.sharedInstance)
    {
        [CountlyCrashReporter.sharedInstance clearCrashLogs];
    }

    // Clear custom performance monitoring traces (safe operation - just clears dictionary)
    if (CountlyPerformanceMonitoring.sharedInstance)
    {
        [CountlyPerformanceMonitoring.sharedInstance clearAllCustomTraces];
    }

    // Note: CountlyRemoteConfigInternal.clearAll is not called here because it triggers
    // storeRemoteConfig which involves file I/O and can block during shutdown.
    // Remote config state will persist across halt/start but is cleared via UserDefaults
    // key removal below.

    [CountlyConsentManager.sharedInstance resetInstance];
    [CountlyPersistency.sharedInstance resetInstance:clearStorage];
    [CountlyDeviceInfo.sharedInstance resetInstance];
    [CountlyConnectionManager.sharedInstance resetInstance];
    [CountlyServerConfig.sharedInstance resetInstance];
#if (TARGET_OS_IOS)
    [CountlyContentBuilderInternal.sharedInstance resetInstance];
#endif
    [CountlyUserDetails.sharedInstance clearUserDetails];
    [self resetInstance];
    [CountlyCommon.sharedInstance resetInstance];

    if(clearStorage)
    {
        NSString *appDomain = [[NSBundle mainBundle] bundleIdentifier];
        [NSUserDefaults.standardUserDefaults removePersistentDomainForName:appDomain];

        // halt(true) calls removePersistentDomainForName which doesn't work in xctest
        // environment (different bundle ID), so clear SDK keys manually
        NSArray* sdkKeys = @[
            @"kCountlyServerConfigPersistencyKey",
            @"kCountlyHealthCheckStatePersistencyKey",
            @"kCountlyQueuedRequestsPersistencyKey",
            @"kCountlyStartedEventsPersistencyKey",
            @"kCountlyStoredDeviceIDKey",
            @"kCountlyStoredNSUUIDKey",
            @"kCountlyStarRatingStatusKey",
            @"kCountlyRemoteConfigKey",
            @"kCountlyIsCustomDeviceIDKey",
            @"kCountlyNotificationPermissionKey",
            @"kCountlyWatchParentDeviceIDKey"
        ];
        for (NSString* key in sdkKeys)
        {
            [NSUserDefaults.standardUserDefaults removeObjectForKey:key];
        }

        // Single synchronize after all UserDefaults modifications
        [NSUserDefaults.standardUserDefaults synchronize];
    }
}

- (void)attemptToSendStoredRequests
{
    CLY_LOG_I(@"%s attempting to send the stored requests", __FUNCTION__);
    [CountlyConnectionManager.sharedInstance attemptToSendStoredRequests];
}

#pragma mark - Interfaces
#if (TARGET_OS_IOS || TARGET_OS_VISION)
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

- (CountlyUserDetails *) userProfile
{
    return CountlyUserDetails.sharedInstance;
}

@end
