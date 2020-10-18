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
NSString* const kCountlyStoredDeviceIDKey = @"kCountlyStoredDeviceIDKey";
NSString* const kCountlyStoredNSUUIDKey = @"kCountlyStoredNSUUIDKey";
NSString* const kCountlyWatchParentDeviceIDKey = @"kCountlyWatchParentDeviceIDKey";
NSString* const kCountlyStarRatingStatusKey = @"kCountlyStarRatingStatusKey";
NSString* const kCountlyNotificationPermissionKey = @"kCountlyNotificationPermissionKey";
NSString* const kCountlyIsCustomDeviceIDKey = @"kCountlyIsCustomDeviceIDKey";
NSString* const kCountlyRemoteConfigPersistencyKey = @"kCountlyRemoteConfigPersistencyKey";

NSString* const kCountlyCustomCrashLogFileName = @"CountlyCustomCrash.log";

+ (instancetype)sharedInstance
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return nil;

    static CountlyPersistency* s_sharedInstance = nil;
    static dispatch_once_t onceToken;
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
            NSDictionary* readDict = [NSKeyedUnarchiver unarchiveObjectWithData:readData];

            self.queuedRequests = [readDict[kCountlyQueuedRequestsPersistencyKey] mutableCopy];
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

- (void)addToQueue:(NSString *)queryString
{
    if (!queryString.length || [queryString isEqual:NSNull.null])
        return;

    @synchronized (self)
    {
        [self.queuedRequests addObject:queryString];

        if (self.queuedRequests.count > self.storedRequestsLimit && !CountlyConnectionManager.sharedInstance.connection)
            [self.queuedRequests removeObjectAtIndex:0];
    }
}

- (void)removeFromQueue:(NSString *)queryString
{
    @synchronized (self)
    {
        if (self.queuedRequests.count)
            [self.queuedRequests removeObject:queryString inRange:(NSRange){0, 1}];
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
        [self.queuedRequests removeAllObjects];
    }
}

- (void)replaceAllTemporaryDeviceIDsInQueueWithDeviceID:(NSString *)deviceID
{
    NSString* temporaryDeviceIDQueryString = [NSString stringWithFormat:@"&%@=%@", kCountlyQSKeyDeviceID, CLYTemporaryDeviceID];
    NSString* realDeviceIDQueryString = [NSString stringWithFormat:@"&%@=%@", kCountlyQSKeyDeviceID, deviceID.cly_URLEscaped];

    @synchronized (self)
    {
        [self.queuedRequests.copy enumerateObjectsUsingBlock:^(NSString* queryString, NSUInteger idx, BOOL* stop)
        {
            if ([queryString containsString:temporaryDeviceIDQueryString])
            {
                COUNTLY_LOG(@"Detected a request with temporary device ID in queue and replaced it with real device ID.");
                NSString * replacedQueryString = [queryString stringByReplacingOccurrencesOfString:temporaryDeviceIDQueryString withString:realDeviceIDQueryString];
                self.queuedRequests[idx] = replacedQueryString;
            }
        }];
    }
}

