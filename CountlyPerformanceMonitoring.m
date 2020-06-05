// CountlyPerformanceMonitoring.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"


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

@end
