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
NSString* const kCountlyPMKeyStartTime              = @"stz";
NSString* const kCountlyPMKeyEndTime                = @"etz";


@interface CountlyPerformanceMonitoring ()
@property (nonatomic) NSMutableDictionary* startedCustomTraces;
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

    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
        return;

    COUNTLY_LOG(@"Starting performance monitoring...");
}

#pragma mark ---

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

    NSDictionary* trace =
    @{
        kCountlyPMKeyType: kCountlyPMKeyDevice,
        kCountlyPMKeyName: traceName,
        kCountlyPMKeyAPMMetrics: metrics,
        kCountlyPMKeyStartTime: startTime,
        kCountlyPMKeyEndTime: endTime,
    };

    [CountlyConnectionManager.sharedInstance sendPerformanceMonitoringTrace:[trace cly_JSONify]];
}

- (void)cancelCustomTrace:(NSString *)traceName
{
    if (!CountlyConsentManager.sharedInstance.consentForPerformanceMonitoring)
        return;

    if (!traceName.length)
        return;
}

@end
