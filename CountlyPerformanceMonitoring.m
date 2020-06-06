// CountlyPerformanceMonitoring.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"


NSString* const kCountlyPMKeyType                   = @"type";
NSString* const kCountlyPMKeyNetwork                = @"network";
NSString* const kCountlyPMKeyName                   = @"name";
NSString* const kCountlyPMKeyAPMMetrics             = @"apm_metrics";
NSString* const kCountlyPMKeyResponseTime           = @"response_time";
NSString* const kCountlyPMKeyResponsePayloadSize    = @"response_payload_size";
NSString* const kCountlyPMKeyResponseCode           = @"response_code";
NSString* const kCountlyPMKeyRequestPayloadSize     = @"request_payload_size";
NSString* const kCountlyPMKeyStartTime              = @"stz";
NSString* const kCountlyPMKeyEndTime                = @"etz";


@interface CountlyPerformanceMonitoring ()

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

@end
