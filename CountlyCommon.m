// CountlyCommon.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"
#include <CommonCrypto/CommonDigest.h>

NSString* const kCountlyReservedEventOrientation = @"[CLY]_orientation";
NSString* const kCountlyOrientationKeyMode = @"mode";

NSString* const kCountlyVisibility = @"cly_v";


@interface CountlyCommon ()
{
    NSCalendar* gregorianCalendar;
    NSTimeInterval startTime;
}
@property long long lastTimestamp;

#if (TARGET_OS_IOS || TARGET_OS_VISION )
@property (nonatomic) NSString* lastInterfaceOrientation;
#endif

#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_TV )
@property (nonatomic) UIBackgroundTaskIdentifier bgTask;
#endif
@end

NSString* const kCountlySDKVersion = @"26.1.4";
NSString* const kCountlySDKName = @"objc-native-ios";

NSString* const kCountlyErrorDomain = @"ly.count.ErrorDomain";

NSString* const kCountlyInternalLogPrefix = @"[Countly] ";


@implementation CountlyCommon

@synthesize lastTimestamp;

static CountlyCommon *s_sharedInstance = nil;
static dispatch_once_t onceToken;
+ (instancetype)sharedInstance
{
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    if (self = [super init])
    {
        gregorianCalendar = [NSCalendar.alloc initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        startTime = NSDate.date.timeIntervalSince1970;
        
        self.lastTimestamp = 0;
        self.SDKVersion = kCountlySDKVersion;
        self.SDKName = kCountlySDKName;
    }

    return self;
}

- (void)resetInstance {
    CLY_LOG_I(@"%s resetting shared state, sdkVersion: [%@], sdkName: [%@]", __FUNCTION__, kCountlySDKVersion, kCountlySDKName);
#if (TARGET_OS_IOS)
    [NSNotificationCenter.defaultCenter removeObserver:self name:UIDeviceOrientationDidChangeNotification object:nil];
#endif
    _hasStarted = false;
    _hasFinishedInit       = false;
    // `startWithConfig:` only ever sets this flag to YES, so without clearing it here it
    // would survive a `halt:` and leak visibility segmentation into the next start.
    _enableVisibiltyTracking = NO;
    _maxKeyLength = kCountlyMaxKeyLength;
    _maxValueLength = kCountlyMaxValueSize;
    _maxValueLengthPicture = kCountlyMaxValueSizePicture;
    _maxSegmentationValues = kCountlyMaxSegmentationValues;
    onceToken = 0;
    s_sharedInstance = nil;
 }


- (BOOL)hasStarted
{
    if (!_hasStarted)
        CountlyPrint(@"SDK should be started first!");

    return _hasStarted;
}

//NOTE: This is an equivalent of hasStarted, but without internal logging.
- (BOOL)hasStarted_
{
    return _hasStarted;
}

BOOL CountlyInternalLogIsEnabled(CLYInternalLogLevel level)
{
    if (!CountlyCommon.sharedInstance.enableDebug && !CountlyCommon.sharedInstance.loggerDelegate)
        return NO;

    return level <= CountlyCommon.sharedInstance.internalLogLevel;
}

void CountlyInternalLog(CLYInternalLogLevel level, NSString *format, ...)
{
    if (level == CLYInternalLogLevelError) {
        [CountlyHealthTracker.sharedInstance logError];
    } else if(level == CLYInternalLogLevelWarning) {
        [CountlyHealthTracker.sharedInstance logWarning];
    }
    
    if (!CountlyCommon.sharedInstance.enableDebug && !CountlyCommon.sharedInstance.loggerDelegate)
        return;

    if (level > CountlyCommon.sharedInstance.internalLogLevel)
        return;

    va_list args;
    va_start(args, format);

    NSString* logString = [NSString.alloc initWithFormat:format arguments:args];

    NSArray<NSString *> *logLevelPrefixes =
    @[
        @"None",
        @"Error",
        @"Warning",
        @"Info",
        @"Debug",
        @"Verbose",
    ];

    logString = [NSString stringWithFormat:@"[%@] %@", logLevelPrefixes[level], logString];

#if DEBUG
    if (CountlyCommon.sharedInstance.enableDebug)
        CountlyPrint(logString);
#endif

    if ([CountlyCommon.sharedInstance.loggerDelegate respondsToSelector:@selector(internalLog:withLevel:)])
    {
        NSString* logStringWithPrefix = [NSString stringWithFormat:@"%@%@", kCountlyInternalLogPrefix, logString];
        [CountlyCommon.sharedInstance.loggerDelegate internalLog:logStringWithPrefix withLevel:level];
    }

    va_end(args);
}

void CountlyPrint(NSString *stringToPrint)
{
    NSLog(@"%@%@", kCountlyInternalLogPrefix, stringToPrint);
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

- (NSString *)randomEventID
{
    const int size = 6;
    void *randomBuffer = malloc(size);
    arc4random_buf(randomBuffer, size);
    NSData* randomData = [NSData dataWithBytesNoCopy:randomBuffer length:size freeWhenDone:YES];
    NSString* randomBase64 = [randomData base64EncodedStringWithOptions:0];
    NSTimeInterval timestamp = self.uniqueTimestamp;
    NSString* randomEventID = [NSString stringWithFormat:@"%@%lld", randomBase64, (long long)(timestamp * 1000)];
    return randomEventID;
}

#pragma mark - Orientation

- (void)observeDeviceOrientationChanges
{
#if (TARGET_OS_IOS)
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(deviceOrientationDidChange:) name:UIDeviceOrientationDidChangeNotification object:nil];
#endif
}

- (void)deviceOrientationDidChange:(NSNotification *)notification
{
    if (!self.enableOrientationTracking)
        return;

    //NOTE: Delay is needed for interface orientation change animation to complete. Otherwise old interface orientation value is returned.
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(recordOrientation) object:nil];
    [self performSelector:@selector(recordOrientation) withObject:nil afterDelay:0.5];
}

