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
    CLY_LOG_I(@"%s", __FUNCTION__);
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
    NSMutableDictionary *persistentBehaviorSettings = [CountlyPersistency.sharedInstance retrieveServerConfig];
    if (persistentBehaviorSettings.count == 0 && config.sdkBehaviorSettings)
    {
        NSError *error = nil;
        id parsed = [NSJSONSerialization JSONObjectWithData:[config.sdkBehaviorSettings cly_dataUTF8] options:0 error:&error];

        if ([parsed isKindOfClass:[NSDictionary class]]) {
            persistentBehaviorSettings = [(NSDictionary *)parsed mutableCopy];
            [CountlyPersistency.sharedInstance storeServerConfig:persistentBehaviorSettings];
        } else {
            CLY_LOG_W(@"%s, Failed to parse sdkBehaviorSettings or not a dictionary: %@", __FUNCTION__, error);
        }
    }

    [self populateServerConfig:persistentBehaviorSettings withConfig:config];
}

- (void)mergeBehaviorSettings:(NSMutableDictionary *)baseConfig
                          withConfig:(NSDictionary *)newConfig
{
    // c, t and v paramters must exist
    if(newConfig.count != 3 || !newConfig[kRConfig]) {
        CLY_LOG_D(@"%s, missing entries for a behavior settings omitting", __FUNCTION__);
        return;
    }
    
    if (!newConfig[kRVersion] || !newConfig[kRTimestamp])
    {
        CLY_LOG_D(@"%s, version or timestamp is missing in the behavioır settings omitting", __FUNCTION__);
        return;
    }
    
    if(!([newConfig[kRConfig] isKindOfClass:[NSDictionary class]]) || ((NSDictionary *)newConfig[kRConfig]).count == 0){
        CLY_LOG_D(@"%s, invalid behavior settings omitting", __FUNCTION__);
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
    }
}

- (void)setBoolProperty:(BOOL *)property fromDictionary:(NSDictionary *)dictionary key:(NSString *)key logString:(NSMutableString *)logString
{
    NSNumber *value = dictionary[key];
    if (value)
    {
        *property = value.boolValue;
        [logString appendFormat:@"%@: %@, ", key, *property ? @"YES" : @"NO"];
    }
}

- (void)setIntegerProperty:(NSInteger *)property fromDictionary:(NSDictionary *)dictionary key:(NSString *)key logString:(NSMutableString *)logString
{
    NSNumber *value = dictionary[key];
    if (value)
    {
        *property = value.integerValue;
        [logString appendFormat:@"%@: %ld, ", key, (long)*property];
    }
}

- (void)setDoubleProperty:(double *)property fromDictionary:(NSDictionary *)dictionary key:(NSString *)key logString:(NSMutableString *)logString
{
    NSNumber *value = dictionary[key];
    if (value)
    {
        *property = value.doubleValue;
        [logString appendFormat:@"%@: %lf, ", key, (double)*property];
    }
}

