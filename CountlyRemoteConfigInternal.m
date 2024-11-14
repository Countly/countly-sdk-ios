// CountlyLocationManager.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

NSString* const kCountlyRCKeyFetchRemoteConfig  = @"fetch_remote_config";
NSString* const kCountlyRCKeyFetchVariant       = @"ab_fetch_variants";
NSString* const kCountlyRCKeyEnrollVariant      = @"ab_enroll_variant";
NSString* const kCountlyRCKeyFetchExperiments   = @"ab_fetch_experiments";
NSString* const kCountlyRCKeyVariant            = @"variant";
NSString* const kCountlyRCKeyKey                = @"key";
NSString* const kCountlyRCKeyKeys               = @"keys";
NSString* const kCountlyRCKeyOmitKeys           = @"omit_keys";

NSString* const kCountlyRCKeyRC                 = @"rc";
NSString* const kCountlyRCKeyAutoOptIn          = @"oi";


CLYRequestResult const CLYResponseNetworkIssue  = @"CLYResponseNetworkIssue";
CLYRequestResult const CLYResponseSuccess       = @"CLYResponseSuccess";
CLYRequestResult const CLYResponseError         = @"CLYResponseError";

@interface CountlyRemoteConfigInternal ()
@property (nonatomic) NSDictionary* localCachedVariants;
@property (nonatomic) NSDictionary<NSString *, CountlyRCData *>* cachedRemoteConfig;
@property (nonatomic) NSDictionary<NSString*, CountlyExperimentInformation*> * localCachedExperiments;
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
        self.cachedRemoteConfig = [CountlyPersistency.sharedInstance retrieveRemoteConfig];
        if(!self.cachedRemoteConfig) {
            self.cachedRemoteConfig = NSMutableDictionary.new;
        }
        
        self.remoteConfigGlobalCallbacks = [[NSMutableArray alloc] init];
        
        self.localCachedExperiments = NSMutableDictionary.new;
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
            CLY_LOG_D(@"%s, Fetching remote config on start is successful. %@", __FUNCTION__, remoteConfig);
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
            CLY_LOG_D(@"%s, Fetching remote config manually is successful. %@", __FUNCTION__, remoteConfig);
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
    if (countlyRCValue) {
        return countlyRCValue.value;
    }
    return nil;
}

- (void)clearCachedRemoteConfig
{
    CLY_LOG_D(@"'clearCachedRemoteConfig' will cache or erase all remote config values.");
    if (!self.isRCValueCachingEnabled)
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
    CLY_LOG_D(@"'clearAll' will erase all remote config values.");
    self.cachedRemoteConfig = NSMutableDictionary.new;
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
    NSURLSessionTask* task = [CountlyCommon.sharedInstance.URLSession dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
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
            CLY_LOG_D(@"%s, Remote Config Request:[ %p ] failed! error:[ %@ ]", __FUNCTION__, request, error);
            
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
    
    CLY_LOG_D(@"%s, Remote Config Request <%p> started: [%@] %@", __FUNCTION__, (id)request, request.HTTPMethod, request.URL.absoluteString);
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
    
    if (self.enrollABOnRCDownload) {
        queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyRCKeyAutoOptIn, @"1"];
    }
    
    if (CountlyConsentManager.sharedInstance.consentForSessions)
    {
        queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyQSKeyMetrics, [CountlyDeviceInfo metrics]];
    }
    
    queryString = [queryString stringByAppendingFormat:@"&%@=%@",
                   kCountlyAppVersionKey, CountlyDeviceInfo.appVersion];
    
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
    CountlyRCData *countlyRCData = self.cachedRemoteConfig[key];
    if (!countlyRCData) {
        countlyRCData = [[CountlyRCData alloc] initWithValue:nil isCurrentUsersData:YES];
    }
    return countlyRCData;
}

- (NSDictionary<NSString*, CountlyRCData *> *)getAllValues
{
    return self.cachedRemoteConfig;
}

- (CountlyRCData *)getValueAndEnroll:(NSString *)key
{
    CountlyRCData *countlyRCData = [self getValue:key];
    if (countlyRCData.value) {
        [self enrollIntoABTestsForKeys:@[key]];
    }
    else {
        CLY_LOG_D(@"No value exists against key: %@ to enroll in AB testing", key);
    }
    return countlyRCData;
}