- (void)recordOrientation
{
#if (TARGET_OS_IOS)
    if (!self.enableOrientationTracking)
        return;
    
    if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) {
        CLY_LOG_D(@"%s app is in the background, orientation recording will be ignored", __FUNCTION__);
        return;
    }
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
    UIInterfaceOrientation interfaceOrientation = UIApplication.sharedApplication.statusBarOrientation;
#pragma GCC diagnostic pop

    NSString* mode = nil;
    if (UIInterfaceOrientationIsPortrait(interfaceOrientation))
        mode = @"portrait";
    else if (UIInterfaceOrientationIsLandscape(interfaceOrientation))
        mode = @"landscape";

    if (!mode)
    {
        CLY_LOG_D(@"%s interface orientation is neither landscape nor portrait, orientation event will be skipped", __FUNCTION__);
        return;
    }

    if ([mode isEqualToString:self.lastInterfaceOrientation])
    {
        CLY_LOG_V(@"%s interface orientation did not change, orientation event will be skipped, mode: [%@]", __FUNCTION__, self.lastInterfaceOrientation);
        return;
    }

    CLY_LOG_D(@"%s interface orientation changed, previousMode: [%@], mode: [%@]", __FUNCTION__, self.lastInterfaceOrientation, mode);

    if (!CountlyConsentManager.sharedInstance.consentForUserDetails)
        return;
    
    self.lastInterfaceOrientation = mode;

    [Countly.sharedInstance recordReservedEvent:kCountlyReservedEventOrientation segmentation:@{kCountlyOrientationKeyMode: mode}];
#endif
}

#pragma mark - Others

