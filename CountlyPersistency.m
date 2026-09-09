// CountlyPersistency.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.
#import "CountlyCommon.h"

@interface CountlyPersistency ()
@property (nonatomic) NSMutableArray* queuedRequests;
@property (nonatomic) NSMutableArray* recordedEvents;
@property (nonatomic) NSMutableDictionary* startedEvents;
@property (nonatomic) BOOL isQueueBeingModified;
@end

@implementation CountlyPersistency
NSString* const kCountlyQueuedRequestsPersistencyKey = @"kCountlyQueuedRequestsPersistencyKey";
NSString* const kCountlyStartedEventsPersistencyKey = @"kCountlyStartedEventsPersistencyKey";
NSString* const kCountlyHealthCheckStatePersistencyKey = @"kCountlyHealthCheckStatePersistencyKey";
NSString* const kCountlyStoredDeviceIDKey = @"kCountlyStoredDeviceIDKey";
NSString* const kCountlyStoredNSUUIDKey = @"kCountlyStoredNSUUIDKey";
NSString* const kCountlyWatchParentDeviceIDKey = @"kCountlyWatchParentDeviceIDKey";
NSString* const kCountlyStarRatingStatusKey = @"kCountlyStarRatingStatusKey";
NSString* const kCountlyNotificationPermissionKey = @"kCountlyNotificationPermissionKey";
NSString* const kCountlyIsCustomDeviceIDKey = @"kCountlyIsCustomDeviceIDKey";
NSString* const kCountlyRemoteConfigKey = @"kCountlyRemoteConfigKey";
NSString* const kCountlyServerConfigPersistencyKey = @"kCountlyServerConfigPersistencyKey";


NSString* const kCountlyCustomCrashLogFileName = @"CountlyCustomCrash.log";

NSUInteger const kCountlyRequestRemovalLoopLimit = 100;

static CountlyPersistency* s_sharedInstance = nil;
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
        NSData* readData = [NSData dataWithContentsOfURL:[self storageFileURL]];

        if (readData)
        {
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
            NSDictionary* readDict = [NSKeyedUnarchiver unarchiveObjectWithData:readData];
#pragma GCC diagnostic pop

            self.queuedRequests = [readDict[kCountlyQueuedRequestsPersistencyKey] mutableCopy];

            CLY_LOG_D(@"%s persistent storage file is loaded, data size: [%lu] bytes, restored request count: [%lu]", __FUNCTION__, (unsigned long)readData.length, (unsigned long)self.queuedRequests.count);
        }

        if (!self.queuedRequests)
            self.queuedRequests = NSMutableArray.new;

        if (!self.startedEvents)
            self.startedEvents = NSMutableDictionary.new;

        self.recordedEvents = NSMutableArray.new;
    }

    return self;
}

#pragma mark ---

- (BOOL)addToQueue:(NSString *)queryString
{
    // NOTE: reachable from CountlySignalHandler through CountlyConnectionManager sendCrashReport,
    // so every log here and in removeOldAgeRequestsFromQueue stays at Debug or lower, even the
    // request dropping ones. CountlyInternalLog re-enters CountlyHealthTracker, which uses
    // dispatch_once and dispatch_async, and neither is async-signal-safe.
    if (!CountlyServerConfig.sharedInstance.trackingEnabled)
    {
        CLY_LOG_D(@"%s request is not queued, reason: SDK tracking is disabled from server config, query string length: [%lu]", __FUNCTION__, (unsigned long)queryString.length);
        return NO;
    }
    
    if (!queryString.length || [queryString isEqual:NSNull.null])
    {
        CLY_LOG_D(@"%s request is not queued, reason: query string is nil or empty", __FUNCTION__);
        return NO;
    }
    
    queryString = [queryString stringByAppendingFormat:@"&%@=%@",
                   kCountlyAppVersionKey, CountlyDeviceInfo.appVersion];

    @synchronized (self)
    {
        if (self.queuedRequests.count >= self.storedRequestsLimit)
        {
            [self removeOldAgeRequestsFromQueue];
            if (self.queuedRequests.count >= self.storedRequestsLimit)
            {
                NSUInteger exceededSize = self.queuedRequests.count - self.storedRequestsLimit;
                // we should remove amount of limit at max
                // for example if exceeded count is 136 and our limit is 100 we should remove 100 items
                // in other case if exceeded count is 36 and out limit is 100 we can only remove 36 items because we have that amount
                NSUInteger gonnaRemoveSize = MIN(exceededSize, kCountlyRequestRemovalLoopLimit) + 1;
                CLY_LOG_D(@"%s request queue size: [%lu] exceeded the limit: [%lu], the first [%lu] request(s) will be dropped", __FUNCTION__, (unsigned long)self.queuedRequests.count, (unsigned long)self.storedRequestsLimit, (unsigned long)gonnaRemoveSize);
                NSRange itemsToRemove = NSMakeRange(0, gonnaRemoveSize);
                [self.queuedRequests removeObjectsInRange:itemsToRemove];
            }
        }
        [self.queuedRequests addObject:queryString];
        CLY_LOG_V(@"%s request is queued, query string length: [%lu], queue size: [%lu]", __FUNCTION__, (unsigned long)queryString.length, (unsigned long)self.queuedRequests.count);
    }
    return YES;
}

