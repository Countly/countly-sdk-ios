// CountlyConfig.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

//Countly features
#if TARGET_OS_IOS
extern NSString* const CLYMessaging;
extern NSString* const CLYCrashReporting;
#endif
extern NSString* const CLYAPM;


//Device ID options
#if TARGET_OS_IOS
extern NSString* const CLYIDFA;
extern NSString* const CLYIDFV;
extern NSString* const CLYOpenUDID;
#elif (!(TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_WATCH))
extern NSString* const CLYOpenUDID;
#endif

@interface CountlyConfig : NSObject

@property (nonatomic, strong) NSString* host;
@property (nonatomic, strong) NSString* appKey;
@property (nonatomic, strong) NSString* deviceID;
@property (nonatomic, readwrite) BOOL forceDeviceIDInitialization;
@property (nonatomic, strong) NSArray* features;
@property (nonatomic, strong) NSDictionary* launchOptions;

@end