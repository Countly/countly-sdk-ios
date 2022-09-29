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
CLYConsent const CLYConsentPerformanceMonitoring = @"apm";
CLYConsent const CLYConsentFeedback             = @"feedback";
CLYConsent const CLYConsentRemoteConfig         = @"remote-config";


@implementation CountlyConsentManager

@synthesize consentForSessions = _consentForSessions;
@synthesize consentForEvents = _consentForEvents;
@synthesize consentForUserDetails = _consentForUserDetails;
@synthesize consentForCrashReporting = _consentForCrashReporting;
@synthesize consentForPushNotifications = _consentForPushNotifications;
@synthesize consentForLocation = _consentForLocation;
@synthesize consentForViewTracking = _consentForViewTracking;
@synthesize consentForAttribution = _consentForAttribution;
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
    
    if ([features containsObject:CLYConsentUserDetails] && !self.consentForUserDetails)
        self.consentForUserDetails = YES;

    if ([features containsObject:CLYConsentSessions] && !self.consentForSessions)
        self.consentForSessions = YES;

    if ([features containsObject:CLYConsentEvents] && !self.consentForEvents)
        self.consentForEvents = YES;

    if ([features containsObject:CLYConsentCrashReporting] && !self.consentForCrashReporting)
        self.consentForCrashReporting = YES;

    if ([features containsObject:CLYConsentPushNotifications] && !self.consentForPushNotifications)
        self.consentForPushNotifications = YES;

    if ([features containsObject:CLYConsentViewTracking] && !self.consentForViewTracking)
        self.consentForViewTracking = YES;

    if ([features containsObject:CLYConsentAttribution] && !self.consentForAttribution)
        self.consentForAttribution = YES;

    if ([features containsObject:CLYConsentPerformanceMonitoring] && !self.consentForPerformanceMonitoring)
        self.consentForPerformanceMonitoring = YES;

    if ([features containsObject:CLYConsentFeedback] && !self.consentForFeedback)
        self.consentForFeedback = YES;

    if ([features containsObject:CLYConsentRemoteConfig] && !self.consentForRemoteConfig)
        self.consentForRemoteConfig = YES;

    [self sendConsents];
}


- (void)cancelConsentForAllFeatures
{
    [self cancelConsentForFeatures:[self allFeatures]];
}


- (void)cancelConsentForAllFeaturesWithoutSendingConsentsRequest
{
    [self cancelConsentForFeatures:[self allFeatures] shouldSkipSendingConsentsRequest:YES];
}


- (void)cancelConsentForFeatures:(NSArray *)features
{
    [self cancelConsentForFeatures:features shouldSkipSendingConsentsRequest:NO];
}


- (void)cancelConsentForFeatures:(NSArray *)features shouldSkipSendingConsentsRequest:(BOOL)shouldSkipSendingConsentsRequest
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

    if ([features containsObject:CLYConsentPerformanceMonitoring] && self.consentForPerformanceMonitoring)
        self.consentForPerformanceMonitoring = NO;

    if ([features containsObject:CLYConsentFeedback] && self.consentForFeedback)
        self.consentForFeedback = NO;

    if ([features containsObject:CLYConsentRemoteConfig] && self.consentForRemoteConfig)
        self.consentForRemoteConfig = NO;

    if (!shouldSkipSendingConsentsRequest)
        [self sendConsents];
}


- (void)sendConsents
{
    NSDictionary * consents =
    @{
        CLYConsentSessions: @(self.consentForSessions),
        CLYConsentEvents: @(self.consentForEvents),
        CLYConsentUserDetails: @(self.consentForUserDetails),
        CLYConsentCrashReporting: @(self.consentForCrashReporting),
        CLYConsentPushNotifications: @(self.consentForPushNotifications),
        CLYConsentLocation: @(self.consentForLocation),
        CLYConsentViewTracking: @(self.consentForViewTracking),
        CLYConsentAttribution: @(self.consentForAttribution),
        CLYConsentPerformanceMonitoring: @(self.consentForPerformanceMonitoring),
        CLYConsentFeedback: @(self.consentForFeedback),
        CLYConsentRemoteConfig: @(self.consentForRemoteConfig),
    };

    [CountlyConnectionManager.sharedInstance sendConsents:[consents cly_JSONify]];
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
        CLYConsentPerformanceMonitoring,
        CLYConsentFeedback,
        CLYConsentRemoteConfig,
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
    self.consentForPerformanceMonitoring ||
    self.consentForFeedback ||
    self.consentForRemoteConfig;
}


#pragma mark -


- (void)setConsentForSessions:(BOOL)consentForSessions
{
    _consentForSessions = consentForSessions;

    if (consentForSessions)
    {
        CLY_LOG_D(@"Consent for Session is given.");

        if (!CountlyCommon.sharedInstance.manualSessionHandling)
            [CountlyConnectionManager.sharedInstance beginSession];
    }
    else
    {
        CLY_LOG_D(@"Consent for Session is cancelled.");
    }
}