- (void)startBackgroundTask
{
#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_TV)
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
#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_TV)
    if (self.bgTask != UIBackgroundTaskInvalid && !CountlyConnectionManager.sharedInstance.connection)
    {
        [UIApplication.sharedApplication endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }
#endif
}

#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_TV)
+ (UIWindow *)keyWindow
{
    if (@available(iOS 13.0, *))
    {
        // connectedScenes is an unordered NSSet, so never rely on iteration order: search
        // explicitly for the correct window rather than acting on whichever scene comes first.
        NSArray<UIScene *> *scenes = UIApplication.sharedApplication.connectedScenes.allObjects;

        // 1) The key window of the foreground-active scene (the one the user is interacting with).
        for (UIScene *scene in scenes)
        {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]])
            {
                for (UIWindow *window in ((UIWindowScene *)scene).windows)
                    if (window.isKeyWindow)
                        return window;
            }
        }

        // 2) Any key window across all scenes.
        for (UIScene *scene in scenes)
        {
            if ([scene isKindOfClass:[UIWindowScene class]])
            {
                for (UIWindow *window in ((UIWindowScene *)scene).windows)
                    if (window.isKeyWindow)
                        return window;
            }
        }

        // 3) Fall back to the first window of a foreground-active scene.
        for (UIScene *scene in scenes)
        {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]])
            {
                UIWindow *window = ((UIWindowScene *)scene).windows.firstObject;
                if (window)
                    return window;
            }
        }
    }
#if (TARGET_OS_VISION)
    return nil;
#else
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
    return UIApplication.sharedApplication.keyWindow;
#pragma GCC diagnostic pop
#endif
}

+ (CGRect)screenBounds
{
    UIWindow *window = [self keyWindow];
    if (window)
        return window.bounds;
#if (TARGET_OS_VISION)
    return CGRectZero;
#else
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
    return UIScreen.mainScreen.bounds;
#pragma GCC diagnostic pop
#endif
}

- (UIViewController *)topViewController
{
    UIViewController* topVC = CountlyCommon.keyWindow.rootViewController;

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
    [self tryPresentingViewController:viewController withCompletion:nil];
}

- (void)tryPresentingViewController:(UIViewController *)viewController withCompletion:(void (^ __nullable) (void))completion
{
    UIViewController* topVC = self.topViewController;

    if (topVC)
    {
        [topVC presentViewController:viewController animated:YES completion:^
        {
            if (completion)
                completion();
        }];

        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^
    {
        [self tryPresentingViewController:viewController];
    });
}
#endif

- (NSURLSession *)URLSession
{
    if (CountlyConnectionManager.sharedInstance.URLSessionConfiguration)
    {
        return [NSURLSession sessionWithConfiguration:CountlyConnectionManager.sharedInstance.URLSessionConfiguration];
    }
    else
    {
        return NSURLSession.sharedSession;
    }
}

- (NSURLSession *)ImmediateURLSession
{
    // Base on the user-provided URLSessionConfiguration so that things like
    // protocolClasses (test mocks), cookie policy, etc. are preserved.
    // If none was provided, fall back to default session configuration.
    NSURLSessionConfiguration *userConfig = CountlyConnectionManager.sharedInstance.URLSessionConfiguration;
    NSURLSessionConfiguration *immediateConfig = userConfig ? [userConfig copy] : [NSURLSessionConfiguration defaultSessionConfiguration];

    // Immediate requests must not be constrained by the SDK's configured
    // request timeout — reset to the system defaults.
    immediateConfig.timeoutIntervalForRequest = 60;
    immediateConfig.timeoutIntervalForResource = 7 * 24 * 60 * 60;

    return [NSURLSession sessionWithConfiguration:immediateConfig];
}

#if (TARGET_OS_IOS || TARGET_OS_VISION)
- (bool) hasTopNotch:(UIEdgeInsets)safeArea
{
    return safeArea.top >= 44;
}
#endif

- (CGSize)getWindowSize{
#if (TARGET_OS_IOS || TARGET_OS_VISION)
    UIWindow *window = [CountlyCommon keyWindow];

    if (!window) return CGSizeZero;

    CGSize size = window.bounds.size;

    if (@available(iOS 11.0, *)) {
        UIEdgeInsets safeArea = window.safeAreaInsets;
        if([self hasTopNotch:safeArea] || CountlyContentBuilderInternal.sharedInstance.webViewDisplayOption == SAFE_AREA){
            size.height -= (safeArea.top); // always respect notch
        }
        if(CountlyContentBuilderInternal.sharedInstance.webViewDisplayOption == SAFE_AREA){
            size.height -= safeArea.bottom;
        }
        size.width -= MAX(safeArea.left, safeArea.right); // regardles of given safe area, act for cutout
    }

    return size;
#else
    return CGSizeZero;
#endif
}