- (NSDictionary<NSString*, CountlyRCData *> *)getAllValuesAndEnroll
{
    if (self.cachedRemoteConfig && self.cachedRemoteConfig.count > 0) {
        [self enrollIntoABTestsForKeys: self.cachedRemoteConfig.allKeys];
    }
    else {
        CLY_LOG_D(@"No values exists to enroll in AB testing...");
    }
    return self.cachedRemoteConfig;
}

- (void)enrollIntoABTestsForKeys:(NSArray *)keys
{
    if (!CountlyConsentManager.sharedInstance.consentForRemoteConfig)
        return;
    
    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
        return;
    
    
    CLY_LOG_D(@"Entolling in AB Tests...");
    
    [CountlyConnectionManager.sharedInstance sendEnrollABRequestForKeys:keys];
}

- (void)exitABTestsForKeys:(NSArray *)keys
{
    if (!CountlyConsentManager.sharedInstance.consentForRemoteConfig)
        return;
    
    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
        return;
    
    
    CLY_LOG_D(@"Exiting AB Tests...");
    
    [CountlyConnectionManager.sharedInstance sendExitABRequestForKeys:keys];
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
            CLY_LOG_D(@"%s, fetching remote config is successful. %@", __FUNCTION__, remoteConfig);
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
    CLY_LOG_D(@"'updateMetaStateToCache' will cache all remote config values.");
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
            CLY_LOG_D(@"%s, Fetching variants manually is successful. %@", __FUNCTION__, varaints);
            
        }
        else
        {
            CLY_LOG_W(@"%s, Fetching variants manually failed: %@", __FUNCTION__, error);
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
    NSURLSessionTask* task = [CountlyCommon.sharedInstance.URLSession dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
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
                    if ([valueType isEqualToString:@"__NSDictionaryI"]) {
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
            CLY_LOG_D(@"%s, Fetch variants Request <%p> failed! Error: %@", __FUNCTION__, request, error);
            
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
    
    CLY_LOG_D(@"%s, Fetch variants Request <%p> started [%@] %@", __FUNCTION__, (id)request, request.HTTPMethod, request.URL.absoluteString);
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
    
    if (!key) {
        CLY_LOG_D(@"'enrollInRCVariant' is aborted: 'key' is not valid");
        return;
    }
    
    if (!variantName) {
        CLY_LOG_D(@"'enrollInRCVariant' is aborted: 'variantName' is not valid");
        return;
    }
    
    NSURLRequest* request = [self enrollInVarianRequestForKey:key variantName:variantName];
    NSURLSessionTask* task = [CountlyCommon.sharedInstance.URLSession dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
    {
        NSDictionary* variants = nil;
        [self clearCachedRemoteConfig];
        if (!error)
        {
            variants = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            if (((NSHTTPURLResponse*)response).statusCode != 200)
            {
                NSMutableDictionary* userInfo = variants.mutableCopy;
                userInfo[NSLocalizedDescriptionKey] = @"Enroll In RC Variant general API error";
                error = [NSError errorWithDomain:kCountlyErrorDomain code:CLYErrorRemoteConfigGeneralAPIError userInfo:userInfo];
            }
        }
        
        if (error)
        {
            CLY_LOG_D(@"%s, Enroll RC Variant Request <%p> failed! Error: %@", __FUNCTION__, request, error);
            
            dispatch_async(dispatch_get_main_queue(), ^
                           {
                completionHandler(CLYResponseError, error);
            });
            
            return;
        }
        
        
        CLY_LOG_D(@"Enroll RC Variant Request <%p> successfully completed.", request);
        
        [self downloadRemoteConfigAutomatically];
        
    }];
    
    [task resume];
    
    CLY_LOG_D(@"%s, Fetch variants Request <%p> started: [%@] %@", __FUNCTION__, (id)request, request.HTTPMethod, request.URL.absoluteString);
}

- (NSURLRequest *)downloadVariantsRequest
{
    NSString* queryString = [CountlyConnectionManager.sharedInstance queryEssentials];
    
    queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyQSKeyMethod, kCountlyRCKeyFetchVariant];
    
    queryString = [queryString stringByAppendingFormat:@"&%@=%@",
                   kCountlyAppVersionKey, CountlyDeviceInfo.appVersion];
    
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

- (void) testingDownloadExperimentInformation:(RCVariantCallback)completionHandler
{
    if (!CountlyConsentManager.sharedInstance.consentForRemoteConfig)
    {
        CLY_LOG_D(@"'testingDownloadExperimentInformation' is aborted: RemoteConfig consent requires");
        return;
    }
    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
    {
        CLY_LOG_D(@"'testingDownloadExperimentInformation' is aborted: Due to temporary device id");
        return;
    }
    
    CLY_LOG_D(@"Download experiments info...");
    
    [self testingDownloaExperimentInfoInternal:^(CLYRequestResult response, NSDictionary *experimentInfo,NSError *error)
     {
        if (!error)
        {
            self.localCachedExperiments = experimentInfo;
            CLY_LOG_D(@"%s, Download experiments info is successful. %@", __FUNCTION__,experimentInfo);
            
        }
        else
        {
            CLY_LOG_W(@"Download experiments info failed: %@", error);
        }
        
        if (completionHandler)
            completionHandler(response, error);
    }];
}


- (void)testingDownloaExperimentInfoInternal:(void (^)(CLYRequestResult response, NSDictionary* experimentsInfo, NSError * error))completionHandler
{
    if (!CountlyServerConfig.sharedInstance.networkingEnabled)
    {
        CLY_LOG_D(@"'testingDownloaExperimentInfoInternal' is aborted: SDK Networking is disabled from server config!");
        return;
    }
    if (!completionHandler)
        return;
    
    NSURLRequest* request = [self downloadExperimentInfoRequest];
    NSURLSessionTask* task = [CountlyCommon.sharedInstance.URLSession dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
                              {
        
        NSMutableDictionary<NSString*, CountlyExperimentInformation*> * experiments = NSMutableDictionary.new;
        
        if (!error)
        {
            
            NSArray* experimentsInfo = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            [experimentsInfo enumerateObjectsUsingBlock:^(NSDictionary* value, NSUInteger idx, BOOL * stop)
             {
                CountlyExperimentInformation* experimentInfo = [[CountlyExperimentInformation alloc] initWithID:value[@"id"] experimentName:value[@"name"] experimentDescription:value[@"description"] currentVariant:value[@"currentVariant"] variants:value[@"variants"]];
                experiments[experimentInfo.experimentID] = experimentInfo;
                
            }];
        }
        
        if (!error)
        {
            if (((NSHTTPURLResponse*)response).statusCode != 200)
            {
                NSMutableDictionary* userInfo = experiments.mutableCopy;
                userInfo[NSLocalizedDescriptionKey] = @"Fetch variants general API error";
                error = [NSError errorWithDomain:kCountlyErrorDomain code:CLYErrorRemoteConfigGeneralAPIError userInfo:userInfo];
            }
        }
        
        if (error)
        {
            CLY_LOG_D(@"%s, Download experiments Request <%p> failed! Error: %@", __FUNCTION__, request, error);
            
            dispatch_async(dispatch_get_main_queue(), ^
                           {
                completionHandler(CLYResponseError, nil, error);
            });
            
            return;
        }
        
        CLY_LOG_D(@"Download experiments Request <%p> successfully completed.", request);
        
        dispatch_async(dispatch_get_main_queue(), ^
                       {
            completionHandler(CLYResponseSuccess, experiments, nil);
        });
    }];
    
    [task resume];
    
    CLY_LOG_D(@"%s, Download experiments Request <%p> started: [%@] %@", __FUNCTION__, (id)request, request.HTTPMethod, request.URL.absoluteString);
}

- (NSURLRequest *)downloadExperimentInfoRequest
{
    NSString* queryString = [CountlyConnectionManager.sharedInstance queryEssentials];
    
    queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyQSKeyMethod, kCountlyRCKeyFetchExperiments];
    
    queryString = [queryString stringByAppendingFormat:@"&%@=%@",
                   kCountlyAppVersionKey, CountlyDeviceInfo.appVersion];
    
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
- (NSDictionary<NSString*, CountlyExperimentInformation*> *) testingGetAllExperimentInfo
{
    return self.localCachedExperiments;
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
    
    queryString = [queryString stringByAppendingFormat:@"&%@=%@",
                   kCountlyAppVersionKey, CountlyDeviceInfo.appVersion];
    
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
