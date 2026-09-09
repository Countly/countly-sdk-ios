//  CountlyServerConfig.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface CountlyServerConfig () {
    NSTimer *_requestTimer;
}
@property (nonatomic) BOOL trackingEnabled;
@property (nonatomic) BOOL networkingEnabled;
@property (nonatomic) BOOL crashReportingEnabled;
@property (nonatomic) BOOL automaticSessionTrackingEnabled;
@property (nonatomic) BOOL automaticViewTrackingEnabled;
@property (nonatomic) BOOL automaticCrashReportingEnabled;
@property (nonatomic) BOOL loggingEnabled;
@property (nonatomic) BOOL customEventTrackingEnabled;
@property (nonatomic) BOOL viewTrackingEnabled;
@property (nonatomic) BOOL sessionTrackingEnabled;
@property (nonatomic) BOOL enterContentZone;
@property (nonatomic) BOOL consentRequired;
@property (nonatomic) BOOL locationTracking;
@property (nonatomic) BOOL refreshContentZone;
@property (nonatomic) BOOL backoffMechanism;

@property (nonatomic) NSInteger limitKeyLength;
@property (nonatomic) NSInteger limitValueSize;
@property (nonatomic) NSInteger limitSegValues;
@property (nonatomic) NSInteger limitBreadcrumb;
@property (nonatomic) NSInteger limitTraceLine;
@property (nonatomic) NSInteger limitTraceLength;
@property (nonatomic) NSInteger sessionInterval;
@property (nonatomic) NSInteger eventQueueSize;
@property (nonatomic) NSInteger requestQueueSize;
@property (nonatomic) NSInteger contentZoneInterval;
@property (nonatomic) NSInteger dropOldRequestTime;
@property (nonatomic) NSInteger serverConfigUpdateInterval;
@property (nonatomic) NSInteger currentServerConfigUpdateInterval;

@property (nonatomic) NSInteger bomAcceptedTimeoutSeconds;
@property (nonatomic) double bomRQPercentage;
@property (nonatomic) NSInteger bomRequestAge;
@property (nonatomic) NSInteger bomDuration;

@property (nonatomic) NSInteger requestTimeoutDuration;

@property (nonatomic) NSSet<NSString *> *eventFilterSet;
@property (nonatomic) BOOL eventFilterIsWhitelist;
@property (nonatomic) NSSet<NSString *> *userPropertyFilterSet;
@property (nonatomic) BOOL userPropertyFilterIsWhitelist;
@property (nonatomic) NSInteger userPropertyCacheLimit;
@property (nonatomic) NSSet<NSString *> *segmentationFilterSet;
@property (nonatomic) BOOL segmentationFilterIsWhitelist;
@property (nonatomic) NSDictionary<NSString *, NSSet<NSString *> *> *eventSegmentationFilterMap;
@property (nonatomic) BOOL eventSegmentationFilterIsWhitelist;
@property (nonatomic) NSSet<NSString *> *journeyTriggerEvents;
@property (nonatomic) NSSet<NSString *> *journeyTriggerViews;

@property (nonatomic) NSInteger version;
@property (nonatomic) long long timestamp;
@property (nonatomic) long long lastFetchTimestamp;
@property (nonatomic) BOOL serverConfigUpdatesDisabled;

@end

NSString *const kCountlySCKeySC = @"sc";
NSString *const kTracking = @"tracking";
NSString *const kNetworking = @"networking";

// request keys
NSString *const kRTimestamp = @"t";
NSString *const kRVersion = @"v";
NSString *const kRConfig = @"c";
NSString *const kRReqQueueSize = @"rqs";
NSString *const kREventQueueSize = @"eqs";
NSString *const kRLogging = @"log";
NSString *const kRSessionUpdateInterval = @"sui";
NSString *const kRSessionTracking = @"st";
NSString *const kRViewTracking = @"vt";
NSString *const kRLocationTracking = @"lt";
NSString *const kRRefreshContentZone = @"rcz";
NSString *const kRbackoffMechanism = @"bom";

NSString *const kRLimitKeyLength = @"lkl";
NSString *const kRLimitValueSize = @"lvs";
NSString *const kRLimitSegValues = @"lsv";
NSString *const kRLimitBreadcrumb = @"lbc";
NSString *const kRLimitTraceLine = @"ltlpt";
NSString *const kRLimitTraceLength = @"ltl";
NSString *const kRCustomEventTracking = @"cet";
NSString *const kREnterContentZone = @"ecz";
NSString *const kRContentZoneInterval = @"czi";
NSString *const kRConsentRequired = @"cr";
NSString *const kRDropOldRequestTime = @"dort";
NSString *const kRCrashReporting = @"crt";
NSString *const kRAutomaticSessionTracking = @"ast";
NSString *const kRAutomaticViewTracking = @"avt";
NSString *const kRAutomaticCrashReporting = @"acr";
NSString *const kRServerConfigUpdateInterval = @"scui";
NSString *const kRBOMAcceptedTimeout = @"bom_at";
NSString *const kRBOMRQPercentage = @"bom_rqp";
NSString *const kRBOMRequestAge = @"bom_ra";
NSString *const kRBOMDuration = @"bom_d";

NSString *const kREventBlacklist = @"eb";
NSString *const kREventWhitelist = @"ew";
NSString *const kRUserPropertyBlacklist = @"upb";
NSString *const kRUserPropertyWhitelist = @"upw";
NSString *const kRUserPropertyCacheLimit = @"upcl";
NSString *const kRSegmentationBlacklist = @"sb";
NSString *const kRSegmentationWhitelist = @"sw";
NSString *const kREventSegmentationBlacklist = @"esb";
NSString *const kREventSegmentationWhitelist = @"esw";
NSString *const kRJourneyTriggerEvents = @"jte";
NSString *const kRJourneyTriggerViews = @"jtv";

// sdk log keys
NSString *const kRLogGathering = @"lg"; // a top level key, siblings of c, v and t
NSString *const kRLGEnabled = @"e";
NSString *const kRLGId = @"i";
NSString *const kRLGLevels = @"l";
NSString *const kRLGBatchSize = @"b";
// connection test key, a top level sibling of c, read from a live response and never stored
NSString *const kRConnectionTest = @"ct";

static CountlyServerConfig *s_sharedInstance = nil;
static dispatch_once_t onceToken;

@implementation CountlyServerConfig

+ (instancetype)sharedInstance
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return nil;

    dispatch_once(&onceToken, ^{
        s_sharedInstance = self.new;
    });
    return s_sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _timestamp = 0;
        _version = 0;
        _currentServerConfigUpdateInterval = 4;
        _requestTimer = nil;
        _serverConfigUpdatesDisabled = NO;
        _requestTimeoutDuration = 30;
        [self setDefaultValues];
    }
    return self;
}

- (void)resetInstance
{
    CLY_LOG_I(@"%s resetting behavior settings state and shared instance", __FUNCTION__);
    _timestamp = 0;
    _version = 0;
    _currentServerConfigUpdateInterval = 4;
    _serverConfigUpdatesDisabled = NO;
    _requestTimeoutDuration = 30;
    _lastFetchTimestamp = 0;
    if (_requestTimer)
    {
        [_requestTimer invalidate];
        _requestTimer = nil;
    }
    [self setDefaultValues];
    onceToken = 0;
    s_sharedInstance = nil;
}

