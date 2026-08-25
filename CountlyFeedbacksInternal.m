// CountlyFeedbacks.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"
#if (TARGET_OS_IOS || TARGET_OS_VISION)
#import <WebKit/WebKit.h>
#endif

@interface CountlyFeedbackWidget ()
+ (CountlyFeedbackWidget *)createWithDictionary:(NSDictionary *)dictionary;
@end



@interface CountlyFeedbacksInternal ()
#if (TARGET_OS_IOS || TARGET_OS_VISION)
@property (nonatomic) UIAlertController* alertController;
@property (nonatomic, copy) void (^ratingCompletion)(NSInteger);
#endif
@end

NSString* const kCountlyReservedEventStarRating = @"[CLY]_star_rating";
NSString* const kCountlyStarRatingStatusSessionCountKey = @"kCountlyStarRatingStatusSessionCountKey";
NSString* const kCountlyStarRatingStatusHasEverAskedAutomatically = @"kCountlyStarRatingStatusHasEverAskedAutomatically";

NSString* const kCountlyFBKeyPlatform       = @"platform";
NSString* const kCountlyFBKeyAppVersion     = @"app_version";
NSString* const kCountlyFBKeyRating         = @"rating";
NSString* const kCountlyFBKeyWidgetID       = @"widget_id";
NSString* const kCountlyFBKeyID             = @"_id";
NSString* const kCountlyFBKeyTargetDevices  = @"target_devices";
NSString* const kCountlyFBKeyPhone          = @"phone";
NSString* const kCountlyFBKeyTablet         = @"tablet";
NSString* const kCountlyFBKeyFeedback       = @"feedback";
NSString* const kCountlyFBKeyEmail          = @"email";
NSString* const kCountlyFBKeyComment        = @"comment";
NSString* const kCountlyFBKeyContactMe      = @"contactMe";

const CGFloat kCountlyStarRatingButtonSize = 40.0;

@implementation CountlyFeedbacksInternal
#if (TARGET_OS_IOS || TARGET_OS_VISION)
{
    UIButton* btn_star[5];
}

+ (instancetype)sharedInstance
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return nil;

    static CountlyFeedbacksInternal* s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    if (self = [super init])
    {
        NSString* langDesignator = [NSLocale.preferredLanguages.firstObject substringToIndex:2];

        NSDictionary* dictMessage =
        @{
            @"en": @"How would you rate the app?",
            @"tr": @"Uygulamayı nasıl değerlendirirsiniz?",
            @"ja": @"あなたの評価を教えてください。",
            @"zh": @"请告诉我你的评价。",
            @"ru": @"Как бы вы оценили приложение?",
            @"cz": @"Jak hodnotíte aplikaci?",
            @"lv": @"Kā Jūs novērtētu šo lietotni?",
            @"bn": @"আপনি কিভাবে এই এপ্লিক্যাশনটি মূল্যায়ন করবেন?",
            @"hi": @"आप एप्लीकेशन का मूल्यांकन कैसे करेंगे?",
        };

        self.message = dictMessage[langDesignator];
        if (!self.message)
            self.message = dictMessage[@"en"];
    }

    return self;
}

#pragma mark - Star Rating

- (void)showDialog:(void(^)(NSInteger rating))completion
{
    CLY_LOG_I(@"%s star rating dialog requested, completionProvided: [%@]", __FUNCTION__, (completion != nil) ? @"YES" : @"NO");

    if (!CountlyConsentManager.sharedInstance.consentForFeedback)
    {
        CLY_LOG_V(@"%s no feedback consent given, star rating dialog will not be shown", __FUNCTION__);
        return;
    }

    self.ratingCompletion = completion;

    self.alertController = [UIAlertController alertControllerWithTitle:@" " message:self.message preferredStyle:UIAlertControllerStyleAlert];

    CLYButton* dismissButton = [CLYButton dismissAlertButton];
    dismissButton.onClick = ^(id sender)
    {
        [self.alertController dismissViewControllerAnimated:YES completion:^
        {
            [self finishWithRating:0];
        }];
    };
    [self.alertController.view addSubview:dismissButton];
    [dismissButton positionToTopRight];

    CLYInternalViewController* cvc = CLYInternalViewController.new;
    [cvc setPreferredContentSize:(CGSize){kCountlyStarRatingButtonSize * 5, kCountlyStarRatingButtonSize * 1.5}];
    [cvc.view addSubview:[self starView]];

    @try
    {
        [self.alertController setValue:cvc forKey:@"contentViewController"];
    }
    @catch (NSException* exception)
    {
        CLY_LOG_E(@"%s contentViewController of the star rating alert can not be set, exception: [%@]", __FUNCTION__, exception.reason);
    }

    [CountlyCommon.sharedInstance tryPresentingViewController:self.alertController];
}

