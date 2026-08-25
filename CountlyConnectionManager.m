// CountlyConnectionManager.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"
#import <stdatomic.h>

@interface CountlyConnectionManager ()
{
    NSTimeInterval unsentSessionLength;
    NSTimeInterval lastSessionStartTime;
    BOOL isCrashing;
    BOOL isSessionStarted;
}
@property (nonatomic) NSURLSession* URLSession;

@property (nonatomic, strong) NSDate *startTime;
@property (nonatomic, assign) atomic_bool backoff;
@property (nonatomic, assign) atomic_bool isProcessingQueue;
@property (nonatomic, strong) NSMutableDictionary<NSString *, CLYRequestCallback> *internalRequestCallbacks;
@property (nonatomic, strong) NSMutableArray<CLYQueueFlushRunnable> *queueFlushRunnables;
@property (nonatomic) BOOL hasAnyRequestFailed;
@property (nonatomic, strong) dispatch_queue_t callbackQueue; // Serial queue for thread-safe callback/runnable access

@end

NSString* const kCountlyQSKeyAppKey           = @"app_key";

NSString* const kCountlyQSKeyDeviceID         = @"device_id";
NSString* const kCountlyQSKeyDeviceIDOld      = @"old_device_id";
NSString* const kCountlyQSKeyDeviceIDType     = @"t";

NSString* const kCountlyQSKeyTimestamp        = @"timestamp";
NSString* const kCountlyQSKeyTimeZone         = @"tz";
NSString* const kCountlyQSKeyTimeHourOfDay    = @"hour";
NSString* const kCountlyQSKeyTimeDayOfWeek    = @"dow";

NSString* const kCountlyQSKeySDKVersion       = @"sdk_version";
NSString* const kCountlyQSKeySDKName          = @"sdk_name";

NSString* const kCountlyQSKeySessionBegin     = @"begin_session";
NSString* const kCountlyQSKeySessionDuration  = @"session_duration";
NSString* const kCountlyQSKeySessionEnd       = @"end_session";

NSString* const kCountlyQSKeyPushTokenSession = @"token_session";
NSString* const kCountlyQSKeyPushTokeniOS     = @"ios_token";
NSString* const kCountlyQSKeyPushTestMode     = @"test_mode";

NSString* const kCountlyQSKeyLocation         = @"location";
NSString* const kCountlyQSKeyLocationCity     = @"city";
NSString* const kCountlyQSKeyLocationCountry  = @"country_code";
NSString* const kCountlyQSKeyLocationIP       = @"ip_address";

NSString* const kCountlyQSKeyAttributionID    = @"aid";
NSString* const kCountlyQSKeyIDFA             = @"idfa";
NSString* const kCountlyQSKeyADID             = @"adid";
NSString* const kCountlyQSKeyCampaignID       = @"campaign_id";
NSString* const kCountlyQSKeyCampaignUser     = @"campaign_user";
NSString* const kCountlyQSKeyAttributionData  = @"attribution_data";

NSString* const kCountlyQSKeyMetrics          = @"metrics";
NSString* const kCountlyQSKeyEvents           = @"events";
NSString* const kCountlyQSKeyUserDetails      = @"user_details";
NSString* const kCountlyQSKeyCrash            = @"crash";
NSString* const kCountlyQSKeyChecksum256      = @"checksum256";
NSString* const kCountlyQSKeyConsent          = @"consent";
NSString* const kCountlyQSKeyAPM              = @"apm";
NSString* const kCountlyQSKeyRemainingRequest = @"rr";

NSString* const kCountlyQSKeyMethod           = @"method";
NSString* const kCountlyQSKeyTheme            = @"th";

NSString* const kCountlyRCKeyABOptIn          = @"ab";
NSString* const kCountlyRCKeyABOptOut         = @"ab_opt_out";
NSString* const kCountlyEndPointOverrideTag   = @"&new_end_point=";
NSString* const kCountlyNewEndPoint           = @"new_end_point";
NSString* const kCountlyCallbackID            = @"callback_id";

CLYAttributionKey const CLYAttributionKeyIDFA = kCountlyQSKeyIDFA;
CLYAttributionKey const CLYAttributionKeyADID = kCountlyQSKeyADID;

NSString* const kCountlyUploadBoundary = @"0cae04a8b698d63ff6ea55d168993f21";

NSString* const kCountlyEndpointI = @"/i"; //NOTE: input endpoint
NSString* const kCountlyEndpointO = @"/o"; //NOTE: output endpoint
NSString* const kCountlyEndpointSDK = @"/sdk";
NSString* const kCountlyEndpointFeedback = @"/feedback";
NSString* const kCountlyEndpointWidget = @"/widget";
NSString* const kCountlyEndpointSurveys = @"/surveys";

const NSInteger kCountlyGETRequestMaxLength = 2048;

@implementation CountlyConnectionManager : NSObject

static CountlyConnectionManager *s_sharedInstance = nil;
static dispatch_once_t onceToken;
+ (instancetype)sharedInstance
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return nil;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    if (self = [super init])
    {
        unsentSessionLength = 0.0;
        isSessionStarted = NO;
        atomic_init(&_backoff, NO);
        atomic_init(&_isProcessingQueue, NO);
        _internalRequestCallbacks = [NSMutableDictionary dictionary];
        _queueFlushRunnables = [NSMutableArray array];
        _hasAnyRequestFailed = NO;
        _callbackQueue = dispatch_queue_create("ly.count.callbackQueue", DISPATCH_QUEUE_SERIAL);
    }

    return self;
}


- (BOOL)isSessionStarted {
    return isSessionStarted;
}

- (void)resetInstance {
    CLY_LOG_I(@"%s connection manager is being reset, pending request callbacks and queue flush runnables will be cleared", __FUNCTION__);
    onceToken = 0;
    s_sharedInstance = nil;
    isSessionStarted = NO;
    dispatch_sync(_callbackQueue, ^{
        [self->_internalRequestCallbacks removeAllObjects];
        [self->_queueFlushRunnables removeAllObjects];
    });
    _hasAnyRequestFailed = NO;
    atomic_store(&_isProcessingQueue, NO);
}

- (void)setHost:(NSString *)host
{
    if ([host hasSuffix:@"/"])
    {
        CLY_LOG_W(@"%s host has an extra \"/\" at the end, it will be removed by the SDK, please fix it to avoid this warning in the future", __FUNCTION__);
        _host = [host substringToIndex:host.length - 1];
    }
    else
    {
        _host = host;
    }
}

- (void)setURLSessionConfiguration:(NSURLSessionConfiguration *)URLSessionConfiguration
{
    if (URLSessionConfiguration != nil)
    {
        CLY_LOG_D(@"%s custom URL session configuration is set, the URL session will be recreated on the next request", __FUNCTION__);
        _URLSessionConfiguration = URLSessionConfiguration;
        _URLSession = nil;
    }
}

