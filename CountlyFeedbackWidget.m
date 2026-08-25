// CountlyFeedbackWidget.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"
#import "CountlyWebViewManager.h"
#if (TARGET_OS_IOS || TARGET_OS_VISION)
#import <WebKit/WebKit.h>
#endif

CLYFeedbackWidgetType const CLYFeedbackWidgetTypeSurvey = @"survey";
CLYFeedbackWidgetType const CLYFeedbackWidgetTypeNPS    = @"nps";
CLYFeedbackWidgetType const CLYFeedbackWidgetTypeRating = @"rating";

NSString* const kCountlyReservedEventSurvey = @"[CLY]_survey";
NSString* const kCountlyReservedEventNPS    = @"[CLY]_nps";
NSString* const kCountlyReservedEventRating = @"[CLY]_star_rating";

NSString* const kCountlyFBKeyClosed         = @"closed";
NSString* const kCountlyFBKeyShown          = @"shown";

#if (TARGET_OS_IOS || TARGET_OS_VISION)
@interface CountlyFeedbackWidget () <WKNavigationDelegate>
#else
@interface CountlyFeedbackWidget ()
#endif
@property (nonatomic) CLYFeedbackWidgetType type;
@property (nonatomic) NSString* ID;
@property (nonatomic) NSString* name;
@property (nonatomic) NSString* widgetVersion;
@property (nonatomic) NSArray<NSString*>* tags;
@property (nonatomic) NSDictionary* data;
@property (nonatomic) WidgetCallback widgetCallback;
#if (TARGET_OS_IOS || TARGET_OS_VISION)
@property (nonatomic) CLYInternalViewController* webVC;
#endif
@end


@implementation CountlyFeedbackWidget
#if (TARGET_OS_IOS || TARGET_OS_VISION)

+ (CountlyFeedbackWidget *)createWithDictionary:(NSDictionary *)dictionary
{
    CountlyFeedbackWidget *feedback = CountlyFeedbackWidget.new;
    feedback.ID = dictionary[kCountlyFBKeyID];
    feedback.type = dictionary[@"type"];
    feedback.name = dictionary[@"name"];
    feedback.tags = dictionary[@"tg"];
    feedback.widgetVersion = dictionary[@"wv"];
    CLY_LOG_V(@"%s feedback widget parsed from the list response, widgetID: [%@], widgetType: [%@]", __FUNCTION__, feedback.ID, feedback.type);
    return feedback;
}

- (void)present
{
    CLY_LOG_I(@"%s widget presentation requested without any block, widgetID: [%@], widgetType: [%@]", __FUNCTION__, self.ID, self.type);
    
    [self presentWithAppearBlock:nil andDismissBlock:nil];
}

- (void)presentWithAppearBlock:(void(^ __nullable)(void))appearBlock andDismissBlock:(void(^ __nullable)(void))dismissBlock
{
    CLY_LOG_I(@"%s widget presentation requested, widgetID: [%@], widgetType: [%@], appearBlockProvided: [%@], dismissBlockProvided: [%@]", __FUNCTION__, self.ID, self.type, (appearBlock != nil) ? @"YES" : @"NO", (dismissBlock != nil) ? @"YES" : @"NO");
    id widgetCallback = ^(WidgetState widgetState) {
        if(appearBlock && widgetState == WIDGET_APPEARED) {
            appearBlock();
        }
        
        if(dismissBlock && widgetState == WIDGET_CLOSED) {
            dismissBlock();
        }
    };
    
    [self presentWithCallback:widgetCallback];
}

- (void)presentWidget_new:(WidgetCallback) widgetCallback;
{
    CLY_LOG_I(@"%s new style widget presentation requested, widgetID: [%@], widgetType: [%@], callbackProvided: [%@]", __FUNCTION__, self.ID, self.type, (widgetCallback != nil) ? @"YES" : @"NO");
    if (!CountlyConsentManager.sharedInstance.consentForFeedback)
    {
        CLY_LOG_V(@"%s no feedback consent given, new style widget will not be presented", __FUNCTION__);
        return;
    }
    
    CGSize size = [CountlyCommon.sharedInstance getWindowSize];
    
    dispatch_async(dispatch_get_main_queue(), ^ {
        CGRect frame = CGRectMake(0.0, 0.0, size.width, size.height);
        
        // Log the frame the widget web view will be placed in
        CLY_LOG_D(@"%s widget web view placement computed, widgetID: [%@], width: [%.2f], height: [%.2f]", __FUNCTION__, self.ID, frame.size.width, frame.size.height);
        
        CountlyWebViewManager* webViewManager =  CountlyWebViewManager.new;
            [webViewManager createWebViewWithURL:[self generateWidgetURL] frame:frame appearBlock:^
             {
                CLY_LOG_I(@"%s new style widget shown, widgetID: [%@], widgetType: [%@]", __FUNCTION__, self.ID, self.type);
                if(widgetCallback)
                    widgetCallback(WIDGET_APPEARED);
            } dismissBlock:^
             {
                CLY_LOG_I(@"%s new style widget dismissed, widgetID: [%@], widgetType: [%@]", __FUNCTION__, self.ID, self.type);
                if (widgetCallback)
                    widgetCallback(WIDGET_CLOSED);
                [self recordReservedEventForDismissing];
            }];
    });
}

