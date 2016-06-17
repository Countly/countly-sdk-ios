// CountlyConfig.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@implementation CountlyConfig

//NOTE: Countly features
#if TARGET_OS_IOS
    NSString* const CLYMessaging = @"CLYMessaging";
    NSString* const CLYCrashReporting = @"CLYCrashReporting";
    NSString* const CLYAutoViewTracking = @"CLYAutoViewTracking";
#endif
    NSString* const CLYAPM = @"CLYAPM";


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
        //NOTE: For checking if launchOptions is set when CLYMessaging feature is used.
        self.launchOptions = @{@"CLYAssertion":@"forLaunchOptions"};

#if TARGET_OS_WATCH
        self.updateSessionPeriod = 20.0;
        self.eventSendThreshold = 3;
#else
        self.updateSessionPeriod = 60.0;
        self.eventSendThreshold = 10;
#endif
        self.storedRequestsLimit = 1000;

        self.location = kCLLocationCoordinate2DInvalid;
    }

    return self;
}

@end