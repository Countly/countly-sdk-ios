// CountlyViewData.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyViewData.h"
#import "CountlyCommon.h"

@implementation CountlyViewData

- (instancetype)init
{
    if (self = [super init])
    {
    }
    
    return self;
}

- (instancetype)initWithID:(NSString *)viewID viewName:(NSString *)viewName
{
    if (self = [super init])
    {
        self.viewID = viewID;
        self.viewName = viewName;
        self.viewCreationTime = CountlyCommon.sharedInstance.uniqueTimestamp;
        self.viewStartTime = self.viewCreationTime;
        self.viewAccumulatedTime = 0;
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
