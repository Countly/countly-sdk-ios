#if (TARGET_OS_IOS)
#import "CountlyWebViewManager.h"
#import "PassThroughBackgroundView.h"
#import "CountlyCommon.h"

//TODO: improve logging, check edge cases
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
    
    if ([url hasPrefix:@"https://countly_action_event"] && [url containsString:@"cly_x_action_event=1"]) {
        NSDictionary *queryParameters = [self parseQueryString:url];
        NSString *action = queryParameters[@"action"];
        
        if ([action isEqualToString:@"event"]) {
            NSString *eventsJson = queryParameters[@"event"];
            [self recordEventsWithJSONString:eventsJson];
        } else if ([action isEqualToString:@"link"]) {
            NSString *link = queryParameters[@"link"];
            [self openExternalLink:link];
        } else if ([action isEqualToString:@"resize_me"]) {
            NSString *resize = queryParameters[@"resize_me"];
            [self resizeWebViewWithJSONString:resize];
        }
        
        if ([queryParameters[@"close"] boolValue]) {
            [self closeWebView];
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

- (NSDictionary *)parseQueryString:(NSString *)url {
    NSMutableDictionary *queryDict = [NSMutableDictionary dictionary];
    NSArray *urlComponents = [url componentsSeparatedByString:@"?"];
    
    if (urlComponents.count > 1) {
        NSArray *queryItems = [urlComponents[1] componentsSeparatedByString:@"&"];
        
        for (NSString *item in queryItems) {
            NSArray *keyValue = [item componentsSeparatedByString:@"="];
            if (keyValue.count == 2) {
                NSString *key = keyValue[0];
                NSString *value = keyValue[1];
                queryDict[key] = value;
            }
        }
    }
    
    return queryDict;
}

- (void)recordEventsWithJSONString:(NSString *)jsonString {
    NSData *data = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    NSArray *events = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    
    for (NSDictionary *event in events) {
        NSString *key = event[@"key"];
        NSDictionary *segmentation = event[@"sg"];
        if(!segmentation) {
            CLY_LOG_I(@"Skipping the event due to missing segmentation");
            continue;
        }
        
        [Countly.sharedInstance recordEvent:key segmentation:segmentation];
    }
}

- (void)openExternalLink:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    if (url) {
        [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
            if (success) {
                CLY_LOG_I(@"URL [%@] opened in external browser", urlString);
            } else {
                CLY_LOG_I(@"Unable to open URL [%@] in external browser", urlString);
            }
        }];
    }
}

- (void)resizeWebViewWithJSONString:(NSString *)jsonString {
    NSData *data = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *resizeDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    
    NSDictionary *portraitDimensions = resizeDict[@"p"];
    NSDictionary *landscapeDimensions = resizeDict[@"l"];
    
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    BOOL isLandscape = UIInterfaceOrientationIsLandscape(orientation);
    
    NSDictionary *dimensions = isLandscape ? landscapeDimensions : portraitDimensions;
    
    CGFloat width = [dimensions[@"w"] floatValue];
    CGFloat height = [dimensions[@"h"] floatValue];
    
    [UIView animateWithDuration:0.3 animations:^{
        CGRect frame = self.backgroundView.webView.frame;
        frame.size.width = width;
        frame.size.height = height;
        self.backgroundView.webView.frame = frame;
    } completion:^(BOOL finished) {
        CLY_LOG_I(@"Resized web view to width: %f, height: %f", width, height);
    }];
}


- (void)closeWebView {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.dismissBlock) {
            self.dismissBlock();
        }
        [self.backgroundView removeFromSuperview];
    });
}
@end
#else
#import "CountlyWebViewManager.h"
@implementation CountlyWebViewManager
@end
#endif
