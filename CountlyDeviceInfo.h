// CountlyDeviceInfo.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyDeviceInfo : NSObject

@property (nonatomic, strong) NSString *deviceID;

+ (instancetype)sharedInstance;
- (void)initializeDeviceID:(NSString *)deviceID;
- (NSString *)zeroSafeIDFA;

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
+ (NSString *)buildUUID;
+ (NSString *)bundleId;
+ (NSString *)executableName;
#if TARGET_OS_IOS
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
+ (float)OpenGLESversion;
+ (BOOL)isJailbroken;
+ (BOOL)isInBackground;
@end