- (void)retrieveServerConfigFromStorage:(CountlyConfig *)config
{
    // Seed the automatic tracking flags from the developer config: it is the lowest-precedence layer.
    // The SBS layers override them below (provided -> stored here, server in fetchServerConfig), giving
    // the precedence: server SBS > stored SBS > provided SBS > developer config. When the server is
    // silent, the resolved value equals the developer config, so behavior stays drop-in.
    _automaticSessionTrackingEnabled = !config.manualSessionHandling;
#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_TV)
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    // CLYAutoViewTracking is deprecated but still supported, so the seed has to keep honouring it
    _automaticViewTrackingEnabled = config.enableAutomaticViewTracking || [config.features containsObject:CLYAutoViewTracking];
#pragma clang diagnostic pop
#endif
    _automaticCrashReportingEnabled = [config.features containsObject:CLYCrashReporting];

    CLY_LOG_D(@"%s automatic tracking flags seeded from the developer config, automaticSessionTracking: [%@], automaticViewTracking: [%@], automaticCrashReporting: [%@]", __FUNCTION__, _automaticSessionTrackingEnabled ? @"YES" : @"NO", _automaticViewTrackingEnabled ? @"YES" : @"NO", _automaticCrashReportingEnabled ? @"YES" : @"NO");

    NSMutableDictionary *persistentBehaviorSettings = [CountlyPersistency.sharedInstance retrieveServerConfig];
    CLY_LOG_D(@"%s behavior settings read from persisted cache, keyCount: [%lu], developerSuppliedSettings: [%@]", __FUNCTION__, (unsigned long)persistentBehaviorSettings.count, config.sdkBehaviorSettings ? @"YES" : @"NO");
    if (persistentBehaviorSettings.count == 0 && config.sdkBehaviorSettings)
    {
        NSError *error = nil;
        id parsed = [NSJSONSerialization JSONObjectWithData:[config.sdkBehaviorSettings cly_dataUTF8] options:0 error:&error];

        if ([parsed isKindOfClass:[NSDictionary class]]) {
            persistentBehaviorSettings = [(NSDictionary *)parsed mutableCopy];
            CLY_LOG_D(@"%s cache was empty, falling back to developer supplied behavior settings, keyCount: [%lu]", __FUNCTION__, (unsigned long)persistentBehaviorSettings.count);
        } else {
            CLY_LOG_E(@"%s could not parse developer supplied sdkBehaviorSettings, they will be ignored, error: [%@]", __FUNCTION__, error.localizedDescription);
        }
    }

    [self populateServerConfig:persistentBehaviorSettings withConfig:config];
    [CountlyPersistency.sharedInstance storeServerConfig:persistentBehaviorSettings];
}

- (void)mergeBehaviorSettings:(NSMutableDictionary *)baseConfig
                          withConfig:(NSDictionary *)newConfig
{
    // c must exist, other top level keys, like lg, are independent of it and handled on their own
    if(!newConfig[kRConfig]) {
        CLY_LOG_W(@"%s incoming behavior settings will be ignored, config section is missing, entryCount: [%lu]", __FUNCTION__, (unsigned long)newConfig.count);
        return;
    }

    if (!newConfig[kRVersion] || !newConfig[kRTimestamp])
    {
        CLY_LOG_W(@"%s incoming behavior settings will be ignored, version or timestamp entry is missing", __FUNCTION__);
        return;
    }

    // an empty c is a valid answer, the server sends one when nothing is configured
    if(!([newConfig[kRConfig] isKindOfClass:[NSDictionary class]])){
        CLY_LOG_W(@"%s incoming behavior settings will be ignored, config section is not a dictionary", __FUNCTION__);
        return;
    }
            
    id timestamp = newConfig[kRTimestamp];
    if (timestamp) {
        baseConfig[kRTimestamp] = timestamp;
    }

    id version = newConfig[kRVersion];
    if (version) {
        baseConfig[kRVersion] = version;
    }
    
    NSDictionary *cBase = baseConfig[kRConfig] ?: NSMutableDictionary.new;
    NSDictionary *cNew = newConfig[kRConfig];

    if ([cBase isKindOfClass:[NSDictionary class]] || [cNew isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *cMerged = [cBase mutableCopy];

        [cNew enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            if (obj != nil && obj != [NSNull null]) {
                cMerged[key] = obj;
            }
        }];

        [self removeConflictingFilterKeys:cMerged newConfig:cNew];
        baseConfig[kRConfig] = cMerged;
        CLY_LOG_D(@"%s incoming behavior settings merged into the stored ones, incomingKeyCount: [%lu], mergedKeyCount: [%lu]", __FUNCTION__, (unsigned long)cNew.count, (unsigned long)cMerged.count);
    }
}

- (void)setBoolProperty:(BOOL *)property fromDictionary:(NSMutableDictionary *)dictionary key:(NSString *)key logString:(NSMutableString *)logString
{
    id value = dictionary[key];
    if (!value)
        return;

    if (CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID())
    {
        *property = [value boolValue];
        [logString appendFormat:@"%@: %@, ", key, *property ? @"YES" : @"NO"];
    }
    else
    {
        CLY_LOG_W(@"%s dropping behavior setting, a boolean was expected, key: [%@], receivedType: [%@]", __FUNCTION__, key, [value class]);
        [dictionary removeObjectForKey:key];
    }
}