- (void)removeFromQueue:(NSString *)queryString
{
    @synchronized (self)
    {
        if (self.queuedRequests.count)
        {
            [self.queuedRequests removeObject:queryString inRange:(NSRange){0, 1}];
            CLY_LOG_D(@"%s request at the head of the queue is removed, remaining request count: [%lu]", __FUNCTION__, (unsigned long)self.queuedRequests.count);
        }
    }
}

- (NSString *)firstItemInQueue
{
    @synchronized (self)
    {
        return self.queuedRequests.firstObject;
    }
}

- (void)flushQueue
{
    @synchronized (self)
    {
        if (self.queuedRequests.count)
        {
            CLY_LOG_D(@"%s request queue is being flushed, [%lu] queued request(s) will be dropped", __FUNCTION__, (unsigned long)self.queuedRequests.count);
        }
        [self.queuedRequests removeAllObjects];
    }
}

- (NSUInteger)remainingRequestCount
{
    @synchronized (self)
    {
        return [self.queuedRequests count];
    }
}

- (void)replaceAllTemporaryDeviceIDsInQueueWithDeviceID:(NSString *)deviceID
{
    CLY_LOG_D(@"%s replacing the temporary device ID in the queued requests, queued request count: [%lu]", __FUNCTION__, (unsigned long)[self remainingRequestCount]);
    NSString* temporaryDeviceIDQueryString = [NSString stringWithFormat:@"&%@=%@", kCountlyQSKeyDeviceID, CLYTemporaryDeviceID];
    NSString* realDeviceIDQueryString = [NSString stringWithFormat:@"&%@=%@", kCountlyQSKeyDeviceID, deviceID.cly_URLEscaped];

    NSString* temporaryDeviceIDTypeQueryString = [NSString stringWithFormat:@"&%@=%d", kCountlyQSKeyDeviceIDType, (int)CLYDeviceIDTypeValueTemporary];
    NSString* realDeviceIDTypeQueryString = [NSString stringWithFormat:@"&%@=%d", kCountlyQSKeyDeviceIDType, (int)CountlyDeviceInfo.sharedInstance.deviceIDTypeValue];

    @synchronized (self)
    {
        self.isQueueBeingModified = YES;

        [self.queuedRequests.copy enumerateObjectsUsingBlock:^(NSString* queryString, NSUInteger idx, BOOL* stop)
        {
            if ([queryString containsString:temporaryDeviceIDQueryString])
            {
                CLY_LOG_V(@"[CountlyPersistency] replaceAllTemporaryDeviceIDsInQueueWithDeviceID, a queued request with the temporary device ID is replaced with the real device ID, request index: [%lu]", (unsigned long)idx);
                NSString * replacedQueryString = [queryString stringByReplacingOccurrencesOfString:temporaryDeviceIDQueryString withString:realDeviceIDQueryString];
                replacedQueryString = [replacedQueryString stringByReplacingOccurrencesOfString:temporaryDeviceIDTypeQueryString withString:realDeviceIDTypeQueryString];
                self.queuedRequests[idx] = replacedQueryString;
            }
        }];

        self.isQueueBeingModified = NO;
    }
}

