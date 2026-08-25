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
CLYConsent const CLYConsentContent              = @"content";
CLYConsent const CLYConsentMetrics              = @"metrics";


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
@synthesize consentForContent = _consentForContent;
@synthesize consentForMetrics = _consentForMetrics;

#pragma mark -

static CountlyConsentManager* s_sharedInstance = nil;
static dispatch_once_t onceToken;
+ (instancetype)sharedInstance
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return nil;

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

- (void)resetInstance {
    CLY_LOG_I(@"%s resetting consent manager instance, consent for all features will be cancelled", __FUNCTION__);
    [self cancelConsentForAllFeatures];
    onceToken = 0;
    s_sharedInstance = nil;
}

#pragma mark -

- (void)giveAllConsents
{
    NSArray* allFeatures = [self allFeatures];
    [self giveConsentForFeatures:allFeatures];
}


- (void)giveConsentForFeatures:(NSArray *)features
{
    CLY_LOG_I(@"%s giving consent for features, feature count: [%lu], features: [%@]", __FUNCTION__, (unsigned long)features.count, features);

    if (!self.requiresConsent)
    {
        CLY_LOG_V(@"%s requiresConsent is not enabled, giving consent for features will be ignored", __FUNCTION__);
        return;
    }

    if (!features.count)
    {
        CLY_LOG_E(@"%s feature list is empty, there is no consent to give", __FUNCTION__);
        return;
    }

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
    
    if ([features containsObject:CLYConsentContent] && !self.consentForContent)
        self.consentForContent = YES;
    
    if ([features containsObject:CLYConsentMetrics] && !self.consentForMetrics)
        self.consentForMetrics = YES;

    [self sendConsents];
}


- (void)cancelConsentForAllFeatures
{
    NSArray* allFeatures = [self allFeatures];
    [self cancelConsentForFeatures:allFeatures];
}


- (void)cancelConsentForAllFeaturesWithoutSendingConsentsRequest
{
    NSArray* allFeatures = [self allFeatures];
    [self cancelConsentForFeatures:allFeatures shouldSkipSendingConsentsRequest:YES];
}


- (void)cancelConsentForFeatures:(NSArray *)features
{
    [self cancelConsentForFeatures:features shouldSkipSendingConsentsRequest:NO];
}


- (void)cancelConsentForFeatures:(NSArray *)features shouldSkipSendingConsentsRequest:(BOOL)shouldSkipSendingConsentsRequest
{
    CLY_LOG_I(@"%s cancelling consent for features, feature count: [%lu], features: [%@], skipSendingConsentsRequest: [%@]", __FUNCTION__, (unsigned long)features.count, features, shouldSkipSendingConsentsRequest ? @"YES" : @"NO");

    if (!self.requiresConsent)
    {
        CLY_LOG_V(@"%s requiresConsent is not enabled, cancelling consent for features will be ignored", __FUNCTION__);
        return;
    }

    if ([features containsObject:CLYConsentSessions] && self.consentForSessions)
    {
        [CountlyConnectionManager.sharedInstance endSession];
        self.consentForSessions = NO;
    }

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
    
    if ([features containsObject:CLYConsentContent] && self.consentForContent)
        self.consentForContent = NO;

    if ([features containsObject:CLYConsentMetrics] && self.consentForMetrics)
        self.consentForMetrics = NO;

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
        CLYConsentContent: @(self.consentForContent),
        CLYConsentMetrics: @(self.consentForMetrics),
    };

    CLY_LOG_D(@"%s consents state will be sent to the server, feature count: [%lu]", __FUNCTION__, (unsigned long)consents.count);

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
        CLYConsentContent,
        CLYConsentMetrics,
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
    self.consentForRemoteConfig ||
    self.consentForContent ||
    self.consentForMetrics;
}


#pragma mark -


- (void)setConsentForSessions:(BOOL)consentForSessions
{
    _consentForSessions = consentForSessions;

    if (consentForSessions)
    {
        CLY_LOG_D(@"%s consent granted, feature: [%@], begin session will be requested unless manual session handling is enabled", __FUNCTION__, CLYConsentSessions);

        if (CountlyServerConfig.sharedInstance.automaticSessionTrackingEnabled)
            [CountlyConnectionManager.sharedInstance beginSession];
    }
    else
    {
        CLY_LOG_D(@"%s consent cancelled, feature: [%@], session tracking will no longer be performed", __FUNCTION__, CLYConsentSessions);
    }
}


