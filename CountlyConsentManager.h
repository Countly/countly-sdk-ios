// CountlyPersistency.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyConsentManager : NSObject

@property (nonatomic) BOOL requiresConsent;

@property (nonatomic, readonly) BOOL consentForSessions;
@property (nonatomic, readonly) BOOL consentForEvents;
@property (nonatomic, readonly) BOOL consentForUserDetails;
@property (nonatomic, readonly) BOOL consentForCrashReporting;
@property (nonatomic, readonly) BOOL consentForPushNotifications;
@property (nonatomic, readonly) BOOL consentForLocation;
@property (nonatomic, readonly) BOOL consentForViewTracking;
@property (nonatomic, readonly) BOOL consentForAttribution;
@property (nonatomic, readonly) BOOL consentForAppleWatch;
@property (nonatomic, readonly) BOOL consentForPerformanceMonitoring;
@property (nonatomic, readonly) BOOL consentForFeedback;
@property (nonatomic, readonly) BOOL consentForRemoteConfig;

+ (instancetype)sharedInstance;
- (void)giveConsentForFeatures:(NSArray *)features;
- (void)giveConsentForAllFeatures;
- (void)cancelConsentForFeatures:(NSArray *)features;
- (void)cancelConsentForAllFeatures;
- (BOOL)hasAnyConsent;

@end