- (void)presentWithCallback:(WidgetCallback) widgetCallback;
{
    CLY_LOG_I(@"%s widget presentation with a callback requested, widgetID: [%@], widgetType: [%@], callbackProvided: [%@]", __FUNCTION__, self.ID, self.type, (widgetCallback != nil) ? @"YES" : @"NO");
    if (!CountlyConsentManager.sharedInstance.consentForFeedback)
    {
        CLY_LOG_V(@"%s no feedback consent given, widget will not be presented", __FUNCTION__);
        return;
    }
        
    if (self.widgetVersion && ![self.widgetVersion isKindOfClass:[NSNull class]]) {
        [self presentWidget_new:widgetCallback];
        return;
    }
    
    __block CLYInternalViewController* webVC = CLYInternalViewController.new;
    webVC.view.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.4];
    webVC.modalPresentationStyle = UIModalPresentationCustom;
    
    // Configure WKWebView with non-persistent data store
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
    WKWebView* webView = [[WKWebView alloc] initWithFrame:webVC.view.bounds configuration:configuration];
    webView.navigationDelegate = self;
    webView.layer.shadowColor = UIColor.blackColor.CGColor;
    webView.layer.shadowOpacity = 0.5;
    webView.layer.shadowOffset = CGSizeMake(0.0f, 5.0f);
    webView.layer.masksToBounds = NO;
    
    webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [webVC.view addSubview:webView];
    webVC.webView = webView;
    self.webVC = webVC;
    self.widgetCallback = widgetCallback;
    NSURLRequest* request = [NSURLRequest requestWithURL:[self generateWidgetURL]];
    [webView loadRequest:request];
    
    CLYButton* dismissButton = [CLYButton dismissAlertButton];
    dismissButton.onClick = ^(id sender)
    {
        [webVC dismissViewControllerAnimated:YES completion:^
        {
            CLY_LOG_I(@"%s legacy style widget dismissed by the close button, widgetID: [%@], widgetType: [%@]", __FUNCTION__, self.ID, self.type);
            if (widgetCallback)
                widgetCallback(WIDGET_CLOSED);
            webVC = nil;
        }];
        [self recordReservedEventForDismissing];
    };
    [webView addSubview:dismissButton];
    [dismissButton positionToTopRight];
    [CountlyCommon.sharedInstance tryPresentingViewController:webVC withCompletion:^{
        CLY_LOG_I(@"%s legacy style widget shown, widgetID: [%@], widgetType: [%@]", __FUNCTION__, self.ID, self.type);
        if(widgetCallback)
            widgetCallback(WIDGET_APPEARED);
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

    CLY_LOG_D(@"%s widget navigation response received, widgetID: [%@], path: [%@], mimeType: [%@], statusCode: [%ld], headerCount: [%lu]",
              __FUNCTION__, self.ID, response.URL.path, mimeType, statusCode, (unsigned long)headers.count);

    CLY_LOG_D(@"%s widget navigation response detail, widgetID: [%@], url: [%@], headers: [%@]", __FUNCTION__, self.ID, response.URL.absoluteString, headers);

    if (statusCode >= 400) {
        CLY_LOG_E(@"%s widget navigation cancelled and widget dismissed, widgetID: [%@], statusCode: [%ld]", __FUNCTION__, self.ID, statusCode);
        decisionHandler(WKNavigationResponsePolicyCancel);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.webVC) {
                [self.webVC dismissViewControllerAnimated:YES completion:^{
                    if (self.widgetCallback) {
                        self.widgetCallback(WIDGET_CLOSED);
                    }
                }];
                self.webVC = nil;
                self.widgetCallback = nil;
            }
        });
        return;
    }

    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)getWidgetData:(void (^)(NSDictionary * __nullable widgetData, NSError * __nullable error))completionHandler
{
    CLY_LOG_I(@"%s widget data fetch requested, widgetID: [%@], widgetType: [%@], completionHandlerProvided: [%@]", __FUNCTION__, self.ID, self.type, (completionHandler != nil) ? @"YES" : @"NO");
    
    if (!CountlyServerConfig.sharedInstance.networkingEnabled)
    {
        CLY_LOG_D(@"%s widget data fetch is dropped, networking is disabled by server config", __FUNCTION__);
        return;
    }
    
    NSURLSessionTask* task = [CountlyCommon.sharedInstance.ImmediateURLSession dataTaskWithRequest:[self dataRequest] completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
    {
        // IMMEDIATE REQUEST to find them better in search
        NSDictionary *widgetData = nil;
        
        if (!error)
        {
            widgetData = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        }
        
        if (!error)
        {
            if (((NSHTTPURLResponse*)response).statusCode != 200)
            {
                NSMutableDictionary* userInfo = widgetData.mutableCopy;
                userInfo[NSLocalizedDescriptionKey] = @"Feedbacks general API error";
                error = [NSError errorWithDomain:kCountlyErrorDomain code:CLYErrorFeedbacksGeneralAPIError userInfo:userInfo];
            }
        }
        
        if (error)
            CLY_LOG_W(@"%s widget data fetch failed, widgetID: [%@], error: [%@]", __FUNCTION__, self.ID, error.localizedDescription);
        else
            CLY_LOG_D(@"%s widget data fetched, widgetID: [%@], fieldCount: [%lu]", __FUNCTION__, self.ID, (unsigned long)widgetData.count);

        CLY_LOG_D(@"%s widget data fetch response detail, widgetID: [%@], url: [%@], widgetData: [%@]", __FUNCTION__, self.ID, response.URL.absoluteString, widgetData);

        self.data = widgetData;
        
        dispatch_async(dispatch_get_main_queue(), ^
        {
            if (completionHandler)
                completionHandler(widgetData, error);
        });
    }];
    
    [task resume];
}