/// Reads and removes the top level 'ct' flag from a live response, so it can never be cached and re-arm from storage.
/// Truthy numbers, YES, and non-empty strings other than "0" and "false" arm the test.
- (BOOL)extractConnectionTestFlag:(NSMutableDictionary *)serverConfigResponse
{
    id value = serverConfigResponse[kRConnectionTest];
    if (!value)
        return NO;

    [serverConfigResponse removeObjectForKey:kRConnectionTest];

    if ([value isKindOfClass:NSNumber.class])
        return ((NSNumber *)value).doubleValue != 0;

    if ([value isKindOfClass:NSString.class])
    {
        NSString *trimmed = [(NSString *)value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        return trimmed.length > 0 && ![trimmed isEqualToString:@"0"] && [trimmed caseInsensitiveCompare:@"false"] != NSOrderedSame;
    }

    return value != NSNull.null;
}

// lg is a top level key, a sibling of c, so a directive still applies when c is missing or unusable.
// A nil or malformed directive means the server is not asking for logs
- (void)applyLogGatheringDirective:(id)directive
{
    NSDictionary* lg = [directive isKindOfClass:NSDictionary.class] ? directive : nil;

    NSNumber* enabled = [lg[kRLGEnabled] isKindOfClass:NSNumber.class] ? lg[kRLGEnabled] : nil;
    NSNumber* batchSize = [lg[kRLGBatchSize] isKindOfClass:NSNumber.class] ? lg[kRLGBatchSize] : nil;
    NSString* levels = [lg[kRLGLevels] isKindOfClass:NSString.class] ? lg[kRLGLevels] : nil;
    NSString* gatherId = [lg[kRLGId] isKindOfClass:NSString.class] ? lg[kRLGId] : nil;

    [CountlyCommon.sharedInstance updateLogGatheringState:enabled.boolValue levels:levels batch:batchSize.integerValue lgid:gatherId];
}

- (void)setIntegerProperty:(NSInteger *)property fromDictionary:(NSMutableDictionary *)dictionary key:(NSString *)key logString:(NSMutableString *)logString
{
    [self setIntegerProperty:property fromDictionary:dictionary key:key minValue:1 logString:logString];
}

- (void)setIntegerProperty:(NSInteger *)property fromDictionary:(NSMutableDictionary *)dictionary key:(NSString *)key minValue:(NSInteger)minValue logString:(NSMutableString *)logString
{
    id value = dictionary[key];
    if (!value)
        return;

    if ([value isKindOfClass:[NSNumber class]] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID())
    {
        NSInteger intVal = [value integerValue];
        if (intVal >= minValue)
        {
            *property = intVal;
            [logString appendFormat:@"%@: %ld, ", key, (long)*property];
        }
        else
        {
            CLY_LOG_W(@"%s dropping behavior setting, value is below the accepted minimum, key: [%@], value: [%ld], minValue: [%ld]", __FUNCTION__, key, (long)intVal, (long)minValue);
            [dictionary removeObjectForKey:key];
        }
    }
    else
    {
        CLY_LOG_W(@"%s dropping behavior setting, an integer was expected, key: [%@], receivedType: [%@]", __FUNCTION__, key, [value class]);
        [dictionary removeObjectForKey:key];
    }
}

- (void)setDoubleProperty:(double *)property fromDictionary:(NSMutableDictionary *)dictionary key:(NSString *)key logString:(NSMutableString *)logString
{
    id value = dictionary[key];
    if (!value)
        return;

    if ([value isKindOfClass:[NSNumber class]] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID())
    {
        double dblVal = [value doubleValue];
        if (dblVal > 0.0 && dblVal < 1.0)
        {
            *property = dblVal;
            [logString appendFormat:@"%@: %lf, ", key, (double)*property];
        }
        else
        {
            CLY_LOG_W(@"%s dropping behavior setting, value is out of the accepted range, key: [%@], value: [%.4f], acceptedRange: [0.0 - 1.0]", __FUNCTION__, key, dblVal);
            [dictionary removeObjectForKey:key];
        }
    }
    else
    {
        CLY_LOG_W(@"%s dropping behavior setting, a double was expected, key: [%@], receivedType: [%@]", __FUNCTION__, key, [value class]);
        [dictionary removeObjectForKey:key];
    }
}

- (void)populateServerConfig:(NSMutableDictionary *)serverConfig withConfig:(CountlyConfig *)config
{
    if(config.requestTimeoutDuration <= 0) {
        config.requestTimeoutDuration = 1;
    }

    _requestTimeoutDuration = config.requestTimeoutDuration;

    if (!serverConfig[kRConfig])
    {
        CLY_LOG_D(@"%s no config section in the behavior settings, falling back to SDK defaults", __FUNCTION__);
        return;
    }

    NSMutableDictionary *dictionary;
    if ([serverConfig[kRConfig] isKindOfClass:[NSDictionary class]])
    {
        dictionary = [serverConfig[kRConfig] mutableCopy];
    }
    else
    {
        CLY_LOG_W(@"%s config section is not a dictionary, falling back to SDK defaults, receivedType: [%@]", __FUNCTION__, [serverConfig[kRConfig] class]);
        return;
    }

    if (!serverConfig[kRVersion] || !serverConfig[kRTimestamp])
    {
        CLY_LOG_W(@"%s version or timestamp is missing in the behavior settings, falling back to SDK defaults", __FUNCTION__);
        return;
    }

    _version = [serverConfig[kRVersion] integerValue];
    _timestamp = [serverConfig[kRTimestamp] longLongValue];

    CLY_LOG_D(@"%s applying behavior settings, version: [%ld], timestamp: [%lld], configKeyCount: [%lu], requestTimeoutDuration: [%ld]", __FUNCTION__, (long)_version, _timestamp, (unsigned long)dictionary.count, (long)_requestTimeoutDuration);

    NSMutableString *logString = [NSMutableString stringWithString:@"Server Config: "];

    // Known keys set — used to remove unknown keys after validation
    NSMutableSet *knownKeys = [NSMutableSet setWithArray:@[
        kTracking,
        kNetworking,
        kRSessionUpdateInterval,
        kRReqQueueSize,
        kREventQueueSize,
        kRCrashReporting,
        kRAutomaticSessionTracking,
        kRAutomaticViewTracking,
        kRAutomaticCrashReporting,
        kRSessionTracking,
        kRLogging,
        kRLimitKeyLength,
        kRLimitValueSize,
        kRLimitSegValues,
        kRLimitBreadcrumb,
        kRLimitTraceLine,
        kRLimitTraceLength,
        kRCustomEventTracking,
        kRViewTracking,
        kREnterContentZone,
        kRContentZoneInterval,
        kRConsentRequired,
        kRDropOldRequestTime,
        kRServerConfigUpdateInterval,
        kRLocationTracking,
        kRRefreshContentZone,
        kRbackoffMechanism,
        kRBOMAcceptedTimeout,
        kRBOMRQPercentage,
        kRBOMRequestAge,
        kRBOMDuration,
        kRUserPropertyCacheLimit,
        kREventBlacklist,
        kREventWhitelist,
        kRUserPropertyBlacklist,
        kRUserPropertyWhitelist,
        kRSegmentationBlacklist,
        kRSegmentationWhitelist,
        kREventSegmentationBlacklist,
        kREventSegmentationWhitelist,
        kRJourneyTriggerEvents,
        kRJourneyTriggerViews
    ]];

    // Remove unknown keys
    for (NSString *key in dictionary.allKeys)
    {
        if (![knownKeys containsObject:key])
        {
            CLY_LOG_D(@"%s unknown behavior setting key will be dropped, key: [%@]", __FUNCTION__, key);
            [dictionary removeObjectForKey:key];
        }
    }

    [self setBoolProperty:&_trackingEnabled fromDictionary:dictionary key:kTracking logString:logString];
    [self setBoolProperty:&_networkingEnabled fromDictionary:dictionary key:kNetworking logString:logString];
    [self setIntegerProperty:&_sessionInterval fromDictionary:dictionary key:kRSessionUpdateInterval logString:logString];
    [self setIntegerProperty:&_requestQueueSize fromDictionary:dictionary key:kRReqQueueSize logString:logString];
    [self setIntegerProperty:&_eventQueueSize fromDictionary:dictionary key:kREventQueueSize logString:logString];
    [self setBoolProperty:&_crashReportingEnabled fromDictionary:dictionary key:kRCrashReporting logString:logString];
    [self setBoolProperty:&_automaticSessionTrackingEnabled fromDictionary:dictionary key:kRAutomaticSessionTracking logString:logString];
    [self setBoolProperty:&_automaticViewTrackingEnabled fromDictionary:dictionary key:kRAutomaticViewTracking logString:logString];
    [self setBoolProperty:&_automaticCrashReportingEnabled fromDictionary:dictionary key:kRAutomaticCrashReporting logString:logString];
    [self setBoolProperty:&_sessionTrackingEnabled fromDictionary:dictionary key:kRSessionTracking logString:logString];
    [self setBoolProperty:&_loggingEnabled fromDictionary:dictionary key:kRLogging logString:logString];
    [self setIntegerProperty:&_limitKeyLength fromDictionary:dictionary key:kRLimitKeyLength logString:logString];
    [self setIntegerProperty:&_limitValueSize fromDictionary:dictionary key:kRLimitValueSize logString:logString];
    [self setIntegerProperty:&_limitSegValues fromDictionary:dictionary key:kRLimitSegValues logString:logString];
    [self setIntegerProperty:&_limitBreadcrumb fromDictionary:dictionary key:kRLimitBreadcrumb logString:logString];
    [self setIntegerProperty:&_limitTraceLine fromDictionary:dictionary key:kRLimitTraceLine logString:logString];
    [self setIntegerProperty:&_limitTraceLength fromDictionary:dictionary key:kRLimitTraceLength logString:logString];
    [self setBoolProperty:&_customEventTrackingEnabled fromDictionary:dictionary key:kRCustomEventTracking logString:logString];
    [self setBoolProperty:&_viewTrackingEnabled fromDictionary:dictionary key:kRViewTracking logString:logString];
    [self setBoolProperty:&_enterContentZone fromDictionary:dictionary key:kREnterContentZone logString:logString];
    [self setIntegerProperty:&_contentZoneInterval fromDictionary:dictionary key:kRContentZoneInterval minValue:16 logString:logString];
    [self setBoolProperty:&_consentRequired fromDictionary:dictionary key:kRConsentRequired logString:logString];
    [self setIntegerProperty:&_dropOldRequestTime fromDictionary:dictionary key:kRDropOldRequestTime minValue:0 logString:logString];
    [self setIntegerProperty:&_serverConfigUpdateInterval fromDictionary:dictionary key:kRServerConfigUpdateInterval logString:logString];
    [self setBoolProperty:&_locationTracking fromDictionary:dictionary key:kRLocationTracking logString:logString];
    [self setBoolProperty:&_refreshContentZone fromDictionary:dictionary key:kRRefreshContentZone logString:logString];
    [self setBoolProperty:&_backoffMechanism fromDictionary:dictionary key:kRbackoffMechanism logString:logString];
    [self setIntegerProperty:&_bomAcceptedTimeoutSeconds fromDictionary:dictionary key:kRBOMAcceptedTimeout logString:logString];
    [self setDoubleProperty:&_bomRQPercentage fromDictionary:dictionary key:kRBOMRQPercentage logString:logString];
    [self setIntegerProperty:&_bomRequestAge fromDictionary:dictionary key:kRBOMRequestAge logString:logString];
    [self setIntegerProperty:&_bomDuration fromDictionary:dictionary key:kRBOMDuration logString:logString];
    [self setIntegerProperty:&_userPropertyCacheLimit fromDictionary:dictionary key:kRUserPropertyCacheLimit logString:logString];

    [self updateListingFilters:dictionary logString:logString];

    // Update the config dictionary with cleaned values
    serverConfig[kRConfig] = dictionary;

    if(![logString isEqualToString: @"Server Config: "]){
        // means new config gotten, if that is the case notify SDK
        [self notifySdkConfigChange: config];
    }

    CLY_LOG_D(@"%s behavior settings applied, version: [%ld], timestamp: [%lld], appliedValues: [%@]", __FUNCTION__, (long)_version, _timestamp, logString);

    CLY_LOG_D(@"%s resolved behavior settings, tracking: [%@], networking: [%@], crashReporting: [%@], sessionTracking: [%@], viewTracking: [%@], automaticSessionTracking: [%@], automaticViewTracking: [%@], automaticCrashReporting: [%@], customEventTracking: [%@], locationTracking: [%@], refreshContentZone: [%@], enterContentZone: [%@], consentRequired: [%@], backoffMechanism: [%@], loggingForcedByServer: [%@], keyLength: [%ld], valueSize: [%ld], segValues: [%ld], breadcrumb: [%ld], traceLine: [%ld], traceLength: [%ld], sessionInterval: [%ld], eventQueueSize: [%ld], requestQueueSize: [%ld], contentZoneInterval: [%ld], dropOldRequestTime: [%ld], updateIntervalHours: [%ld], userPropertyCacheLimit: [%ld], backoffAcceptedTimeoutSeconds: [%ld], backoffRQPercentage: [%.4f], backoffRequestAgeHours: [%ld], backoffDurationSeconds: [%ld]", __FUNCTION__,
              _trackingEnabled ? @"YES" : @"NO", _networkingEnabled ? @"YES" : @"NO", _crashReportingEnabled ? @"YES" : @"NO", _sessionTrackingEnabled ? @"YES" : @"NO", _viewTrackingEnabled ? @"YES" : @"NO", _automaticSessionTrackingEnabled ? @"YES" : @"NO", _automaticViewTrackingEnabled ? @"YES" : @"NO", _automaticCrashReportingEnabled ? @"YES" : @"NO", _customEventTrackingEnabled ? @"YES" : @"NO", _locationTracking ? @"YES" : @"NO", _refreshContentZone ? @"YES" : @"NO", _enterContentZone ? @"YES" : @"NO", _consentRequired ? @"YES" : @"NO", _backoffMechanism ? @"YES" : @"NO", _loggingEnabled ? @"YES" : @"NO",
              (long)_limitKeyLength, (long)_limitValueSize, (long)_limitSegValues, (long)_limitBreadcrumb, (long)_limitTraceLine, (long)_limitTraceLength, (long)_sessionInterval, (long)_eventQueueSize, (long)_requestQueueSize, (long)_contentZoneInterval, (long)_dropOldRequestTime, (long)_serverConfigUpdateInterval, (long)_userPropertyCacheLimit,
              (long)_bomAcceptedTimeoutSeconds, _bomRQPercentage, (long)_bomRequestAge, (long)_bomDuration);
}

- (void)notifySdkConfigChange:(CountlyConfig *)config
{
    config.enableDebug = _loggingEnabled || config.enableDebug;
    CountlyCommon.sharedInstance.enableDebug = config.enableDebug;

    // Limits could be moved to another function, but letting them stay here serves us a monopolized view of notify
    if (config.maxKeyLength != kCountlyMaxKeyLength)
    {
        [config.sdkInternalLimits setMaxKeyLength:config.maxKeyLength];
    }

    if (config.maxValueLength != kCountlyMaxValueSize)
    {
        [config.sdkInternalLimits setMaxValueSize:config.maxValueLength];
    }

    if (config.maxSegmentationValues != kCountlyMaxSegmentationValues)
    {
        [config.sdkInternalLimits setMaxSegmentationValues:config.maxSegmentationValues];
    }

    if (config.crashLogLimit != kCountlyMaxBreadcrumbCount)
    {
        [config.sdkInternalLimits setMaxBreadcrumbCount:config.crashLogLimit];
    }

    [config.sdkInternalLimits setMaxKeyLength:_limitKeyLength ?: config.sdkInternalLimits.getMaxKeyLength];
    [config.sdkInternalLimits setMaxValueSize:_limitValueSize ?: config.sdkInternalLimits.getMaxValueSize];
    [config.sdkInternalLimits setMaxSegmentationValues:_limitSegValues ?: config.sdkInternalLimits.getMaxSegmentationValues];
    [config.sdkInternalLimits setMaxBreadcrumbCount:_limitBreadcrumb ?: config.sdkInternalLimits.getMaxBreadcrumbCount];
    [config.sdkInternalLimits setMaxStackTraceLineLength:_limitTraceLength ?: config.sdkInternalLimits.getMaxStackTraceLineLength];
    [config.sdkInternalLimits setMaxStackTraceLinesPerThread:_limitTraceLine ?: config.sdkInternalLimits.getMaxStackTraceLinesPerThread];

    CountlyCommon.sharedInstance.maxKeyLength = config.sdkInternalLimits.getMaxKeyLength;
    CountlyCommon.sharedInstance.maxValueLength = config.sdkInternalLimits.getMaxValueSize;
    CountlyCommon.sharedInstance.maxValueLengthPicture = config.sdkInternalLimits.getMaxValueSizePicture;
    CountlyCommon.sharedInstance.maxSegmentationValues = config.sdkInternalLimits.getMaxSegmentationValues;

    config.eventSendThreshold = _eventQueueSize ?: config.eventSendThreshold;
    config.requestDropAgeHours = _dropOldRequestTime ?: config.requestDropAgeHours;
    config.storedRequestsLimit = _requestQueueSize ?: config.storedRequestsLimit;
    CountlyPersistency.sharedInstance.eventSendThreshold = config.eventSendThreshold;
    CountlyPersistency.sharedInstance.requestDropAgeHours = config.requestDropAgeHours;
    CountlyPersistency.sharedInstance.storedRequestsLimit = MAX(1, config.storedRequestsLimit);

    config.updateSessionPeriod = _sessionInterval ?: config.updateSessionPeriod;
    _sessionInterval = config.updateSessionPeriod;

    CLY_LOG_D(@"%s effective limits and queue settings applied, maxKeyLength: [%lu], maxValueLength: [%lu], maxValueLengthPicture: [%lu], maxSegmentationValues: [%lu], maxBreadcrumbCount: [%lu], eventSendThreshold: [%lu], requestDropAgeHours: [%lu], storedRequestsLimit: [%lu], updateSessionPeriod: [%.1f]", __FUNCTION__,
              (unsigned long)CountlyCommon.sharedInstance.maxKeyLength, (unsigned long)CountlyCommon.sharedInstance.maxValueLength, (unsigned long)CountlyCommon.sharedInstance.maxValueLengthPicture, (unsigned long)CountlyCommon.sharedInstance.maxSegmentationValues, (unsigned long)config.sdkInternalLimits.getMaxBreadcrumbCount,
              (unsigned long)config.eventSendThreshold, (unsigned long)config.requestDropAgeHours, (unsigned long)config.storedRequestsLimit, config.updateSessionPeriod);

    BOOL consentDidChange = !config.requiresConsent && _consentRequired;
    config.requiresConsent = _consentRequired ?: config.requiresConsent;
    CountlyConsentManager.sharedInstance.requiresConsent = config.requiresConsent;
    if(consentDidChange && CountlyCommon.sharedInstance.hasFinishedInit){
        CLY_LOG_D(@"%s consent requirement was turned on by behavior settings, consents will be resent", __FUNCTION__);
        [CountlyConsentManager.sharedInstance sendConsents];
        if (!CountlyConsentManager.sharedInstance.consentForLocation)
        {
            [CountlyConnectionManager.sharedInstance sendLocationInfo];
        }
    }

#if (TARGET_OS_IOS)
    [config.content setZoneTimerInterval:_contentZoneInterval ?: config.content.getZoneTimerInterval];
    if (config.content.getZoneTimerInterval)
    {
        CountlyContentBuilderInternal.sharedInstance.zoneTimerInterval = config.content.getZoneTimerInterval;
    }
    // clearContentState, not exitContentZone: this runs on every config apply, and exitContentZone
    // would pull displayed content off screen.
    if (!_enterContentZone)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [CountlyContentBuilderInternal.sharedInstance clearContentState];
        });
    }
    else
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [CountlyContentBuilderInternal.sharedInstance clearContentState];
            [CountlyContentBuilderInternal.sharedInstance enterContentZone:@[]];
        });
    }
