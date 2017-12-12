// CountlyPersistency.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface CountlyPersistency()
@property (nonatomic, strong) NSMutableArray* queuedRequests;
@property (nonatomic, strong) NSMutableArray* recordedEvents;
@property (nonatomic, strong) NSMutableDictionary* startedEvents;
@end

@implementation CountlyPersistency
NSString* const kCountlyQueuedRequestsPersistencyKey = @"kCountlyQueuedRequestsPersistencyKey";
NSString* const kCountlyStartedEventsPersistencyKey = @"kCountlyStartedEventsPersistencyKey";
NSString* const kCountlyTVOSNSUDKey = @"kCountlyTVOSNSUDKey";
NSString* const kCountlyStoredDeviceIDKey = @"kCountlyStoredDeviceIDKey";
NSString* const kCountlyWatchParentDeviceIDKey = @"kCountlyWatchParentDeviceIDKey";
NSString* const kCountlyStarRatingStatusKey = @"kCountlyStarRatingStatusKey";
NSString* const kCountlyNotificationPermissionKey = @"kCountlyNotificationPermissionKey";

+ (instancetype)sharedInstance
{
    static CountlyPersistency* s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
#if TARGET_OS_TV
        NSData* readData = [NSUserDefaults.standardUserDefaults objectForKey:kCountlyTVOSNSUDKey];
#else
        NSData* readData = [NSData dataWithContentsOfURL:[self storageFileURL]];
#endif
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
    @synchronized (self)
    {
        [self.queuedRequests addObject:queryString];

        if (self.queuedRequests.count > self.storedRequestsLimit && !CountlyConnectionManager.sharedInstance.connection)
        {
            [self.queuedRequests removeObjectsInRange:(NSRange){0,1}];
        }
    }
}

- (void)removeFromQueue:(NSString *)queryString
{
    @synchronized (self)
    {
        [self.queuedRequests removeObject:queryString];
    }
}

- (NSString *)firstItemInQueue
{
    @synchronized (self)
    {
        return self.queuedRequests.firstObject;
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

- (NSURL *)storageFileURL
{
    NSString* const kCountlyPersistencyFileName = @"Countly.dat";

    static NSURL *url = nil;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        url = [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject];
#if TARGET_OS_OSX
        url = [url URLByAppendingPathComponent:NSBundle.mainBundle.bundleIdentifier];
#endif
        NSError *error = nil;

        if (![NSFileManager.defaultManager fileExistsAtPath:url.absoluteString])
        {
            [NSFileManager.defaultManager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:&error];
            if (error){ COUNTLY_LOG(@"Application Support directory can not be created: \n%@", error); }
        }

        url = [url URLByAppendingPathComponent:kCountlyPersistencyFileName];
    });

    return url;
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
        saveData = [NSKeyedArchiver archivedDataWithRootObject:@{kCountlyQueuedRequestsPersistencyKey:self.queuedRequests}];
    }
#if TARGET_OS_TV
    [NSUserDefaults.standardUserDefaults setObject:saveData forKey:kCountlyTVOSNSUDKey];
    [NSUserDefaults.standardUserDefaults synchronize];
#else
    [saveData writeToFile:[self storageFileURL].path atomically:YES];
#endif
}

#pragma mark ---

- (NSString* )retrieveStoredDeviceID
{
    NSString* retrievedDeviceID = [NSUserDefaults.standardUserDefaults objectForKey:kCountlyStoredDeviceIDKey];

    if (retrievedDeviceID)
    {
        COUNTLY_LOG(@"Device ID successfully retrieved from UserDefaults: %@", retrievedDeviceID);
        return retrievedDeviceID;
    }

    NSDictionary *keychainDict =
    @{
        (__bridge id)kSecAttrAccount:       kCountlyStoredDeviceIDKey,
        (__bridge id)kSecAttrService:       kCountlyStoredDeviceIDKey,
        (__bridge id)kSecClass:             (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccessible:    (__bridge id)kSecAttrAccessibleAlways,
        (__bridge id)kSecReturnData:        (__bridge id)kCFBooleanTrue,
        (__bridge id)kSecReturnAttributes:  (__bridge id)kCFBooleanTrue
    };

    CFDictionaryRef resultDictRef = nil;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)keychainDict, (CFTypeRef *)&resultDictRef);
    if (status == noErr)
    {
        NSDictionary *resultDict = (__bridge_transfer NSDictionary *)resultDictRef;
        NSData *data = resultDict[(__bridge id)kSecValueData];

        if (data)
        {
            retrievedDeviceID = [data cly_stringUTF8];

            COUNTLY_LOG(@"Device ID successfully retrieved from KeyChain: %@", retrievedDeviceID);

            [NSUserDefaults.standardUserDefaults setObject:retrievedDeviceID forKey:kCountlyStoredDeviceIDKey];
            [NSUserDefaults.standardUserDefaults synchronize];

            return retrievedDeviceID;
        }
    }

    COUNTLY_LOG(@"Device ID can not be retrieved!");

    return nil;
}

- (void)storeDeviceID:(NSString *)deviceID
{
    [NSUserDefaults.standardUserDefaults setObject:deviceID forKey:kCountlyStoredDeviceIDKey];
    [NSUserDefaults.standardUserDefaults synchronize];

    NSDictionary *keychainDict =
    @{
        (__bridge id)kSecAttrAccount:       kCountlyStoredDeviceIDKey,
        (__bridge id)kSecAttrService:       kCountlyStoredDeviceIDKey,
        (__bridge id)kSecClass:             (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccessible:    (__bridge id)kSecAttrAccessibleAlways,
        (__bridge id)kSecValueData:         [deviceID cly_dataUTF8]
    };

    SecItemDelete((__bridge CFDictionaryRef)keychainDict);

    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)keychainDict, NULL);

    if (status == noErr)
    {
        COUNTLY_LOG(@"Device ID successfully stored: %@", deviceID);
    }
    else
    {
        COUNTLY_LOG(@"Device ID can not be stored! %d", (int)status);
    }
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

@end