- (void)replaceAllAppKeysInQueueWithCurrentAppKey
{
    @synchronized (self)
    {
        self.isQueueBeingModified = YES;

        [self.queuedRequests.copy enumerateObjectsUsingBlock:^(NSString* queryString, NSUInteger idx, BOOL* stop)
        {
            NSString* appKeyInQueryString = [queryString cly_valueForQueryStringKey:kCountlyQSKeyAppKey];

            if (![appKeyInQueryString isEqualToString:CountlyConnectionManager.sharedInstance.appKey.cly_URLEscaped])
            {
                COUNTLY_LOG(@"Detected a request with a different app key (%@) in queue and replaced it with current app key.", appKeyInQueryString);

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
        self.isQueueBeingModified = YES;

        NSPredicate* predicate = [NSPredicate predicateWithBlock:^BOOL(NSString* queryString, NSDictionary<NSString *, id> * bindings)
        {
            NSString* appKeyInQueryString = [queryString cly_valueForQueryStringKey:kCountlyQSKeyAppKey];

            BOOL isSameAppKey = [appKeyInQueryString isEqualToString:CountlyConnectionManager.sharedInstance.appKey.cly_URLEscaped];
            if (!isSameAppKey)
            {
                COUNTLY_LOG(@"Detected a request with a different app key (%@) in queue and removed it.", appKeyInQueryString);
            }

            return isSameAppKey;
        }];

        [self.queuedRequests filterUsingPredicate:predicate];

        self.isQueueBeingModified = NO;
    }
}

#pragma mark ---

- (void)recordEvent:(CountlyEvent *)event
{
    @synchronized (self.recordedEvents)
    {
        [self.recordedEvents addObject:event];

        if (self.recordedEvents.count >= self.eventSendThreshold)
            [CountlyConnectionManager.sharedInstance sendEvents];
    }
}

- (NSString *)serializedRecordedEvents
{
    NSMutableArray* tempArray = NSMutableArray.new;

    @synchronized (self.recordedEvents)
    {
        if (self.recordedEvents.count == 0)
            return nil;

        for (CountlyEvent* event in self.recordedEvents.copy)
        {
            [tempArray addObject:[event dictionaryRepresentation]];
            [self.recordedEvents removeObject:event];
        }
    }

    return [tempArray cly_JSONify];
}

- (void)flushEvents
{
    @synchronized (self.recordedEvents)
    {
        [self.recordedEvents removeAllObjects];
    }
}

#pragma mark ---

- (void)recordTimedEvent:(CountlyEvent *)event
{
    @synchronized (self.startedEvents)
    {
        if (self.startedEvents[event.key])
        {
            COUNTLY_LOG(@"Event with key '%@' already started!", event.key);
            return;
        }

        self.startedEvents[event.key] = event;
    }
}

- (CountlyEvent *)timedEventForKey:(NSString *)key
{
    @synchronized (self.startedEvents)
    {
        CountlyEvent *event = self.startedEvents[key];
        [self.startedEvents removeObjectForKey:key];

        return event;
    }
}

- (void)clearAllTimedEvents
{
    @synchronized (self.startedEvents)
    {
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
        }
        else
        {
            NSError* error = nil;
            [line writeToFile:crashLogFileURL.path atomically:YES encoding:NSUTF8StringEncoding error:&error];
            if (error)
            {
                COUNTLY_LOG(@"Crash Log File can not be created: \n%@", error);
            }
        }
    });
}

- (NSString *)customCrashLogsFromFile
{
    NSURL* crashLogFileURL = [[self storageDirectoryURL] URLByAppendingPathComponent:kCountlyCustomCrashLogFileName];
    NSData* readData = [NSData dataWithContentsOfURL:crashLogFileURL];

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
        COUNTLY_LOG(@"Detected Crash Log File and deleting it.");
        [NSFileManager.defaultManager removeItemAtURL:crashLogFileURL error:&error];
        if (error)
        {
            COUNTLY_LOG(@"Crash Log File can not be deleted: \n%@", error);
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
                COUNTLY_LOG(@"Application Support directory can not be created: \n%@", error);
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
    NSData* saveData;

    @synchronized (self)
    {
        saveData = [NSKeyedArchiver archivedDataWithRootObject:@{kCountlyQueuedRequestsPersistencyKey: self.queuedRequests}];
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-variable"

    BOOL writeResult = [saveData writeToFile:[self storageFileURL].path atomically:YES];
    COUNTLY_LOG(@"Result of writing data to file: %d", writeResult);

#pragma clang diagnostic pop

    [CountlyCommon.sharedInstance finishBackgroundTask];
}

#pragma mark ---

- (NSString* )retrieveDeviceID
{
    NSString* retrievedDeviceID = [NSUserDefaults.standardUserDefaults objectForKey:kCountlyStoredDeviceIDKey];

    if (retrievedDeviceID)
    {
        COUNTLY_LOG(@"Device ID successfully retrieved from UserDefaults: %@", retrievedDeviceID);
        return retrievedDeviceID;
    }

    COUNTLY_LOG(@"There is no stored Device ID in UserDefaults!");

    return nil;
}

- (void)storeDeviceID:(NSString *)deviceID
{
    [NSUserDefaults.standardUserDefaults setObject:deviceID forKey:kCountlyStoredDeviceIDKey];
    [NSUserDefaults.standardUserDefaults synchronize];

    COUNTLY_LOG(@"Device ID successfully stored in UserDefaults: %@", deviceID);
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
    NSDictionary* remoteConfig = [NSUserDefaults.standardUserDefaults objectForKey:kCountlyRemoteConfigPersistencyKey];
    if (!remoteConfig)
        remoteConfig = NSDictionary.new;

    return remoteConfig;
}

- (void)storeRemoteConfig:(NSDictionary *)remoteConfig
{
    [NSUserDefaults.standardUserDefaults setObject:remoteConfig forKey:kCountlyRemoteConfigPersistencyKey];
    [NSUserDefaults.standardUserDefaults synchronize];
}

@end
