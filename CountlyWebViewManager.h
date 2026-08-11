// CountlyWebViewManager.h
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
typedef NS_ENUM(NSUInteger, AnimationType) {
    AnimationTypeSlideInFromBottom,
    AnimationTypeSlideInFromTop,
    AnimationTypeSlideInFromLeft,
    AnimationTypeSlideInFromRight,
    AnimationTypeIncreaseHeight,
    AnimationTypeIncreaseHeightFromBottom
};



@interface CountlyWebViewManager : NSObject <WKNavigationDelegate, WKScriptMessageHandler>

- (void)createWebViewWithURL:(NSURL *)url
                     frame:(CGRect)frame
                 appearBlock:(void(^ __nullable)(void))appearBlock
                dismissBlock:(void(^ __nullable)(void))dismissBlock;

/// Tears down the web view and overlay window and invokes the dismiss block. Any thread, idempotent.
- (void)closeWebView;



@end
#endif
NS_ASSUME_NONNULL_END
