// CountlyStarRating.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"
#if TARGET_OS_IOS
#import <WebKit/WebKit.h>
#endif

@interface CountlyStarRating ()
#if TARGET_OS_IOS
@property (nonatomic) UIAlertController* alertController;
@property (nonatomic, copy) void (^ratingCompletion)(NSInteger);
#endif
@end

NSString* const kCountlyReservedEventStarRating = @"[CLY]_star_rating";
NSString* const kCountlyStarRatingStatusSessionCountKey = @"kCountlyStarRatingStatusSessionCountKey";
NSString* const kCountlyStarRatingStatusHasEverAskedAutomatically = @"kCountlyStarRatingStatusHasEverAskedAutomatically";

NSString* const kCountlySRKeyAppKey         = @"app_key";
NSString* const kCountlySRKeyPlatform       = @"platform";
NSString* const kCountlySRKeyAppVersion     = @"app_version";
NSString* const kCountlySRKeyRating         = @"rating";
NSString* const kCountlySRKeyWidgetID       = @"widget_id";
NSString* const kCountlySRKeyDeviceID       = @"device_id";
NSString* const kCountlySRKeySDKVersion     = @"sdk_version";
NSString* const kCountlySRKeySDKName        = @"sdk_name";
NSString* const kCountlySRKeyID             = @"_id";
NSString* const kCountlySRKeyTargetDevices  = @"target_devices";
NSString* const kCountlySRKeyPhone          = @"phone";
NSString* const kCountlySRKeyTablet         = @"tablet";

NSString* const kCountlyOutputEndpoint      = @"/o";
NSString* const kCountlyFeedbackEndpoint    = @"/feedback";
NSString* const kCountlyWidgetEndpoint      = @"/widget";

const CGFloat kCountlyStarRatingButtonSize = 40.0;

@implementation CountlyStarRating
#if TARGET_OS_IOS
{
    UIButton* btn_star[5];
}

+ (instancetype)sharedInstance
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return nil;

    static CountlyStarRating* s_sharedInstance = nil;
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
    if (!CountlyConsentManager.sharedInstance.consentForStarRating)
        return;

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

    CLYInternalViewController* cvc = CLYInternalViewController.new;
    [cvc setPreferredContentSize:(CGSize){kCountlyStarRatingButtonSize * 5, kCountlyStarRatingButtonSize * 1.5}];
    [cvc.view addSubview:[self starView]];

    @try
    {
        [self.alertController setValue:cvc forKey:@"contentViewController"];
    }
    @catch (NSException* exception)
    {
        COUNTLY_LOG(@"UIAlertController's contentViewController can not be set: \n%@", exception);
    }

    [CountlyCommon.sharedInstance tryPresentingViewController:self.alertController];
}