#endif
    CountlyCrashReporter.sharedInstance.crashLogLimit = config.sdkInternalLimits.getMaxBreadcrumbCount;

    if (_serverConfigUpdateInterval && _serverConfigUpdateInterval != _currentServerConfigUpdateInterval && _requestTimer)
    {
        CLY_LOG_D(@"%s behavior settings refresh timer will be rescheduled, intervalHours: [%ld]", __FUNCTION__, (long)_serverConfigUpdateInterval);
        _currentServerConfigUpdateInterval = _serverConfigUpdateInterval;
        [_requestTimer invalidate];
        _requestTimer = nil;
        _requestTimer = [NSTimer timerWithTimeInterval:_currentServerConfigUpdateInterval * 60 * 60 target:self selector:@selector(fetchServerConfigTimer:) userInfo:config repeats:YES];
        [NSRunLoop.mainRunLoop addTimer:_requestTimer forMode:NSRunLoopCommonModes];
    }

    if (!_locationTracking && !CountlyLocationManager.sharedInstance.isLocationInfoDisabled)
    {
        CLY_LOG_D(@"%s location tracking is disabled by behavior settings, location info will be cleared", __FUNCTION__);
        [CountlyLocationManager.sharedInstance disableLocation];
        [CountlyConnectionManager.sharedInstance sendLocationInfo];
    }

    if(_backoffMechanism && config.disableBackoffMechanism){
        CLY_LOG_D(@"%s backoff mechanism is enabled by behavior settings but disabled in the developer config, it will stay off", __FUNCTION__);
        _backoffMechanism = NO;
    }

    // Skipped while init is still running: 'shouldUsePLCrashReporter' is not assigned until later in
    // 'startWithConfig', so installing the crash handler here would take the default handler path and then
    // block PLCrashReporter from ever starting. 'startWithConfig' calls this itself once init is complete.
    if (CountlyCommon.sharedInstance.hasFinishedInit)
    {
        [self applyAutomaticTrackingState];
    }
}

