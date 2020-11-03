// CountlyPersistency.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

CLYConsent const CLYConsentSessions             = @"sessions";
CLYConsent const CLYConsentEvents               = @"events";
CLYConsent const CLYConsentUserDetails          = @"users";
CLYConsent const CLYConsentCrashReporting       = @"crashes";
CLYConsent const CLYConsentPushNotifications    = @"push";
CLYConsent const CLYConsentLocation             = @"location";
CLYConsent const CLYConsentViewTracking         = @"views";
CLYConsent const CLYConsentAttribution          = @"attribution";
CLYConsent const CLYConsentStarRating           = @"star-rating";
CLYConsent const CLYConsentAppleWatch           = @"accessory-devices";
CLYConsent const CLYConsentPerformanceMonitoring = @"apm";
CLYConsent const CLYConsentFeedback             = @"feedback";
CLYConsent const CLYConsentRemoteConfig         = @"remote-config";


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
@synthesize consentForAppleWatch = _consentForAppleWatch;
@synthesize consentForPerformanceMonitoring = _consentForPerformanceMonitoring;
@synthesize consentForFeedback = _consentForFeedback;
@synthesize consentForRemoteConfig = _consentForRemoteConfig;

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

    //NOTE: Due to some legacy Countly Server location info problems, giving consent for location should be the first.
    //NOTE: Otherwise, if location consent is given after sessions consent, begin_session request will be sent with an empty string as location.
    if ([features containsObject:CLYConsentLocation] && !self.consentForLocation)
        self.consentForLocation = YES;

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

    if ([features containsObject:CLYConsentViewTracking] && !self.consentForViewTracking)
        self.consentForViewTracking = YES;

    if ([features containsObject:CLYConsentAttribution] && !self.consentForAttribution)
        self.consentForAttribution = YES;

    if ([features containsObject:CLYConsentAppleWatch] && !self.consentForAppleWatch)
        self.consentForAppleWatch = YES;

    if ([features containsObject:CLYConsentPerformanceMonitoring] && !self.consentForPerformanceMonitoring)
        self.consentForPerformanceMonitoring = YES;

    if ([self containsFeedbackOrStarRating:features] && !self.consentForFeedback)
        self.consentForFeedback = YES;

    if ([features containsObject:CLYConsentRemoteConfig] && !self.consentForRemoteConfig)
        self.consentForRemoteConfig = YES;

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

    if ([features containsObject:CLYConsentAppleWatch] && self.consentForAppleWatch)
        self.consentForAppleWatch = NO;

    if ([features containsObject:CLYConsentPerformanceMonitoring] && self.consentForPerformanceMonitoring)
        self.consentForPerformanceMonitoring = NO;

    if ([self containsFeedbackOrStarRating:features] && self.consentForFeedback)
        self.consentForFeedback = NO;

    if ([features containsObject:CLYConsentRemoteConfig] && self.consentForRemoteConfig)
        self.consentForRemoteConfig = NO;

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
        CLYConsentAppleWatch,
        CLYConsentPerformanceMonitoring,
        CLYConsentFeedback,
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
    self.consentForAppleWatch ||
    self.consentForPerformanceMonitoring ||
    self.consentForFeedback ||
    self.consentForRemoteConfig;
}

- (BOOL)containsFeedbackOrStarRating:(NSArray *)features
{
    //NOTE: StarRating consent is merged into new Feedback consent.
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
    return [features containsObject:CLYConsentFeedback] || [features containsObject:CLYConsentStarRating];
#pragma GCC diagnostic pop
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

    self.consentChanges[CLYConsentCrashReporting] = @(consentForCrashReporting);
}


- (void)setConsentForPushNotifications:(BOOL)consentForPushNotifications
{
    _consentForPushNotifications = consentForPushNotifications;

#if (TARGET_OS_IOS || TARGET_OS_OSX)
    if (consentForPushNotifications)
    {
        COUNTLY_LOG(@"Consent for PushNotifications is given.");

#ifndef COUNTLY_EXCLUDE_PUSHNOTIFICATIONS
        [CountlyPushNotifications.sharedInstance startPushNotifications];
#endif
    }
    else
    {
        COUNTLY_LOG(@"Consent for PushNotifications is cancelled.");
#ifndef COUNTLY_EXCLUDE_PUSHNOTIFICATIONS
        [CountlyPushNotifications.sharedInstance stopPushNotifications];
#endif
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

        [CountlyConnectionManager.sharedInstance sendAttribution];
    }
    else
    {
        COUNTLY_LOG(@"Consent for Attribution is cancelled.");
    }

    self.consentChanges[CLYConsentAttribution] = @(consentForAttribution);
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


- (void)setConsentForPerformanceMonitoring:(BOOL)consentForPerformanceMonitoring
{
    _consentForPerformanceMonitoring = consentForPerformanceMonitoring;

#if (TARGET_OS_IOS)
    if (consentForPerformanceMonitoring)
    {
        COUNTLY_LOG(@"Consent for PerformanceMonitoring is given.");
        
        [CountlyPerformanceMonitoring.sharedInstance startPerformanceMonitoring];
    }
    else
    {
        COUNTLY_LOG(@"Consent for PerformanceMonitoring is cancelled.");

        [CountlyPerformanceMonitoring.sharedInstance stopPerformanceMonitoring];
    }
#endif

    self.consentChanges[CLYConsentPerformanceMonitoring] = @(consentForPerformanceMonitoring);
}

- (void)setConsentForFeedback:(BOOL)consentForFeedback
{
    _consentForFeedback = consentForFeedback;

#if (TARGET_OS_IOS)
    if (consentForFeedback)
    {
        COUNTLY_LOG(@"Consent for Feedback is given.");

        [CountlyFeedbacks.sharedInstance checkForStarRatingAutoAsk];
    }
    else
    {
        COUNTLY_LOG(@"Consent for Feedback is cancelled.");
    }
#endif

    self.consentChanges[CLYConsentFeedback] = @(consentForFeedback);
}

- (void)setConsentForRemoteConfig:(BOOL)consentForRemoteConfig
{
    _consentForRemoteConfig = consentForRemoteConfig;

    if (consentForRemoteConfig)
    {
        COUNTLY_LOG(@"Consent for RemoteConfig is given.");

        [CountlyRemoteConfig.sharedInstance startRemoteConfig];
    }
    else
    {
        COUNTLY_LOG(@"Consent for RemoteConfig is cancelled.");
    }

    self.consentChanges[CLYConsentRemoteConfig] = @(consentForRemoteConfig);
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


- (BOOL)consentForAppleWatch
{
    if (!self.requiresConsent)
      return YES;

    return _consentForAppleWatch;
}


- (BOOL)consentForPerformanceMonitoring
{
    if (!self.requiresConsent)
        return YES;

    return _consentForPerformanceMonitoring;
}

- (BOOL)consentForFeedback
{
    if (!self.requiresConsent)
        return YES;

    return _consentForFeedback;
}

- (BOOL)consentForRemoteConfig
{
    if (!self.requiresConsent)
      return YES;

    return _consentForRemoteConfig;
}

@end
