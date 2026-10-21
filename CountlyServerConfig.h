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
- (void)applyAutomaticTrackingState;
/// The consent requirement start sends the consent state for. It is remembered, so applyConsentRequirement acts on a change behavior settings make after start handled consent, also one that lands before init has finished.
- (BOOL)takeConsentRequirementForStart:(CountlyConfig *)config;
/// Sends the consent state and the empty location when behavior settings turned the consent requirement on since its consent state was last sent, and starts the features that waited for consent when they turned it off.
- (void)applyConsentRequirement;
/// Clears the stored location info and sends the empty location when behavior settings turn location tracking off. Before init has finished a request would go without the app key, so startWithConfig calls this once init is complete.
- (void)applyLocationTrackingState;

@end

