// CountlyConnectionManager.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
#import <UIKit/UIKit.h>
#endif

@interface CountlyConnectionManager : NSObject

@property (nonatomic, strong) NSString* appKey;
@property (nonatomic, strong) NSString* appHost;
@property (nonatomic, strong) NSURLSessionTask* connection;
@property (nonatomic, assign) BOOL startedWithTest;
@property (nonatomic, strong) NSString* locationString;
#if (TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR) && (!COUNTLY_TARGET_WATCHKIT)
@property (nonatomic, assign) UIBackgroundTaskIdentifier bgTask;
#endif

+ (instancetype)sharedInstance;

- (void)beginSession;
- (void)updateSessionWithDuration:(int)duration;
- (void)endSessionWithDuration:(int)duration;

- (void)sendEvents;
- (void)sendUserDetails;
- (void)sendPushToken:(NSString*)token;
- (void)sendCrashReportLater:(NSString *)report;

- (NSString *)queryEssentials;

@end