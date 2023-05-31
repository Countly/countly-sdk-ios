// CountlyLocationManager.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

NSString* const kCountlyRCKeyFetchRemoteConfig  = @"fetch_remote_config";
NSString* const kCountlyRCKeyFetchVariant       = @"ab_fetch_variants";
NSString* const kCountlyRCKeyEnrollVariant      = @"ab_enroll_variant";
NSString* const kCountlyRCKeyVariant            = @"variant";
NSString* const kCountlyRCKeyKey                = @"key";
NSString* const kCountlyRCKeyKeys               = @"keys";
NSString* const kCountlyRCKeyOmitKeys           = @"omit_keys";


CLYResponse const CLYResponseNetworkIssue       = @"CLYResponseNetworkIssue";
CLYResponse const CLYResponseSuccess            = @"CLYResponseSuccess";
CLYResponse const CLYResponseError              = @"CLYResponseError";

@interface CountlyRemoteConfig ()
@property (nonatomic) NSDictionary* cachedRemoteConfig;
@property (nonatomic) NSDictionary* localCachedVariants;
@end

@implementation CountlyRemoteConfig

+ (instancetype)sharedInstance
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return nil;

    static CountlyRemoteConfig* s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    if (self = [super init])
    {
        self.cachedRemoteConfig = [CountlyPersistency.sharedInstance retrieveRemoteConfig];
    }

    return self;
}

#pragma mark ---

- (void)startRemoteConfig
{
    if (!self.isEnabledOnInitialConfig)
        return;

    if (!CountlyConsentManager.sharedInstance.consentForRemoteConfig)
        return;

    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
        return;

    CLY_LOG_D(@"Fetching remote config on start...");

    [self fetchRemoteConfigForKeys:nil omitKeys:nil completionHandler:^(NSDictionary *remoteConfig, NSError *error)
    {
        if (!error)
        {
            CLY_LOG_D(@"Fetching remote config on start is successful. \n%@", remoteConfig);

            self.cachedRemoteConfig = remoteConfig;
            [CountlyPersistency.sharedInstance storeRemoteConfig:self.cachedRemoteConfig];
        }
        else
        {
            CLY_LOG_W(@"Fetching remote config on start failed: %@", error);
        }

        if (self.remoteConfigCompletionHandler)
            self.remoteConfigCompletionHandler(error);
    }];
}

- (void)updateRemoteConfigForKeys:(NSArray *)keys omitKeys:(NSArray *)omitKeys completionHandler:(void (^)(NSError * error))completionHandler
{
    if (!CountlyConsentManager.sharedInstance.consentForRemoteConfig)
        return;

    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
        return;

    CLY_LOG_D(@"Fetching remote config manually...");

    [self fetchRemoteConfigForKeys:keys omitKeys:omitKeys completionHandler:^(NSDictionary *remoteConfig, NSError *error)
    {
        if (!error)
        {
            CLY_LOG_D(@"Fetching remote config manually is successful. \n%@", remoteConfig);

            if (!keys && !omitKeys)
            {
                self.cachedRemoteConfig = remoteConfig;
            }
            else
            {
                NSMutableDictionary* partiallyUpdatedRemoteConfig = self.cachedRemoteConfig.mutableCopy;
                [partiallyUpdatedRemoteConfig addEntriesFromDictionary:remoteConfig];
                self.cachedRemoteConfig = [NSDictionary dictionaryWithDictionary:partiallyUpdatedRemoteConfig];
            }

            [CountlyPersistency.sharedInstance storeRemoteConfig:self.cachedRemoteConfig];
        }
        else
        {
            CLY_LOG_W(@"Fetching remote config manually failed: %@", error);
        }

        if (completionHandler)
            completionHandler(error);
    }];
}

- (id)remoteConfigValueForKey:(NSString *)key
{
    return self.cachedRemoteConfig[key];
}

- (void)clearCachedRemoteConfig
{
    self.cachedRemoteConfig = nil;
    [CountlyPersistency.sharedInstance storeRemoteConfig:self.cachedRemoteConfig];
}

