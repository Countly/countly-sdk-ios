// CountlyPersistency.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@implementation CountlyPersistency
NSString* const kCountlyQueuedRequestsPersistencyKey = @"kCountlyQueuedRequestsPersistencyKey";
NSString* const kCountlyStartedEventsPersistencyKey = @"kCountlyStartedEventsPersistencyKey";
NSString* const kCountlyTVOSNSUDKey = @"kCountlyTVOSNSUDKey";
NSString* const kCountlyStoredDeviceIDKey = @"kCountlyStoredDeviceIDKey";
NSString* const kCountlyWatchParentDeviceIDKey = @"kCountlyWatchParentDeviceIDKey";


+ (instancetype)sharedInstance
{
    static CountlyPersistency* s_sharedInstance;
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
        if(readData)
        {
            NSDictionary* readDict = [NSKeyedUnarchiver unarchiveObjectWithData:readData];
        
            self.queuedRequests = [readDict[kCountlyQueuedRequestsPersistencyKey] mutableCopy];

            self.startedEvents = [readDict[kCountlyStartedEventsPersistencyKey] mutableCopy];
        }
    
        if(!self.queuedRequests)
            self.queuedRequests = NSMutableArray.new;

        if(!self.startedEvents)
            self.startedEvents = NSMutableDictionary.new;
    
        self.recordedEvents = NSMutableArray.new;
    }
    
    return self;
}

- (void)addToQueue:(NSString*)queryString
{
    @synchronized (self)
    {
        [self.queuedRequests addObject:queryString];
    }
}

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
            if(error){ COUNTLY_LOG(@"Cannot create Application Support directory: %@", error); }
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
    NSDictionary* saveDict = @{
                                kCountlyQueuedRequestsPersistencyKey:self.queuedRequests,
                                kCountlyStartedEventsPersistencyKey:self.startedEvents
                              };
    NSData* saveData;

    @synchronized (self)
    {
        saveData = [NSKeyedArchiver archivedDataWithRootObject:saveDict];
    }
#if TARGET_OS_TV
    [NSUserDefaults.standardUserDefaults setObject:saveData forKey:kCountlyTVOSNSUDKey];
    [NSUserDefaults.standardUserDefaults synchronize];
#else
    [saveData writeToFile:[self storageFileURL].path atomically:YES];
#endif
}

- (NSString* )retrieveStoredDeviceID
{
    NSString* retrievedDeviceID = nil;
    
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
            retrievedDeviceID = [NSString.alloc initWithData:data encoding:NSUTF8StringEncoding];
        }
    }
    
    COUNTLY_LOG(@"Retrieved Device ID: %@", retrievedDeviceID);
    return retrievedDeviceID;
}

- (void)storeDeviceID:(NSString*)deviceID
{
    NSDictionary *keychainDict =
    @{
        (__bridge id)kSecAttrAccount:       kCountlyStoredDeviceIDKey,
        (__bridge id)kSecAttrService:       kCountlyStoredDeviceIDKey,
        (__bridge id)kSecClass:             (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccessible:    (__bridge id)kSecAttrAccessibleAlways,
        (__bridge id)kSecValueData:         [deviceID dataUsingEncoding:NSUTF8StringEncoding]
    };

    SecItemDelete((__bridge CFDictionaryRef)keychainDict);

    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)keychainDict, NULL);
    
    if(status == noErr)
    {
        COUNTLY_LOG(@"Successfully stored Device ID: %@", deviceID);
    }
    else
    {
        COUNTLY_LOG(@"Failed storing Device ID: %@", deviceID);
    }
}

- (NSString*)retrieveWatchParentDeviceID
{
    return [NSUserDefaults.standardUserDefaults objectForKey:kCountlyWatchParentDeviceIDKey];
}

- (void)storeWatchParentDeviceID:(NSString*)deviceID
{
    [NSUserDefaults.standardUserDefaults setObject:deviceID forKey:kCountlyWatchParentDeviceIDKey];
    [NSUserDefaults.standardUserDefaults synchronize];
}

@end
