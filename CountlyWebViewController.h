// CountlyWebViewController.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#if (TARGET_OS_IOS)
  #import "PassThroughBackgroundView.h"
  #import <UIKit/UIKit.h>
#endif

#import "CountlyCommon.h"

NS_ASSUME_NONNULL_BEGIN
#if (TARGET_OS_IOS)
@interface                                              CountlyWebViewController : UIViewController
@property(nonatomic, strong) PassThroughBackgroundView *contentView;
- (void)updatePlacementRespectToSafeAreas;
@end
#endif
NS_ASSUME_NONNULL_END