#pragma mark ---

- (void)fetchRemoteConfigForKeys:(NSArray *)keys omitKeys:(NSArray *)omitKeys completionHandler:(void (^)(NSDictionary* remoteConfig, NSError * error))completionHandler
{
    if (!CountlyServerConfig.sharedInstance.networkingEnabled)
    {
        CLY_LOG_D(@"'fetchRemoteConfigForKeys' is aborted: SDK Networking is disabled from server config!");
        return;
    }
    if (!completionHandler)
        return;

    NSURLRequest* request = [self remoteConfigRequestForKeys:keys omitKeys:omitKeys];
    NSURLSessionTask* task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
    {
        NSDictionary* remoteConfig = nil;

        if (!error)
        {
            remoteConfig = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        }

        if (!error)
        {
            if (((NSHTTPURLResponse*)response).statusCode != 200)
            {
                NSMutableDictionary* userInfo = remoteConfig.mutableCopy;
                userInfo[NSLocalizedDescriptionKey] = @"Remote config general API error";
                error = [NSError errorWithDomain:kCountlyErrorDomain code:CLYErrorRemoteConfigGeneralAPIError userInfo:userInfo];
            }
        }

        if (error)
        {
            CLY_LOG_D(@"Remote Config Request <%p> failed!\nError: %@", request, error);

            dispatch_async(dispatch_get_main_queue(), ^
            {
                completionHandler(nil, error);
            });

            return;
        }

        CLY_LOG_D(@"Remote Config Request <%p> successfully completed.", request);

        dispatch_async(dispatch_get_main_queue(), ^
        {
            completionHandler(remoteConfig, nil);
        });
    }];

    [task resume];

    CLY_LOG_D(@"Remote Config Request <%p> started:\n[%@] %@", (id)request, request.HTTPMethod, request.URL.absoluteString);
}

- (NSURLRequest *)remoteConfigRequestForKeys:(NSArray *)keys omitKeys:(NSArray *)omitKeys
{
    NSString* queryString = [CountlyConnectionManager.sharedInstance queryEssentials];

    queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyQSKeyMethod, kCountlyRCKeyFetchRemoteConfig];

    if (keys)
    {
        queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyRCKeyKeys, [keys cly_JSONify]];
    }
    else if (omitKeys)
    {
        queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyRCKeyOmitKeys, [omitKeys cly_JSONify]];
    }

    if (CountlyConsentManager.sharedInstance.consentForSessions)
    {
        queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyQSKeyMetrics, [CountlyDeviceInfo metrics]];
    }

    queryString = [CountlyConnectionManager.sharedInstance appendChecksum:queryString];

    NSString* serverOutputSDKEndpoint = [CountlyConnectionManager.sharedInstance.host stringByAppendingFormat:@"%@%@",
                                         kCountlyEndpointO,
                                         kCountlyEndpointSDK];

    if (CountlyConnectionManager.sharedInstance.alwaysUsePOST)
    {
        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:serverOutputSDKEndpoint]];
        request.HTTPMethod = @"POST";
        request.HTTPBody = [queryString cly_dataUTF8];
        return request.copy;
    }
    else
    {
        NSString* withQueryString = [serverOutputSDKEndpoint stringByAppendingFormat:@"?%@", queryString];
        NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:withQueryString]];
        return request;
    }
}

- (NSDictionary *)testingGetAllVariants
{
    return self.localCachedVariants;
}

- (NSDictionary *)testingGetVariantsForKey:(NSString *)key {
    return  self.localCachedVariants[key];
}

- (void)testingFetchVariantsForKeys:(NSArray *)keys completionHandler:(RCVariantCallback)completionHandler
{
    if (!CountlyConsentManager.sharedInstance.consentForRemoteConfig)
    {
        CLY_LOG_D(@"'fetchVariantForKeys' is aborted: RemoteConfig consent requires");
        return;
    }
    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
    {
        CLY_LOG_D(@"'fetchVariantForKeys' is aborted: Due to temporary device id");
        return;
    }
    
    CLY_LOG_D(@"Fetching variants manually...");
    
    [self testingGetVariantsForKeyInternal:keys completionHandler:^(CLYResponse response, NSDictionary *varaints,NSError *error)
     {
        if (!error)
        {
            self.localCachedVariants = varaints;
            CLY_LOG_D(@"Fetching variants manually is successful. \n%@", varaints);
            
        }
        else
        {
            CLY_LOG_W(@"Fetching variants manually failed: %@", error);
        }
        
        if (completionHandler)
            completionHandler(response, error);
    }];
}