- (void)addCustomNetworkRequestHeaders:(NSDictionary<NSString *, NSString *> *_Nullable)customHeaderValues {
    if (_URLSessionConfiguration == nil) {
        CLY_LOG_W(@"%s custom network request headers are ignored, reason: URL session configuration is not set, provided header count: [%lu]", __FUNCTION__, (unsigned long)customHeaderValues.count);
        return;
    }

    // Start with current headers (or empty if nil)
    NSMutableDictionary *updatedHeaders = [NSMutableDictionary dictionaryWithDictionary:_URLSessionConfiguration.HTTPAdditionalHeaders ?: @{}];

    // Enumerate and validate custom headers
    __block NSUInteger skippedHeaderCount = 0;
    [customHeaderValues enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        if (key == nil || key.length == 0) {
            skippedHeaderCount++;
            CLY_LOG_V(@"[CountlyConnectionManager] addCustomNetworkRequestHeaders, a custom network request header with a nil or empty key is skipped");
            return; // Skip empty key
        }
        if (value == nil) {
            skippedHeaderCount++;
            CLY_LOG_V(@"[CountlyConnectionManager] addCustomNetworkRequestHeaders, a custom network request header with a nil value is skipped, header key: [%@]", key);
            return; // Skip nil value
        }

        // Add or override
        updatedHeaders[key] = value;
    }];

    if (skippedHeaderCount)
    {
        CLY_LOG_W(@"%s some custom network request headers are skipped, reason: nil or empty key or nil value, skipped header count: [%lu]", __FUNCTION__, (unsigned long)skippedHeaderCount);
    }

    // Apply updated headers
    CLY_LOG_I(@"%s custom network request headers are applied, total header count: [%lu]", __FUNCTION__, (unsigned long)updatedHeaders.count);
    _URLSessionConfiguration.HTTPAdditionalHeaders = [updatedHeaders copy];
    _URLSession = nil;
}

- (void)proceedOnQueue
{
    if (!CountlyServerConfig.sharedInstance.networkingEnabled)
    {
        CLY_LOG_D(@"%s aborting queue processing, reason: SDK networking is disabled from server config", __FUNCTION__);
        return;
    }
    
    if (self.connection || atomic_exchange(&_isProcessingQueue, YES))
    {
        CLY_LOG_D(@"%s aborting queue processing, reason: another request is already in process", __FUNCTION__);
        return;
    }

    if (isCrashing)
    {
        CLY_LOG_D(@"%s aborting queue processing, reason: application is crashing", __FUNCTION__);
        atomic_store(&_isProcessingQueue, NO);
        return;
    }

    if (self.isTerminating)
    {
        CLY_LOG_D(@"%s aborting queue processing, reason: application is terminating", __FUNCTION__);
        atomic_store(&_isProcessingQueue, NO);
        return;
    }

    if (CountlyPersistency.sharedInstance.isQueueBeingModified)
    {
        CLY_LOG_D(@"%s aborting queue processing, reason: request queue is being modified", __FUNCTION__);
        atomic_store(&_isProcessingQueue, NO);
        return;
    }

    BOOL backoffFlag = atomic_load(&_backoff) ? YES : NO;
    if (backoffFlag) {
        CLY_LOG_D(@"%s aborting queue processing, reason: backoff is currently active", __FUNCTION__);
        atomic_store(&_isProcessingQueue, NO);
        return;
    }
    
    if (!self.startTime) {
        self.startTime = [NSDate date]; // Record start time only when it's not already recorded
        self.hasAnyRequestFailed = NO; // Reset failure flag when starting queue processing
        CLY_LOG_D(@"%s queue processing is started, queued request count: [%lu]", __FUNCTION__, (unsigned long)[CountlyPersistency.sharedInstance remainingRequestCount]);
    }

    NSString* firstItemInQueue = [CountlyPersistency.sharedInstance firstItemInQueue];
    if (!firstItemInQueue)
    {
        // Calculate total time when the queue becomes empty
        NSTimeInterval elapsedTime = -[self.startTime timeIntervalSinceNow];
        CLY_LOG_D(@"%s request queue is empty, all requests are processed, total time taken: [%.2f] seconds", __FUNCTION__, elapsedTime);

        // Execute and clear runnables only if all requests succeeded
        if (!self.hasAnyRequestFailed) {
            // Thread-safe copy and clear of runnables
            __block NSArray<CLYQueueFlushRunnable> *runnablesToExecute = nil;
            dispatch_sync(_callbackQueue, ^{
                if (self->_queueFlushRunnables.count > 0) {
                    CLY_LOG_D(@"[CountlyConnectionManager] proceedOnQueue, all requests succeeded, executing queue flush runnables, count: [%lu]", (unsigned long)self->_queueFlushRunnables.count);
                    runnablesToExecute = [self->_queueFlushRunnables copy];
                    [self->_queueFlushRunnables removeAllObjects];
                }
            });

            // Execute runnables outside the lock to prevent deadlocks
            if (runnablesToExecute) {
                for (CLYQueueFlushRunnable runnable in runnablesToExecute) {
                    runnable();
                }
                CLY_LOG_D(@"%s all queue flush runnables are executed and removed", __FUNCTION__);
            }
        } else {
            CLY_LOG_D(@"%s at least one request failed, queue flush runnables will not be executed", __FUNCTION__);
        }

        // Reset start time and failure flag for future queue processing
        self.startTime = nil;
        self.hasAnyRequestFailed = NO;
        atomic_store(&_isProcessingQueue, NO);
        return;
    }
    
    BOOL isOldRequest = [CountlyPersistency.sharedInstance isOldRequest:firstItemInQueue];
    if(isOldRequest)
    {
        CLY_LOG_W(@"%s dropping the request at the head of the queue, reason: request age exceeded the configured drop age, request size: [%lu] bytes", __FUNCTION__, (unsigned long)firstItemInQueue.length);
        [CountlyPersistency.sharedInstance removeFromQueue:firstItemInQueue];
        
        [CountlyPersistency.sharedInstance saveToFile];

        atomic_store(&_isProcessingQueue, NO);
        [self proceedOnQueue];

        return;
    }


    NSString* temporaryDeviceIDQueryString = [NSString stringWithFormat:@"&%@=%@", kCountlyQSKeyDeviceID, CLYTemporaryDeviceID];
    if ([firstItemInQueue containsString:temporaryDeviceIDQueryString])
    {
        CLY_LOG_D(@"%s aborting queue processing, reason: device ID of the request at the head of the queue is the temporary device ID", __FUNCTION__);
        atomic_store(&_isProcessingQueue, NO);
        return;
    }

    _URLSessionConfiguration.timeoutIntervalForRequest = [CountlyServerConfig.sharedInstance requestTimeoutDuration];
    _URLSessionConfiguration.timeoutIntervalForResource = [CountlyServerConfig.sharedInstance requestTimeoutDuration];
    NSString* queryString = firstItemInQueue;
    NSString* endPoint = kCountlyEndpointI;
    
    NSString* overrideEndPoint = [self extractAndRemoveParameter:&queryString parameter: kCountlyNewEndPoint];
    if(overrideEndPoint) {
        endPoint = overrideEndPoint;
    }
    
    NSString* callbackID = [self extractAndRemoveParameter:&queryString parameter: kCountlyCallbackID];
    __block CLYRequestCallback requestCallback = nil;
    if(callbackID){
        dispatch_sync(_callbackQueue, ^{
            requestCallback = self.internalRequestCallbacks[callbackID];
        });
    }
    
    
    [CountlyCommon.sharedInstance startBackgroundTask];

    queryString = [self appendRemainingRequest:queryString];
    NSMutableData* pictureUploadData = [self pictureUploadDataForQueryString:queryString];

    if (!pictureUploadData)
    {
        queryString = [self appendChecksum:queryString];
    }

    NSString* serverInputEndpoint = [self.host stringByAppendingString:endPoint];
    NSMutableURLRequest* request;
    
    if (pictureUploadData)
    {
        request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:serverInputEndpoint]];
        NSString *contentType = [@"multipart/form-data; boundary=" stringByAppendingString:kCountlyUploadBoundary];
        [request addValue:contentType forHTTPHeaderField: @"Content-Type"];
        
        NSArray *query = [queryString componentsSeparatedByString:@"&"];
        NSEnumerator *e = [query objectEnumerator];
        NSString* kvString;
        while (kvString = [e nextObject]) {
            NSArray *kv = [kvString componentsSeparatedByString:@"="];
            [self addMultipart:pictureUploadData andKey:[kv[0] stringByRemovingPercentEncoding] andValue:[kv[1] stringByRemovingPercentEncoding]];
        }
        
        if (self.secretSalt)
        {
            NSString* checksum = [[[queryString stringByRemovingPercentEncoding] stringByAppendingString:self.secretSalt] cly_SHA256];
            [self addMultipart:pictureUploadData andKey:kCountlyQSKeyChecksum256 andValue:checksum];
        }
        
        NSString* boundaryEnd = [NSString stringWithFormat:@"\r\n--%@--\r\n", kCountlyUploadBoundary];
        [pictureUploadData appendData:[boundaryEnd cly_dataUTF8]];
        request.HTTPMethod = @"POST";
        request.HTTPBody = pictureUploadData;
        CLY_LOG_D(@"%s request will be sent as a multipart POST with picture data, endpoint: [%@], upload data size: [%lu] bytes", __FUNCTION__, endPoint, (unsigned long)pictureUploadData.length);
    }
    else if (queryString.length > kCountlyGETRequestMaxLength || self.alwaysUsePOST)
    {
        request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:serverInputEndpoint]];
        request.HTTPMethod = @"POST";
        request.HTTPBody = [queryString cly_dataUTF8];
    }
    else
    {
        NSString* fullRequestURL = [serverInputEndpoint stringByAppendingFormat:@"?%@", queryString];
        request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:fullRequestURL]];
    }

    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    NSDate *startTimeRequest = [NSDate date];
    self.connection = [self.URLSession dataTaskWithRequest:request completionHandler:^(NSData * data, NSURLResponse * response, NSError * error)
    {
        self.connection = nil;
        NSDate *endTimeRequest = [NSDate date];
        long duration = (long)[endTimeRequest timeIntervalSinceDate:startTimeRequest];
        
        if(response) {
            NSInteger code = ((NSHTTPURLResponse*)response).statusCode;
            CLY_LOG_D(@"[CountlyConnectionManager] proceedOnQueue completion, response received, endpoint: [%@], status code: [%ld], response size: [%ld] bytes, duration: [%ld] seconds", request.URL.path, (long)code, (long)data.length, duration);
            CLY_LOG_D(@"[CountlyConnectionManager] proceedOnQueue completion, response detail, full response URL: [%@], status code: [%ld]", request.URL.absoluteString, (long)code);
        }
        

        if (!error)
        {
            if ([self isRequestSuccessful:response data:data])
            {
                CLY_LOG_D(@"[CountlyConnectionManager] proceedOnQueue completion, request completed successfully, endpoint: [%@], duration: [%ld] seconds", request.URL.path, duration);

                if(requestCallback){
                    requestCallback([response description], YES);
                    // Clean up callback after execution
                    if (callbackID) {
                        dispatch_sync(self->_callbackQueue, ^{
                            [self.internalRequestCallbacks removeObjectForKey:callbackID];
                        });
                    }
                }

                [CountlyPersistency.sharedInstance removeFromQueue:firstItemInQueue];

                [CountlyPersistency.sharedInstance saveToFile];

                // Clear the processing flag only after the head has been removed
                // from the queue. Clearing it earlier would let a concurrent
                // proceedOnQueue caller re-send the same head request.
                atomic_store(&self->_isProcessingQueue, NO);

                if(CountlyServerConfig.sharedInstance.backoffMechanism && [self backoff:duration queryString:queryString]){
                    CLY_LOG_D(@"[CountlyConnectionManager] proceedOnQueue completion, stopping queue processing, reason: backoff is triggered, last response duration: [%ld] seconds", duration);
                    self.startTime = nil;
                    self.hasAnyRequestFailed = NO; // Reset on backoff
                    [self backoffCountdown];
                } else {
                    [self proceedOnQueue];

                }
            }
            else
            {
                CLY_LOG_D(@"[CountlyConnectionManager] proceedOnQueue completion, request failed, endpoint: [%@], status code: [%ld], response size: [%ld] bytes", request.URL.path, (long)((NSHTTPURLResponse*)response).statusCode, (long)data.length);

                if (CountlyInternalLogIsEnabled(CLYInternalLogLevelDebug))
                {
                    NSString* errorResponseBody = [data cly_stringUTF8];
                    CLY_LOG_D(@"[CountlyConnectionManager] proceedOnQueue completion, failed request detail, full response URL: [%@], server error response body: [%@]", request.URL.absoluteString, errorResponseBody);
                }

                self.hasAnyRequestFailed = YES; // Mark that a request has failed

                if(requestCallback){
                    requestCallback([data cly_stringUTF8], NO);
                    // Clean up callback after execution
                    if (callbackID) {
                        dispatch_sync(self->_callbackQueue, ^{
                            [self.internalRequestCallbacks removeObjectForKey:callbackID];
                        });
                    }
                }

                [CountlyHealthTracker.sharedInstance logFailedNetworkRequestWithStatusCode:((NSHTTPURLResponse*)response).statusCode errorResponse: [data cly_stringUTF8]];
                [CountlyHealthTracker.sharedInstance saveState];
                self.startTime = nil;
                atomic_store(&self->_isProcessingQueue, NO);
            }
        }
        else
        {
            CLY_LOG_D(@"[CountlyConnectionManager] proceedOnQueue completion, request failed with a network error, endpoint: [%@], error domain: [%@], error code: [%ld], error description: [%@]", request.URL.path, error.domain, (long)error.code, error.localizedDescription);

            self.hasAnyRequestFailed = YES; // Mark that a request has failed

            if(requestCallback){
                requestCallback([error description], NO);
                // Clean up callback after execution
                if (callbackID) {
                    dispatch_sync(self->_callbackQueue, ^{
                        [self.internalRequestCallbacks removeObjectForKey:callbackID];
                    });
                }
            }
#if (TARGET_OS_WATCH)
            [CountlyPersistency.sharedInstance saveToFile];
#endif
            self.startTime = nil;
            atomic_store(&self->_isProcessingQueue, NO);
        }
    }];

    [self.connection resume];

    [self logRequest:request];
}

