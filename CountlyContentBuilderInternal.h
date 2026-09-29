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
- (void)refreshContentZoneJTE;
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
 * Puts the global content segmentation underneath the segmentation a content or feedback widget
 * event built for itself. The event's own entries win, so a global value can never replace a key
 * like "widget_id" or an answer reported by a feedback widget.
 *
 * @param eventSegmentation the segmentation the event built for itself
 * @return the merged segmentation, or eventSegmentation itself when there is nothing to add
 */
- (NSDictionary *)mergeGlobalContentSegmentationInto:(NSDictionary *)eventSegmentation;

#endif
NS_ASSUME_NONNULL_END
@end

