// CountlyOverlayWindow.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.
#if (TARGET_OS_IOS)
  #import <UIKit/UIKit.h>
#endif

#import "CountlyCommon.h"

NS_ASSUME_NONNULL_BEGIN
#if (TARGET_OS_IOS)
@interface CountlyOverlayWindow : UIWindow
@end
#endif
NS_ASSUME_NONNULL_END