- (void)recordMetrics:(nullable NSDictionary *)metricsOverride
{
    CLY_LOG_I(@"%s recording metrics, override metric count: [%lu]", __FUNCTION__, (unsigned long)metricsOverride.count);
    if (!CountlyConsentManager.sharedInstance.consentForMetrics)
    return;
    
    NSDictionary *defaultMetrics = [CountlyDeviceInfo metricsDictionary];
    if (!defaultMetrics) {
        CLY_LOG_W(@"%s aborting metrics recording, reason: default metrics dictionary is nil", __FUNCTION__);
        return;
    }
    NSDictionary *finalMetrics;
    if (metricsOverride && metricsOverride.count > 0) {
        NSMutableDictionary *mutableMetrics = [defaultMetrics mutableCopy];
        [mutableMetrics addEntriesFromDictionary:metricsOverride];
        finalMetrics = [mutableMetrics copy];
    } else {
        finalMetrics = defaultMetrics;
    }
    CLY_LOG_D(@"%s metrics request is being prepared, final metric count: [%lu]", __FUNCTION__, (unsigned long)finalMetrics.count);
    CLY_LOG_V(@"%s final metric keys: [%@]", __FUNCTION__, finalMetrics.allKeys);
    CLY_LOG_D(@"%s default metrics detail, default metrics: [%@]", __FUNCTION__, defaultMetrics);
    CLY_LOG_D(@"%s final metrics detail, final metrics: [%@]", __FUNCTION__, finalMetrics);
    
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&%@=%@",
                             kCountlyQSKeyMetrics, [finalMetrics cly_JSONify]];
    
    [CountlyPersistency.sharedInstance addToQueue:queryString];
    [self proceedOnQueue];
}

