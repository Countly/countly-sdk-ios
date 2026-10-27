// CountlyLocationManager.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

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

static CountlyRemoteConfigInternal* s_sharedInstance = nil;
static dispatch_once_t onceToken;

+ (instancetype)sharedInstance
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return nil;
    
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (void)resetInstance
{
    CLY_LOG_I(@"%s", __FUNCTION__);
    onceToken = 0;
    s_sharedInstance = nil;
}

/// Hands a response to its completion handler on the main thread, unless the SDK was halted after the request was made.
- (void)deliverOnMainUnlessHalted:(dispatch_block_t)delivery
{
    dispatch_async(dispatch_get_main_queue(), ^
    {
        if (self != s_sharedInstance)
        {
            CLY_LOG_D(@"%s a response arrived after halt, it is ignored", __FUNCTION__);
            return;
        }

        delivery();
    });
}

- (instancetype)init
{
    if (self = [super init])
    {
        self.cachedRemoteConfig = [CountlyPersistency.sharedInstance retrieveRemoteConfig];
        if(!self.cachedRemoteConfig) {
            self.cachedRemoteConfig = NSMutableDictionary.new;
        }

        CLY_LOG_D(@"%s remote config cache is loaded from persistency, cachedKeyCount: [%lu]", __FUNCTION__, (unsigned long)self.cachedRemoteConfig.count);
        
        self.remoteConfigGlobalCallbacks = [[NSMutableArray alloc] init];
        
        self.localCachedExperiments = NSMutableDictionary.new;
    }
    
    return self;
}

#pragma mark ---

- (void)downloadRemoteConfigAutomatically
{
    if (!self.isRCAutomaticTriggersEnabled)
    {
        CLY_LOG_D(@"%s automatic triggers are disabled, automatic remote config download will be skipped", __FUNCTION__);
        return;
    }

    if (!CountlyConsentManager.sharedInstance.consentForRemoteConfig)
    {
        CLY_LOG_V(@"%s no consent for remote config, automatic download will be skipped", __FUNCTION__);
        return;
    }

    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
    {
        CLY_LOG_D(@"%s device ID is in temporary mode, automatic remote config download will be skipped", __FUNCTION__);
        return;
    }

    CLY_LOG_D(@"%s automatic remote config download is starting, fetchType: [full]", __FUNCTION__);

    [self downloadValuesForKeys:nil omitKeys:nil completionHandler:^(CLYRequestResult  _Nonnull response, NSError * _Nonnull error, BOOL fullValueUpdate, NSDictionary<NSString *,CountlyRCData *> * _Nonnull downloadedValues)
     {
        CLY_LOG_D(@"%s automatic remote config download finished, response: [%@], fullValueUpdate: [%@], downloadedValueCount: [%lu]", __FUNCTION__, response, fullValueUpdate ? @"YES" : @"NO", (unsigned long)downloadedValues.count);
        CLY_LOG_D(@"%s automatic remote config download payload detail, downloadedValues: [%@]", __FUNCTION__, downloadedValues);
    }];
    
}

- (void)clearCachedRemoteConfig
{
    CLY_LOG_D(@"%s cached remote config values will be [%@], valueCachingEnabled: [%@], cachedKeyCount: [%lu]", __FUNCTION__, self.isRCValueCachingEnabled ? @"marked as stale" : @"erased", self.isRCValueCachingEnabled ? @"YES" : @"NO", (unsigned long)self.cachedRemoteConfig.count);
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
    CLY_LOG_D(@"%s all remote config values will be erased, clearedKeyCount: [%lu]", __FUNCTION__, (unsigned long)self.cachedRemoteConfig.count);
    self.cachedRemoteConfig = NSMutableDictionary.new;
    [CountlyPersistency.sharedInstance storeRemoteConfig:self.cachedRemoteConfig];
}

#pragma mark ---

