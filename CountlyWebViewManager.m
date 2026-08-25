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
#import "CountlyContentBuilderInternal.h"

#if (TARGET_OS_IOS || TARGET_OS_VISION)
// Critical-resource load retries: how many times to reload the web view before
// giving up when a critical (JS/CSS) resource fails to load. A single transient
// network hiccup — e.g. a connection stalled under a burst of parallel asset
// requests against an HTTP/1.1 / rate-limited edge — should not tear down otherwise
// valid content. On reload, already-loaded resources are served from the in-session
// cache, so the retry re-fetches only what failed. Mirrors the more tolerant Android
// behavior (which never closes on a transient JS error event).
static const NSInteger kCLYMaxResourceRetries = 2;
static const NSTimeInterval kCLYResourceRetryBaseDelay = 0.6;
// Fallback stall timeout (seconds) used only when reload-on-stall is enabled but no
// timeout was configured (e.g. the SDK was not started via config in a unit test). The
// real value comes from CountlyContentConfig setContentReloadOnStallTimeout: (default
// 1000 ms). Kept short because a manual reload is observed to recover reliably: on reload
// the already-fetched assets come from cache and the rest reuse the warm connection, so
// the parallel-connection burst shrinks below the edge's limit. A stalled load fires no
// JS 'error' event, so this timer is what triggers the reload for that case. When the
// flag is off, the 60s safety-net timeout is used and the view closes on failure.
static const NSTimeInterval kCLYLoadStallTimeout = 1.0;
static const NSTimeInterval kCLYDefaultLoadTimeout = 60.0;
// Absolute deadline (seconds) by which the content must report [CLY]_content_shown, else the
// web view is closed. Armed ONCE when the web view is created and never reset by reloads, so it
// is a hard backstop the reload/stall machinery cannot defeat: no matter how the retry/verify
// logic behaves, a content that never actually shows is torn down within this window. This is
// the guaranteed replacement for the old fixed 60s close (which no longer applies once the
// per-navigation stall timer shrinks under reload-on-stall).
static const NSTimeInterval kCLYContentShownDeadline = 60.0;

// TODO: improve logging, check edge cases
@interface CountlyWebViewManager ()

@property(nonatomic, strong) PassThroughBackgroundView *backgroundView;
@property(nonatomic, copy) void (^dismissBlock)(void);
@property(nonatomic, copy) void (^appearBlock)(void);
@property(nonatomic, strong) NSTimer *loadTimeoutTimer;
@property(nonatomic, strong) NSDate *loadStartDate;
@property(nonatomic) BOOL hasAppeared;
@property(nonatomic) BOOL webViewClosed;
@property(nonatomic) NSInteger resourceRetryCount;
@property(nonatomic) NSTimeInterval loadTimeoutInterval;
// Non-nil exactly while a reload is scheduled but not yet fired. Single source of truth for
// "a retry is in progress"; cancellable so a load that succeeds first can cancel it.
@property(nonatomic, copy) dispatch_block_t pendingReloadBlock;
// Absolute [CLY]_content_shown deadline timer (see kCLYContentShownDeadline). Armed once at
// creation, cancelled when content_shown arrives, fires closeWebView otherwise.
@property(nonatomic, strong) NSTimer *contentShownDeadlineTimer;
@property(nonatomic, strong) CountlyWebViewController *presentingController;
@property(nonatomic, strong) CountlyOverlayWindow *window;
// Latched at creation; the manager is shared with feedback widgets, so content-only behaviour gates on it.
@property(nonatomic) BOOL isFeedbackWidget;
@end

@implementation CountlyWebViewManager
  #if (TARGET_OS_IOS || TARGET_OS_VISION)