- (void)setConsentForEvents:(BOOL)consentForEvents
{
    _consentForEvents = consentForEvents;

    if (consentForEvents)
    {
        CLY_LOG_D(@"%s consent granted, feature: [%@], custom events will be recorded", __FUNCTION__, CLYConsentEvents);
    }
    else
    {
        CLY_LOG_D(@"%s consent cancelled, feature: [%@], recorded events will be sent and timed events will be cleared", __FUNCTION__, CLYConsentEvents);

        [CountlyConnectionManager.sharedInstance sendEventsWithSaveIfNeeded];
        [CountlyPersistency.sharedInstance clearAllTimedEvents];
    }
}


- (void)setConsentForUserDetails:(BOOL)consentForUserDetails
{
    _consentForUserDetails = consentForUserDetails;

    if (consentForUserDetails)
    {
        CLY_LOG_D(@"%s consent granted, feature: [%@], orientation will be recorded and user details will be saved", __FUNCTION__, CLYConsentUserDetails);
        [CountlyCommon.sharedInstance recordOrientation];
        [CountlyUserDetails.sharedInstance save];
    }
    else
    {
        CLY_LOG_D(@"%s consent cancelled, feature: [%@], stored user details will be cleared", __FUNCTION__, CLYConsentUserDetails);

        [CountlyUserDetails.sharedInstance clearUserDetails];
    }
}


- (void)setConsentForCrashReporting:(BOOL)consentForCrashReporting
{
    _consentForCrashReporting = consentForCrashReporting;

    if (consentForCrashReporting)
    {
        CLY_LOG_D(@"%s consent granted, feature: [%@], crash reporting will be started", __FUNCTION__, CLYConsentCrashReporting);

        [CountlyCrashReporter.sharedInstance startCrashReporting];
    }
    else
    {
        CLY_LOG_D(@"%s consent cancelled, feature: [%@], crash reporting will be stopped", __FUNCTION__, CLYConsentCrashReporting);

        [CountlyCrashReporter.sharedInstance stopCrashReporting];
    }
}


- (void)setConsentForPushNotifications:(BOOL)consentForPushNotifications
{
    _consentForPushNotifications = consentForPushNotifications;

#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_OSX)
    if (consentForPushNotifications)
    {
        CLY_LOG_D(@"%s consent granted, feature: [%@], push notifications will be started", __FUNCTION__, CLYConsentPushNotifications);

#ifndef COUNTLY_EXCLUDE_PUSHNOTIFICATIONS
        [CountlyPushNotifications.sharedInstance startPushNotifications];
#endif
    }
    else
    {
        CLY_LOG_D(@"%s consent cancelled, feature: [%@], push notifications will be stopped", __FUNCTION__, CLYConsentPushNotifications);
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
        CLY_LOG_D(@"%s consent granted, feature: [%@], location info will be sent", __FUNCTION__, CLYConsentLocation);

        [CountlyLocationManager.sharedInstance sendLocationInfo];
    }
    else
    {
        CLY_LOG_D(@"%s consent cancelled, feature: [%@], location info will be cleared on the server", __FUNCTION__, CLYConsentLocation);
        
        [CountlyConnectionManager.sharedInstance sendLocationInfo];
    }
}


- (void)setConsentForViewTracking:(BOOL)consentForViewTracking
{
    _consentForViewTracking = consentForViewTracking;

// Automatic view tracking is only implemented for iOS and tvOS, so the guard must not include
// visionOS: the methods below would be declared but have no definition there
#if (TARGET_OS_IOS || TARGET_OS_TV)
    if (consentForViewTracking)
    {
        CLY_LOG_D(@"%s consent granted, feature: [%@], automatic view tracking will be started", __FUNCTION__, CLYConsentViewTracking);

        [CountlyViewTrackingInternal.sharedInstance startAutoViewTracking];
    }
    else
    {
        CLY_LOG_D(@"%s consent cancelled, feature: [%@], automatic view tracking will be stopped", __FUNCTION__, CLYConsentViewTracking);

        [CountlyViewTrackingInternal.sharedInstance stopAutoViewTracking];
    }
#endif
}


