// CountlyPerformanceMonitoring.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"


NSString* const kCountlyPMKeyType                   = @"type";
NSString* const kCountlyPMKeyNetwork                = @"network";
NSString* const kCountlyPMKeyDevice                 = @"device";
NSString* const kCountlyPMKeyName                   = @"name";
NSString* const kCountlyPMKeyAPMMetrics             = @"apm_metrics";
NSString* const kCountlyPMKeyResponseTime           = @"response_time";
NSString* const kCountlyPMKeyResponsePayloadSize    = @"response_payload_size";
NSString* const kCountlyPMKeyResponseCode           = @"response_code";
NSString* const kCountlyPMKeyRequestPayloadSize     = @"request_payload_size";
NSString* const kCountlyPMKeyDuration               = @"duration";
NSString* const kCountlyPMKeyStartTime              = @"stz";
NSString* const kCountlyPMKeyEndTime                = @"etz";
NSString* const kCountlyPMKeyAppStart               = @"app_start";
NSString* const kCountlyPMKeyAppInForeground        = @"app_in_foreground";
NSString* const kCountlyPMKeyAppInBackground        = @"app_in_background";


@interface CountlyPerformanceMonitoring ()
@property (nonatomic) NSMutableDictionary* startedCustomTraces;
@property (nonatomic) BOOL hasAlreadyRecordedAppStartDurationTrace;
@end


@implementation CountlyPerformanceMonitoring

BOOL enableAppStartTimeTracking;
BOOL enableManualAppLoadedTrigger;
BOOL enableForegroundBackgroundTracking;

+ (instancetype)sharedInstance
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return nil;

    static CountlyPerformanceMonitoring* s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}


- (void) startWithConfig:(CountlyAPMConfig *) apmConfig
{
    CLY_LOG_I(@"%s apm module starting, enableAppStartTimeTracking: [%@], enableManualAppLoadedTrigger: [%@], enableForegroundBackgroundTracking: [%@]", __FUNCTION__, apmConfig.enableAppStartTimeTracking ? @"YES" : @"NO", apmConfig.enableManualAppLoadedTrigger ? @"YES" : @"NO", apmConfig.enableForegroundBackgroundTracking ? @"YES" : @"NO");

    enableAppStartTimeTracking = apmConfig.enableAppStartTimeTracking;
    enableManualAppLoadedTrigger = apmConfig.enableManualAppLoadedTrigger;
    if(enableAppStartTimeTracking && !enableManualAppLoadedTrigger) {
        CLY_LOG_W(@"%s, Automatic app start tracking is currently not supported, use manual app loaded trigger for now by setting 'config.apm.enableManualAppLoadedTrigger' Then call '[Countly.sharedInstance appLoadingFinished]'", __FUNCTION__);
    }
    enableForegroundBackgroundTracking = apmConfig.enableForegroundBackgroundTracking;
    [self startPerformanceMonitoring];
}

- (instancetype)init
{
    if (self = [super init])
    {
        self.startedCustomTraces = NSMutableDictionary.new;
    }

    return self;
}

#pragma mark ---

- (void)startPerformanceMonitoring
{
    if (!enableForegroundBackgroundTracking)
    {
        CLY_LOG_D(@"%s foreground and background tracking is not enabled in config, observers will not be added", __FUNCTION__);
        return;
    }

    if (!CountlyConsentManager.sharedInstance.consentForPerformanceMonitoring)
    {
        CLY_LOG_V(@"%s no apm consent given, foreground and background tracking is not started", __FUNCTION__);
        return;
    }
    
    CLY_LOG_D(@"%s foreground and background tracking is starting, isInBackground: [%@]", __FUNCTION__, CountlyDeviceInfo.isInBackground ? @"YES" : @"NO");

#if (TARGET_OS_OSX)
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidBecomeActive:) name:NSApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationWillResignActive:) name:NSApplicationWillResignActiveNotification object:nil];
#elif (TARGET_OS_IOS || TARGET_OS_VISION  || TARGET_OS_TV)
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationWillResignActive:) name:UIApplicationWillResignActiveNotification object:nil];
#endif

    if (CountlyDeviceInfo.isInBackground)
        [self startBackgroundTrace];
    else
        [self startForegroundTrace];
}