- (void)createWebViewWithURL:(NSURL *)url
                       frame:(CGRect)frame
                 appearBlock:(void(^ __nullable)(void))appearBlock
                dismissBlock:(void(^ __nullable)(void))dismissBlock {
    self.isFeedbackWidget = [self isFeedbackWidgetURL:url];
    BOOL pinnedToPortrait = !self.isFeedbackWidget && CountlyContentBuilderInternal.sharedInstance.disableRotation;
    // Host and path only: the content and widget URL query strings carry the app key and the device ID.
    CLY_LOG_I(@"%s web view presentation requested, host: [%@], path: [%@], isFeedbackWidget: [%@], pinnedToPortrait: [%@], appearCallbackProvided: [%@], dismissCallbackProvided: [%@]", __FUNCTION__, url.host, url.path, self.isFeedbackWidget ? @"YES" : @"NO", pinnedToPortrait ? @"YES" : @"NO", (appearBlock != nil) ? @"YES" : @"NO", (dismissBlock != nil) ? @"YES" : @"NO");
    CLY_LOG_D(@"%s web view presentation URL detail, url: [%@], isFeedbackWidget: [%@]", __FUNCTION__, url.absoluteString, self.isFeedbackWidget ? @"YES" : @"NO");
    self.dismissBlock = dismissBlock;
    self.appearBlock = appearBlock;
    self.hasAppeared = NO;
    self.webViewClosed = NO;
    self.resourceRetryCount = 0;
    self.pendingReloadBlock = nil;
    _window = [CountlyOverlayWindow new];
    CountlyWebViewController *modal = [CountlyWebViewController new];
    modal.modalPresentationStyle = UIModalPresentationOverFullScreen;
    modal.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    _window.rootViewController = modal;
    // The rotation hook: UIKit always delivers it, unlike the device-orientation notification.
    __weak typeof(self) weakSelf = self;
    modal.sizeChangeHandler = ^(CGSize newSize) {
        [weakSelf handleInterfaceSizeChange:newSize];
    };
    UIViewController *rootViewController = CountlyCommon.keyWindow.rootViewController;
    modal.modalPresentationCapturesStatusBarAppearance = YES;
    CGRect backgroundFrame = rootViewController.view.bounds;
    CLY_LOG_D(@"%s frames computed, webViewFrame: [%@], backgroundFrame: [%@]", __FUNCTION__, NSStringFromCGRect(frame), NSStringFromCGRect(backgroundFrame));
    self.backgroundView = [[PassThroughBackgroundView alloc] initWithFrame:backgroundFrame];
    self.backgroundView.backgroundColor = [UIColor clearColor];
    self.backgroundView.hidden = YES;
    self.backgroundView.reportPortraitSizeOnly = pinnedToPortrait;
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

       // Opt-in (CountlyContentConfig disableZoom): prevent user zoom (pinch / double-tap) by
       // enforcing the no-zoom viewport directives. Injected at document end so document.head
       // exists. This PRESERVES the page's own width / initial-scale (only strips and re-adds
       // maximum-scale / minimum-scale / user-scalable), so it disables zoom without changing
       // the layout the content declared. The scroll-view pinch gesture is also disabled in
       // configureWebView: as a native backstop.
       if (CountlyContentBuilderInternal.sharedInstance.disableZoom) {
           CLY_LOG_D(@"%s zoom is disabled by the config, injecting the no zoom viewport script", __FUNCTION__);
           NSString *disableZoomJS =
            @"(function(){"
             "var m=document.querySelector('meta[name=viewport]');"
             "if(m){"
             "var kept=(m.content||'').split(',').map(function(s){return s.trim();}).filter(function(s){var l=s.toLowerCase();return s.length&&l.indexOf('maximum-scale')!==0&&l.indexOf('minimum-scale')!==0&&l.indexOf('user-scalable')!==0;});"
             "kept.push('maximum-scale=1.0','minimum-scale=1.0','user-scalable=no');"
             "m.content=kept.join(', ');"
             "}else{"
             "m=document.createElement('meta');m.name='viewport';"
             "m.content='width=device-width, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, user-scalable=no';"
             "(document.head||document.documentElement).appendChild(m);"
             "}"
             "})();";
           WKUserScript *disableZoomScript =
           [[WKUserScript alloc] initWithSource:disableZoomJS
                                  injectionTime:WKUserScriptInjectionTimeAtDocumentEnd
                               forMainFrameOnly:YES];
           [contentController addUserScript:disableZoomScript];
       }

       [contentController addScriptMessageHandler:self name:@"resourceLoadError"];
       [contentController addScriptMessageHandler:self name:@"resourceVerifyResult"];

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
    configuration.userContentController = contentController;

    WKWebView *webView = [[WKWebView alloc] initWithFrame:frame configuration:configuration];
    if (@available(iOS 11.0, *)) {
        webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    // When SDK debug is enabled, expose the content web view to Safari Web Inspector
    // (iOS 16.4+ requires this to be set explicitly). Lets you inspect the Network and
    // Console tabs of the content web view live from a Mac. Off in production.
    if (@available(iOS 16.4, *)) {
        webView.inspectable = CountlyCommon.sharedInstance.enableDebug;
    }
    [self configureWebView:webView];

    NSURLRequest *request = [NSURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60];
    [webView loadRequest:request];

    // Arm the absolute content-shown deadline ONCE (not per navigation, so reloads cannot
    // extend it). If [CLY]_content_shown is not reported within kCLYContentShownDeadline, the
    // web view is closed regardless of retry/stall/verify state.
    // Only for CONTENT: feedback widgets (survey/NPS/rating) load a different SDK-built URL and
    // never report [CLY]_content_shown, so arming the deadline for them would force-close a
    // widget the user is still filling out. Skip it for feedback widget URLs.
    if (!self.isFeedbackWidget) {
        __weak typeof(self) deadlineSelf = self;
        self.contentShownDeadlineTimer = [NSTimer scheduledTimerWithTimeInterval:kCLYContentShownDeadline repeats:NO block:^(NSTimer * _Nonnull timer) {
            [deadlineSelf contentShownDeadlineReached];
        }];
    }

    CLYButton *dismissButton = [CLYButton dismissAlertButton:@"X"];
    [self configureDismissButton:dismissButton forWebView:webView];

    self.backgroundView.webView = webView;
    self.backgroundView.baseWebViewFrame = frame;
    self.backgroundView.dismissButton = dismissButton;
}

// An interface size change (rotation, split view). The page is the authority on the new geometry.
- (void)handleInterfaceSizeChange:(CGSize)newSize {
    if (self.webViewClosed || !self.backgroundView.webView) {
        return;
    }

    // Feedback widgets fill the window and have no resize channel of their own (widgetURLAction
    // handles no commands), so they are re-placed natively. Measured the same way as at creation.
    if (self.isFeedbackWidget) {
        CGSize windowSize = [CountlyCommon.sharedInstance getWindowSize];
        CGRect frame = CGRectMake(0.0, 0.0, windowSize.width, windowSize.height);
        CLY_LOG_D(@"%s re-placing the feedback widget after an interface size change, frame: [%@]", __FUNCTION__, NSStringFromCGRect(frame));
        self.backgroundView.baseWebViewFrame = frame;
        self.backgroundView.webView.frame = frame;
        [self.presentingController updatePlacementRespectToSafeAreas];
        [self.backgroundView updateWindowSize];
        return;
    }

    // Prompted even when rotation is disabled: the page is told the portrait size either way (see
    // reportPortraitSizeOnly), and re-asking is what corrects a page that laid out for the wrong
    // orientation — e.g. content first shown while the device was already landscape.

    CLY_LOG_D(@"%s prompting the page for its size after an interface size change, size: [%@]", __FUNCTION__, NSStringFromCGSize(newSize));
    [self.backgroundView updateWindowSize];
}

- (void)configureWebView:(WKWebView *)webView {
    webView.layer.shadowColor = UIColor.blackColor.CGColor;
    webView.layer.shadowOpacity = 0.5;
    webView.layer.shadowOffset = CGSizeMake(0.0f, 5.0f);
    webView.layer.masksToBounds = NO;
    webView.opaque = NO;
    webView.scrollView.bounces = NO;
    // Native backstop for the opt-in viewport zoom disable: turn off the scroll view's pinch
    // gesture. Left alone (does not touch zoom scales, which interact with the page's
    // initial-scale) unless disableZoom is enabled.
    if (CountlyContentBuilderInternal.sharedInstance.disableZoom) {
        webView.scrollView.pinchGestureRecognizer.enabled = NO;
    }
    webView.navigationDelegate = self;

    [self.backgroundView addSubview:webView];
}

- (void)configureDismissButton:(CLYButton *)dismissButton forWebView:(WKWebView *)webView {
    dismissButton.onClick = ^(id sender) {
        CLY_LOG_I(@"%s the dismiss button was tapped, reason: [user-closed]", __FUNCTION__);
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
        CLY_LOG_D(@"%s the navigation action carries no URL (possible proxy tunnel), allowing it", __FUNCTION__);
        decisionHandler(WKNavigationActionPolicyAllow);
        return;
    }

    if ([url containsString:@"cly_x_int=1"]) {
        // Host and path only: the link query string can carry identifiers.
        CLY_LOG_I(@"%s the content asked to open an external URL, host: [%@], path: [%@]", __FUNCTION__, navigationAction.request.URL.host, navigationAction.request.URL.path);
        CLY_LOG_D(@"%s external URL request detail, url: [%@]", __FUNCTION__, url);
        // Routed through the app's content URL handler if one is set, else the system browser.
        [self openExternalURL:navigationAction.request.URL];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    if ([url hasPrefix:@"https://countly_action_event"]) {
        NSDictionary *queryParameters = [self parseQueryString:url];
        CLY_LOG_D(@"%s action event URL parsed, url: [%@], queryParameters: [%@]", __FUNCTION__, url, queryParameters);

        if([url containsString:@"cly_x_action_event=1"]){
            [self contentURLAction:queryParameters];
        } else if([url containsString:@"cly_widget_command=1"]){
            CLY_LOG_D(@"%s handling a widget command, paramCount: [%lu]", __FUNCTION__, (unsigned long)queryParameters.count);
            [self widgetURLAction:queryParameters];
        }

        if ([queryParameters[@"close"] boolValue]) {
            CLY_LOG_I(@"%s dismissing the web view, reason: [JS-requested]", __FUNCTION__);
            [self closeWebView];
        }

        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    decisionHandler(WKNavigationActionPolicyAllow);
}

// Opens an external URL from the content. If the host app has provided a content URL handler
// (CountlyContentConfig setContentURLHandler:), the URL is offered to it first so the app can
// route its own deep link (custom scheme or https) to the right screen; the handler returns
// YES if it took over. If there is no handler, or it returns NO, the SDK opens the URL in the
// system browser as before.
- (void)openExternalURL:(NSURL *)url {
    if (!url) {
        CLY_LOG_W(@"%s there is no valid URL to open, skipping", __FUNCTION__);
        CLY_LOG_D(@"%s the URL to open was nil, no URL detail is available", __FUNCTION__);
        return;
    }

    ContentURLHandler handler = CountlyContentBuilderInternal.sharedInstance.contentURLHandler;
    if (handler && handler(url)) {
        // Host and path only: the link query string can carry identifiers.
        CLY_LOG_I(@"%s the URL was handled by the app's content URL handler, host: [%@], path: [%@]", __FUNCTION__, url.host, url.path);
        CLY_LOG_D(@"%s the URL handed to the app's content URL handler, url: [%@]", __FUNCTION__, url.absoluteString);
        return;
    }

    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL success) {
        CLY_LOG_I(@"%s the URL was handed to the browser, host: [%@], path: [%@], opened: [%@]", __FUNCTION__, url.host, url.path, success ? @"YES" : @"NO");
        CLY_LOG_D(@"%s the URL handed to the browser, url: [%@], opened: [%@]", __FUNCTION__, url.absoluteString, success ? @"YES" : @"NO");
    }];
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

    // Host and path only, and header names are never printed: the response headers and the URL
    // query string can carry identifiers.
    CLY_LOG_D(@"%s navigation response received, host: [%@], path: [%@], mimeType: [%@], status: [%ld], headerCount: [%lu]", __FUNCTION__, response.URL.host, response.URL.path, mimeType, statusCode, (unsigned long)headers.count);

    CLY_LOG_D(@"%s navigation response detail, url: [%@], status: [%ld], headers: [%@]", __FUNCTION__, response.URL.absoluteString, statusCode, headers);

    if (statusCode >= 400) {
        CLY_LOG_E(@"%s cancelling the navigation because of an HTTP error status, status: [%ld], path: [%@], dismissing the web view, reason: [http-error]", __FUNCTION__, statusCode, response.URL.path);
        decisionHandler(WKNavigationResponsePolicyCancel);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self closeWebView];
        });
        return;
    }

    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)webView:(WKWebView *)webView didReceiveServerRedirectForProvisionalNavigation:(WKNavigation *)navigation {
    CLY_LOG_D(@"%s a server redirect was received for the provisional navigation, host: [%@], path: [%@]", __FUNCTION__, webView.URL.host, webView.URL.path);
    CLY_LOG_D(@"%s server redirect destination detail, url: [%@]", __FUNCTION__, webView.URL.absoluteString);
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self.loadTimeoutTimer invalidate];
    self.loadTimeoutTimer = nil;
    CLY_LOG_D(@"%s the provisional navigation failed, error: [%@], domain: [%@], code: [%ld], dismissing the web view, reason: [navigation-failure]", __FUNCTION__, error.localizedDescription, error.domain, (long)error.code);
    [self closeWebView];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self.loadTimeoutTimer invalidate];
    self.loadTimeoutTimer = nil;
    CLY_LOG_D(@"%s the navigation failed after being committed, error: [%@], domain: [%@], code: [%ld], dismissing the web view, reason: [navigation-failure]", __FUNCTION__, error.localizedDescription, error.domain, (long)error.code);
    [self closeWebView];
}