- (void)checkForAutoAsk
{
    if (!self.sessionCount)
        return;

    if (!CountlyConsentManager.sharedInstance.consentForStarRating)
        return;

    NSMutableDictionary* status = [CountlyPersistency.sharedInstance retrieveStarRatingStatus].mutableCopy;

    if (self.disableAskingForEachAppVersion && status[kCountlyStarRatingStatusHasEverAskedAutomatically])
        return;

    NSString* keyForAppVersion = [kCountlyStarRatingStatusSessionCountKey stringByAppendingString:CountlyDeviceInfo.appVersion];
    NSInteger sessionCountSoFar = [status[keyForAppVersion] integerValue];
    sessionCountSoFar++;

    if (self.sessionCount == sessionCountSoFar)
    {
        COUNTLY_LOG(@"Asking for star-rating as session count reached specified limit %d ...", (int)self.sessionCount);

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
    if (self.ratingCompletion)
        self.ratingCompletion(rating);

    if (rating != 0)
    {
        NSDictionary* segmentation =
        @{
            kCountlySRKeyPlatform: CountlyDeviceInfo.osName,
            kCountlySRKeyAppVersion: CountlyDeviceInfo.appVersion,
            kCountlySRKeyRating: @(rating)
        };

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

#pragma mark - Feedback Widget

- (void)checkFeedbackWidgetWithID:(NSString *)widgetID completionHandler:(void (^)(NSError * error))completionHandler
{
    if (!CountlyConsentManager.sharedInstance.consentForStarRating)
        return;

    if (!widgetID.length)
        return;

    NSURL* widgetCheckURL = [self widgetCheckURL:widgetID];
    NSURLRequest* feedbackWidgetCheckRequest = [NSURLRequest requestWithURL:widgetCheckURL];
    NSURLSessionTask* task = [NSURLSession.sharedSession dataTaskWithRequest:feedbackWidgetCheckRequest completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
    {
        NSDictionary* widgetInfo = nil;

        if (!error)
        {
            widgetInfo = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        }

        if (!error)
        {
            NSMutableDictionary* userInfo = widgetInfo.mutableCopy;

            if (![widgetInfo[kCountlySRKeyID] isEqualToString:widgetID])
            {
                userInfo[NSLocalizedDescriptionKey] = [NSString stringWithFormat:@"Feedback widget with ID %@ is not available.", widgetID];
                error = [NSError errorWithDomain:kCountlyErrorDomain code:CLYErrorFeedbackWidgetNotAvailable userInfo:userInfo];
            }
            else if (![self isDeviceTargetedByWidget:widgetInfo])
            {
                userInfo[NSLocalizedDescriptionKey] = [NSString stringWithFormat:@"Feedback widget with ID %@ does not include this device in target devices list.", widgetID];
                error = [NSError errorWithDomain:kCountlyErrorDomain code:CLYErrorFeedbackWidgetNotTargetedForDevice userInfo:userInfo];
            }
        }

        if (error)
        {
            dispatch_async(dispatch_get_main_queue(), ^
            {
                if (completionHandler)
                    completionHandler(error);
            });
            return;
        }

        dispatch_async(dispatch_get_main_queue(), ^
        {
            [self presentFeedbackWidgetWithID:widgetID completionHandler:completionHandler];
        });
    }];

    [task resume];
}

- (void)presentFeedbackWidgetWithID:(NSString *)widgetID completionHandler:(void (^)(NSError * error))completionHandler
{
    __block CLYInternalViewController* webVC = CLYInternalViewController.new;
    webVC.view.backgroundColor = UIColor.whiteColor;
    webVC.view.bounds = UIScreen.mainScreen.bounds;
    webVC.modalPresentationStyle = UIModalPresentationCustom;

    WKWebView* webView = [WKWebView.alloc initWithFrame:webVC.view.bounds];
    [webVC.view addSubview:webView];
    NSURL* widgetDisplayURL = [self widgetDisplayURL:widgetID];
    [webView loadRequest:[NSURLRequest requestWithURL:widgetDisplayURL]];

    CLYButton* dismissButton = [CLYButton dismissAlertButton];
    dismissButton.onClick = ^(id sender)
    {
        [webVC dismissViewControllerAnimated:YES completion:^
        {
            if (completionHandler)
                completionHandler(nil);

            webVC = nil;
        }];
    };
    [webVC.view addSubview:dismissButton];

    CGPoint center = dismissButton.center;
    center.y += 20; //NOTE: adjust dismiss button position for status bar
    if (webVC.view.bounds.size.height == 812 || webVC.view.bounds.size.height == 896)
        center.y += 24; //NOTE: adjust dismiss button position for iPhone X type of devices
    dismissButton.center = center;

    [CountlyCommon.sharedInstance tryPresentingViewController:webVC];
}

- (NSURL *)widgetCheckURL:(NSString *)widgetID
{
    NSString* queryString = [CountlyConnectionManager.sharedInstance queryEssentials];

    queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlySRKeyWidgetID, widgetID];

    queryString = [CountlyConnectionManager.sharedInstance appendChecksum:queryString];

    NSString* URLString = [NSString stringWithFormat:@"%@%@%@%@?%@",
                           CountlyConnectionManager.sharedInstance.host,
                           kCountlyOutputEndpoint, kCountlyFeedbackEndpoint, kCountlyWidgetEndpoint,
                           queryString];

    return [NSURL URLWithString:URLString];
}

- (NSURL *)widgetDisplayURL:(NSString *)widgetID
{
    NSString* queryString = [CountlyConnectionManager.sharedInstance queryEssentials];

    queryString = [queryString stringByAppendingFormat:@"&%@=%@&%@=%@",
                   kCountlySRKeyWidgetID, widgetID,
                   kCountlySRKeyAppVersion, CountlyDeviceInfo.appVersion];

    queryString = [CountlyConnectionManager.sharedInstance appendChecksum:queryString];

    NSString* URLString = [NSString stringWithFormat:@"%@%@?%@",
                           CountlyConnectionManager.sharedInstance.host,
                           kCountlyFeedbackEndpoint,
                           queryString];

    return [NSURL URLWithString:URLString];
}

- (BOOL)isDeviceTargetedByWidget:(NSDictionary *)widgetInfo
{
    BOOL isTablet = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad;
    BOOL isPhone = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone;
    BOOL isTabletTargeted = [widgetInfo[kCountlySRKeyTargetDevices][kCountlySRKeyTablet] boolValue];
    BOOL isPhoneTargeted = [widgetInfo[kCountlySRKeyTargetDevices][kCountlySRKeyPhone] boolValue];

    return ((isTablet && isTabletTargeted) || (isPhone && isPhoneTargeted));
}

#endif
@end