- (void)populateServerConfig:(NSDictionary *)serverConfig withConfig:(CountlyConfig *)config
{
    if(config.requestTimeoutDuration <= 0) {
        config.requestTimeoutDuration = 1;
    }
    
    _requestTimeoutDuration = config.requestTimeoutDuration;
    
    if (!serverConfig[kRConfig])
    {
        CLY_LOG_D(@"%s, config key is missing in the server configuration omitting", __FUNCTION__);
        return;
    }
    
    NSDictionary *dictionary = serverConfig[kRConfig];
    
    if (!serverConfig[kRVersion] || !serverConfig[kRTimestamp])
    {
        CLY_LOG_D(@"%s, version or timestamp is missing in the server configuration omitting", __FUNCTION__);
        return;
    }
    
    _version = [serverConfig[kRVersion] integerValue];
    _timestamp = [serverConfig[kRTimestamp] longLongValue];
    
    NSMutableString *logString = [NSMutableString stringWithString:@"Server Config: "];
    
    [self setBoolProperty:&_trackingEnabled fromDictionary:dictionary key:kTracking logString:logString];
    [self setBoolProperty:&_networkingEnabled fromDictionary:dictionary key:kNetworking logString:logString];
    [self setIntegerProperty:&_sessionInterval fromDictionary:dictionary key:kRSessionUpdateInterval logString:logString];
    [self setIntegerProperty:&_requestQueueSize fromDictionary:dictionary key:kRReqQueueSize logString:logString];
    [self setIntegerProperty:&_eventQueueSize fromDictionary:dictionary key:kREventQueueSize logString:logString];
    [self setBoolProperty:&_crashReportingEnabled fromDictionary:dictionary key:kRCrashReporting logString:logString];
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
    [self setIntegerProperty:&_contentZoneInterval fromDictionary:dictionary key:kRContentZoneInterval logString:logString];
    [self setBoolProperty:&_consentRequired fromDictionary:dictionary key:kRConsentRequired logString:logString];
    [self setIntegerProperty:&_dropOldRequestTime fromDictionary:dictionary key:kRDropOldRequestTime logString:logString];
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

    if(![logString isEqualToString: @"Server Config: "]){
        // means new config gotten, if that is the case notify SDK
        [self notifySdkConfigChange: config];
    }

    CLY_LOG_D(@"%s, version:[%li], timestamp:[%lli], %@", __FUNCTION__, _version, _timestamp, logString);
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
    CountlyCommon.sharedInstance.maxSegmentationValues = config.sdkInternalLimits.getMaxSegmentationValues;

    config.eventSendThreshold = _eventQueueSize ?: config.eventSendThreshold;
    config.requestDropAgeHours = _dropOldRequestTime ?: config.requestDropAgeHours;
    config.storedRequestsLimit = _requestQueueSize ?: config.storedRequestsLimit;
    CountlyPersistency.sharedInstance.eventSendThreshold = config.eventSendThreshold;
    CountlyPersistency.sharedInstance.requestDropAgeHours = config.requestDropAgeHours;
    CountlyPersistency.sharedInstance.storedRequestsLimit = MAX(1, config.storedRequestsLimit);

    config.updateSessionPeriod = _sessionInterval ?: config.updateSessionPeriod;
    _sessionInterval = config.updateSessionPeriod;
    
    config.requiresConsent = _consentRequired ?: config.requiresConsent;
    CountlyConsentManager.sharedInstance.requiresConsent = config.requiresConsent;

#if (TARGET_OS_IOS)
    [config.content setZoneTimerInterval:_contentZoneInterval ?: config.content.getZoneTimerInterval];
    if (config.content.getZoneTimerInterval)
    {
        CountlyContentBuilderInternal.sharedInstance.zoneTimerInterval = config.content.getZoneTimerInterval;
    }
    if (!_enterContentZone)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [CountlyContentBuilderInternal.sharedInstance exitContentZone];
        });
    }
    else
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [CountlyContentBuilderInternal.sharedInstance exitContentZone];
            [CountlyContentBuilderInternal.sharedInstance enterContentZone:@[]];
        });
    }
#endif
    CountlyCrashReporter.sharedInstance.crashLogLimit = config.sdkInternalLimits.getMaxBreadcrumbCount;

    if (_serverConfigUpdateInterval && _serverConfigUpdateInterval != _currentServerConfigUpdateInterval && _requestTimer)
    {
        _currentServerConfigUpdateInterval = _serverConfigUpdateInterval;
        [_requestTimer invalidate];
        _requestTimer = nil;
        _requestTimer = [NSTimer timerWithTimeInterval:_currentServerConfigUpdateInterval * 60 * 60 target:self selector:@selector(fetchServerConfigTimer:) userInfo:config repeats:YES];
        [NSRunLoop.mainRunLoop addTimer:_requestTimer forMode:NSRunLoopCommonModes];
    }

    if (!_locationTracking && !CountlyLocationManager.sharedInstance.isLocationInfoDisabled)
    {
        [CountlyLocationManager.sharedInstance disableLocationInfo];
    }
    
    if(_backoffMechanism && config.disableBackoffMechanism){
        _backoffMechanism = NO;
    }
}

- (void)fetchServerConfigTimer:(NSTimer *)timer
{
    CountlyConfig *config = (CountlyConfig *)timer.userInfo; // Retrieve CountlyConfig from userInfo
    if (config)
    {
        [self fetchServerConfig:config];
    }
}