- (void)testingGetVariantsForKeyInternal:(NSArray *)keys completionHandler:(void (^)(CLYResponse response, NSDictionary* variants, NSError * error))completionHandler
{
    if (!CountlyServerConfig.sharedInstance.networkingEnabled)
    {
        CLY_LOG_D(@"'fetchVariantForKeys' is aborted: SDK Networking is disabled from server config!");
        return;
    }
    if (!completionHandler)
        return;
    
    NSURLRequest* request = [self fetchVariantsRequestForKeys:keys];
    NSURLSessionTask* task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
                              {
        NSDictionary* variants = nil;
        
        if (!error)
        {
            variants = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        }
        
        if (!error)
        {
            if (((NSHTTPURLResponse*)response).statusCode != 200)
            {
                NSMutableDictionary* userInfo = variants.mutableCopy;
                userInfo[NSLocalizedDescriptionKey] = @"Fetch variants general API error";
                error = [NSError errorWithDomain:kCountlyErrorDomain code:CLYErrorRemoteConfigGeneralAPIError userInfo:userInfo];
            }
        }
        
        if (error)
        {
            CLY_LOG_D(@"Fetch variants Request <%p> failed!\nError: %@", request, error);
            
            dispatch_async(dispatch_get_main_queue(), ^
                           {
                completionHandler(CLYResponseError, nil, error);
            });
            
            return;
        }
        
        CLY_LOG_D(@"Fetch variants Request <%p> successfully completed.", request);
        
        dispatch_async(dispatch_get_main_queue(), ^
                       {
            completionHandler(CLYResponseSuccess, variants, nil);
        });
    }];
    
    [task resume];
    
    CLY_LOG_D(@"Fetch variants Request <%p> started:\n[%@] %@", (id)request, request.HTTPMethod, request.URL.absoluteString);
}

- (void)testingEnrollIntoVariant:(NSString *)key variantName:(NSString *)variantName completionHandler:(RCVariantCallback)completionHandler
{
    if (!CountlyConsentManager.sharedInstance.consentForRemoteConfig)
        return;
    
    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
        return;
    
    CLY_LOG_D(@"Enrolling RC variant");
    
    [self testingEnrollIntoVariantInternal:key variantName:variantName completionHandler:^(CLYResponse response, NSError *error)
     {
        if (!error)
        {
            CLY_LOG_D(@"Enrolling RC variant successful.");
            
        }
        else
        {
            CLY_LOG_W(@"Enrolling RC variant failed: %@", error);
        }
        
        if (completionHandler)
            completionHandler(response, error);
    }];
}

