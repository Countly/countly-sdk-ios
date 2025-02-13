//  CountlyServerConfig.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface CountlyServerConfig ()
@property (nonatomic) BOOL trackingEnabled;
@property (nonatomic) BOOL networkingEnabled;
@property (nonatomic) NSInteger sessionInterval;
@property (nonatomic) NSInteger eventQueueSize;
@property (nonatomic) NSInteger requestQueueSize;
@property (nonatomic) BOOL crashReportingEnabled;
@property (nonatomic) BOOL loggingEnabled;

@property (nonatomic) NSInteger limitKeyLength;
@property (nonatomic) NSInteger limitValueSize;
@property (nonatomic) NSInteger limitSegValues;
@property (nonatomic) NSInteger limitBreadcrumb;
@property (nonatomic) NSInteger limitTraceLine;
@property (nonatomic) NSInteger limitTraceLength;
@property (nonatomic) BOOL customEventTrackingEnabled;
@property (nonatomic) BOOL viewTrackingEnabled;
@property (nonatomic) BOOL sessionTrackingEnabled;
@property (nonatomic) BOOL enterContentZone;
@property (nonatomic) NSInteger contentZoneInterval;
@property (nonatomic) BOOL consentRequired;
@property (nonatomic) NSInteger dropOldRequestTime;
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
        
        NSDictionary* serverConfigObject = [CountlyPersistency.sharedInstance retrieveServerConfig];
        if (serverConfigObject) {
            [self populateServerConfig:serverConfigObject];
        }
    }
    return self;
}

- (void)populateServerConfig:(NSDictionary *)dictionary
{
    if (dictionary[kTracking]) {
        self.trackingEnabled = [dictionary[kTracking] boolValue];
    }

    if (dictionary[kNetworking]) {
        self.networkingEnabled = [dictionary[kNetworking] boolValue];
    }

    if (dictionary[kRSessionUpdateInterval]) {
        self.sessionInterval = [dictionary[kRSessionUpdateInterval] integerValue];
    }
    
    if (dictionary[kRReqQueueSize]) {
        self.requestQueueSize = [dictionary[kRReqQueueSize] integerValue];
    }

    if (dictionary[kREventQueueSize]) {
        self.eventQueueSize = [dictionary[kREventQueueSize] integerValue];
    }

    if (dictionary[kRCrashReporting]) {
        self.crashReportingEnabled = [dictionary[kRCrashReporting] boolValue];
    }

    if (dictionary[kRSessionTracking]) {
        self.sessionTrackingEnabled = [dictionary[kRSessionTracking] boolValue];
    }
    
    if (dictionary[kRLogging]) {
        self.loggingEnabled = [dictionary[kRLogging] boolValue];
    }

    if (dictionary[kRLimitKeyLength]) {
        self.limitKeyLength = [dictionary[kRLimitKeyLength] integerValue];
    }

    if (dictionary[kRLimitValueSize]) {
        self.limitValueSize = [dictionary[kRLimitValueSize] integerValue];
    }

    if (dictionary[kRLimitSegValues]) {
        self.limitSegValues = [dictionary[kRLimitSegValues] integerValue];
    }

    if (dictionary[kRLimitBreadcrumb]) {
        self.limitBreadcrumb = [dictionary[kRLimitBreadcrumb] integerValue];
    }

    if (dictionary[kRLimitTraceLine]) {
        self.limitTraceLine = [dictionary[kRLimitTraceLine] integerValue];
    }

    if (dictionary[kRLimitTraceLength]) {
        self.limitTraceLength = [dictionary[kRLimitTraceLength] integerValue];
    }

    if (dictionary[kRCustomEventTracking]) {
        self.customEventTrackingEnabled = [dictionary[kRCustomEventTracking] boolValue];
    }
    
    if (dictionary[kRViewTracking]) {
        self.viewTrackingEnabled = [dictionary[kRViewTracking] boolValue];
    }

    if (dictionary[kREnterContentZone]) {
        self.enterContentZone = [dictionary[kREnterContentZone] boolValue];
    }

    if (dictionary[kRContentZoneInterval]) {
        self.contentZoneInterval = [dictionary[kRContentZoneInterval] integerValue];
    }

    if (dictionary[kRConsentRequired]) {
        self.consentRequired = [dictionary[kRConsentRequired] boolValue];
    }

    if (dictionary[kRDropOldRequestTime]) {
        self.dropOldRequestTime = [dictionary[kRDropOldRequestTime] integerValue];
    }

    
    CLY_LOG_D(@"tracking : %@", self.trackingEnabled ? @"YES" : @"NO");
    CLY_LOG_D(@"networking : %@", self.networkingEnabled ? @"YES" : @"NO");
    CLY_LOG_D(@"sessionInterval : %ld", (long)self.sessionInterval);
    CLY_LOG_D(@"eventQueueSize : %ld", (long)self.eventQueueSize);
    CLY_LOG_D(@"crashReporting : %@", self.crashReportingEnabled ? @"YES" : @"NO");
    CLY_LOG_D(@"logging : %@", self.loggingEnabled ? @"YES" : @"NO");
}

- (void)fetchServerConfig
{
    CLY_LOG_D(@"Fetching server configs...");
    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
        return;
    
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
            return;
        }
        
        NSDictionary* serverConfigObject = serverConfigResponse[kRConfig];
        if (serverConfigObject) {
            [self populateServerConfig:serverConfigObject];
            [CountlyPersistency.sharedInstance storeServerConfig:serverConfigObject];
        }
    
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
