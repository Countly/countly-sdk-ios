//  CountlyServerConfig.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"
#if (TARGET_OS_IOS)
#import <WebKit/WebKit.h>
#endif

NSString* const kCountlySCKeySC             = @"sc";

@implementation CountlyServerConfig
#if (TARGET_OS_IOS)
{
    UIButton* btn_star[5];
}

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
    if (self = [super init])
    {
#if (TARGET_OS_WATCH)
        self.updateSessionPeriod = 20.0;
#else
        self.updateSessionPeriod = 60.0;
#endif
        self.eventSendThreshold = 100;
        self.storedRequestsLimit = 1000;
        
        self.views = YES;
        self.crashes = YES;
        self.tracking = YES;
        self.networking = YES;
        NSDictionary* serverConfigObject = [CountlyPersistency.sharedInstance retrieveServerConfig];
        if(serverConfigObject) {
            [self populateServerConfig:serverConfigObject];
        }
    }
    
    return self;
}

- (void)populateServerConfig:(NSDictionary *)dictionary
{
    self.updateSessionPeriod = [dictionary[@"heartbeat"] intValue];
    self.eventSendThreshold = [dictionary[@"event_queue"] intValue];
    self.storedRequestsLimit = [dictionary[@"request_queue"] intValue];
    
    self.views = [dictionary[@"views"] boolValue];
    self.crashes = [dictionary[@"crashes"] boolValue];
    self.tracking = [dictionary[@"tracking"] boolValue];
    self.networking = [dictionary[@"networking"] boolValue];
    
    CLY_LOG_D(@"updateSessionPeriod : %lu", (unsigned long)self.updateSessionPeriod);
    CLY_LOG_D(@"eventSendThreshold : %lu", (unsigned long)self.eventSendThreshold);
    CLY_LOG_D(@"storedRequestsLimit : %lu", (unsigned long)self.eventSendThreshold);
    
    CLY_LOG_D(@"views : %@", self.views ? @"YES" : @"NO");
    CLY_LOG_D(@"crashes : %@", self.crashes ? @"YES" : @"NO");
    CLY_LOG_D(@"tracking : %@", self.tracking ? @"YES" : @"NO");
    CLY_LOG_D(@"networking : %@", self.networking ? @"YES" : @"NO");
}

- (void)fetchServerConfig
{
    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
        return;
    
    NSURLSessionTask* task = [NSURLSession.sharedSession dataTaskWithRequest:[self serverConfigRequest] completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
                              {
        NSDictionary *serverConfigResponse = nil;
        
        if (!error)
        {
            serverConfigResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            CLY_LOG_D(@"%@", serverConfigResponse.description);
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
        
        NSDictionary* serverConfigObject = serverConfigResponse[@"c"];
        if(serverConfigObject) {
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
}

#endif
@end
