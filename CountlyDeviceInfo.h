// CountlyDeviceInfo.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyDeviceInfo : NSObject

@property (nonatomic) NSString *deviceID;
@property (nonatomic) NSDictionary<NSString *, NSString *>* customMetrics;

+ (instancetype)sharedInstance;
- (void)initializeDeviceID:(NSString *)deviceID;
- (NSString *)ensafeDeviceID:(NSString *)deviceID;
- (BOOL)isDeviceIDTemporary;

+ (NSString *)device;
+ (NSString *)architecture;
+ (NSString *)osName;
+ (NSString *)osVersion;
+ (NSString *)carrier;
+ (NSString *)resolution;
+ (NSString *)density;
+ (NSString *)locale;
+ (NSString *)appVersion;
+ (NSString *)appBuild;
#if (TARGET_OS_IOS)
+ (NSInteger)hasWatch;
+ (NSInteger)installedWatchApp;
#endif

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
@end