- (void)fetchServerConfigIfTimeIsUp
{
    if (_serverConfigUpdatesDisabled) {
        return;
    }
    
    if (_lastFetchTimestamp)
    {
        long long currentTime = NSDate.date.timeIntervalSince1970 * 1000;
        long long timePassed = currentTime - _lastFetchTimestamp;

        if (timePassed > _currentServerConfigUpdateInterval * 60 * 60 * 1000)
        {
            [self fetchServerConfig:CountlyConfig.new];
        }
    }
}

- (void)fetchServerConfig:(CountlyConfig *)config
{
    CLY_LOG_D(@"%s, fetching sdk behavior settings", __FUNCTION__);
    
    if (_serverConfigUpdatesDisabled) {
        CLY_LOG_D(@"%s, sdk behavior settings updates disabled, omitting fetch", __FUNCTION__);
        return;
    }
    
    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
        return;

    _lastFetchTimestamp = NSDate.date.timeIntervalSince1970 * 1000;

    if (!_requestTimer)
    {
        _requestTimer = [NSTimer timerWithTimeInterval:_currentServerConfigUpdateInterval * 60 * 60 target:self selector:@selector(fetchServerConfigTimer:) userInfo:config repeats:YES];
        [NSRunLoop.mainRunLoop addTimer:_requestTimer forMode:NSRunLoopCommonModes];
    }

    id handler = ^(NSData *data, NSURLResponse *response, NSError *error) {
        NSDictionary *serverConfigResponse = nil;
        if (!error)
        {
            serverConfigResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            CLY_LOG_D(@"Server Config Fetched: %@", serverConfigResponse.description);
        }

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
            CLY_LOG_E(@"Error while fetching server configs: %@", error.description);
        }

        if (serverConfigResponse[kRConfig] != nil)
        {
            NSMutableDictionary *persistentBehaviorSettings = [CountlyPersistency.sharedInstance retrieveServerConfig];
            [self mergeBehaviorSettings:persistentBehaviorSettings withConfig:serverConfigResponse];
            [CountlyPersistency.sharedInstance storeServerConfig:persistentBehaviorSettings];
            [self populateServerConfig:persistentBehaviorSettings withConfig:config];
        }
    };
    // Set default values
    NSURLSessionTask *task = [CountlyCommon.sharedInstance.URLSession dataTaskWithRequest:[self serverConfigRequest] completionHandler:handler];
    [task resume];
}

- (NSURLRequest *)serverConfigRequest
{
    NSString *queryString = [NSString stringWithFormat:@"%@=%@&%@=%@&%@=%@&%@=%@&%@=%@", kCountlyQSKeyMethod, kCountlySCKeySC, kCountlyQSKeyAppKey, CountlyConnectionManager.sharedInstance.appKey.cly_URLEscaped, kCountlyQSKeyDeviceID, CountlyDeviceInfo.sharedInstance.deviceID.cly_URLEscaped,
                                                       kCountlyQSKeySDKName, CountlyCommon.sharedInstance.SDKName, kCountlyQSKeySDKVersion, CountlyCommon.sharedInstance.SDKVersion];

    queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyAppVersionKey, CountlyDeviceInfo.appVersion];

    queryString = [CountlyConnectionManager.sharedInstance appendChecksum:queryString];

    NSMutableString *URL = CountlyConnectionManager.sharedInstance.host.mutableCopy;
    [URL appendString:kCountlyEndpointO];
    [URL appendString:kCountlyEndpointSDK];

    if (queryString.length > kCountlyGETRequestMaxLength || CountlyConnectionManager.sharedInstance.alwaysUsePOST)
    {
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:URL]];
        request.HTTPMethod = @"POST";
        request.HTTPBody = [queryString cly_dataUTF8];
        return request.copy;
    }
    else
    {
        [URL appendFormat:@"?%@", queryString];
        NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:URL]];
        return request;
    }

    CLY_LOG_D(@"serverConfigRequest URL :%@", URL);
}

- (void)setDefaultValues {
    _trackingEnabled = YES;
    _networkingEnabled = YES;
    _crashReportingEnabled = YES;
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

    // Reset numeric properties to 0 so notifySdkConfigChange: falls back to CountlyConfig defaults
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
}

