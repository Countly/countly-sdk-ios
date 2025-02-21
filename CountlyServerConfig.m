//  CountlyServerConfig.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface CountlyServerConfig ()
@property (nonatomic) BOOL trackingEnabled;
@property (nonatomic) BOOL networkingEnabled;
@property (nonatomic) BOOL crashReportingEnabled;
@property (nonatomic) BOOL loggingEnabled;
@property (nonatomic) BOOL customEventTrackingEnabled;
@property (nonatomic) BOOL viewTrackingEnabled;
@property (nonatomic) BOOL sessionTrackingEnabled;
@property (nonatomic) BOOL enterContentZone;
@property (nonatomic) BOOL consentRequired;

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

@property (nonatomic) NSInteger version;
@property (nonatomic) long long timestamp;
@end

NSString* const kCountlySCKeySC = @"sc";
NSString* const kTracking = @"tracking";
NSString* const kNetworking = @"networking";

// request keys
NSString* const kRTimestamp = @"t";
NSString* const kRVersion = @"v";
NSString* const kRConfig = @"c";
NSString* const kRReqQueueSize = @"rqs";
NSString* const kREventQueueSize = @"eqs";
NSString* const kRLogging = @"log";
NSString* const kRSessionUpdateInterval = @"sui";
NSString* const kRSessionTracking = @"st";
NSString* const kRViewTracking = @"vt";

NSString* const kRLimitKeyLength = @"lkl";
NSString* const kRLimitValueSize = @"lvs";
NSString* const kRLimitSegValues = @"lsv";
NSString* const kRLimitBreadcrumb = @"lbc";
NSString* const kRLimitTraceLine = @"ltlpt";
NSString* const kRLimitTraceLength = @"ltl";
NSString* const kRCustomEventTracking = @"cet";
NSString* const kREnterContentZone = @"ecz";
NSString* const kRContentZoneInterval = @"czi";
NSString* const kRConsentRequired = @"cr";
NSString* const kRDropOldRequestTime = @"dort";
NSString* const kRCrashReporting = @"crt";


@implementation CountlyServerConfig

+ (instancetype)sharedInstance
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return nil;
    
    static CountlyServerConfig* s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        // Set default values
        _trackingEnabled = YES;
        _networkingEnabled = YES;
        _crashReportingEnabled = YES;
        _customEventTrackingEnabled = YES;
        _enterContentZone = NO;
        
        _timestamp = 0;
        _version = 0;
        
        NSError* error = nil;
        NSDictionary* serverConfigObject;
        serverConfigObject = [NSJSONSerialization JSONObjectWithData:[_providedServerConfiguration cly_dataUTF8] options:0 error:&error];
        
        if(error){
            serverConfigObject = [CountlyPersistency.sharedInstance retrieveServerConfig];
        }
        
        if (serverConfigObject) {
            [self populateServerConfig:serverConfigObject];
        }
    }
    return self;
}

- (void)setBoolProperty:(BOOL *)property fromDictionary:(NSDictionary *)dictionary key:(NSString *)key logString:(NSMutableString *)logString
{
    NSNumber *value = dictionary[key];
    if (value) {
        *property = value.boolValue;
        [logString appendFormat:@"%@: %@, ", key, *property ? @"YES" : @"NO"];
    }
}

- (void)setIntegerProperty:(NSInteger *)property fromDictionary:(NSDictionary *)dictionary key:(NSString *)key logString:(NSMutableString *)logString
{
    NSNumber *value = dictionary[key];
    if (value) {
        *property = value.integerValue;
        [logString appendFormat:@"%@: %ld, ", key, (long)*property];
    }
}