// Brings automatic view tracking and automatic crash reporting in line with the resolved 'avt' and 'acr'
// values. Safe to call repeatedly: the view tracking calls act only on an actual state change, and
// 'startCrashReporting' is idempotent and re-checks 'acr' and consent itself.
- (void)applyAutomaticTrackingState
{
// The platform guard matches where automatic view tracking is actually implemented, which is narrower
// than what the header declares
#if (TARGET_OS_IOS || TARGET_OS_TV)
    BOOL shouldAutoTrackViews = _viewTrackingEnabled && _automaticViewTrackingEnabled;
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL isActive = CountlyViewTrackingInternal.sharedInstance.isAutoViewTrackingActive;
        if (shouldAutoTrackViews && !isActive)
        {
            CLY_LOG_D(@"[CountlyServerConfig] applyAutomaticTrackingState, behavior settings enable automatic view tracking, it will be started");
            [CountlyViewTrackingInternal.sharedInstance startAutoViewTracking];
        }
        else if (!shouldAutoTrackViews && isActive)
        {
            CLY_LOG_D(@"[CountlyServerConfig] applyAutomaticTrackingState, behavior settings disable automatic view tracking, it will be stopped");
            [CountlyViewTrackingInternal.sharedInstance stopAutoViewTracking];
        }
    });
#endif

    // A runtime 'acr' = false does not uninstall the handler; it no-ops through its own runtime check
    // instead, so a later 'acr' = true does not have to reinstall it.
    if (_crashReportingEnabled && _automaticCrashReportingEnabled)
    {
        [CountlyCrashReporter.sharedInstance startCrashReporting];
    }
    else
    {
        CLY_LOG_D(@"%s automatic crash reporting is disabled by behavior settings, the crash handler will not be started, crashReporting: [%@], automaticCrashReporting: [%@]", __FUNCTION__, _crashReportingEnabled ? @"YES" : @"NO", _automaticCrashReportingEnabled ? @"YES" : @"NO");
    }
}

- (void)fetchServerConfigTimer:(NSTimer *)timer
{
    CountlyConfig *config = (CountlyConfig *)timer.userInfo; // Retrieve CountlyConfig from userInfo
    CLY_LOG_D(@"%s behavior settings refresh timer fired, configAvailable: [%@]", __FUNCTION__, config ? @"YES" : @"NO");
    if (config)
    {
        [self fetchServerConfig:config];
    }
}