- (BOOL)backoff:(long)responseTimeSeconds queryString:(NSString *)queryString
{
    BOOL result = NO;
    // Check if the current response time is within acceptable limits
    if (responseTimeSeconds >= [CountlyServerConfig.sharedInstance bomAcceptedTimeoutSeconds]) {
        // Check if the remaining request count is within acceptable limits
        NSUInteger remainingRequests = [CountlyPersistency.sharedInstance remainingRequestCount];
        NSUInteger threshold = (NSUInteger)(CountlyPersistency.sharedInstance.storedRequestsLimit * [CountlyServerConfig.sharedInstance bomRQPercentage]);
        
        if (remainingRequests <= threshold) {
            // Calculate the age of the current request
            double requestTimestamp = [[queryString cly_valueForQueryStringKey:kCountlyQSKeyTimestamp] longLongValue] / 1000.0;
            double requestAgeInSeconds = [NSDate date].timeIntervalSince1970 - requestTimestamp;
            
            if (requestAgeInSeconds <= [CountlyServerConfig.sharedInstance bomRequestAge] * 3600.0) {
                // Server is too busy, back off
                result = YES;
                CLY_LOG_W(@"%s backoff is triggered, response time: [%ld] seconds, remaining request count: [%lu], request count threshold: [%lu], request age: [%.2f] seconds", __FUNCTION__, responseTimeSeconds, (unsigned long)remainingRequests, (unsigned long)threshold, requestAgeInSeconds);
                [CountlyHealthTracker.sharedInstance logBackoffRequest];
            }
        }
    }
    
    if (!result) {
        [CountlyHealthTracker.sharedInstance logConsecutiveBackoffRequest];
    }
    
    CLY_LOG_D(@"%s backoff evaluation is completed, decision: [%@], response time: [%ld] seconds", __FUNCTION__, result ? @"YES" : @"NO", responseTimeSeconds);

    return result;
}

- (void)backoffCountdown
{
    __weak typeof(self) weakSelf = self;
    CLY_LOG_D(@"%s backoff countdown is started, queue processing will be paused for [%ld] seconds", __FUNCTION__, (long)[CountlyServerConfig.sharedInstance bomDuration]);

    atomic_store(&_backoff, YES);
    dispatch_time_t delay = dispatch_time(DISPATCH_TIME_NOW, (int64_t)([CountlyServerConfig.sharedInstance bomDuration] * NSEC_PER_SEC));
    dispatch_after(delay, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        
        CLY_LOG_D(@"[CountlyConnectionManager] backoffCountdown, backoff countdown is finished, resuming queue processing on a background thread");
        atomic_store(&strongSelf->_backoff, NO);
        [strongSelf proceedOnQueue];
    });
}

- (NSString*)extractAndRemoveParameter:(NSString **)queryString parameter:(NSString*)parameter
{
    if([*queryString containsString:parameter]) {
        NSString* parameterExtracted = [*queryString cly_valueForQueryStringKey:parameter];
        if(parameterExtracted) {
            NSString* stringToRemove = [NSString stringWithFormat:@"&%@=%@",parameter,parameterExtracted];
            *queryString = [*queryString stringByReplacingOccurrencesOfString:stringToRemove withString:@""];
            CLY_LOG_D(@"%s parameter is extracted and removed from the query string, parameter: [%@], value length: [%lu]", __FUNCTION__, parameter, (unsigned long)parameterExtracted.length);
            return parameterExtracted;
        }
        CLY_LOG_W(@"%s parameter is present in the query string but its value could not be extracted, parameter: [%@]", __FUNCTION__, parameter);
    } else {
        CLY_LOG_V(@"%s parameter is not present in the query string, parameter: [%@]", __FUNCTION__, parameter);
    }
    return nil;
}

- (void)logRequest:(NSURLRequest *)request
{
    NSInteger sentSize = request.URL.absoluteString.length;

    if (request.HTTPBody)
    {
        sentSize += request.HTTPBody.length;
    }

    CLY_LOG_I(@"%s sending request, endpoint: [%@], method: [%@], approximate sent data size: [%ld] bytes, body size: [%ld] bytes", __FUNCTION__, request.URL.path, request.HTTPMethod, (long)sentSize, (long)request.HTTPBody.length);

    if (CountlyInternalLogIsEnabled(CLYInternalLogLevelDebug))
    {
        NSString* bodyAsString = @"";
        if (request.HTTPBody)
        {
            bodyAsString = [request.HTTPBody cly_stringUTF8];
            if (!bodyAsString)
                bodyAsString = @"Picture uploading...";
        }

        CLY_LOG_D(@"%s request detail, request: [<%p>], method: [%@], URL: [%@], body: [%@]", __FUNCTION__, request, request.HTTPMethod, request.URL.absoluteString, bodyAsString);
    }
}

#pragma mark ---

- (void)beginSession
{
    if (!CountlyConsentManager.sharedInstance.consentForSessions)
        return;
    
    if(!CountlyServerConfig.sharedInstance.sessionTrackingEnabled)
        return;
    
    if (isSessionStarted) {
        CLY_LOG_W(@"%s A session is already running, this 'beginSession' will be ignored", __FUNCTION__);
        return;
    }
    
#if TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_VISION
    if (CountlyServerConfig.sharedInstance.automaticSessionTrackingEnabled && [UIApplication sharedApplication].applicationState == UIApplicationStateBackground) {
        CLY_LOG_D(@"%s App is in the background, 'beginSession' will be ignored", __FUNCTION__);
        return;
    }
#elif TARGET_OS_OSX
    if (CountlyServerConfig.sharedInstance.automaticSessionTrackingEnabled && ![NSApplication sharedApplication].isActive) {
        CLY_LOG_D(@"%s App is not active, 'beginSession' will be ignored", __FUNCTION__);
        return;
    }
#elif TARGET_OS_WATCH
    if (CountlyServerConfig.sharedInstance.automaticSessionTrackingEnabled && [WKExtension sharedExtension].applicationState == WKApplicationStateBackground) {
        CLY_LOG_D(@"%s watch app is in the background, 'beginSession' will be ignored", __FUNCTION__);
        return;
    }
#endif

    if ([CountlyUserDetails.sharedInstance hasUnsyncedChanges])
    {
        [CountlyUserDetails.sharedInstance save];
    }

    isSessionStarted = YES;
    lastSessionStartTime = NSDate.date.timeIntervalSince1970;
    unsentSessionLength = 0.0;

    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&%@=%@&%@=%@",
                             kCountlyQSKeySessionBegin, @"1",
                             kCountlyQSKeyMetrics, [CountlyDeviceInfo metrics]];

    if(CountlyServerConfig.sharedInstance.locationTrackingEnabled) {
        NSString* locationRelatedInfoQueryString = [self locationRelatedInfoQueryString];
        if (locationRelatedInfoQueryString)
            queryString = [queryString stringByAppendingString:locationRelatedInfoQueryString];
    }

    NSString* attributionQueryString = [self attributionQueryString];
    if (attributionQueryString)
        queryString = [queryString stringByAppendingString:attributionQueryString];

    [CountlyPersistency.sharedInstance addToQueue:queryString];
    
    [CountlyCommon.sharedInstance recordOrientation];
    
    [self proceedOnQueue];
}