- (void)fetchRemoteConfigForKeys:(NSArray *)keys omitKeys:(NSArray *)omitKeys completionHandler:(void (^)(NSDictionary* remoteConfig, NSError * error))completionHandler
{
    if (!CountlyServerConfig.sharedInstance.networkingEnabled)
    {
        CLY_LOG_D(@"%s remote config fetch is aborted, reason: [networking is disabled from server config]", __FUNCTION__);
        return;
    }
    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
    {
        CLY_LOG_D(@"%s remote config fetch is aborted, reason: [device ID is in temporary mode]", __FUNCTION__);
        return;
    }
    if (!completionHandler)
    {
        CLY_LOG_E(@"%s remote config fetch is aborted, reason: [completionHandler is not provided]", __FUNCTION__);
        return;
    }

    NSURLRequest* request = [self remoteConfigRequestForKeys:keys omitKeys:omitKeys];
    NSURLSessionTask* task = [CountlyCommon.sharedInstance immediateDataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
                              {
        // IMMEDIATE REQUEST to find them better in search
        NSDictionary* remoteConfig = nil;
        
        if (!error)
        {
            remoteConfig = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        }

        if (!error && ![remoteConfig isKindOfClass:NSDictionary.class])
        {
            remoteConfig = nil;
            error = [NSError errorWithDomain:kCountlyErrorDomain code:CLYErrorRemoteConfigGeneralAPIError userInfo:@{NSLocalizedDescriptionKey: @"Remote config response is not a JSON object"}];
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
            CLY_LOG_D(@"%s remote config request failed, stage: [%@], statusCode: [%ld], error: [%@]", __FUNCTION__, data ? (remoteConfig ? @"API response" : @"JSON parsing") : @"network", (long)((NSHTTPURLResponse*)response).statusCode, error.localizedDescription);
            
            [self deliverOnMainUnlessHalted:^{
                completionHandler(nil, error);
            }];
            
            return;
        }
        
        CLY_LOG_D(@"%s remote config request successfully completed, statusCode: [%ld], keys: [%@], valueCount: [%lu]", __FUNCTION__, (long)((NSHTTPURLResponse*)response).statusCode, remoteConfig.allKeys, (unsigned long)remoteConfig.count);
        CLY_LOG_D(@"%s remote config response payload detail, remoteConfig: [%@]", __FUNCTION__, remoteConfig);
        
        [self deliverOnMainUnlessHalted:^{
            completionHandler(remoteConfig, nil);
        }];
    }];
    
    [task resume];
    
    CLY_LOG_D(@"%s remote config request is started, method: [%@], path: [%@], keyCount: [%lu], omitKeyCount: [%lu]", __FUNCTION__, request.HTTPMethod, request.URL.path, (unsigned long)keys.count, (unsigned long)omitKeys.count);
    CLY_LOG_D(@"%s remote config request URL detail, url: [%@]", __FUNCTION__, request.URL.absoluteString);
}

- (NSURLRequest *)remoteConfigRequestForKeys:(NSArray *)keys omitKeys:(NSArray *)omitKeys
{
    NSString* queryString = [CountlyConnectionManager.sharedInstance queryEssentials];
    
    queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyQSKeyMethod, kCountlyRCKeyRC];
    
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
    CLY_LOG_D(@"%s remote config value is read from cache, key: [%@], valueExists: [%@]", __FUNCTION__, key, (countlyRCData != nil) ? @"YES" : @"NO");
    if (!countlyRCData) {
        countlyRCData = [[CountlyRCData alloc] initWithValue:nil isCurrentUsersData:YES];
    }
    return countlyRCData;
}

- (NSDictionary<NSString*, CountlyRCData *> *)getAllValues
{
    CLY_LOG_D(@"%s all remote config values are read from cache, cachedKeyCount: [%lu]", __FUNCTION__, (unsigned long)self.cachedRemoteConfig.count);
    return self.cachedRemoteConfig;
}

