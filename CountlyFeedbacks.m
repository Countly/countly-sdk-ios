//  CountlyFeedbacks.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.
//

#import "CountlyFeedbacks.h"
#import "CountlyCommon.h"

@implementation CountlyFeedbacks
#if (TARGET_OS_IOS || TARGET_OS_VISION)
+ (instancetype)sharedInstance
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return nil;
    
    static CountlyFeedbacks* s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    
    return self;
}

- (void)enterContentZone:(NSArray<NSString *> *)tags
{
    CLY_LOG_I(@"%s content zone entry requested, tagCount: [%lu]", __FUNCTION__, (unsigned long)tags.count);
    [CountlyContentBuilderInternal.sharedInstance enterContentZone:tags];
}

- (void)presentNPS {
    [self presentNPS:nil widgetCallback:nil];
}

- (void)presentNPS:(NSString *)nameIDorTag {
    [self presentNPS:nameIDorTag widgetCallback:nil];
}

- (void) presentNPS:(NSString *)nameIDorTag widgetCallback:(WidgetCallback) widgetCallback {
    CLY_LOG_I(@"%s NPS widget requested, nameIDorTag: [%@], callbackProvided: [%@]", __FUNCTION__, nameIDorTag, (widgetCallback != nil) ? @"YES" : @"NO");
    [CountlyFeedbacksInternal.sharedInstance presentNPS:nameIDorTag widgetCallback:widgetCallback];
}

- (void)presentSurvey {
    [self presentSurvey:nil widgetCallback:nil];
}

- (void)presentSurvey:(NSString *)nameIDorTag {
    [self presentSurvey:nameIDorTag widgetCallback:nil];
}

- (void) presentSurvey:(NSString *)nameIDorTag widgetCallback:(WidgetCallback) widgetCallback {
    CLY_LOG_I(@"%s survey widget requested, nameIDorTag: [%@], callbackProvided: [%@]", __FUNCTION__, nameIDorTag, (widgetCallback != nil) ? @"YES" : @"NO");
    [CountlyFeedbacksInternal.sharedInstance presentSurvey:nameIDorTag widgetCallback:widgetCallback];
}

- (void)presentRating {
    [self presentRating:nil widgetCallback:nil];
}

- (void)presentRating:(NSString *)nameIDorTag {
    [self presentRating:nameIDorTag widgetCallback:nil];
}

- (void) presentRating:(NSString *)nameIDorTag widgetCallback:(WidgetCallback) widgetCallback {
    CLY_LOG_I(@"%s rating widget requested, nameIDorTag: [%@], callbackProvided: [%@]", __FUNCTION__, nameIDorTag, (widgetCallback != nil) ? @"YES" : @"NO");
    [CountlyFeedbacksInternal.sharedInstance presentRating:nameIDorTag widgetCallback:widgetCallback];
}

- (void)getAvailableFeedbackWidgets:(void (^)(NSArray <CountlyFeedbackWidget *> *feedbackWidgets, NSError * error))completionHandler
{
    CLY_LOG_I(@"%s available feedback widgets requested, completionHandlerProvided: [%@]", __FUNCTION__, (completionHandler != nil) ? @"YES" : @"NO");
    [CountlyFeedbacksInternal.sharedInstance getFeedbackWidgets:completionHandler];
}
#endif
@end