- (void)fetchServerConfigIfTimeIsUp
{
    if (_serverConfigUpdatesDisabled) {
        CLY_LOG_D(@"%s periodic behavior settings check skipped, updates are disabled", __FUNCTION__);
        return;
    }

    if (_lastFetchTimestamp)
    {
        long long currentTime = NSDate.date.timeIntervalSince1970 * 1000;
        long long timePassed = currentTime - _lastFetchTimestamp;

        if (timePassed > _currentServerConfigUpdateInterval * 60 * 60 * 1000)
        {
            CLY_LOG_D(@"%s behavior settings refresh interval elapsed, a fetch will be triggered, timePassedMs: [%lld], intervalHours: [%ld]", __FUNCTION__, timePassed, (long)_currentServerConfigUpdateInterval);
            [self fetchServerConfig:CountlyConfig.new];
        }
    }
}

- (void)fetchServerConfig:(CountlyConfig *)config
{
    CLY_LOG_D(@"%s starting a behavior settings fetch, currentVersion: [%ld], updateIntervalHours: [%ld]", __FUNCTION__, (long)_version, (long)_currentServerConfigUpdateInterval);

    if (_serverConfigUpdatesDisabled) {
        CLY_LOG_D(@"%s fetch aborted, behavior settings updates are disabled", __FUNCTION__);
        [CountlyCommon.sharedInstance decideLogGatheringOffIfUndecided:@"behavior settings updates are disabled, no directive can ever arrive"];
        return;
    }

    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
    {
        CLY_LOG_D(@"%s fetch aborted, sdk is in temporary device ID mode", __FUNCTION__);
        [CountlyCommon.sharedInstance decideLogGatheringOffIfUndecided:@"temporary device ID mode, no server response this run"];
        return;
    }

    _lastFetchTimestamp = NSDate.date.timeIntervalSince1970 * 1000;

    if (!_requestTimer)
    {
        _requestTimer = [NSTimer timerWithTimeInterval:_currentServerConfigUpdateInterval * 60 * 60 target:self selector:@selector(fetchServerConfigTimer:) userInfo:config repeats:YES];
        [NSRunLoop.mainRunLoop addTimer:_requestTimer forMode:NSRunLoopCommonModes];
    }

    NSDate *fetchStart = NSDate.date;
    id handler = ^(NSData *data, NSURLResponse *response, NSError *error) {
        if (self != s_sharedInstance)
        {
            // the SDK was halted while this fetch was in flight, its answer must not decide anything for the next run
            CLY_LOG_D(@"%s, response arrived after halt, ignoring", __FUNCTION__);
            return;
        }

        // wall clock of the whole fetch, the connection test reports it as its 'sc' row
        long long fetchLatencyMs = (long long)([NSDate.date timeIntervalSinceDate:fetchStart] * 1000);
        NSMutableDictionary *serverConfigResponse = nil;
        if (!error)
        {
            id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            if ([parsed isKindOfClass:NSDictionary.class])
                serverConfigResponse = [parsed mutableCopy];
            CLY_LOG_D(@"[CountlyServerConfig] fetchServerConfig response, behavior settings received from network, statusCode: [%ld], responseKeyCount: [%lu], parsed: [%@]", (long)((NSHTTPURLResponse *)response).statusCode, (unsigned long)serverConfigResponse.count, error ? @"NO" : @"YES");
        }

        // read only here, from a live response, and removed before anything below sees the response so it is never cached
        BOOL connectionTestArmed = [self extractConnectionTestFlag:serverConfigResponse];

        if (!error)
        {
            if (((NSHTTPURLResponse *)response).statusCode != 200)
            {
                NSMutableDictionary *serverConfig = serverConfigResponse.mutableCopy;
                serverConfig[NSLocalizedDescriptionKey] = @"Server configuration general API error";
                error = [NSError errorWithDomain:kCountlyErrorDomain code:CLYErrorServerConfigGeneralAPIError userInfo:serverConfig];
            }
        }

        if (error)
        {
            CLY_LOG_D(@"[CountlyServerConfig] fetchServerConfig response, behavior settings fetch failed, statusCode: [%ld], error: [%@]", (long)((NSHTTPURLResponse *)response).statusCode, error.localizedDescription);
        }

        if (serverConfigResponse[kRConfig] != nil)
        {
            NSMutableDictionary *persistentBehaviorSettings = [CountlyPersistency.sharedInstance retrieveServerConfig];
            [self mergeBehaviorSettings:persistentBehaviorSettings withConfig:serverConfigResponse];
            [self populateServerConfig:persistentBehaviorSettings withConfig:config];
            [CountlyPersistency.sharedInstance storeServerConfig:persistentBehaviorSettings];
            CLY_LOG_D(@"[CountlyServerConfig] fetchServerConfig response, fetched behavior settings were merged and persisted, storedKeyCount: [%lu]", (unsigned long)persistentBehaviorSettings.count);
        }
        else
        {
            CLY_LOG_D(@"[CountlyServerConfig] fetchServerConfig response, no config section in the response, previously stored behavior settings will be kept");
        }

        if (error)
        {
            // a failed fetch decides against gathering only while nothing has been decided yet, a
            // running gather survives a transient failure of the periodic refetch
            [CountlyCommon.sharedInstance decideLogGatheringOffIfUndecided:@"server config fetch failed"];
            return;
        }

        // only a fresh response decides log gathering, never a stored config. A live response without a
        // usable directive decides against it
        [self applyLogGatheringDirective:serverConfigResponse[kRLogGathering]];

        if (connectionTestArmed)
            [CountlyConnectionTest.sharedInstance startBatteryWithServerConfigLatency:fetchLatencyMs];
    };
    // Set default values
    NSURLSessionTask *task = [CountlyCommon.sharedInstance.ImmediateURLSession dataTaskWithRequest:[self serverConfigRequest] completionHandler:handler];
    // IMMEDIATE REQUEST to find them better in search
    [task resume];
}

- (NSURLRequest *)serverConfigRequest
{
    NSString *queryString = [CountlyConnectionManager.sharedInstance queryEssentials];

    queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyQSKeyMethod, kCountlySCKeySC];

    queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyAppVersionKey, CountlyDeviceInfo.appVersion];

    queryString = [CountlyConnectionManager.sharedInstance appendChecksum:queryString];

    NSMutableString *URL = CountlyConnectionManager.sharedInstance.host.mutableCopy;
    [URL appendString:kCountlyEndpointO];
    [URL appendString:kCountlyEndpointSDK];

    if (queryString.length > kCountlyGETRequestMaxLength || CountlyConnectionManager.sharedInstance.alwaysUsePOST)
    {
        CLY_LOG_D(@"%s behavior settings request prepared as POST, queryLength: [%lu]", __FUNCTION__, (unsigned long)queryString.length);
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:URL]];
        request.HTTPMethod = @"POST";
        request.HTTPBody = [queryString cly_dataUTF8];
        return request.copy;
    }
    else
    {
        CLY_LOG_D(@"%s behavior settings request prepared as GET, queryLength: [%lu]", __FUNCTION__, (unsigned long)queryString.length);
        [URL appendFormat:@"?%@", queryString];
        NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:URL]];
        return request;
    }
}

