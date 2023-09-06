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

NSString* const kCountlyRCKeyRC                 = @"rc";
NSString* const kCountlyRCKeyABOptIn            = @"ab";
NSString* const kCountlyRCKeyABOptOut           = @"ab_opt_out";
NSString* const kCountlyRCKeyAutoOptIn          = @"oi";


CLYRequestResult const CLYResponseNetworkIssue  = @"CLYResponseNetworkIssue";
CLYRequestResult const CLYResponseSuccess       = @"CLYResponseSuccess";
CLYRequestResult const CLYResponseError         = @"CLYResponseError";

@interface CountlyRemoteConfigInternal ()
@property (nonatomic) NSDictionary* localCachedVariants;
@property (nonatomic) NSDictionary<NSString *, CountlyRCData *>* cachedRemoteConfig;
@end

@implementation CountlyRemoteConfigInternal

+ (instancetype)sharedInstance
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return nil;
    
    static CountlyRemoteConfigInternal* s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    if (self = [super init])
    {
        self.cachedRemoteConfig = [CountlyPersistency.sharedInstance retrieveRemoteConfig] ;
        
        self.remoteConfigGlobalCallbacks = [[NSMutableArray alloc] init];
    }
    
    return self;
}

#pragma mark ---

- (void)startRemoteConfig
{
    if (!self.isRCAutomaticTriggersEnabled)
        return;
    
    if (!CountlyConsentManager.sharedInstance.consentForRemoteConfig)
        return;
    
    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
        return;
    
    CLY_LOG_D(@"Fetching remote config on start...");
    
    [self fetchRemoteConfigForKeys:nil omitKeys:nil isLegacy:NO completionHandler:^(NSDictionary *remoteConfig, NSError *error)
     {
        if (!error)
        {
            CLY_LOG_D(@"Fetching remote config on start is successful. \n%@", remoteConfig);
            self.cachedRemoteConfig = [self createRCMeta:remoteConfig];
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

- (void)downloadRemoteConfigAutomatically
{
    if (!self.isRCAutomaticTriggersEnabled)
        return;
    
    if (!CountlyConsentManager.sharedInstance.consentForRemoteConfig)
        return;
    
    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
        return;
    
    CLY_LOG_D(@"Fetching remote config on start...");
    
    [self downloadValuesForKeys:nil omitKeys:nil completionHandler:^(CLYRequestResult  _Nonnull response, NSError * _Nonnull error, BOOL fullValueUpdate, NSDictionary<NSString *,CountlyRCData *> * _Nonnull downloadedValues)
     {
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
    
    [self fetchRemoteConfigForKeys:keys omitKeys:omitKeys isLegacy:YES completionHandler:^(NSDictionary *remoteConfig, NSError *error)
     {
        if (!error)
        {
            CLY_LOG_D(@"Fetching remote config manually is successful. \n%@", remoteConfig);
            NSDictionary* remoteConfigMeta = [self createRCMeta:remoteConfig];
            if (!keys && !omitKeys)
            {
                self.cachedRemoteConfig = remoteConfigMeta;
            }
            else
            {
                NSMutableDictionary* partiallyUpdatedRemoteConfigMeta = self.cachedRemoteConfig.mutableCopy;
                [partiallyUpdatedRemoteConfigMeta addEntriesFromDictionary:remoteConfigMeta];
                self.cachedRemoteConfig = [NSDictionary dictionaryWithDictionary:partiallyUpdatedRemoteConfigMeta];
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
    CountlyRCData* countlyRCValue = self.cachedRemoteConfig[key];
    if(countlyRCValue) {
        return countlyRCValue.value;
    }
    return nil;
}

- (void)clearCachedRemoteConfig
{
    if(!self.isRCValueCachingEnabled)
    {
        [self clearAll];
    }
    else
    {
        [self updateMetaStateToCache];
    }
}

-(void)clearAll
{
    self.cachedRemoteConfig = nil;
    [CountlyPersistency.sharedInstance storeRemoteConfig:self.cachedRemoteConfig];
}

#pragma mark ---

- (void)fetchRemoteConfigForKeys:(NSArray *)keys omitKeys:(NSArray *)omitKeys  isLegacy:(BOOL)isLegacy completionHandler:(void (^)(NSDictionary* remoteConfig, NSError * error))completionHandler
{
    if (!CountlyServerConfig.sharedInstance.networkingEnabled)
    {
        CLY_LOG_D(@"'fetchRemoteConfigForKeys' is aborted: SDK Networking is disabled from server config!");
        return;
    }
    if (!completionHandler)
        return;
    
    NSURLRequest* request = [self remoteConfigRequestForKeys:keys omitKeys:omitKeys isLegacy:isLegacy];
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

- (NSURLRequest *)remoteConfigRequestForKeys:(NSArray *)keys omitKeys:(NSArray *)omitKeys isLegacy:(BOOL)isLegacy
{
    NSString* queryString = [CountlyConnectionManager.sharedInstance queryEssentials];
    
    queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyQSKeyMethod,
                   isLegacy ? kCountlyRCKeyFetchRemoteConfig : kCountlyRCKeyRC];
    
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
    
    if(self.enrollABOnRCDownload) {
        queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyRCKeyAutoOptIn, @"1"];
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

- (CountlyRCData *)getValue:(NSString *)key
{
    return self.cachedRemoteConfig[key];
}

- (NSDictionary<NSString*, CountlyRCData *> *)getAllValues
{
    return self.cachedRemoteConfig;
}

- (void)enrollIntoABTestsForKeys:(NSArray *)keys
{
    if (!CountlyConsentManager.sharedInstance.consentForRemoteConfig)
        return;
    
    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
        return;
    
    
    CLY_LOG_D(@"Entolling in AB Tests...");
    
    [self enrollExitABForKeys:keys enroll:YES];
    
}

- (void)exitABTestsForKeys:(NSArray *)keys
{
    if (!CountlyConsentManager.sharedInstance.consentForRemoteConfig)
        return;
    
    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
        return;
    
    
    CLY_LOG_D(@"Exiting AB Tests...");
    
    [self enrollExitABForKeys:keys enroll:NO];
}

- (void)downloadValuesForKeys:(NSArray *)keys omitKeys:(NSArray *)omitKeys completionHandler:(RCDownloadCallback)completionHandler
{
    if (!CountlyConsentManager.sharedInstance.consentForRemoteConfig)
        return;
    
    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
        return;
    
    CLY_LOG_D(@"Fetching remote config...");
    
    [self fetchRemoteConfigForKeys:keys omitKeys:omitKeys isLegacy:NO completionHandler:^(NSDictionary *remoteConfig, NSError *error)
     {
        BOOL fullValueUpdate = false;
        NSDictionary* remoteConfigMeta = remoteConfig ? [self createRCMeta:remoteConfig] : @{};
        CLYRequestResult requestResult = CLYResponseSuccess;
        if (!error)
        {
            CLY_LOG_D(@"Fetching remote config is successful. \n%@", remoteConfig);
//            NSDictionary* remoteConfigMeta = [self createRCMeta:remoteConfig];
            if (!keys && !omitKeys)
            {
                fullValueUpdate = true;
                self.cachedRemoteConfig = remoteConfigMeta;
            }
            else
            {
                NSMutableDictionary* partiallyUpdatedRemoteConfigMeta = self.cachedRemoteConfig.mutableCopy;
                [partiallyUpdatedRemoteConfigMeta addEntriesFromDictionary:remoteConfigMeta];
                self.cachedRemoteConfig = [NSDictionary dictionaryWithDictionary:partiallyUpdatedRemoteConfigMeta];
            }
            
            [CountlyPersistency.sharedInstance storeRemoteConfig:self.cachedRemoteConfig];
            
            
        }
        else
        {
            requestResult = CLYResponseError;
            CLY_LOG_W(@"Fetching remote config failed: %@", error);
        }
        
        if (completionHandler)
            completionHandler(requestResult, error, fullValueUpdate, remoteConfigMeta);
        
        
        [self.remoteConfigGlobalCallbacks enumerateObjectsUsingBlock:^(RCDownloadCallback callback, NSUInteger idx, BOOL * stop)
         {
            callback(requestResult, error, fullValueUpdate, remoteConfigMeta);
        }];
        
        
    }];
}

- (NSDictionary *) createRCMeta:(NSDictionary *) remoteConfig
{
    NSMutableDictionary<NSString *, CountlyRCData *>* remoteConfigMeta = [[NSMutableDictionary alloc] init];
    [remoteConfig enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * value, BOOL * stop)
     {
        remoteConfigMeta[key] = [[CountlyRCData alloc] initWithValue:value isCurrentUsersData:YES];
        
    }];
    
    return  remoteConfigMeta;
}

- (void)updateMetaStateToCache
{
    [self.cachedRemoteConfig enumerateKeysAndObjectsUsingBlock:^(NSString * key, CountlyRCData * countlyRCMeta, BOOL * stop)
     {
        countlyRCMeta.isCurrentUsersData = NO;
        
    }];
    
    [CountlyPersistency.sharedInstance storeRemoteConfig:self.cachedRemoteConfig];
}

-(void)registerDownloadCallback:(RCDownloadCallback) callback
{
    [self.remoteConfigGlobalCallbacks addObject:callback];
}
-(void)removeDownloadCallback:(RCDownloadCallback) callback
{
    [self.remoteConfigGlobalCallbacks removeObject:callback];
}

- (NSDictionary *)testingGetAllVariants
{
    return self.localCachedVariants;
}

- (NSDictionary *)testingGetVariantsForKey:(NSString *)key
{
    return  self.localCachedVariants[key];
}

- (void)testingDownloadAllVariants:(RCVariantCallback)completionHandler
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
    
    [self testingDownloadAllVariantsInternal:^(CLYRequestResult response, NSDictionary *varaints,NSError *error)
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

- (void)testingDownloadAllVariantsInternal:(void (^)(CLYRequestResult response, NSDictionary* variants, NSError * error))completionHandler
{
    if (!CountlyServerConfig.sharedInstance.networkingEnabled)
    {
        CLY_LOG_D(@"'fetchVariantForKeys' is aborted: SDK Networking is disabled from server config!");
        return;
    }
    if (!completionHandler)
        return;
    
    NSURLRequest* request = [self downloadVariantsRequest];
    NSURLSessionTask* task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
                              {
        NSMutableDictionary* variants = NSMutableDictionary.new;
        
        if (!error)
        {
            NSDictionary* variants_ = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            [variants_ enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSArray* value, BOOL * stop)
             {
                NSMutableArray<NSString*>* valuesArray = NSMutableArray.new;
                [value enumerateObjectsUsingBlock:^(id arrayValue, NSUInteger idx, BOOL * stop)
                 {
                    
                    NSString *valueType = NSStringFromClass([arrayValue class]);
                    if([valueType isEqualToString:@"__NSDictionaryI"]) {
                        [valuesArray addObject:arrayValue[@"name"]];
                    }
                    else {
                        [valuesArray addObject:arrayValue];
                    }
                }];
                variants[key] = valuesArray;
            }];
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
    
    [self testingEnrollIntoVariantInternal:key variantName:variantName completionHandler:^(CLYRequestResult response, NSError *error)
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

- (NSURLRequest *)downloadVariantsRequest
{
    NSString* queryString = [CountlyConnectionManager.sharedInstance queryEssentials];
    
    queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyQSKeyMethod, kCountlyRCKeyFetchVariant];
    
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

- (void)enrollExitABForKeys:(NSArray *)keys enroll:(BOOL)enroll
{
    if (!CountlyServerConfig.sharedInstance.networkingEnabled)
    {
        CLY_LOG_D(@"'%@' is aborted: SDK Networking is disabled from server config!", enroll ? @"enrollABTestForKeys" : @"exitABTestForKeys");
        return;
    }
    
    NSURLRequest* request = enroll ? [self enrollABRequestForKeys:keys] : [self exitABRequestForKeys:keys];
    NSURLSessionTask* task = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
                              {
        
        if (error)
        {
            CLY_LOG_D(@"%@ Request <%p> failed!\nError: %@", enroll ? @"enrollABTestForKeys" : @"exitABTestForKeys", request, error);
        }
        else
        {
            CLY_LOG_D(@"%@ Request <%p> successfully completed.", enroll ? @"enrollABTestForKeys" : @"exitABTestForKeys", request);
        }
        
    }];
    
    [task resume];
    
    CLY_LOG_D(@"%@ Request <%p> started:\n[%@] %@", enroll ? @"enrollABTestForKeys" : @"exitABTestForKeys", (id)request, request.HTTPMethod, request.URL.absoluteString);
}

- (NSURLRequest *)enrollABRequestForKeys:(NSArray*)keys
{
    return [self aBRequestForMethod:kCountlyRCKeyABOptIn keys:keys];
}

- (NSURLRequest *)exitABRequestForKeys:(NSArray*)keys
{
    return [self aBRequestForMethod:kCountlyRCKeyABOptOut keys:keys];
}

- (NSURLRequest *)aBRequestForMethod:(NSString*)method keys:(NSArray*)keys
{
    NSString* queryString = [CountlyConnectionManager.sharedInstance queryEssentials];
    
    queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyQSKeyMethod, kCountlyRCKeyABOptIn];
    
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

@end
