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

#endif
NS_ASSUME_NONNULL_END
@end

