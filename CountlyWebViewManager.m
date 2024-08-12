#import "CountlyWebViewManager.h"
#import "PassThroughBackgroundView.h"
#import "CountlyCommon.h"

@interface CountlyWebViewManager()
@property (nonatomic, strong) PassThroughBackgroundView *backgroundView;
@property (nonatomic, copy) void (^dismissBlock)(void);
@end

@implementation CountlyWebViewManager

- (void)createWebViewWithURL:(NSURL *)url
                       frame:(CGRect)frame
                 appearBlock:(void(^ __nullable)(void))appearBlock
                dismissBlock:(void(^ __nullable)(void))dismissBlock {
    self.dismissBlock = dismissBlock;
    UIViewController *rootViewController = UIApplication.sharedApplication.keyWindow.rootViewController;
    CGRect backgroundFrame = rootViewController.view.bounds;
    
    if (@available(iOS 11.0, *)) {
        CGFloat top = UIApplication.sharedApplication.keyWindow.safeAreaInsets.top;
        backgroundFrame.origin.y += top ? top + 5 : 20.0;
        backgroundFrame.size.height -= top ? top + 5 : 20.0;
    } else {
        backgroundFrame.origin.y += 20.0;
        backgroundFrame.size.height -= 20.0;
    }
    
    self.backgroundView = [[PassThroughBackgroundView alloc] initWithFrame:backgroundFrame];
    self.backgroundView.backgroundColor = [UIColor clearColor];
    [rootViewController.view addSubview:self.backgroundView];
    
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
    WKWebView *webView = [[WKWebView alloc] initWithFrame:frame configuration:configuration];
    
    [self configureWebView:webView];
    
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    [webView loadRequest:request];
    
    CLYButton *dismissButton = [CLYButton dismissAlertButton:@"X"];
    [self configureDismissButton:dismissButton forWebView:webView];
    
    self.backgroundView.webView = webView;
    self.backgroundView.dismissButton = dismissButton;
    [webView evaluateJavaScript:@"document.readyState" completionHandler:^(id _Nullable result, NSError * _Nullable error) {
        if ([result isKindOfClass:[NSString class]] && [(NSString *)result isEqualToString:@"complete"]) {
            NSLog(@"Web view has finished loading");
            self.backgroundView.hidden = NO;
            if (appearBlock) {
                appearBlock();
            }
        }
    }];
}

- (void)configureWebView:(WKWebView *)webView {
    webView.layer.shadowColor = UIColor.blackColor.CGColor;
    webView.layer.shadowOpacity = 0.5;
    webView.layer.shadowOffset = CGSizeMake(0.0f, 5.0f);
    webView.layer.masksToBounds = NO;
    webView.opaque = NO;
    webView.scrollView.bounces = NO;
    webView.navigationDelegate = self;
    
    [self.backgroundView addSubview:webView];
}

- (void)configureDismissButton:(CLYButton *)dismissButton forWebView:(WKWebView *)webView {
    dismissButton.onClick = ^(id sender) {
        if (self.dismissBlock) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.dismissBlock();
                [self.backgroundView removeFromSuperview];
            });
        }
    };
    
    [self.backgroundView addSubview:dismissButton];
    [dismissButton positionToTopRight];
    [self.backgroundView bringSubviewToFront:webView];
    [webView bringSubviewToFront:dismissButton];
    
    self.backgroundView.dismissButton = dismissButton;
    dismissButton.hidden = YES;
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSString *url = navigationAction.request.URL.absoluteString;
    
    if ([url containsString:@"cly_x_int=1"]) {
        CLY_LOG_I(@"%s Opening URL [%@] in external browser", __FUNCTION__, url);
        [[UIApplication sharedApplication] openURL:navigationAction.request.URL options:@{} completionHandler:^(BOOL success) {
            CLY_LOG_I(success ? @"%s URL [%@] opened in external browser" : @"%s Unable to open URL [%@] in external browser", __FUNCTION__, url);
        }];
        decisionHandler(WKNavigationActionPolicyCancel);
    } else if ([url containsString:@"cly_x_close=1"]) {
        CLY_LOG_I(@"%s Closing webview", __FUNCTION__);
        if (self.dismissBlock) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.dismissBlock();
                [self.backgroundView removeFromSuperview];
            });
        }
        decisionHandler(WKNavigationActionPolicyCancel);
    } else {
        decisionHandler(WKNavigationActionPolicyAllow);
    }
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    CLY_LOG_I(@"%s Web view has started loading", __FUNCTION__);
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    CLY_LOG_I(@"%s Web view has finished loading", __FUNCTION__);
}

- (void)animateView:(UIView *)view withAnimationType:(AnimationType)animationType {
    NSTimeInterval animationDuration = 0;
    CGAffineTransform initialTransform = CGAffineTransformIdentity;
    
    switch (animationType) {
        case AnimationTypeSlideInFromBottom:
            initialTransform = CGAffineTransformMakeTranslation(0, view.superview.frame.size.height);
            break;
        case AnimationTypeSlideInFromTop:
            initialTransform = CGAffineTransformMakeTranslation(0, -view.superview.frame.size.height);
            break;
        case AnimationTypeSlideInFromLeft:
            initialTransform = CGAffineTransformMakeTranslation(-view.superview.frame.size.width, 0);
            break;
        case AnimationTypeSlideInFromRight:
            initialTransform = CGAffineTransformMakeTranslation(view.superview.frame.size.width, 0);
            break;
        case AnimationTypeIncreaseHeight: {
            CGRect originalFrame = view.frame;
            view.frame = CGRectMake(originalFrame.origin.x, originalFrame.origin.y, originalFrame.size.width, 0);
            [UIView animateWithDuration:animationDuration animations:^{
                view.frame = originalFrame;
            }];
            return;
        }
        default:
            return;
    }
    
    view.transform = initialTransform;
    [UIView animateWithDuration:animationDuration animations:^{
        view.transform = CGAffineTransformIdentity;
    }];
}

CGSize sizeForWebViewSize(WebViewSize size, CGRect backgroundFrame, UIEdgeInsets padding) {
    CGFloat width = backgroundFrame.size.width - padding.left - padding.right;
    CGFloat height = backgroundFrame.size.height - padding.top - padding.bottom;
    
    switch (size) {
        case WebViewFullScreen:
            return CGSizeMake(width, height);
        case WebViewHalf:
            return CGSizeMake(width, height / 2);
        case WebViewBanner:
            return CGSizeMake(width, 70);
        case WebViewSquareSmall:
            return CGSizeMake(250, 250);
        default:
            return CGSizeMake(width, height);
    }
}
@end