- (void)populateServerConfig:(NSDictionary *)serverConfig
{
    if(!serverConfig[kRConfig]) {
        CLY_LOG_D(@"%s, config key is missing in the server configuration omitting", __FUNCTION__);
        return;
    }
    
    NSDictionary* dictionary = serverConfig[kRConfig];
    
    if(!dictionary[kRVersion] || !dictionary[kRTimestamp]) {
        CLY_LOG_D(@"%s, version or timestamps is missing in the server configuration omitting", __FUNCTION__);
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

    CLY_LOG_D(@"%s, version:[%li], timestamp:[%lli], %@", __FUNCTION__, _version, _timestamp, logString);
}

- (void)notifySdkConfigChange:(CountlyConfig *)config
{
    config.enableDebug = _loggingEnabled || config.enableDebug;
    CountlyCommon.sharedInstance.enableDebug = config.enableDebug;
    
    // Limits could be moved to another function, but letting them stay here serves us a monopolized view of notify
    if (config.maxKeyLength) {
        [config.sdkInternalLimits setMaxKeyLength: config.maxKeyLength];
    }
    
    if (config.maxValueLength) {
        [config.sdkInternalLimits setMaxValueSize: config.maxValueLength];
    }
    
    if (config.maxSegmentationValues) {
        [config.sdkInternalLimits setMaxSegmentationValues: config.maxSegmentationValues];
    }
    
    if (config.crashLogLimit) {
        [config.sdkInternalLimits setMaxBreadcrumbCount: config.crashLogLimit];
    }
    
    [config.sdkInternalLimits setMaxKeyLength: _limitKeyLength ?: config.sdkInternalLimits.getMaxKeyLength];
    [config.sdkInternalLimits setMaxValueSize: _limitValueSize ?: config.sdkInternalLimits.getMaxValueSize];
    [config.sdkInternalLimits setMaxSegmentationValues: _limitSegValues ?: config.sdkInternalLimits.getMaxSegmentationValues];
    [config.sdkInternalLimits setMaxBreadcrumbCount: _limitBreadcrumb ?: config.sdkInternalLimits.getMaxBreadcrumbCount];
    [config.sdkInternalLimits setMaxStackTraceLineLength: _limitTraceLength ?: config.sdkInternalLimits.getMaxStackTraceLineLength];
    [config.sdkInternalLimits setMaxStackTraceLinesPerThread: _limitTraceLine ?: config.sdkInternalLimits.getMaxStackTraceLinesPerThread];
            
    CountlyCommon.sharedInstance.maxKeyLength = config.sdkInternalLimits.getMaxKeyLength;
    CountlyCommon.sharedInstance.maxValueLength = config.sdkInternalLimits.getMaxValueSize;
    CountlyCommon.sharedInstance.maxSegmentationValues = config.sdkInternalLimits.getMaxSegmentationValues;
    
    config.requiresConsent = _consentRequired ?: config.requiresConsent;
    CountlyConsentManager.sharedInstance.requiresConsent = config.requiresConsent;
    
    config.eventSendThreshold = _eventQueueSize ?: config.eventSendThreshold;
    config.requestDropAgeHours = _dropOldRequestTime ?: config.requestDropAgeHours;
    config.storedRequestsLimit = _requestQueueSize ?: config.storedRequestsLimit;
    CountlyPersistency.sharedInstance.eventSendThreshold = config.eventSendThreshold;
    CountlyPersistency.sharedInstance.requestDropAgeHours = config.requestDropAgeHours;
    CountlyPersistency.sharedInstance.storedRequestsLimit = MAX(1, config.storedRequestsLimit);
    
    config.updateSessionPeriod = _sessionInterval ?: config.updateSessionPeriod;
    
    [config.content setZoneTimerInterval: _contentZoneInterval ?: config.content.getZoneTimerInterval];
    
    CountlyCrashReporter.sharedInstance.crashLogLimit = config.sdkInternalLimits.getMaxBreadcrumbCount;
    
    if(_enterContentZone){
        dispatch_async(dispatch_get_main_queue(), ^{
            [CountlyContentBuilder.sharedInstance enterContentZone];
        });
    }
}

- (void)fetchServerConfig:(CountlyConfig *)config
{
    CLY_LOG_D(@"Fetching server configs...");
    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
        return;
    
    // Set default values
    _trackingEnabled = YES;
    _networkingEnabled = YES;
    _crashReportingEnabled = YES;
    _customEventTrackingEnabled = YES;
    _enterContentZone = NO;
    _loggingEnabled = NO;
    
    NSURLSessionTask* task = [CountlyCommon.sharedInstance.URLSession dataTaskWithRequest:[self serverConfigRequest] completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
                              {
        NSDictionary *serverConfigResponse = nil;
        
        if (!error)
        {
            serverConfigResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            CLY_LOG_D(@"Server Config Fetched: %@", serverConfigResponse.description);
        }
        
        if (!error)
        {
            if (((NSHTTPURLResponse*)response).statusCode != 200)
            {
                NSMutableDictionary* serverConfig = serverConfigResponse.mutableCopy;
                serverConfig[NSLocalizedDescriptionKey] = @"Server configuration general API error";
                error = [NSError errorWithDomain:kCountlyErrorDomain code:CLYErrorServerConfigGeneralAPIError userInfo:serverConfig];
            }
        }
        
        if (error)
        {
            CLY_LOG_E(@"Error while fetching server configs: %@",error.description);
        }
        
        if (serverConfigResponse[kRConfig] != nil) {
            [self populateServerConfig:serverConfigResponse];
            [CountlyPersistency.sharedInstance storeServerConfig:serverConfigResponse];
        }
        
        [self notifySdkConfigChange: config]; // if no config let stored ones to be set
    }];
    
    [task resume];
}

- (NSURLRequest *)serverConfigRequest
{
    NSString* queryString = [NSString stringWithFormat:@"%@=%@&%@=%@&%@=%@&%@=%@&%@=%@",
                             kCountlyQSKeyMethod, kCountlySCKeySC,
                             kCountlyQSKeyAppKey, CountlyConnectionManager.sharedInstance.appKey.cly_URLEscaped,
                             kCountlyQSKeyDeviceID, CountlyDeviceInfo.sharedInstance.deviceID.cly_URLEscaped,
                             kCountlyQSKeySDKName, CountlyCommon.sharedInstance.SDKName,
                             kCountlyQSKeySDKVersion, CountlyCommon.sharedInstance.SDKVersion];
    
    queryString = [queryString stringByAppendingFormat:@"&%@=%@",
                   kCountlyAppVersionKey, CountlyDeviceInfo.appVersion];
    
    queryString = [CountlyConnectionManager.sharedInstance appendChecksum:queryString];
    
    NSMutableString* URL = CountlyConnectionManager.sharedInstance.host.mutableCopy;
    [URL appendString:kCountlyEndpointO];
    [URL appendString:kCountlyEndpointSDK];
    
    if (queryString.length > kCountlyGETRequestMaxLength || CountlyConnectionManager.sharedInstance.alwaysUsePOST)
    {
        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:URL]];
        request.HTTPMethod = @"POST";
        request.HTTPBody = [queryString cly_dataUTF8];
        return request.copy;
    }
    else
    {
        [URL appendFormat:@"?%@", queryString];
        NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:URL]];
        return request;
    }
    
    CLY_LOG_D(@"serverConfigRequest URL :%@", URL);
}

