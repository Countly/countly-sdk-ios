// CountlyFeedbackWidget.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSString* CLYFeedbackWidgetType NS_EXTENSIBLE_STRING_ENUM;
extern CLYFeedbackWidgetType const CLYFeedbackWidgetTypeSurvey;
extern CLYFeedbackWidgetType const CLYFeedbackWidgetTypeNPS;


@interface CountlyFeedbackWidget : NSObject
#if (TARGET_OS_IOS)

@property (nonatomic, readonly) CLYFeedbackWidgetType type;
@property (nonatomic, readonly) NSString* ID;
@property (nonatomic, readonly) NSString* name;

- (void)present;

#endif
@end

NS_ASSUME_NONNULL_END
