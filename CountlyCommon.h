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

#define COUNTLY_LOG(fmt, ...) CountlyInternalLog(fmt, ##__VA_ARGS__)

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

extern NSString* const kCountlyErrorDomain;

NS_ERROR_ENUM(kCountlyErrorDomain)
{
    CLYErrorFeedbackWidgetNotAvailable = 10001,
    CLYErrorFeedbackWidgetNotTargetedForDevice = 10002,
    CLYErrorRemoteConfigGeneralAPIError = 10011,
    CLYErrorFeedbacksGeneralAPIError = 10012,
};

@interface CountlyCommon : NSObject

@property (nonatomic, copy) NSString* SDKVersion;
@property (nonatomic, copy) NSString* SDKName;

@property (nonatomic) BOOL hasStarted;
@property (nonatomic) BOOL enableDebug;
@property (nonatomic, weak) id <CountlyLoggerDelegate> loggerDelegate;
@property (nonatomic) BOOL enableAppleWatch;
@property (nonatomic, copy) NSString* attributionID;
@property (nonatomic) BOOL manualSessionHandling;

void CountlyInternalLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);
void CountlyPrint(NSString *stringToPrint);

+ (instancetype)sharedInstance;
- (NSInteger)hourOfDay;
- (NSInteger)dayOfWeek;
- (NSInteger)timeZone;
- (NSInteger)timeSinceLaunch;
- (NSTimeInterval)uniqueTimestamp;

- (void)startBackgroundTask;
- (void)finishBackgroundTask;

#if (TARGET_OS_IOS || TARGET_OS_TV)
- (UIViewController *)topViewController;
- (void)tryPresentingViewController:(UIViewController *)viewController;
#endif

- (void)startAppleWatchMatching;

- (void)observeDeviceOrientationChanges;

- (BOOL)hasStarted_;
@end


#if (TARGET_OS_IOS)
@interface CLYInternalViewController : UIViewController
@end

@interface CLYButton : UIButton
@property (nonatomic, copy) void (^onClick)(id sender);
+ (CLYButton *)dismissAlertButton;
- (void)positionToTopRight;
- (void)positionToTopRightConsideringStatusBar;
@end
#endif

@interface CLYDelegateInterceptor : NSObject
@property (nonatomic, weak) id originalDelegate;
@end

@interface NSString (Countly)
- (NSString *)cly_URLEscaped;
- (NSString *)cly_SHA256;
- (NSData *)cly_dataUTF8;
- (NSString *)cly_valueForQueryStringKey:(NSString *)key;
@end

@interface NSArray (Countly)
- (NSString *)cly_JSONify;
@end

@interface NSDictionary (Countly)
- (NSString *)cly_JSONify;
@end

@interface NSData (Countly)
- (NSString *)cly_stringUTF8;
@end

@interface Countly (RecordReservedEvent)
- (void)recordReservedEvent:(NSString *)key segmentation:(NSDictionary *)segmentation;
- (void)recordReservedEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(NSUInteger)count sum:(double)sum duration:(NSTimeInterval)duration timestamp:(NSTimeInterval)timestamp;
@end

@interface CountlyUserDetails (ClearUserDetails)
- (void)clearUserDetails;
@end
