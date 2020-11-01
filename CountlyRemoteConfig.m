// CountlyLocationManager.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

NSString* const kCountlyRCKeyFetchRemoteConfig  = @"fetch_remote_config";
NSString* const kCountlyRCKeyKeys               = @"keys";
NSString* const kCountlyRCKeyOmitKeys           = @"omit_keys";

@interface CountlyRemoteConfig ()
@property (nonatomic) NSDictionary* cachedRemoteConfig;
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

    COUNTLY_LOG(@"Fetching remote config on start...");

    [self fetchRemoteConfigForKeys:nil omitKeys:nil completionHandler:^(NSDictionary *remoteConfig, NSError *error)
    {
        if (!error)
        {
            COUNTLY_LOG(@"Fetching remote config on start is successful. \n%@", remoteConfig);

            self.cachedRemoteConfig = remoteConfig;
            [CountlyPersistency.sharedInstance storeRemoteConfig:self.cachedRemoteConfig];
        }
        else
        {
            COUNTLY_LOG(@"Fetching remote config on start failed: %@", error);
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

    COUNTLY_LOG(@"Fetching remote config manually...");

    [self fetchRemoteConfigForKeys:keys omitKeys:omitKeys completionHandler:^(NSDictionary *remoteConfig, NSError *error)
    {
        if (!error)
        {
            COUNTLY_LOG(@"Fetching remote config manually is successful. \n%@", remoteConfig);

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
            COUNTLY_LOG(@"Fetching remote config manually failed: %@", error);
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
            COUNTLY_LOG(@"Remote Config Request <%p> failed!\nError: %@", request, error);

            dispatch_async(dispatch_get_main_queue(), ^
            {
                completionHandler(nil, error);
            });

            return;
        }

        COUNTLY_LOG(@"Remote Config Request <%p> successfully completed.", request);

        dispatch_async(dispatch_get_main_queue(), ^
        {
            completionHandler(remoteConfig, nil);
        });
    }];

    [task resume];

    COUNTLY_LOG(@"Remote Config Request <%p> started:\n[%@] %@", (id)request, request.HTTPMethod, request.URL.absoluteString);
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
        return  request.copy;
    }
    else
    {
        NSString* withQueryString = [serverOutputSDKEndpoint stringByAppendingFormat:@"?%@", queryString];
        NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:withQueryString]];
        return request;
    }
}

@end
