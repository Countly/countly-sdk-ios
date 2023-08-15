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
        self.viewAccumulatedTime = 0;
        self.isAutoStoppedView = false;
    }
    
    return self;
}

- (NSTimeInterval)duration
{
    NSTimeInterval duration = NSDate.date.timeIntervalSince1970 - self.viewStartTime + self.viewAccumulatedTime;
    return duration;
}

- (void)pauseView
{
    if (self.viewStartTime)
    {
        self.viewAccumulatedTime = NSDate.date.timeIntervalSince1970 - self.viewStartTime + self.viewAccumulatedTime;
        self.viewStartTime = 0;
    }
}

- (void)resumeView
{
    self.viewStartTime = CountlyCommon.sharedInstance.uniqueTimestamp;
}



@end
