// CountlyWebViewManager.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyWebViewManager.h"
#import "PassThroughBackgroundView.h"
#import "CountlyCommon.h"

@implementation CountlyWebViewManager

- (void)createWebViewWithURL:(NSURL *)URL
                        size:(WebViewSize)size
                     padding:(UIEdgeInsets)padding
                  atPosition:(WebViewPosition)position
                 animatation:(AnimationType)animation {
    
    UIViewController *rootViewController = UIApplication.sharedApplication.keyWindow.rootViewController;
    CGRect backgroundFrame =  rootViewController.view.bounds;
    
    if (@available(iOS 11.0, *))
    {
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
        CGFloat top = UIApplication.sharedApplication.keyWindow.safeAreaInsets.top;
#pragma GCC diagnostic pop
        
        if (top)
        {
            backgroundFrame.origin.y += top+5;
            backgroundFrame.size.height -= top-5;
        }
        else
        {
            backgroundFrame.origin.y += 20.0;
            backgroundFrame.size.height -= 20.0;
        }
    }
    else
    {
        backgroundFrame.origin.y += 20.0;
        backgroundFrame.size.height -= 20.0;
    }
    
    CGRect frame = CGRectZero;
    CGSize webViewSize = sizeForWebViewSize(size, backgroundFrame, padding);
    
    CGFloat originX = 0;
    CGFloat originY = 0;
    
    switch (position) {
        case WebViewPositionTop:
            originX = (backgroundFrame.size.width - webViewSize.width) / 2;
            originY = padding.top;
            break;
        case WebViewPositionBottom:
            originX = (backgroundFrame.size.width - webViewSize.width) / 2;
            originY = backgroundFrame.size.height - webViewSize.height - padding.bottom;
            break;
        case WebViewPositionCenter:
            originX = (backgroundFrame.size.width - webViewSize.width) / 2 + padding.left - padding.right;
            originY = (backgroundFrame.size.height - webViewSize.height) / 2 + padding.top - padding.bottom;
            break;
        case WebViewPositionTopLeft:
            originX = padding.left;
            originY = padding.top;
            break;
        case WebViewPositionTopRight:
            originX = backgroundFrame.size.width - webViewSize.width - padding.right;
            originY = padding.top;
            break;
        case WebViewPositionBottomLeft: 
            originX = padding.left;
            originY = backgroundFrame.size.height - webViewSize.height - padding.bottom;
            break;
        case WebViewPositionBottomRight:
            originX = backgroundFrame.size.width - webViewSize.width - padding.right;
            originY = backgroundFrame.size.height - webViewSize.height - padding.bottom;
            break;
        default:
            break;
    }
    
    frame = CGRectMake(originX, originY, webViewSize.width, webViewSize.height);

    
    PassThroughBackgroundView *backgroundView = [[PassThroughBackgroundView alloc] initWithFrame:backgroundFrame];
    backgroundView.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.25];
    [rootViewController.view addSubview:backgroundView];
    
    WKWebView *webView = [[WKWebView alloc] initWithFrame:frame];
    
    webView.backgroundColor = [UIColor clearColor];
    webView.opaque = NO;
    webView.scrollView.bounces = NO;
    webView.navigationDelegate = self;
    
    NSURLRequest *request = [NSURLRequest requestWithURL:URL];
    [webView loadRequest:request];
    
    
    CLYButton* dismissButton = [CLYButton dismissAlertButton:@"X"];
    dismissButton.onClick = ^(id sender)
    {
        [backgroundView removeFromSuperview];
    };
    
    backgroundView.webView = webView;
    backgroundView.dismissButton = dismissButton;
    
    [backgroundView addSubview:webView];
    [webView addSubview:dismissButton];
    
    [dismissButton positionToTopRight];
    [backgroundView bringSubviewToFront:webView];
    [webView bringSubviewToFront:dismissButton];
    backgroundView.hidden = YES;
    [webView evaluateJavaScript:@"document.readyState" completionHandler:^(id _Nullable result, NSError * _Nullable error) {
        if (result != nil && [result isKindOfClass:[NSString class]] && [(NSString *)result isEqualToString:@"complete"]) {
            NSLog(@"Web view has finished loading");
            backgroundView.hidden = NO;
            [self animateView:webView withAnimationType:animation];
            
        }
    }];
    
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(null_unspecified WKNavigation *)navigation
{
    NSLog(@"Web view has start loading");

}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    NSLog(@"Web view has finished loading");
}

- (void)animateView:(UIView *)view withAnimationType:(AnimationType)animationType {
    NSTimeInterval animationDuration = 1.25;
    switch (animationType) {
        case AnimationTypeSlideInFromBottom:
        {
            view.transform = CGAffineTransformMakeTranslation(0, view.superview.frame.size.height);
            [UIView animateWithDuration:animationDuration animations:^{
                view.transform = CGAffineTransformIdentity;
            }];
        }
            break;
            
        case AnimationTypeSlideInFromTop:
        {
            view.transform = CGAffineTransformMakeTranslation(0, -view.superview.frame.size.height);
            [UIView animateWithDuration:animationDuration animations:^{
                view.transform = CGAffineTransformIdentity;
            }];
        }
            break;
            
        case AnimationTypeSlideInFromLeft:
        {
            view.transform = CGAffineTransformMakeTranslation(-view.superview.frame.size.width, 0);
            [UIView animateWithDuration:animationDuration animations:^{
                view.transform = CGAffineTransformIdentity;
            }];
        }
            break;
            
        case AnimationTypeSlideInFromRight:
        {
            view.transform = CGAffineTransformMakeTranslation(view.superview.frame.size.width, 0);
            [UIView animateWithDuration:animationDuration animations:^{
                view.transform = CGAffineTransformIdentity;
            }];
        }
            break;
            
        case AnimationTypeIncreaseHeight:
        {
            CGRect originalFrame = view.frame;
            view.frame = CGRectMake(originalFrame.origin.x, originalFrame.origin.y, originalFrame.size.width, 0);
            [UIView animateWithDuration:animationDuration animations:^{
                view.frame = originalFrame;
            }];
        }
            break;
            
        default:
            break;
    }
}

CGSize sizeForWebViewSize(WebViewSize size, CGRect backgroundFrame, UIEdgeInsets padding) {
    switch (size) {
        case WebViewFullScreen:
            return CGSizeMake(backgroundFrame.size.width - padding.left - padding.right, backgroundFrame.size.height - padding.top - padding.bottom);
        case WebViewHalf:
            return CGSizeMake(backgroundFrame.size.width - padding.left - padding.right, (backgroundFrame.size.height - padding.top - padding.bottom) / 2);
        case WebViewBanner:
            return CGSizeMake(backgroundFrame.size.width - padding.left - padding.right, 70);
        case WebViewSquareSmall:
            return CGSizeMake(250, 250);
        default:
            return CGSizeMake(backgroundFrame.size.width - padding.left - padding.right, backgroundFrame.size.height - padding.top - padding.bottom);
    }
}
@end