- (void)checkForStarRatingAutoAsk
{
    if (!self.sessionCount)
        return;

    if (!CountlyConsentManager.sharedInstance.consentForFeedback)
    {
        CLY_LOG_V(@"%s no feedback consent given, star rating auto ask check is skipped", __FUNCTION__);
        return;
    }

    NSMutableDictionary* status = [CountlyPersistency.sharedInstance retrieveStarRatingStatus].mutableCopy;

    if (self.disableAskingForEachAppVersion && status[kCountlyStarRatingStatusHasEverAskedAutomatically])
        return;

    NSString* keyForAppVersion = [kCountlyStarRatingStatusSessionCountKey stringByAppendingString:CountlyDeviceInfo.appVersion];
    NSInteger sessionCountSoFar = [status[keyForAppVersion] integerValue];
    sessionCountSoFar++;

    if (self.sessionCount == sessionCountSoFar)
    {
        CLY_LOG_D(@"%s asking for star rating as session count reached the limit, sessionCount: [%ld]", __FUNCTION__, (long)self.sessionCount);

        [self showDialog:self.ratingCompletionForAutoAsk];

        status[kCountlyStarRatingStatusHasEverAskedAutomatically] = @YES;
    }

    status[keyForAppVersion] = @(sessionCountSoFar);

    [CountlyPersistency.sharedInstance storeStarRatingStatus:status];
}

- (UIView *)starView
{
    UIView* vw_star = [UIView.alloc initWithFrame:(CGRect){0, 0, kCountlyStarRatingButtonSize * 5, kCountlyStarRatingButtonSize}];
    vw_star.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;

    for (int i = 0; i < 5; i++)
    {
        btn_star[i] = [UIButton.alloc initWithFrame:(CGRect){i * kCountlyStarRatingButtonSize, 0, kCountlyStarRatingButtonSize, kCountlyStarRatingButtonSize}];
        btn_star[i].titleLabel.font = [UIFont fontWithName:@"Helvetica" size:28];
        [btn_star[i] setTitle:@"★" forState:UIControlStateNormal];
        [btn_star[i] setTitleColor:[self passiveStarColor] forState:UIControlStateNormal];
        [btn_star[i] addTarget:self action:@selector(onClick_star:) forControlEvents:UIControlEventTouchUpInside];

        [vw_star addSubview:btn_star[i]];
    }

    return vw_star;
}

- (void)setMessage:(NSString *)message
{
    if (!message)
        return;

    _message = message;
}

- (void)onClick_star:(id)sender
{
    UIColor* color = [self activeStarColor];
    NSInteger rating = 0;

    for (int i = 0; i < 5; i++)
    {
        [btn_star[i] setTitleColor:color forState:UIControlStateNormal];

        if (btn_star[i] == sender)
        {
            color = [self passiveStarColor];
            rating = i + 1;
        }
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^
    {
        [self.alertController dismissViewControllerAnimated:YES completion:^{ [self finishWithRating:rating]; }];
    });
}

