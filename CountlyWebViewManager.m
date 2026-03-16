// CountlyWebViewManager.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.
#import "CountlyWebViewManager.h"
#import "CountlyCommon.h"
#import "CountlyOverlayWindow.h"
#import "CountlyWebViewController.h"
#import "PassThroughBackgroundView.h"

#if (TARGET_OS_IOS)
// TODO: improve logging, check edge cases
@interface CountlyWebViewManager ()

@property(nonatomic, strong) PassThroughBackgroundView *backgroundView;
@property(nonatomic, copy) void (^dismissBlock)(void);
@property(nonatomic, copy) void (^appearBlock)(void);
@property(nonatomic, strong) NSTimer *loadTimeoutTimer;
@property(nonatomic, strong) NSDate *loadStartDate;
@property(nonatomic) BOOL hasAppeared;
@property(nonatomic) BOOL webViewClosed;
@property(nonatomic, strong) CountlyWebViewController *presentingController;
@property(nonatomic, strong) CountlyOverlayWindow *window;
@end

@implementation CountlyWebViewManager
  #if (TARGET_OS_IOS)
- (void)createWebViewWithURL:(NSURL *)url
                       frame:(CGRect)frame
                 appearBlock:(void(^ __nullable)(void))appearBlock
                dismissBlock:(void(^ __nullable)(void))dismissBlock {
    self.dismissBlock = dismissBlock;
    self.appearBlock = appearBlock;
    self.hasAppeared = NO;
    self.webViewClosed = NO;
    // TODO: keyWindow deprecation fix
    _window = [CountlyOverlayWindow new];
    CountlyWebViewController *modal = [CountlyWebViewController new];
    modal.modalPresentationStyle = UIModalPresentationOverFullScreen;
    modal.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    _window.rootViewController = modal;
    UIViewController *rootViewController = UIApplication.sharedApplication.keyWindow.rootViewController;
    modal.modalPresentationCapturesStatusBarAppearance = YES;
    CGRect backgroundFrame = rootViewController.view.bounds;
    self.backgroundView = [[PassThroughBackgroundView alloc] initWithFrame:backgroundFrame];
    self.backgroundView.backgroundColor = [UIColor clearColor];
    self.backgroundView.hidden = YES;
    modal.contentView = self.backgroundView;

    _window.hidden = NO;
    self.presentingController = modal;
    
    NSString *jsString = @"(function(){"
     // 1) Catch network-level failures (connection refused, DNS, etc.) for SCRIPT/LINK
     "window.addEventListener('error',function(e){"
     "if(!e.target)return;"
     "var url=e.target.src||e.target.href;"
     "if(!url)return;"
     "if(url.includes('favicon.ico'))return;"
     "if(e.target.tagName&&(e.target.tagName==='SCRIPT'||e.target.tagName==='LINK')){"
     "window.webkit.messageHandlers.resourceLoadError.postMessage({"
     "tag:e.target.tagName,"
     "url:url"
     "});}"
     "},true);"
     // 2) Catch HTTP errors (4xx/5xx) on CSS/JS via PerformanceObserver
     "if(window.PerformanceObserver){"
     "var obs=new PerformanceObserver(function(list){"
     "list.getEntries().forEach(function(entry){"
     "if(entry.responseStatus&&entry.responseStatus>=400){"
     "var tag='';"
     "if(entry.initiatorType==='link')tag='LINK';"
     "else if(entry.initiatorType==='script')tag='SCRIPT';"
     "if(tag){"
     "window.webkit.messageHandlers.resourceLoadError.postMessage({"
     "tag:tag,"
     "url:entry.name"
     "});}}"
     "});"
     "});"
     "obs.observe({type:'resource',buffered:true});"
     "}"
     "})();";
       WKUserContentController *contentController = [[WKUserContentController alloc] init];

       WKUserScript *resourceErrorScript =
       [[WKUserScript alloc] initWithSource:jsString
                              injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                           forMainFrameOnly:NO];

       [contentController addUserScript:resourceErrorScript];
       [contentController addScriptMessageHandler:self name:@"resourceLoadError"];
       [contentController addScriptMessageHandler:self name:@"resourceVerifyResult"];

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
    configuration.userContentController = contentController;

    WKWebView *webView = [[WKWebView alloc] initWithFrame:frame configuration:configuration];
    if (@available(iOS 11.0, *)) {
        webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    [self configureWebView:webView];

    NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60];
    [webView loadRequest:request];

    CLYButton *dismissButton = [CLYButton dismissAlertButton:@"X"];
    [self configureDismissButton:dismissButton forWebView:webView];

    self.backgroundView.webView = webView;
    self.backgroundView.dismissButton = dismissButton;
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
                [self.loadTimeoutTimer invalidate];
                self.loadTimeoutTimer = nil;
                self.loadStartDate = nil;
                self.dismissBlock();
                [self closeWebView];
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

    if (!url) {
        CLY_LOG_I(@"%s Navigation action with nil URL (possible proxy tunnel), allowing", __FUNCTION__);
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }

    if ([url containsString:@"cly_x_int=1"]) {
        CLY_LOG_I(@"%s Opening url [%@] in external browser", __FUNCTION__, url);
        [[UIApplication sharedApplication] openURL:navigationAction.request.URL options:@{} completionHandler:^(BOOL success) {
            if (success) {
                CLY_LOG_I(@"%s url [%@] opened in external browser", __FUNCTION__, url);
            }
            else {
                CLY_LOG_I(@"%s unable to open url [%@] in external browser", __FUNCTION__, url);
            }
        }];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    if ([url hasPrefix:@"https://countly_action_event"]) {
        NSDictionary *queryParameters = [self parseQueryString:url];

        if([url containsString:@"cly_x_action_event=1"]){
            [self contentURLAction:queryParameters];
        } else if([url containsString:@"cly_widget_command=1"]){
            [self widgetURLAction:queryParameters];
        }

        if ([queryParameters[@"close"] boolValue]) {
            [self closeWebView];
        }

        decisionHandler(WKNavigationActionPolicyCancel);
    } else {
        decisionHandler(WKNavigationActionPolicyAllow);
    }
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    NSURLResponse *response = navigationResponse.response;
    NSString *mimeType = response.MIMEType ?: @"(unknown)";
    long statusCode = 0;
    NSDictionary *headers = nil;
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
        statusCode = http.statusCode;
        headers = http.allHeaderFields;
    }

    CLY_LOG_I(@"%s Navigation response received: URL=%@, MIME=%@, status=%ld, headers=%@", __FUNCTION__, response.URL.absoluteString, mimeType, statusCode, headers);

    if (statusCode >= 400) {
        CLY_LOG_I(@"%s Cancelling navigation due to HTTP status code: %ld", __FUNCTION__, statusCode);
        decisionHandler(WKNavigationResponsePolicyCancel);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self closeWebView];
        });
        return;
    }

    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)webView:(WKWebView *)webView didReceiveServerRedirectForProvisionalNavigation:(WKNavigation *)navigation {
    CLY_LOG_I(@"%s Server redirect received for navigation: %@", __FUNCTION__, navigation);
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self.loadTimeoutTimer invalidate];
    self.loadTimeoutTimer = nil;
    CLY_LOG_I(@"%s Provisional navigation failed: %@ (%ld). Closing web view.", __FUNCTION__, error.localizedDescription, (long)error.code);
    [self closeWebView];
}

- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    CLY_LOG_I(@"%s Content started arriving (didCommitNavigation).", __FUNCTION__);
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self.loadTimeoutTimer invalidate];
    self.loadTimeoutTimer = nil;
    CLY_LOG_I(@"%s Navigation failed after commit: %@ (%ld). Closing web view.", __FUNCTION__, error.localizedDescription, (long)error.code);
    [self closeWebView];
}

- (void)webView:(WKWebView *)webView didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
    CLY_LOG_I(@"%s Received authentication challenge for host: %@, protectionSpace: %@", __FUNCTION__, challenge.protectionSpace.host, challenge.protectionSpace.authenticationMethod);
    // sth custom if needed later?
    completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    CLY_LOG_I(@"%s Web content process terminated for URL: %@.", __FUNCTION__, webView.URL.absoluteString);
    // reload?
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    CLY_LOG_I(@"%s Web view has started loading", __FUNCTION__);
    [self.loadTimeoutTimer invalidate];
    __weak typeof(self) weakSelf = self;
    self.loadTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval:60.0 repeats:NO block:^(NSTimer * _Nonnull timer) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf loadDidTimeout];
    }];
    self.loadStartDate = [NSDate date];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    // Don't invalidate the timeout timer here — keep it running until
    // the view actually appears or resource verification completes.
    // This ensures a 60s safety net even if fetch() calls hang.

    if (self.webViewClosed) return;

    CLY_LOG_I(@"%s Web view has finished loading", __FUNCTION__);
    if (self.loadStartDate) {
        NSTimeInterval loadDuration = [[NSDate date] timeIntervalSinceDate:self.loadStartDate];
        CLY_LOG_I(@"%s Web view load duration: %.3f seconds", __FUNCTION__, loadDuration);
        self.loadStartDate = nil;
    }

    [self verifyResourceStatuses:webView];
}

