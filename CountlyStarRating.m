// CountlyStarRating.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface CountlyStarRating ()
#if TARGET_OS_IOS
@property (nonatomic, strong) UIWindow* alertWindow;
@property (nonatomic, copy) void (^ratingCompletion)(NSInteger);
#endif
@end

NSString* const kCountlyReservedEventStarRating = @"[CLY]_star_rating";
NSString* const kCountlyStarRatingStatusSessionCountKey = @"kCountlyStarRatingStatusSessionCountKey";
NSString* const kCountlyStarRatingStatusHasEverAskedAutomatically = @"kCountlyStarRatingStatusHasEverAskedAutomatically";

@implementation CountlyStarRating
#if TARGET_OS_IOS
{
    UIButton* btn_star[5];
    UIAlertController* alertController;
}

const float kCountlyStarRatingButtonSize = 40;

+ (instancetype)sharedInstance
{
    static CountlyStarRating* s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        NSString* langDesignator = [NSLocale.preferredLanguages.firstObject substringToIndex:2];

        NSDictionary* dictMessage =
        @{
            @"en" : @"How would you rate the app?",
            @"tr" : @"Uygulamayı nasıl değerlendirirsiniz?",
            @"jp" : @"あなたの評価を教えてください。",
            @"zh" : @"请告诉我你的评价。",
            @"ru" : @"Как бы вы оценили приложение?",
            @"cz" : @"Jak hodnotíte aplikaci?",
            @"lv" : @"Kā Jūs novērtētu šo lietotni?"            
        };

        self.message = dictMessage[langDesignator];
        if (!self.message)
            self.message = dictMessage[@"en"];
    }

    return self;
}

- (void)showDialog:(void(^)(NSInteger rating))completion
{
    self.ratingCompletion = completion;

    alertController = [UIAlertController alertControllerWithTitle:@" " message:self.message preferredStyle:UIAlertControllerStyleAlert];

    CLYButton* dismissButton = [CLYButton dismissAlertButton];
    dismissButton.onClick = ^(id sender)
    {
        [alertController dismissViewControllerAnimated:YES completion:^
        {
            [self finishWithRating:0];
        }];
    };
    [alertController.view addSubview:dismissButton];

    CLYInternalViewController* cvc = CLYInternalViewController.new;
    [cvc setPreferredContentSize:(CGSize){kCountlyStarRatingButtonSize * 5, kCountlyStarRatingButtonSize * 1.5}];
    [cvc.view addSubview:[self starView]];

    @try
    {
        [alertController setValue:cvc forKey:@"contentViewController"];
    }
    @catch(NSException* exception)
    {
        COUNTLY_LOG(@"UIAlertController's contentViewController can not be set: \n%@", exception);
    }

    self.alertWindow = [UIWindow.alloc initWithFrame:UIScreen.mainScreen.bounds];
    self.alertWindow.rootViewController = CLYInternalViewController.new;
    self.alertWindow.windowLevel = UIWindowLevelAlert;
    [self.alertWindow makeKeyAndVisible];
    [self.alertWindow.rootViewController presentViewController:alertController animated:YES completion:nil];
}

- (void)checkForAutoAsk
{
    NSMutableDictionary* status = [CountlyPersistency.sharedInstance retrieveStarRatingStatus].mutableCopy;

    if (self.disableAskingForEachAppVersion && status[kCountlyStarRatingStatusHasEverAskedAutomatically])
        return;

    if (self.sessionCount != 0)
    {
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
    if (message == nil)
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
            rating = i+1;
        }
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^
    {
        [alertController dismissViewControllerAnimated:YES completion:^{ [self finishWithRating:rating]; }];
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
            @"platform": CountlyDeviceInfo.osName,
            @"app_version": CountlyDeviceInfo.appVersion,
            @"rating" : @(rating)
        };

        [Countly.sharedInstance recordEvent:kCountlyReservedEventStarRating segmentation:segmentation count:1];
    }

    self.alertWindow.hidden = YES;
    self.alertWindow = nil;

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

#endif
@end