- (void)updateSession
{
    if (!CountlyConsentManager.sharedInstance.consentForSessions)
        return;
    
    if(!CountlyServerConfig.sharedInstance.sessionTrackingEnabled)
        return;
    
    if (!isSessionStarted) {
        CLY_LOG_D(@"%s No session is running, this 'updateSession' will be ignored", __FUNCTION__);
        return;
    }
    
    if ([CountlyUserDetails.sharedInstance hasUnsyncedChanges])
    {
        [CountlyUserDetails.sharedInstance save];
    }

    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&%@=%d",
                             kCountlyQSKeySessionDuration, (int)[self sessionLengthInSeconds]];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self proceedOnQueue];
}

- (void)endSession
{
    if (!CountlyConsentManager.sharedInstance.consentForSessions)
        return;
    
    if(!CountlyServerConfig.sharedInstance.sessionTrackingEnabled)
        return;
    
    if (!isSessionStarted) {
        CLY_LOG_D(@"%s No session is running, this 'endSession' will be ignored", __FUNCTION__);
        return;
    }

    isSessionStarted = NO;
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&%@=%@&%@=%d",
                             kCountlyQSKeySessionEnd, @"1",
                             kCountlyQSKeySessionDuration, (int)[self sessionLengthInSeconds]];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self proceedOnQueue];
    
    [CountlyViewTrackingInternal.sharedInstance resetFirstView];
}

#pragma mark ---

- (void)sendEventsWithSaveIfNeeded
{
    if ([CountlyUserDetails.sharedInstance hasUnsyncedChanges])
    {
        [CountlyUserDetails.sharedInstance save];
    }
    else
    {
        [self sendEventsInternal];
    }
}

- (void)sendEvents
{
    [self sendEventsInternal];
}

- (void)attemptToSendStoredRequests
{
    [self addEventsToQueue];
    [CountlyPersistency.sharedInstance saveToFileSync];
    [self proceedOnQueue];
}

- (void)sendEventsInternal
{
    [self addEventsToQueue];
    [self proceedOnQueue];
}

- (void)addEventsToQueue
{
    [self addEventsToQueue:nil];
}

- (void)addEventsToQueue:(CLYRequestCallback)callback
{
    NSString* events = [CountlyPersistency.sharedInstance serializedRecordedEvents];

    if (!events)
        return;

    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&%@=%@", kCountlyQSKeyEvents, events];
    [self addToQueueWithCallback:queryString callback:callback];
}

- (void)sendEventsWithCallback:(CLYRequestCallback)callback
{
    [self addEventsToQueue:callback];
    [self proceedOnQueue];
}

#pragma mark ---

- (void)sendPushToken:(NSString *)token
{
#ifndef COUNTLY_EXCLUDE_PUSHNOTIFICATIONS
    NSInteger testMode = 0; //NOTE: default is 0: Production - not test mode

    if ([CountlyPushNotifications.sharedInstance.pushTestMode isEqualToString:CLYPushTestModeDevelopment])
        testMode = 1; //NOTE: 1: Developement/Debug builds - standard test mode using Sandbox APNs
    else if ([CountlyPushNotifications.sharedInstance.pushTestMode isEqualToString:CLYPushTestModeTestFlightOrAdHoc])
        testMode = 2; //NOTE: 2: TestFlight/AdHoc builds - special test mode using Production APNs

    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&%@=%@&%@=%@&%@=%ld",
                             kCountlyQSKeyPushTokenSession, @"1",
                             kCountlyQSKeyPushTokeniOS, token,
                             kCountlyQSKeyPushTestMode, (long)testMode];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self proceedOnQueue];
#endif
}

- (void)sendLocationInfo
{
    NSString* locationRelatedInfoQueryString = [self locationRelatedInfoQueryString];

    if (!locationRelatedInfoQueryString)
        return;

    NSString* queryString = [[self queryEssentials] stringByAppendingString:locationRelatedInfoQueryString];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self proceedOnQueue];
}

- (void)sendUserDetails:(NSString *)userDetails
{
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&%@=%@",
                             kCountlyQSKeyUserDetails, userDetails];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self proceedOnQueue];
}

- (void)sendCrashReport:(NSString *)report immediately:(BOOL)immediately;
{
    // NOTE: this method is reachable from CountlySignalHandler through
    // CountlyUncaughtExceptionHandler and CountlyExceptionHandler, so every log on it stays at Debug or
    // lower. CountlyInternalLog would otherwise call into CountlyHealthTracker, which touches
    // dispatch_once, dispatch_queue_create and dispatch_async, none of which are async-signal-safe.
    if (!CountlyServerConfig.sharedInstance.networkingEnabled)
    {
        CLY_LOG_D(@"%s crash report is dropped, reason: SDK networking is disabled from server config, crash report length: [%lu]", __FUNCTION__, (unsigned long)report.length);
        return;
    }
    
    if (!report)
    {
        CLY_LOG_D(@"%s crash report is nil, converting it to JSON may have failed due to custom objects in the initial config crashSegmentation property", __FUNCTION__);
        return;
    }

    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&%@=%@",
                             kCountlyQSKeyCrash, report];

    if (!immediately)
    {
        [CountlyPersistency.sharedInstance addToQueue:queryString];
        [self proceedOnQueue];
        return;
    }

    //NOTE: Prevent `event` and `end_session` requests from being started, after `sendEvents` and `endSession` calls below.
    isCrashing = YES;

    [self sendEventsWithSaveIfNeeded];

    if (CountlyServerConfig.sharedInstance.automaticSessionTrackingEnabled)
        [self endSession];

    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
    {
        CLY_LOG_D(@"%s crash report is stored to be sent later, reason: device ID is the temporary device ID, crash report length: [%lu]", __FUNCTION__, (unsigned long)report.length);

        [CountlyPersistency.sharedInstance addToQueue:queryString];
        [CountlyPersistency.sharedInstance saveToFileSync];
        return;
    }

    [CountlyPersistency.sharedInstance saveToFileSync];

    queryString = [queryString stringByAppendingFormat:@"&%@=%@",
                   kCountlyAppVersionKey, CountlyDeviceInfo.appVersion];
    
    NSString* serverInputEndpoint = [self.host stringByAppendingString:kCountlyEndpointI];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:serverInputEndpoint]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [[self appendChecksum:queryString] cly_dataUTF8];

    CLY_LOG_I(@"%s sending crash report immediately, endpoint: [%@], method: [%@], body size: [%lu] bytes", __FUNCTION__, kCountlyEndpointI, request.HTTPMethod, (unsigned long)request.HTTPBody.length);

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    [[self.URLSession dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError*  error)
    {
        if (error || ![self isRequestSuccessful:response data:data])
        {
            CLY_LOG_D(@"[CountlyConnectionManager] sendCrashReport completion, immediate crash report request failed and it is queued to be sent later, endpoint: [%@], status code: [%ld], response size: [%ld] bytes, error domain: [%@], error code: [%ld], error description: [%@]", request.URL.path, (long)((NSHTTPURLResponse*)response).statusCode, (long)data.length, error.domain ?: @"none", (long)error.code, error.localizedDescription ?: @"none");
            [CountlyPersistency.sharedInstance addToQueue:queryString];
            [CountlyPersistency.sharedInstance saveToFileSync];
        }
        else
        {
            CLY_LOG_D(@"[CountlyConnectionManager] sendCrashReport completion, immediate crash report request completed successfully, endpoint: [%@], response size: [%ld] bytes", request.URL.path, (long)data.length);
        }

        dispatch_semaphore_signal(semaphore);

    }] resume];

    [self logRequest:request];

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)sendOldDeviceID:(NSString *)oldDeviceID
{
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&%@=%@",
                             kCountlyQSKeyDeviceIDOld, oldDeviceID.cly_URLEscaped];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self proceedOnQueue];
}