- (void)webView:(WKWebView *)webView didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
    CLY_LOG_D(@"%s an authentication challenge was received, host: [%@], authenticationMethod: [%@], performing the default handling", __FUNCTION__, challenge.protectionSpace.host, challenge.protectionSpace.authenticationMethod);
    // sth custom if needed later?
    completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    CLY_LOG_E(@"%s the web content process terminated, host: [%@], path: [%@]", __FUNCTION__, webView.URL.host, webView.URL.path);
    CLY_LOG_D(@"%s the terminated web content process URL detail, url: [%@]", __FUNCTION__, webView.URL.absoluteString);
    // reload?
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    [self.loadTimeoutTimer invalidate];
    __weak typeof(self) weakSelf = self;
    // Fast stall-detect (reload) when enabled, using the configurable stall timeout;
    // otherwise a plain 60s safety-net close.
    NSTimeInterval stall = CountlyContentBuilderInternal.sharedInstance.contentReloadOnStallTimeout;
    if (stall <= 0) stall = kCLYLoadStallTimeout; // fallback default (e.g. SDK not started via config)
    NSTimeInterval timeout = CountlyContentBuilderInternal.sharedInstance.enableContentReloadOnStall ? stall : kCLYDefaultLoadTimeout;
    self.loadTimeoutInterval = timeout;
    self.loadTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval:timeout repeats:NO block:^(NSTimer * _Nonnull timer) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        [strongSelf loadDidTimeout];
    }];
    self.loadStartDate = [NSDate date];
    CLY_LOG_D(@"%s the navigation started and the load timeout was armed, host: [%@], path: [%@], timeout: [%.1f] seconds, reloadOnStall: [%@]", __FUNCTION__, webView.URL.host, webView.URL.path, timeout, CountlyContentBuilderInternal.sharedInstance.enableContentReloadOnStall ? @"YES" : @"NO");
    CLY_LOG_D(@"%s the navigation started URL detail, url: [%@]", __FUNCTION__, webView.URL.absoluteString);
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    // Don't invalidate the timeout timer here — keep it running until
    // the view actually appears or resource verification completes.
    // This ensures a 60s safety net even if fetch() calls hang.

    if (self.webViewClosed) return;

    NSTimeInterval loadDuration = self.loadStartDate ? [[NSDate date] timeIntervalSinceDate:self.loadStartDate] : 0;
    self.loadStartDate = nil;
    CLY_LOG_I(@"%s the navigation finished, host: [%@], path: [%@], duration: [%.3f] seconds", __FUNCTION__, webView.URL.host, webView.URL.path, loadDuration);
    CLY_LOG_D(@"%s the navigation finished URL detail, url: [%@]", __FUNCTION__, webView.URL.absoluteString);

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
            CLY_LOG_D(@"%s injecting the resource verification script failed, error: [%@], domain: [%@], code: [%ld], continuing without verification", __FUNCTION__, error.localizedDescription, error.domain, (long)error.code);
            [self notifyPageLoaded];
        }
    }];
}

