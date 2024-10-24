// PassThroughBackgroundView.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.


#if (TARGET_OS_IOS)
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#endif

#import "CountlyCommon.h"

NS_ASSUME_NONNULL_BEGIN
#if (TARGET_OS_IOS)
@interface PassThroughBackgroundView : UIView


@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) CLYButton *dismissButton;



@end
#endif
NS_ASSUME_NONNULL_END