- (void)setConsentForAttribution:(BOOL)consentForAttribution
{
    _consentForAttribution = consentForAttribution;

    if (consentForAttribution)
    {
        CLY_LOG_D(@"%s consent granted, feature: [%@], attribution will be sent", __FUNCTION__, CLYConsentAttribution);

        [CountlyConnectionManager.sharedInstance sendAttribution];
    }
    else
    {
        CLY_LOG_D(@"%s consent cancelled, feature: [%@], attribution will no longer be sent", __FUNCTION__, CLYConsentAttribution);
    }
}


- (void)setConsentForPerformanceMonitoring:(BOOL)consentForPerformanceMonitoring
{
    _consentForPerformanceMonitoring = consentForPerformanceMonitoring;

#if (TARGET_OS_IOS || TARGET_OS_VISION)
    if (consentForPerformanceMonitoring)
    {
        CLY_LOG_D(@"%s consent granted, feature: [%@], performance monitoring will be started", __FUNCTION__, CLYConsentPerformanceMonitoring);
        
        [CountlyPerformanceMonitoring.sharedInstance startPerformanceMonitoring];
    }
    else
    {
        CLY_LOG_D(@"%s consent cancelled, feature: [%@], performance monitoring will be stopped", __FUNCTION__, CLYConsentPerformanceMonitoring);

        [CountlyPerformanceMonitoring.sharedInstance stopPerformanceMonitoring];
    }
#endif
}

- (void)setConsentForFeedback:(BOOL)consentForFeedback
{
    _consentForFeedback = consentForFeedback;

#if (TARGET_OS_IOS || TARGET_OS_VISION)
    if (consentForFeedback)
    {
        CLY_LOG_D(@"%s consent granted, feature: [%@], star rating auto ask will be checked", __FUNCTION__, CLYConsentFeedback);

        [CountlyFeedbacksInternal.sharedInstance checkForStarRatingAutoAsk];
    }
    else
    {
        CLY_LOG_D(@"%s consent cancelled, feature: [%@], feedback widgets will no longer be shown", __FUNCTION__, CLYConsentFeedback);
    }
#endif
}

- (void)setConsentForRemoteConfig:(BOOL)consentForRemoteConfig
{
    _consentForRemoteConfig = consentForRemoteConfig;

    if (consentForRemoteConfig)
    {
        CLY_LOG_D(@"%s consent granted, feature: [%@], automatic remote config download will be triggered", __FUNCTION__, CLYConsentRemoteConfig);

        [CountlyRemoteConfigInternal.sharedInstance downloadRemoteConfigAutomatically];
    }
    else
    {
        CLY_LOG_D(@"%s consent cancelled, feature: [%@], remote config values will no longer be downloaded", __FUNCTION__, CLYConsentRemoteConfig);
    }
}

- (void)setConsentForMetrics:(BOOL)consentForMetrics
{
    _consentForMetrics = consentForMetrics;

    if (consentForMetrics)
    {
        CLY_LOG_D(@"%s consent granted, feature: [%@], metrics will be included in requests", __FUNCTION__, CLYConsentMetrics);
    }
    else
    {
        CLY_LOG_D(@"%s consent cancelled, feature: [%@], metrics will be omitted from requests", __FUNCTION__, CLYConsentMetrics);
    }
}

- (void)setConsentForContent:(BOOL)consentForContent
{
    _consentForContent = consentForContent;
    
    if (consentForContent)
    {
        CLY_LOG_D(@"%s consent granted, feature: [%@], content zone can be entered", __FUNCTION__, CLYConsentContent);
    }
    else
    {
        CLY_LOG_D(@"%s consent cancelled, feature: [%@], content zone will be exited", __FUNCTION__, CLYConsentContent);
#if (TARGET_OS_IOS || TARGET_OS_VISION)
        [CountlyContentBuilderInternal.sharedInstance exitContentZone];
#endif
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

- (BOOL)consentForContent
{
    if (!self.requiresConsent)
        return YES;
    
    return _consentForContent;
}

- (BOOL)consentForMetrics
{
    if (!self.requiresConsent)
        return YES;
    
    return _consentForMetrics;
}

@end