- (void)replaceAllAppKeysInQueueWithCurrentAppKey
{
    @synchronized (self)
    {
        CLY_LOG_D(@"%s replacing different app keys in the queued requests, queued request count: [%lu]", __FUNCTION__, (unsigned long)self.queuedRequests.count);
        self.isQueueBeingModified = YES;

        [self.queuedRequests.copy enumerateObjectsUsingBlock:^(NSString* queryString, NSUInteger idx, BOOL* stop)
        {
            NSString* appKeyInQueryString = [queryString cly_valueForQueryStringKey:kCountlyQSKeyAppKey];

            if (![appKeyInQueryString isEqualToString:CountlyConnectionManager.sharedInstance.appKey.cly_URLEscaped])
            {
                CLY_LOG_V(@"[CountlyPersistency] replaceAllAppKeysInQueueWithCurrentAppKey, a queued request with a different app key is replaced with the current app key, request index: [%lu]", (unsigned long)idx);

                NSString* currentAppKeyQueryString = [NSString stringWithFormat:@"%@=%@", kCountlyQSKeyAppKey, CountlyConnectionManager.sharedInstance.appKey.cly_URLEscaped];
                NSString* differentAppKeyQueryString = [NSString stringWithFormat:@"%@=%@", kCountlyQSKeyAppKey, appKeyInQueryString];
                NSString * replacedQueryString = [queryString stringByReplacingOccurrencesOfString:differentAppKeyQueryString withString:currentAppKeyQueryString];
                self.queuedRequests[idx] = replacedQueryString;
            }
        }];

        self.isQueueBeingModified = NO;
    }
}

- (void)removeDifferentAppKeysFromQueue
{
    @synchronized (self)
    {
        NSUInteger requestCountBeforeAppKeyFilter = self.queuedRequests.count;
        self.isQueueBeingModified = YES;

        NSPredicate* predicate = [NSPredicate predicateWithBlock:^BOOL(NSString* queryString, NSDictionary<NSString *, id> * bindings)
        {
            NSString* appKeyInQueryString = [queryString cly_valueForQueryStringKey:kCountlyQSKeyAppKey];

            BOOL isSameAppKey = [appKeyInQueryString isEqualToString:CountlyConnectionManager.sharedInstance.appKey.cly_URLEscaped];
            if (!isSameAppKey)
            {
                CLY_LOG_V(@"[CountlyPersistency] removeDifferentAppKeysFromQueue, a queued request with a different app key will be dropped");
            }

            return isSameAppKey;
        }];

        [self.queuedRequests filterUsingPredicate:predicate];

        if (requestCountBeforeAppKeyFilter > self.queuedRequests.count)
        {
            CLY_LOG_W(@"%s dropped [%lu] queued request(s) with a different app key, remaining request count: [%lu]", __FUNCTION__, (unsigned long)(requestCountBeforeAppKeyFilter - self.queuedRequests.count), (unsigned long)self.queuedRequests.count);
        }

        self.isQueueBeingModified = NO;
    }
}

- (void)removeOldAgeRequestsFromQueue
{
    @synchronized (self)
    {
        if(self.requestDropAgeHours && self.requestDropAgeHours > 0) {
            NSUInteger requestCountBeforeAgeFilter = self.queuedRequests.count;
            self.isQueueBeingModified = YES;
            
            NSPredicate* predicate = [NSPredicate predicateWithBlock:^BOOL(NSString* queryString, NSDictionary<NSString *, id> * bindings)
                                      {
                BOOL isOldAgeRequest = [self isOldRequestInternal:queryString];
                return !isOldAgeRequest;
            }];
            
            [self.queuedRequests filterUsingPredicate:predicate];
            
            if (requestCountBeforeAgeFilter > self.queuedRequests.count)
            {
                CLY_LOG_D(@"%s dropped [%lu] old age queued request(s), request drop age in hours: [%lu], remaining request count: [%lu]", __FUNCTION__, (unsigned long)(requestCountBeforeAgeFilter - self.queuedRequests.count), (unsigned long)self.requestDropAgeHours, (unsigned long)self.queuedRequests.count);
            }
            
            self.isQueueBeingModified = NO;
        }
    }
}

-(BOOL)isOldRequest:(NSString*) queryString
{
    if(self.requestDropAgeHours && self.requestDropAgeHours > 0) {
        return [self isOldRequestInternal:queryString];
    }
    return false;
    
}

