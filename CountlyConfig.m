// CountlyConfig.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@implementation CountlyConfig

//Countly features
#if TARGET_OS_IOS
    NSString* const CLYMessaging = @"CLYMessaging";
    NSString* const CLYCrashReporting = @"CLYCrashReporting";
#endif
    NSString* const CLYAPM = @"CLYAPM";


//Device ID options
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
        //For checking if launchOptions is set when CLYMessaging feature is used.
        self.launchOptions = @{@"CLYAssertion":@"forLaunchOptions"};
    }

    return self;
}

@end