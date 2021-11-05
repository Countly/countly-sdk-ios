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

extern NSString* const kCountlyReservedEventSurvey;
extern NSString* const kCountlyReservedEventNPS;

@interface CountlyFeedbackWidget : NSObject
#if (TARGET_OS_IOS)

@property (nonatomic, readonly) CLYFeedbackWidgetType type;
@property (nonatomic, readonly) NSString* ID;
@property (nonatomic, readonly) NSString* name;
@property (nonatomic, readonly) NSDictionary* data;

/**
 * Modally presents the feedback widget above the top visible view controller.
 * @discussion Calls to this method will be ignored if consent for @c CLYConsentFeedback is not given
 * while @c requiresConsent flag is set on initial configuration.
 */
- (void)present;

/**
 * Modally presents the feedback widget above the top visible view controller and executes given blocks.
 * @discussion Calls to this method will be ignored if consent for @c CLYConsentFeedback is not given while @c requiresConsent flag is set on initial configuration.
 * @param appearBlock Block to be executed when widget is displayed
 * @param dismissBlock Block to be executed when widget is dismissed
 */
- (void)presentWithAppearBlock:(void(^ __nullable)(void))appearBlock andDismissBlock:(void(^ __nullable)(void))dismissBlock;

/**
 * Fetches feedback widget's data to be used for manually presenting it.
 * @discussion When feedback widget's data is fetched successfully, @c completionHandler will be executed with an @c NSDictionary
 * @discussion This @c NSDictionary represents the feedback widget's data and can be used for creating custom feedback widget UI.
 * @discussion Otherwise, @c completionHandler will be executed with an @c NSError.
 * @param completionHandler A completion handler block to be executed when data is fetched successfully or there is an error
 */
- (void)getWidgetData:(void (^)(NSDictionary * __nullable widgetData, NSError * __nullable error))completionHandler;

/**
 * Records manually presented feedback widget's result.
 * @discussion Calls to this method will be ignored if consent for @c CLYConsentFeedback is not given while @c requiresConsent flag is set on initial configuration.
 * @discussion If there is no result available due to user dismissing the feedback widget without completing it, @c result can be passed as @c nil.
 * @param result A dictionary representing result of manually presented feedback widget
 */
- (void)recordResult:(NSDictionary * __nullable)result;

#endif
@end

NS_ASSUME_NONNULL_END
