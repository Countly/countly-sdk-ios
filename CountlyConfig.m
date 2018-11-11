// CountlyConfig.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@implementation CountlyConfig

//NOTE: Countly features
#if TARGET_OS_IOS
    NSString* const CLYPushNotifications = @"CLYPushNotifications";
    NSString* const CLYCrashReporting = @"CLYCrashReporting";
    NSString* const CLYAutoViewTracking = @"CLYAutoViewTracking";
#elif TARGET_OS_TV
    NSString* const CLYAutoViewTracking = @"CLYAutoViewTracking";
#elif TARGET_OS_OSX
    NSString* const CLYPushNotifications = @"CLYPushNotifications";
#endif
//NOTE: Disable APM feature until Countly Server completely supports it
// NSString* const CLYAPM = @"CLYAPM";


//NOTE: Device ID options
#if TARGET_OS_IOS
    NSString* const CLYIDFA = @"CLYIDFA";
    NSString* const CLYIDFV = @"CLYIDFV";
    NSString* const CLYOpenUDID = @"CLYOpenUDID";
#elif TARGET_OS_OSX
    NSString* const CLYOpenUDID = @"CLYOpenUDID";
#endif


- (instancetype)init
{
    if (self = [super init])
    {
#if TARGET_OS_WATCH
        self.updateSessionPeriod = 20.0;
        self.eventSendThreshold = 3;
        self.enableAppleWatch = YES;
#else
        self.updateSessionPeriod = 60.0;
        self.eventSendThreshold = 10;
#endif
        self.storedRequestsLimit = 1000;
        self.crashLogLimit = 100;

        self.location = kCLLocationCoordinate2DInvalid;
    }

    return self;
}

@end