-(BOOL)isOldRequestInternal:(NSString *)queryString
{
    double requestTimeStamp = [[queryString cly_valueForQueryStringKey:kCountlyQSKeyTimestamp] longLongValue]/1000.0;
    double durationInSecods = NSDate.date.timeIntervalSince1970 - requestTimeStamp;
    double durationInHours = (durationInSecods/3600.0);
    BOOL isOldAgeRequest = durationInHours >= self.requestDropAgeHours;
    if (isOldAgeRequest)
    {
        CLY_LOG_V(@"%s a queued request exceeded the request drop age and will be dropped, request age in hours: [%.2f], request drop age in hours: [%lu]", __FUNCTION__, durationInHours, (unsigned long)self.requestDropAgeHours);
    }
    
    return isOldAgeRequest;
}

#pragma mark ---

- (void)recordEvent:(CountlyEvent *)event
{
    [self recordEvent:event callback:nil];
}

- (void)recordEvent:(CountlyEvent *)event callback:(CLYRequestCallback)callback
{
    @synchronized (self.recordedEvents)
    {
        if ([CountlyUserDetails.sharedInstance hasUnsyncedChanges])
        {
            [CountlyUserDetails.sharedInstance save];
        }
        
        [self.recordedEvents addObject:event];

        CLY_LOG_D(@"%s event is added to the in memory event queue, pending event count: [%lu], event send threshold: [%lu], callback provided: [%@]", __FUNCTION__, (unsigned long)self.recordedEvents.count, (unsigned long)self.eventSendThreshold, (callback != nil) ? @"YES" : @"NO");
        
        if (callback != nil || self.recordedEvents.count >= self.eventSendThreshold)
        {
            [CountlyConnectionManager.sharedInstance sendEventsWithCallback:callback];
        }
    }
}

- (NSString *)serializedRecordedEvents
{
    @synchronized (self.recordedEvents)
    {
        if (self.recordedEvents.count == 0)
            return nil;

        NSArray *eventDictionaries = [self.recordedEvents valueForKey:@"dictionaryRepresentation"];

        CLY_LOG_D(@"%s serializing the recorded events for the next request, event count: [%lu]", __FUNCTION__, (unsigned long)eventDictionaries.count);

        [self.recordedEvents removeAllObjects];

        return [eventDictionaries cly_JSONify];
    }
}


- (void)flushEvents
{
    @synchronized (self.recordedEvents)
    {
        if (self.recordedEvents.count)
        {
            CLY_LOG_D(@"%s in memory event queue is being flushed, [%lu] recorded event(s) will be dropped", __FUNCTION__, (unsigned long)self.recordedEvents.count);
        }
        [self.recordedEvents removeAllObjects];
    }
}

- (void)resetInstance:(BOOL) clearStorage 
{
    CLY_LOG_I(@"%s persistency instance is being reset, clear storage: [%@]", __FUNCTION__, clearStorage ? @"YES" : @"NO");
    [CountlyConnectionManager.sharedInstance sendEventsWithSaveIfNeeded];
    [self flushEvents];
    [self clearAllTimedEvents];
    [self flushQueue];
    if(clearStorage)
    {
        [self saveToFile];
    }
    onceToken = 0;
    s_sharedInstance = nil;
}

#pragma mark ---

- (void)recordTimedEvent:(CountlyEvent *)event
{
    @synchronized (self.startedEvents)
    {
        if (self.startedEvents[event.key])
        {
            CLY_LOG_W(@"%s timed event is not started, reason: a timed event with the same key is already started, key: [%@]", __FUNCTION__, event.key);
            return;
        }

        self.startedEvents[event.key] = event;

        CLY_LOG_D(@"%s timed event is started, key: [%@], started timed event count: [%lu]", __FUNCTION__, event.key, (unsigned long)self.startedEvents.count);
    }
}

- (CountlyEvent *)timedEventForKey:(NSString *)key
{
    @synchronized (self.startedEvents)
    {
        CountlyEvent *event = self.startedEvents[key];

        CLY_LOG_D(@"%s timed event is requested from the started timed events, key: [%@], found: [%@]", __FUNCTION__, key, (event != nil) ? @"YES" : @"NO");

        [self.startedEvents removeObjectForKey:key];

        return event;
    }
}