- (void)notifyPageLoaded {
    if (self.webViewClosed || self.hasAppeared) return;

    // Reaching here means the load verified good (all resources OK, or verification could
    // not run). A successful load wins over a retry still pending from an earlier failure
    // in this cycle: cancel it, otherwise the stale reload would wipe the now-good page and
    // re-fire the page's on-load [CLY]_content_shown.
    [self cancelPendingReload];

    [self.loadTimeoutTimer invalidate];
    self.loadTimeoutTimer = nil;

    CLY_LOG_D(@"%s the load verified good, revealing the web view, resourceRetryCount: [%ld]", __FUNCTION__, (long)self.resourceRetryCount);
    [self.presentingController updatePlacementRespectToSafeAreas];
    self.hasAppeared = YES;
    self.backgroundView.hidden = NO;
    if (self.appearBlock) {
        self.appearBlock();
    }
}

// A critical (JS/CSS) resource failed to load. Rather than closing the content
// immediately, reload the web view up to kCLYMaxResourceRetries times before giving
// up. This turns a transient network hiccup (e.g. a connection stalled under a burst
// of parallel asset requests against a rate-limited / HTTP-1.1 edge) into a recoverable
// event instead of a dismissed content. Multiple failures from the same load are
// coalesced into a single reload. Must be called on the main thread.
- (void)retryOrCloseWebViewForReason:(NSString *)reason {
    if (self.webViewClosed) return;

    // Once the content is visible, a late resource failure must not reload or tear it
    // down: the injected error listener / PerformanceObserver stay active for the whole
    // page life, so a dynamically-loaded or lazy resource failing after appearance would
    // otherwise re-run the page (flashing it, discarding scroll / in-progress survey
    // input, and re-firing on-load analytics) or dismiss content the user is using. The
    // retry mechanism only recovers failures during the initial load.
    if (self.hasAppeared) {
        CLY_LOG_D(@"%s a load failure arrived while the content is already visible, treating it as non-fatal, reason: [%@]", __FUNCTION__, reason);
        return;
    }

    // Reload-on-failure is opt-in. When disabled, keep the original behavior: close on failure.
    if (!CountlyContentBuilderInternal.sharedInstance.enableContentReloadOnStall) {
        CLY_LOG_D(@"%s reload on stall is disabled, dismissing the web view, reason: [resource-failure], detail: [%@]", __FUNCTION__, reason);
        [self closeWebView];
        return;
    }

    // A reload is already scheduled for this load cycle — coalesce further failures.
    // pendingReloadBlock being non-nil is the single source of truth for "a reload is pending".
    if (self.pendingReloadBlock) {
        CLY_LOG_D(@"%s a reload is already scheduled for this load cycle, ignoring this failure, reason: [%@]", __FUNCTION__, reason);
        return;
    }

    if (self.resourceRetryCount >= kCLYMaxResourceRetries) {
        CLY_LOG_W(@"%s the load retries are exhausted, retryCount: [%ld], maxRetries: [%ld], dismissing the web view, reason: [resource-failure-retries-exhausted], detail: [%@]", __FUNCTION__, (long)self.resourceRetryCount, (long)kCLYMaxResourceRetries, reason);
        [self closeWebView];
        return;
    }

    self.resourceRetryCount += 1;
    // Cancel the in-flight stall timer: we have committed to a reload, and the reload's
    // own didStartProvisionalNavigation: will arm a fresh one. Leaving the old timer live
    // risks a spurious loadDidTimeout in the reload-delay window.
    [self.loadTimeoutTimer invalidate];
    self.loadTimeoutTimer = nil;
    NSTimeInterval delay = kCLYResourceRetryBaseDelay * self.resourceRetryCount;
    CLY_LOG_D(@"%s scheduling a reload, retry: [%ld], maxRetries: [%ld], delay: [%.1f] seconds, reason: [%@]", __FUNCTION__, (long)self.resourceRetryCount, (long)kCLYMaxResourceRetries, delay, reason);

    __weak typeof(self) weakSelf = self;
    // Cancellable so a load that succeeds during the delay window can cancel this reload
    // (see cancelPendingReload / notifyPageLoaded). Otherwise a stale reload would wipe the
    // now-good page and re-fire the page's on-load [CLY]_content_shown.
    dispatch_block_t reloadBlock = dispatch_block_create(0, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.pendingReloadBlock = nil;
        // hasAppeared / webViewClosed are belt-and-suspenders: a successful load normally
        // cancels this block outright, but never reload content that already loaded/closed.
        if (strongSelf.webViewClosed || strongSelf.hasAppeared) return;
        WKWebView *webView = strongSelf.backgroundView.webView;
        if (!webView) {
            CLY_LOG_D(@"%s the web view is gone when the reload fired, dismissing the web view, reason: [resource-failure]", __FUNCTION__);
            [strongSelf closeWebView];
            return;
        }
        CLY_LOG_D(@"%s reloading the web view now, retry: [%ld], maxRetries: [%ld]", __FUNCTION__, (long)strongSelf.resourceRetryCount, (long)kCLYMaxResourceRetries);
        [webView reload];
    });
    self.pendingReloadBlock = reloadBlock;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), reloadBlock);
}