- (CountlyRCData *)getValueAndEnroll:(NSString *)key
{
    CountlyRCData *countlyRCData = [self getValue:key];
    if (countlyRCData.value) {
        CLY_LOG_D(@"%s a value exists for the key, AB test enrollment will be requested, key: [%@]", __FUNCTION__, key);
        [self enrollIntoABTestsForKeys:@[key]];
    }
    else {
        CLY_LOG_D(@"%s no value exists for the key, AB test enrollment will be skipped, key: [%@]", __FUNCTION__, key);
    }
    return countlyRCData;
}

- (NSDictionary<NSString*, CountlyRCData *> *)getAllValuesAndEnroll
{
    if (self.cachedRemoteConfig && self.cachedRemoteConfig.count > 0) {
        CLY_LOG_D(@"%s AB test enrollment will be requested for all cached keys, cachedKeyCount: [%lu]", __FUNCTION__, (unsigned long)self.cachedRemoteConfig.count);
        [self enrollIntoABTestsForKeys: self.cachedRemoteConfig.allKeys];
    }
    else {
        CLY_LOG_D(@"%s no cached remote config values exist, AB test enrollment for all keys will be skipped", __FUNCTION__);
    }
    return self.cachedRemoteConfig;
}

- (void)enrollIntoABTestsForKeys:(NSArray *)keys
{
    if (!CountlyConsentManager.sharedInstance.consentForRemoteConfig)
    {
        CLY_LOG_V(@"%s no consent for remote config, AB test enrollment will be skipped", __FUNCTION__);
        return;
    }

    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
    {
        CLY_LOG_D(@"%s device ID is in temporary mode, AB test enrollment will be skipped", __FUNCTION__);
        return;
    }


    CLY_LOG_D(@"%s AB test enrollment request will be sent, keys: [%@], keyCount: [%lu]", __FUNCTION__, keys, (unsigned long)keys.count);
    
    [CountlyConnectionManager.sharedInstance sendEnrollABRequestForKeys:keys];
}

- (void)exitABTestsForKeys:(NSArray *)keys
{
    if (!CountlyConsentManager.sharedInstance.consentForRemoteConfig)
    {
        CLY_LOG_V(@"%s no consent for remote config, AB test exit will be skipped", __FUNCTION__);
        return;
    }

    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
    {
        CLY_LOG_D(@"%s device ID is in temporary mode, AB test exit will be skipped", __FUNCTION__);
        return;
    }


    CLY_LOG_D(@"%s AB test exit request will be sent, keys: [%@], keyCount: [%lu]", __FUNCTION__, keys, (unsigned long)keys.count);
    
    [CountlyConnectionManager.sharedInstance sendExitABRequestForKeys:keys];
}

