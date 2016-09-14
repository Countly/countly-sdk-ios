// CountlyConnectionManager.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

NSString* const kCountlySDKVersion = @"16.06.4";
NSString* const kCountlySDKName = @"objc-native-ios";

@interface CountlyConnectionManager()
#if TARGET_OS_IOS
@property (nonatomic) UIBackgroundTaskIdentifier bgTask;
#endif
@end

@implementation CountlyConnectionManager : NSObject

+ (instancetype)sharedInstance
{
    static CountlyConnectionManager *s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (void)tick
{
    if (self.connection != nil)
        return;

    if (self.customHeaderFieldName && !self.customHeaderFieldValue)
    {
        COUNTLY_LOG(@"customHeaderFieldName specified on config, but customHeaderFieldValue not set! Requests are postponed!");
        return;
    }

    NSString* firstItemInQueue = [CountlyPersistency.sharedInstance firstItemInQueue];
    if (firstItemInQueue == nil)
        return;

    [self startBackgroundTask];

    NSString* queryString = firstItemInQueue;

    if(self.secretSalt)
    {
        NSString* checksum = [[queryString stringByAppendingString:self.secretSalt] SHA1];
        queryString = [queryString stringByAppendingFormat:@"&checksum=%@", checksum];
    }

    //NOTE: For Limit Ad Tracking zero-IDFA problem
    if([queryString rangeOfString:@"&device_id=00000000-0000-0000-0000-000000000000"].location != NSNotFound)
    {
        COUNTLY_LOG(@"Detected a request with device_id=[zero-IDFA] in queue and fixed.");

        queryString = [queryString stringByReplacingOccurrencesOfString:@"&device_id=00000000-0000-0000-0000-000000000000" withString:[@"&device_id=" stringByAppendingString:CountlyDeviceInfo.sharedInstance.deviceID]];
    }

    if([queryString rangeOfString:@"&old_device_id=00000000-0000-0000-0000-000000000000"].location != NSNotFound)
    {
        COUNTLY_LOG(@"Detected a request with old_device_id=[zero-IDFA] in queue and fixed.");

        [CountlyPersistency.sharedInstance removeFromQueue:firstItemInQueue];
        [self tick];
    }

    NSString* countlyServerEndpoint = [self.appHost stringByAppendingString:@"/i"];
    NSString* fullRequestURL = [countlyServerEndpoint stringByAppendingFormat:@"?%@", queryString];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:fullRequestURL]];

    NSData* pictureUploadData = [CountlyUserDetails.sharedInstance pictureUploadDataForRequest:queryString];
    if(pictureUploadData)
    {
        NSString *contentType = [@"multipart/form-data; boundary=" stringByAppendingString:self.boundary];
        [request addValue:contentType forHTTPHeaderField: @"Content-Type"];
        request.HTTPMethod = @"POST";
        request.HTTPBody = pictureUploadData;
    }
    else if(queryString.length > 2048 || self.alwaysUsePOST)
    {
        request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:countlyServerEndpoint]];
        request.HTTPMethod = @"POST";
        request.HTTPBody = [queryString dataUTF8];
    }

    if(self.customHeaderFieldName && self.customHeaderFieldValue)
        [request setValue:self.customHeaderFieldValue forHTTPHeaderField:self.customHeaderFieldName];

    NSURLSession* session = NSURLSession.sharedSession;

    if(self.pinnedCertificates)
    {
        COUNTLY_LOG(@"%i pinned certificate(s) specified in config.", self.pinnedCertificates.count);
        NSURLSessionConfiguration *sc = [NSURLSessionConfiguration defaultSessionConfiguration];
        session = [NSURLSession sessionWithConfiguration:sc delegate:self delegateQueue:nil];
    }

    self.connection = [session dataTaskWithRequest:request
    completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error)
    {
        self.connection = nil;

        if(!error)
        {
            if([self isRequestSuccessful:response])
            {
                COUNTLY_LOG(@"Request <%p> successfully completed.", request);

                [CountlyPersistency.sharedInstance removeFromQueue:firstItemInQueue];

                [CountlyPersistency.sharedInstance saveToFile];

                [self tick];
            }
            else
            {
                COUNTLY_LOG(@"Request <%p> failed!\nServer reply: %@", request, [data stringUTF8]);
            }
        }
        else
        {
            COUNTLY_LOG(@"Request <%p> failed!\nError: %@", request, error);
#if TARGET_OS_WATCH
            [CountlyPersistency.sharedInstance saveToFile];
#endif
        }

        [self finishBackgroundTask];
    }];

    [self.connection resume];

    COUNTLY_LOG(@"Request <%p> started:\n[%@] %@ \n%@", (id)request, request.HTTPMethod, request.URL.absoluteString, request.HTTPBody?([request.HTTPBody stringUTF8]?[request.HTTPBody stringUTF8]:@"Picture uploading..."):@"");
}

#pragma mark ---

- (void)beginSession
{
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&begin_session=1&metrics=%@", [CountlyDeviceInfo metrics]];

    NSString* optionalParameters = [CountlyCommon.sharedInstance optionalParameters];
    if(optionalParameters)
        queryString = [queryString stringByAppendingString:optionalParameters];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self tick];
}

- (void)updateSessionWithDuration:(int)duration
{
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&session_duration=%d", duration];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self tick];
}

- (void)endSessionWithDuration:(int)duration
{
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&end_session=1&session_duration=%d", duration];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self tick];
}