// Cancel a reload scheduled by retryOrCloseWebViewForReason: that has not fired yet. Called
// when a load succeeds (notifyPageLoaded) or the view closes, so a stale reload can't reload a
// page that already loaded.
- (void)cancelPendingReload {
    if (self.pendingReloadBlock) {
        dispatch_block_cancel(self.pendingReloadBlock);
        self.pendingReloadBlock = nil;
    }
}

// The content never reported [CLY]_content_shown within kCLYContentShownDeadline. Close it,
// regardless of hasAppeared: if content_shown had arrived this timer would have been cancelled,
// so reaching here means nothing was ever actually shown (e.g. a blank-but-HTTP-200 page).
- (void)contentShownDeadlineReached {
    if (self.webViewClosed) return;
    CLY_LOG_W(@"%s the content never reported that it is shown, deadline: [%.0f] seconds, dismissing the web view, reason: [content-shown-deadline]", __FUNCTION__, kCLYContentShownDeadline);
    [self closeWebView];
}

// A feedback widget is presented through the same web view manager but loads a URL the SDK
// builds in the feedback module as "<host>/feedback/<type>?...&widget_id=<id>&..." (see
// CountlyFeedbackWidget generateWidgetURL), whereas content loads "<host>/_external/content?...".
// Feedback widgets never report [CLY]_content_shown, so we must not arm the content-shown
// deadline for them. Recognized by the SDK's own "/feedback/" endpoint path segment
// (kCountlyEndpointFeedback), which content URLs never contain.
- (BOOL)isFeedbackWidgetURL:(NSURL *)url {
    if (!url) return NO;
    NSString *path = url.path;
    if (!path) return NO;
    NSString *feedbackSegment = [kCountlyEndpointFeedback stringByAppendingString:@"/"];
    return [path rangeOfString:feedbackSegment].location != NSNotFound;
}

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message
{
    if (self.webViewClosed) return;

    if ([message.name isEqualToString:@"resourceLoadError"]) {
        NSDictionary *body = message.body;
        NSString *tag = body[@"tag"];
        // Host and path only: a resource URL can carry a query string. The page controlled url is
        // an untyped id, so it is type checked before NSURL sees it.
        NSString *url = [body[@"url"] isKindOfClass:NSString.class] ? body[@"url"] : nil;
        NSURL *failedResourceURL = url ? [NSURL URLWithString:url] : nil;

        CLY_LOG_D(@"%s a critical resource failed to load, resourceKind: [%@], host: [%@], path: [%@]", __FUNCTION__, tag, failedResourceURL.host, failedResourceURL.path);

        CLY_LOG_D(@"%s the failed critical resource detail, resourceKind: [%@], url: [%@], messageBody: [%@]", __FUNCTION__, tag, url, message.body);

        NSString *reason = [NSString stringWithFormat:@"a critical resource failed to load, resourceKind: [%@]", tag];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self retryOrCloseWebViewForReason:reason];
        });
    }
    else if ([message.name isEqualToString:@"resourceVerifyResult"]) {
        NSDictionary *body = message.body;
        NSArray *results = body[@"results"];

        if ([results isKindOfClass:[NSArray class]]) {
            BOOL anyUnreachable = NO;
            for (NSDictionary *entry in results) {
                NSInteger status = [entry[@"status"] integerValue];
                if (status >= 400) {
                    // Resource kind and status only: a resource URL can carry a query string.
                    CLY_LOG_D(@"%s the post load verification found a critical resource with an HTTP error status, resourceKind: [%@], status: [%ld]",
                              __FUNCTION__, entry[@"tag"], (long)status);
                    CLY_LOG_D(@"%s the post load verification failing resource detail, status: [%ld], entry: [%@]", __FUNCTION__, (long)status, entry);
                    // This is the post-load HEAD verification (runs on didFinishNavigation):
                    // the page has already finished loading and run its on-load JS, so a
                    // reload from here would re-fire any analytics it recorded. Do NOT retry
                    // from this path. Retries are driven only by the during-load
                    // resourceLoadError path. Defer to an in-flight retry if one is already
                    // scheduled, never tear down already-visible content, otherwise close.
                    if (self.hasAppeared || self.pendingReloadBlock) {
                        CLY_LOG_D(@"%s deferring the verified resource failure, contentVisible: [%@], reloadPending: [%@]", __FUNCTION__, self.hasAppeared ? @"YES" : @"NO", (self.pendingReloadBlock != nil) ? @"YES" : @"NO");
                        return;
                    }
                    CLY_LOG_E(@"%s a verified critical resource is broken, dismissing the web view, reason: [resource-http-error]", __FUNCTION__);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self closeWebView];
                    });
                    return;
                }
                if (status == 0) {
                    // HEAD could not reach the resource (network error, not an HTTP status).
                    anyUnreachable = YES;
                }
            }

            // A critical resource is unreachable and reload-on-stall is enabled: the content is
            // NOT verified good, so do NOT appear here. Appearing would also cancel a pending
            // reload (see notifyPageLoaded), yet an unreachable resource is exactly what a
            // reload recovers over the warm connection. Defer: an in-flight reload, or the
            // still-running load-timeout timer, will drive the retry/close. When reload-on-stall
            // is off there is no reload to protect, so keep the original show-anyway behavior.
            if (anyUnreachable && !self.hasAppeared && CountlyContentBuilderInternal.sharedInstance.enableContentReloadOnStall) {
                CLY_LOG_D(@"%s a critical resource is unreachable, resourceKind: [any], status: [0], deferring to a reload instead of appearing", __FUNCTION__);
                return;
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
        CLY_LOG_D(@"%s a content action was received, action: [%@]", __FUNCTION__, action);
        CLY_LOG_D(@"%s the content action detail, action: [%@], queryParameters: [%@]", __FUNCTION__, action, queryParameters);
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

// The action URL is percent-decoded once here (a malformed escape falls back to the raw string so
// the action is not dropped). Two params can carry a literal '&' in their value: "link" (sent
// unencoded, may hold its own query string) and a decoded "event"/"resize_me" JSON (segmentation
// strings can contain '&'). A plain '&' split would therefore mis-slice them, and the params can
// appear in any order. Instead we span the query from the END: at each step we take the right-most
// reserved marker ("&<key>=") whose value VALIDATES for that key (event/resize_me = JSON, close =
// 0/1, action = a known verb, link = has a URI scheme), record it, and shrink the span to its left.
// A marker whose value does NOT validate is treated as ordinary text inside an enclosing value (so
// it is skipped and absorbed by an outer param). What remains at the front is the comm-url-adjacent
// identifier ("cly_x_action_event=1" / "cly_widget_command=1"), parsed verbatim. Reserved-name
// limitation (documented for integrators): a value that literally contains "&<key>=<valid-value>"
// may be mis-split.
- (NSDictionary *)parseQueryString:(NSString *)url {
    NSMutableDictionary *queryDict = [NSMutableDictionary dictionary];

    NSString *decodedUrl = [url stringByRemovingPercentEncoding] ?: url;

    NSRange qMark = [decodedUrl rangeOfString:@"?"];
    if (qMark.location == NSNotFound) {
        return queryDict;
    }
    NSString *query = [decodedUrl substringFromIndex:qMark.location + 1];

    NSArray<NSString *> *reservedKeys = @[@"action", @"event", @"resize_me", @"close", @"link"];
    NSInteger end = (NSInteger)query.length;

    while (end > 0) {
        NSInteger chosenIdx = -1;
        NSString *chosenKey = nil;
        NSString *chosenValue = nil;

        // Right-to-left, pick the first reserved marker whose value validates. Scanning from the
        // right lets an inner (invalid) marker be absorbed into an outer, valid value.
        NSInteger searchFrom = end;
        while (searchFrom > 0) {
            NSInteger marker = -1;
            NSString *markerKey = nil;
            for (NSString *key in reservedKeys) {
                NSString *needle = [NSString stringWithFormat:@"&%@=", key];
                NSRange r = [query rangeOfString:needle options:NSBackwardsSearch range:NSMakeRange(0, searchFrom)];
                if (r.location != NSNotFound && (NSInteger)r.location > marker && (NSInteger)(r.location + needle.length) <= end) {
                    marker = (NSInteger)r.location;
                    markerKey = key;
                }
            }
            if (marker < 0) {
                break;
            }
            NSInteger valueStart = marker + (NSInteger)markerKey.length + 2; // "&" + key + "="
            NSString *value = [query substringWithRange:NSMakeRange(valueStart, end - valueStart)];
            if ([self isReservedValue:value validForKey:markerKey]) {
                chosenIdx = marker;
                chosenKey = markerKey;
                chosenValue = value;
                break;
            }
            // Not a real param -> ordinary text; keep looking further left.
            searchFrom = marker;
        }

        if (chosenIdx < 0) {
            break;
        }
        queryDict[chosenKey] = chosenValue;
        end = chosenIdx;
    }

    // Remaining prefix is the identifier param(s) adjacent to the comm URL.
    NSString *head = [query substringToIndex:end];
    for (NSString *pair in [head componentsSeparatedByString:@"&"]) {
        NSRange eq = [pair rangeOfString:@"="];
        if (eq.location != NSNotFound) {
            queryDict[[pair substringToIndex:eq.location]] = [pair substringFromIndex:eq.location + 1];
        }
    }

    return queryDict;
}

// Validates a reserved param value. Returns NO if it does not validate (meaning the "&<key>=" was
// actually text inside an enclosing value, not a real parameter).
- (BOOL)isReservedValue:(NSString *)value validForKey:(NSString *)key {
    if ([key isEqualToString:@"event"]) {
        return [self isValidJSONOfClass:[NSArray class] string:value];
    } else if ([key isEqualToString:@"resize_me"]) {
        return [self isValidJSONOfClass:[NSDictionary class] string:value];
    } else if ([key isEqualToString:@"close"]) {
        return [value isEqualToString:@"0"] || [value isEqualToString:@"1"];
    } else if ([key isEqualToString:@"action"]) {
        return [value isEqualToString:@"event"] || [value isEqualToString:@"link"] || [value isEqualToString:@"resize_me"];
    } else if ([key isEqualToString:@"link"]) {
        return [self hasURIScheme:value];
    }
    return NO;
}

- (BOOL)isValidJSONOfClass:(Class)klass string:(NSString *)value {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) {
        return NO;
    }
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [obj isKindOfClass:klass];
}