- (void)sendAttribution
{
    NSString * attributionQueryString = [self attributionQueryString];
    if (!attributionQueryString)
        return;

    NSString* queryString = [[self queryEssentials] stringByAppendingString:attributionQueryString];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self proceedOnQueue];
}

- (void)sendDirectAttributionWithCampaignID:(NSString *)campaignID andCampaignUserID:(NSString *)campaignUserID
{
    NSMutableString* queryString = [self queryEssentials].mutableCopy;
    [queryString appendFormat:@"&%@=%@", kCountlyQSKeyCampaignID, campaignID];

    if (campaignUserID.length)
    {
        [queryString appendFormat:@"&%@=%@", kCountlyQSKeyCampaignUser, campaignUserID];
    }

    CLY_LOG_I(@"%s direct attribution request is being queued, campaign ID: [%@], campaign user ID provided: [%@]", __FUNCTION__, campaignID, campaignUserID.length ? @"YES" : @"NO");

    [CountlyPersistency.sharedInstance addToQueue:queryString.copy];

    [self proceedOnQueue];
}

- (void)sendAttributionData:(NSString *)attributionData
{
    NSMutableString* queryString = [self queryEssentials].mutableCopy;
    [queryString appendFormat:@"&%@=%@", kCountlyQSKeyAttributionData, [attributionData cly_URLEscaped]];

    [CountlyPersistency.sharedInstance addToQueue:queryString.copy];

    [self proceedOnQueue];
}

- (void)sendIndirectAttribution:(NSDictionary *)attribution
{
    NSMutableString* queryString = [self queryEssentials].mutableCopy;
    [queryString appendFormat:@"&%@=%@", kCountlyQSKeyAttributionID, [attribution cly_JSONify]];

    [CountlyPersistency.sharedInstance addToQueue:queryString.copy];

    [self proceedOnQueue];
}

- (void)sendConsents:(NSString *)consents
{
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&%@=%@",
                             kCountlyQSKeyConsent, consents];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self proceedOnQueue];
}

- (void)sendPerformanceMonitoringTrace:(NSString *)trace
{
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&%@=%@",
                             kCountlyQSKeyAPM, trace];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self proceedOnQueue];
}

#pragma mark ---

- (void)sendEnrollABRequestForKeys:(NSArray*)keys
{
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&%@=%@", kCountlyQSKeyMethod, kCountlyRCKeyABOptIn];
    
    if (keys)
    {
        queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyRCKeyKeys, [keys cly_JSONify]];
    }
    
    queryString = [queryString stringByAppendingFormat:@"%@%@%@", kCountlyEndPointOverrideTag, kCountlyEndpointO, kCountlyEndpointSDK];

    [CountlyPersistency.sharedInstance addToQueue:queryString];
    
    [self proceedOnQueue];
}

- (void)sendExitABRequestForKeys:(NSArray*)keys
{
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&%@=%@", kCountlyQSKeyMethod, kCountlyRCKeyABOptOut];

    if (keys)
    {
        queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyRCKeyKeys, [keys cly_JSONify]];
    }   
    
    CLY_LOG_I(@"%s A/B test exit request is being queued, key count: [%lu]", __FUNCTION__, (unsigned long)keys.count);
    
    [CountlyPersistency.sharedInstance addToQueue:queryString];
    
    [self proceedOnQueue];
}

#pragma mark ---

- (void)addDirectRequest:(NSDictionary<NSString *, NSString *> *)requestParameters
{
    if (!CountlyConsentManager.sharedInstance.hasAnyConsent)
        return;

    NSMutableDictionary* mutableRequestParameters = requestParameters.mutableCopy;

    for (NSString * reservedKey in self.reservedQueryStringKeys)
    {
        if (mutableRequestParameters[reservedKey])
        {
            CLY_LOG_W(@"%s a reserved query string key is detected in the direct request parameters and it will be removed, key: [%@]", __FUNCTION__, reservedKey);
            [mutableRequestParameters removeObjectForKey:reservedKey];
        }
    }
    
    mutableRequestParameters[@"dr"] = [NSNumber numberWithInt:1];

    CLY_LOG_I(@"%s direct request is being queued, parameter count: [%lu]", __FUNCTION__, (unsigned long)mutableRequestParameters.count);
    NSMutableString* queryString = [self queryEssentials].mutableCopy;

    [mutableRequestParameters enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * value, BOOL * stop)
    {
        [queryString appendFormat:@"&%@=%@", key, value];
    }];

    [CountlyPersistency.sharedInstance addToQueue:queryString.copy];

    [self proceedOnQueue];
}

#pragma mark ---

- (NSString *)queryEssentials
{
    return [NSString stringWithFormat:@"%@=%@&%@=%@&%@=%d&%@=%lld&%@=%d&%@=%d&%@=%d&%@=%@&%@=%@",
        kCountlyQSKeyAppKey, self.appKey.cly_URLEscaped,
        kCountlyQSKeyDeviceID, CountlyDeviceInfo.sharedInstance.deviceID.cly_URLEscaped,
        kCountlyQSKeyDeviceIDType, (int)CountlyDeviceInfo.sharedInstance.deviceIDTypeValue,
        kCountlyQSKeyTimestamp, (long long)(CountlyCommon.sharedInstance.uniqueTimestamp * 1000),
        kCountlyQSKeyTimeHourOfDay, (int)CountlyCommon.sharedInstance.hourOfDay,
        kCountlyQSKeyTimeDayOfWeek, (int)CountlyCommon.sharedInstance.dayOfWeek,
        kCountlyQSKeyTimeZone, (int)CountlyCommon.sharedInstance.timeZone,
        kCountlyQSKeySDKVersion, CountlyCommon.sharedInstance.SDKVersion,
        kCountlyQSKeySDKName, CountlyCommon.sharedInstance.SDKName];
}


- (NSArray *)reservedQueryStringKeys
{
    return
    @[
        kCountlyQSKeyAppKey,
        kCountlyQSKeyDeviceID,
        kCountlyQSKeyDeviceIDType,
        kCountlyQSKeyTimestamp,
        kCountlyQSKeyTimeHourOfDay,
        kCountlyQSKeyTimeDayOfWeek,
        kCountlyQSKeyTimeZone,
        kCountlyQSKeySDKVersion,
        kCountlyQSKeySDKName,
        kCountlyQSKeyDeviceID,
        kCountlyQSKeyDeviceIDOld,
        kCountlyQSKeyChecksum256,
    ];
}


- (NSString *)locationRelatedInfoQueryString
{
    if (!CountlyConsentManager.sharedInstance.consentForLocation || CountlyLocationManager.sharedInstance.isLocationInfoDisabled)
    {
        //NOTE: Return empty string for location. This is a server requirement to disable IP based location inferring.
        return [NSString stringWithFormat:@"&%@=%@", kCountlyQSKeyLocation, @""];
    }

    NSString* location = CountlyLocationManager.sharedInstance.location.cly_URLEscaped;
    NSString* city = CountlyLocationManager.sharedInstance.city.cly_URLEscaped;
    NSString* ISOCountryCode = CountlyLocationManager.sharedInstance.ISOCountryCode.cly_URLEscaped;
    NSString* IP = CountlyLocationManager.sharedInstance.IP.cly_URLEscaped;

    NSMutableString* locationInfoQueryString = NSMutableString.new;

    if (location)
        [locationInfoQueryString appendFormat:@"&%@=%@", kCountlyQSKeyLocation, location];

    if (city)
        [locationInfoQueryString appendFormat:@"&%@=%@", kCountlyQSKeyLocationCity, city];

    if (ISOCountryCode)
        [locationInfoQueryString appendFormat:@"&%@=%@", kCountlyQSKeyLocationCountry, ISOCountryCode];

    if (IP)
        [locationInfoQueryString appendFormat:@"&%@=%@", kCountlyQSKeyLocationIP, IP];

    if (locationInfoQueryString.length)
        return locationInfoQueryString.copy;

    return nil;
}

