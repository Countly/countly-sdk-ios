// CountlyPersistency.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@implementation CountlyPersistency
NSString* const kCountlyQueuedRequestsPersistencyKey = @"kCountlyQueuedRequestsPersistencyKey";
NSString* const kCountlyStartedEventsPersistencyKey = @"kCountlyStartedEventsPersistencyKey";

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
        NSData* readData = [NSData dataWithContentsOfURL:[self storageFileURL]];
    
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
    [self.queuedRequests addObject:queryString];
}

- (NSURL *)storageFileURL
{
    NSString* const kCountlyPersistencyFileName = @"Countly.dat";

    static NSURL *url = nil;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        url = [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject];
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
        NSDictionary* saveDict = @{
                                    kCountlyQueuedRequestsPersistencyKey:self.queuedRequests,
                                    kCountlyStartedEventsPersistencyKey:self.startedEvents
                                  };
    
        NSData* saveData = [NSKeyedArchiver archivedDataWithRootObject:saveDict];

        [saveData writeToFile:[self storageFileURL].path atomically:YES];
    });
}
@end
