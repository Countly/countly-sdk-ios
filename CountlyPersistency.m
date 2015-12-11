// CountlyPersistency.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@implementation CountlyPersistency

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
        NSError* error = nil;
    
        if(readData)
            self.queuedRequests = [[NSJSONSerialization JSONObjectWithData:readData options:0 error:&error] mutableCopy];
    
        if(error){ COUNTLY_LOG(@"Cannot restore the data read from disk, error: %@", error); }

        if(!self.queuedRequests)
            self.queuedRequests = NSMutableArray.new;

        self.recordedEvents = NSMutableArray.new;
    }
    
    return self;
}

- (void)addToQueue:(NSString*)queryString
{
#ifdef COUNTLY_TARGET_WATCHKIT
    NSDictionary* watchSegmentation = @{@"[CLY]_apple_watch":(WKInterfaceDevice.currentDevice.screenBounds.size.width == 136.0)?@"38mm":@"42mm"};
    
    queryString = [queryString stringByAppendingFormat:@"&segment=%@", [watchSegmentation JSONify]];
#endif
    
    [self.queuedRequests addObject:queryString];
}

- (NSURL *)storageFileURL
{
    static NSURL *url = nil;

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
#ifdef COUNTLY_APP_GROUP_ID
        url = [[NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:COUNTLY_APP_GROUP_ID] URLByAppendingPathComponent:@"Countly.dat"];
#else
        url = [[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject];
        NSError *error = nil;

        if (![NSFileManager.defaultManager fileExistsAtPath:url.absoluteString])
        {
            [NSFileManager.defaultManager createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:&error];
            if(error){ COUNTLY_LOG(@"Cannot create Application Support directory: %@", error); }
        }

        url = [url URLByAppendingPathComponent:@"Countly.dat"];
#endif
    });
    
    return url;
}

- (void)saveToFile
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^
    {
        NSError* error = nil;
        NSData* saveData = [NSJSONSerialization dataWithJSONObject:self.queuedRequests options:0 error:&error];
        if(error){ COUNTLY_LOG(@"Cannot convert to JSON data, error: %@", error); }

        [saveData writeToFile:[self storageFileURL].path atomically:YES];
    });
}
@end
