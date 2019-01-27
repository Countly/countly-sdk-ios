// CountlyCommon.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>
#import "Countly.h"
#import "Countly_OpenUDID.h"
#import "CountlyPersistency.h"
#import "CountlyConnectionManager.h"
#import "CountlyEvent.h"
#import "CountlyUserDetails.h"
#import "CountlyDeviceInfo.h"
#import "CountlyCrashReporter.h"
#import "CountlyAPMNetworkLog.h"
#import "CountlyAPM.h"
#import "CountlyConfig.h"
#import "CountlyViewTracking.h"
#import "CountlyStarRating.h"
#import "CountlyPushNotifications.h"
#import "CountlyNotificationService.h"
#import "CountlyConsentManager.h"
#import "CountlyLocationManager.h"
#import "CountlyRemoteConfig.h"

#if DEBUG
#define COUNTLY_LOG(fmt, ...) CountlyInternalLog(fmt, ##__VA_ARGS__)
#else
#define COUNTLY_LOG(...)
#endif

#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#ifndef COUNTLY_EXCLUDE_IDFA
#import <AdSupport/ASIdentifierManager.h>
#endif
#import "WatchConnectivity/WatchConnectivity.h"
#endif

#if TARGET_OS_WATCH
#import <WatchKit/WatchKit.h>
#import "WatchConnectivity/WatchConnectivity.h"
#endif

#if TARGET_OS_TV
#import <UIKit/UIKit.h>
#ifndef COUNTLY_EXCLUDE_IDFA
#import <AdSupport/ASIdentifierManager.h>
#endif
#endif

#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#endif

#import <objc/runtime.h>

extern NSString* const kCountlySDKVersion;
extern NSString* const kCountlySDKName;

extern NSString* const kCountlyErrorDomain;

NS_ERROR_ENUM(kCountlyErrorDomain)
{
    CLYErrorFeedbackWidgetNotAvailable = 10001,
    CLYErrorFeedbackWidgetNotTargetedForDevice = 10002,
    CLYErrorRemoteConfigGeneralAPIError = 10011,
};

@interface CountlyCommon : NSObject

@property (nonatomic) BOOL hasStarted;
@property (nonatomic) BOOL enableDebug;
@property (nonatomic) BOOL enableAppleWatch;
@property (nonatomic) BOOL enableAttribution;
@property (nonatomic) BOOL manualSessionHandling;

void CountlyInternalLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);

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
- (void)startAttribution;
@end


#if TARGET_OS_IOS
@interface CLYInternalViewController : UIViewController
@end

@interface CLYButton : UIButton
@property (nonatomic, copy) void (^onClick)(id sender);
+ (CLYButton *)dismissAlertButton;
@end
#endif


@interface NSString (Countly)
- (NSString *)cly_URLEscaped;
- (NSString *)cly_SHA256;
- (NSData *)cly_dataUTF8;
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
