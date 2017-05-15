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

#if DEBUG
#define COUNTLY_LOG(fmt, ...) CountlyInternalLog(fmt, ##__VA_ARGS__)
#else
#define COUNTLY_LOG(...)
#endif

#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#import <AdSupport/ASIdentifierManager.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
#import "WatchConnectivity/WatchConnectivity.h"
#endif

#if TARGET_OS_WATCH
#import <WatchKit/WatchKit.h>
#import "WatchConnectivity/WatchConnectivity.h"
#endif

#if TARGET_OS_TV
#import <UIKit/UIKit.h>
#import <AdSupport/ASIdentifierManager.h>
#endif

#ifndef TARGET_OS_OSX
#define TARGET_OS_OSX (!(TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_WATCH))
#endif

#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#endif

#include <sys/types.h>
#include <sys/sysctl.h>
#include <libkern/OSAtomic.h>
#include <execinfo.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <objc/runtime.h>

extern NSString* const kCountlySDKVersion;
extern NSString* const kCountlySDKName;

@interface CountlyCommon : NSObject

@property (nonatomic) BOOL enableDebug;
@property (nonatomic) BOOL enableAppleWatch;
@property (nonatomic) BOOL manualSessionHandling;
@property (nonatomic, strong) NSString* ISOCountryCode;
@property (nonatomic, strong) NSString* city;
@property (nonatomic, strong) NSString* location;
@property (nonatomic, strong) NSString* IP;

void CountlyInternalLog(NSString *format, ...) NS_FORMAT_FUNCTION(1,2);

+ (instancetype)sharedInstance;
- (NSInteger)hourOfDay;
- (NSInteger)dayOfWeek;
- (NSInteger)timeZone;
- (NSInteger)timeSinceLaunch;
- (NSTimeInterval)uniqueTimestamp;
#if (TARGET_OS_IOS || TARGET_OS_WATCH)
- (void)activateWatchConnectivity;
#endif

#if TARGET_OS_IOS
- (void)transferParentDeviceID;
#endif
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

@interface Countly (RecordEventWithTimeStamp)
- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(NSUInteger)count sum:(double)sum duration:(NSTimeInterval)duration timestamp:(NSTimeInterval)timestamp;
@end