- (void)finishWithRating:(NSInteger)rating
{
    CLY_LOG_I(@"%s star rating dialog finished, widgetType: [%@], answerProvided: [%@]", __FUNCTION__, @"star-rating", (rating != 0) ? @"YES" : @"NO");

    CLY_LOG_D(@"%s star rating dialog answer detail, widgetType: [%@], rating: [%ld]", __FUNCTION__, @"star-rating", (long)rating);

    if (self.ratingCompletion)
        self.ratingCompletion(rating);

    if (rating != 0)
    {
        NSMutableDictionary* segmentation = NSMutableDictionary.new;
        segmentation[kCountlyFBKeyPlatform] = CountlyDeviceInfo.osName;
        segmentation[kCountlyFBKeyAppVersion] = CountlyDeviceInfo.appVersion;
        segmentation[kCountlyFBKeyRating] =  @(rating);

        [Countly.sharedInstance recordReservedEvent:kCountlyReservedEventStarRating segmentation:segmentation];
    }

    self.alertController = nil;
    self.ratingCompletion = nil;
}

- (UIColor *)activeStarColor
{
    return [UIColor colorWithRed:253/255.0 green:148/255.0 blue:38/255.0 alpha:1];
}

- (UIColor *)passiveStarColor
{
    return [UIColor colorWithWhite:178/255.0 alpha:1];
}

#pragma mark - Feedbacks (Ratings) (Legacy Feedback Widget)