- (void)setDefaultValues {
    _trackingEnabled = YES;
    _networkingEnabled = YES;
    _crashReportingEnabled = YES;
    _automaticSessionTrackingEnabled = YES;
    _automaticViewTrackingEnabled = NO;
    _automaticCrashReportingEnabled = NO;
    _customEventTrackingEnabled = YES;
    _enterContentZone = NO;
    _locationTracking = YES;
    _viewTrackingEnabled = YES;
    _sessionTrackingEnabled = YES;
    _loggingEnabled = NO;
    _refreshContentZone = YES;
    _backoffMechanism = YES;
    _bomAcceptedTimeoutSeconds = 10;
    _bomRQPercentage = 0.5;
    _bomRequestAge = 24;
    _bomDuration = 60;

    _eventQueueSize = 0;
    _requestQueueSize = 0;
    _sessionInterval = 0;
    _limitKeyLength = 0;
    _limitValueSize = 0;
    _limitSegValues = 0;
    _limitBreadcrumb = 0;
    _limitTraceLine = 0;
    _limitTraceLength = 0;
    _consentRequired = NO;
    _dropOldRequestTime = 0;
    _contentZoneInterval = 0;

    _eventFilterSet = [NSSet set];
    _eventFilterIsWhitelist = NO;
    _userPropertyFilterSet = [NSSet set];
    _userPropertyFilterIsWhitelist = NO;
    _userPropertyCacheLimit = 100;
    _segmentationFilterSet = [NSSet set];
    _segmentationFilterIsWhitelist = NO;
    _eventSegmentationFilterMap = @{};
    _eventSegmentationFilterIsWhitelist = NO;
    _journeyTriggerEvents = [NSSet set];
    _journeyTriggerViews = [NSSet set];

    CLY_LOG_D(@"%s behavior settings reset to built in SDK defaults", __FUNCTION__);
}

- (void)disableSDKBehaviourSettings {
    CLY_LOG_I(@"%s behavior settings updates are being disabled", __FUNCTION__);
    _serverConfigUpdatesDisabled = YES;
}

- (BOOL)trackingEnabled
{
    return _trackingEnabled;
}

- (BOOL)networkingEnabled
{
    return _networkingEnabled;
}

- (NSInteger)sessionInterval
{
    return _sessionInterval;
}

- (NSInteger)requestQueueSize
{
    return _requestQueueSize;
}

- (NSInteger)eventQueueSize
{
    return _eventQueueSize;
}

- (BOOL)crashReportingEnabled
{
    return _crashReportingEnabled;
}

- (BOOL)automaticSessionTrackingEnabled
{
    return _automaticSessionTrackingEnabled;
}

- (BOOL)automaticViewTrackingEnabled
{
    return _automaticViewTrackingEnabled;
}

- (BOOL)automaticCrashReportingEnabled
{
    return _automaticCrashReportingEnabled;
}

- (BOOL)sessionTrackingEnabled
{
    return _sessionTrackingEnabled;
}
- (BOOL)loggingEnabled
{
    return _loggingEnabled;
}

- (NSInteger)limitKeyLength
{
    return _limitKeyLength;
}

- (NSInteger)limitValueSize
{
    return _limitValueSize;
}

- (NSInteger)limitSegValues
{
    return _limitSegValues;
}

- (NSInteger)limitBreadcrumb
{
    return _limitBreadcrumb;
}

- (NSInteger)limitTraceLine
{
    return _limitTraceLine;
}

- (NSInteger)limitTraceLength
{
    return _limitTraceLength;
}

- (BOOL)customEventTrackingEnabled
{
    return _customEventTrackingEnabled;
}

- (BOOL)viewTrackingEnabled
{
    return _viewTrackingEnabled;
}

- (BOOL)enterContentZone
{
    return _enterContentZone;
}

- (NSInteger)contentZoneInterval
{
    return _contentZoneInterval;
}

- (BOOL)consentRequired
{
    return _consentRequired;
}

- (NSInteger)dropOldRequestTime
{
    return _dropOldRequestTime;
}

- (BOOL)locationTrackingEnabled
{
    return _locationTracking;
}

- (BOOL)refreshContentZoneEnabled
{
    return _refreshContentZone;
}

- (BOOL)backoffMechanism
{
    return _backoffMechanism;
}

- (NSInteger)bomAcceptedTimeoutSeconds
{
    return _bomAcceptedTimeoutSeconds;
}

- (double)bomRQPercentage
{
    return _bomRQPercentage;
}

- (NSInteger)bomRequestAge
{
    return _bomRequestAge;
}

- (NSInteger)bomDuration
{
    return _bomDuration;
}

- (NSInteger)requestTimeoutDuration
{
    return _requestTimeoutDuration;
}

- (NSInteger)userPropertyCacheLimit
{
    return _userPropertyCacheLimit;
}

#pragma mark - Listing Filters

- (void)removeConflictingFilterKeys:(NSMutableDictionary *)mergedConfig newConfig:(NSDictionary *)newConfig
{
    // Remove conflicting filter keys per category.
    // Within each category, if new config provides a blacklist, remove stored whitelist (and vice versa).
    NSArray *filterPairs = @[
        @[kREventBlacklist, kREventWhitelist],
        @[kRSegmentationBlacklist, kRSegmentationWhitelist],
        @[kREventSegmentationBlacklist, kREventSegmentationWhitelist],
        @[kRUserPropertyBlacklist, kRUserPropertyWhitelist],
    ];

    for (NSArray *pair in filterPairs)
    {
        NSString *blacklistKey = pair[0];
        NSString *whitelistKey = pair[1];

        // Only consider valid filter values (arrays/dicts) for conflict resolution
        id blacklistVal = newConfig[blacklistKey];
        id whitelistVal = newConfig[whitelistKey];
        BOOL hasValidBlacklist = [blacklistVal isKindOfClass:NSArray.class] || [blacklistVal isKindOfClass:NSDictionary.class];
        BOOL hasValidWhitelist = [whitelistVal isKindOfClass:NSArray.class] || [whitelistVal isKindOfClass:NSDictionary.class];

        if (hasValidBlacklist)
        {
            [mergedConfig removeObjectForKey:whitelistKey];
        }
        if (hasValidWhitelist)
        {
            [mergedConfig removeObjectForKey:blacklistKey];
        }
    }
}