- (void)disableSDKBehaviourSettings {
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
    // Remove listing filter keys from stored config based on new config
    // If new config has any whitelist key, remove all blacklist keys from stored config
    // If new config has any blacklist key, remove all whitelist keys from stored config
    NSArray *whitelistKeys = @[kREventWhitelist, kRSegmentationWhitelist, kREventSegmentationWhitelist, kRUserPropertyWhitelist];
    NSArray *blacklistKeys = @[kREventBlacklist, kRSegmentationBlacklist, kREventSegmentationBlacklist, kRUserPropertyBlacklist];

    BOOL newHasWhitelist = NO;
    BOOL newHasBlacklist = NO;
    for (NSString *key in whitelistKeys)
    {
        if (newConfig[key]) { newHasWhitelist = YES; break; }
    }
    for (NSString *key in blacklistKeys)
    {
        if (newConfig[key]) { newHasBlacklist = YES; break; }
    }

    if (newHasWhitelist)
    {
        for (NSString *key in blacklistKeys)
        {
            [mergedConfig removeObjectForKey:key];
        }
    }
    if (newHasBlacklist)
    {
        for (NSString *key in whitelistKeys)
        {
            [mergedConfig removeObjectForKey:key];
        }
    }
}

- (void)updateListingFilters:(NSDictionary *)dictionary logString:(NSMutableString *)logString
{
    // Event filter (eb/ew) - blacklist takes precedence
    NSArray *eb = dictionary[kREventBlacklist];
    NSArray *ew = dictionary[kREventWhitelist];
    if ([eb isKindOfClass:NSArray.class]) {
        _eventFilterSet = [NSSet setWithArray:eb];
        _eventFilterIsWhitelist = NO;
        [logString appendFormat:@"%@: %@, ", kREventBlacklist, eb];
    } else if ([ew isKindOfClass:NSArray.class]) {
        _eventFilterSet = [NSSet setWithArray:ew];
        _eventFilterIsWhitelist = YES;
        [logString appendFormat:@"%@: %@, ", kREventWhitelist, ew];
    }

    // User property filter (upb/upw) - blacklist takes precedence
    NSArray *upb = dictionary[kRUserPropertyBlacklist];
    NSArray *upw = dictionary[kRUserPropertyWhitelist];
    if ([upb isKindOfClass:NSArray.class]) {
        _userPropertyFilterSet = [NSSet setWithArray:upb];
        _userPropertyFilterIsWhitelist = NO;
        [logString appendFormat:@"%@: %@, ", kRUserPropertyBlacklist, upb];
    } else if ([upw isKindOfClass:NSArray.class]) {
        _userPropertyFilterSet = [NSSet setWithArray:upw];
        _userPropertyFilterIsWhitelist = YES;
        [logString appendFormat:@"%@: %@, ", kRUserPropertyWhitelist, upw];
    }

    // Segmentation filter (sb/sw) - blacklist takes precedence
    NSArray *sb = dictionary[kRSegmentationBlacklist];
    NSArray *sw = dictionary[kRSegmentationWhitelist];
    if ([sb isKindOfClass:NSArray.class]) {
        _segmentationFilterSet = [NSSet setWithArray:sb];
        _segmentationFilterIsWhitelist = NO;
        [logString appendFormat:@"%@: %@, ", kRSegmentationBlacklist, sb];
    } else if ([sw isKindOfClass:NSArray.class]) {
        _segmentationFilterSet = [NSSet setWithArray:sw];
        _segmentationFilterIsWhitelist = YES;
        [logString appendFormat:@"%@: %@, ", kRSegmentationWhitelist, sw];
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
    }

    // Journey trigger events (jte)
    NSArray *jte = dictionary[kRJourneyTriggerEvents];
    if ([jte isKindOfClass:NSArray.class]) {
        _journeyTriggerEvents = [NSSet setWithArray:jte];
        [logString appendFormat:@"%@: %@, ", kRJourneyTriggerEvents, jte];
    }
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
            CLY_LOG_D(@"Filtering out segmentation key '%@' by global segmentation filter", key);
            [result removeObjectForKey:key];
        }
        else if (hasEventFilter && _eventSegmentationFilterIsWhitelist != [eventFilter containsObject:key]) {
            CLY_LOG_D(@"Filtering out segmentation key '%@' for event '%@' by event segmentation filter", key, eventKey);
            [result removeObjectForKey:key];
        }
    }

    return result.copy;
}

- (BOOL)isJourneyTriggerEvent:(NSString *)eventKey
{
    return [_journeyTriggerEvents containsObject:eventKey];
}

@end
