// CountlyCommon.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>
#import "CountlyPersistency.h"
#import "CountlyConnectionManager.h"
#import "CountlyEvent.h"
#import "CountlyUserDetails.h"
#import "CountlyDeviceInfo.h"
#import "CountlyCrashReporter.h"
#import "CountlyAPMNetworkLog.h"
#import "CountlyAPM.h"

#ifndef COUNTLY_DEBUG
#define COUNTLY_DEBUG 1
#endif

#ifndef COUNTLY_PREFER_IDFA
#define COUNTLY_PREFER_IDFA 0
#endif

#if COUNTLY_DEBUG
#define COUNTLY_LOG(fmt, ...) NSLog(fmt, ##__VA_ARGS__)
#else
#define COUNTLY_LOG(...)
#endif

#define COUNTLY_SDK_VERSION @"15.06.01"

#if TARGET_OS_WATCH
#define COUNTLY_DEFAULT_UPDATE_INTERVAL 20.0
#define COUNTLY_EVENT_SEND_THRESHOLD 3
#import <WatchKit/WatchKit.h>
#else
#define COUNTLY_DEFAULT_UPDATE_INTERVAL 60.0
#define COUNTLY_EVENT_SEND_THRESHOLD 10
#endif

#import "Countly.h"
#import "Countly_OpenUDID.h"
#import <objc/runtime.h>

#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
#if COUNTLY_PREFER_IDFA
#import <AdSupport/ASIdentifierManager.h>
#endif
#endif

#include <sys/types.h>
#include <sys/sysctl.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#include <libkern/OSAtomic.h>
#include <execinfo.h>


//#   define COUNTLY_APP_GROUP_ID @"group.example.myapp"
#if TARGET_OS_WATCH
#   ifndef COUNTLY_APP_GROUP_ID
#       error "Application Group Identifier not specified! Please uncomment the line above and specify it."
#   endif
#endif


@interface CountlyCommon : NSObject
+ (instancetype)sharedInstance;
- (NSInteger)hourOfDay;
- (NSInteger)dayOfWeek;
- (long)timeSinceLaunch;
@end

@interface NSString (URLEscaped)
- (NSString *)URLEscaped;
@end

@interface NSArray (JSONify)
- (NSString *)JSONify;
@end

@interface NSDictionary (JSONify)
- (NSString *)JSONify;
@end

@interface NSMutableData (AppendStringUTF8)
- (void)appendStringUTF8:(NSString*)string;
@end