//  CountlyServerConfig.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface CountlyServerConfig () {
    NSTimer *_requestTimer;
    // the developer's config from start, every later fetch applies the settings on top of it
    CountlyConfig *_startConfig;
    NSNumber *_lastAppliedAutomaticViewTracking;
    // the developer's values from start, before any behavior setting was applied, see rememberDeveloperValues:
    NSDictionary *_developerValues;
    // what notifySdkConfigChange: last wrote into the start config, see restoreDeveloperValuesInto:
    NSDictionary *_writtenValues;
    // the keys of the applied settings: a setting they carry wins over the developer's value, also when it is NO or 0,
    // and a key that disappears from them is noticed
    NSSet *_appliedSettingKeys;
    // the consent requirement whose consent state was last sent, nil until start has handled consent
    NSNumber *_handledConsentRequirement;
    // the developer's disableBackoffMechanism from start, which no behavior setting turns back on
    BOOL _isBackoffDisabledByDeveloper;
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

@property (atomic) NSSet<NSString *> *eventFilterSet;
@property (nonatomic) BOOL eventFilterIsWhitelist;
@property (atomic) NSSet<NSString *> *userPropertyFilterSet;
@property (nonatomic) BOOL userPropertyFilterIsWhitelist;
@property (nonatomic) NSInteger userPropertyCacheLimit;
@property (atomic) NSSet<NSString *> *segmentationFilterSet;
@property (nonatomic) BOOL segmentationFilterIsWhitelist;
@property (atomic) NSDictionary<NSString *, NSSet<NSString *> *> *eventSegmentationFilterMap;
@property (nonatomic) BOOL eventSegmentationFilterIsWhitelist;
// atomic: replaced by a settings response on its own thread while events and views read them on theirs
@property (atomic) NSSet<NSString *> *journeyTriggerEvents;
@property (atomic) NSSet<NSString *> *journeyTriggerViews;

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

// the behavior settings refresh interval in hours when the server does not set one
static const NSInteger kCountlyDefaultServerConfigUpdateInterval = 4;

/// Whether a behavior settings version or timestamp can be read as a number.
static BOOL CountlyIsBehaviorSettingsNumber(id value)
{
    return [value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class];
}

/// A copy of a behavior setting value without the nulls inside its lists and dictionaries, which the standard user
/// defaults can not store and every reader would have to step around.
static id CountlyBehaviorSettingWithoutNulls(id value)
{
    if ([value isKindOfClass:NSArray.class])
    {
        NSMutableArray* cleaned = NSMutableArray.new;
        for (id element in (NSArray *)value)
        {
            if (element != NSNull.null)
                [cleaned addObject:CountlyBehaviorSettingWithoutNulls(element)];
        }
        return cleaned;
    }

    if ([value isKindOfClass:NSDictionary.class])
    {
        NSMutableDictionary* cleaned = NSMutableDictionary.new;
        [(NSDictionary *)value enumerateKeysAndObjectsUsingBlock:^(id key, id element, BOOL* stop) {
            if (element != NSNull.null)
                cleaned[key] = CountlyBehaviorSettingWithoutNulls(element);
        }];
        return cleaned;
    }

    return value;
}
#if (TARGET_OS_IOS)
// the content zone timer interval in seconds when neither the server nor the developer sets one, as CountlyContentBuilderInternal starts with
static const NSUInteger kCountlyDefaultZoneTimerInterval = 30;
#endif

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
        _currentServerConfigUpdateInterval = kCountlyDefaultServerConfigUpdateInterval;
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
    _currentServerConfigUpdateInterval = kCountlyDefaultServerConfigUpdateInterval;
    _serverConfigUpdatesDisabled = NO;
    _requestTimeoutDuration = 30;
    _lastFetchTimestamp = 0;
    [self restoreDeveloperValuesInto:_startConfig];
    _startConfig = nil;
    _lastAppliedAutomaticViewTracking = nil;
    _developerValues = nil;
    _writtenValues = nil;
    _appliedSettingKeys = nil;
    _isBackoffDisabledByDeveloper = NO;
    // an answer still in flight applies to this dropped instance, which must not send consents into the next run
    @synchronized (self) {
        _handledConsentRequirement = nil;
    }
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
    _startConfig = config;
    [self rememberDeveloperValues:config];
    _isBackoffDisabledByDeveloper = config.disableBackoffMechanism;

    // Seed the automatic tracking flags from the developer config: it is the lowest-precedence layer.
    // The SBS layers override them below (provided -> stored here, server in fetchServerConfig), giving
    // the precedence: server SBS > stored SBS > provided SBS > developer config. When the server is
    // silent, the resolved value equals the developer config, so behavior stays drop-in.
    _automaticSessionTrackingEnabled = !config.manualSessionHandling;
