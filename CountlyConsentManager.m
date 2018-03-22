// CountlyPersistency.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"


//NOTE: Consent Features
NSString* const CLYConsentSessions             = @"sessions";
NSString* const CLYConsentEvents               = @"events";
NSString* const CLYConsentUserDetails          = @"users";
NSString* const CLYConsentCrashReporting       = @"crashes";
NSString* const CLYConsentPushNotifications    = @"push";
NSString* const CLYConsentViewTracking         = @"views";
NSString* const CLYConsentAttribution          = @"attribution";
NSString* const CLYConsentStarRating           = @"star-rating";
NSString* const CLYConsentAppleWatch           = @"accessory-devices";


@interface CountlyConsentManager()
@end

@implementation CountlyConsentManager

+ (instancetype)sharedInstance
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return nil;

    static CountlyConsentManager* s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    if (self = [super init])
    {

    }

    return self;
}


- (void)giveConsentForFeatures:(NSArray *)features
{
    if (!self.requiresConsent)
        return;

    if ([features containsObject:CLYConsentCrashReporting] && !self.consentForCrashReporting)
        self.consentForCrashReporting = YES;

    if ([features containsObject:CLYConsentAppleWatch] && !self.consentForAppleWatch)
        self.consentForAppleWatch = YES;
}


- (void)cancelConsentForFeatures:(NSArray *)features
{
    if (!self.requiresConsent)
        return;

    if ([features containsObject:CLYConsentCrashReporting] && self.consentForCrashReporting)
        self.consentForCrashReporting = NO;

    if ([features containsObject:CLYConsentAppleWatch] && self.consentForAppleWatch)
        self.consentForAppleWatch = NO;
}


- (void)setConsentForCrashReporting:(BOOL)consentForCrashReporting
{
    _consentForCrashReporting = consentForCrashReporting;

    if (consentForCrashReporting)
    {
        [CountlyCrashReporter.sharedInstance startCrashReporting];
    }
    else
    {
        [CountlyCrashReporter.sharedInstance stopCrashReporting];
    }
}


- (void)setConsentForAppleWatch:(BOOL)consentForAppleWatch
{
    _consentForAppleWatch = consentForAppleWatch;

    if (consentForAppleWatch)
    {
        [CountlyCommon.sharedInstance startAppleWatchMatching];
    }
    else
    {

    }
}

@end
