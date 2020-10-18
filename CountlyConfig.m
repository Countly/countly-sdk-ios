// CountlyConfig.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@implementation CountlyConfig

//NOTE: Countly features
#if (TARGET_OS_IOS)
CLYFeature const CLYPushNotifications   = @"CLYPushNotifications";
CLYFeature const CLYCrashReporting      = @"CLYCrashReporting";
CLYFeature const CLYAutoViewTracking    = @"CLYAutoViewTracking";
#elif (TARGET_OS_WATCH)
CLYFeature const CLYCrashReporting      = @"CLYCrashReporting";
#elif (TARGET_OS_TV)
CLYFeature const CLYCrashReporting      = @"CLYCrashReporting";
CLYFeature const CLYAutoViewTracking    = @"CLYAutoViewTracking";
#elif (TARGET_OS_OSX)
CLYFeature const CLYPushNotifications   = @"CLYPushNotifications";
CLYFeature const CLYCrashReporting      = @"CLYCrashReporting";
#endif


//NOTE: Device ID options
NSString* const CLYDefaultDeviceID = @""; //NOTE: It will be overridden to default device ID mechanism, depending on platform.
NSString* const CLYTemporaryDeviceID = @"CLYTemporaryDeviceID";

//NOTE: Device ID Types
CLYDeviceIDType const CLYDeviceIDTypeCustom     = @"CLYDeviceIDTypeCustom";
CLYDeviceIDType const CLYDeviceIDTypeTemporary  = @"CLYDeviceIDTypeTemporary";
CLYDeviceIDType const CLYDeviceIDTypeIDFV       = @"CLYDeviceIDTypeIDFV";
CLYDeviceIDType const CLYDeviceIDTypeNSUUID     = @"CLYDeviceIDTypeNSUUID";

//NOTE: Legacy device ID options. They will fallback to default device ID.
NSString* const CLYIDFA = CLYDefaultDeviceID;
NSString* const CLYIDFV = CLYDefaultDeviceID;
NSString* const CLYOpenUDID = CLYDefaultDeviceID;

- (instancetype)init
{
    if (self = [super init])
    {
#if (TARGET_OS_WATCH)
        self.updateSessionPeriod = 20.0;
        self.eventSendThreshold = 3;
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