#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_TV)
    _automaticViewTrackingEnabled = config.enableAutomaticViewTracking;
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
            // checked like a server answer, so a null in them can not crash every start
            persistentBehaviorSettings = NSMutableDictionary.new;
            [self replaceBehaviorSettings:persistentBehaviorSettings withConfig:parsed];
            CLY_LOG_D(@"%s cache was empty, falling back to developer supplied behavior settings, keyCount: [%lu]", __FUNCTION__, (unsigned long)persistentBehaviorSettings.count);
        } else {
            CLY_LOG_E(@"%s could not parse developer supplied sdkBehaviorSettings, they will be ignored, error: [%@]", __FUNCTION__, error.localizedDescription);
        }
    }

    [self populateServerConfig:persistentBehaviorSettings withConfig:config];
    [CountlyPersistency.sharedInstance storeServerConfig:persistentBehaviorSettings];
}

/// Remembers the developer's values from start, before any behavior setting is applied. A setting the server stops
/// sending goes back to them, see revertSettingsMissingFrom: and notifySdkConfigChange:. The developer config itself is
/// not a reliable source later, because notifySdkConfigChange: writes the resolved values into it.
- (void)rememberDeveloperValues:(CountlyConfig *)config
{
    NSMutableDictionary *values = [self notifiedValuesOf:config].mutableCopy;
    values[kRAutomaticSessionTracking] = @(!config.manualSessionHandling);
#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_TV)
    values[kRAutomaticViewTracking] = @(config.enableAutomaticViewTracking);
#endif
    values[kRAutomaticCrashReporting] = @([config.features containsObject:CLYCrashReporting]);
    _developerValues = values.copy;
}

/// The values of a configuration that notifySdkConfigChange: writes, by the key of the behavior setting that decides each.
- (NSDictionary *)notifiedValuesOf:(CountlyConfig *)config
{
    NSMutableDictionary *values = NSMutableDictionary.new;
    values[kRConsentRequired] = @(config.requiresConsent);
    values[kRLogging] = @(config.enableDebug);
    values[kREventQueueSize] = @(config.eventSendThreshold);
    values[kRReqQueueSize] = @(config.storedRequestsLimit);
    values[kRDropOldRequestTime] = @(config.requestDropAgeHours);
    values[kRSessionUpdateInterval] = @(config.updateSessionPeriod);
    values[kRLimitKeyLength] = @(config.sdkInternalLimits.getMaxKeyLength);
    values[kRLimitValueSize] = @(config.sdkInternalLimits.getMaxValueSize);
    values[kRLimitSegValues] = @(config.sdkInternalLimits.getMaxSegmentationValues);
    values[kRLimitBreadcrumb] = @(config.sdkInternalLimits.getMaxBreadcrumbCount);
    values[kRLimitTraceLength] = @(config.sdkInternalLimits.getMaxStackTraceLineLength);
    values[kRLimitTraceLine] = @(config.sdkInternalLimits.getMaxStackTraceLinesPerThread);
#if (TARGET_OS_IOS)
    values[kRContentZoneInterval] = @(config.content.getZoneTimerInterval);
#endif
    return values;
}

/// The developer's value of a setting from start, or the given current value when none was remembered
- (NSNumber *)developerValueForKey:(NSString *)key orCurrent:(NSNumber *)current
{
    return _developerValues[key] ?: current;
}

/// Puts the developer's values from start back into the configuration the SDK was started with, where
/// notifySdkConfigChange: wrote a value that is still there. It writes the resolved values into that configuration, and its
/// internal limits and content parts are shared by every configuration in the process, so without this the next start
/// would remember the halted run's behavior settings as the developer's values. A value that changed since was set by the
/// app, on this configuration or on another one sharing those parts, and stays.
- (void)restoreDeveloperValuesInto:(CountlyConfig *)config
{
    if (!config || !_developerValues || !_writtenValues)
        return;

    NSDictionary *current = [self notifiedValuesOf:config];
    NSMutableDictionary *restored = NSMutableDictionary.new;
    [_writtenValues enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSNumber *written, BOOL *stop) {
        if ([current[key] isEqual:written])
            restored[key] = self->_developerValues[key];
    }];
    [self writeValues:restored into:config];

    CLY_LOG_D(@"%s the developer's values from start are put back into the start configuration, restoredKeys: [%@], keptKeys: [%lu]", __FUNCTION__, [restored.allKeys componentsJoinedByString:@","], (unsigned long)(_writtenValues.count - restored.count));
}