- (void)clearAllTimedEvents
{
    @synchronized (self.startedEvents)
    {
        CLY_LOG_D(@"%s clearing all started timed events, started timed event count: [%lu]", __FUNCTION__, (unsigned long)self.startedEvents.count);
        [self.startedEvents removeAllObjects];
    }
}

#pragma mark ---

- (void)writeCustomCrashLogToFile:(NSString *)log
{
    static NSURL* crashLogFileURL = nil;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        crashLogFileURL = [[self storageDirectoryURL] URLByAppendingPathComponent:kCountlyCustomCrashLogFileName];
    });

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^
    {
        NSString* line = [NSString stringWithFormat:@"%@\n", log];
        NSFileHandle* fileHandle = [NSFileHandle fileHandleForWritingAtPath:crashLogFileURL.path];
        if (fileHandle)
        {
            [fileHandle seekToEndOfFile];
            [fileHandle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            [fileHandle closeFile];
            CLY_LOG_V(@"[CountlyPersistency] writeCustomCrashLogToFile, a line is appended to the custom crash log file, line length: [%lu]", (unsigned long)line.length);
        }
        else
        {
            NSError* error = nil;
            [line writeToFile:crashLogFileURL.path atomically:YES encoding:NSUTF8StringEncoding error:&error];
            if (error)
            {
                CLY_LOG_W(@"[CountlyPersistency] writeCustomCrashLogToFile, custom crash log file can not be created, error domain: [%@], error code: [%ld], error description: [%@]", error.domain, (long)error.code, error.localizedDescription);
            }
        }
    });
}

- (NSString *)customCrashLogsFromFile
{
    NSURL* crashLogFileURL = [[self storageDirectoryURL] URLByAppendingPathComponent:kCountlyCustomCrashLogFileName];
    NSData* readData = [NSData dataWithContentsOfURL:crashLogFileURL];

    CLY_LOG_D(@"%s custom crash logs are read from the custom crash log file, data size: [%lu] bytes", __FUNCTION__, (unsigned long)readData.length);

    NSString* storedCustomCrashLogs = nil;
    if (readData)
    {
        storedCustomCrashLogs = [NSString.alloc initWithData:readData encoding:NSUTF8StringEncoding];
    }

    return storedCustomCrashLogs;
}

- (void)deleteCustomCrashLogFile
{
    NSURL* crashLogFileURL = [[self storageDirectoryURL] URLByAppendingPathComponent:kCountlyCustomCrashLogFileName];
    NSError* error = nil;
    if ([NSFileManager.defaultManager fileExistsAtPath:crashLogFileURL.path])
    {
        CLY_LOG_D(@"%s custom crash log file is detected and it is being deleted", __FUNCTION__);
        [NSFileManager.defaultManager removeItemAtURL:crashLogFileURL error:&error];
        if (error)
        {
            CLY_LOG_W(@"%s custom crash log file can not be deleted, error domain: [%@], error code: [%ld], error description: [%@]", __FUNCTION__, error.domain, (long)error.code, error.localizedDescription);
        }
    }
}

#pragma mark ---

- (NSURL *)storageDirectoryURL
{
    static NSURL* URL = nil;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
#if (TARGET_OS_TV)
        NSSearchPathDirectory directory = NSCachesDirectory;
#else
        NSSearchPathDirectory directory = NSApplicationSupportDirectory;
#endif
        URL = [[NSFileManager.defaultManager URLsForDirectory:directory inDomains:NSUserDomainMask] lastObject];

#if (TARGET_OS_OSX)
        URL = [URL URLByAppendingPathComponent:NSBundle.mainBundle.bundleIdentifier];
#endif
        NSError *error = nil;

        if (![NSFileManager.defaultManager fileExistsAtPath:URL.path])
        {
            [NSFileManager.defaultManager createDirectoryAtURL:URL withIntermediateDirectories:YES attributes:nil error:&error];
            if (error)
            {
                CLY_LOG_E(@"[CountlyPersistency] storageDirectoryURL, storage directory can not be created, error domain: [%@], error code: [%ld], error description: [%@]", error.domain, (long)error.code, error.localizedDescription);
            }
        }
    });

    return URL;
}

- (NSURL *)storageFileURL
{
    NSString* const kCountlyPersistencyFileName = @"Countly.dat";

    static NSURL* URL = nil;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        URL = [[self storageDirectoryURL] URLByAppendingPathComponent:kCountlyPersistencyFileName];
    });

    return URL;
}