- (NSString *)attributionQueryString
{
    if (!CountlyConsentManager.sharedInstance.consentForAttribution)
        return nil;

    if (!CountlyCommon.sharedInstance.attributionID)
        return nil;

    NSDictionary* attribution = @{kCountlyQSKeyIDFA: CountlyCommon.sharedInstance.attributionID};

    return [NSString stringWithFormat:@"&%@=%@", kCountlyQSKeyAttributionID, [attribution cly_JSONify]];
}

- (NSMutableData *)pictureUploadDataForQueryString:(NSString *)queryString
{
#if (TARGET_OS_IOS || TARGET_OS_VISION)
    NSString* localPicturePath = nil;

    NSString* userDetails = [queryString cly_valueForQueryStringKey:kCountlyQSKeyUserDetails];
    NSString* unescapedUserDetails = [userDetails stringByRemovingPercentEncoding];
    if (!unescapedUserDetails)
        return nil;

    NSDictionary* pathDictionary = [NSJSONSerialization JSONObjectWithData:[unescapedUserDetails cly_dataUTF8] options:0 error:nil];
    localPicturePath = pathDictionary[kCountlyLocalPicturePath];

    if (!localPicturePath.length)
        return nil;

    CLY_LOG_D(@"%s local picture path is extracted from the query string, path length: [%lu], file extension: [%@]", __FUNCTION__, (unsigned long)localPicturePath.length, localPicturePath.pathExtension.lowercaseString);

    NSArray* allowedFileTypes = @[@"gif", @"png", @"jpg", @"jpeg"];
    NSString* fileExt = localPicturePath.pathExtension.lowercaseString;
    NSInteger fileExtIndex = [allowedFileTypes indexOfObject:fileExt];

    if (fileExtIndex == NSNotFound)
    {
        CLY_LOG_W(@"%s picture upload is skipped, reason: unsupported file extension, extension: [%@]", __FUNCTION__, fileExt);
        return nil;
    }

    NSData* imageData = [NSData dataWithContentsOfURL:[NSURL URLWithString:localPicturePath]];

    if (!imageData)
    {
        CLY_LOG_W(@"%s picture upload is skipped, reason: local picture data can not be read, extension: [%@]", __FUNCTION__, fileExt);
        return nil;
    }

    CLY_LOG_D(@"%s local picture data is read successfully, size: [%lu] bytes", __FUNCTION__, (unsigned long)imageData.length);

    //NOTE: Overcome failing PNG file upload if data is directly read from disk
    if (fileExtIndex == 1)
        imageData = UIImagePNGRepresentation([UIImage imageWithData:imageData]);

    //NOTE: Remap content type from jpg to jpeg
    if (fileExtIndex == 2)
        fileExtIndex = 3;

    NSString* boundaryStart = [NSString stringWithFormat:@"--%@\r\n", kCountlyUploadBoundary];
    NSString* contentDisposition = [NSString stringWithFormat:@"Content-Disposition: form-data; name=\"pictureFile\"; filename=\"%@\"\r\n", localPicturePath.lastPathComponent];
    NSString* contentType = [NSString stringWithFormat:@"Content-Type: image/%@\r\n\r\n", allowedFileTypes[fileExtIndex]];

    NSMutableData* uploadData = NSMutableData.new;
    [uploadData appendData:[boundaryStart cly_dataUTF8]];
    [uploadData appendData:[contentDisposition cly_dataUTF8]];
    [uploadData appendData:[contentType cly_dataUTF8]];
    [uploadData appendData:imageData];
    return uploadData;
#endif
    return nil;
}

- (void)addMultipart:(NSMutableData *)uploadData andKey:(NSString *)key andValue:(NSString *)value
{
    NSString* boundaryStart = [NSString stringWithFormat:@"\r\n--%@\r\n", kCountlyUploadBoundary];
    NSString* contentDisposition = [NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\";\r\n\r\n", key];

    [uploadData appendData:[boundaryStart cly_dataUTF8]];
    [uploadData appendData:[contentDisposition cly_dataUTF8]];
    [uploadData appendData:[value cly_dataUTF8]];
}

- (NSString *)appendChecksum:(NSString *)queryString
{
    if (self.secretSalt)
    {
        NSString* checksum = [[queryString stringByAppendingString:self.secretSalt] cly_SHA256];
        CLY_LOG_V(@"%s checksum is appended to the query string, query string length: [%lu]", __FUNCTION__, (unsigned long)queryString.length);
        return [queryString stringByAppendingFormat:@"&%@=%@", kCountlyQSKeyChecksum256, checksum];
    }

    return queryString;
}

- (NSString *)appendRemainingRequest:(NSString *)queryString
{
    NSUInteger rrCount = [CountlyPersistency.sharedInstance remainingRequestCount] - 1;
    return [queryString stringByAppendingFormat:@"&%@=%lu", kCountlyQSKeyRemainingRequest, (unsigned long)rrCount];
    
    return queryString;
}

- (BOOL)isRequestSuccessful:(NSURLResponse *)response data:(NSData *)data 
{
    if (!response)
        return NO;

    NSInteger code = ((NSHTTPURLResponse*)response).statusCode;

    if (code >= 200 && code < 300)
    {
        NSError* error = nil;
        NSDictionary* serverReply = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error]; 

        if (error)
        {
            CLY_LOG_E(@"%s server reply is not a valid JSON, the request is considered failed, response size: [%ld] bytes, error description: [%@]", __FUNCTION__, (long)data.length, error.localizedDescription);
            return NO;
        }
        
        CLY_LOG_D(@"%s server reply detail, full response URL: [%@], parsed server reply: [%@]", __FUNCTION__, response.URL.absoluteString, serverReply);

        NSString* result = serverReply[@"result"];
        
        if(result)
        {
            return YES;
        }

        CLY_LOG_E(@"%s server reply does not contain the result field, the request is considered failed, response size: [%ld] bytes", __FUNCTION__, (long)data.length);
        
        return NO;
        
    }
    else
    {
        CLY_LOG_V(@"%s HTTP status code is not in the 2XX series, status code: [%ld], response size: [%ld] bytes", __FUNCTION__, (long)code, (long)data.length);
        CLY_LOG_D(@"%s non 2XX response detail, full response URL: [%@]", __FUNCTION__, response.URL.absoluteString);
        return NO;        
    }
}

- (NSInteger)sessionLengthInSeconds
{
    NSTimeInterval currentTime = NSDate.date.timeIntervalSince1970;
    unsentSessionLength += (currentTime - lastSessionStartTime);
    lastSessionStartTime = currentTime;
    int sessionLengthInSeconds = (int)unsentSessionLength;
    unsentSessionLength -= sessionLengthInSeconds;
    return sessionLengthInSeconds;
}

#pragma mark ---