- (void)recordResult:(NSDictionary * __nullable)result
{
    CLY_LOG_I(@"%s widget result recording requested, widgetID: [%@], widgetType: [%@], answeredFieldCount: [%lu]", __FUNCTION__, self.ID, self.type, (unsigned long)result.count);
    CLY_LOG_D(@"%s widget result recording detail, widgetID: [%@], widgetType: [%@], result: [%@]", __FUNCTION__, self.ID, self.type, result);

    if (!result)
        [self recordReservedEventForDismissing];
    else
        [self recordReservedEventWithSegmentation:result];
}

- (NSURLRequest *)dataRequest
{
    NSString* queryString = [NSString stringWithFormat:@"%@=%@&%@=%@&%@=%@&%@=%@&%@=%@&%@=%@",
                             kCountlyQSKeySDKName, CountlyCommon.sharedInstance.SDKName,
                             kCountlyQSKeySDKVersion, CountlyCommon.sharedInstance.SDKVersion,
                             kCountlyFBKeyAppVersion, CountlyDeviceInfo.appVersion,
                             kCountlyFBKeyPlatform, CountlyDeviceInfo.osName,
                             kCountlyFBKeyShown, @"1",
                             kCountlyFBKeyWidgetID, self.ID];
    
    queryString = [queryString stringByAppendingFormat:@"&%@=%@",
                   kCountlyAppVersionKey, CountlyDeviceInfo.appVersion];
    
    queryString = [CountlyConnectionManager.sharedInstance appendChecksum:queryString];
    
    NSMutableString* URL = CountlyConnectionManager.sharedInstance.host.mutableCopy;
    [URL appendString:kCountlyEndpointO];
    [URL appendString:kCountlyEndpointSurveys];
    NSString* feedbackTypeEndpoint = [@"/" stringByAppendingString:self.type];
    [URL appendString:feedbackTypeEndpoint];
    [URL appendString:kCountlyEndpointWidget];
    
    if (queryString.length > kCountlyGETRequestMaxLength || CountlyConnectionManager.sharedInstance.alwaysUsePOST)
    {
        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:URL]];
        request.HTTPMethod = @"POST";
        request.HTTPBody = [queryString cly_dataUTF8];
        CLY_LOG_V(@"%s widget data request built as POST, widgetID: [%@], url: [%@], body: [%@]", __FUNCTION__, self.ID, URL, queryString);
        return request.copy;
    }
    else
    {
        [URL appendFormat:@"?%@", queryString];
        NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:URL]];
        CLY_LOG_V(@"%s widget data request built as GET, widgetID: [%@], url: [%@]", __FUNCTION__, self.ID, URL);
        return request;
    }
}

