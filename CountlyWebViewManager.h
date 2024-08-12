// CountlyWebViewManager.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

typedef NS_ENUM(NSInteger, WebViewPosition) {
    WebViewPositionTop,
    WebViewPositionBottom,
    WebViewPositionCenter,
    WebViewPositionTopLeft,
    WebViewPositionTopRight,
    WebViewPositionBottomLeft,
    WebViewPositionBottomRight,
};

typedef NS_ENUM(NSInteger, WebViewSize) {
    WebViewFullScreen,
    WebViewHalf,
    WebViewBanner,
    WebViewSquareSmall
};

typedef NS_ENUM(NSUInteger, AnimationType) {
    AnimationTypeSlideInFromBottom,
    AnimationTypeSlideInFromTop,
    AnimationTypeSlideInFromLeft,
    AnimationTypeSlideInFromRight,
    AnimationTypeIncreaseHeight,
    AnimationTypeIncreaseHeightFromBottom
};

@interface CountlyWebViewManager : NSObject <WKNavigationDelegate>


- (void)createWebViewWithURL:(NSURL *)url
                     frame:(CGRect)frame
                 appearBlock:(void(^ __nullable)(void))appearBlock
                dismissBlock:(void(^ __nullable)(void))dismissBlock;

@end
