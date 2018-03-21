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
#endif
//NOTE: Disable APM feature until server completely supports it
// NSString* const CLYAPM = @"CLYAPM";


//NOTE: Device ID options
#if TARGET_OS_IOS
    NSString* const CLYIDFA = @"CLYIDFA";
    NSString* const CLYIDFV = @"CLYIDFV";
    NSString* const CLYOpenUDID = @"CLYOpenUDID";
#elif TARGET_OS_OSX
    NSString* const CLYOpenUDID = @"CLYOpenUDID";
#endif


//NOTE: Consent Features
NSString* const CLYConsentSessions             = @"sessions";
NSString* const CLYConsentEvents               = @"events";
NSString* const CLYConsentUserDetails          = @"users";
NSString* const CLYConsentCrashReporting       = @"crashes";
NSString* const CLYConsentPushNotifications    = @"push";
NSString* const CLYConsentViewTracking         = @"views";
NSString* const CLYConsentAttribution          = @"attribution";
NSString* const CLYConsentStarRating           = @"star-rating";
NSString* const CLYConsentAppleWatch           = @"accessory-devices";


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

        self.location = kCLLocationCoordinate2DInvalid;
    }

    return self;
}

@end
