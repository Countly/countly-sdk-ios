// CountlyWebViewController.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#if (TARGET_OS_IOS || TARGET_OS_VISION)
  #import <UIKit/UIKit.h>
#endif

#import "CountlyCommon.h"

NS_ASSUME_NONNULL_BEGIN
#if (TARGET_OS_IOS || TARGET_OS_VISION)
@interface                           CountlyWebViewController : UIViewController
@property(nonatomic, strong) UIView *contentView;

/// Called once an interface size change has settled. The SDK's rotation hook.
@property(nonatomic, copy, nullable) void (^sizeChangeHandler)(CGSize newSize);

- (void)updatePlacementRespectToSafeAreas;
@end
#endif
NS_ASSUME_NONNULL_END
