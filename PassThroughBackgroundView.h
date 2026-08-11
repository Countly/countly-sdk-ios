// PassThroughBackgroundView.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.


#if (TARGET_OS_IOS || TARGET_OS_VISION)
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#endif

#import "CountlyCommon.h"

NS_ASSUME_NONNULL_BEGIN
#if (TARGET_OS_IOS || TARGET_OS_VISION)
@interface PassThroughBackgroundView : UIView


@property(nonatomic, strong) WKWebView *webView;
@property(nonatomic, strong) CLYButton *dismissButton;

/// The web view's placement before safe-area adjustment. Those insets are additive, so every
/// placement pass must start here or they accumulate. CGRectNull means "not tracked".
@property(nonatomic) CGRect baseWebViewFrame;

/// When set, the page is always told the PORTRAIT-oriented size, whatever the device is doing.
/// Set for content with disableRotation, so the page lays out for the portrait frame it is given.
@property(nonatomic) BOOL reportPortraitSizeOnly;

/// Tells the page its available size via a `{type:'resize'}` postMessage.
- (void)updateWindowSize;

/// Applies reportPortraitSizeOnly to a measured size. Exposed for tests.
- (CGSize)portraitAdjustedSize:(CGSize)size;



@end
#endif
NS_ASSUME_NONNULL_END