- (void)presentRatingWidgetWithID:(NSString *)widgetID closeButtonText:(NSString *)closeButtonText completionHandler:(void (^)(NSError * error))completionHandler
{
    CLY_LOG_I(@"%s rating widget presentation requested, widgetID: [%@], closeButtonTextProvided: [%@], completionHandlerProvided: [%@]", __FUNCTION__, widgetID, (closeButtonText != nil) ? @"YES" : @"NO", (completionHandler != nil) ? @"YES" : @"NO");

    if (!CountlyServerConfig.sharedInstance.networkingEnabled)
    {
        CLY_LOG_D(@"%s rating widget presentation is dropped, networking is disabled by server config", __FUNCTION__);
        return;
    }
    
    if (!CountlyConsentManager.sharedInstance.consentForFeedback)
    {
        CLY_LOG_V(@"%s no feedback consent given, rating widget presentation is skipped", __FUNCTION__);
        return;
    }

    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
    {
        CLY_LOG_W(@"%s rating widget presentation is dropped, device ID is temporary", __FUNCTION__);
        return;
    }

    if (!widgetID.length)
    {
        CLY_LOG_E(@"%s rating widget presentation is dropped, widget ID is empty or nil", __FUNCTION__);
        return;
    }

    NSURLRequest* feedbackWidgetCheckRequest = [self widgetCheckURLRequest:widgetID];
    NSURLSessionTask* task = [CountlyCommon.sharedInstance.ImmediateURLSession dataTaskWithRequest:feedbackWidgetCheckRequest completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
    {
        // IMMEDIATE REQUEST to find them better in search
        NSDictionary* widgetInfo = nil;

        if (!error)
        {
            widgetInfo = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        }

        CLY_LOG_D(@"%s rating widget check response detail, widgetID: [%@], url: [%@], widgetInfo: [%@]", __FUNCTION__, widgetID, response.URL.absoluteString, widgetInfo);

        if (!error)
        {
            NSMutableDictionary* userInfo = widgetInfo.mutableCopy;

            if (![widgetInfo[kCountlyFBKeyID] isEqualToString:widgetID])
            {
                CLY_LOG_W(@"%s no rating widget found on the server for the given widgetID: [%@]", __FUNCTION__, widgetID);
                userInfo[NSLocalizedDescriptionKey] = [NSString stringWithFormat:@"Feedback widget with ID %@ is not available.", widgetID];
                error = [NSError errorWithDomain:kCountlyErrorDomain code:CLYErrorFeedbackWidgetNotAvailable userInfo:userInfo];
            }
            else if (![self isDeviceTargetedByWidget:widgetInfo])
            {
                CLY_LOG_D(@"%s this device is not in the target devices list of the widget, widgetID: [%@]", __FUNCTION__, widgetID);
                userInfo[NSLocalizedDescriptionKey] = [NSString stringWithFormat:@"Feedback widget with ID %@ does not include this device in target devices list.", widgetID];
                error = [NSError errorWithDomain:kCountlyErrorDomain code:CLYErrorFeedbackWidgetNotTargetedForDevice userInfo:userInfo];
            }
        }

        if (error)
        {
            CLY_LOG_W(@"%s rating widget check request failed, widgetID: [%@], error: [%@]", __FUNCTION__, widgetID, error.localizedDescription);
            dispatch_async(dispatch_get_main_queue(), ^
            {
                if (completionHandler)
                    completionHandler(error);
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^
        {
            [self presentRatingWidgetInternal:widgetID closeButtonText:closeButtonText completionHandler:completionHandler];
        });
    }];

    [task resume];
}

- (void)presentRatingWidgetInternal:(NSString *)widgetID closeButtonText:(NSString *)closeButtonText  completionHandler:(void (^)(NSError * error))completionHandler
{
    __block CLYInternalViewController* webVC = CLYInternalViewController.new;
    webVC.view.backgroundColor = UIColor.whiteColor;
    CGSize windowSize = [CountlyCommon.sharedInstance getWindowSize];
    webVC.view.bounds = CGRectMake(0, 0, windowSize.width, windowSize.height);
    webVC.modalPresentationStyle = UIModalPresentationCustom;

    WKWebView* webView = [WKWebView.alloc initWithFrame:webVC.view.bounds];
    webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [webVC.view addSubview:webView];
    NSURL* widgetDisplayURL = [self widgetDisplayURL:widgetID];
    [webView loadRequest:[NSURLRequest requestWithURL:widgetDisplayURL]];

    CLYButton* dismissButton = [CLYButton dismissAlertButton:closeButtonText];
    dismissButton.onClick = ^(id sender)
    {
        [webVC dismissViewControllerAnimated:YES completion:^
        {
            CLY_LOG_I(@"%s rating widget web view is dismissed, widgetID: [%@], widgetType: [%@]", __FUNCTION__, widgetID, CLYFeedbackWidgetTypeRating);

            if (completionHandler)
                completionHandler(nil);

            webVC = nil;
        }];
    };
    [webVC.view addSubview:dismissButton];
    [dismissButton positionToTopRightConsideringStatusBar];

    CLY_LOG_I(@"%s rating widget web view is being presented, widgetID: [%@], widgetType: [%@]", __FUNCTION__, widgetID, CLYFeedbackWidgetTypeRating);

    [CountlyCommon.sharedInstance tryPresentingViewController:webVC];
}

- (NSURLRequest *)widgetCheckURLRequest:(NSString *)widgetID
{
    NSString* queryString = [CountlyConnectionManager.sharedInstance queryEssentials];

    queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyFBKeyWidgetID, widgetID];
    
    queryString = [queryString stringByAppendingFormat:@"&%@=%@",
                   kCountlyAppVersionKey, CountlyDeviceInfo.appVersion];

    queryString = [CountlyConnectionManager.sharedInstance appendChecksum:queryString];

    NSString* serverOutputFeedbackWidgetEndpoint = [CountlyConnectionManager.sharedInstance.host stringByAppendingFormat:@"%@%@%@",
                                                    kCountlyEndpointO,
                                                    kCountlyEndpointFeedback,
                                                    kCountlyEndpointWidget];

    if (queryString.length > kCountlyGETRequestMaxLength || CountlyConnectionManager.sharedInstance.alwaysUsePOST)
    {
        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:serverOutputFeedbackWidgetEndpoint]];
        request.HTTPMethod = @"POST";
        request.HTTPBody = [queryString cly_dataUTF8];
        return request.copy;
    }
    else
    {
        NSString* withQueryString = [serverOutputFeedbackWidgetEndpoint stringByAppendingFormat:@"?%@", queryString];
        NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:withQueryString]];
        return request;
    }    
}

