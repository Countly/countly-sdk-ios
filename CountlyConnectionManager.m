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
@property (nonatomic) NSURLSession* URLSession;
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

NSString* const kCountlyQSKeyMethod           = @"method";

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

- (void)setHost:(NSString *)host
{
    if ([host hasSuffix:@"/"])
    {
        CLY_LOG_W(@"Host has an extra \"/\" at the end! It will be removed by the SDK.\
                  But please make sure you fix it to avoid this warning in the future.");
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
        _URLSessionConfiguration = URLSessionConfiguration;
        _URLSession = nil;
    }
}


- (void)proceedOnQueue
{
    CLY_LOG_D(@"Proceeding on queue...");

    if (self.connection)
    {
        CLY_LOG_D(@"Proceeding on queue is aborted: Already has a request in process!");
        return;
    }

    if (isCrashing)
    {
        CLY_LOG_D(@"Proceeding on queue is aborted: Application is crashing!");
        return;
    }

    if (self.isTerminating)
    {
        CLY_LOG_D(@"Proceeding on queue is aborted: Application is terminating!");
        return;
    }

    if (CountlyPersistency.sharedInstance.isQueueBeingModified)
    {
        CLY_LOG_D(@"Proceeding on queue is aborted: Queue is being modified!");
        return;
    }

    NSString* firstItemInQueue = [CountlyPersistency.sharedInstance firstItemInQueue];
    if (!firstItemInQueue)
    {
        CLY_LOG_D(@"Queue is empty. All requests are processed.");
        return;
    }

    NSString* temporaryDeviceIDQueryString = [NSString stringWithFormat:@"&%@=%@", kCountlyQSKeyDeviceID, CLYTemporaryDeviceID];
    if ([firstItemInQueue containsString:temporaryDeviceIDQueryString])
    {
        CLY_LOG_D(@"Proceeding on queue is aborted: Device ID in request is CLYTemporaryDeviceID!");
        return;
    }

    [CountlyCommon.sharedInstance startBackgroundTask];

    NSString* queryString = firstItemInQueue;

    queryString = [self appendChecksum:queryString];

    NSString* serverInputEndpoint = [self.host stringByAppendingString:kCountlyEndpointI];
    NSString* fullRequestURL = [serverInputEndpoint stringByAppendingFormat:@"?%@", queryString];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:fullRequestURL]];

    NSData* pictureUploadData = [self pictureUploadDataForQueryString:queryString];
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

    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;

    self.connection = [self.URLSession dataTaskWithRequest:request completionHandler:^(NSData * data, NSURLResponse * response, NSError * error)
    {
        self.connection = nil;

        CLY_LOG_V(@"Approximate received data size for request <%p> is %ld bytes.", (id)request, (long)data.length);

        if (!error)
        {
            if ([self isRequestSuccessful:response data:data])
            {
                CLY_LOG_D(@"Request <%p> successfully completed.", request);

                [CountlyPersistency.sharedInstance removeFromQueue:firstItemInQueue];

                [CountlyPersistency.sharedInstance saveToFile];

                [self proceedOnQueue];
            }
            else
            {
                CLY_LOG_D(@"Request <%p> failed!\nServer reply: %@", request, [data cly_stringUTF8]);
            }
        }
        else
        {
            CLY_LOG_D(@"Request <%p> failed!\nError: %@", request, error);
#if (TARGET_OS_WATCH)
            [CountlyPersistency.sharedInstance saveToFile];
#endif
        }
    }];

    [self.connection resume];

    [self logRequest:request];
}

