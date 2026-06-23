//  CountlyServerConfig.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

extern NSString* const kCountlySCKeySC;

@interface CountlyServerConfig : NSObject

+ (instancetype)sharedInstance;
- (void)resetInstance;

- (void)fetchServerConfig:(CountlyConfig *)config;
- (void)retrieveServerConfigFromStorage:(CountlyConfig *)config;
- (void)fetchServerConfigIfTimeIsUp;
- (void)disableSDKBehaviourSettings;

- (BOOL)trackingEnabled;
- (BOOL)networkingEnabled;
- (NSInteger)sessionInterval;
- (NSInteger)eventQueueSize;
- (BOOL)crashReportingEnabled;
- (BOOL)automaticSessionTrackingEnabled;
- (BOOL)automaticViewTrackingEnabled;
- (BOOL)automaticCrashReportingEnabled;
- (BOOL)loggingEnabled;
- (NSInteger)limitKeyLength;
- (NSInteger)limitValueSize;
- (NSInteger)limitSegValues;
- (NSInteger)limitBreadcrumb;
- (NSInteger)limitTraceLine;
- (NSInteger)limitTraceLength;
- (BOOL)customEventTrackingEnabled;
- (BOOL)enterContentZone;
- (NSInteger)contentZoneInterval;
- (BOOL)consentRequired;
- (NSInteger)dropOldRequestTime;
- (BOOL)viewTrackingEnabled;
- (NSInteger)requestQueueSize;
- (BOOL)sessionTrackingEnabled;
- (BOOL)locationTrackingEnabled;
- (BOOL)refreshContentZoneEnabled;
- (BOOL)backoffMechanism;
- (NSInteger)bomAcceptedTimeoutSeconds;
- (double)bomRQPercentage;
- (NSInteger)bomRequestAge;
- (NSInteger)bomDuration;
- (NSInteger)requestTimeoutDuration;

#pragma mark - Listing Filters

- (BOOL)shouldRecordEvent:(NSString *)eventKey;
- (BOOL)shouldRecordUserProperty:(NSString *)propertyKey;
- (NSDictionary *)filterSegmentation:(NSDictionary *)segmentation eventKey:(NSString *)eventKey;
- (BOOL)isJourneyTriggerEvent:(NSString *)eventKey;
- (BOOL)isJourneyTriggerView:(NSString *)viewName;
- (NSInteger)userPropertyCacheLimit;

@end

