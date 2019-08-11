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


//NOTE: Device ID options
NSString* const CLYDefaultDeviceID = @""; //NOTE: It will be overridden to default device ID mechanism, depending on platform.
NSString* const CLYTemporaryDeviceID = @"CLYTemporaryDeviceID";

//NOTE: Legacy device ID options. They will fallback to default device ID.
NSString* const CLYIDFA = CLYDefaultDeviceID;
NSString* const CLYIDFV = CLYDefaultDeviceID;
NSString* const CLYOpenUDID = CLYDefaultDeviceID;

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

        self.URLSessionConfiguration = NSURLSessionConfiguration.defaultSessionConfiguration;
    }

    return self;
}

@end
