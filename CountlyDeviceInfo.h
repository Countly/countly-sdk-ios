// CountlyDeviceInfo.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyDeviceInfo : NSObject <Resettable>

typedef enum : NSUInteger
{
    CLYDeviceIDTypeValueCustom = 0,
    CLYDeviceIDTypeValueIDFV = 1,
    CLYDeviceIDTypeValueNSUUID = 2,
    CLYDeviceIDTypeValueTemporary = 9
} CLYDeviceIDTypeValue;


@property (nonatomic) NSString *deviceID;
@property (nonatomic) NSDictionary<NSString *, NSString *>* customMetrics;

+ (instancetype)sharedInstance;
- (void)initializeDeviceID:(NSString *)deviceID;
- (NSString *)ensafeDeviceID:(NSString *)deviceID;
- (BOOL)isDeviceIDTemporary;
- (CLYDeviceIDTypeValue)deviceIDTypeValue;

+ (NSString *)device;
+ (NSString *)deviceType;
+ (NSString *)architecture;
+ (NSString *)osName;
+ (NSString *)osVersion;
+ (NSString *)carrier;
+ (NSString *)resolution;
+ (NSString *)density;
+ (NSString *)locale;
+ (NSString *)appVersion;
+ (NSString *)appBuild;

+ (NSDictionary *)metricsDictionary;
+ (NSString *)metrics;

+ (NSUInteger)connectionType;
+ (unsigned long long)freeRAM;
+ (unsigned long long)totalRAM;
+ (unsigned long long)freeDisk;
+ (unsigned long long)totalDisk;
+ (NSInteger)batteryLevel;
+ (NSString *)orientation;
+ (BOOL)isJailbroken;
+ (BOOL)isInBackground;
+ (NSString *)architectureNameForCPUType:(cpu_type_t)cpuType subtype:(cpu_subtype_t)cpuSubtype;

// Resolves the theme the app is currently rendering with. Returns @"d" for dark, @"l" for light,
// or nil when the mode is undefined/unavailable (e.g. below iOS 13). Reads the key window's trait
// collection because in-app messages render in that window - so its style is the effective theme.
+ (nullable NSString *)themeMode;

// Appends the current theme as the "th" query parameter to the given URL, so a feedback/rating
// widget or content loaded in a WebView renders matching the theme. "?" is used when the URL has
// no query yet, "&" otherwise. When the theme is undefined the URL is returned unchanged.
+ (NSString *)URLStringByAppendingThemeMode:(NSString *)urlString NS_SWIFT_NAME(urlStringByAppendingThemeMode(_:));

// Primitive used by URLStringByAppendingThemeMode: with the resolved theme passed explicitly so
// the separator/omission logic is testable independently of the runtime interface style.
+ (NSString *)URLString:(NSString *)urlString byAppendingThemeMode:(nullable NSString *)theme;
@end
