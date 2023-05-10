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

@synthesize trackingEnabled = _trackingEnabled;
@synthesize networkingEnabled = _networkingEnabled;

#if (TARGET_OS_IOS)
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
        self.trackingEnabled = YES;
        self.networkingEnabled = YES;
        NSDictionary* serverConfigObject = [CountlyPersistency.sharedInstance retrieveServerConfig];
        if(serverConfigObject) {
            [self populateServerConfig:serverConfigObject];
        }
    }
    
    return self;
}

- (BOOL)trackingEnabled
{
    if (!CountlyCommon.sharedInstance.enableServerConfiguration)
        return YES;
    
    return _trackingEnabled;
}

- (BOOL)networkingEnabled
{
    if (!CountlyCommon.sharedInstance.enableServerConfiguration)
        return YES;
    
    return _networkingEnabled;
}

- (void)populateServerConfig:(NSDictionary *)dictionary
{
    if(dictionary[@"tracking"])
    {
        self.trackingEnabled = [dictionary[@"tracking"] boolValue];
    }
    if(dictionary[@"networking"])
    {
        self.networkingEnabled = [dictionary[@"networking"] boolValue];
    }
    
    CLY_LOG_D(@"tracking : %@", self.trackingEnabled ? @"YES" : @"NO");
    CLY_LOG_D(@"networking : %@", self.networkingEnabled ? @"YES" : @"NO");
}

- (void)fetchServerConfig
{
    CLY_LOG_D(@"Fetching server configs...");
    if (!CountlyCommon.sharedInstance.enableServerConfiguration)
    {
        CLY_LOG_D(@"'fetchServerConfig' enable server configuration during init time configuration.");
        return;
    }
    
    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
        return;
    
    NSURLSessionTask* task = [NSURLSession.sharedSession dataTaskWithRequest:[self serverConfigRequest] completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
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
    
    CLY_LOG_D(@"serverConfigRequest URL :%@", URL);
}

#endif
@end