// YES if value begins with a URI scheme (ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ) ":"), covering
// http(s) URLs and custom-scheme deeplinks. The server prepends "https://" to schemeless links, so
// a valid link value always carries a scheme.
- (BOOL)hasURIScheme:(NSString *)value {
    NSRange colon = [value rangeOfString:@":"];
    if (colon.location == NSNotFound || colon.location == 0) {
        return NO;
    }
    for (NSUInteger i = 0; i < colon.location; i++) {
        unichar c = [value characterAtIndex:i];
        BOOL ok;
        if (i == 0) {
            ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');
        } else {
            ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '+' || c == '-' || c == '.';
        }
        if (!ok) {
            return NO;
        }
    }
    return YES;
}

- (void)recordEventsWithJSONString:(NSString *)jsonString {
    // The value is already percent-decoded by parseQueryString; use it directly.
    NSString *decodedString = jsonString;

    // Convert the decoded string to NSData
    NSData *data = [decodedString dataUsingEncoding:NSUTF8StringEncoding];

    // Parse the JSON data
    NSError *error = nil;
    NSArray *events = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];

    if (error) {
        CLY_LOG_D(@"%s parsing the content events JSON failed, error: [%@], domain: [%@], code: [%ld], jsonLength: [%lu]", __FUNCTION__, error.localizedDescription, error.domain, (long)error.code, (unsigned long)jsonString.length);
    }

    CLY_LOG_D(@"%s content events JSON parsed, json: [%@], events: [%@]", __FUNCTION__, jsonString, events);

    if (!events || ![events isKindOfClass:[NSArray class]]) {
            CLY_LOG_E(@"%s the content events payload is nil or not an array, ignoring the action", __FUNCTION__);
            return;
    }
    NSUInteger skippedCount = 0;
    for (NSDictionary *event in events) {
            NSString *key = event[@"key"];
            NSDictionary *segmentation = event[@"segmentation"];
            NSDictionary *sg = event[@"sg"];
            if(!key) {
                CLY_LOG_V(@"%s skipping a content event, reason: [the event key is nil or empty]", __FUNCTION__);
                skippedCount++;
                continue;
            }
            if(sg) {
                segmentation = sg;
            }
            if(!segmentation) {
                CLY_LOG_V(@"%s skipping a content event, reason: [the event has no segmentation], key: [%@]", __FUNCTION__, key);
                skippedCount++;
                continue;
            }

            // The page reported it is actually showing content: cancel the absolute
            // content-shown deadline so a genuinely-displayed content is never torn down.
            if ([key isEqualToString:@"[CLY]_content_shown"]) {
                CLY_LOG_D(@"%s the page reported that the content is shown, cancelling the content shown deadline", __FUNCTION__);
                [self.contentShownDeadlineTimer invalidate];
                self.contentShownDeadlineTimer = nil;
            }

            CLY_LOG_D(@"%s recording a content event, key: [%@], segmentation: [%@]", __FUNCTION__, key, segmentation);

            [Countly.sharedInstance recordEvent:key segmentation:segmentation];
    }

    if (skippedCount) {
        CLY_LOG_D(@"%s some content events were dropped, dropped: [%lu], recorded: [%lu]", __FUNCTION__, (unsigned long)skippedCount, (unsigned long)(events.count - skippedCount));
    } else {
        CLY_LOG_I(@"%s content events recorded, count: [%lu]", __FUNCTION__, (unsigned long)events.count);
    }

    [CountlyConnectionManager.sharedInstance attemptToSendStoredRequests];
}