- (NSURLSession *)URLSession
{
    if (!_URLSession)
    {
        if (self.pinnedCertificates)
        {
            CLY_LOG_D(@"%s creating the URL session with certificate pinning, pinned certificate count: [%d]", __FUNCTION__, (int)self.pinnedCertificates.count);
            _URLSession = [NSURLSession sessionWithConfiguration:self.URLSessionConfiguration delegate:self delegateQueue:nil];
        }
        else
        {
            _URLSession = [NSURLSession sessionWithConfiguration:self.URLSessionConfiguration];
        }
    }

    return _URLSession;
}

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler
{
    SecPolicyRef policy = SecPolicyCreateSSL(true, (__bridge CFStringRef)challenge.protectionSpace.host);
    SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
    SecKeyRef serverKey = NULL;

    if (@available(iOS 14.0, tvOS 14.0, macOS 11.0, watchOS 7.0, *))
    {
        serverKey = SecTrustCopyKey(serverTrust);
    }
    else
    {
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
        serverKey = SecTrustCopyPublicKey(serverTrust);
#pragma GCC diagnostic pop
    }

    __block BOOL isLocalAndServerCertMatch = NO;

    for (NSString* certificate in self.pinnedCertificates)
    {
        NSString* localCertPath = [NSBundle.mainBundle pathForResource:certificate ofType:nil];

        if (!localCertPath)
           [NSException raise:@"CountlyCertificateNotFoundException" format:@"Bundled certificate can not be found for %@", certificate];

        NSData* localCertData = [NSData dataWithContentsOfFile:localCertPath];
        SecCertificateRef localCert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)localCertData);
        SecTrustRef localTrust = NULL;
        SecTrustCreateWithCertificates(localCert, policy, &localTrust);
        SecKeyRef localKey = NULL;

        if (@available(iOS 14.0, tvOS 14.0, macOS 11.0, watchOS 7.0, *))
        {
            localKey = SecTrustCopyKey(localTrust);
        }
        else
        {
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
            localKey = SecTrustCopyPublicKey(localTrust);
#pragma GCC diagnostic pop
        }

        CFRelease(localCert);
        CFRelease(localTrust);

        if (serverKey != NULL && localKey != NULL && [(__bridge id)serverKey isEqual:(__bridge id)localKey])
        {
            CLY_LOG_D(@"%s pinned certificate and server certificate match", __FUNCTION__);

            isLocalAndServerCertMatch = YES;
            CFRelease(localKey);
            break;
        }

        if (localKey)
            CFRelease(localKey);
    }
    
#if DEBUG
    if (CountlyCommon.sharedInstance.shouldIgnoreTrustCheck)
    {
        CFDataRef exceptions = SecTrustCopyExceptions(serverTrust);
        SecTrustSetExceptions(serverTrust, exceptions);
        CFRelease(exceptions);
    }
#endif
    
    SecTrustResultType serverTrustResult;
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
    SecTrustEvaluate(serverTrust, &serverTrustResult);
#pragma GCC diagnostic pop
    BOOL isServerCertValid = (serverTrustResult == kSecTrustResultUnspecified || serverTrustResult == kSecTrustResultProceed);

    if (isLocalAndServerCertMatch && isServerCertValid)
    {
        CLY_LOG_D(@"%s pinned certificate check is successful, proceeding with the request, host: [%@]", __FUNCTION__, challenge.protectionSpace.host);
        completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:serverTrust]);
    }
    else
    {
        if (!isLocalAndServerCertMatch)
            CLY_LOG_D(@"%s pinned certificate and server certificate do not match", __FUNCTION__);

        if (!isServerCertValid)
            CLY_LOG_D(@"%s server certificate is not valid, SecTrustEvaluate result: [%u]", __FUNCTION__, (unsigned int)serverTrustResult);

        CLY_LOG_E(@"%s pinned certificate check failed, cancelling the request, host: [%@]", __FUNCTION__, challenge.protectionSpace.host);
        completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, NULL);
    }

    if (serverKey)
        CFRelease(serverKey);

    CFRelease(policy);
}

#pragma mark - Request Callbacks

- (void)registerRequestCallback:(NSString *)callbackID callback:(CLYRequestCallback)callback
{
    if (!callbackID || callbackID.length == 0)
    {
        CLY_LOG_W(@"%s request callback registration is ignored, reason: callback ID is nil or empty", __FUNCTION__);
        return;
    }

    if (!callback)
    {
        CLY_LOG_W(@"%s request callback registration is ignored, reason: callback block is nil, callback ID: [%@]", __FUNCTION__, callbackID);
        return;
    }

    dispatch_sync(_callbackQueue, ^{
        CLY_LOG_D(@"[CountlyConnectionManager] registerRequestCallback, registering a request callback, callback ID: [%@], registered callback count before registration: [%lu]", callbackID, (unsigned long)self.internalRequestCallbacks.count);
        self.internalRequestCallbacks[callbackID] = callback;
    });
}

- (void)removeRequestCallback:(NSString *)callbackID
{
    if (!callbackID || callbackID.length == 0)
    {
        CLY_LOG_W(@"%s request callback removal is ignored, reason: callback ID is nil or empty", __FUNCTION__);
        return;
    }

    dispatch_sync(_callbackQueue, ^{
        CLY_LOG_D(@"[CountlyConnectionManager] removeRequestCallback, removing a request callback, callback ID: [%@], registered callback count before removal: [%lu]", callbackID, (unsigned long)self.internalRequestCallbacks.count);
        [self.internalRequestCallbacks removeObjectForKey:callbackID];
    });
}

- (void)addQueueFlushRunnable:(CLYQueueFlushRunnable)runnable
{
    if (!runnable)
    {
        CLY_LOG_W(@"%s queue flush runnable is not added, reason: runnable is nil", __FUNCTION__);
        return;
    }

    CLYQueueFlushRunnable runnableCopy = [runnable copy];
    dispatch_sync(_callbackQueue, ^{
        CLY_LOG_D(@"[CountlyConnectionManager] addQueueFlushRunnable, adding a queue flush runnable, total runnable count: [%lu]", (unsigned long)(self->_queueFlushRunnables.count + 1));
        [self->_queueFlushRunnables addObject:runnableCopy];
    });
}

- (void)clearQueueFlushRunnables
{
    dispatch_sync(_callbackQueue, ^{
        CLY_LOG_D(@"[CountlyConnectionManager] clearQueueFlushRunnables, clearing all queue flush runnables, count: [%lu]", (unsigned long)self->_queueFlushRunnables.count);
        [self->_queueFlushRunnables removeAllObjects];
    });
}

- (void)addToQueueWithCallback:(NSString *)queryString callback:(CLYRequestCallback)callback
{
    // NOTE: reachable from CountlySignalHandler through sendCrashReport, keep every log here at
    // Debug or lower. See the note on sendCrashReport.
    if (!queryString || queryString.length == 0)
    {
        CLY_LOG_D(@"%s request is not queued, reason: query string is nil or empty, callback provided: [%@]", __FUNCTION__, (callback != nil) ? @"YES" : @"NO");
        return;
    }

    if (!callback)
    {
        [CountlyPersistency.sharedInstance addToQueue:queryString];
        return;
    }

    // Generate a unique callback ID
    NSString* callbackID = [[NSUUID UUID] UUIDString];
    CLY_LOG_D(@"%s queueing a request with a callback, callback ID: [%@], query string length: [%lu]", __FUNCTION__, callbackID, (unsigned long)queryString.length);

    // Register the callback
    [self registerRequestCallback:callbackID callback:callback];

    // Append callback_id parameter to query string
    NSString* queryStringWithCallback = [queryString stringByAppendingFormat:@"&callback_id=%@", callbackID];

    // Add to queue
    [CountlyPersistency.sharedInstance addToQueue:queryStringWithCallback];
}

@end