- (void)updateListingFilters:(NSMutableDictionary *)dictionary logString:(NSMutableString *)logString
{
    // Event filter (eb/ew) - blacklist takes precedence
    NSArray *eb = dictionary[kREventBlacklist];
    NSArray *ew = dictionary[kREventWhitelist];
    if ([eb isKindOfClass:NSArray.class]) {
        _eventFilterSet = [NSSet setWithArray:eb];
        _eventFilterIsWhitelist = NO;
        [logString appendFormat:@"%@: %@, ", kREventBlacklist, eb];
        if (ew)
            [dictionary removeObjectForKey:kREventWhitelist]; // blacklist takes precedence
    } else if ([ew isKindOfClass:NSArray.class]) {
        _eventFilterSet = [NSSet setWithArray:ew];
        _eventFilterIsWhitelist = YES;
        [logString appendFormat:@"%@: %@, ", kREventWhitelist, ew];
    } else {
        if (eb)
            [dictionary removeObjectForKey:kREventBlacklist];
        if (ew)
            [dictionary removeObjectForKey:kREventWhitelist];
    }

    // User property filter (upb/upw) - blacklist takes precedence
    NSArray *upb = dictionary[kRUserPropertyBlacklist];
    NSArray *upw = dictionary[kRUserPropertyWhitelist];
    if ([upb isKindOfClass:NSArray.class]) {
        _userPropertyFilterSet = [NSSet setWithArray:upb];
        _userPropertyFilterIsWhitelist = NO;
        [logString appendFormat:@"%@: %@, ", kRUserPropertyBlacklist, upb];
        if (upw)
            [dictionary removeObjectForKey:kRUserPropertyWhitelist];
    } else if ([upw isKindOfClass:NSArray.class]) {
        _userPropertyFilterSet = [NSSet setWithArray:upw];
        _userPropertyFilterIsWhitelist = YES;
        [logString appendFormat:@"%@: %@, ", kRUserPropertyWhitelist, upw];
    } else {
        if (upb)
            [dictionary removeObjectForKey:kRUserPropertyBlacklist];
        if (upw)
            [dictionary removeObjectForKey:kRUserPropertyWhitelist];
    }

    // Segmentation filter (sb/sw) - blacklist takes precedence
    NSArray *sb = dictionary[kRSegmentationBlacklist];
    NSArray *sw = dictionary[kRSegmentationWhitelist];
    if ([sb isKindOfClass:NSArray.class]) {
        _segmentationFilterSet = [NSSet setWithArray:sb];
        _segmentationFilterIsWhitelist = NO;
        [logString appendFormat:@"%@: %@, ", kRSegmentationBlacklist, sb];
        if (sw)
            [dictionary removeObjectForKey:kRSegmentationWhitelist];
    } else if ([sw isKindOfClass:NSArray.class]) {
        _segmentationFilterSet = [NSSet setWithArray:sw];
        _segmentationFilterIsWhitelist = YES;
        [logString appendFormat:@"%@: %@, ", kRSegmentationWhitelist, sw];
    } else {
        if (sb)
            [dictionary removeObjectForKey:kRSegmentationBlacklist];
        if (sw)
            [dictionary removeObjectForKey:kRSegmentationWhitelist];
    }

    // Event segmentation filter (esb/esw) - blacklist takes precedence
    NSDictionary *esb = dictionary[kREventSegmentationBlacklist];
    NSDictionary *esw = dictionary[kREventSegmentationWhitelist];
    if ([esb isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *map = NSMutableDictionary.new;
        [esb enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSArray *obj, BOOL *stop) {
            if ([obj isKindOfClass:NSArray.class]) {
                map[key] = [NSSet setWithArray:obj];
            }
        }];
        _eventSegmentationFilterMap = map.copy;
        _eventSegmentationFilterIsWhitelist = NO;
        [logString appendFormat:@"%@: %@, ", kREventSegmentationBlacklist, esb];
        if (esw)
            [dictionary removeObjectForKey:kREventSegmentationWhitelist];
    } else if ([esw isKindOfClass:NSDictionary.class]) {
        NSMutableDictionary *map = NSMutableDictionary.new;
        [esw enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSArray *obj, BOOL *stop) {
            if ([obj isKindOfClass:NSArray.class]) {
                map[key] = [NSSet setWithArray:obj];
            }
        }];
        _eventSegmentationFilterMap = map.copy;
        _eventSegmentationFilterIsWhitelist = YES;
        [logString appendFormat:@"%@: %@, ", kREventSegmentationWhitelist, esw];
    } else {
        if (esb)
            [dictionary removeObjectForKey:kREventSegmentationBlacklist];
        if (esw)
            [dictionary removeObjectForKey:kREventSegmentationWhitelist];
    }

    // Journey trigger events (jte)
    NSArray *jte = dictionary[kRJourneyTriggerEvents];
    if ([jte isKindOfClass:NSArray.class]) {
        _journeyTriggerEvents = [NSSet setWithArray:jte];
        [logString appendFormat:@"%@: %@, ", kRJourneyTriggerEvents, jte];
    } else {
        if (jte)
            [dictionary removeObjectForKey:kRJourneyTriggerEvents];
    }

    // Journey trigger views (jtv)
    NSArray *jtv = dictionary[kRJourneyTriggerViews];
    if ([jtv isKindOfClass:NSArray.class]) {
        _journeyTriggerViews = [NSSet setWithArray:jtv];
        [logString appendFormat:@"%@: %@, ", kRJourneyTriggerViews, jtv];
    } else {
        if (jtv)
            [dictionary removeObjectForKey:kRJourneyTriggerViews];
    }

    CLY_LOG_D(@"%s resolved listing filters, eventFilterCount: [%lu], eventFilterIsWhitelist: [%@], userPropertyFilterCount: [%lu], userPropertyFilterIsWhitelist: [%@], segmentationFilterCount: [%lu], segmentationFilterIsWhitelist: [%@], eventSegmentationFilteredEventCount: [%lu], eventSegmentationFilterIsWhitelist: [%@], journeyTriggerEventCount: [%lu], journeyTriggerViewCount: [%lu]", __FUNCTION__, (unsigned long)_eventFilterSet.count, _eventFilterIsWhitelist ? @"YES" : @"NO", (unsigned long)_userPropertyFilterSet.count, _userPropertyFilterIsWhitelist ? @"YES" : @"NO", (unsigned long)_segmentationFilterSet.count, _segmentationFilterIsWhitelist ? @"YES" : @"NO", (unsigned long)_eventSegmentationFilterMap.count, _eventSegmentationFilterIsWhitelist ? @"YES" : @"NO", (unsigned long)_journeyTriggerEvents.count, (unsigned long)_journeyTriggerViews.count);
}

- (BOOL)shouldRecordEvent:(NSString *)eventKey
{
    if (_eventFilterSet.count == 0) return YES;
    return _eventFilterIsWhitelist == [_eventFilterSet containsObject:eventKey];
}

- (BOOL)shouldRecordUserProperty:(NSString *)propertyKey
{
    if (_userPropertyFilterSet.count == 0) return YES;
    return _userPropertyFilterIsWhitelist == [_userPropertyFilterSet containsObject:propertyKey];
}

- (NSDictionary *)filterSegmentation:(NSDictionary *)segmentation eventKey:(NSString *)eventKey
{
    if (!segmentation) {
        return segmentation;
    }

    BOOL hasGlobalFilter = _segmentationFilterSet.count > 0;
    NSSet *eventFilter = _eventSegmentationFilterMap[eventKey];
    BOOL hasEventFilter = eventFilter.count > 0;

    if (!hasGlobalFilter && !hasEventFilter) {
        return segmentation;
    }

    NSMutableDictionary *result = [segmentation mutableCopy];
    for (NSString *key in segmentation.allKeys) {
        if (hasGlobalFilter && _segmentationFilterIsWhitelist != [_segmentationFilterSet containsObject:key]) {
            CLY_LOG_V(@"%s dropping segmentation key by the global segmentation filter, key: [%@], filterIsWhitelist: [%@]", __FUNCTION__, key, _segmentationFilterIsWhitelist ? @"YES" : @"NO");
            [result removeObjectForKey:key];
        }
        else if (hasEventFilter && _eventSegmentationFilterIsWhitelist != [eventFilter containsObject:key]) {
            CLY_LOG_V(@"%s dropping segmentation key by the event level segmentation filter, key: [%@], eventKey: [%@]", __FUNCTION__, key, eventKey);
            [result removeObjectForKey:key];
        }
    }

    return result.copy;
}

- (BOOL)isJourneyTriggerEvent:(NSString *)eventKey
{
    return [_journeyTriggerEvents containsObject:eventKey];
}

- (BOOL)isJourneyTriggerView:(NSString *)viewName
{
    return [_journeyTriggerViews containsObject:viewName];
}

@end