- (void)setConsentForEvents:(BOOL)consentForEvents
{
    _consentForEvents = consentForEvents;

    if (consentForEvents)
    {
        CLY_LOG_D(@"Consent for Events is given.");
    }
    else
    {
        CLY_LOG_D(@"Consent for Events is cancelled.");

        [CountlyConnectionManager.sharedInstance sendEvents];
        [CountlyPersistency.sharedInstance clearAllTimedEvents];
    }
}


- (void)setConsentForUserDetails:(BOOL)consentForUserDetails
{
    _consentForUserDetails = consentForUserDetails;

    if (consentForUserDetails)
    {
        CLY_LOG_D(@"Consent for UserDetails is given.");
        [Countly.user save];
    }
    else
    {
        CLY_LOG_D(@"Consent for UserDetails is cancelled.");

        [CountlyUserDetails.sharedInstance clearUserDetails];
    }
}


- (void)setConsentForCrashReporting:(BOOL)consentForCrashReporting
{
    _consentForCrashReporting = consentForCrashReporting;

    if (consentForCrashReporting)
    {
        CLY_LOG_D(@"Consent for CrashReporting is given.");

        [CountlyCrashReporter.sharedInstance startCrashReporting];
    }
    else
    {
        CLY_LOG_D(@"Consent for CrashReporting is cancelled.");

        [CountlyCrashReporter.sharedInstance stopCrashReporting];
    }
}


- (void)setConsentForPushNotifications:(BOOL)consentForPushNotifications
{
    _consentForPushNotifications = consentForPushNotifications;

#if (TARGET_OS_IOS || TARGET_OS_OSX)
    if (consentForPushNotifications)
    {
        CLY_LOG_D(@"Consent for PushNotifications is given.");

#ifndef COUNTLY_EXCLUDE_PUSHNOTIFICATIONS
        [CountlyPushNotifications.sharedInstance startPushNotifications];
#endif
    }
    else
    {
        CLY_LOG_D(@"Consent for PushNotifications is cancelled.");
#ifndef COUNTLY_EXCLUDE_PUSHNOTIFICATIONS
        [CountlyPushNotifications.sharedInstance stopPushNotifications];
#endif
    }
#endif
}


- (void)setConsentForLocation:(BOOL)consentForLocation
{
    _consentForLocation = consentForLocation;

    if (consentForLocation)
    {
        CLY_LOG_D(@"Consent for Location is given.");

        [CountlyLocationManager.sharedInstance sendLocationInfo];
    }
    else
    {
        CLY_LOG_D(@"Consent for Location is cancelled.");
    }
}


- (void)setConsentForViewTracking:(BOOL)consentForViewTracking
{
    _consentForViewTracking = consentForViewTracking;

#if (TARGET_OS_IOS || TARGET_OS_TV)
    if (consentForViewTracking)
    {
        CLY_LOG_D(@"Consent for ViewTracking is given.");

        [CountlyViewTracking.sharedInstance startAutoViewTracking];
    }
    else
    {
        CLY_LOG_D(@"Consent for ViewTracking is cancelled.");

        [CountlyViewTracking.sharedInstance stopAutoViewTracking];
    }
#endif
}


- (void)setConsentForAttribution:(BOOL)consentForAttribution
{
    _consentForAttribution = consentForAttribution;

    if (consentForAttribution)
    {
        CLY_LOG_D(@"Consent for Attribution is given.");

        [CountlyConnectionManager.sharedInstance sendAttribution];
    }
    else
    {
        CLY_LOG_D(@"Consent for Attribution is cancelled.");
    }
}


- (void)setConsentForPerformanceMonitoring:(BOOL)consentForPerformanceMonitoring
{
    _consentForPerformanceMonitoring = consentForPerformanceMonitoring;

#if (TARGET_OS_IOS)
    if (consentForPerformanceMonitoring)
    {
        CLY_LOG_D(@"Consent for PerformanceMonitoring is given.");
        
        [CountlyPerformanceMonitoring.sharedInstance startPerformanceMonitoring];
    }
    else
    {
        CLY_LOG_D(@"Consent for PerformanceMonitoring is cancelled.");

        [CountlyPerformanceMonitoring.sharedInstance stopPerformanceMonitoring];
    }
#endif
}

- (void)setConsentForFeedback:(BOOL)consentForFeedback
{
    _consentForFeedback = consentForFeedback;

#if (TARGET_OS_IOS)
    if (consentForFeedback)
    {
        CLY_LOG_D(@"Consent for Feedback is given.");

        [CountlyFeedbacks.sharedInstance checkForStarRatingAutoAsk];
    }
    else
    {
        CLY_LOG_D(@"Consent for Feedback is cancelled.");
    }
#endif
}

- (void)setConsentForRemoteConfig:(BOOL)consentForRemoteConfig
{
    _consentForRemoteConfig = consentForRemoteConfig;

    if (consentForRemoteConfig)
    {
        CLY_LOG_D(@"Consent for RemoteConfig is given.");

        [CountlyRemoteConfig.sharedInstance startRemoteConfig];
    }
    else
    {
        CLY_LOG_D(@"Consent for RemoteConfig is cancelled.");
    }
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