- (NSURL *)generateWidgetURL {
    // Create the base URL with endpoint and feedback type
    NSMutableString *URL = [NSMutableString stringWithFormat:@"%@%@/%@",
                            CountlyConnectionManager.sharedInstance.host,
                            kCountlyEndpointFeedback,
                            self.type];
    
    // Create a dictionary for query parameters
    NSDictionary *queryParams = @{
        kCountlyQSKeyAppKey: CountlyConnectionManager.sharedInstance.appKey.cly_URLEscaped,
        kCountlyQSKeyDeviceID: CountlyDeviceInfo.sharedInstance.deviceID.cly_URLEscaped,
        kCountlyQSKeySDKName: CountlyCommon.sharedInstance.SDKName,
        kCountlyQSKeySDKVersion: CountlyCommon.sharedInstance.SDKVersion,
        kCountlyFBKeyAppVersion: CountlyDeviceInfo.appVersion,
        kCountlyFBKeyPlatform: CountlyDeviceInfo.osName,
        kCountlyFBKeyWidgetID: self.ID,
        kCountlyAppVersionKey: CountlyDeviceInfo.appVersion,
    };
    
    // Create the query string
    NSMutableArray *queryItems = [NSMutableArray array];
    [queryParams enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        [queryItems addObject:[NSString stringWithFormat:@"%@=%@", key, obj]];
    }];
    
    NSString *queryString = [queryItems componentsJoinedByString:@"&"];
    
    // Append checksum to the query string
    queryString = [CountlyConnectionManager.sharedInstance appendChecksum:queryString];
    
    // Add the query string to the URL
    [URL appendFormat:@"?%@", queryString];
    
    // Create custom parameters
    NSMutableDictionary *customParams = [@{@"tc": @"1"} mutableCopy];
    
    if (self.widgetVersion && ![self.widgetVersion isKindOfClass:[NSNull class]]) {
        customParams[@"rw"] = @"1";
        customParams[@"xb"] = @"1";
    }
    
    // Create JSON data from custom parameters
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:customParams options:0 error:&error];
    
    if (!jsonData) {
        CLY_LOG_E(@"%s custom widget URL parameters could not be serialized, widgetID: [%@], error: [%@]", __FUNCTION__, self.ID, error.localizedDescription);
    } else {
        NSString *customString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        // Append the custom parameter to the URL
        [URL appendFormat:@"&custom=%@", customString.cly_URLEscaped];
    }

    NSString *finalURL = [CountlyDeviceInfo URLStringByAppendingThemeMode:URL];

    CLY_LOG_V(@"%s widget URL generated, widgetID: [%@], widgetType: [%@], url: [%@]", __FUNCTION__, self.ID, self.type, finalURL);

    return [NSURL URLWithString:finalURL];
}


- (void)recordReservedEventForDismissing
{
    [self recordReservedEventWithSegmentation:@{kCountlyFBKeyClosed: @1}];
}

- (void)recordReservedEventWithSegmentation:(NSDictionary *)segm
{
    if (!CountlyConsentManager.sharedInstance.consentForFeedback)
    {
        CLY_LOG_V(@"%s no feedback consent given, widget result event is not recorded", __FUNCTION__);
        return;
    }
    
    NSString* eventName = nil;
    if ([self.type isEqualToString:CLYFeedbackWidgetTypeSurvey])
        eventName = kCountlyReservedEventSurvey;
    else if ([self.type isEqualToString:CLYFeedbackWidgetTypeNPS])
        eventName = kCountlyReservedEventNPS;
    else if ([self.type isEqualToString:CLYFeedbackWidgetTypeRating])
        eventName = kCountlyReservedEventRating;
    
    if (!eventName)
    {
        CLY_LOG_W(@"%s widget result event is dropped, unsupported widget type, widgetID: [%@], widgetType: [%@]", __FUNCTION__, self.ID, self.type);
        return;
    }
    
    NSMutableDictionary* segmentation = segm.mutableCopy;
    segmentation[kCountlyFBKeyPlatform] = CountlyDeviceInfo.osName;
    segmentation[kCountlyFBKeyAppVersion] = CountlyDeviceInfo.appVersion;
    segmentation[kCountlyFBKeyWidgetID] = self.ID;

    CLY_LOG_I(@"%s widget result submitted, widgetID: [%@], widgetType: [%@], submittedFieldCount: [%lu]", __FUNCTION__, self.ID, self.type, (unsigned long)segm.count);

    CLY_LOG_D(@"%s widget result submission detail, widgetID: [%@], eventName: [%@], answers: [%@], segmentation: [%@]", __FUNCTION__, self.ID, eventName, segm, segmentation);

    [Countly.sharedInstance recordReservedEvent:eventName segmentation:segmentation];
    
    [CountlyConnectionManager.sharedInstance sendEvents];
}

- (NSString *)description
{
    NSString *customDescription = [NSString stringWithFormat:@"\rID: %@, Type: %@ \rName: %@ \rTags: %@", self.ID, self.type, self.name, self.tags];
    return [[super description] stringByAppendingString:customDescription];
}

#endif
@end
