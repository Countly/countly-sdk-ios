// CountlyCommon.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>
#import "Countly.h"
#import "CountlyPersistency.h"
#import "CountlyConnectionManager.h"
#import "CountlyEvent.h"
#import "CountlyUserDetails.h"
#import "CountlyDeviceInfo.h"
#import "CountlyCrashReporter.h"
#import "CountlyConfig.h"
#import "CountlyViewTracking.h"
#import "CountlyFeedbacks.h"
#import "CountlyFeedbackWidget.h"
#import "CountlyPushNotifications.h"
#import "CountlyNotificationService.h"
#import "CountlyConsentManager.h"
#import "CountlyLocationManager.h"
#import "CountlyRemoteConfig.h"
#import "CountlyPerformanceMonitoring.h"

#define CLY_LOG_E(fmt, ...) CountlyInternalLog(CLYInternalLogLevelError, fmt, ##__VA_ARGS__)
#define CLY_LOG_W(fmt, ...) CountlyInternalLog(CLYInternalLogLevelWarning, fmt, ##__VA_ARGS__)
#define CLY_LOG_I(fmt, ...) CountlyInternalLog(CLYInternalLogLevelInfo, fmt, ##__VA_ARGS__)
#define CLY_LOG_D(fmt, ...) CountlyInternalLog(CLYInternalLogLevelDebug, fmt, ##__VA_ARGS__)
#define CLY_LOG_V(fmt, ...) CountlyInternalLog(CLYInternalLogLevelVerbose, fmt, ##__VA_ARGS__)

#if (TARGET_OS_IOS)
#import <UIKit/UIKit.h>
#import "WatchConnectivity/WatchConnectivity.h"
#endif

#if (TARGET_OS_WATCH)
#import <WatchKit/WatchKit.h>
#import "WatchConnectivity/WatchConnectivity.h"
#endif

#if (TARGET_OS_TV)
#import <UIKit/UIKit.h>
#endif

#import <objc/runtime.h>

extern NSString* _Nonnull const kCountlyErrorDomain;

NS_ERROR_ENUM(kCountlyErrorDomain)
{
    CLYErrorFeedbackWidgetNotAvailable = 10001,
    CLYErrorFeedbackWidgetNotTargetedForDevice = 10002,
    CLYErrorRemoteConfigGeneralAPIError = 10011,
    CLYErrorFeedbacksGeneralAPIError = 10012,
};

@interface CountlyCommon : NSObject

@property (nonatomic, copy, nonnull) NSString* SDKVersion;
@property (nonatomic, copy, nonnull) NSString* SDKName;

@property (nonatomic) BOOL hasStarted;
@property (nonatomic) BOOL enableDebug;
@property (nonatomic, weak, nullable) id <CountlyLoggerDelegate> loggerDelegate;
@property (nonatomic) CLYInternalLogLevel internalLogLevel;
@property (nonatomic) BOOL enableAppleWatch;
@property (nonatomic, copy, nullable) NSString* attributionID;
@property (nonatomic) BOOL manualSessionHandling;

void CountlyInternalLog(CLYInternalLogLevel level, NSString* _Nonnull format, ...) NS_FORMAT_FUNCTION(2, 3);
void CountlyPrint(NSString* _Nonnull stringToPrint);

+ (nonnull instancetype)sharedInstance;
- (NSInteger)hourOfDay;
- (NSInteger)dayOfWeek;
- (NSInteger)timeZone;
- (NSInteger)timeSinceLaunch;
- (NSTimeInterval)uniqueTimestamp;

- (void)startBackgroundTask;
- (void)finishBackgroundTask;

#if (TARGET_OS_IOS || TARGET_OS_TV)
- (nullable UIViewController *)topViewController;
- (void)tryPresentingViewController:(nullable UIViewController *)viewController;
- (void)tryPresentingViewController:(nullable UIViewController *)viewController withCompletion:(void (^ __nullable) (void))completion;
#endif

- (void)startAppleWatchMatching;

- (void)observeDeviceOrientationChanges;

- (BOOL)hasStarted_;
@end


#if (TARGET_OS_IOS)
@interface CLYInternalViewController : UIViewController
@end

@interface CLYButton : UIButton
@property (nonatomic, nullable, copy) void (^onClick)(id _Nonnull sender);
+ (nonnull CLYButton *)dismissAlertButton;
- (void)positionToTopRight;
- (void)positionToTopRightConsideringStatusBar;
@end
#endif

@interface CLYDelegateInterceptor : NSObject
@property (nonatomic, nullable, weak) id originalDelegate;
@end

@interface NSString (Countly)
- (nonnull NSString *)cly_URLEscaped;
- (nonnull NSString *)cly_SHA256;
- (nonnull NSData *)cly_dataUTF8;
- (nonnull NSString *)cly_valueForQueryStringKey:(nonnull NSString *)key;
@end

@interface NSArray (Countly)
- (nonnull NSString *)cly_JSONify;
@end

@interface NSDictionary (Countly)
- (nonnull NSString *)cly_JSONify;
@end

@interface NSData (Countly)
- (nonnull NSString *)cly_stringUTF8;
@end

@interface Countly (RecordReservedEvent)
- (void)recordReservedEvent:(nonnull NSString *)key segmentation:(nullable NSDictionary *)segmentation;
- (void)recordReservedEvent:(nonnull NSString *)key segmentation:(nullable NSDictionary *)segmentation count:(NSUInteger)count sum:(double)sum duration:(NSTimeInterval)duration timestamp:(NSTimeInterval)timestamp;
@end

@interface CountlyUserDetails (ClearUserDetails)
- (void)clearUserDetails;
@end
