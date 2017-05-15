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
@end

NSString* const kCountlyParentDeviceIDTransferKey = @"kCountlyParentDeviceIDTransferKey";
NSString* const kCountlySDKVersion = @"17.05";
NSString* const kCountlySDKName = @"objc-native-ios";

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
    return components.weekday-1;
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
        self.lastTimestamp ++;
    else
        self.lastTimestamp = now;

    return (double)(self.lastTimestamp / 1000.0);
}

#pragma mark - Watch Connectivity

#if (TARGET_OS_IOS || TARGET_OS_WATCH)
- (void)activateWatchConnectivity
{
    if (!self.enableAppleWatch)
        return;

    if ([WCSession isSupported])
    {
        WCSession *session = WCSession.defaultSession;
        session.delegate = (id<WCSessionDelegate>)self;
        [session activateSession];
    }
}
#endif

#if TARGET_OS_IOS
- (void)transferParentDeviceID
{
    if (!self.enableAppleWatch)
        return;

    [self activateWatchConnectivity];

    if (WCSession.defaultSession.paired && WCSession.defaultSession.watchAppInstalled)
    {
        [WCSession.defaultSession transferUserInfo:@{kCountlyParentDeviceIDTransferKey:CountlyDeviceInfo.sharedInstance.deviceID}];
        COUNTLY_LOG(@"Transferring parent device ID %@ ...", CountlyDeviceInfo.sharedInstance.deviceID);
    }
}
#endif

#if (TARGET_OS_WATCH)
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

@end


#pragma mark - Internal ViewController
#if TARGET_OS_IOS
@implementation CLYInternalViewController : UIViewController

//NOTE: For using the same status bar preferences as the view controller currently being  displayed, when a Countly triggered alert is displayed using a separate window
- (UIStatusBarStyle)preferredStatusBarStyle
{
    if (UIApplication.sharedApplication.windows.firstObject.rootViewController == self)
        return UIStatusBarStyleDefault;

    return [UIApplication.sharedApplication.windows.firstObject.rootViewController preferredStatusBarStyle];
}

- (BOOL)prefersStatusBarHidden
{
    if (UIApplication.sharedApplication.windows.firstObject.rootViewController == self)
        return NO;

    return [UIApplication.sharedApplication.windows.firstObject.rootViewController prefersStatusBarHidden];
}

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
    const float kCountlyDismissButtonSize = 30.0;
    const float kCountlyDismissButtonMargin = 10.0;
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
