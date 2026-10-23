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
        self.viewStartTime = CountlyCommon.sharedInstance.monotonicTime;
        self.isAutoStoppedView = false;
        self.willStartAgain = false;
    }
    
    return self;
}

- (NSInteger)duration
{
    NSTimeInterval duration = CountlyCommon.sharedInstance.monotonicTime - self.viewStartTime;
    return (NSInteger)round(duration); // Rounds to the nearest integer, to fix long value converted to 0 on server side.
}

- (void)pauseView
{
    if (self.viewStartTime)
    {
        // For safe side we have set the value to current time stamp instead of 0 when pausing the view, as setting it to 0 could result in an invalid duration value.
        self.viewStartTime = CountlyCommon.sharedInstance.monotonicTime;
    }
}

- (void)resumeView
{
    self.viewStartTime = CountlyCommon.sharedInstance.monotonicTime;
}



@end
