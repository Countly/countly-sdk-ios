// CountlyCommon.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"
#include <CommonCrypto/CommonDigest.h>

@interface CountlyCommon ()
{
    NSCalendar* gregorianCalendar;
    NSTimeInterval startTime;
}
@property long long lastTimestamp;
#if (TARGET_OS_IOS || TARGET_OS_TV)
@property (nonatomic) UIBackgroundTaskIdentifier bgTask;
#endif
@end

NSString* const kCountlySDKVersion = @"19.02";
NSString* const kCountlySDKName = @"objc-native-ios";

NSString* const kCountlyParentDeviceIDTransferKey = @"kCountlyParentDeviceIDTransferKey";
NSString* const kCountlyAttributionIDFAKey = @"idfa";

NSString* const kCountlyErrorDomain = @"ly.count.ErrorDomain";

@implementation CountlyCommon

+ (instancetype)sharedInstance
{
    static CountlyCommon *s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    if (self = [super init])
    {
        gregorianCalendar = [NSCalendar.alloc initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        startTime = NSDate.date.timeIntervalSince1970;
    }

    return self;
}

void CountlyInternalLog(NSString *format, ...)
{
    if (!CountlyCommon.sharedInstance.enableDebug)
        return;

    va_list args;
    va_start(args, format);

    NSString* logFormat = [NSString stringWithFormat:@"[Countly] %@", format];
    NSString* logString = [NSString.alloc initWithFormat:logFormat arguments:args];
    NSLog(@"%@", logString);

    va_end(args);
}


#pragma mark - Time/Date related methods
- (NSInteger)hourOfDay
{
    NSDateComponents* components = [gregorianCalendar components:NSCalendarUnitHour fromDate:NSDate.date];
    return components.hour;
}

- (NSInteger)dayOfWeek
{
    NSDateComponents* components = [gregorianCalendar components:NSCalendarUnitWeekday fromDate:NSDate.date];
    return components.weekday - 1;
}

- (NSInteger)timeZone
{
    return NSTimeZone.systemTimeZone.secondsFromGMT / 60;
}

- (NSInteger)timeSinceLaunch
{
    return (int)NSDate.date.timeIntervalSince1970 - startTime;
}

- (NSTimeInterval)uniqueTimestamp
{
    long long now = floor(NSDate.date.timeIntervalSince1970 * 1000);

    if (now <= self.lastTimestamp)
        self.lastTimestamp++;
    else
        self.lastTimestamp = now;

    return (NSTimeInterval)(self.lastTimestamp / 1000.0);
}

#pragma mark - Watch Connectivity

- (void)startAppleWatchMatching
{
    if (!self.enableAppleWatch)
        return;

    if (!CountlyConsentManager.sharedInstance.consentForAppleWatch)
        return;

#if (TARGET_OS_IOS || TARGET_OS_WATCH)
    if (@available(iOS 9.0, *))
    {
        if ([WCSession isSupported])
        {
            WCSession.defaultSession.delegate = (id<WCSessionDelegate>)self;
            [WCSession.defaultSession activateSession];
        }
    }
#endif

#if TARGET_OS_IOS
    if (@available(iOS 9.0, *))
    {
        if (WCSession.defaultSession.paired && WCSession.defaultSession.watchAppInstalled)
        {
            [WCSession.defaultSession transferUserInfo:@{kCountlyParentDeviceIDTransferKey: CountlyDeviceInfo.sharedInstance.deviceID}];
            COUNTLY_LOG(@"Transferring parent device ID %@ ...", CountlyDeviceInfo.sharedInstance.deviceID);
        }
    }
#endif
}

#if TARGET_OS_WATCH
- (void)session:(WCSession *)session didReceiveUserInfo:(NSDictionary<NSString *, id> *)userInfo
{
    COUNTLY_LOG(@"Watch received user info: \n%@", userInfo);

    NSString* parentDeviceID = userInfo[kCountlyParentDeviceIDTransferKey];

    if (parentDeviceID && ![parentDeviceID isEqualToString:[CountlyPersistency.sharedInstance retrieveWatchParentDeviceID]])
    {
        [CountlyConnectionManager.sharedInstance sendParentDeviceID:parentDeviceID];

        COUNTLY_LOG(@"Parent device ID %@ added to queue.", parentDeviceID);

        [CountlyPersistency.sharedInstance storeWatchParentDeviceID:parentDeviceID];
    }
}
#endif

#pragma mark - Attribution

- (void)startAttribution
{
    if (!self.enableAttribution)
        return;

    if (!CountlyConsentManager.sharedInstance.consentForAttribution)
        return;

    NSDictionary* attribution = nil;

#if (TARGET_OS_IOS || TARGET_OS_TV)
#ifndef COUNTLY_EXCLUDE_IDFA
    if (ASIdentifierManager.sharedManager.advertisingTrackingEnabled)
    {
        attribution = @{kCountlyAttributionIDFAKey: ASIdentifierManager.sharedManager.advertisingIdentifier.UUIDString};
    }
#endif
#endif

    if (!attribution)
        return;

    [CountlyConnectionManager.sharedInstance sendAttribution:[attribution cly_JSONify]];
}

#pragma mark - Others

- (void)startBackgroundTask
{
#if (TARGET_OS_IOS || TARGET_OS_TV)
    if (self.bgTask != UIBackgroundTaskInvalid)
        return;

    self.bgTask = [UIApplication.sharedApplication beginBackgroundTaskWithExpirationHandler:^
    {
        [UIApplication.sharedApplication endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }];
#endif
}

- (void)finishBackgroundTask
{
#if (TARGET_OS_IOS || TARGET_OS_TV)
    if (self.bgTask != UIBackgroundTaskInvalid && !CountlyConnectionManager.sharedInstance.connection)
    {
        [UIApplication.sharedApplication endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }
#endif
}

#if (TARGET_OS_IOS || TARGET_OS_TV)
- (UIViewController *)topViewController
{
    UIViewController* topVC = UIApplication.sharedApplication.keyWindow.rootViewController;

    while (YES)
    {
        if (topVC.presentedViewController)
            topVC = topVC.presentedViewController;
         else if ([topVC isKindOfClass:UINavigationController.class])
             topVC = ((UINavigationController *)topVC).topViewController;
         else if ([topVC isKindOfClass:UITabBarController.class])
             topVC = ((UITabBarController *)topVC).selectedViewController;
         else
             break;
    }

    return topVC;
}

- (void)tryPresentingViewController:(UIViewController *)viewController
{
    UIViewController* topVC = self.topViewController;

    if (topVC)
    {
        [topVC presentViewController:viewController animated:YES completion:nil];
        return;
    }

    [self performSelector:@selector(tryPresentingViewController:) withObject:viewController afterDelay:1.0];
}
#endif

@end


#pragma mark - Internal ViewController
#if TARGET_OS_IOS
@implementation CLYInternalViewController : UIViewController

@end


@implementation CLYButton : UIButton

- (instancetype)initWithFrame:(CGRect)frame
{
    if (self = [super initWithFrame:frame])
    {
        [self addTarget:self action:@selector(touchUpInside:) forControlEvents:UIControlEventTouchUpInside];
    }

    return self;
}

- (void)touchUpInside:(id)sender
{
    if (self.onClick)
        self.onClick(self);
}

+ (CLYButton *)dismissAlertButton
{
    const CGFloat kCountlyDismissButtonSize = 30.0;
    const CGFloat kCountlyDismissButtonMargin = 10.0;
    CLYButton* dismissButton = [CLYButton buttonWithType:UIButtonTypeCustom];
    dismissButton.frame = (CGRect){UIScreen.mainScreen.bounds.size.width - kCountlyDismissButtonSize - kCountlyDismissButtonMargin, kCountlyDismissButtonMargin, kCountlyDismissButtonSize, kCountlyDismissButtonSize};
    [dismissButton setTitle:@"✕" forState:UIControlStateNormal];
    [dismissButton setTitleColor:UIColor.grayColor forState:UIControlStateNormal];
    dismissButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;

    return dismissButton;
}

@end
#endif

#pragma mark - Categories
NSString* CountlyJSONFromObject(id object)
{
    if (!object)
        return nil;

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    if (error){ COUNTLY_LOG(@"JSON can not be created: \n%@", error); }

    return [data cly_stringUTF8];
}

@implementation NSString (Countly)
- (NSString *)cly_URLEscaped
{
    NSCharacterSet* charset = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"];
    return [self stringByAddingPercentEncodingWithAllowedCharacters:charset];
}

- (NSString *)cly_SHA256
{
    const char* s = [self UTF8String];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(s, (CC_LONG)strlen(s), digest);

    NSMutableString* hash = NSMutableString.new;
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++)
        [hash appendFormat:@"%02x", digest[i]];

    return hash;
}

- (NSData *)cly_dataUTF8
{
    return [self dataUsingEncoding:NSUTF8StringEncoding];
}
@end

@implementation NSArray (Countly)
- (NSString *)cly_JSONify
{
    return [CountlyJSONFromObject(self) cly_URLEscaped];
}
@end

@implementation NSDictionary (Countly)
- (NSString *)cly_JSONify
{
    return [CountlyJSONFromObject(self) cly_URLEscaped];
}
@end

@implementation NSData (Countly)
- (NSString *)cly_stringUTF8
{
    return [NSString.alloc initWithData:self encoding:NSUTF8StringEncoding];
}
@end
