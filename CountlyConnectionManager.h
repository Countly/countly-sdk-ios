// CountlyConnectionManager.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

extern NSString* const kCountlyQSKeyAppKey;
extern NSString* const kCountlyQSKeyDeviceID;
extern NSString* const kCountlyQSKeySDKVersion;
extern NSString* const kCountlyQSKeySDKName;
extern NSString* const kCountlyQSKeyMethod;
extern NSString* const kCountlyQSKeyMetrics;

extern NSString* const kCountlyEndpointI;
extern NSString* const kCountlyEndpointO;
extern NSString* const kCountlyEndpointSDK;
extern NSString* const kCountlyEndpointFeedback;
extern NSString* const kCountlyEndpointWidget;

@interface CountlyConnectionManager : NSObject <NSURLSessionDelegate>

@property (nonatomic) NSString* appKey;
@property (nonatomic) NSString* host;
@property (nonatomic) NSURLSessionTask* connection;
@property (nonatomic) NSArray* pinnedCertificates;
@property (nonatomic) NSString* customHeaderFieldName;
@property (nonatomic) NSString* customHeaderFieldValue;
@property (nonatomic) NSString* secretSalt;
@property (nonatomic) BOOL alwaysUsePOST;
@property (nonatomic) NSURLSessionConfiguration* URLSessionConfiguration;

@property (nonatomic) BOOL isTerminating;

+ (instancetype)sharedInstance;

- (void)beginSession;
- (void)updateSession;
- (void)endSession;

- (void)sendEvents;
- (void)sendPushToken:(NSString *)token;
- (void)sendLocationInfo;
- (void)sendUserDetails:(NSString *)userDetails;
- (void)sendCrashReport:(NSString *)report immediately:(BOOL)immediately;
- (void)sendOldDeviceID:(NSString *)oldDeviceID;
- (void)sendParentDeviceID:(NSString *)parentDeviceID;
- (void)sendAttribution;
- (void)sendConsentChanges:(NSString *)consentChanges;
- (void)sendPerformanceMonitoringTrace:(NSString *)trace;

- (void)proceedOnQueue;

- (NSString *)queryEssentials;
- (NSString *)appendChecksum:(NSString *)queryString;

@end
