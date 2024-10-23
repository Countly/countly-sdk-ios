// CountlyFeedbacksInternal.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@class CountlyFeedbackWidget;

extern NSString* const kCountlyFBKeyPlatform;
extern NSString* const kCountlyFBKeyAppVersion;
extern NSString* const kCountlyFBKeyWidgetID;
extern NSString* const kCountlyFBKeyID;

extern NSString* const kCountlyReservedEventStarRating;

@interface CountlyFeedbacksInternal : NSObject
#if (TARGET_OS_IOS)
+ (instancetype)sharedInstance;

- (void)showDialog:(void(^)(NSInteger rating))completion;
- (void)presentRatingWidgetWithID:(NSString *)widgetID closeButtonText:(NSString *)closeButtonText completionHandler:(void (^)(NSError * error))completionHandler;
- (void)recordRatingWidgetWithID:(NSString *)widgetID rating:(NSInteger)rating email:(NSString *)email comment:(NSString *)comment userCanBeContacted:(BOOL)userCanBeContacted;
- (void)checkForStarRatingAutoAsk;

- (void)getFeedbackWidgets:(void (^)(NSArray <CountlyFeedbackWidget *> *feedbackWidgets, NSError *error))completionHandler;

- (void) presentNPS:(NSString *)nameIDorTag widgetCallback:(WidgetCallback) wigetCallback;

- (void) presentSurvey:(NSString *)nameIDorTag widgetCallback:(WidgetCallback) wigetCallback;

- (void) presentRating:(NSString *)nameIDorTag widgetCallback:(WidgetCallback) wigetCallback;

@property (nonatomic) NSString* message;
@property (nonatomic) NSString* dismissButtonTitle;
@property (nonatomic) NSUInteger sessionCount;
@property (nonatomic) BOOL disableAskingForEachAppVersion;
@property (nonatomic, copy) void (^ratingCompletionForAutoAsk)(NSInteger);
#endif
@end