- (void)openExternalLink:(NSString *)urlString {
    CLY_LOG_D(@"%s an external link was requested by the content, link: [%@]", __FUNCTION__, urlString);
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        // The decoded link may contain characters NSURL rejects (e.g. a space from a decoded '%20').
        // Re-encode the illegal characters while preserving URL structure, then retry.
        NSString *encoded = [urlString stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLFragmentAllowedCharacterSet]];
        url = encoded ? [NSURL URLWithString:encoded] : nil;
    }
    // Prefers the app (Universal Link) when enableUniversalLinkHandling is on, else browser.
    [self openExternalURL:url];
}

- (void)resizeWebViewWithJSONString:(NSString *)jsonString {

    // The value is already percent-decoded by parseQueryString; use it directly.
    NSString *decodedString = jsonString;

    // Convert the decoded string to NSData
    NSData *data = [decodedString dataUsingEncoding:NSUTF8StringEncoding];

    // Parse the JSON data
    NSError *error = nil;
    NSDictionary *resizeDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];

    if (!resizeDict) {
        CLY_LOG_E(@"%s parsing the resize JSON failed or it was empty, error: [%@], jsonLength: [%lu]", __FUNCTION__, error.localizedDescription, (unsigned long)jsonString.length);
        return;
    }

    // Ensure resizeDict is a dictionary
    if (![resizeDict isKindOfClass:[NSDictionary class]]) {
        CLY_LOG_E(@"%s the resize payload is not a dictionary, ignoring the resize", __FUNCTION__);
        return;
    }

    CLY_LOG_D(@"%s the resize payload parsed, json: [%@], resizeDict: [%@]", __FUNCTION__, jsonString, resizeDict);

    // Retrieve portrait and landscape dimensions
    NSDictionary *portraitDimensions = resizeDict[@"p"];
    NSDictionary *landscapeDimensions = resizeDict[@"l"];

    if (!portraitDimensions && !landscapeDimensions) {
        CLY_LOG_W(@"%s the resize payload carries neither portrait nor landscape dimensions, ignoring the resize", __FUNCTION__);
        return;
    }

    // Prefer the window the content is in over interfaceOrientation, which can disagree.
    UIWindow *ownWindow = self.backgroundView.window;
    BOOL isLandscape;
    if (ownWindow && !CGRectIsEmpty(ownWindow.bounds)) {
        isLandscape = ownWindow.bounds.size.width > ownWindow.bounds.size.height;
    } else {
        isLandscape = UIInterfaceOrientationIsLandscape([CountlyCommon.sharedInstance interfaceOrientation]);
    }

    // Content pinned to portrait must stay portrait even if the page asks for landscape.
    if (!self.isFeedbackWidget && CountlyContentBuilderInternal.sharedInstance.disableRotation) {
        isLandscape = NO;
    }

    // Select the appropriate dimensions based on orientation
    NSDictionary *dimensions = isLandscape ? landscapeDimensions : portraitDimensions;
    if (!dimensions) {
        dimensions = isLandscape ? portraitDimensions : landscapeDimensions;
    }

    CGRect base = [self rectFromDimensions:dimensions];

    // Animate the resizing of the web view
    [UIView animateWithDuration:0.3 animations:^{
        self.backgroundView.baseWebViewFrame = base;
        self.backgroundView.webView.frame = base;
        [self.presentingController updatePlacementRespectToSafeAreas];
    } completion:^(BOOL finished) {
        CLY_LOG_D(@"%s the web view was resized on the page's request, frame: [%@], finished: [%@]", __FUNCTION__, NSStringFromCGRect(base), finished ? @"YES" : @"NO");
    }];
}

