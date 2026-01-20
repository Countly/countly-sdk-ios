// CountlyWebViewController.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#if (TARGET_OS_IOS)
  #import "CountlyCommon.h"
  #import "PassThroughBackgroundView.h"
  #import <UIKit/UIKit.h>

@interface                                              CountlyWebViewController : UIViewController
@property(nonatomic, strong) PassThroughBackgroundView *contentView;
- (void)updatePlacementRespectToSafeAreas;
@end
#endif
