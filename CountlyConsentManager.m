// CountlyPersistency.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

NSString* const CLYConsentSessions             = @"sessions";
NSString* const CLYConsentEvents               = @"events";
NSString* const CLYConsentUserDetails          = @"users";
NSString* const CLYConsentCrashReporting       = @"crashes";
NSString* const CLYConsentPushNotifications    = @"push";
NSString* const CLYConsentLocation             = @"location";
NSString* const CLYConsentViewTracking         = @"views";
NSString* const CLYConsentAttribution          = @"attribution";
NSString* const CLYConsentStarRating           = @"star-rating";
NSString* const CLYConsentAppleWatch           = @"accessory-devices";


@interface CountlyConsentManager ()
@property (nonatomic, strong) NSMutableDictionary* consentChanges;
@end

@implementation CountlyConsentManager

@synthesize consentForSessions = _consentForSessions;
@synthesize consentForEvents = _consentForEvents;
@synthesize consentForUserDetails = _consentForUserDetails;
@synthesize consentForCrashReporting = _consentForCrashReporting;
@synthesize consentForPushNotifications = _consentForPushNotifications;
@synthesize consentForLocation = _consentForLocation;
@synthesize consentForViewTracking = _consentForViewTracking;
@synthesize consentForAttribution = _consentForAttribution;
@synthesize consentForStarRating = _consentForStarRating;
@synthesize consentForAppleWatch = _consentForAppleWatch;

#pragma mark -

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


#pragma mark -


- (void)giveConsentForAllFeatures
{
    [self giveConsentForFeatures:[self allFeatures]];
}


- (void)giveConsentForFeatures:(NSArray *)features
{
    if (!self.requiresConsent)
        return;

    if (!features.count)
        return;

    if ([features containsObject:CLYConsentSessions] && !self.consentForSessions)
        self.consentForSessions = YES;

    if ([features containsObject:CLYConsentEvents] && !self.consentForEvents)
        self.consentForEvents = YES;

    if ([features containsObject:CLYConsentUserDetails] && !self.consentForUserDetails)
        self.consentForUserDetails = YES;

    if ([features containsObject:CLYConsentCrashReporting] && !self.consentForCrashReporting)
        self.consentForCrashReporting = YES;

    if ([features containsObject:CLYConsentPushNotifications] && !self.consentForPushNotifications)
        self.consentForPushNotifications = YES;

    if ([features containsObject:CLYConsentLocation] && !self.consentForLocation)
        self.consentForLocation = YES;

    if ([features containsObject:CLYConsentViewTracking] && !self.consentForViewTracking)
        self.consentForViewTracking = YES;

    if ([features containsObject:CLYConsentAttribution] && !self.consentForAttribution)
        self.consentForAttribution = YES;

    if ([features containsObject:CLYConsentStarRating] && !self.consentForStarRating)
        self.consentForStarRating = YES;

    if ([features containsObject:CLYConsentAppleWatch] && !self.consentForAppleWatch)
        self.consentForAppleWatch = YES;

    [self sendConsentChanges];
}


- (void)cancelConsentForAllFeatures
{
    [self cancelConsentForFeatures:[self allFeatures]];
}