- (NSURL *)widgetDisplayURL:(NSString *)widgetID
{
    NSString* queryString = [CountlyConnectionManager.sharedInstance queryEssentials];

    queryString = [queryString stringByAppendingFormat:@"&%@=%@&%@=%@",
                   kCountlyFBKeyWidgetID, widgetID,
                   kCountlyFBKeyAppVersion, CountlyDeviceInfo.appVersion];
    
    queryString = [queryString stringByAppendingFormat:@"&%@=%@",
                   kCountlyAppVersionKey, CountlyDeviceInfo.appVersion];

    queryString = [CountlyConnectionManager.sharedInstance appendChecksum:queryString];

    NSString* URLString = [NSString stringWithFormat:@"%@%@?%@",
                           CountlyConnectionManager.sharedInstance.host,
                           kCountlyEndpointFeedback,
                           queryString];

    URLString = [CountlyDeviceInfo URLStringByAppendingThemeMode:URLString];

    return [NSURL URLWithString:URLString];
}

- (BOOL)isDeviceTargetedByWidget:(NSDictionary *)widgetInfo
{
    BOOL isTablet = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad;
    BOOL isPhone = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone;
    BOOL isTabletTargeted = [widgetInfo[kCountlyFBKeyTargetDevices][kCountlyFBKeyTablet] boolValue];
    BOOL isPhoneTargeted = [widgetInfo[kCountlyFBKeyTargetDevices][kCountlyFBKeyPhone] boolValue];

    return ((isTablet && isTabletTargeted) || (isPhone && isPhoneTargeted));
}

- (void)recordRatingWidgetWithID:(NSString *)widgetID rating:(NSInteger)rating email:(NSString *)email comment:(NSString *)comment userCanBeContacted:(BOOL)userCanBeContacted
{
    CLY_LOG_I(@"%s rating widget result recording requested, widgetID: [%@], emailProvided: [%@], commentProvided: [%@], userCanBeContacted: [%@]", __FUNCTION__, widgetID, (email.length > 0) ? @"YES" : @"NO", (comment.length > 0) ? @"YES" : @"NO", userCanBeContacted ? @"YES" : @"NO");

    if (!CountlyConsentManager.sharedInstance.consentForFeedback)
    {
        CLY_LOG_V(@"%s no feedback consent given, rating widget result is not recorded", __FUNCTION__);
        return;
    }

    if (!widgetID.length)
    {
        CLY_LOG_E(@"%s rating widget result is dropped, widget ID is empty or nil", __FUNCTION__);
        return;
    }

    NSMutableDictionary* segmentation = NSMutableDictionary.new;
    segmentation[kCountlyFBKeyPlatform] = CountlyDeviceInfo.osName;
    segmentation[kCountlyFBKeyAppVersion] = CountlyDeviceInfo.appVersion;
    segmentation[kCountlyFBKeyRating] = @(rating);
    segmentation[kCountlyFBKeyWidgetID] = widgetID;
    segmentation[kCountlyFBKeyEmail] = email;
    segmentation[kCountlyFBKeyComment] = comment;
    segmentation[kCountlyFBKeyContactMe] = @(userCanBeContacted);

    CLY_LOG_I(@"%s rating widget result submitted, widgetID: [%@], widgetType: [%@], answeredFieldCount: [%lu]", __FUNCTION__, widgetID, CLYFeedbackWidgetTypeRating, (unsigned long)segmentation.count);

    CLY_LOG_D(@"%s rating widget result submission detail, widgetID: [%@], rating: [%ld], email: [%@], comment: [%@], userCanBeContacted: [%@], segmentation: [%@]", __FUNCTION__, widgetID, (long)rating, email, comment, userCanBeContacted ? @"YES" : @"NO", segmentation);

    [Countly.sharedInstance recordReservedEvent:kCountlyReservedEventStarRating segmentation:segmentation];
}


#pragma mark - Feedbacks (Surveys, NPS)