- (void)stopPerformanceMonitoring
{
    CLY_LOG_D(@"%s foreground and background tracking observers are being removed", __FUNCTION__);

#if (TARGET_OS_OSX)
    [NSNotificationCenter.defaultCenter removeObserver:self name:NSApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter removeObserver:self name:NSApplicationWillResignActiveNotification object:nil];
#elif (TARGET_OS_IOS || TARGET_OS_VISION  || TARGET_OS_TV)
    [NSNotificationCenter.defaultCenter removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
#endif

    [self clearAllCustomTraces];
}

#pragma mark ---

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    CLY_LOG_V(@"%s did become active notification received by the apm module", __FUNCTION__);
    
    if (!enableForegroundBackgroundTracking)
        return;
    
    [self startForegroundTrace];
    
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    CLY_LOG_V(@"%s will resign active notification received by the apm module", __FUNCTION__);
    
    if (!enableForegroundBackgroundTracking)
        return;
    
    [self startBackgroundTrace];
}

- (void)startForegroundTrace
{
    if (!enableForegroundBackgroundTracking)
        return;
    
    [self endBackgroundTrace];

    [self startCustomTrace:kCountlyPMKeyAppInForeground];
}

- (void)endForegroundTrace
{
    if (!enableForegroundBackgroundTracking)
        return;
    
    [self endCustomTrace:kCountlyPMKeyAppInForeground metrics:nil];
}

- (void)startBackgroundTrace
{
    if (!enableForegroundBackgroundTracking)
        return;
    
    [self endForegroundTrace];

    [self startCustomTrace:kCountlyPMKeyAppInBackground];
}

- (void)endBackgroundTrace
{
    if (!enableForegroundBackgroundTracking)
        return;
    [self endCustomTrace:kCountlyPMKeyAppInBackground metrics:nil];
}

#pragma mark ---

- (void)recordAppStartDurationTraceWithStartTime:(long long)startTime endTime:(long long)endTime
{
    CLY_LOG_I(@"%s app start duration trace recording requested, startTime: [%lld], endTime: [%lld]", __FUNCTION__, startTime, endTime);

    if (!CountlyConsentManager.sharedInstance.consentForPerformanceMonitoring)
    {
        CLY_LOG_V(@"%s no apm consent given, app start duration trace is not recorded", __FUNCTION__);
        return;
    }

    if(!enableAppStartTimeTracking || !enableManualAppLoadedTrigger)
    {
        CLY_LOG_D(@"%s app start duration trace is dropped, set 'enableAppStartTimeTracking' and 'enableManualAppLoadedTrigger' in config to record it", __FUNCTION__);
        return;
    }
    
    if (self.hasAlreadyRecordedAppStartDurationTrace)
    {
        CLY_LOG_W(@"%s app start duration trace is dropped, it can only be recorded once per app launch", __FUNCTION__);
        return;
    }

    long long appStartDuration = endTime - startTime;

    if (appStartDuration < 0)
        CLY_LOG_W(@"%s app start duration is negative, it will still be recorded, duration: [%lld]", __FUNCTION__, appStartDuration);

    CLY_LOG_D(@"%s app start trace recorded, traceName: [%@], duration: [%lld] ms", __FUNCTION__, kCountlyPMKeyAppStart, appStartDuration);

    NSDictionary* metrics =
    @{
        kCountlyPMKeyDuration: @(appStartDuration),
    };

    NSDictionary* trace =
    @{
        kCountlyPMKeyType: kCountlyPMKeyDevice,
        kCountlyPMKeyName: kCountlyPMKeyAppStart,
        kCountlyPMKeyAPMMetrics: metrics,
        kCountlyPMKeyStartTime: @(startTime),
        kCountlyPMKeyEndTime: @(endTime),
    };

    [CountlyConnectionManager.sharedInstance sendPerformanceMonitoringTrace:[trace cly_JSONify]];

    self.hasAlreadyRecordedAppStartDurationTrace = YES;
}