/// Writes the values given by behavior setting key into a configuration, leaving out the keys the dictionary does not carry.
- (void)writeValues:(NSDictionary *)values into:(CountlyConfig *)config
{
    if (values[kRLogging])
        config.enableDebug = [values[kRLogging] boolValue];
    if (values[kRConsentRequired])
        config.requiresConsent = [values[kRConsentRequired] boolValue];
    if (values[kREventQueueSize])
        config.eventSendThreshold = [values[kREventQueueSize] unsignedIntegerValue];
    if (values[kRReqQueueSize])
        config.storedRequestsLimit = [values[kRReqQueueSize] unsignedIntegerValue];
    if (values[kRDropOldRequestTime])
        config.requestDropAgeHours = [values[kRDropOldRequestTime] unsignedIntegerValue];
    if (values[kRSessionUpdateInterval])
        config.updateSessionPeriod = [values[kRSessionUpdateInterval] doubleValue];
    if (values[kRLimitKeyLength])
        [config.sdkInternalLimits setMaxKeyLength:[values[kRLimitKeyLength] unsignedIntegerValue]];
    if (values[kRLimitValueSize])
        [config.sdkInternalLimits setMaxValueSize:[values[kRLimitValueSize] unsignedIntegerValue]];
    if (values[kRLimitSegValues])
        [config.sdkInternalLimits setMaxSegmentationValues:[values[kRLimitSegValues] unsignedIntegerValue]];
    if (values[kRLimitBreadcrumb])
        [config.sdkInternalLimits setMaxBreadcrumbCount:[values[kRLimitBreadcrumb] unsignedIntegerValue]];
    if (values[kRLimitTraceLength])
        [config.sdkInternalLimits setMaxStackTraceLineLength:[values[kRLimitTraceLength] unsignedIntegerValue]];
    if (values[kRLimitTraceLine])
        [config.sdkInternalLimits setMaxStackTraceLinesPerThread:[values[kRLimitTraceLine] unsignedIntegerValue]];
#if (TARGET_OS_IOS)
    if (values[kRContentZoneInterval])
        [config.content restoreZoneTimerInterval:[values[kRContentZoneInterval] unsignedIntegerValue]];
#endif
}

