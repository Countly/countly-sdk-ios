// CountlyPersistency.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyConsentManager : NSObject

@property (nonatomic) BOOL requiresConsent;

@property (nonatomic) BOOL consentForSessions;
@property (nonatomic) BOOL consentForEvents;
@property (nonatomic) BOOL consentForUserDetails;
@property (nonatomic) BOOL consentForCrashReporting;
@property (nonatomic) BOOL consentForPushNotifications;
@property (nonatomic) BOOL consentForViewTracking;
@property (nonatomic) BOOL consentForAttribution;
@property (nonatomic) BOOL consentForStarRating;
@property (nonatomic) BOOL consentForAppleWatch;

+ (instancetype)sharedInstance;
- (void)giveConsentForFeatures:(NSArray *)features;
- (void)cancelConsentForFeatures:(NSArray *)features;

@end
