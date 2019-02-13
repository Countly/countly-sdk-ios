// CountlyConnectionManager.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface CountlyConnectionManager ()
{
    NSTimeInterval unsentSessionLength;
    NSTimeInterval lastSessionStartTime;
    BOOL isCrashing;
}
@end

NSString* const kCountlyQSKeyAppKey           = @"app_key";

NSString* const kCountlyQSKeyDeviceID         = @"device_id";
NSString* const kCountlyQSKeyDeviceIDOld      = @"old_device_id";
NSString* const kCountlyQSKeyDeviceIDParent   = @"parent_device_id";

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

NSString* const kCountlyQSKeyMetrics          = @"metrics";
NSString* const kCountlyQSKeyEvents           = @"events";
NSString* const kCountlyQSKeyUserDetails      = @"user_details";
NSString* const kCountlyQSKeyCrash            = @"crash";
NSString* const kCountlyQSKeyChecksum256      = @"checksum256";
NSString* const kCountlyQSKeyAttributionID    = @"aid";
NSString* const kCountlyQSKeyConsent          = @"consent";

NSString* const kCountlyUploadBoundary = @"0cae04a8b698d63ff6ea55d168993f21";
NSString* const kCountlyInputEndpoint = @"/i";
const NSInteger kCountlyGETRequestMaxLength = 2048;

@implementation CountlyConnectionManager : NSObject

+ (instancetype)sharedInstance
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return nil;

    static CountlyConnectionManager *s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    if (self = [super init])
    {
        unsentSessionLength = 0.0;
    }

    return self;
}

- (void)proceedOnQueue
{
    COUNTLY_LOG(@"Proceeding on queue...");

    if (self.connection)
    {
        COUNTLY_LOG(@"Proceeding on queue is aborted: Already has a request in process!");
        return;
    }

    if (isCrashing)
    {
        COUNTLY_LOG(@"Proceeding on queue is aborted: Application is crashing!");
        return;
    }

    if (self.customHeaderFieldName && !self.customHeaderFieldValue)
    {
        COUNTLY_LOG(@"Proceeding on queue is aborted: customHeaderFieldName specified on config, but customHeaderFieldValue not set yet!");
        return;
    }

    NSString* firstItemInQueue = [CountlyPersistency.sharedInstance firstItemInQueue];
    if (!firstItemInQueue)
    {
        COUNTLY_LOG(@"Queue is empty. All requests are processed.");
        return;
    }

    if ([firstItemInQueue isEqual:NSNull.null])
    {
        COUNTLY_LOG(@"Detected an NSNull in queue and removed.");

        [CountlyPersistency.sharedInstance removeFromQueue:firstItemInQueue];
        [self proceedOnQueue];
        return;
    }

    [CountlyCommon.sharedInstance startBackgroundTask];

    NSString* queryString = firstItemInQueue;

    if (self.applyZeroIDFAFix)
    {
        NSString* deviceIDZeroIDFA = [NSString stringWithFormat:@"&%@=%@", kCountlyQSKeyDeviceID, kCountlyZeroIDFA];
        NSString* oldDeviceIDZeroIDFA = [NSString stringWithFormat:@"&%@=%@", kCountlyQSKeyDeviceIDOld, kCountlyZeroIDFA];
        NSString* deviceIDFixed = [NSString stringWithFormat:@"&%@=%@", kCountlyQSKeyDeviceID, CountlyDeviceInfo.sharedInstance.deviceID.cly_URLEscaped];

        if ([queryString containsString:deviceIDZeroIDFA])
        {
            COUNTLY_LOG(@"Detected a request with zero-IDFA in queue and fixed.");

            queryString = [queryString stringByReplacingOccurrencesOfString:deviceIDZeroIDFA withString:deviceIDFixed];
        }

        if ([queryString containsString:oldDeviceIDZeroIDFA])
        {
            COUNTLY_LOG(@"Detected a request with zero-IDFA in queue and removed.");

            [CountlyPersistency.sharedInstance removeFromQueue:firstItemInQueue];
            [self proceedOnQueue];
            return;
        }
    }

    queryString = [self appendChecksum:queryString];

    NSString* serverInputEndpoint = [self.host stringByAppendingString:kCountlyInputEndpoint];
    NSString* fullRequestURL = [serverInputEndpoint stringByAppendingFormat:@"?%@", queryString];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:fullRequestURL]];

    NSData* pictureUploadData = [self pictureUploadDataForRequest:queryString];
    if (pictureUploadData)
    {
        NSString *contentType = [@"multipart/form-data; boundary=" stringByAppendingString:kCountlyUploadBoundary];
        [request addValue:contentType forHTTPHeaderField: @"Content-Type"];
        request.HTTPMethod = @"POST";
        request.HTTPBody = pictureUploadData;
    }
    else if (queryString.length > kCountlyGETRequestMaxLength || self.alwaysUsePOST)
    {
        request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:serverInputEndpoint]];
        request.HTTPMethod = @"POST";
        request.HTTPBody = [queryString cly_dataUTF8];
    }

    if (self.customHeaderFieldName && self.customHeaderFieldValue)
        [request setValue:self.customHeaderFieldValue forHTTPHeaderField:self.customHeaderFieldName];

    self.connection = [[self URLSession] dataTaskWithRequest:request completionHandler:^(NSData * data, NSURLResponse * response, NSError * error)
    {
        self.connection = nil;

        if (!error)
        {
            if ([self isRequestSuccessful:response])
            {
                COUNTLY_LOG(@"Request <%p> successfully completed.", request);

                [CountlyPersistency.sharedInstance removeFromQueue:firstItemInQueue];

                [CountlyPersistency.sharedInstance saveToFile];

                [self proceedOnQueue];
            }
            else
            {
                COUNTLY_LOG(@"Request <%p> failed!\nServer reply: %@", request, [data cly_stringUTF8]);
            }
        }
        else
        {
            COUNTLY_LOG(@"Request <%p> failed!\nError: %@", request, error);
#if TARGET_OS_WATCH
            [CountlyPersistency.sharedInstance saveToFile];
#endif
        }
    }];

    [self.connection resume];

    COUNTLY_LOG(@"Request <%p> started:\n[%@] %@ \n%@", (id)request, request.HTTPMethod, request.URL.absoluteString, request.HTTPBody ? ([request.HTTPBody cly_stringUTF8] ?: @"Picture uploading...") : @"");
}