- (void)saveToFile
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^
    {
        [self saveToFileSync];
    });
}

- (void)saveToFileSync
{
    // NOTE: reachable from CountlySignalHandler through CountlyConnectionManager sendCrashReport,
    // keep every log here at Debug or lower. See the note on addToQueue.
    NSData* saveData;
    NSUInteger queuedRequestCountForLog = 0;

    @synchronized (self)
    {
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
        saveData = [NSKeyedArchiver archivedDataWithRootObject:@{kCountlyQueuedRequestsPersistencyKey: self.queuedRequests}];
        queuedRequestCountForLog = self.queuedRequests.count;
#pragma GCC diagnostic pop
    }

    BOOL writeResult = [saveData writeToFile:[self storageFileURL].path atomically:YES];
    CLY_LOG_D(@"%s request queue is written to the persistent storage file, success: [%@], data size: [%lu] bytes, request count: [%lu]", __FUNCTION__, writeResult ? @"YES" : @"NO", (unsigned long)saveData.length, (unsigned long)queuedRequestCountForLog);

    if (!writeResult)
    {
        CLY_LOG_D(@"%s writing the request queue to the persistent storage file failed, data size: [%lu] bytes, request count: [%lu]", __FUNCTION__, (unsigned long)saveData.length, (unsigned long)queuedRequestCountForLog);
    }

    [CountlyCommon.sharedInstance finishBackgroundTask];
}

#pragma mark ---

- (NSString* )retrieveDeviceID
{
    NSString* retrievedDeviceID = [NSUserDefaults.standardUserDefaults objectForKey:kCountlyStoredDeviceIDKey];

    if (retrievedDeviceID)
    {
        CLY_LOG_D(@"%s device ID is retrieved from the user defaults, device ID length: [%lu]", __FUNCTION__, (unsigned long)retrievedDeviceID.length);
        CLY_LOG_D(@"%s retrieved device ID detail, device ID: [%@]", __FUNCTION__, retrievedDeviceID);
        return retrievedDeviceID;
    }

    CLY_LOG_D(@"%s there is no stored device ID in the user defaults", __FUNCTION__);

    return nil;
}

- (void)storeDeviceID:(NSString *)deviceID
{
    [NSUserDefaults.standardUserDefaults setObject:deviceID forKey:kCountlyStoredDeviceIDKey];
    [NSUserDefaults.standardUserDefaults synchronize];

    CLY_LOG_D(@"%s device ID is stored in the user defaults, device ID length: [%lu]", __FUNCTION__, (unsigned long)deviceID.length);
    CLY_LOG_D(@"%s stored device ID detail, device ID: [%@]", __FUNCTION__, deviceID);
}

- (NSString *)retrieveNSUUID
{
    return [NSUserDefaults.standardUserDefaults objectForKey:kCountlyStoredNSUUIDKey];
}

- (void)storeNSUUID:(NSString *)UUID
{
    [NSUserDefaults.standardUserDefaults setObject:UUID forKey:kCountlyStoredNSUUIDKey];
    [NSUserDefaults.standardUserDefaults synchronize];
}

- (NSString *)retrieveWatchParentDeviceID
{
    return [NSUserDefaults.standardUserDefaults objectForKey:kCountlyWatchParentDeviceIDKey];
}

- (void)storeWatchParentDeviceID:(NSString *)deviceID
{
    [NSUserDefaults.standardUserDefaults setObject:deviceID forKey:kCountlyWatchParentDeviceIDKey];
    [NSUserDefaults.standardUserDefaults synchronize];
}

- (NSDictionary *)retrieveStarRatingStatus
{
    NSDictionary* status = [NSUserDefaults.standardUserDefaults objectForKey:kCountlyStarRatingStatusKey];
    if (!status)
        status = NSDictionary.new;

    return status;
}

- (void)storeStarRatingStatus:(NSDictionary *)status
{
    [NSUserDefaults.standardUserDefaults setObject:status forKey:kCountlyStarRatingStatusKey];
    [NSUserDefaults.standardUserDefaults synchronize];
}

- (BOOL)retrieveNotificationPermission
{
    return [NSUserDefaults.standardUserDefaults boolForKey:kCountlyNotificationPermissionKey];
}

