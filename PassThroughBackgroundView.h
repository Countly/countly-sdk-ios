// PassThroughBackgroundView.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.


#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "CountlyCommon.h"
NS_ASSUME_NONNULL_BEGIN
@interface PassThroughBackgroundView : UIView

#if (TARGET_OS_IOS)
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) CLYButton *dismissButton;
#endif

NS_ASSUME_NONNULL_END
@end
