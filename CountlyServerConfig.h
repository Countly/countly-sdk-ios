//  CountlyServerConfig.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

extern NSString* const kCountlySCKeySC;

@interface CountlyServerConfig : NSObject

+ (instancetype)sharedInstance;

- (void)fetchServerConfig:(CountlyConfig *)config;
- (void)retrieveServerConfigFromStorage:(NSString*) sdkBehaviorSettings;
- (void)fetchServerConfigIfTimeIsUp;

- (BOOL)trackingEnabled;
- (BOOL)networkingEnabled;
- (NSInteger)sessionInterval;
- (NSInteger)eventQueueSize;
- (BOOL)crashReportingEnabled;
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
@end

