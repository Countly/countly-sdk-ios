//  CountlyContentConfig.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface CountlyContentConfig ()
#if (TARGET_OS_IOS)
@property (nonatomic) ContentCallback contentCallback;
@property (nonatomic) NSUInteger zoneTimerInterval;
#endif
@end

@implementation CountlyContentConfig

- (instancetype)init
{
    if (self = [super init])
    {
    }
    
    return self;
}

#if (TARGET_OS_IOS)
-(void)setGlobalContentCallback:(ContentCallback) callback
{
    self.contentCallback = callback;
}

- (ContentCallback) getGlobalContentCallback
{
    return self.contentCallback;
}


-(void)setZoneTimerInterval:(NSUInteger)zoneTimerIntervalSeconds
{
    if (zoneTimerIntervalSeconds > 15) {
        self.zoneTimerInterval = zoneTimerIntervalSeconds;
    }
}

- (NSUInteger) getZoneTimerInterval
{
    return self.zoneTimerInterval;
}
#endif

@end
