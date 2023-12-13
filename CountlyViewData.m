// CountlyViewData.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyViewData.h"
#import "CountlyCommon.h"

@implementation CountlyViewData

- (instancetype)initWithID:(NSString *)viewID viewName:(NSString *)viewName
{
    if (self = [super init])
    {
        self.viewID = viewID;
        self.viewName = viewName;
        self.viewStartTime = CountlyCommon.sharedInstance.uniqueTimestamp;
        self.isAutoStoppedView = false;
        self.isAutoPaused = false;
    }
    
    return self;
}

- (NSTimeInterval)duration
{
    NSTimeInterval duration = NSDate.date.timeIntervalSince1970 - self.viewStartTime;
    return duration;
}

- (void)autoPauseView
{
    if (self.viewStartTime) // To check that view is not paused already manually
    {
        self.isAutoPaused = true;
    }
    [self pauseView];
}

- (void)pauseView
{
    if (self.viewStartTime)
    {
        self.viewStartTime = 0;
    }
}

- (void)resumeView
{
    self.isAutoPaused = false;
    self.viewStartTime = CountlyCommon.sharedInstance.uniqueTimestamp;
}



@end
