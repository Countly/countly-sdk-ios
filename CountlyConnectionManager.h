// CountlyConnectionManager.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>
#import "Resettable.h"

extern NSString* const kCountlyQSKeyAppKey;
extern NSString* const kCountlyQSKeyDeviceID;
extern NSString* const kCountlyQSKeyDeviceIDType;
extern NSString* const kCountlyQSKeySDKVersion;
extern NSString* const kCountlyQSKeySDKName;
extern NSString* const kCountlyQSKeyMethod;
extern NSString* const kCountlyQSKeyMetrics;

extern NSString* const kCountlyEndpointI;
extern NSString* const kCountlyEndpointO;
extern NSString* const kCountlyEndpointSDK;
extern NSString* const kCountlyEndpointFeedback;
extern NSString* const kCountlyEndpointWidget;
extern NSString* const kCountlyEndpointSurveys;
extern NSString* const kCountlyRCKeyKeys;
extern NSString* const kCountlyQSKeyTimestamp;

extern const NSInteger kCountlyGETRequestMaxLength;

@interface CountlyConnectionManager : NSObject <NSURLSessionDelegate, Resettable>

@property (nonatomic) NSString* appKey;
@property (nonatomic) NSString* host;
@property (nonatomic) NSURLSessionTask* connection;
@property (nonatomic) NSArray* pinnedCertificates;
@property (nonatomic) NSString* secretSalt;
@property (nonatomic) BOOL alwaysUsePOST;
@property (nonatomic) NSURLSessionConfiguration* URLSessionConfiguration;

@property (nonatomic) BOOL isTerminating;

+ (instancetype)sharedInstance;

- (void)recordMetrics:(nullable NSDictionary *)metricsOverride;

- (void)beginSession;
- (void)updateSession;
- (void)endSession;

- (void)sendEventsWithSaveIfNeeded;
- (void)sendEvents;
- (void)attemptToSendStoredRequests;
- (void)sendPushToken:(NSString *)token;
- (void)sendLocationInfo;
- (void)sendUserDetails:(NSString *)userDetails;
- (void)sendCrashReport:(NSString *)report immediately:(BOOL)immediately;
- (void)sendOldDeviceID:(NSString *)oldDeviceID;
- (void)sendAttribution;
- (void)sendDirectAttributionWithCampaignID:(NSString *)campaignID andCampaignUserID:(NSString *)campaignUserID;
- (void)sendAttributionData:(NSString *)attributionData;
- (void)sendIndirectAttribution:(NSDictionary *)attribution;
- (void)sendConsents:(NSString *)consents;
- (void)sendPerformanceMonitoringTrace:(NSString *)trace;

- (void)sendEnrollABRequestForKeys:(NSArray*)keys;
- (void)sendExitABRequestForKeys:(NSArray*)keys;

- (void)addDirectRequest:(NSDictionary<NSString *, NSString *> *)requestParameters;
- (void)addCustomNetworkRequestHeaders:(NSDictionary<NSString *, NSString *> *_Nullable)customHeaderValues;

- (void)proceedOnQueue;

- (NSString *)queryEssentials;
- (NSString *)appendChecksum:(NSString *)queryString;

- (BOOL)isSessionStarted;

#pragma mark - Request Callbacks

/**
 * Callback block type for individual request results.
 * @param response Response string from server (or error description if failed)
 * @param success YES if request succeeded, NO if failed
 */
typedef void (^CLYRequestCallback)(NSString * _Nullable response, BOOL success);

/**
 * Callback block type for global queue flush events.
 * @param allSuccess YES if all requests in the queue were successful, NO if any failed
 */
typedef void (^CLYQueueFlushCallback)(BOOL allSuccess);

/**
 * Sets a global callback to be executed when the entire queue is flushed.
 * @discussion This callback is called when queue becomes empty after processing requests.
 * @discussion Only one global callback can be active at a time. Setting a new one replaces the old one.
 * @discussion Pass nil to remove the global callback.
 * @param callback Block to be executed when queue is flushed, or nil to remove
 */
- (void)setGlobalQueueFlushCallback:(CLYQueueFlushCallback _Nullable)callback;

/**
 * Adds a request to the queue with an associated callback.
 * @discussion The callback will be executed when this specific request completes.
 * @discussion A unique callback ID will be automatically generated internally using UUID.
 * @discussion Callback IDs are managed internally and cannot be accessed or modified by developers.
 * @param queryString Query string for the request
 * @param callback Block to be executed when this request completes
 */
- (void)addToQueueWithCallback:(NSString *)queryString callback:(CLYRequestCallback)callback;

@end