- (void)cancelConsentForFeatures:(NSArray *)features
{
    if (!self.requiresConsent)
        return;

    if ([features containsObject:CLYConsentSessions] && self.consentForSessions)
        self.consentForSessions = NO;

    if ([features containsObject:CLYConsentEvents] && self.consentForEvents)
        self.consentForEvents = NO;

    if ([features containsObject:CLYConsentUserDetails] && self.consentForUserDetails)
        self.consentForUserDetails = NO;

    if ([features containsObject:CLYConsentCrashReporting] && self.consentForCrashReporting)
        self.consentForCrashReporting = NO;

    if ([features containsObject:CLYConsentPushNotifications] && self.consentForPushNotifications)
        self.consentForPushNotifications = NO;

    if ([features containsObject:CLYConsentLocation] && self.consentForLocation)
        self.consentForLocation = NO;

    if ([features containsObject:CLYConsentViewTracking] && self.consentForViewTracking)
        self.consentForViewTracking = NO;

    if ([features containsObject:CLYConsentAttribution] && self.consentForAttribution)
        self.consentForAttribution = NO;

    if ([features containsObject:CLYConsentStarRating] && self.consentForStarRating)
        self.consentForStarRating = NO;

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


- (NSArray *)allFeatures
{
    return
    @[
        CLYConsentSessions,
        CLYConsentEvents,
        CLYConsentUserDetails,
        CLYConsentCrashReporting,
        CLYConsentPushNotifications,
        CLYConsentLocation,
        CLYConsentViewTracking,
        CLYConsentAttribution,
        CLYConsentStarRating,
        CLYConsentAppleWatch,
    ];
}


- (BOOL)hasAnyConsent
{
    return
    self.consentForSessions ||
    self.consentForEvents ||
    self.consentForUserDetails ||
    self.consentForCrashReporting ||
    self.consentForPushNotifications ||
    self.consentForLocation ||
    self.consentForViewTracking ||
    self.consentForAttribution ||
    self.consentForStarRating ||
    self.consentForAppleWatch;
}


#pragma mark -


- (void)setConsentForSessions:(BOOL)consentForSessions
{
    _consentForSessions = consentForSessions;

    if (consentForSessions)
    {
        COUNTLY_LOG(@"Consent for Session is given.");

        if (!CountlyCommon.sharedInstance.manualSessionHandling)
            [CountlyConnectionManager.sharedInstance beginSession];
    }
    else
    {
        COUNTLY_LOG(@"Consent for Session is cancelled.");
    }

    self.consentChanges[CLYConsentSessions] = @(consentForSessions);
}


- (void)setConsentForEvents:(BOOL)consentForEvents
{
    _consentForEvents = consentForEvents;

    if (consentForEvents)
    {
        COUNTLY_LOG(@"Consent for Events is given.");
    }
    else
    {
        COUNTLY_LOG(@"Consent for Events is cancelled.");

        [CountlyConnectionManager.sharedInstance sendEvents];
        [CountlyPersistency.sharedInstance clearAllTimedEvents];
    }

    self.consentChanges[CLYConsentEvents] = @(consentForEvents);
}


- (void)setConsentForUserDetails:(BOOL)consentForUserDetails
{
    _consentForUserDetails = consentForUserDetails;

    if (consentForUserDetails)
    {
        COUNTLY_LOG(@"Consent for UserDetails is given.");
    }
    else
    {
        COUNTLY_LOG(@"Consent for UserDetails is cancelled.");

        [CountlyUserDetails.sharedInstance clearUserDetails];
    }

    self.consentChanges[CLYConsentUserDetails] = @(consentForUserDetails);
}


- (void)setConsentForCrashReporting:(BOOL)consentForCrashReporting
{
    _consentForCrashReporting = consentForCrashReporting;

#if TARGET_OS_IOS
    if (consentForCrashReporting)
    {
        COUNTLY_LOG(@"Consent for CrashReporting is given.");

        [CountlyCrashReporter.sharedInstance startCrashReporting];
    }
    else
    {
        COUNTLY_LOG(@"Consent for CrashReporting is cancelled.");

        [CountlyCrashReporter.sharedInstance stopCrashReporting];
    }
#endif

    self.consentChanges[CLYConsentCrashReporting] = @(consentForCrashReporting);
}


- (void)setConsentForPushNotifications:(BOOL)consentForPushNotifications
{
    _consentForPushNotifications = consentForPushNotifications;

#if TARGET_OS_IOS
    if (consentForPushNotifications)
    {
        COUNTLY_LOG(@"Consent for PushNotifications is given.");

        [CountlyPushNotifications.sharedInstance startPushNotifications];
    }
    else
    {
        COUNTLY_LOG(@"Consent for PushNotifications is cancelled.");

        [CountlyPushNotifications.sharedInstance stopPushNotifications];
    }
#endif

    self.consentChanges[CLYConsentPushNotifications] = @(consentForPushNotifications);
}


- (void)setConsentForLocation:(BOOL)consentForLocation
{
    _consentForLocation = consentForLocation;

    if (consentForLocation)
    {
        COUNTLY_LOG(@"Consent for Location is given.");

        [CountlyLocationManager.sharedInstance sendLocationInfo];
    }
    else
    {
        COUNTLY_LOG(@"Consent for Location is cancelled.");
    }

    self.consentChanges[CLYConsentLocation] = @(consentForLocation);
}


- (void)setConsentForViewTracking:(BOOL)consentForViewTracking
{
    _consentForViewTracking = consentForViewTracking;

#if (TARGET_OS_IOS || TARGET_OS_TV)
    if (consentForViewTracking)
    {
        COUNTLY_LOG(@"Consent for ViewTracking is given.");

        [CountlyViewTracking.sharedInstance startAutoViewTracking];
    }
    else
    {
        COUNTLY_LOG(@"Consent for ViewTracking is cancelled.");

        [CountlyViewTracking.sharedInstance stopAutoViewTracking];
    }
#endif

    self.consentChanges[CLYConsentViewTracking] = @(consentForViewTracking);
}


- (void)setConsentForAttribution:(BOOL)consentForAttribution
{
    _consentForAttribution = consentForAttribution;

    if (consentForAttribution)
    {
        COUNTLY_LOG(@"Consent for Attribution is given.");

        [CountlyCommon.sharedInstance startAttribution];
    }
    else
    {
        COUNTLY_LOG(@"Consent for Attribution is cancelled.");
    }

    self.consentChanges[CLYConsentAttribution] = @(consentForAttribution);
}


- (void)setConsentForStarRating:(BOOL)consentForStarRating
{
    _consentForStarRating = consentForStarRating;

#if TARGET_OS_IOS
    if (consentForStarRating)
    {
        COUNTLY_LOG(@"Consent for StarRating is given.");

        [CountlyStarRating.sharedInstance checkForAutoAsk];
    }
    else
    {
        COUNTLY_LOG(@"Consent for StarRating is cancelled.");
    }
#endif

    self.consentChanges[CLYConsentStarRating] = @(consentForStarRating);
}


- (void)setConsentForAppleWatch:(BOOL)consentForAppleWatch
{
    _consentForAppleWatch = consentForAppleWatch;

#if (TARGET_OS_IOS || TARGET_OS_WATCH)
    if (consentForAppleWatch)
    {
        COUNTLY_LOG(@"Consent for AppleWatch is given.");

        [CountlyCommon.sharedInstance startAppleWatchMatching];
    }
    else
    {
        COUNTLY_LOG(@"Consent for AppleWatch is cancelled.");
    }
#endif

    self.consentChanges[CLYConsentAppleWatch] = @(consentForAppleWatch);
}

#pragma mark -

- (BOOL)consentForSessions
{
    if (!self.requiresConsent)
      return YES;

    return _consentForSessions;
}


- (BOOL)consentForEvents
{
    if (!self.requiresConsent)
      return YES;

    return _consentForEvents;
}


- (BOOL)consentForUserDetails
{
    if (!self.requiresConsent)
      return YES;

    return _consentForUserDetails;
}


- (BOOL)consentForCrashReporting
{
    if (!self.requiresConsent)
      return YES;

    return _consentForCrashReporting;
}


- (BOOL)consentForPushNotifications
{
    if (!self.requiresConsent)
      return YES;

    return _consentForPushNotifications;
}


- (BOOL)consentForLocation
{
    if (!self.requiresConsent)
        return YES;

    return _consentForLocation;
}


- (BOOL)consentForViewTracking
{
    if (!self.requiresConsent)
      return YES;

    return _consentForViewTracking;
}


- (BOOL)consentForAttribution
{
    if (!self.requiresConsent)
      return YES;

    return _consentForAttribution;
}


- (BOOL)consentForStarRating
{
    if (!self.requiresConsent)
      return YES;

    return _consentForStarRating;
}


- (BOOL)consentForAppleWatch
{
    if (!self.requiresConsent)
      return YES;

    return _consentForAppleWatch;
}

@end