#pragma mark ---

- (void)beginSession
{
    if (!CountlyConsentManager.sharedInstance.consentForSessions)
        return;

    lastSessionStartTime = NSDate.date.timeIntervalSince1970;
    unsentSessionLength = 0.0;

    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&%@=%@&%@=%@",
                             kCountlyQSKeySessionBegin, @"1",
                             kCountlyQSKeyMetrics, [CountlyDeviceInfo metrics]];

    if (!CountlyConsentManager.sharedInstance.consentForLocation || CountlyLocationManager.sharedInstance.isLocationInfoDisabled)
        queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyQSKeyLocation, @""];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self proceedOnQueue];
}

- (void)updateSession
{
    if (!CountlyConsentManager.sharedInstance.consentForSessions)
        return;

    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&%@=%d",
                             kCountlyQSKeySessionDuration, (int)[self sessionLengthInSeconds]];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self proceedOnQueue];
}

- (void)endSession
{
    if (!CountlyConsentManager.sharedInstance.consentForSessions)
        return;

    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&%@=%@&%@=%d",
                             kCountlyQSKeySessionEnd, @"1",
                             kCountlyQSKeySessionDuration, (int)[self sessionLengthInSeconds]];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self proceedOnQueue];
}

#pragma mark ---

- (void)sendEvents
{
    NSString* events = [CountlyPersistency.sharedInstance serializedRecordedEvents];

    if (!events)
        return;

    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&%@=%@",
                             kCountlyQSKeyEvents, events];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self proceedOnQueue];
}

#pragma mark ---

- (void)sendPushToken:(NSString *)token
{
    typedef enum : NSInteger
    {
        CLYPushTokenModeProduction,
        CLYPushTokenModeDevelopment,
        CLYPushTokenModeAdHoc,
    } CLYPushTokenMode;

    int testMode;
#ifdef DEBUG
    testMode = CLYPushTokenModeDevelopment;
#else
    testMode = CountlyPushNotifications.sharedInstance.isTestDevice ? CLYPushTokenModeAdHoc : CLYPushTokenModeProduction;
#endif

    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&%@=%@&%@=%@&%@=%d",
                             kCountlyQSKeyPushTokenSession, @"1",
                             kCountlyQSKeyPushTokeniOS, token,
                             kCountlyQSKeyPushTestMode, testMode];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self proceedOnQueue];
}