- (void)sendEvents
{
    NSString* events = [CountlyPersistency.sharedInstance serializedRecordedEvents];

    if(!events)
        return;

    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&events=%@", events];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self tick];
}

#pragma mark ---

- (void)sendPushToken:(NSString *)token
{
    // Test modes: 0 = Production build,
    //             1 = Development build,
    //             2 = AdHoc build (when isTestDevice flag on config object is set explicitly)

    int testMode;
#ifndef __OPTIMIZE__
    testMode = 1;
#else
    testMode = self.isTestDevice ? 2 : 0;
#endif

    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&token_session=1&ios_token=%@&test_mode=%d",
                             [token length] ? token : @"",
                             testMode];

    // Not right now to prevent race with begin_session=1 when adding new user
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^
    {
        COUNTLY_LOG(@"Sending APNS token in mode %d", testMode);
        [CountlyPersistency.sharedInstance addToQueue:queryString];
        [self tick];
    });
}

- (void)sendUserDetails:(NSString *)userDetails
{
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&user_details=%@", userDetails];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self tick];
}

- (void)sendCrashReportLater:(NSString *)report
{
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&crash=%@", report];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [CountlyPersistency.sharedInstance saveToFileSync];
}

- (void)sendOldDeviceID:(NSString *)oldDeviceID
{
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&old_device_id=%@", oldDeviceID];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self tick];
}

- (void)sendParentDeviceID:(NSString *)parentDeviceID
{
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&parent_device_id=%@", parentDeviceID];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self tick];
}

- (void)sendLocation:(CLLocationCoordinate2D)coordinate
{
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&location=%f,%f", coordinate.latitude, coordinate.longitude];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self tick];
}

#pragma mark ---

- (void)startBackgroundTask
{
#if TARGET_OS_IOS
    if (self.bgTask != UIBackgroundTaskInvalid)
        return;

    self.bgTask = [UIApplication.sharedApplication beginBackgroundTaskWithExpirationHandler:^
    {
        [UIApplication.sharedApplication endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }];
#endif
}

- (void)finishBackgroundTask
{
#if TARGET_OS_IOS
    if (self.bgTask != UIBackgroundTaskInvalid && !self.connection)
    {
        [UIApplication.sharedApplication endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }
#endif
}

#pragma mark ---

- (NSString *)queryEssentials
{
    return [NSString stringWithFormat:@"app_key=%@&device_id=%@&timestamp=%ld&hour=%ld&dow=%ld&tz=%ld&sdk_version=%@&sdk_name=%@",
                                        self.appKey,
                                        CountlyDeviceInfo.sharedInstance.deviceID,
                                        (long)(CountlyCommon.sharedInstance.uniqueTimestamp * 1000),
                                        (long)CountlyCommon.sharedInstance.hourOfDay,
                                        (long)CountlyCommon.sharedInstance.dayOfWeek,
                                        (long)CountlyCommon.sharedInstance.timeZone,
                                        kCountlySDKVersion,
                                        kCountlySDKName];
}

- (NSString *)boundary
{
    return @"0cae04a8b698d63ff6ea55d168993f21";
}

- (BOOL)isRequestSuccessful:(NSURLResponse *)response
{
    if(!response)
        return NO;

    NSInteger code = ((NSHTTPURLResponse*)response).statusCode;

    return (code >= 200 && code < 300);
}

#pragma mark ---

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler
{
    SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
    SecKeyRef serverKey = SecTrustCopyPublicKey(serverTrust);
    SecPolicyRef policy = SecPolicyCreateSSL(true, (__bridge CFStringRef)challenge.protectionSpace.host);

    __block BOOL isLocalAndServerCertMatch = NO;

    for (NSString* certificate in self.pinnedCertificates )
    {
        NSString* localCertPath = [NSBundle.mainBundle pathForResource:certificate ofType:nil];
        NSAssert(localCertPath != nil, @"[CountlyAssert] Bundled certificate can not be found");
        NSData* localCertData = [NSData dataWithContentsOfFile:localCertPath];
        SecCertificateRef localCert = SecCertificateCreateWithData(NULL, (__bridge CFDataRef)localCertData);
        SecTrustRef localTrust = NULL;
        SecTrustCreateWithCertificates(localCert, policy, &localTrust);
        SecKeyRef localKey = SecTrustCopyPublicKey(localTrust);

        CFRelease(localCert);
        CFRelease(localTrust);

        if (serverKey != NULL && localKey != NULL && [(__bridge id)serverKey isEqual:(__bridge id)localKey])
        {
            COUNTLY_LOG(@"Pinned certificate and server certificate match.");

            isLocalAndServerCertMatch = YES;
            CFRelease(localKey);
            break;
        }

        if(localKey) CFRelease(localKey);
    }

    SecTrustResultType serverTrustResult;
    SecTrustEvaluate(serverTrust, &serverTrustResult);
    BOOL isServerCertValid = (serverTrustResult == kSecTrustResultUnspecified || serverTrustResult == kSecTrustResultProceed);

    if (isLocalAndServerCertMatch && isServerCertValid)
    {
        COUNTLY_LOG(@"Pinned certificate check is successful. Proceeding with request.");
        completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:serverTrust]);
    }
    else
    {
        COUNTLY_LOG(@"Pinned certificate check is failed! Cancelling request.");
        completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, NULL);
    }

    if (serverKey) CFRelease(serverKey);
    CFRelease(policy);
}

@end