- (CGRect)rectFromDimensions:(NSDictionary *)dimensions {
    return CGRectMake([dimensions[@"x"] floatValue],
                      [dimensions[@"y"] floatValue],
                      [dimensions[@"w"] floatValue],
                      [dimensions[@"h"] floatValue]);
}

- (void)closeWebView
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.backgroundView.webView) {
            CLY_LOG_D(@"%s the web view is already dismissed, skipping this dismissal", __FUNCTION__);
            return;
        }
        CLY_LOG_I(@"%s dismissing the web view, hadAppeared: [%@], resourceRetryCount: [%ld], dismissCallbackProvided: [%@]", __FUNCTION__, self.hasAppeared ? @"YES" : @"NO", (long)self.resourceRetryCount, (self.dismissBlock != nil) ? @"YES" : @"NO");
        self.webViewClosed = YES;
        self.window.hidden = YES;
        self.loadStartDate = nil;
        [self.loadTimeoutTimer invalidate];
        self.loadTimeoutTimer = nil;
        [self.contentShownDeadlineTimer invalidate];
        self.contentShownDeadlineTimer = nil;
        [self cancelPendingReload];
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
    CLY_LOG_D(@"%s the web view load stalled, timeout: [%.1f] seconds, routing it through the retry path", __FUNCTION__, self.loadTimeoutInterval);
    // A stalled load fires no JS 'error' event, so it never reaches the resource-error
    // retry path. Route it through the same retry here: reload (observed to recover)
    // up to the retry cap, then close. Do NOT set webViewClosed first — that would make
    // retryOrCloseWebViewForReason: bail out before it can retry.
    [self retryOrCloseWebViewForReason:@"the load stalled with no appearance"];
}
  #endif
@end
#endif