- (void)sendLocationInfo
{
    NSString* location = CountlyLocationManager.sharedInstance.location.cly_URLEscaped;
    NSString* city = CountlyLocationManager.sharedInstance.city.cly_URLEscaped;
    NSString* ISOCountryCode = CountlyLocationManager.sharedInstance.ISOCountryCode.cly_URLEscaped;
    NSString* IP = CountlyLocationManager.sharedInstance.IP.cly_URLEscaped;

    if (!(location || city || ISOCountryCode || IP))
        return;

    NSString* queryString = [self queryEssentials];

    if (location)
        queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyQSKeyLocation, location];

   if (city)
        queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyQSKeyLocationCity, city];

    if (ISOCountryCode)
        queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyQSKeyLocationCountry, ISOCountryCode];

    if (IP)
        queryString = [queryString stringByAppendingFormat:@"&%@=%@", kCountlyQSKeyLocationIP, IP];

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

    [self sendEvents];

    if (!CountlyCommon.sharedInstance.manualSessionHandling)
        [self endSession];

    if (self.customHeaderFieldName && !self.customHeaderFieldValue)
    {
        COUNTLY_LOG(@"customHeaderFieldName specified on config, but customHeaderFieldValue not set! Crash report stored to be sent later!");

        [CountlyPersistency.sharedInstance addToQueue:queryString];
        [CountlyPersistency.sharedInstance saveToFileSync];
        return;
    }

    [CountlyPersistency.sharedInstance saveToFileSync];

    NSString* serverInputEndpoint = [self.host stringByAppendingString:kCountlyInputEndpoint];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:serverInputEndpoint]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [[self appendChecksum:queryString] cly_dataUTF8];

    if (self.customHeaderFieldName && self.customHeaderFieldValue)
        [request setValue:self.customHeaderFieldValue forHTTPHeaderField:self.customHeaderFieldName];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    [[[self URLSession] dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError*  error)
    {
        if (error || ![self isRequestSuccessful:response])
        {
            COUNTLY_LOG(@"Crash Report Request <%p> failed!\n%@: %@", request, error ? @"Error" : @"Server reply", error ?: [data cly_stringUTF8]);
            [CountlyPersistency.sharedInstance addToQueue:queryString];
            [CountlyPersistency.sharedInstance saveToFileSync];
        }
        else
        {
            COUNTLY_LOG(@"Crash Report Request <%p> successfully completed.", request);
        }

        dispatch_semaphore_signal(semaphore);

    }] resume];

    COUNTLY_LOG(@"Crash Report Request <%p> started:\n[%@] %@ \n%@", (id)request, request.HTTPMethod, request.URL.absoluteString, [request.HTTPBody cly_stringUTF8]);

    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
}

- (void)sendOldDeviceID:(NSString *)oldDeviceID
{
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&%@=%@",
                             kCountlyQSKeyDeviceIDOld, oldDeviceID.cly_URLEscaped];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self proceedOnQueue];
}

- (void)sendParentDeviceID:(NSString *)parentDeviceID
{
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&%@=%@",
                             kCountlyQSKeyDeviceIDParent, parentDeviceID.cly_URLEscaped];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self proceedOnQueue];
}

- (void)sendAttribution:(NSString *)attribution
{
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&%@=%@",
                             kCountlyQSKeyAttributionID, attribution];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self proceedOnQueue];
}

- (void)sendConsentChanges:(NSString *)consentChanges
{
    NSString* queryString = [[self queryEssentials] stringByAppendingFormat:@"&%@=%@",
                             kCountlyQSKeyConsent, consentChanges];

    [CountlyPersistency.sharedInstance addToQueue:queryString];

    [self proceedOnQueue];
}

#pragma mark ---