// After page load, fetch each CSS/JS URL with HEAD to verify HTTP status.
// Results are sent back via postMessage since evaluateJavaScript can't handle Promises.
- (void)verifyResourceStatuses:(WKWebView *)webView {
    if (self.webViewClosed) return;

    NSString *js =
        @"(function(){"
         "var urls=[];"
         "document.querySelectorAll('link[rel=\"stylesheet\"]').forEach(function(l){if(l.href)urls.push({tag:'LINK',url:l.href});});"
         "document.querySelectorAll('script[src]').forEach(function(s){urls.push({tag:'SCRIPT',url:s.src});});"
         "if(urls.length===0){"
         "window.webkit.messageHandlers.resourceVerifyResult.postMessage({results:[]});"
         "return;"
         "}"
         "Promise.all(urls.map(function(r){"
         "return fetch(r.url,{method:'HEAD'}).then(function(resp){"
         "return {tag:r.tag,url:r.url,status:resp.status};"
         "}).catch(function(){"
         "return {tag:r.tag,url:r.url,status:0};"
         "});"
         "})).then(function(results){"
         "window.webkit.messageHandlers.resourceVerifyResult.postMessage({results:results});"
         "});"
         "})()";

    [webView evaluateJavaScript:js completionHandler:^(id result, NSError *error) {
        if (error) {
            CLY_LOG_I(@"%s Error injecting verify script: %@", __FUNCTION__, error.localizedDescription);
            [self notifyPageLoaded];
        }
    }];
}

- (void)notifyPageLoaded {
    if (self.webViewClosed || self.hasAppeared) return;

    [self.loadTimeoutTimer invalidate];
    self.loadTimeoutTimer = nil;

    [self.presentingController updatePlacementRespectToSafeAreas];
    self.hasAppeared = YES;
    self.backgroundView.hidden = NO;
    if (self.appearBlock) {
        self.appearBlock();
    }
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message
{
    if (self.webViewClosed) return;

    if ([message.name isEqualToString:@"resourceLoadError"]) {
        NSDictionary *body = message.body;
        NSString *tag = body[@"tag"];
        NSString *url = body[@"url"];

        CLY_LOG_I(@"%s Critical resource (%@) failed to load: [%@]. Closing web view.", __FUNCTION__, tag, url);

        dispatch_async(dispatch_get_main_queue(), ^{
            [self closeWebView];
        });
    }
    else if ([message.name isEqualToString:@"resourceVerifyResult"]) {
        NSDictionary *body = message.body;
        NSArray *results = body[@"results"];

        if ([results isKindOfClass:[NSArray class]]) {
            for (NSDictionary *entry in results) {
                NSInteger status = [entry[@"status"] integerValue];
                if (status >= 400) {
                    CLY_LOG_I(@"%s Critical resource (%@) returned HTTP %ld: [%@]. Closing web view.",
                              __FUNCTION__, entry[@"tag"], (long)status, entry[@"url"]);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self closeWebView];
                    });
                    return;
                }
            }
        }

        [self notifyPageLoaded];
    }
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

- (void)contentURLAction:(NSDictionary *)queryParameters {
    NSString *action = queryParameters[@"action"];
    if(action) {
        if ([action isEqualToString:@"event"]) {
            NSString *eventsJson = queryParameters[@"event"];
            if(eventsJson) {
                [self recordEventsWithJSONString:eventsJson];
            }
        } else if ([action isEqualToString:@"link"]) {
            NSString *link = queryParameters[@"link"];
            if(link) {
                [self openExternalLink:link];
            }
        } else if ([action isEqualToString:@"resize_me"]) {
            NSString *resize = queryParameters[@"resize_me"];
            if(resize) {
                [self resizeWebViewWithJSONString:resize];
            }
        }
    }
}