- (void)recordNetworkTrace:(NSString *)traceName
        requestPayloadSize:(NSInteger)requestPayloadSize
       responsePayloadSize:(NSInteger)responsePayloadSize
        responseStatusCode:(NSInteger)responseStatusCode
                 startTime:(long long)startTime
                   endTime:(long long)endTime
{
    CLY_LOG_I(@"%s network trace recording requested, traceName: [%@], requestPayloadSize: [%ld], responsePayloadSize: [%ld], responseStatusCode: [%ld]", __FUNCTION__, traceName, (long)requestPayloadSize, (long)responsePayloadSize, (long)responseStatusCode);

    if (!CountlyConsentManager.sharedInstance.consentForPerformanceMonitoring)
    {
        CLY_LOG_V(@"%s no apm consent given, network trace is not recorded", __FUNCTION__);
        return;
    }

    if (!traceName.length)
    {
        CLY_LOG_E(@"%s network trace is dropped, trace name is empty or nil", __FUNCTION__);
        return;
    }

    if (endTime - startTime < 0)
        CLY_LOG_W(@"%s network trace response time is negative, traceName: [%@], responseTime: [%lld] ms", __FUNCTION__, traceName, endTime - startTime);

    traceName = [traceName cly_truncatedKey:@"Network trace name"];

    NSDictionary* metrics =
    @{
        kCountlyPMKeyRequestPayloadSize: @(requestPayloadSize),
        kCountlyPMKeyResponseTime: @(endTime - startTime),
        kCountlyPMKeyResponseCode: @(responseStatusCode),
        kCountlyPMKeyResponsePayloadSize: @(responsePayloadSize),
    };

    NSDictionary* trace =
    @{
        kCountlyPMKeyType: kCountlyPMKeyNetwork,
        kCountlyPMKeyName: traceName,
        kCountlyPMKeyAPMMetrics: metrics,
        kCountlyPMKeyStartTime: @(startTime),
        kCountlyPMKeyEndTime: @(endTime),
    };

    CLY_LOG_D(@"%s network trace recorded, traceName: [%@], responseTime: [%lld] ms", __FUNCTION__, traceName, endTime - startTime);

    [CountlyConnectionManager.sharedInstance sendPerformanceMonitoringTrace:[trace cly_JSONify]];
}

- (void)startCustomTrace:(NSString *)traceName
{
    CLY_LOG_I(@"%s custom trace start requested, traceName: [%@]", __FUNCTION__, traceName);

    if (!CountlyConsentManager.sharedInstance.consentForPerformanceMonitoring)
    {
        CLY_LOG_V(@"%s no apm consent given, custom trace is not started", __FUNCTION__);
        return;
    }

    if (!traceName.length)
    {
        CLY_LOG_E(@"%s custom trace start is dropped, trace name is empty or nil", __FUNCTION__);
        return;
    }

    NSUInteger runningTraceCount = 0;

    @synchronized (self.startedCustomTraces)
    {
        if (self.startedCustomTraces[traceName])
        {
            CLY_LOG_W(@"%s custom trace start is ignored, a trace with the same name is already running, traceName: [%@]", __FUNCTION__, traceName);
            return;
        }

        NSNumber* startTime = @((long long)(CountlyCommon.sharedInstance.uniqueTimestamp * 1000));
        self.startedCustomTraces[traceName] = startTime;
        runningTraceCount = self.startedCustomTraces.count;
    }

    CLY_LOG_D(@"%s custom trace started, traceName: [%@], runningTraceCount: [%lu]", __FUNCTION__, traceName, (unsigned long)runningTraceCount);
}

