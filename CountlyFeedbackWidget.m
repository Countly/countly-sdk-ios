// CountlyFeedbackWidget.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"
#if (TARGET_OS_IOS)
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

@interface CountlyFeedbackWidget ()
@property (nonatomic) CLYFeedbackWidgetType type;
@property (nonatomic) NSString* ID;
@property (nonatomic) NSString* name;
@property (nonatomic) NSArray<NSString*>* tags;
@property (nonatomic) NSDictionary* data;
@end


@implementation CountlyFeedbackWidget
#if (TARGET_OS_IOS)

+ (CountlyFeedbackWidget *)createWithDictionary:(NSDictionary *)dictionary
{
    CountlyFeedbackWidget *feedback = CountlyFeedbackWidget.new;
    feedback.ID = dictionary[kCountlyFBKeyID];
    feedback.type = dictionary[@"type"];
    feedback.name = dictionary[@"name"];
    feedback.tags = dictionary[@"tg"];
    return feedback;
}

- (void)present
{
    CLY_LOG_I(@"%s", __FUNCTION__);
    
    [self presentWithAppearBlock:nil andDismissBlock:nil];
}

- (void)presentWithAppearBlock:(void(^ __nullable)(void))appearBlock andDismissBlock:(void(^ __nullable)(void))dismissBlock
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, appearBlock, dismissBlock);
    [self presentWithCallback:^(WidgetState widgetState) {
        if(appearBlock && widgetState == WIDGET_APPEARED) {
            appearBlock();
        }
        
        if(dismissBlock && widgetState == WIDGET_CLOSED) {
            dismissBlock();
        }
    }];
}

- (void)presentWithCallback:(WidgetCallback) widgetCallback;
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, widgetCallback);
    if (!CountlyConsentManager.sharedInstance.consentForFeedback)
        return;
    __block CLYInternalViewController* webVC = CLYInternalViewController.new;
    webVC.view.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.4];
    webVC.modalPresentationStyle = UIModalPresentationCustom;
    // Configure WKWebView with non-persistent data store
    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
    WKWebView* webView = [[WKWebView alloc] initWithFrame:webVC.view.bounds configuration:configuration];
    webView.layer.shadowColor = UIColor.blackColor.CGColor;
    webView.layer.shadowOpacity = 0.5;
    webView.layer.shadowOffset = CGSizeMake(0.0f, 5.0f);
    webView.layer.masksToBounds = NO;
    webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [webVC.view addSubview:webView];
    webVC.webView = webView;
    NSURLRequest* request = [self displayRequest];
    [webView loadRequest:request];
    CLYButton* dismissButton = [CLYButton dismissAlertButton];
    dismissButton.onClick = ^(id sender)
    {
        [webVC dismissViewControllerAnimated:YES completion:^
        {
            CLY_LOG_D(@"Feedback widget dismissed. Widget ID: %@, Name: %@", self.ID, self.name);
            if (widgetCallback)
                widgetCallback(WIDGET_CLOSED);
            webVC = nil;
        }];
        [self recordReservedEventForDismissing];
    };
    [webView addSubview:dismissButton];
    [dismissButton positionToTopRight];
    [CountlyCommon.sharedInstance tryPresentingViewController:webVC withCompletion:^{
        CLY_LOG_D(@"Feedback widget presented. Widget ID: %@, Name: %@", self.ID, self.name);
        if(widgetCallback)
            widgetCallback(WIDGET_APPEARED);
    }];
}

- (void)getWidgetData:(void (^)(NSDictionary * __nullable widgetData, NSError * __nullable error))completionHandler
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, completionHandler);
    
    if (!CountlyServerConfig.sharedInstance.networkingEnabled)
    {
        CLY_LOG_D(@"'getWidgetData' is aborted: SDK Networking is disabled from server config!");
        return;
    }
    
    NSURLSessionTask* task = [NSURLSession.sharedSession dataTaskWithRequest:[self dataRequest] completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
    {
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
    CLY_LOG_I(@"%s %@", __FUNCTION__, result);
    
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
        return request.copy;
    }
    else
    {
        [URL appendFormat:@"?%@", queryString];
        NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:URL]];
        return request;
    }
}

- (NSURLRequest *)displayRequest {
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
    NSDictionary *customParams = @{@"tc": @"1"};
    
    // Create JSON data from custom parameters
    NSError *error;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:customParams options:0 error:&error];
    
    if (!jsonData) {
        NSLog(@"Failed to serialize JSON: %@", error);
    } else {
        NSString *customString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
        // Append the custom parameter to the URL
        [URL appendFormat:@"&custom=%@", customString.cly_URLEscaped];
    }
    
    // Create and return the NSURLRequest
    return [NSURLRequest requestWithURL:[NSURL URLWithString:URL]];
}


- (void)recordReservedEventForDismissing
{
    [self recordReservedEventWithSegmentation:@{kCountlyFBKeyClosed: @1}];
}

- (void)recordReservedEventWithSegmentation:(NSDictionary *)segm
{
    if (!CountlyConsentManager.sharedInstance.consentForFeedback)
        return;
    
    NSString* eventName = nil;
    if ([self.type isEqualToString:CLYFeedbackWidgetTypeSurvey])
        eventName = kCountlyReservedEventSurvey;
    else if ([self.type isEqualToString:CLYFeedbackWidgetTypeNPS])
        eventName = kCountlyReservedEventNPS;
    else if ([self.type isEqualToString:CLYFeedbackWidgetTypeRating])
        eventName = kCountlyReservedEventRating;
    
    if (!eventName)
    {
        CLY_LOG_W(@"Unsupported feedback widget type! Event will not be recorded!");
        return;
    }
    
    NSMutableDictionary* segmentation = segm.mutableCopy;
    segmentation[kCountlyFBKeyPlatform] = CountlyDeviceInfo.osName;
    segmentation[kCountlyFBKeyAppVersion] = CountlyDeviceInfo.appVersion;
    segmentation[kCountlyFBKeyWidgetID] = self.ID;
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

