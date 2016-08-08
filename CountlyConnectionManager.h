// CountlyConnectionManager.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>
#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#endif

@interface CountlyConnectionManager : NSObject <NSURLSessionDelegate>

@property (nonatomic, strong) NSString* appKey;
@property (nonatomic, strong) NSString* appHost;
@property (nonatomic, strong) NSURLSessionTask* connection;
@property (nonatomic, assign) BOOL isTestDevice;
@property (nonatomic, assign) NSTimeInterval updateSessionPeriod;
@property (nonatomic, strong) NSString* ISOCountryCode;
@property (nonatomic, strong) NSString* city;
@property (nonatomic, strong) NSString* location;
@property (nonatomic, strong) NSArray* pinnedCertificates;
@property (nonatomic, strong) NSString* customHeaderFieldName;
@property (nonatomic, strong) NSString* customHeaderFieldValue;
#if TARGET_OS_IOS
@property (nonatomic, assign) UIBackgroundTaskIdentifier bgTask;
#endif

+ (instancetype)sharedInstance;

- (void)beginSession;
- (void)updateSessionWithDuration:(int)duration;
- (void)endSessionWithDuration:(int)duration;

- (void)sendEvents;
- (void)sendUserDetails:(NSString *)userDetails;
- (void)sendPushToken:(NSString *)token;
- (void)sendCrashReportLater:(NSString *)report;
- (void)sendOldDeviceID:(NSString *)oldDeviceID;
- (void)sendParentDeviceID:(NSString *)parentDeviceID;
- (void)sendLocation:(CLLocationCoordinate2D)coordinate;

- (NSString *)queryEssentials;
- (NSString *)boundary;
- (BOOL)isRequestSuccessful:(NSData *)data;
- (void)tick;
@end