- (void)testingEnrollIntoVariantInternal:(NSString *)key variantName:(NSString *)variantName completionHandler:(RCVariantCallback)completionHandler
{
    if (!CountlyServerConfig.sharedInstance.networkingEnabled)
    {
        CLY_LOG_D(@"'enrollInRCVariant' is aborted: SDK Networking is disabled from server config!");
        return;
    }
    if (!completionHandler)
    {
        CLY_LOG_D(@"'enrollInRCVariant' is aborted: 'completionHandler' not provided");
        return;
    }
    
    if(!key) {
        CLY_LOG_D(@"'enrollInRCVariant' is aborted: 'key' is not valid");
        return;
    }
    
    if(!variantName) {
        CLY_LOG_D(@"'enrollInRCVariant' is aborted: 'variantName' is not valid");
        return;
    }
    
    NSURLRequest* request = [self enrollInVarianRequestForKey:key variantName:variantName];
    NSURLSessionTask* task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
                              {
        NSDictionary* variants = nil;
        
        if (!error)
        {
            variants = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        }
        
        if (!error)
        {
            if (((NSHTTPURLResponse*)response).statusCode != 200)
            {
                NSMutableDictionary* userInfo = variants.mutableCopy;
                userInfo[NSLocalizedDescriptionKey] = @"Enroll In RC Variant general API error";
                error = [NSError errorWithDomain:kCountlyErrorDomain code:CLYErrorRemoteConfigGeneralAPIError userInfo:userInfo];
            }
        }
        
        if (error)
        {
            CLY_LOG_D(@"Enroll RC Variant Request <%p> failed!\nError: %@", request, error);
            
            dispatch_async(dispatch_get_main_queue(), ^
                           {
                completionHandler(CLYResponseError, error);
            });
            
            return;
        }
        
        CLY_LOG_D(@"Enroll RC Variant Request <%p> successfully completed.", request);
        
        [self updateRemoteConfigForKeys:nil omitKeys:nil completionHandler:^(NSError *updateRCError) {
            dispatch_async(dispatch_get_main_queue(), ^
                           {
                completionHandler(CLYResponseSuccess, nil);
            });
        }];
       
    }];
    
    [task resume];
    
    CLY_LOG_D(@"Fetch variants Request <%p> started:\n[%@] %@", (id)request, request.HTTPMethod, request.URL.absoluteString);
}

- (NSURLRequest *)fetchVariantsRequestForKeys:(NSArray *)keys
{
    NSString* queryString = [CountlyConnectionManager.sharedInstance queryEssentials];
    
    queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyQSKeyMethod, kCountlyRCKeyFetchVariant];
    
    if (keys)
    {
        queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyRCKeyKeys, [keys cly_JSONify]];
    }
    
    if (CountlyConsentManager.sharedInstance.consentForSessions)
    {
        queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyQSKeyMetrics, [CountlyDeviceInfo metrics]];
    }
    
    queryString = [CountlyConnectionManager.sharedInstance appendChecksum:queryString];
    
    NSString* serverOutputSDKEndpoint = [CountlyConnectionManager.sharedInstance.host stringByAppendingFormat:@"%@%@",
                                         kCountlyEndpointO,
                                         kCountlyEndpointSDK];
    
    if (CountlyConnectionManager.sharedInstance.alwaysUsePOST)
    {
        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:serverOutputSDKEndpoint]];
        request.HTTPMethod = @"POST";
        request.HTTPBody = [queryString cly_dataUTF8];
        return request.copy;
    }
    else
    {
        NSString* withQueryString = [serverOutputSDKEndpoint stringByAppendingFormat:@"?%@", queryString];
        NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:withQueryString]];
        return request;
    }
}

- (NSURLRequest *)enrollInVarianRequestForKey:(NSString *)key variantName:(NSString *)variantName
{
    NSString* queryString = [CountlyConnectionManager.sharedInstance queryEssentials];
    
    queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyQSKeyMethod, kCountlyRCKeyEnrollVariant];
    queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyRCKeyKey, key];
    if (variantName)
    {
        queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyRCKeyVariant, variantName.cly_URLEscaped];
    }
    
    if (CountlyConsentManager.sharedInstance.consentForSessions)
    {
        queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyQSKeyMetrics, [CountlyDeviceInfo metrics]];
    }
    
    queryString = [CountlyConnectionManager.sharedInstance appendChecksum:queryString];
    
    NSString* serverOutputSDKEndpoint = [CountlyConnectionManager.sharedInstance.host stringByAppendingFormat:@"%@",
                                         kCountlyEndpointI];
    
    if (CountlyConnectionManager.sharedInstance.alwaysUsePOST)
    {
        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:serverOutputSDKEndpoint]];
        request.HTTPMethod = @"POST";
        request.HTTPBody = [queryString cly_dataUTF8];
        return request.copy;
    }
    else
    {
        NSString* withQueryString = [serverOutputSDKEndpoint stringByAppendingFormat:@"?%@", queryString];
        NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:withQueryString]];
        return request;
    }
}

@end
