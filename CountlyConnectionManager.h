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
@property (nonatomic, strong) NSString* host;
@property (nonatomic, strong) NSURLSessionTask* connection;
@property (nonatomic, strong) NSArray* pinnedCertificates;
@property (nonatomic, strong) NSString* customHeaderFieldName;
@property (nonatomic, strong) NSString* customHeaderFieldValue;
@property (nonatomic, strong) NSString* secretSalt;
@property (nonatomic) BOOL alwaysUsePOST;

+ (instancetype)sharedInstance;

- (void)beginSession;
- (void)updateSession;
- (void)endSession;

- (void)sendEvents;
- (void)sendUserDetails:(NSString *)userDetails;
- (void)sendPushToken:(NSString *)token;
- (void)sendCrashReport:(NSString *)report immediately:(BOOL)immediately;
- (void)sendOldDeviceID:(NSString *)oldDeviceID;
- (void)sendParentDeviceID:(NSString *)parentDeviceID;
- (void)sendLocation:(CLLocationCoordinate2D)coordinate;

- (void)proceedOnQueue;
@end
