//  CountlyAPMConfig.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyAPMConfig.h"

@implementation CountlyAPMConfig

long long appLoadStartTimeOverride;

- (instancetype)init
{
    if (self = [super init])
    {
    }
    
    return self;
}

- (void)setAppStartTimestampOverride:(long long)appStartTimeTimestamp
{
    appLoadStartTimeOverride = appStartTimeTimestamp;
}

- (long long)getAppStartTimestampOverride
{
    return appLoadStartTimeOverride;
}
@end
