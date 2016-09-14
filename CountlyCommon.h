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

#ifndef COUNTLY_DEBUG
#define COUNTLY_DEBUG 0
#endif

#if COUNTLY_DEBUG
#define COUNTLY_LOG(fmt, ...) NSLog([@"%@ " stringByAppendingString:fmt], @"[Countly]", ##__VA_ARGS__)
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

#if (TARGET_OS_IOS || TARGET_OS_WATCH)
@interface CountlyCommon : NSObject <WCSessionDelegate>
#else
@interface CountlyCommon : NSObject
#endif

@property (nonatomic, strong) NSString* ISOCountryCode;
@property (nonatomic, strong) NSString* city;
@property (nonatomic, strong) NSString* location;

+ (instancetype)sharedInstance;
- (NSInteger)hourOfDay;
- (NSInteger)dayOfWeek;
- (NSInteger)timeZone;
- (long)timeSinceLaunch;
- (NSTimeInterval)uniqueTimestamp;
- (NSString *)optionalParameters;
#if (TARGET_OS_IOS || TARGET_OS_WATCH)
- (void)activateWatchConnectivity;
#endif

#if (TARGET_OS_IOS)
- (void)transferParentDeviceID;
#endif
@end

@interface NSString (URLEscaped)
- (NSString *)URLEscaped;
- (NSString *)SHA1;
- (NSData *)dataUTF8;
@end

@interface NSArray (JSONify)
- (NSString *)JSONify;
@end

@interface NSDictionary (JSONify)
- (NSString *)JSONify;
@end

@interface NSMutableData (AppendStringUTF8)
- (void)appendStringUTF8:(NSString *)string;
@end

@interface NSData (stringUTF8)
- (NSString *)stringUTF8;
@end

@interface Countly (RecordEventWithTimeStamp)
- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(NSUInteger)count sum:(double)sum duration:(NSTimeInterval)duration timestamp:(NSTimeInterval)timestamp;
@end
