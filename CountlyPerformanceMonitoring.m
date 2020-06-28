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

+ (instancetype)sharedInstance
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return nil;

    static CountlyPerformanceMonitoring* s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
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
    if (!self.isEnabledOnInitialConfig)
        return;

    if (!CountlyConsentManager.sharedInstance.consentForPerformanceMonitoring)
        return;
    
    COUNTLY_LOG(@"Starting performance monitoring...");

#if (TARGET_OS_OSX)
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationDidBecomeActive:) name:NSApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(applicationWillResignActive:) name:NSApplicationWillResignActiveNotification object:nil];
#elif (TARGET_OS_IOS  || TARGET_OS_TV)
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
#if (TARGET_OS_OSX)
    [NSNotificationCenter.defaultCenter removeObserver:self name:NSApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter removeObserver:self name:NSApplicationWillResignActiveNotification object:nil];
#elif (TARGET_OS_IOS  || TARGET_OS_TV)
    [NSNotificationCenter.defaultCenter removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
#endif

    [self clearAllCustomTraces];
}

#pragma mark ---

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    COUNTLY_LOG(@"applicationDidBecomeActive: (Performance Monitoring)");
    [self startForegroundTrace];
    
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    COUNTLY_LOG(@"applicationWillResignActive: (Performance Monitoring)");
    [self startBackgroundTrace];
}

- (void)startForegroundTrace
{
    [self endBackgroundTrace];

    [self startCustomTrace:kCountlyPMKeyAppInForeground];
}

- (void)endForegroundTrace
{
    [self endCustomTrace:kCountlyPMKeyAppInForeground metrics:nil];
}

- (void)startBackgroundTrace
{
    [self endForegroundTrace];

    [self startCustomTrace:kCountlyPMKeyAppInBackground];
}

- (void)endBackgroundTrace
{
    [self endCustomTrace:kCountlyPMKeyAppInBackground metrics:nil];
}

#pragma mark ---

- (void)recordAppStartDurationTraceWithStartTime:(long long)startTime endTime:(long long)endTime
{
    if (!CountlyConsentManager.sharedInstance.consentForPerformanceMonitoring)
        return;

    if (self.hasAlreadyRecordedAppStartDurationTrace)
    {
        COUNTLY_LOG(@"App start duration trace can be recorded once per app launch. So, it will not be recorded this time!");
        return;
    }

    long long appStartDuration = endTime - startTime;

    COUNTLY_LOG(@"App is loaded and displayed its first view in %lld milliseconds.", appStartDuration);

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
    if (!CountlyConsentManager.sharedInstance.consentForPerformanceMonitoring)
        return;

    if (!traceName.length)
        return;

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

    [CountlyConnectionManager.sharedInstance sendPerformanceMonitoringTrace:[trace cly_JSONify]];
}

- (void)startCustomTrace:(NSString *)traceName
{
    if (!CountlyConsentManager.sharedInstance.consentForPerformanceMonitoring)
        return;

    if (!traceName.length)
        return;

    @synchronized (self.startedCustomTraces)
    {
        if (self.startedCustomTraces[traceName])
        {
            COUNTLY_LOG(@"Custom trace with name '%@' already started!", traceName);
            return;
        }

        NSNumber* startTime = @((long long)(CountlyCommon.sharedInstance.uniqueTimestamp * 1000));
        self.startedCustomTraces[traceName] = startTime;
    }
    
    COUNTLY_LOG(@"Custom trace with name '%@' just started!", traceName);
}

- (void)endCustomTrace:(NSString *)traceName metrics:(NSDictionary *)metrics
{
    if (!CountlyConsentManager.sharedInstance.consentForPerformanceMonitoring)
        return;

    if (!traceName.length)
        return;

    NSNumber* startTime = nil;

    @synchronized (self.startedCustomTraces)
    {
        startTime = self.startedCustomTraces[traceName];
        [self.startedCustomTraces removeObjectForKey:traceName];
    }

    if (!startTime)
    {
        COUNTLY_LOG(@"Custom trace with name '%@' not started yet or cancelled/ended before!", traceName);
        return;
    }

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

    COUNTLY_LOG(@"Custom trace with name '%@' just ended with duration %lld ms.", traceName, duration);

    [CountlyConnectionManager.sharedInstance sendPerformanceMonitoringTrace:[trace cly_JSONify]];    
}

- (void)cancelCustomTrace:(NSString *)traceName
{
    if (!CountlyConsentManager.sharedInstance.consentForPerformanceMonitoring)
        return;

    if (!traceName.length)
        return;

    NSNumber* startTime = nil;

    @synchronized (self.startedCustomTraces)
    {
        startTime = self.startedCustomTraces[traceName];
        [self.startedCustomTraces removeObjectForKey:traceName];
    }

    if (!startTime)
    {
        COUNTLY_LOG(@"Custom trace with name '%@' not started yet or cancelled/ended before!", traceName);
        return;
    }

    COUNTLY_LOG(@"Custom trace with name '%@' cancelled!", traceName);
}

- (void)clearAllCustomTraces
{
    @synchronized (self.startedCustomTraces)
    {
        [self.startedCustomTraces removeAllObjects];
    }
}
@end
