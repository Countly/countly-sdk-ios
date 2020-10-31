// CountlyFeedbacks.h
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

@interface CountlyFeedbacks : NSObject
#if (TARGET_OS_IOS)
+ (instancetype)sharedInstance;

- (void)showDialog:(void(^)(NSInteger rating))completion;
- (void)checkFeedbackWidgetWithID:(NSString *)widgetID completionHandler:(void (^)(NSError * error))completionHandler;
- (void)checkForStarRatingAutoAsk;

- (void)getFeedbackWidgets:(void (^)(NSArray <CountlyFeedbackWidget *> *feedbackWidgets, NSError *error))completionHandler;

@property (nonatomic) NSString* message;
@property (nonatomic) NSString* dismissButtonTitle;
@property (nonatomic) NSUInteger sessionCount;
@property (nonatomic) BOOL disableAskingForEachAppVersion;
@property (nonatomic, copy) void (^ratingCompletionForAutoAsk)(NSInteger);
#endif
@end