- (void)logRequest:(NSURLRequest *)request
{
    NSString* bodyAsString = @"";
    NSInteger sentSize = request.URL.absoluteString.length;

    if (request.HTTPBody)
    {
        bodyAsString = [request.HTTPBody cly_stringUTF8];
        if (!bodyAsString)
            bodyAsString = @"Picture uploading...";

        sentSize += request.HTTPBody.length;
    }

    CLY_LOG_D(@"Request <%p> started:\n[%@] %@ \n%@", (id)request, request.HTTPMethod, request.URL.absoluteString, bodyAsString);
    CLY_LOG_V(@"Approximate sent data size for request <%p> is %ld bytes.", (id)request, (long)sentSize);
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

    NSString* locationRelatedInfoQueryString = [self locationRelatedInfoQueryString];
    if (locationRelatedInfoQueryString)
        queryString = [queryString stringByAppendingString:locationRelatedInfoQueryString];

    NSString* attributionQueryString = [self attributionQueryString];
    if (attributionQueryString)
        queryString = [queryString stringByAppendingString:attributionQueryString];

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
    if (!report)
    {
        CLY_LOG_W(@"Crash report is nil. Converting to JSON may have failed due to custom objects in initial config's crashSegmentation property.");
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

    [self sendEvents];

    if (!CountlyCommon.sharedInstance.manualSessionHandling)
        [self endSession];

    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
    {
        CLY_LOG_D(@"Device ID is set as CLYTemporaryDeviceID! Crash report stored to be sent later!");

        [CountlyPersistency.sharedInstance addToQueue:queryString];
        [CountlyPersistency.sharedInstance saveToFileSync];
        return;
    }

    [CountlyPersistency.sharedInstance saveToFileSync];

    NSString* serverInputEndpoint = [self.host stringByAppendingString:kCountlyEndpointI];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:serverInputEndpoint]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [[self appendChecksum:queryString] cly_dataUTF8];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    [[self.URLSession dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError*  error)
    {
        if (error || ![self isRequestSuccessful:response data:data])
        {
            CLY_LOG_D(@"Request <%p> failed!\n%@: %@", request, error ? @"Error" : @"Server reply", error ?: [data cly_stringUTF8]);
            [CountlyPersistency.sharedInstance addToQueue:queryString];
            [CountlyPersistency.sharedInstance saveToFileSync];
        }
        else
        {
            CLY_LOG_D(@"Request <%p> successfully completed.", request);
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

- (void)addDirectRequest:(NSDictionary<NSString *, NSString *> *)requestParameters
{
    if (!CountlyConsentManager.sharedInstance.hasAnyConsent)
        return;

    NSMutableDictionary* mutableRequestParameters = requestParameters.mutableCopy;

    for (NSString * reservedKey in self.reservedQueryStringKeys)
    {
        if (mutableRequestParameters[reservedKey])
        {
            CLY_LOG_W(@"A reserved query string key detected in direct request parameters and it will be removed: %@", reservedKey);
            [mutableRequestParameters removeObjectForKey:reservedKey];
        }
    }

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

- (NSData *)pictureUploadDataForQueryString:(NSString *)queryString
{
#if (TARGET_OS_IOS)
    NSString* localPicturePath = nil;

    NSString* userDetails = [queryString cly_valueForQueryStringKey:kCountlyQSKeyUserDetails];
    NSString* unescapedUserDetails = [userDetails stringByRemovingPercentEncoding];
    if (!unescapedUserDetails)
        return nil;

    NSDictionary* pathDictionary = [NSJSONSerialization JSONObjectWithData:[unescapedUserDetails cly_dataUTF8] options:0 error:nil];
    localPicturePath = pathDictionary[kCountlyLocalPicturePath];

    if (!localPicturePath.length)
        return nil;

    CLY_LOG_D(@"Local picture path successfully extracted from query string: %@", localPicturePath);

    NSArray* allowedFileTypes = @[@"gif", @"png", @"jpg", @"jpeg"];
    NSString* fileExt = localPicturePath.pathExtension.lowercaseString;
    NSInteger fileExtIndex = [allowedFileTypes indexOfObject:fileExt];

    if (fileExtIndex == NSNotFound)
    {
        CLY_LOG_W(@"Unsupported file extension for picture upload: %@", fileExt);
        return nil;
    }

    NSData* imageData = [NSData dataWithContentsOfURL:[NSURL URLWithString:localPicturePath]];

    if (!imageData)
    {
        CLY_LOG_W(@"Local picture data can not be read!");
        return nil;
    }

    CLY_LOG_D(@"Local picture data read successfully.");

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
            CLY_LOG_W(@"Server reply is not a valid JSON!");
            return NO;
        }
        
        NSString* result = serverReply[@"result"];
        if ([result isEqualToString:@"Success"])
        {
            CLY_LOG_V(@"Value for `result` key in server reply is `Success`.");
            return YES;            
        }
        else
        {
            CLY_LOG_V(@"Value for `result` key in server reply is not `Success`.");
            return NO;
        }
    }
    else
    {
        CLY_LOG_V(@"HTTP status code is not 2XX series.");
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
            CLY_LOG_D(@"%d pinned certificate(s) specified in config.", (int)self.pinnedCertificates.count);
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
            CLY_LOG_D(@"Pinned certificate and server certificate match.");

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
        CLY_LOG_D(@"Pinned certificate check is successful. Proceeding with request.");
        completionHandler(NSURLSessionAuthChallengeUseCredential, [NSURLCredential credentialForTrust:serverTrust]);
    }
    else
    {
        if (!isLocalAndServerCertMatch)
            CLY_LOG_W(@"Pinned certificate and server certificate does not match!");

        if (!isServerCertValid)
            CLY_LOG_W(@"Server certificate is not valid! SecTrustEvaluate result is: %u", serverTrustResult);

        CLY_LOG_D(@"Pinned certificate check failed! Cancelling request.");
        completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, NULL);
    }

    if (serverKey)
        CFRelease(serverKey);

    CFRelease(policy);
}

@end