- (BOOL)trackingEnabled {
    return _trackingEnabled;
}

- (BOOL)networkingEnabled {
    return _networkingEnabled;
}

- (NSInteger)sessionInterval {
    return _sessionInterval;
}

- (NSInteger)requestQueueSize {
    return _requestQueueSize;
}

- (NSInteger)eventQueueSize {
    return _eventQueueSize;
}

- (BOOL)crashReportingEnabled {
    return _crashReportingEnabled;
}

- (BOOL)sessionTrackingEnabled {
    return _sessionTrackingEnabled;
}
- (BOOL)loggingEnabled {
    return _loggingEnabled;
}

- (NSInteger)limitKeyLength {
    return _limitKeyLength;
}

- (NSInteger)limitValueSize {
    return _limitValueSize;
}

- (NSInteger)limitSegValues {
    return _limitSegValues;
}

- (NSInteger)limitBreadcrumb {
    return _limitBreadcrumb;
}

- (NSInteger)limitTraceLine {
    return _limitTraceLine;
}

- (NSInteger)limitTraceLength {
    return _limitTraceLength;
}

- (BOOL)customEventTrackingEnabled {
    return _customEventTrackingEnabled;
}

- (BOOL)viewTrackingEnabled {
    return _viewTrackingEnabled;
}

- (BOOL)enterContentZone {
    return _enterContentZone;
}

- (NSInteger)contentZoneInterval {
    return _contentZoneInterval;
}

- (BOOL)consentRequired {
    return _consentRequired;
}

- (NSInteger)dropOldRequestTime {
    return _dropOldRequestTime;
}


@end
