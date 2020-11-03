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

@interface CountlyFeedbackWidget ()
@property (nonatomic) CLYFeedbackWidgetType type;
@property (nonatomic) NSString* ID;
@property (nonatomic) NSString* name;
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
            webVC = nil;
        }];

        [self recordReservedEventForDismissing];
    };
    [webVC.view addSubview:dismissButton];
    [dismissButton positionToTopRightConsideringStatusBar];

    [CountlyCommon.sharedInstance tryPresentingViewController:webVC];
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
    if (!CountlyConsentManager.sharedInstance.consentForFeedback)
        return;

    NSString* eventName = [kCountlyReservedEventPrefix stringByAppendingString:self.type];
    NSMutableDictionary* segmentation = NSMutableDictionary.new;
    segmentation[kCountlyFBKeyPlatform] = CountlyDeviceInfo.osName;
    segmentation[kCountlyFBKeyAppVersion] = CountlyDeviceInfo.appVersion;
    segmentation[kCountlyFBKeyClosed] =  @1;
    segmentation[kCountlyFBKeyWidgetID] = self.ID;
    [Countly.sharedInstance recordReservedEvent:eventName segmentation:segmentation];
}

- (NSString *)description
{
    NSString *customDescription = [NSString stringWithFormat:@"\rID: %@, Type: %@ \rName: %@", self.ID, self.type, self.name];
    return [[super description] stringByAppendingString:customDescription];
}

#endif
@end