- (void)downloadValuesForKeys:(NSArray *)keys omitKeys:(NSArray *)omitKeys completionHandler:(RCDownloadCallback)completionHandler
{
    if (!CountlyConsentManager.sharedInstance.consentForRemoteConfig)
    {
        CLY_LOG_V(@"%s no consent for remote config, value download will be skipped", __FUNCTION__);
        return;
    }

    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
    {
        CLY_LOG_D(@"%s device ID is in temporary mode, remote config value download will be skipped", __FUNCTION__);
        return;
    }

    CLY_LOG_D(@"%s remote config value download is starting, requestKind: [%@], fetchType: [%@], keys: [%@], keyCount: [%lu], omitKeys: [%@], omitKeyCount: [%lu], completionHandlerProvided: [%@]", __FUNCTION__, kCountlyRCKeyRC, (!keys && !omitKeys) ? @"full" : @"partial", keys, (unsigned long)keys.count, omitKeys, (unsigned long)omitKeys.count, (completionHandler != nil) ? @"YES" : @"NO");

    NSString* requestedDeviceID = CountlyDeviceInfo.sharedInstance.deviceID;
    [self fetchRemoteConfigForKeys:keys omitKeys:omitKeys completionHandler:^(NSDictionary *remoteConfig, NSError *error)
     {
        // an answer for the user before a device ID change would otherwise be stored as the values of the next user
        if (!error && ![CountlyDeviceInfo.sharedInstance.deviceID isEqualToString:requestedDeviceID])
        {
            CLY_LOG_D(@"%s remote config values arrived for a device ID that changed during the download, they are discarded", __FUNCTION__);
            remoteConfig = nil;
            error = [NSError errorWithDomain:kCountlyErrorDomain code:CLYErrorRemoteConfigGeneralAPIError userInfo:@{NSLocalizedDescriptionKey: @"Remote config values are for the device ID before the change"}];
        }

        BOOL fullValueUpdate = false;
        NSDictionary* remoteConfigMeta = remoteConfig ? [self createRCMeta:remoteConfig] : @{};
        CLYRequestResult requestResult = CLYResponseSuccess;
        if (!error)
        {
            CLY_LOG_D(@"%s remote config value download is successful, keys: [%@], valueCount: [%lu]", __FUNCTION__, remoteConfig.allKeys, (unsigned long)remoteConfig.count);
            CLY_LOG_D(@"%s remote config value download payload detail, remoteConfig: [%@]", __FUNCTION__, remoteConfig);
            if (!keys && !omitKeys)
            {
                fullValueUpdate = true;
                self.cachedRemoteConfig = remoteConfigMeta;
                CLY_LOG_D(@"%s remote config cache is replaced on full download, cachedKeyCount: [%lu]", __FUNCTION__, (unsigned long)self.cachedRemoteConfig.count);
            }
            else
            {
                NSMutableDictionary* partiallyUpdatedRemoteConfigMeta = self.cachedRemoteConfig.mutableCopy;
                [partiallyUpdatedRemoteConfigMeta addEntriesFromDictionary:remoteConfigMeta];
                self.cachedRemoteConfig = [NSDictionary dictionaryWithDictionary:partiallyUpdatedRemoteConfigMeta];
                CLY_LOG_D(@"%s remote config cache is merged on partial download, mergedKeyCount: [%lu], cachedKeyCount: [%lu]", __FUNCTION__, (unsigned long)remoteConfigMeta.count, (unsigned long)self.cachedRemoteConfig.count);
            }

            [CountlyPersistency.sharedInstance storeRemoteConfig:self.cachedRemoteConfig];


        }
        else
        {
            requestResult = CLYResponseError;
            CLY_LOG_D(@"%s remote config value download failed, error: [%@]", __FUNCTION__, error.localizedDescription);
        }

        if (completionHandler)
            completionHandler(requestResult, error, fullValueUpdate, remoteConfigMeta);

        CLY_LOG_D(@"%s registered download callbacks will be notified, callbackCount: [%lu], response: [%@], fullValueUpdate: [%@], downloadedValueCount: [%lu]", __FUNCTION__, (unsigned long)self.remoteConfigGlobalCallbacks.count, requestResult, fullValueUpdate ? @"YES" : @"NO", (unsigned long)remoteConfigMeta.count);
        CLY_LOG_D(@"%s download callback notification payload detail, remoteConfigMeta: [%@]", __FUNCTION__, remoteConfigMeta);

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
    CLY_LOG_D(@"%s all cached remote config values will be marked as not belonging to the current user, cachedKeyCount: [%lu]", __FUNCTION__, (unsigned long)self.cachedRemoteConfig.count);
    [self.cachedRemoteConfig enumerateKeysAndObjectsUsingBlock:^(NSString * key, CountlyRCData * countlyRCMeta, BOOL * stop)
     {
        countlyRCMeta.isCurrentUsersData = NO;
        
    }];
    
    [CountlyPersistency.sharedInstance storeRemoteConfig:self.cachedRemoteConfig];
}

-(void)registerDownloadCallback:(RCDownloadCallback) callback
{
    [self.remoteConfigGlobalCallbacks addObject:callback];
    CLY_LOG_D(@"%s download callback is registered, callbackCount: [%lu]", __FUNCTION__, (unsigned long)self.remoteConfigGlobalCallbacks.count);
}
-(void)removeDownloadCallback:(RCDownloadCallback) callback
{
    [self.remoteConfigGlobalCallbacks removeObject:callback];
    CLY_LOG_D(@"%s download callback is removed, callbackCount: [%lu]", __FUNCTION__, (unsigned long)self.remoteConfigGlobalCallbacks.count);
}

- (NSDictionary *)testingGetAllVariants
{
    CLY_LOG_D(@"%s all locally cached variants are read, variantKeyCount: [%lu]", __FUNCTION__, (unsigned long)self.localCachedVariants.count);
    return self.localCachedVariants;
}

- (NSDictionary *)testingGetVariantsForKey:(NSString *)key
{
    CLY_LOG_D(@"%s locally cached variants for a single key are read, key: [%@], variantKeyCount: [%lu]", __FUNCTION__, key, (unsigned long)self.localCachedVariants.count);
    return  self.localCachedVariants[key];
}

- (void)testingDownloadAllVariants:(RCVariantCallback)completionHandler
{
    if (!CountlyConsentManager.sharedInstance.consentForRemoteConfig)
    {
        CLY_LOG_V(@"%s no consent for remote config, variants download will be skipped", __FUNCTION__);
        return;
    }
    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
    {
        CLY_LOG_D(@"%s device ID is in temporary mode, variants download will be skipped", __FUNCTION__);
        return;
    }

    CLY_LOG_D(@"%s variants download is starting, requestKind: [%@]", __FUNCTION__, kCountlyRCKeyFetchVariant);

    [self testingDownloadAllVariantsInternal:^(CLYRequestResult response, NSDictionary *varaints,NSError *error)
     {
        if (!error)
        {
            self.localCachedVariants = varaints;
            CLY_LOG_D(@"%s variants download is successful, response: [%@], keys: [%@], variantKeyCount: [%lu]", __FUNCTION__, response, varaints.allKeys, (unsigned long)varaints.count);
            CLY_LOG_D(@"%s variants download payload detail, variants: [%@]", __FUNCTION__, varaints);
        }
        else
        {
            CLY_LOG_D(@"%s variants download failed, response: [%@], error: [%@]", __FUNCTION__, response, error.localizedDescription);
        }
        
        if (completionHandler)
            completionHandler(response, error);
    }];
}


- (void)testingDownloadAllVariantsInternal:(void (^)(CLYRequestResult response, NSDictionary* variants, NSError * error))completionHandler
{
    if (!CountlyServerConfig.sharedInstance.networkingEnabled)
    {
        CLY_LOG_D(@"%s variants request is aborted, reason: [networking is disabled from server config], requestKind: [%@]", __FUNCTION__, kCountlyRCKeyFetchVariant);
        return;
    }
    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
    {
        CLY_LOG_D(@"%s variants request is aborted, reason: [device ID is in temporary mode]", __FUNCTION__);
        return;
    }
    if (!completionHandler)
    {
        CLY_LOG_E(@"%s variants request is aborted, reason: [completionHandler is not provided]", __FUNCTION__);
        return;
    }

    NSURLRequest* request = [self downloadVariantsRequest];
    NSURLSessionTask* task = [CountlyCommon.sharedInstance immediateDataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
                              {
        // IMMEDIATE REQUEST to find them better in search
        NSMutableDictionary* variants = NSMutableDictionary.new;
        
        if (!error)
        {
            id variantsResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            // an error body such as {"result": "..."} is a dictionary too, so every entry is checked before it is read
            NSDictionary* variantsByKey = [variantsResponse isKindOfClass:NSDictionary.class] ? variantsResponse : nil;
            [variantsByKey enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL * stop)
             {
                if (![key isKindOfClass:NSString.class] || ![value isKindOfClass:NSArray.class])
                    return;

                NSMutableArray<NSString*>* valuesArray = NSMutableArray.new;
                for (id arrayValue in (NSArray *)value)
                {
                    id variantName = [arrayValue isKindOfClass:NSDictionary.class] ? arrayValue[@"name"] : arrayValue;
                    if ([variantName isKindOfClass:NSString.class])
                        [valuesArray addObject:variantName];
                }
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
            CLY_LOG_D(@"%s variants request failed, requestKind: [%@], stage: [%@], statusCode: [%ld], error: [%@]", __FUNCTION__, kCountlyRCKeyFetchVariant, data ? @"response handling" : @"network", (long)((NSHTTPURLResponse*)response).statusCode, error.localizedDescription);
            
            [self deliverOnMainUnlessHalted:^{
                completionHandler(CLYResponseError, nil, error);
            }];
            
            return;
        }
        
        CLY_LOG_D(@"%s variants request successfully completed, requestKind: [%@], statusCode: [%ld], variantKeyCount: [%lu]", __FUNCTION__, kCountlyRCKeyFetchVariant, (long)((NSHTTPURLResponse*)response).statusCode, (unsigned long)variants.count);
        CLY_LOG_D(@"%s variants response payload detail, variants: [%@]", __FUNCTION__, variants);
        
        [self deliverOnMainUnlessHalted:^{
            completionHandler(CLYResponseSuccess, variants, nil);
        }];
    }];
    
    [task resume];
    
    CLY_LOG_D(@"%s variants request is started, requestKind: [%@], method: [%@], path: [%@]", __FUNCTION__, kCountlyRCKeyFetchVariant, request.HTTPMethod, request.URL.path);
    CLY_LOG_D(@"%s variants request URL detail, url: [%@]", __FUNCTION__, request.URL.absoluteString);
}

- (void)testingEnrollIntoVariant:(NSString *)key variantName:(NSString *)variantName completionHandler:(RCVariantCallback)completionHandler
{
    if (!CountlyConsentManager.sharedInstance.consentForRemoteConfig)
    {
        CLY_LOG_V(@"%s no consent for remote config, variant enrollment will be skipped", __FUNCTION__);
        return;
    }

    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
    {
        CLY_LOG_D(@"%s device ID is in temporary mode, variant enrollment will be skipped", __FUNCTION__);
        return;
    }

    CLY_LOG_D(@"%s variant enrollment is starting, requestKind: [%@], key: [%@], variantName: [%@]", __FUNCTION__, kCountlyRCKeyEnrollVariant, key, variantName);

    [self testingEnrollIntoVariantInternal:key variantName:variantName completionHandler:^(CLYRequestResult response, NSError *error)
     {
        if (!error)
        {
            CLY_LOG_D(@"%s variant enrollment is successful, response: [%@], key: [%@], variantName: [%@]", __FUNCTION__, response, key, variantName);
        }
        else
        {
            CLY_LOG_D(@"%s variant enrollment failed, response: [%@], key: [%@], variantName: [%@], error: [%@]", __FUNCTION__, response, key, variantName, error.localizedDescription);
        }
        
        if (completionHandler)
            completionHandler(response, error);
    }];
}

- (void)testingEnrollIntoVariantInternal:(NSString *)key variantName:(NSString *)variantName completionHandler:(RCVariantCallback)completionHandler
{
    if (!CountlyServerConfig.sharedInstance.networkingEnabled)
    {
        CLY_LOG_D(@"%s variant enrollment request is aborted, reason: [networking is disabled from server config], requestKind: [%@]", __FUNCTION__, kCountlyRCKeyEnrollVariant);
        return;
    }
    if (!completionHandler)
    {
        CLY_LOG_E(@"%s variant enrollment request is aborted, reason: [completionHandler is not provided]", __FUNCTION__);
        return;
    }

    if (!key) {
        CLY_LOG_E(@"%s variant enrollment request is aborted, reason: [key is not valid], key: [%@]", __FUNCTION__, key);
        return;
    }

    if (!variantName) {
        CLY_LOG_E(@"%s variant enrollment request is aborted, reason: [variantName is not valid], key: [%@], variantName: [%@]", __FUNCTION__, key, variantName);
        return;
    }

    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
    {
        CLY_LOG_D(@"%s variant enrollment request is aborted, reason: [device ID is in temporary mode], key: [%@]", __FUNCTION__, key);
        return;
    }

    NSURLRequest* request = [self enrollInVarianRequestForKey:key variantName:variantName];
    NSURLSessionTask* task = [CountlyCommon.sharedInstance immediateDataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
    {
        // IMMEDIATE REQUEST to find them better in search
        if (self != s_sharedInstance)
        {
            CLY_LOG_D(@"%s variant enrollment response arrived after halt, it is ignored, key: [%@]", __FUNCTION__, key);
            return;
        }

        NSDictionary* variants = nil;
        [self clearCachedRemoteConfig];
        if (!error)
        {
            variants = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            if (![variants isKindOfClass:NSDictionary.class])
                variants = nil;

            if (((NSHTTPURLResponse*)response).statusCode != 200)
            {
                NSMutableDictionary* userInfo = variants.mutableCopy ?: NSMutableDictionary.new;
                userInfo[NSLocalizedDescriptionKey] = @"Enroll In RC Variant general API error";
                error = [NSError errorWithDomain:kCountlyErrorDomain code:CLYErrorRemoteConfigGeneralAPIError userInfo:userInfo];
            }
        }
        
        if (error)
        {
            CLY_LOG_D(@"%s variant enrollment request failed, requestKind: [%@], key: [%@], stage: [%@], statusCode: [%ld], error: [%@]", __FUNCTION__, kCountlyRCKeyEnrollVariant, key, data ? (variants ? @"API response" : @"JSON parsing") : @"network", (long)((NSHTTPURLResponse*)response).statusCode, error.localizedDescription);
            
            [self deliverOnMainUnlessHalted:^{
                completionHandler(CLYResponseError, error);
            }];
            
            return;
        }
        
        
        CLY_LOG_D(@"%s variant enrollment request successfully completed, requestKind: [%@], key: [%@], statusCode: [%ld]", __FUNCTION__, kCountlyRCKeyEnrollVariant, key, (long)((NSHTTPURLResponse*)response).statusCode);
        
        [self downloadRemoteConfigAutomatically];
        
    }];
    
    [task resume];
    
    CLY_LOG_D(@"%s variant enrollment request is started, requestKind: [%@], key: [%@], variantName: [%@], method: [%@], path: [%@]", __FUNCTION__, kCountlyRCKeyEnrollVariant, key, variantName, request.HTTPMethod, request.URL.path);
    CLY_LOG_D(@"%s variant enrollment request URL detail, url: [%@]", __FUNCTION__, request.URL.absoluteString);
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
        CLY_LOG_V(@"%s no consent for remote config, experiment information download will be skipped", __FUNCTION__);
        return;
    }
    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
    {
        CLY_LOG_D(@"%s device ID is in temporary mode, experiment information download will be skipped", __FUNCTION__);
        return;
    }

    CLY_LOG_D(@"%s experiment information download is starting, requestKind: [%@]", __FUNCTION__, kCountlyRCKeyFetchExperiments);

    [self testingDownloaExperimentInfoInternal:^(CLYRequestResult response, NSDictionary *experimentInfo,NSError *error)
     {
        if (!error)
        {
            self.localCachedExperiments = experimentInfo;
            CLY_LOG_D(@"%s experiment information download is successful, response: [%@], keys: [%@], experimentCount: [%lu]", __FUNCTION__, response, experimentInfo.allKeys, (unsigned long)experimentInfo.count);
            CLY_LOG_D(@"%s experiment information download payload detail, experimentInfo: [%@]", __FUNCTION__, experimentInfo);
        }
        else
        {
            CLY_LOG_D(@"%s experiment information download failed, response: [%@], error: [%@]", __FUNCTION__, response, error.localizedDescription);
        }
        
        if (completionHandler)
            completionHandler(response, error);
    }];
}


- (void)testingDownloaExperimentInfoInternal:(void (^)(CLYRequestResult response, NSDictionary* experimentsInfo, NSError * error))completionHandler
{
    if (!CountlyServerConfig.sharedInstance.networkingEnabled)
    {
        CLY_LOG_D(@"%s experiments request is aborted, reason: [networking is disabled from server config], requestKind: [%@]", __FUNCTION__, kCountlyRCKeyFetchExperiments);
        return;
    }
    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
    {
        CLY_LOG_D(@"%s experiments request is aborted, reason: [device ID is in temporary mode]", __FUNCTION__);
        return;
    }
    if (!completionHandler)
    {
        CLY_LOG_E(@"%s experiments request is aborted, reason: [completionHandler is not provided]", __FUNCTION__);
        return;
    }

    NSURLRequest* request = [self downloadExperimentInfoRequest];
    NSURLSessionTask* task = [CountlyCommon.sharedInstance immediateDataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
                              {
        // IMMEDIATE REQUEST to find them better in search
        NSMutableDictionary<NSString*, CountlyExperimentInformation*> * experiments = NSMutableDictionary.new;
        
        if (!error)
        {
            
            id experimentsResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
            // an error body is a dictionary, not the list of experiments
            NSArray* experimentsInfo = [experimentsResponse isKindOfClass:NSArray.class] ? experimentsResponse : nil;
            for (id value in experimentsInfo)
            {
                if (![value isKindOfClass:NSDictionary.class])
                    continue;

                CountlyExperimentInformation* experimentInfo = [[CountlyExperimentInformation alloc] initWithID:value[@"id"] experimentName:value[@"name"] experimentDescription:value[@"description"] currentVariant:value[@"currentVariant"] variants:value[@"variants"]];
                if (experimentInfo.experimentID)
                    experiments[experimentInfo.experimentID] = experimentInfo;
            }
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
            CLY_LOG_D(@"%s experiments request failed, requestKind: [%@], stage: [%@], statusCode: [%ld], error: [%@]", __FUNCTION__, kCountlyRCKeyFetchExperiments, data ? @"response handling" : @"network", (long)((NSHTTPURLResponse*)response).statusCode, error.localizedDescription);
            
            [self deliverOnMainUnlessHalted:^{
                completionHandler(CLYResponseError, nil, error);
            }];
            
            return;
        }
        
        CLY_LOG_D(@"%s experiments request successfully completed, requestKind: [%@], statusCode: [%ld], experimentCount: [%lu]", __FUNCTION__, kCountlyRCKeyFetchExperiments, (long)((NSHTTPURLResponse*)response).statusCode, (unsigned long)experiments.count);
        CLY_LOG_D(@"%s experiments response payload detail, experiments: [%@]", __FUNCTION__, experiments);
        
        [self deliverOnMainUnlessHalted:^{
            completionHandler(CLYResponseSuccess, experiments, nil);
        }];
    }];
    
    [task resume];
    
    CLY_LOG_D(@"%s experiments request is started, requestKind: [%@], method: [%@], path: [%@]", __FUNCTION__, kCountlyRCKeyFetchExperiments, request.HTTPMethod, request.URL.path);
    CLY_LOG_D(@"%s experiments request URL detail, url: [%@]", __FUNCTION__, request.URL.absoluteString);
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
    CLY_LOG_D(@"%s all locally cached experiment information is read, experimentCount: [%lu]", __FUNCTION__, (unsigned long)self.localCachedExperiments.count);
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