- (void)storeNotificationPermission:(BOOL)allowed
{
    [NSUserDefaults.standardUserDefaults setBool:allowed forKey:kCountlyNotificationPermissionKey];
    [NSUserDefaults.standardUserDefaults synchronize];
}

- (BOOL)retrieveIsCustomDeviceID
{
    return [NSUserDefaults.standardUserDefaults boolForKey:kCountlyIsCustomDeviceIDKey];
}

- (void)storeIsCustomDeviceID:(BOOL)isCustomDeviceID
{
    [NSUserDefaults.standardUserDefaults setBool:isCustomDeviceID forKey:kCountlyIsCustomDeviceIDKey];
    [NSUserDefaults.standardUserDefaults synchronize];
}

- (NSDictionary *)retrieveRemoteConfig
{
    NSData* data = [NSUserDefaults.standardUserDefaults objectForKey:kCountlyRemoteConfigKey];
    NSDictionary* remoteConfig = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    if (!remoteConfig)
        remoteConfig = NSDictionary.new;

    CLY_LOG_D(@"%s remote config is retrieved from the storage, stored data size: [%lu] bytes, key count: [%lu]", __FUNCTION__, (unsigned long)data.length, (unsigned long)remoteConfig.count);
    
    return remoteConfig;
}

- (void)storeRemoteConfig:(NSDictionary *)remoteConfig
{
    [NSUserDefaults.standardUserDefaults setObject:[NSKeyedArchiver archivedDataWithRootObject:remoteConfig] forKey:kCountlyRemoteConfigKey];
    [NSUserDefaults.standardUserDefaults synchronize];

    CLY_LOG_D(@"%s remote config is stored, key count: [%lu]", __FUNCTION__, (unsigned long)remoteConfig.count);
}

- (NSMutableDictionary *)retrieveServerConfig
{
    NSDictionary* serverConfig = [NSUserDefaults.standardUserDefaults objectForKey:kCountlyServerConfigPersistencyKey];
    if ([serverConfig isKindOfClass:[NSDictionary class]]) {
         CLY_LOG_D(@"%s server config is retrieved from the storage, key count: [%lu]", __FUNCTION__, (unsigned long)serverConfig.count);
         return [serverConfig mutableCopy];
     }

     CLY_LOG_D(@"%s there is no stored server config, returning an empty one", __FUNCTION__);

     return [NSMutableDictionary new];
}

- (void)storeServerConfig:(NSMutableDictionary *)serverConfig
{
    [NSUserDefaults.standardUserDefaults setObject:serverConfig forKey:kCountlyServerConfigPersistencyKey];
    [NSUserDefaults.standardUserDefaults synchronize];

    CLY_LOG_D(@"%s server config is stored, key count: [%lu]", __FUNCTION__, (unsigned long)serverConfig.count);
}

- (NSDictionary *)retrieveHealthCheckTrackerState
{
    NSDictionary* healthCheckTrackerState = [NSUserDefaults.standardUserDefaults objectForKey:kCountlyHealthCheckStatePersistencyKey];
    if (!healthCheckTrackerState)
        healthCheckTrackerState = NSDictionary.new;

    CLY_LOG_D(@"%s health check tracker state is retrieved from the storage, key count: [%lu]", __FUNCTION__, (unsigned long)healthCheckTrackerState.count);
    
    return healthCheckTrackerState;
}

- (void)storeHealthCheckTrackerState:(NSDictionary *)healthCheckTrackerState
{
    @try {
        [NSUserDefaults.standardUserDefaults setObject:healthCheckTrackerState forKey:kCountlyHealthCheckStatePersistencyKey];
        [NSUserDefaults.standardUserDefaults synchronize];

        CLY_LOG_D(@"%s health check tracker state is stored, key count: [%lu]", __FUNCTION__, (unsigned long)healthCheckTrackerState.count);
    }
    @catch (NSException *exception) {
        // NOTE: Debug on purpose. This method is only ever called from inside CountlyHealthTracker's
        // hcQueue, and CountlyInternalLog re-enters that class for Error and Warning levels, which
        // would repopulate the very counters this write is persisting or clearing.
        CLY_LOG_D(@"%s exception while storing the health check tracker state, exception name: [%@], reason: [%@]", __FUNCTION__,
                  exception.name, exception.reason);
    }
}

@end
