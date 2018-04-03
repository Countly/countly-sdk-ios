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
@property (nonatomic, strong) NSMutableDictionary* consentChanges;
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
        self.consentChanges = NSMutableDictionary.new;
    }

    return self;
}


- (void)giveConsentForFeatures:(NSArray *)features
{
    if (!self.requiresConsent)
        return;

    if ([features containsObject:CLYConsentEvents] && !self.consentForEvents)
        self.consentForEvents = YES;

    if ([features containsObject:CLYConsentUserDetails] && !self.consentForUserDetails)
        self.consentForUserDetails = YES;

    if ([features containsObject:CLYConsentCrashReporting] && !self.consentForCrashReporting)
        self.consentForCrashReporting = YES;

    if ([features containsObject:CLYConsentAppleWatch] && !self.consentForAppleWatch)
        self.consentForAppleWatch = YES;

    [self sendConsentChanges];
}


- (void)cancelConsentForFeatures:(NSArray *)features
{
    if (!self.requiresConsent)
        return;

    if ([features containsObject:CLYConsentEvents] && self.consentForEvents)
        self.consentForEvents = NO;

    if ([features containsObject:CLYConsentUserDetails] && self.consentForUserDetails)
        self.consentForUserDetails = NO;

    if ([features containsObject:CLYConsentCrashReporting] && self.consentForCrashReporting)
        self.consentForCrashReporting = NO;

    if ([features containsObject:CLYConsentAppleWatch] && self.consentForAppleWatch)
        self.consentForAppleWatch = NO;

    [self sendConsentChanges];
}


- (void)sendConsentChanges
{
    if (self.consentChanges.allKeys.count)
    {
        [CountlyConnectionManager.sharedInstance sendConsentChanges:[self.consentChanges cly_JSONify]];
        [self.consentChanges removeAllObjects];
    }
}


#pragma mark -


- (void)setConsentForEvents:(BOOL)consentForEvents
{
    _consentForEvents = consentForEvents;

    if (consentForEvents)
    {
        //NOTE: consent for Events is given
    }
    else
    {
        [CountlyPersistency.sharedInstance clearAllTimedEvents];
    }

    self.consentChanges[CLYConsentEvents] = @(consentForEvents);
}


- (void)setConsentForUserDetails:(BOOL)consentForUserDetails
{
    _consentForUserDetails = consentForUserDetails;

    if (consentForUserDetails)
    {
        //NOTE: consent for UserDetails is given
    }
    else
    {
        [CountlyUserDetails.sharedInstance clearUserDetails];
    }

    self.consentChanges[CLYConsentUserDetails] = @(consentForUserDetails);
}


#if TARGET_OS_IOS
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

    self.consentChanges[CLYConsentCrashReporting] = @(consentForCrashReporting);
}
#endif


#if (TARGET_OS_IOS || TARGET_OS_WATCH)
- (void)setConsentForAppleWatch:(BOOL)consentForAppleWatch
{
    _consentForAppleWatch = consentForAppleWatch;

    if (consentForAppleWatch)
    {
        [CountlyCommon.sharedInstance startAppleWatchMatching];
    }
    else
    {
        //NOTE: consent for AppleWatch is cancelled
    }

    self.consentChanges[CLYConsentAppleWatch] = @(consentForAppleWatch);
}
#endif

@end
