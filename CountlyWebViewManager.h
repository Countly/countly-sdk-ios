// CountlyWebViewManager.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#if (TARGET_OS_IOS)
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#endif
#import "CountlyCommon.h"

#if (TARGET_OS_IOS)
typedef NS_ENUM(NSUInteger, AnimationType) {
    AnimationTypeSlideInFromBottom,
    AnimationTypeSlideInFromTop,
    AnimationTypeSlideInFromLeft,
    AnimationTypeSlideInFromRight,
    AnimationTypeIncreaseHeight,
    AnimationTypeIncreaseHeightFromBottom
};

@interface CountlyWebViewManager : NSObject <WKNavigationDelegate>

- (void)createWebViewWithURL:(NSURL * _Nonnull)url
                     frame:(CGRect)frame
                 appearBlock:(void(^ __nullable)(void))appearBlock
                dismissBlock:(void(^ __nullable)(void))dismissBlock;

#else
@interface CountlyWebViewManager : NSObject
#endif
@end
