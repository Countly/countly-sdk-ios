// CountlyContent.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>
#if (TARGET_OS_IOS || TARGET_OS_VISION)
#import <UIKit/UIKit.h>
#endif
#import "CountlyCommon.h"
NS_ASSUME_NONNULL_BEGIN

extern NSString* const kCountlyContentTriggerKeySession;
extern NSString* const kCountlyContentTriggerKeyUserProperties;
extern NSString* const kCountlyContentTriggerKeyCrash;
extern NSString* const kCountlyContentTriggerKeyConsent;

@interface CountlyContentBuilderInternal: NSObject
#if (TARGET_OS_IOS || TARGET_OS_VISION)
@property (nonatomic, strong) NSArray<NSString *> *currentTags;
@property (nonatomic, assign) NSTimeInterval zoneTimerInterval;
@property (nonatomic) ContentCallback contentCallback;
@property (nonatomic, assign) WebViewDisplayOption webViewDisplayOption;
@property (nonatomic, assign) BOOL enableContentReloadOnStall;
@property (nonatomic, assign) NSTimeInterval contentReloadOnStallTimeout; // seconds
@property (nonatomic, assign) BOOL disableZoom;
@property (nonatomic, assign) BOOL disableRotation;
@property (nonatomic, copy, nullable) ContentURLHandler contentURLHandler;
@property (nonatomic, assign) int contentInitialDelay;

+ (instancetype)sharedInstance;

- (void)enterContentZone:(NSArray<NSString *> *)tags;
- (void)exitContentZone;
/// Resets retrieval state without closing displayed content, unlike exitContentZone.
- (void)clearContentState;
- (void)resetInstance;
- (void)changeContent:(NSArray<NSString *> *)tags;
- (void)refreshContentZone;

/**
 * Checks whether something the SDK recorded is a content trigger and, when it is, sends the queued requests and asks
 * for content right away instead of waiting for the content zone timer. Can be called on any thread.
 *
 * @param key the event key as the app passed it, or one of the kCountlyContentTriggerKey keys
 * @param viewName the view name as the app passed it, for a view event
 * @param viewEnd NO for the event recorded when a view starts, YES for the one recorded when it ends
 * @param properties the user properties a user details request sends, for kCountlyContentTriggerKeyUserProperties
 * @param customEvent YES for an event of the app, NO for one the SDK records itself
 */
- (void)onContentTriggerWithKey:(NSString *)key viewName:(nullable NSString *)viewName viewEnd:(BOOL)viewEnd properties:(nullable NSArray<NSString *> *)properties customEvent:(BOOL)customEvent;

/**
 * Called when the behavior settings answer of this run arrived, or when none will arrive. What was recorded before it
 * and the settings in use did not list is checked again, so that content for a first session is still asked for.
 *
 * @param answered YES when an answer arrived and was applied
 * @param enterContentZone YES when the answer of a first start has "ecz" on, so the SDK enters the content zone now
 */
- (void)behaviorSettingsSettled:(BOOL)answered enterContentZone:(BOOL)enterContentZone;

/**
 * Sets the zone timer interval, and restarts the zone timer with it when the content zone is entered.
 *
 * @param zoneTimerInterval the interval in seconds
 */
- (void)updateZoneTimerInterval:(NSTimeInterval)zoneTimerInterval;
- (void)previewContent:(NSString *)contentId;

/**
 * Sanitizes the given segmentation and makes it the segmentation added to every content and
 * feedback widget event. It is held in memory only, so it survives a session ending and a new one
 * starting and is gone after an app restart.
 *
 * @param segmentation the dictionary given by the developer, 'nil' or empty clears the stored one
 */
- (void)setGlobalContentSegmentation:(NSDictionary<NSString *, id> * _Nullable)segmentation;

/**
 * Puts the global content segmentation underneath the segmentation a content event built for itself.
 * The event's own entries win. When both together exceed the SDK segmentation value limit, global
 * entries are dropped first, so the limit never trims the event's own.
 *
 * @param eventSegmentation the segmentation the event built for itself
 * @return the merged segmentation, or eventSegmentation itself when there is nothing to add
 */
- (NSDictionary *)mergeGlobalContentSegmentationInto:(NSDictionary *)eventSegmentation;

/**
 * The global content segmentation as feedback widgets carry it: without the keys the server reads as a
 * widget answer or uses to route a widget event ("closed", "shown", "rating", "comment", "email",
 * "contactMe", "widget_id", "platform", "app_version", "campaign_id" and survey answer keys), since a
 * global value under one of those names would turn a dismissal into an answer or discard a real answer.
 *
 * @return the remaining segmentation, empty when nothing is left
 */
- (NSDictionary *)globalContentSegmentationForFeedbackWidget;

/**
 * Puts the feedback widget form of the global content segmentation underneath the segmentation a feedback
 * widget event built for itself. The event's own entries win. Widget events are not trimmed to the SDK
 * segmentation value limit, which would cut survey answers.
 *
 * @param eventSegmentation the segmentation the event built for itself
 * @return the merged segmentation, or eventSegmentation itself when there is nothing to add
 */
- (NSDictionary *)mergeGlobalContentSegmentationIntoFeedbackWidgetEvent:(NSDictionary *)eventSegmentation;

#endif
NS_ASSUME_NONNULL_END
@end

