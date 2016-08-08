// CountlyStarRating.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated"

@interface CountlyStarRating ()
@property (nonatomic, copy, nullable) void (^ratingCompletion)(NSInteger);
@end

NSString* const kCountlyReservedEventStarRating = @"[CLY]_star_rating";
NSString* const kCountlyStarRatingStatusSessionCountKey = @"kCountlyStarRatingStatusSessionCountKey";
NSString* const kCountlyStarRatingStatusHasEverAskedAutomatically = @"kCountlyStarRatingStatusHasEverAskedAutomatically";

@implementation CountlyStarRating
#if TARGET_OS_IOS
{
    UIButton* btn_star[5];
    UIAlertController* alertController;
    UIAlertView* alertView;
}

const float buttonSize = 40;

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
    
        NSDictionary* dictDismiss =
        @{
              @"en" : @"Dismiss",
              @"tr" : @"Kapat",
              @"jp" : @"閉じる",
              @"zh" : @"关闭",
              @"de" : @"Schließen",
              @"fr" : @"Fermer",
              @"es" : @"Cerrar",
              @"ru" : @"закрыть",
              @"lv" : @"Aizvērt",
              @"cs" : @"Zavřít"
        };
    
        self.dismissButtonTitle = dictDismiss[langDesignator];
        if(!self.dismissButtonTitle)
            self.dismissButtonTitle = dictDismiss[@"en"];
    
        NSDictionary* dictMessage =
        @{
            @"en" : @"How would you rate the app?",
            @"tr" : @"Uygulamayı nasıl değerlendirirsiniz?",
            @"jp" : @"あなたの評価を教えてください。",
            @"zh" : @"请告诉我你的评价。"
        };

        self.message = dictMessage[langDesignator];
        if(!self.message)
            self.message = dictMessage[@"en"];
    }

    return self;
}

- (void)showDialog:(void(^)(NSInteger rating))completion
{
    self.ratingCompletion = completion;

    if(UIAlertController.class)
    {
        alertController = [UIAlertController alertControllerWithTitle:@" " message:self.message preferredStyle:UIAlertControllerStyleAlert];

        UIAlertAction* dismiss = [UIAlertAction actionWithTitle:self.dismissButtonTitle style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action)
        {
            [self finishWithRating:0];
        }];
        
        [alertController addAction:dismiss];
        
        UIViewController* cvc = UIViewController.new;
        [cvc setPreferredContentSize:(CGSize){buttonSize * 5, buttonSize * 1.5}];
        [cvc.view addSubview:[self starView]];
        
        @try
        {
            [alertController setValue:cvc forKey:@"contentViewController"];
        }
        @catch(NSException* exception)
        {
            COUNTLY_LOG(@"UIAlertController's contentViewController can not be set: \n%@", exception);
        }
    
        //NOTE: if rootViewController is not set at early app launch, try again 1 sec after.
        UIViewController* rvc = UIApplication.sharedApplication.keyWindow.rootViewController;
        if(rvc)
        {
            [rvc presentViewController:alertController animated:YES completion:nil];
        }
        else
        {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^
            {
                [UIApplication.sharedApplication.keyWindow.rootViewController presentViewController:alertController animated:YES completion:nil];
            });
        }
    }
    else
    {
        alertView = [UIAlertView.alloc initWithTitle:@" " message:self.message delegate:self cancelButtonTitle:self.dismissButtonTitle otherButtonTitles:nil];
        
        UIView* vw_star = [self starView];
        CGRect f = vw_star.frame;
        f.size.height *= 1.5;
        UIView* aligner = UIView.new;
        aligner.frame = f;
        [aligner addSubview:vw_star];
    
        [alertView setValue:aligner forKey:@"accessoryView"];
        [alertView show];
    }
}

- (void)checkForAutoAsk
{
    NSMutableDictionary* status = [CountlyPersistency.sharedInstance retrieveStarRatingStatus].mutableCopy;

    if(self.disableAskingForEachAppVersion && status[kCountlyStarRatingStatusHasEverAskedAutomatically])
        return;
    
    if(self.sessionCount != 0)
    {
        NSString* keyForAppVersion = [kCountlyStarRatingStatusSessionCountKey stringByAppendingString:CountlyDeviceInfo.appVersion];
        NSInteger sessionCountSoFar = [status[keyForAppVersion] integerValue];
        sessionCountSoFar++;

        if(self.sessionCount == sessionCountSoFar)
        {
            COUNTLY_LOG(@"Asking for star-rating as session count reached specified limit %i ...", self.sessionCount);
        
            [self showDialog:^(NSInteger rating){}];
        
            status[kCountlyStarRatingStatusHasEverAskedAutomatically] = @YES;
        }
    
        status[keyForAppVersion] = @(sessionCountSoFar);
    
        [CountlyPersistency.sharedInstance storeStarRatingStatus:status];
    }
}

- (UIView *)starView
{
    UIView* vw_star = [UIView.alloc initWithFrame:(CGRect){0, 0, buttonSize * 5, buttonSize}];
    vw_star.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;

    for (int i = 0; i < 5; i++)
    {
        btn_star[i] = [UIButton.alloc initWithFrame:(CGRect){i * buttonSize, 0, buttonSize, buttonSize}];
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

- (void)setDismissButtonTitle:(NSString *)dismissButtonTitle
{
    if (dismissButtonTitle == nil)
        return;
    
    _dismissButtonTitle = dismissButtonTitle;
}

- (void)onClick_star:(id)sender
{
    UIColor* color = [self activeStarColor];
    NSInteger rating = 0;
    
    for (int i = 0; i < 5; i++)
    {
        [btn_star[i] setTitleColor:color forState:UIControlStateNormal];
    
        if(btn_star[i] == sender)
        {
            color = [self passiveStarColor];
            rating = i+1;
        }
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^
    {
        if(alertController)
            [alertController dismissViewControllerAnimated:YES completion:^{ [self finishWithRating:rating]; }];
        else if(alertView)
            [alertView dismissWithClickedButtonIndex:rating animated:YES];
    });
}

- (void)finishWithRating:(NSInteger)rating
{
    if(self.ratingCompletion)
        self.ratingCompletion(rating);

    if(rating==0)
        return;
    
    NSDictionary* segmentation =
    @{
        @"platform": CountlyDeviceInfo.osName,
        @"appVersion": CountlyDeviceInfo.appVersion,
        @"rating" : @(rating)
    };

    [Countly.sharedInstance recordEvent:kCountlyReservedEventStarRating segmentation:segmentation count:1 sum:0];
    
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

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex
{
    [self finishWithRating:buttonIndex];
}
#endif
@end
#pragma clang diagnostic pop