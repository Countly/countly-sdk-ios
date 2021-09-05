// CountlyFeedbackWidget.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"
#if (TARGET_OS_IOS)
#import <WebKit/WebKit.h>
#endif

CLYFeedbackWidgetType const CLYFeedbackWidgetTypeSurvey     = @"survey";
CLYFeedbackWidgetType const CLYFeedbackWidgetTypeNPS        = @"nps";

NSString* const kCountlyReservedEventPrefix = @"[CLY]_"; //NOTE: This will be used with feedback type.
NSString* const kCountlyFBKeyClosed         = @"closed";
NSString* const kCountlyFBKeyShown          = @"shown";

@interface CountlyFeedbackWidget ()
@property (nonatomic) CLYFeedbackWidgetType type;
@property (nonatomic) NSString* ID;
@property (nonatomic) NSString* name;
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
    return feedback;
}

- (void)present
{
    [self presentWithAppearBlock:nil andDismissBlock:nil];
}

- (void)presentWithAppearBlock:(void(^ __nullable)(void))appearBlock andDismissBlock:(void(^ __nullable)(void))dismissBlock;
{
    if (!CountlyConsentManager.sharedInstance.consentForFeedback)
        return;

    __block CLYInternalViewController* webVC = CLYInternalViewController.new;
    webVC.view.backgroundColor = UIColor.whiteColor;
    webVC.view.bounds = UIScreen.mainScreen.bounds;
    webVC.modalPresentationStyle = UIModalPresentationCustom;

    WKWebView* webView = [WKWebView.alloc initWithFrame:webVC.view.bounds];
    webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [webVC.view addSubview:webView];
    NSURLRequest* request = [self displayRequest];
    [webView loadRequest:request];

    CLYButton* dismissButton = [CLYButton dismissAlertButton];
    dismissButton.onClick = ^(id sender)
    {
        [webVC dismissViewControllerAnimated:YES completion:^
        {
            if (dismissBlock)
                dismissBlock();

            webVC = nil;
        }];

        [self recordReservedEventForDismissing];
    };
    [webVC.view addSubview:dismissButton];
    [dismissButton positionToTopRightConsideringStatusBar];

    [CountlyCommon.sharedInstance tryPresentingViewController:webVC withCompletion:appearBlock];
}

- (void)getWidgetData:(void (^)(NSDictionary * __nullable widgetData, NSError * __nullable error))completionHandler
{
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

- (NSURLRequest *)displayRequest
{
    NSString* queryString = [NSString stringWithFormat:@"%@=%@&%@=%@&%@=%@&%@=%@&%@=%@&%@=%@&%@=%@",
        kCountlyQSKeyAppKey, CountlyConnectionManager.sharedInstance.appKey.cly_URLEscaped,
        kCountlyQSKeyDeviceID, CountlyDeviceInfo.sharedInstance.deviceID.cly_URLEscaped,
        kCountlyQSKeySDKName, CountlyCommon.sharedInstance.SDKName,
        kCountlyQSKeySDKVersion, CountlyCommon.sharedInstance.SDKVersion,
        kCountlyFBKeyAppVersion, CountlyDeviceInfo.appVersion,
        kCountlyFBKeyPlatform, CountlyDeviceInfo.osName,
        kCountlyFBKeyWidgetID, self.ID];

    queryString = [CountlyConnectionManager.sharedInstance appendChecksum:queryString];

    NSMutableString* URL = CountlyConnectionManager.sharedInstance.host.mutableCopy;
    [URL appendString:kCountlyEndpointFeedback];
    NSString* feedbackTypeEndpoint = [@"/" stringByAppendingString:self.type];
    [URL appendString:feedbackTypeEndpoint];
    [URL appendFormat:@"?%@", queryString];

    NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:URL]];
    return request;
}

- (void)recordReservedEventForDismissing
{
    [self recordReservedEventWithSegmentation:@{kCountlyFBKeyClosed: @1}];
}

- (void)recordReservedEventWithSegmentation:(NSDictionary *)segm
{
    if (!CountlyConsentManager.sharedInstance.consentForFeedback)
        return;

    NSString* eventName = [kCountlyReservedEventPrefix stringByAppendingString:self.type];
    NSMutableDictionary* segmentation = segm.mutableCopy;
    segmentation[kCountlyFBKeyPlatform] = CountlyDeviceInfo.osName;
    segmentation[kCountlyFBKeyAppVersion] = CountlyDeviceInfo.appVersion;
    segmentation[kCountlyFBKeyWidgetID] = self.ID;
    [Countly.sharedInstance recordReservedEvent:eventName segmentation:segmentation];

    [CountlyConnectionManager.sharedInstance sendEvents];
}

- (NSString *)description
{
    NSString *customDescription = [NSString stringWithFormat:@"\rID: %@, Type: %@ \rName: %@", self.ID, self.type, self.name];
    return [[super description] stringByAppendingString:customDescription];
}

#endif
@end