#if (TARGET_OS_IOS || TARGET_OS_VISION)
- (UIInterfaceOrientation)interfaceOrientation
{
    if (@available(iOS 13.0, *))
    {
        UIWindowScene *windowScene = [CountlyCommon keyWindow].windowScene;
        if (windowScene)
            return windowScene.interfaceOrientation;
    }
#if (TARGET_OS_IOS)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
    return UIApplication.sharedApplication.statusBarOrientation;
#pragma GCC diagnostic pop
#else
    return UIInterfaceOrientationPortrait;
#endif
}
#endif


@end


#pragma mark - Internal ViewController
#if (TARGET_OS_IOS || TARGET_OS_VISION)
@implementation CLYInternalViewController : UIViewController

- (void)viewWillLayoutSubviews
{
    [super viewWillLayoutSubviews];

    if (self.webView)
    {
        CGRect frame = CGRectInset(self.view.bounds, 20.0, 20.0);

        UIEdgeInsets insets = UIEdgeInsetsZero;
        if (@available(iOS 11.0, *))
        {
            insets = CountlyCommon.keyWindow.safeAreaInsets;
        }

        self.webView.navigationDelegate = self;
        frame = UIEdgeInsetsInsetRect(frame, insets);
        self.webView.frame = frame;
    }
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *contentURL = navigationAction.request.URL;
    if ([contentURL.absoluteString containsString:@"cly_x_int=1"]) {
        CLY_LOG_I(@"%s content url is marked for the external browser and will be handed over, host: [%@], path: [%@]", __FUNCTION__, contentURL.host, contentURL.path);
        CLY_LOG_D(@"%s external browser handover content url detail, contentURL: [%@]", __FUNCTION__, contentURL.absoluteString);
        [[UIApplication sharedApplication] openURL:contentURL options:@{} completionHandler:^(BOOL success) {
            if (success) {
                CLY_LOG_I(@"[CLYInternalViewController] openURL completion, external browser accepted the content url, host: [%@], path: [%@]", contentURL.host, contentURL.path);
                CLY_LOG_D(@"[CLYInternalViewController] openURL completion detail, the content url accepted by the external browser, contentURL: [%@]", contentURL.absoluteString);
            }
            else {
                CLY_LOG_W(@"[CLYInternalViewController] openURL completion, external browser could not open the content url, host: [%@], path: [%@]", contentURL.host, contentURL.path);
                CLY_LOG_D(@"[CLYInternalViewController] openURL completion detail, the content url rejected by the external browser, contentURL: [%@]", contentURL.absoluteString);
            }
        }];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(null_unspecified WKNavigation *)navigation
{
    CLY_LOG_D(@"%s internal web view started loading", __FUNCTION__);

}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    CLY_LOG_D(@"%s internal web view finished loading", __FUNCTION__);
}


@end


@implementation CLYButton : UIButton

const CGFloat kCountlyDismissButtonSize = 30.0;
const CGFloat kCountlyDismissButtonMargin = 10.0;
const CGFloat kCountlyDismissButtonStandardStatusBarHeight = 20.0;

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

+ (CLYButton *)dismissAlertButton:(NSString * _Nullable)closeButtonText
{
    if (!closeButtonText) {
        closeButtonText = @"x";
    }
    CLYButton* dismissButton = [CLYButton buttonWithType:UIButtonTypeCustom];
    dismissButton.frame = (CGRect){CGPointZero, kCountlyDismissButtonSize, kCountlyDismissButtonSize};
    [dismissButton setTitle:closeButtonText forState:UIControlStateNormal];
    [dismissButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    dismissButton.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.5];
    dismissButton.layer.cornerRadius = dismissButton.bounds.size.width * 0.5;
    dismissButton.layer.borderColor = [UIColor.blackColor colorWithAlphaComponent:0.7].CGColor;
    dismissButton.layer.borderWidth = 1.0;
    dismissButton.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
    
    return dismissButton;
}

+ (CLYButton *)dismissAlertButton
{
    return [CLYButton dismissAlertButton:nil];
}

- (void)positionToTopRight
{
    [self positionToTopRight:NO];
}

- (void)positionToTopRightConsideringStatusBar
{
    [self positionToTopRight:YES];
}

- (void)positionToTopRight:(BOOL)shouldConsiderStatusBar
{
    CGRect rect = self.frame;
    rect.origin.x = self.superview.bounds.size.width - self.bounds.size.width - kCountlyDismissButtonMargin;
    rect.origin.y = kCountlyDismissButtonMargin;

    if (shouldConsiderStatusBar)
    {
        if (@available(iOS 11.0, *))
        {
            CGFloat top = CountlyCommon.keyWindow.safeAreaInsets.top;

            if (top)
            {
                rect.origin.y += top;
            }
            else
            {
                rect.origin.y += kCountlyDismissButtonStandardStatusBarHeight;
            }
        }
        else
        {
            rect.origin.y += kCountlyDismissButtonStandardStatusBarHeight;
        }
    }

    self.frame = rect;
}

@end
#endif


#pragma mark - Proxy Object
@implementation CLYDelegateInterceptor

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel
{
    return [self.originalDelegate methodSignatureForSelector:sel];
}

- (void)forwardInvocation:(NSInvocation *)invocation
{
    if ([self.originalDelegate respondsToSelector:invocation.selector])
        [invocation invokeWithTarget:self.originalDelegate];
    else
        [super forwardInvocation:invocation];
}
@end



#pragma mark - Categories
NSString* CountlyJSONFromObject(id object)
{
    if (!object)
        return nil;

    if (![NSJSONSerialization isValidJSONObject:object])
    {
        CLY_LOG_E(@"%s object can not be represented as JSON and will be dropped, objectType: [%@]", __FUNCTION__, [object class]);
        return nil;
    }

    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    if (error)
    {
        CLY_LOG_E(@"%s JSON serialization failed and the data will be lost, objectType: [%@], error: [%@]", __FUNCTION__, [object class], error.localizedDescription);
    }

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

- (NSString *)cly_valueForQueryStringKey:(NSString *)key
{
    NSString* tempURLString = [@"http://example.com/path?" stringByAppendingString:self];
    NSURLComponents* URLComponents = [NSURLComponents componentsWithString:tempURLString];
    for (NSURLQueryItem* queryItem in URLComponents.queryItems)
    {
        if ([queryItem.name isEqualToString:key])
        {
            return queryItem.value;
        }
    }

    return nil;
}

- (NSString *)cly_truncatedKey:(NSString *)explanation
{
    if (self.length > CountlyCommon.sharedInstance.maxKeyLength)
    {
        CLY_LOG_D(@"%s key exceeds the SDK key length limit and will be truncated, target: [%@], key: [%@], keyLength: [%lu], truncatedTo: [%lu]", __FUNCTION__, explanation, self, (unsigned long)self.length, (unsigned long)CountlyCommon.sharedInstance.maxKeyLength);
        return [self substringToIndex:CountlyCommon.sharedInstance.maxKeyLength];
    }

    return self;
}

- (NSString *)cly_truncatedPictureValue:(NSString *)explanation
{
    NSUInteger limit = CountlyCommon.sharedInstance.maxValueLengthPicture;
    if (self.length > limit)
    {
        CLY_LOG_D(@"%s value exceeds the SDK picture value limit and will be truncated, target: [%@], valueLength: [%lu], truncatedTo: [%lu]", __FUNCTION__, explanation, (unsigned long)self.length, (unsigned long)limit);
        CLY_LOG_D(@"%s truncated picture value detail, target: [%@], fullValue: [%@]", __FUNCTION__, explanation, self);
        return [self substringToIndex:limit];
    }
    return self;
}

- (NSString *)cly_truncatedValue:(NSString *)explanation
{
    if (self.length > CountlyCommon.sharedInstance.maxValueLength)
    {
        CLY_LOG_D(@"%s value exceeds the SDK value length limit and will be truncated, target: [%@], valueLength: [%lu], truncatedTo: [%lu]", __FUNCTION__, explanation, (unsigned long)self.length, (unsigned long)CountlyCommon.sharedInstance.maxValueLength);
        CLY_LOG_D(@"%s truncated value detail, target: [%@], fullValue: [%@]", __FUNCTION__, explanation, self);
        return [self substringToIndex:CountlyCommon.sharedInstance.maxValueLength];
    }

    return self;
}

@end

@implementation NSArray (Countly)
- (NSString *)cly_JSONify
{
    return [CountlyJSONFromObject(self) cly_URLEscaped];
}

- (NSArray *) cly_filterSupportedDataTypes {
    NSMutableArray *filteredArray = [NSMutableArray array];
    for (id obj in self) {
        if ([obj isKindOfClass:[NSNumber class]] || [obj isKindOfClass:[NSString class]]) {
            [filteredArray addObject:obj];
        } else {
            CLY_LOG_D(@"%s dropping array element with an unsupported type, only NSNumber and NSString are allowed, receivedType: [%@]", __FUNCTION__, [obj class]);
        }
    }
    return filteredArray.copy;
}
@end

@implementation NSDictionary (Countly)
- (NSString *)cly_JSONify
{
    return [CountlyJSONFromObject(self) cly_URLEscaped];
}

- (NSDictionary *)cly_truncated:(NSString *)explanation
{
    NSMutableDictionary* truncatedDict = self.mutableCopy;
    [self enumerateKeysAndObjectsUsingBlock:^(NSString * key, id obj, BOOL * stop)
    {
        NSString* truncatedKey = [key cly_truncatedKey:[explanation stringByAppendingString:@" key"]];
        if (![truncatedKey isEqualToString:key])
        {
            truncatedDict[truncatedKey] = obj;
            [truncatedDict removeObjectForKey:key];
        }

        if ([obj isKindOfClass:NSString.class])
        {
            NSString* truncatedValue = [obj cly_truncatedValue:[explanation stringByAppendingString:@" value"]];
            if (![truncatedValue isEqualToString:obj])
            {
                truncatedDict[truncatedKey] = truncatedValue;
            }
        }
    }];

    return truncatedDict.copy;
}

- (NSDictionary *)cly_limited:(NSString *)explanation
{
    NSArray* allKeys = self.allKeys;

    if (allKeys.count <= CountlyCommon.sharedInstance.maxSegmentationValues)
        return self;

    NSMutableArray* excessKeys = allKeys.mutableCopy;
    [excessKeys removeObjectsInRange:(NSRange){0, CountlyCommon.sharedInstance.maxSegmentationValues}];

    CLY_LOG_D(@"%s segmentation exceeds the SDK segmentation value limit and will be trimmed, target: [%@], keyCount: [%lu], trimmedTo: [%lu], droppedKeyCount: [%lu], droppedKeys: [%@]", __FUNCTION__, explanation, (unsigned long)allKeys.count, (unsigned long)CountlyCommon.sharedInstance.maxSegmentationValues, (unsigned long)excessKeys.count, excessKeys);

    NSMutableDictionary* limitedDict = self.mutableCopy;
    [limitedDict removeObjectsForKeys:excessKeys];

    return limitedDict.copy;
}

- (NSMutableDictionary *) cly_filterSupportedDataTypes
{
    NSMutableDictionary<NSString *, id> *filteredDictionary = [NSMutableDictionary dictionary];
    
    for (NSString *key in self) {
        id value = [self objectForKey:key];
        
        if ([value isKindOfClass:[NSNumber class]] ||
            [value isKindOfClass:[NSString class]] ||
            ([value isKindOfClass:[NSArray class]] && (value = [(NSArray *)value cly_filterSupportedDataTypes]))) {
            [filteredDictionary setObject:value forKey:key];
        } else {
            CLY_LOG_D(@"%s dropping dictionary entry with an unsupported value type, key: [%@], receivedType: [%@]", __FUNCTION__, key, [value class]);
        }
    }
    
    return filteredDictionary.mutableCopy;
}

@end

@implementation NSData (Countly)
- (NSString *)cly_stringUTF8
{
    return [NSString.alloc initWithData:self encoding:NSUTF8StringEncoding];
}
@end