- (void)getFeedbackWidgets:(void (^)(NSArray <CountlyFeedbackWidget *> *feedbackWidgets, NSError *error))completionHandler
{
    CLY_LOG_I(@"%s feedback widget list fetch requested, completionHandlerProvided: [%@]", __FUNCTION__, (completionHandler != nil) ? @"YES" : @"NO");

    if (!CountlyServerConfig.sharedInstance.networkingEnabled)
    {
        CLY_LOG_D(@"%s feedback widget list fetch is dropped, networking is disabled by server config", __FUNCTION__);
        if(completionHandler){
            completionHandler(nil, nil);
        }
        return;
    }
    
    if (!CountlyConsentManager.sharedInstance.consentForFeedback) {
        CLY_LOG_V(@"%s no feedback consent given, feedback widget list is not fetched", __FUNCTION__);
        if(completionHandler){
            completionHandler(nil, nil);
        }
        return;
    }
        

    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary) {
        CLY_LOG_W(@"%s feedback widget list fetch is dropped, device ID is temporary", __FUNCTION__);
        if(completionHandler){
            completionHandler(nil, nil);
        }
        return;
    }

    NSURLSessionTask* task = [CountlyCommon.sharedInstance.ImmediateURLSession dataTaskWithRequest:[self feedbacksRequest] completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
    {
        // IMMEDIATE REQUEST to find them better in search
        NSDictionary *feedbacksResponse = nil;

        CLY_LOG_V(@"%s feedback widget list raw response received, url: [%@], responseBody: [%@]", __FUNCTION__, response.URL.absoluteString, [data cly_stringUTF8]);

        if (!error)
        {
            feedbacksResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        }

        if (!error)
        {
            if (((NSHTTPURLResponse*)response).statusCode != 200)
            {
                NSMutableDictionary* userInfo = feedbacksResponse.mutableCopy;
                userInfo[NSLocalizedDescriptionKey] = @"Feedbacks general API error";
                error = [NSError errorWithDomain:kCountlyErrorDomain code:CLYErrorFeedbacksGeneralAPIError userInfo:userInfo];
            }
        }

        if (error || !feedbacksResponse || ![feedbacksResponse isKindOfClass:[NSDictionary class]])
        {
            CLY_LOG_W(@"%s feedback widget list fetch failed, responseIsDictionary: [%@], error: [%@]", __FUNCTION__, [feedbacksResponse isKindOfClass:[NSDictionary class]] ? @"YES" : @"NO", error.localizedDescription);
            dispatch_async(dispatch_get_main_queue(), ^
            {
                if (completionHandler)
                    completionHandler(nil, error);
            });

            return;
        }
        

        NSMutableArray* feedbacks = NSMutableArray.new;
        NSArray* rawFeedbackObjects = feedbacksResponse[@"result"];
        if(!rawFeedbackObjects){
            CLY_LOG_E(@"%s feedback widget list response has no result field, ignoring the response", __FUNCTION__);
            dispatch_async(dispatch_get_main_queue(), ^
            {
                if (completionHandler)
                    completionHandler(nil, error);
            });

            return;
        }
        for (NSDictionary * feedbackDict in rawFeedbackObjects)
        {
            CountlyFeedbackWidget *feedback = [CountlyFeedbackWidget createWithDictionary:feedbackDict];
            if (feedback)
                [feedbacks addObject:feedback];
        }

        CLY_LOG_I(@"%s feedback widget list fetched, widgetCount: [%lu]", __FUNCTION__, (unsigned long)feedbacks.count);

        CLY_LOG_D(@"%s feedback widget list parsed response detail, widgetCount: [%lu], parsedResponse: [%@]", __FUNCTION__, (unsigned long)feedbacks.count, feedbacksResponse);

        dispatch_async(dispatch_get_main_queue(), ^
        {
            if (completionHandler)
                completionHandler([NSArray arrayWithArray:feedbacks], nil);
        });
    }];

    [task resume];
}

