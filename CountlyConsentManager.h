// CountlyPersistency.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>
#import "Resettable.h"

@interface CountlyConsentManager : NSObject <Resettable>

@property (nonatomic) BOOL requiresConsent;

@property (nonatomic, readonly) BOOL consentForSessions;
@property (nonatomic, readonly) BOOL consentForEvents;
@property (nonatomic, readonly) BOOL consentForUserDetails;
@property (nonatomic, readonly) BOOL consentForCrashReporting;
@property (nonatomic, readonly) BOOL consentForPushNotifications;
@property (nonatomic, readonly) BOOL consentForLocation;
@property (nonatomic, readonly) BOOL consentForViewTracking;
@property (nonatomic, readonly) BOOL consentForAttribution;
@property (nonatomic, readonly) BOOL consentForPerformanceMonitoring;
@property (nonatomic, readonly) BOOL consentForFeedback;
@property (nonatomic, readonly) BOOL consentForRemoteConfig;
@property (nonatomic, readonly) BOOL consentForContent;


+ (instancetype)sharedInstance;
- (void)giveConsentForFeatures:(NSArray *)features;
- (void)giveAllConsents;
- (void)cancelConsentForFeatures:(NSArray *)features;
- (void)cancelConsentForAllFeatures;
- (void)cancelConsentForAllFeaturesWithoutSendingConsentsRequest;
- (BOOL)hasAnyConsent;
- (void)sendConsents;

@end