- (void)endCustomTrace:(NSString *)traceName metrics:(NSDictionary *)metrics
{
    CLY_LOG_I(@"%s custom trace end requested, traceName: [%@], metricCount: [%lu]", __FUNCTION__, traceName, (unsigned long)metrics.count);

    if (!CountlyConsentManager.sharedInstance.consentForPerformanceMonitoring)
    {
        CLY_LOG_V(@"%s no apm consent given, custom trace is not ended", __FUNCTION__);
        return;
    }

    if (!traceName.length)
    {
        CLY_LOG_E(@"%s custom trace end is dropped, trace name is empty or nil", __FUNCTION__);
        return;
    }

    NSNumber* startTime = nil;

    @synchronized (self.startedCustomTraces)
    {
        startTime = self.startedCustomTraces[traceName];
        [self.startedCustomTraces removeObjectForKey:traceName];
    }

    if (!startTime)
    {
        CLY_LOG_W(@"%s custom trace end is a no-op, no running trace with this name, traceName: [%@]", __FUNCTION__, traceName);
        return;
    }

    traceName = [traceName cly_truncatedKey:@"Custom trace name"];
    NSDictionary* metricsTruncated = [metrics cly_truncated:@"Custom trace metric"];
    metrics = [metricsTruncated cly_limited:@"Custom trace metric"];

    NSNumber* endTime = @((long long)(CountlyCommon.sharedInstance.uniqueTimestamp * 1000));

    NSMutableDictionary* mutableMetrics = metrics.mutableCopy;
    if (!mutableMetrics)
        mutableMetrics = NSMutableDictionary.new;

    long long duration = endTime.longLongValue - startTime.longLongValue;
    mutableMetrics[kCountlyPMKeyDuration] = @(duration);

    NSDictionary* trace =
    @{
        kCountlyPMKeyType: kCountlyPMKeyDevice,
        kCountlyPMKeyName: traceName,
        kCountlyPMKeyAPMMetrics: mutableMetrics,
        kCountlyPMKeyStartTime: startTime,
        kCountlyPMKeyEndTime: endTime,
    };

    if (duration < 0)
        CLY_LOG_W(@"%s custom trace duration is negative, it will still be recorded, traceName: [%@], duration: [%lld]", __FUNCTION__, traceName, duration);

    CLY_LOG_D(@"%s custom trace ended, traceName: [%@], duration: [%lld] ms, metricCount: [%lu]", __FUNCTION__, traceName, duration, (unsigned long)mutableMetrics.count);

    [CountlyConnectionManager.sharedInstance sendPerformanceMonitoringTrace:[trace cly_JSONify]];    
}

- (void)cancelCustomTrace:(NSString *)traceName
{
    CLY_LOG_I(@"%s custom trace cancellation requested, traceName: [%@]", __FUNCTION__, traceName);

    if (!CountlyConsentManager.sharedInstance.consentForPerformanceMonitoring)
    {
        CLY_LOG_V(@"%s no apm consent given, custom trace is not cancelled", __FUNCTION__);
        return;
    }

    if (!traceName.length)
    {
        CLY_LOG_E(@"%s custom trace cancellation is dropped, trace name is empty or nil", __FUNCTION__);
        return;
    }

    NSNumber* startTime = nil;
    NSUInteger runningTraceCount = 0;

    @synchronized (self.startedCustomTraces)
    {
        startTime = self.startedCustomTraces[traceName];
        [self.startedCustomTraces removeObjectForKey:traceName];
        runningTraceCount = self.startedCustomTraces.count;
    }

    if (!startTime)
    {
        CLY_LOG_D(@"%s custom trace cancellation is a no-op, no running trace with this name, traceName: [%@]", __FUNCTION__, traceName);
        return;
    }

    CLY_LOG_D(@"%s custom trace cancelled, its duration is discarded, traceName: [%@], startTime: [%lld], runningTraceCount: [%lu]", __FUNCTION__, traceName, startTime.longLongValue, (unsigned long)runningTraceCount);
}

- (void)clearAllCustomTraces
{
    @synchronized (self.startedCustomTraces)
    {
        CLY_LOG_D(@"%s clearing all running custom traces, runningTraceCount: [%lu]", __FUNCTION__, (unsigned long)self.startedCustomTraces.count);
        [self.startedCustomTraces removeAllObjects];
    }
}
@end
