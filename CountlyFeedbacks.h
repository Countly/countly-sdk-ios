//  CountlyFeedbacks.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.
//

#import <Foundation/Foundation.h>
#import "CountlyConfig.h"
#import "CountlyFeedbackWidget.h"

@interface CountlyFeedbacks: NSObject
#if (TARGET_OS_IOS)
+ (instancetype)sharedInstance;

- (void) presentNPS;
- (void) presentNPS:(NSString *)nameIDorTag;
- (void) presentNPS:(NSString *)nameIDorTag widgetCallback:(WidgetCallback) widgetCallback;

- (void) presentSurvey;
- (void) presentSurvey:(NSString *)nameIDorTag;
- (void) presentSurvey:(NSString *)nameIDorTag widgetCallback:(WidgetCallback) widgetCallback;

- (void) presentRating;
- (void) presentRating:(NSString *)nameIDorTag;
- (void) presentRating:(NSString *)nameIDorTag widgetCallback:(WidgetCallback) widgetCallback;

- (void)getAvailableFeedbackWidgets:(void (^)(NSArray <CountlyFeedbackWidget *> *feedbackWidgets, NSError * error))completionHandler;
#endif
@end