/// Replaces the stored behavior settings with a valid answer as a whole, so a setting the server no longer sends is
/// gone from them. An answer without a 'c' dictionary, a version or a timestamp changes nothing, and an empty 'c' is
/// valid. A value in an unacceptable format is dropped by populateServerConfig:withConfig: before anything is applied
/// or stored, so that setting is treated as not sent.
- (void)replaceBehaviorSettings:(NSMutableDictionary *)baseConfig
                     withConfig:(NSDictionary *)newConfig
{
    // c must exist, other top level keys, like lg, are independent of it and handled on their own
    if(!newConfig[kRConfig]) {
        CLY_LOG_W(@"%s incoming behavior settings will be ignored, config section is missing, entryCount: [%lu]", __FUNCTION__, (unsigned long)newConfig.count);
        return;
    }

    if (!CountlyIsBehaviorSettingsNumber(newConfig[kRVersion]) || !CountlyIsBehaviorSettingsNumber(newConfig[kRTimestamp]))
    {
        CLY_LOG_W(@"%s incoming behavior settings will be ignored, version or timestamp entry is missing or not a number", __FUNCTION__);
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

    NSDictionary *cNew = newConfig[kRConfig];
    NSMutableDictionary *cReplacement = NSMutableDictionary.new;
    [cNew enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if (obj != nil && obj != [NSNull null]) {
            cReplacement[key] = CountlyBehaviorSettingWithoutNulls(obj);
        }
    }];

    baseConfig[kRConfig] = cReplacement;
    CLY_LOG_D(@"%s incoming behavior settings replaced the stored ones, keyCount: [%lu]", __FUNCTION__, (unsigned long)cReplacement.count);
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

    if (!CountlyIsBehaviorSettingsNumber(serverConfig[kRVersion]) || !CountlyIsBehaviorSettingsNumber(serverConfig[kRTimestamp]))
    {
        CLY_LOG_W(@"%s version or timestamp is missing in the behavior settings or not a number, falling back to SDK defaults", __FUNCTION__);
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

    [self revertSettingsMissingFrom:dictionary];

    // Update the config dictionary with cleaned values
    serverConfig[kRConfig] = dictionary;

    NSSet *settingKeys = [NSSet setWithArray:dictionary.allKeys];
    BOOL settingRemoved = _appliedSettingKeys != nil && ![_appliedSettingKeys isSubsetOfSet:settingKeys];
    _appliedSettingKeys = settingKeys;

    if(![logString isEqualToString: @"Server Config: "] || settingRemoved){
        // means new config gotten, or a setting was removed, if that is the case notify SDK
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
    // A setting the server does not send falls back to the developer's value from start, not to the config's current
    // value: this method writes the resolved values into the config, so that would keep the last server value. A
    // setting the server sends wins, also when it is NO or 0.
    config.enableDebug = [_appliedSettingKeys containsObject:kRLogging] ? _loggingEnabled : [self developerValueForKey:kRLogging orCurrent:@(config.enableDebug)].boolValue;
    CountlyCommon.sharedInstance.enableDebug = config.enableDebug;

    // Limits could be moved to another function, but letting them stay here serves us a monopolized view of notify
    [config.sdkInternalLimits setMaxKeyLength:_limitKeyLength ?: [self developerValueForKey:kRLimitKeyLength orCurrent:@(config.sdkInternalLimits.getMaxKeyLength)].unsignedIntegerValue];
    [config.sdkInternalLimits setMaxValueSize:_limitValueSize ?: [self developerValueForKey:kRLimitValueSize orCurrent:@(config.sdkInternalLimits.getMaxValueSize)].unsignedIntegerValue];
    [config.sdkInternalLimits setMaxSegmentationValues:_limitSegValues ?: [self developerValueForKey:kRLimitSegValues orCurrent:@(config.sdkInternalLimits.getMaxSegmentationValues)].unsignedIntegerValue];
    [config.sdkInternalLimits setMaxBreadcrumbCount:_limitBreadcrumb ?: [self developerValueForKey:kRLimitBreadcrumb orCurrent:@(config.sdkInternalLimits.getMaxBreadcrumbCount)].unsignedIntegerValue];
    [config.sdkInternalLimits setMaxStackTraceLineLength:_limitTraceLength ?: [self developerValueForKey:kRLimitTraceLength orCurrent:@(config.sdkInternalLimits.getMaxStackTraceLineLength)].unsignedIntegerValue];
    [config.sdkInternalLimits setMaxStackTraceLinesPerThread:_limitTraceLine ?: [self developerValueForKey:kRLimitTraceLine orCurrent:@(config.sdkInternalLimits.getMaxStackTraceLinesPerThread)].unsignedIntegerValue];

    CountlyCommon.sharedInstance.maxKeyLength = config.sdkInternalLimits.getMaxKeyLength;
    CountlyCommon.sharedInstance.maxValueLength = config.sdkInternalLimits.getMaxValueSize;
    CountlyCommon.sharedInstance.maxValueLengthPicture = config.sdkInternalLimits.getMaxValueSizePicture;
    CountlyCommon.sharedInstance.maxSegmentationValues = config.sdkInternalLimits.getMaxSegmentationValues;

    config.eventSendThreshold = _eventQueueSize ?: [self developerValueForKey:kREventQueueSize orCurrent:@(config.eventSendThreshold)].unsignedIntegerValue;
    config.requestDropAgeHours = [_appliedSettingKeys containsObject:kRDropOldRequestTime] ? (NSUInteger)_dropOldRequestTime : [self developerValueForKey:kRDropOldRequestTime orCurrent:@(config.requestDropAgeHours)].unsignedIntegerValue;
    config.storedRequestsLimit = _requestQueueSize ?: [self developerValueForKey:kRReqQueueSize orCurrent:@(config.storedRequestsLimit)].unsignedIntegerValue;
    CountlyPersistency.sharedInstance.eventSendThreshold = config.eventSendThreshold;
    CountlyPersistency.sharedInstance.requestDropAgeHours = config.requestDropAgeHours;
    CountlyPersistency.sharedInstance.storedRequestsLimit = MAX(1, config.storedRequestsLimit);

    config.updateSessionPeriod = _sessionInterval ?: [self developerValueForKey:kRSessionUpdateInterval orCurrent:@(config.updateSessionPeriod)].doubleValue;
    _sessionInterval = config.updateSessionPeriod;

    CLY_LOG_D(@"%s effective limits and queue settings applied, maxKeyLength: [%lu], maxValueLength: [%lu], maxValueLengthPicture: [%lu], maxSegmentationValues: [%lu], maxBreadcrumbCount: [%lu], eventSendThreshold: [%lu], requestDropAgeHours: [%lu], storedRequestsLimit: [%lu], updateSessionPeriod: [%.1f]", __FUNCTION__,
              (unsigned long)CountlyCommon.sharedInstance.maxKeyLength, (unsigned long)CountlyCommon.sharedInstance.maxValueLength, (unsigned long)CountlyCommon.sharedInstance.maxValueLengthPicture, (unsigned long)CountlyCommon.sharedInstance.maxSegmentationValues, (unsigned long)config.sdkInternalLimits.getMaxBreadcrumbCount,
              (unsigned long)config.eventSendThreshold, (unsigned long)config.requestDropAgeHours, (unsigned long)config.storedRequestsLimit, config.updateSessionPeriod);

    // The server can require consent but never lift a requirement the developer set, since the consents the app gave and
    // withdrew are not recorded while consent is not required
    BOOL developerRequiresConsent = [self developerValueForKey:kRConsentRequired orCurrent:@(config.requiresConsent)].boolValue;
    BOOL requiresConsent = developerRequiresConsent || ([_appliedSettingKeys containsObject:kRConsentRequired] && _consentRequired);
    config.requiresConsent = requiresConsent;
    CountlyConsentManager.sharedInstance.requiresConsent = config.requiresConsent;
    [self applyConsentRequirement];

#if (TARGET_OS_IOS)
    // setZoneTimerInterval: ignores values the developer can not set, so a removed 'czi' with no developer interval
    // would leave the previous server interval in config.content; the content builder takes the resolved value
    NSUInteger zoneTimerInterval = _contentZoneInterval ?: [self developerValueForKey:kRContentZoneInterval orCurrent:@(config.content.getZoneTimerInterval)].unsignedIntegerValue;
    [config.content setZoneTimerInterval:zoneTimerInterval];
    CountlyContentBuilderInternal.sharedInstance.zoneTimerInterval = zoneTimerInterval ?: kCountlyDefaultZoneTimerInterval;
#endif
#if (TARGET_OS_IOS || TARGET_OS_VISION)
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

    NSInteger updateInterval = _serverConfigUpdateInterval ?: kCountlyDefaultServerConfigUpdateInterval;
    if (updateInterval != _currentServerConfigUpdateInterval && _requestTimer)
    {
        CLY_LOG_D(@"%s behavior settings refresh timer will be rescheduled, intervalHours: [%ld]", __FUNCTION__, (long)updateInterval);
        _currentServerConfigUpdateInterval = updateInterval;
        [_requestTimer invalidate];
        _requestTimer = nil;
        _requestTimer = [NSTimer timerWithTimeInterval:_currentServerConfigUpdateInterval * 60 * 60 target:self selector:@selector(fetchServerConfigTimer:) userInfo:config repeats:YES];
        [NSRunLoop.mainRunLoop addTimer:_requestTimer forMode:NSRunLoopCommonModes];
    }

    if (CountlyCommon.sharedInstance.hasFinishedInit)
    {
        [self applyLocationTrackingState];
    }

    // Skipped while init is still running: 'shouldUsePLCrashReporter' is not assigned until later in
    // 'startWithConfig', so installing the crash handler here would take the default handler path and then
    // block PLCrashReporter from ever starting. 'startWithConfig' calls this itself once init is complete.
    if (CountlyCommon.sharedInstance.hasFinishedInit)
    {
        [self applyAutomaticTrackingState];
    }

    _writtenValues = [self notifiedValuesOf:config];
}

- (BOOL)takeConsentRequirementForStart:(CountlyConfig *)config
{
    @synchronized (self) {
        _handledConsentRequirement = @(config.requiresConsent);
        return config.requiresConsent;
    }
}

- (void)applyConsentRequirement
{
    BOOL wasTurnedOn = NO;
    BOOL wasLifted = NO;
    @synchronized (self) {
        // until start has handled consent, start sends the consent state for whichever requirement it finds
        if (!_handledConsentRequirement)
            return;

        BOOL requiresConsent = CountlyConsentManager.sharedInstance.requiresConsent;
        wasTurnedOn = requiresConsent && !_handledConsentRequirement.boolValue;
        wasLifted = !requiresConsent && _handledConsentRequirement.boolValue;
        _handledConsentRequirement = @(requiresConsent);
    }

    if (wasLifted)
    {
        // features that waited for their consent start the way giving that consent starts them: automatic view
        // tracking through applyAutomaticTrackingState, push notifications here, on the main thread its registration needs
        CLY_LOG_D(@"%s consent requirement the behavior settings turned on is off again, features waiting for consent will be started", __FUNCTION__);
        _lastAppliedAutomaticViewTracking = nil;
#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_OSX)
#ifndef COUNTLY_EXCLUDE_PUSHNOTIFICATIONS
        CountlyRunOnMainThread(^{
            [CountlyPushNotifications.sharedInstance startPushNotifications];
        });
#endif
#endif
    }
    if (wasTurnedOn)
    {
        CLY_LOG_D(@"%s consent requirement was turned on by behavior settings, consents will be resent", __FUNCTION__);
        [CountlyConsentManager.sharedInstance sendConsents];
        if (!CountlyConsentManager.sharedInstance.consentForLocation)
        {
            [CountlyConnectionManager.sharedInstance sendLocationInfo];
        }

        // crash handlers installed while no consent was required would otherwise keep capturing, and PLCrashReporter would
        // send that capture on the next start
        if (!CountlyConsentManager.sharedInstance.consentForCrashReporting)
        {
            [CountlyCrashReporter.sharedInstance stopCrashReporting];
        }
    }
}

- (void)applyLocationTrackingState
{
    if (_locationTracking || CountlyLocationManager.sharedInstance.isLocationInfoDisabled)
        return;

    CLY_LOG_D(@"%s location tracking is disabled by behavior settings, location info will be cleared", __FUNCTION__);
    [CountlyLocationManager.sharedInstance disableLocation];
    [CountlyConnectionManager.sharedInstance sendLocationInfo];
}

// Applies the resolved 'ast', 'avt' and 'acr' values, acting only on what changed, so it is safe after every settings response.
- (void)applyAutomaticTrackingState
{
// The platform guard matches where automatic view tracking is actually implemented, which is narrower
// than what the header declares
#if (TARGET_OS_IOS || TARGET_OS_TV)
    BOOL shouldAutoTrackViews = _viewTrackingEnabled && _automaticViewTrackingEnabled;
    BOOL hasChanged = _lastAppliedAutomaticViewTracking == nil || _lastAppliedAutomaticViewTracking.boolValue != shouldAutoTrackViews;
    _lastAppliedAutomaticViewTracking = @(shouldAutoTrackViews);
    if (hasChanged)
    {
        CountlyRunOnMainThread(^{
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
    }
#endif

    CountlyRunOnMainThread(^{
        [Countly.sharedInstance applyAutomaticSessionTracking];
    });

    // A runtime 'acr' = false does not uninstall the handler; it no-ops through its own runtime check
    // instead, so a later 'acr' = true does not have to reinstall it.
    if (_crashReportingEnabled && _automaticCrashReportingEnabled)
    {
        [CountlyCrashReporter.sharedInstance startCrashReporting];
    }
    else
    {
        CLY_LOG_D(@"%s automatic crash reporting is disabled by behavior settings, the crash handler will not be started, crashReporting: [%@], automaticCrashReporting: [%@]", __FUNCTION__, _crashReportingEnabled ? @"YES" : @"NO", _automaticCrashReportingEnabled ? @"YES" : @"NO");
        [CountlyCrashReporter.sharedInstance suppressAutomaticCrashCapture];
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
            [self fetchServerConfig:_startConfig ?: CountlyConfig.new];
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
    NSString *requestedDeviceID = CountlyDeviceInfo.sharedInstance.deviceID;
    NSUInteger requestedDeviceIDType = CountlyDeviceInfo.sharedInstance.deviceIDTypeValue;
    NSUInteger requestedDeviceIDChangeCount = CountlyCommon.sharedInstance.deviceIDChangeWithoutMergeCount;
    NSUInteger requestedDeviceIDMergeCount = CountlyCommon.sharedInstance.deviceIDMergeCount;
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
            CLY_LOG_D(@"[CountlyServerConfig] fetchServerConfig response, behavior settings fetch failed, previously stored behavior settings will be kept, statusCode: [%ld], error: [%@]", (long)((NSHTTPURLResponse *)response).statusCode, error.localizedDescription);
        }
        else if (serverConfigResponse[kRConfig] != nil)
        {
            NSMutableDictionary *persistentBehaviorSettings = [CountlyPersistency.sharedInstance retrieveServerConfig];
            [self replaceBehaviorSettings:persistentBehaviorSettings withConfig:serverConfigResponse];
            [self populateServerConfig:persistentBehaviorSettings withConfig:config];
            [CountlyPersistency.sharedInstance storeServerConfig:persistentBehaviorSettings];
            CLY_LOG_D(@"[CountlyServerConfig] fetchServerConfig response, fetched behavior settings replaced the stored ones and were persisted, storedKeyCount: [%lu]", (unsigned long)persistentBehaviorSettings.count);
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
        // usable directive decides against it. A merge keeps the user, and the server moves the gather with it
        if (requestedDeviceIDChangeCount == CountlyCommon.sharedInstance.deviceIDChangeWithoutMergeCount)
            [self applyLogGatheringDirective:serverConfigResponse[kRLogGathering]];
        else
            CLY_LOG_D(@"%s, the device ID changed without merge while the fetch was in flight, its log gathering directive belongs to the previous user and is ignored", __FUNCTION__);

        if (connectionTestArmed)
            [CountlyConnectionTest.sharedInstance startBatteryWithServerConfigLatency:fetchLatencyMs deviceID:requestedDeviceID deviceIDType:requestedDeviceIDType deviceIDMergeCount:requestedDeviceIDMergeCount];
    };
    // Set default values
    NSURLSessionTask *task = [CountlyCommon.sharedInstance immediateDataTaskWithRequest:[self serverConfigRequest] completionHandler:handler];
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
    [self revertSettingsMissingFrom:@{}];

    CLY_LOG_D(@"%s behavior settings reset to built in SDK defaults", __FUNCTION__);
}

/// Puts every setting the given behavior settings do not carry back to its default, so a setting the server stops
/// sending does not keep its last server value. The automatic tracking flags go back to the developer's values from
/// start, and the integer settings to 0, which notifySdkConfigChange: resolves to the developer's value. It runs after
/// the carried settings are applied, so a carried setting is never reset in between.
- (void)revertSettingsMissingFrom:(NSDictionary *)dictionary
{
    if (!dictionary[kTracking]) _trackingEnabled = YES;
    if (!dictionary[kNetworking]) _networkingEnabled = YES;
    if (!dictionary[kRCrashReporting]) _crashReportingEnabled = YES;
    if (!dictionary[kRAutomaticSessionTracking]) _automaticSessionTrackingEnabled = [self developerValueForKey:kRAutomaticSessionTracking orCurrent:@YES].boolValue;
    if (!dictionary[kRAutomaticViewTracking]) _automaticViewTrackingEnabled = [self developerValueForKey:kRAutomaticViewTracking orCurrent:@NO].boolValue;
    if (!dictionary[kRAutomaticCrashReporting]) _automaticCrashReportingEnabled = [self developerValueForKey:kRAutomaticCrashReporting orCurrent:@NO].boolValue;
    if (!dictionary[kRCustomEventTracking]) _customEventTrackingEnabled = YES;
    if (!dictionary[kREnterContentZone]) _enterContentZone = NO;
    if (!dictionary[kRLocationTracking]) _locationTracking = YES;
    if (!dictionary[kRViewTracking]) _viewTrackingEnabled = YES;
    if (!dictionary[kRSessionTracking]) _sessionTrackingEnabled = YES;
    if (!dictionary[kRLogging]) _loggingEnabled = NO;
    if (!dictionary[kRRefreshContentZone]) _refreshContentZone = YES;
    if (!dictionary[kRbackoffMechanism]) _backoffMechanism = YES;
    if (!dictionary[kRBOMAcceptedTimeout]) _bomAcceptedTimeoutSeconds = 10;
    if (!dictionary[kRBOMRQPercentage]) _bomRQPercentage = 0.5;
    if (!dictionary[kRBOMRequestAge]) _bomRequestAge = 24;
    if (!dictionary[kRBOMDuration]) _bomDuration = 60;

    if (!dictionary[kREventQueueSize]) _eventQueueSize = 0;
    if (!dictionary[kRReqQueueSize]) _requestQueueSize = 0;
    if (!dictionary[kRSessionUpdateInterval]) _sessionInterval = 0;
    if (!dictionary[kRLimitKeyLength]) _limitKeyLength = 0;
    if (!dictionary[kRLimitValueSize]) _limitValueSize = 0;
    if (!dictionary[kRLimitSegValues]) _limitSegValues = 0;
    if (!dictionary[kRLimitBreadcrumb]) _limitBreadcrumb = 0;
    if (!dictionary[kRLimitTraceLine]) _limitTraceLine = 0;
    if (!dictionary[kRLimitTraceLength]) _limitTraceLength = 0;
    if (!dictionary[kRConsentRequired]) _consentRequired = NO;
    if (!dictionary[kRDropOldRequestTime]) _dropOldRequestTime = 0;
    if (!dictionary[kRContentZoneInterval]) _contentZoneInterval = 0;
    if (!dictionary[kRServerConfigUpdateInterval]) _serverConfigUpdateInterval = 0;
    if (!dictionary[kRUserPropertyCacheLimit]) _userPropertyCacheLimit = 100;

    if (!dictionary[kREventBlacklist] && !dictionary[kREventWhitelist])
    {
        self.eventFilterSet = [NSSet set];
        _eventFilterIsWhitelist = NO;
    }
    if (!dictionary[kRUserPropertyBlacklist] && !dictionary[kRUserPropertyWhitelist])
    {
        self.userPropertyFilterSet = [NSSet set];
        _userPropertyFilterIsWhitelist = NO;
    }
    if (!dictionary[kRSegmentationBlacklist] && !dictionary[kRSegmentationWhitelist])
    {
        self.segmentationFilterSet = [NSSet set];
        _segmentationFilterIsWhitelist = NO;
    }
    if (!dictionary[kREventSegmentationBlacklist] && !dictionary[kREventSegmentationWhitelist])
    {
        self.eventSegmentationFilterMap = @{};
        _eventSegmentationFilterIsWhitelist = NO;
    }
    if (!dictionary[kRJourneyTriggerEvents]) self.journeyTriggerEvents = [NSSet set];
    if (!dictionary[kRJourneyTriggerViews]) self.journeyTriggerViews = [NSSet set];
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
    // read here rather than written into the resolved value, which every answer resets to the server's or the default
    return _backoffMechanism && !_isBackoffDisabledByDeveloper;
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

- (void)updateListingFilters:(NSMutableDictionary *)dictionary logString:(NSMutableString *)logString
{
    // Event filter (eb/ew) - blacklist takes precedence
    NSArray *eb = dictionary[kREventBlacklist];
    NSArray *ew = dictionary[kREventWhitelist];
    if ([eb isKindOfClass:NSArray.class]) {
        self.eventFilterSet = [NSSet setWithArray:eb];
        _eventFilterIsWhitelist = NO;
        [logString appendFormat:@"%@: %@, ", kREventBlacklist, eb];
        if (ew)
            [dictionary removeObjectForKey:kREventWhitelist]; // blacklist takes precedence
    } else if ([ew isKindOfClass:NSArray.class]) {
        self.eventFilterSet = [NSSet setWithArray:ew];
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
        self.userPropertyFilterSet = [NSSet setWithArray:upb];
        _userPropertyFilterIsWhitelist = NO;
        [logString appendFormat:@"%@: %@, ", kRUserPropertyBlacklist, upb];
        if (upw)
            [dictionary removeObjectForKey:kRUserPropertyWhitelist];
    } else if ([upw isKindOfClass:NSArray.class]) {
        self.userPropertyFilterSet = [NSSet setWithArray:upw];
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
        self.segmentationFilterSet = [NSSet setWithArray:sb];
        _segmentationFilterIsWhitelist = NO;
        [logString appendFormat:@"%@: %@, ", kRSegmentationBlacklist, sb];
        if (sw)
            [dictionary removeObjectForKey:kRSegmentationWhitelist];
    } else if ([sw isKindOfClass:NSArray.class]) {
        self.segmentationFilterSet = [NSSet setWithArray:sw];
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
        self.eventSegmentationFilterMap = map.copy;
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
        self.eventSegmentationFilterMap = map.copy;
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
        self.journeyTriggerEvents = [NSSet setWithArray:jte];
        [logString appendFormat:@"%@: %@, ", kRJourneyTriggerEvents, jte];
    } else {
        if (jte)
            [dictionary removeObjectForKey:kRJourneyTriggerEvents];
    }

    // Journey trigger views (jtv)
    NSArray *jtv = dictionary[kRJourneyTriggerViews];
    if ([jtv isKindOfClass:NSArray.class]) {
        self.journeyTriggerViews = [NSSet setWithArray:jtv];
        [logString appendFormat:@"%@: %@, ", kRJourneyTriggerViews, jtv];
    } else {
        if (jtv)
            [dictionary removeObjectForKey:kRJourneyTriggerViews];
    }

    CLY_LOG_D(@"%s resolved listing filters, eventFilterCount: [%lu], eventFilterIsWhitelist: [%@], userPropertyFilterCount: [%lu], userPropertyFilterIsWhitelist: [%@], segmentationFilterCount: [%lu], segmentationFilterIsWhitelist: [%@], eventSegmentationFilteredEventCount: [%lu], eventSegmentationFilterIsWhitelist: [%@], journeyTriggerEventCount: [%lu], journeyTriggerViewCount: [%lu]", __FUNCTION__, (unsigned long)self.eventFilterSet.count, _eventFilterIsWhitelist ? @"YES" : @"NO", (unsigned long)self.userPropertyFilterSet.count, _userPropertyFilterIsWhitelist ? @"YES" : @"NO", (unsigned long)self.segmentationFilterSet.count, _segmentationFilterIsWhitelist ? @"YES" : @"NO", (unsigned long)self.eventSegmentationFilterMap.count, _eventSegmentationFilterIsWhitelist ? @"YES" : @"NO", (unsigned long)self.journeyTriggerEvents.count, (unsigned long)self.journeyTriggerViews.count);
}

- (BOOL)shouldRecordEvent:(NSString *)eventKey
{
    NSSet<NSString *> *eventFilterSet = self.eventFilterSet;
    if (eventFilterSet.count == 0) return YES;
    return _eventFilterIsWhitelist == [eventFilterSet containsObject:eventKey];
}

- (BOOL)shouldRecordUserProperty:(NSString *)propertyKey
{
    NSSet<NSString *> *userPropertyFilterSet = self.userPropertyFilterSet;
    if (userPropertyFilterSet.count == 0) return YES;
    return _userPropertyFilterIsWhitelist == [userPropertyFilterSet containsObject:propertyKey];
}

- (NSDictionary *)filterSegmentation:(NSDictionary *)segmentation eventKey:(NSString *)eventKey
{
    if (!segmentation) {
        return segmentation;
    }

    NSSet<NSString *> *segmentationFilterSet = self.segmentationFilterSet;
    BOOL hasGlobalFilter = segmentationFilterSet.count > 0;
    NSSet *eventFilter = self.eventSegmentationFilterMap[eventKey];
    BOOL hasEventFilter = eventFilter.count > 0;

    if (!hasGlobalFilter && !hasEventFilter) {
        return segmentation;
    }

    NSMutableDictionary *result = [segmentation mutableCopy];
    for (NSString *key in segmentation.allKeys) {
        if (hasGlobalFilter && _segmentationFilterIsWhitelist != [segmentationFilterSet containsObject:key]) {
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
    return [self.journeyTriggerEvents containsObject:eventKey];
}

- (BOOL)isJourneyTriggerView:(NSString *)viewName
{
    return [self.journeyTriggerViews containsObject:viewName];
}

@end
