// CountlyConfig.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyConfig.h"

@implementation CountlyConfig
#if TARGET_OS_IOS
NSString* const CLYMessaging = @"CLYMessaging";
NSString* const CLYCrashReporting = @"CLYCrashReporting";
#endif
NSString* const CLYAPM = @"CLYAPM";


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