- (NSString *)queryEssentials
{
    return [NSString stringWithFormat:@"%@=%@&%@=%@&%@=%lld&%@=%d&%@=%d&%@=%d&%@=%@&%@=%@",
                                        kCountlyQSKeyAppKey, self.appKey,
                                        kCountlyQSKeyDeviceID, CountlyDeviceInfo.sharedInstance.deviceID.cly_URLEscaped,
                                        kCountlyQSKeyTimestamp, (long long)(CountlyCommon.sharedInstance.uniqueTimestamp * 1000),
                                        kCountlyQSKeyTimeHourOfDay, (int)CountlyCommon.sharedInstance.hourOfDay,
                                        kCountlyQSKeyTimeDayOfWeek, (int)CountlyCommon.sharedInstance.dayOfWeek,
                                        kCountlyQSKeyTimeZone, (int)CountlyCommon.sharedInstance.timeZone,
                                        kCountlyQSKeySDKVersion, kCountlySDKVersion,
                                        kCountlyQSKeySDKName, kCountlySDKName];
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

- (NSData *)pictureUploadDataForRequest:(NSString *)requestString
{
#if TARGET_OS_IOS
    NSString* localPicturePath = nil;
    NSString* tempURLString = [@"http://example.com/path?" stringByAppendingString:requestString];
    NSURLComponents* URLComponents = [NSURLComponents componentsWithString:tempURLString];
    for (NSURLQueryItem* queryItem in URLComponents.queryItems)
    {
        if ([queryItem.name isEqualToString:kCountlyQSKeyUserDetails])
        {
            NSString* unescapedValue = [queryItem.value stringByRemovingPercentEncoding];
            if (!unescapedValue)
                return nil;

            NSDictionary* pathDictionary = [NSJSONSerialization JSONObjectWithData:[unescapedValue cly_dataUTF8] options:0 error:nil];
            localPicturePath = pathDictionary[kCountlyLocalPicturePath];
            break;
        }
    }

    if (!localPicturePath || !localPicturePath.length)
        return nil;

    COUNTLY_LOG(@"Local picture path successfully extracted from query string: %@", localPicturePath);

    NSArray* allowedFileTypes = @[@"gif", @"png", @"jpg", @"jpeg"];
    NSString* fileExt = localPicturePath.pathExtension.lowercaseString;
    NSInteger fileExtIndex = [allowedFileTypes indexOfObject:fileExt];

    if (fileExtIndex == NSNotFound)
        return nil;

    NSData* imageData = [NSData dataWithContentsOfURL:[NSURL URLWithString:localPicturePath]];

    if (!imageData)
    {
        COUNTLY_LOG(@"Local picture data can not be read!");
        return nil;
    }

    COUNTLY_LOG(@"Local picture data read successfully.");

    //NOTE: Overcome failing PNG file upload if data is directly read from disk
    if (fileExtIndex == 1)
        imageData = UIImagePNGRepresentation([UIImage imageWithData:imageData]);

    //NOTE: Remap content type from jpg to jpeg
    if (fileExtIndex == 2)
        fileExtIndex = 3;

    NSString* boundaryStart = [NSString stringWithFormat:@"--%@\r\n", kCountlyUploadBoundary];
    NSString* contentDisposition = [NSString stringWithFormat:@"Content-Disposition: form-data; name=\"pictureFile\"; filename=\"%@\"\r\n", localPicturePath.lastPathComponent];
    NSString* contentType = [NSString stringWithFormat:@"Content-Type: image/%@\r\n\r\n", allowedFileTypes[fileExtIndex]];
    NSString* boundaryEnd = [NSString stringWithFormat:@"\r\n--%@--\r\n", kCountlyUploadBoundary];

    NSMutableData* uploadData = NSMutableData.new;
    [uploadData appendData:[boundaryStart cly_dataUTF8]];
    [uploadData appendData:[contentDisposition cly_dataUTF8]];
    [uploadData appendData:[contentType cly_dataUTF8]];
    [uploadData appendData:imageData];
    [uploadData appendData:[boundaryEnd cly_dataUTF8]];
    return uploadData;
#endif
    return nil;
}

- (NSString *)appendChecksum:(NSString *)queryString
{
    if (self.secretSalt)
    {
        NSString* checksum = [[queryString stringByAppendingString:self.secretSalt] cly_SHA256];
        return [queryString stringByAppendingFormat:@"&%@=%@", kCountlyQSKeyChecksum256, checksum];
    }

    return queryString;
}

- (BOOL)isRequestSuccessful:(NSURLResponse *)response
{
    if (!response)
        return NO;

    NSInteger code = ((NSHTTPURLResponse*)response).statusCode;

    return (code >= 200 && code < 300);
}

#pragma mark ---

- (NSURLSession *)URLSession
{
    if (self.pinnedCertificates)
    {
        COUNTLY_LOG(@"%d pinned certificate(s) specified in config.", (int)self.pinnedCertificates.count);
        NSURLSessionConfiguration *sc = [NSURLSessionConfiguration defaultSessionConfiguration];
        return [NSURLSession sessionWithConfiguration:sc delegate:self delegateQueue:nil];
    }

    return NSURLSession.sharedSession;
}

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler
{
    SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
    SecKeyRef serverKey = SecTrustCopyPublicKey(serverTrust);
    SecPolicyRef policy = SecPolicyCreateSSL(true, (__bridge CFStringRef)challenge.protectionSpace.host);

    __block BOOL isLocalAndServerCertMatch = NO;

    for (NSString* certificate in self.pinnedCertificates )
    {
        NSString* localCertPath = [NSBundle.mainBundle pathForResource:certificate ofType:nil];
        if (!localCertPath)
           [NSException raise:@"CountlyCertificateNotFoundException" format:@"Bundled certificate can not be found for %@", certificate];
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

        if (localKey) CFRelease(localKey);
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
