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

@interface CountlyConfig : NSObject

@property (nonatomic, strong) NSString* host;
@property (nonatomic, strong) NSString* appKey;
@property (nonatomic, strong) NSArray* features;
@property (nonatomic, strong) NSDictionary* launchOptions;

@end