- (void)widgetURLAction:(NSDictionary *)queryParameters {
    // none action yet
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
    // Decode the URL-encoded JSON string
    NSString *decodedString = [jsonString stringByRemovingPercentEncoding];

    // Convert the decoded string to NSData
    NSData *data = [decodedString dataUsingEncoding:NSUTF8StringEncoding];

    // Parse the JSON data
    NSError *error = nil;
    NSArray *events = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];

    if (error) {
        CLY_LOG_I(@"%s Error parsing JSON: %@", __FUNCTION__, error);
    } else {
        CLY_LOG_I(@"%s Parsed JSON: %@", __FUNCTION__, events);
    }

    if (!events || ![events isKindOfClass:[NSArray class]]) {
            CLY_LOG_I(@"Events array should not be empty or nil, and should be of type NSArray");
            return;
    }
    for (NSDictionary *event in events) {
            NSString *key = event[@"key"];
            NSDictionary *segmentation = event[@"segmentation"];
            NSDictionary *sg = event[@"sg"];
            if(!key) {
                CLY_LOG_I(@"Skipping the event due to key is empty or nil");
                continue;
            }
            if(sg) {
                segmentation = sg;
            }
            if(!segmentation) {
                CLY_LOG_I(@"Skipping the event due to missing segmentation");
                continue;
            }

            [Countly.sharedInstance recordEvent:key segmentation:segmentation];
    }

    [CountlyConnectionManager.sharedInstance attemptToSendStoredRequests];
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

    // Decode the URL-encoded JSON string
    NSString *decodedString = [jsonString stringByRemovingPercentEncoding];

    // Convert the decoded string to NSData
    NSData *data = [decodedString dataUsingEncoding:NSUTF8StringEncoding];

    // Parse the JSON data
    NSError *error = nil;
    NSDictionary *resizeDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];

    if (!resizeDict) {
        CLY_LOG_I(@"Resize dictionary should not be empty or nil. Error: %@", error);
        return;
    }

    // Ensure resizeDict is a dictionary
    if (![resizeDict isKindOfClass:[NSDictionary class]]) {
        CLY_LOG_I(@"Resize dictionary should be of type NSDictionary");
        return;
    }

    // Retrieve portrait and landscape dimensions
    NSDictionary *portraitDimensions = resizeDict[@"p"];
    NSDictionary *landscapeDimensions = resizeDict[@"l"];

    if (!portraitDimensions && !landscapeDimensions) {
        CLY_LOG_I(@"Resize dimensions should not be empty or nil");
        return;
    }

    // Determine the current orientation
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    BOOL isLandscape = UIInterfaceOrientationIsLandscape(orientation);

    // Select the appropriate dimensions based on orientation
    NSDictionary *dimensions = isLandscape ? landscapeDimensions : portraitDimensions;

    // Get the dimension values
    CGFloat x = [dimensions[@"x"] floatValue];
    CGFloat y = [dimensions[@"y"] floatValue];
    CGFloat width = [dimensions[@"w"] floatValue];
    CGFloat height = [dimensions[@"h"] floatValue];

    // Animate the resizing of the web view
    [UIView animateWithDuration:0.3 animations:^{
        CGRect frame = self.backgroundView.webView.frame;
        frame.origin.x = x;
        frame.origin.y = y;
        frame.size.width = width;
        frame.size.height = height;
        self.backgroundView.webView.frame = frame;
        [self.presentingController updatePlacementRespectToSafeAreas];
    } completion:^(BOOL finished) {
        CLY_LOG_I(@"%s, Resized web view to width: %f, height: %f", __FUNCTION__, width, height);
    }];
}

- (void)closeWebView
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.backgroundView.webView) {
            return;
        }
        self.webViewClosed = YES;
        self.window.hidden = YES;
        self.loadStartDate = nil;
        [self.loadTimeoutTimer invalidate];
        self.loadTimeoutTimer = nil;
        if (self.backgroundView) {
            [self.backgroundView.webView stopLoading];
            self.backgroundView.webView.navigationDelegate = nil;
            self.backgroundView.webView.UIDelegate = nil;
            [self.backgroundView removeFromSuperview];
            WKUserContentController *controller = self.backgroundView.webView.configuration.userContentController;
            [controller removeScriptMessageHandlerForName:@"resourceLoadError"];
            [controller removeScriptMessageHandlerForName:@"resourceVerifyResult"];
        }
        if (self.dismissBlock) {
            self.dismissBlock();
        }
        if(self.presentingController) {
            [self.presentingController dismissViewControllerAnimated:NO completion:nil];
        }
        if(self.window) {
            if(self.window.rootViewController) {
                [self.window.rootViewController.view removeFromSuperview];
            }
            self.window.rootViewController = nil;
            if (@available(iOS 13.0, *)) {
                self.window.windowScene = nil;
            }
        }
        
        self.backgroundView = nil;
        self.presentingController = nil;
        self.window = nil;
    });
}

- (void)loadDidTimeout {
    if (self.hasAppeared || self.webViewClosed) return;
    self.webViewClosed = YES;
    CLY_LOG_I(@"%s Web view load timed out after 60s, closing", __FUNCTION__);
    [self closeWebView];
}
  #endif
@end
#endif