- (NSURLRequest *)feedbacksRequest
{
    NSString* queryString = [NSString stringWithFormat:@"%@=%@&%@=%@&%@=%@&%@=%@&%@=%@",
        kCountlyQSKeyMethod, kCountlyFBKeyFeedback,
        kCountlyQSKeyAppKey, CountlyConnectionManager.sharedInstance.appKey.cly_URLEscaped,
        kCountlyQSKeyDeviceID, CountlyDeviceInfo.sharedInstance.deviceID.cly_URLEscaped,
        kCountlyQSKeySDKName, CountlyCommon.sharedInstance.SDKName,
        kCountlyQSKeySDKVersion, CountlyCommon.sharedInstance.SDKVersion];
    
    queryString = [queryString stringByAppendingFormat:@"&%@=%@",
                   kCountlyAppVersionKey, CountlyDeviceInfo.appVersion];

    queryString = [CountlyConnectionManager.sharedInstance appendChecksum:queryString];

    NSMutableString* URL = CountlyConnectionManager.sharedInstance.host.mutableCopy;
    [URL appendString:kCountlyEndpointO];
    [URL appendString:kCountlyEndpointSDK];

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

- (void) presentNPS:(NSString *)nameIDorTag widgetCallback:(WidgetCallback) widgetCallback {
    [self presentFeedbackWidget:CLYFeedbackWidgetTypeNPS nameIDorTag:nameIDorTag widgetCallback:widgetCallback];
}

- (void) presentSurvey:(NSString *)nameIDorTag widgetCallback:(WidgetCallback) widgetCallback {
    [self presentFeedbackWidget:CLYFeedbackWidgetTypeSurvey nameIDorTag:nameIDorTag widgetCallback:widgetCallback];
}

- (void) presentRating:(NSString *)nameIDorTag widgetCallback:(WidgetCallback) widgetCallback {
    [self presentFeedbackWidget:CLYFeedbackWidgetTypeRating nameIDorTag:nameIDorTag widgetCallback:widgetCallback];
}


-(void)presentFeedbackWidget:(CLYFeedbackWidgetType)widgetType nameIDorTag:(NSString *)nameIDorTag  widgetCallback:(WidgetCallback) widgetCallback {
    [self getFeedbackWidgets:^(NSArray *feedbackWidgets, NSError *error) {
        if (error) {
            CLY_LOG_D(@"%s widget list could not be retrieved while resolving a widget to present, widgetType: [%@], error: [%@]", __FUNCTION__, widgetType, error.localizedDescription);
            return;
        }
        
        CLY_LOG_D(@"%s widget list available for resolving, totalWidgetCount: [%lu]", __FUNCTION__, (unsigned long)feedbackWidgets.count);
        
        NSPredicate *typePredicate = [NSPredicate predicateWithFormat:@"type == %@", widgetType];
        NSArray *filteredWidgets = [feedbackWidgets filteredArrayUsingPredicate:typePredicate];
        
        CLY_LOG_D(@"%s widget list filtered by type, widgetType: [%@], matchingWidgetCount: [%lu]", __FUNCTION__, widgetType, (unsigned long)filteredWidgets.count);
        
        CountlyFeedbackWidget *widgetToPresent = nil;
        
        if (nameIDorTag && nameIDorTag.length > 0) {
            for (CountlyFeedbackWidget *feedbackWidget in filteredWidgets) {
                if ([nameIDorTag isEqualToString:feedbackWidget.name] ||
                    [nameIDorTag isEqualToString:feedbackWidget.ID] ||
                    [feedbackWidget.tags containsObject:nameIDorTag]) {
                    widgetToPresent = feedbackWidget;
                    CLY_LOG_D(@"%s exact widget match found, nameIDorTag: [%@], widgetID: [%@], widgetType: [%@]", __FUNCTION__, nameIDorTag, feedbackWidget.ID, widgetType);
                    break;
                }
            }
        }
        
        if (!widgetToPresent && filteredWidgets.count > 0) {
            widgetToPresent = filteredWidgets.firstObject;
            CLY_LOG_D(@"%s no exact widget match, falling back to the first widget of the type, nameIDorTag: [%@], widgetType: [%@], widgetID: [%@]", __FUNCTION__, nameIDorTag, widgetType, widgetToPresent.ID);
        }
        
        if (widgetToPresent) {
            [widgetToPresent presentWithCallback:widgetCallback];
        } else {
            CLY_LOG_W(@"%s no feedback widget found to present, widgetType: [%@], nameIDorTag: [%@]", __FUNCTION__, widgetType, nameIDorTag);
        }
    }];
}

#endif
@end
