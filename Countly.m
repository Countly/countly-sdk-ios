// Countly.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#pragma mark - Directives

#if __has_feature(objc_arc)
#error This is a non-ARC class. Please add -fno-objc-arc flag for Countly.m, Countly_OpenUDID.m and CountlyDB.m under Build Phases > Compile Sources
#endif

#ifndef COUNTLY_DEBUG
#define COUNTLY_DEBUG 0
#endif

#ifndef COUNTLY_IGNORE_INVALID_CERTIFICATES
#define COUNTLY_IGNORE_INVALID_CERTIFICATES 0
#endif

#if COUNTLY_DEBUG
#   define COUNTLY_LOG(fmt, ...) NSLog(fmt, ##__VA_ARGS__)
#else
#   define COUNTLY_LOG(...)
#endif

#define COUNTLY_VERSION "2.0"
#define COUNTLY_DEFAULT_UPDATE_INTERVAL 60.0
#define COUNTLY_EVENT_SEND_THRESHOLD 10

#import "Countly.h"
#import "Countly_OpenUDID.h"
#import "CountlyDB.h"

#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
#import <UIKit/UIKit.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
#endif

#include <sys/types.h>
#include <sys/sysctl.h>


#pragma mark - Helper Functions

NSString* CountlyJSONFromObject(id object);
NSString* CountlyURLEscapedString(NSString* string);
NSString* CountlyURLUnescapedString(NSString* string);

NSString* CountlyJSONFromObject(id object)
{
	NSError *error = nil;
	NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
	
	if (error)
        COUNTLY_LOG(@"%@", [error description]);
	
	return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
}

NSString* CountlyURLEscapedString(NSString* string)
{
	// Encode all the reserved characters, per RFC 3986
	// (<http://www.ietf.org/rfc/rfc3986.txt>)
	CFStringRef escaped =
    CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                            (CFStringRef)string,
                                            NULL,
                                            (CFStringRef)@"!*'();:@&=+$,/?%#[]",
                                            kCFStringEncodingUTF8);
	return [(NSString*)escaped autorelease];
}

NSString* CountlyURLUnescapedString(NSString* string)
{
	NSMutableString *resultString = [NSMutableString stringWithString:string];
	[resultString replaceOccurrencesOfString:@"+"
								  withString:@" "
									 options:NSLiteralSearch
									   range:NSMakeRange(0, [resultString length])];
	return [resultString stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
}


#pragma mark - CountlyDeviceInfo

@interface CountlyDeviceInfo : NSObject

+ (NSString *)udid;
+ (NSString *)device;
+ (NSString *)osName;
+ (NSString *)osVersion;
+ (NSString *)carrier;
+ (NSString *)resolution;
+ (NSString *)locale;
+ (NSString *)appVersion;

+ (NSString *)metrics;

@end

@implementation CountlyDeviceInfo

+ (NSString *)udid
{
	return [Countly_OpenUDID value];
}

+ (NSString *)device
{
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
    char *modelKey = "hw.machine";
#else
    char *modelKey = "hw.model";
#endif
    size_t size;
    sysctlbyname(modelKey, NULL, &size, NULL, 0);
    char *model = malloc(size);
    sysctlbyname(modelKey, model, &size, NULL, 0);
    NSString *modelString = [NSString stringWithUTF8String:model];
    free(model);
    return modelString;
}

+ (NSString *)osName
{
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
	return @"iOS";
#else
	return @"OS X";
#endif
}

+ (NSString *)osVersion
{
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
	return [[UIDevice currentDevice] systemVersion];
#else
    return [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"][@"ProductVersion"];
#endif
}

+ (NSString *)carrier
{
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
	if (NSClassFromString(@"CTTelephonyNetworkInfo"))
	{
		CTTelephonyNetworkInfo *netinfo = [[[CTTelephonyNetworkInfo alloc] init] autorelease];
		CTCarrier *carrier = [netinfo subscriberCellularProvider];
		return [carrier carrierName];
	}
#endif
	return nil;
}

+ (NSString *)resolution
{
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
	CGRect bounds = UIScreen.mainScreen.bounds;
	CGFloat scale = [UIScreen.mainScreen respondsToSelector:@selector(scale)] ? [UIScreen.mainScreen scale] : 1.f;
    return [NSString stringWithFormat:@"%gx%g", bounds.size.width * scale, bounds.size.height * scale];
#else
    NSRect screenRect = NSScreen.mainScreen.frame;
    CGFloat scale = [NSScreen.mainScreen backingScaleFactor];
    return [NSString stringWithFormat:@"%gx%g", screenRect.size.width * scale, screenRect.size.height * scale];
#endif
}

+ (NSString *)locale
{
	return [[NSLocale currentLocale] localeIdentifier];
}

+ (NSString *)appVersion
{
    NSString *result = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if ([result length] == 0)
        result = [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString*)kCFBundleVersionKey];
    
    return result;
}

+ (NSString *)metrics
{
    NSMutableDictionary* metricsDictionary = [NSMutableDictionary dictionary];
	[metricsDictionary setObject:CountlyDeviceInfo.device forKey:@"_device"];
	[metricsDictionary setObject:CountlyDeviceInfo.osName forKey:@"_os"];
	[metricsDictionary setObject:CountlyDeviceInfo.osVersion forKey:@"_os_version"];
    
	NSString *carrier = CountlyDeviceInfo.carrier;
	if (carrier)
        [metricsDictionary setObject:carrier forKey:@"_carrier"];

	[metricsDictionary setObject:CountlyDeviceInfo.resolution forKey:@"_resolution"];
	[metricsDictionary setObject:CountlyDeviceInfo.locale forKey:@"_locale"];
	[metricsDictionary setObject:CountlyDeviceInfo.appVersion forKey:@"_app_version"];
	
	return CountlyURLEscapedString(CountlyJSONFromObject(metricsDictionary));
}

@end


#pragma mark - CountlyEvent

@interface CountlyEvent : NSObject
{
}

@property (nonatomic, copy) NSString *key;
@property (nonatomic, retain) NSDictionary *segmentation;
@property (nonatomic, assign) int count;
@property (nonatomic, assign) double sum;
@property (nonatomic, assign) NSTimeInterval timestamp;

@end

@implementation CountlyEvent

- (void)dealloc
{
    self.key = nil;
    self.segmentation = nil;
    [super dealloc];
}

+ (CountlyEvent*)objectWithManagedObject:(NSManagedObject*)managedObject
{
	CountlyEvent* event = [[CountlyEvent new] autorelease];
	
	event.key = [managedObject valueForKey:@"key"];
	event.count = [[managedObject valueForKey:@"count"] doubleValue];
	event.sum = [[managedObject valueForKey:@"sum"] doubleValue];
	event.timestamp = [[managedObject valueForKey:@"timestamp"] doubleValue];
	event.segmentation = [managedObject valueForKey:@"segmentation"];
    return event;
}

- (NSDictionary*)serializedData
{
	NSMutableDictionary* eventData = NSMutableDictionary.dictionary;
	[eventData setObject:self.key forKey:@"key"];
	if (self.segmentation)
    {
		[eventData setObject:self.segmentation forKey:@"segmentation"];
	}
	[eventData setObject:@(self.count) forKey:@"count"];
	[eventData setObject:@(self.sum) forKey:@"sum"];
	[eventData setObject:@(self.timestamp) forKey:@"timestamp"];
	return eventData;
}

@end


#pragma mark - CountlyEventQueue

@interface CountlyEventQueue : NSObject

@end


@implementation CountlyEventQueue

- (void)dealloc
{
    [super dealloc];
}

- (NSUInteger)count
{
    @synchronized (self)
    {
        return [[CountlyDB sharedInstance] getEventCount];
    }
}


- (NSString *)events
{
    NSMutableArray* result = [NSMutableArray array];
    
	@synchronized (self)
    {
		NSArray* events = [[[[CountlyDB sharedInstance] getEvents] copy] autorelease];
		for (id managedEventObject in events)
        {
			CountlyEvent* event = [CountlyEvent objectWithManagedObject:managedEventObject];
            
			[result addObject:event.serializedData];
            
            [CountlyDB.sharedInstance deleteEvent:managedEventObject];
        }
    }
    
	return CountlyURLEscapedString(CountlyJSONFromObject(result));
}

- (void)recordEvent:(NSString *)key count:(int)count
{
    @synchronized (self)
    {
        NSArray* events = [[[[CountlyDB sharedInstance] getEvents] copy] autorelease];
        for (NSManagedObject* obj in events)
        {
            CountlyEvent *event = [CountlyEvent objectWithManagedObject:obj];
            if ([event.key isEqualToString:key])
            {
                event.count += count;
                event.timestamp = (event.timestamp + time(NULL)) / 2;
                
                [obj setValue:@(event.count) forKey:@"count"];
                [obj setValue:@(event.timestamp) forKey:@"timestamp"];
                
                [[CountlyDB sharedInstance] saveContext];
                return;
            }
        }
        
        CountlyEvent *event = [[CountlyEvent new] autorelease];
        event.key = key;
        event.count = count;
        event.timestamp = time(NULL);
        
        [[CountlyDB sharedInstance] createEvent:event.key count:event.count sum:event.sum segmentation:event.segmentation timestamp:event.timestamp];
    }
}

- (void)recordEvent:(NSString *)key count:(int)count sum:(double)sum
{
    @synchronized (self)
    {
        NSArray* events = [[[[CountlyDB sharedInstance] getEvents] copy] autorelease];
        for (NSManagedObject* obj in events)
        {
            CountlyEvent *event = [CountlyEvent objectWithManagedObject:obj];
            if ([event.key isEqualToString:key])
            {
                event.count += count;
                event.sum += sum;
                event.timestamp = (event.timestamp + time(NULL)) / 2;
                
                [obj setValue:@(event.count) forKey:@"count"];
                [obj setValue:@(event.sum) forKey:@"sum"];
                [obj setValue:@(event.timestamp) forKey:@"timestamp"];
                
                [[CountlyDB sharedInstance] saveContext];
                
                return;
            }
        }
        
        CountlyEvent *event = [[CountlyEvent new] autorelease];
        event.key = key;
        event.count = count;
        event.sum = sum;
        event.timestamp = time(NULL);
        
        [[CountlyDB sharedInstance] createEvent:event.key count:event.count sum:event.sum segmentation:event.segmentation timestamp:event.timestamp];
    }
}

- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(int)count;
{
    @synchronized (self)
    {
        NSArray* events = [[[[CountlyDB sharedInstance] getEvents] copy] autorelease];
        for (NSManagedObject* obj in events)
        {
            CountlyEvent *event = [CountlyEvent objectWithManagedObject:obj];
            if ([event.key isEqualToString:key] &&
                event.segmentation && [event.segmentation isEqualToDictionary:segmentation])
            {
                event.count += count;
                event.timestamp = (event.timestamp + time(NULL)) / 2;
                
                [obj setValue:@(event.count) forKey:@"count"];
                [obj setValue:@(event.timestamp) forKey:@"timestamp"];
                
                [[CountlyDB sharedInstance] saveContext];
                
                return;
            }
        }
        
        CountlyEvent *event = [[CountlyEvent new] autorelease];
        event.key = key;
        event.segmentation = segmentation;
        event.count = count;
        event.timestamp = time(NULL);
        
        [[CountlyDB sharedInstance] createEvent:event.key count:event.count sum:event.sum segmentation:event.segmentation timestamp:event.timestamp];
    }
}

- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(int)count sum:(double)sum;
{
    @synchronized (self)
    {
        NSArray* events = [[[[CountlyDB sharedInstance] getEvents] copy] autorelease];
        for (NSManagedObject* obj in events)
        {
            CountlyEvent *event = [CountlyEvent objectWithManagedObject:obj];
            if ([event.key isEqualToString:key] &&
                event.segmentation && [event.segmentation isEqualToDictionary:segmentation])
            {
                event.count += count;
                event.sum += sum;
                event.timestamp = (event.timestamp + time(NULL)) / 2;
                
                [obj setValue:@(event.count) forKey:@"count"];
                [obj setValue:@(event.sum) forKey:@"sum"];
                [obj setValue:@(event.timestamp) forKey:@"timestamp"];
                
                [[CountlyDB sharedInstance] saveContext];
                
                return;
            }
        }
        
        CountlyEvent *event = [[CountlyEvent new] autorelease];
        event.key = key;
        event.segmentation = segmentation;
        event.count = count;
        event.sum = sum;
        event.timestamp = time(NULL);
        
        [[CountlyDB sharedInstance] createEvent:event.key count:event.count sum:event.sum segmentation:event.segmentation timestamp:event.timestamp];
    }
}

@end


#pragma mark - CountlyConnectionQueue

@interface CountlyConnectionQueue : NSObject

@property (nonatomic, copy) NSString *appKey;
@property (nonatomic, copy) NSString *appHost;
@property (nonatomic, retain) NSURLConnection *connection;
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
@property (nonatomic, assign) UIBackgroundTaskIdentifier bgTask;
#endif

+ (instancetype)sharedInstance;

@end


@implementation CountlyConnectionQueue : NSObject

+ (instancetype)sharedInstance
{
    static CountlyConnectionQueue *s_sharedCountlyConnectionQueue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedCountlyConnectionQueue = self.new;});
	return s_sharedCountlyConnectionQueue;
}

- (void) tick
{
    NSArray* dataQueue = [[[[CountlyDB sharedInstance] getQueue] copy] autorelease];
    
    if (self.connection != nil || [dataQueue count] == 0)
        return;

#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
    if (self.bgTask != UIBackgroundTaskInvalid)
        return;
    
    UIApplication *app = [UIApplication sharedApplication];
    self.bgTask = [app beginBackgroundTaskWithExpirationHandler:^{
		[app endBackgroundTask:self.bgTask];
		self.bgTask = UIBackgroundTaskInvalid;
    }];
#endif
    
    NSString *data = [dataQueue[0] valueForKey:@"post"];
    NSString *urlString = [NSString stringWithFormat:@"%@/i?%@", self.appHost, data];
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    self.connection = [NSURLConnection connectionWithRequest:request delegate:self];

    COUNTLY_LOG(@"Request Started \n %@", urlString);
}

- (void)beginSession
{
	NSString *data = [NSString stringWithFormat:@"app_key=%@&device_id=%@&timestamp=%ld&sdk_version="COUNTLY_VERSION"&begin_session=1&metrics=%@",
					  self.appKey,
					  [CountlyDeviceInfo udid],
					  time(NULL),
					  [CountlyDeviceInfo metrics]];
    
    [[CountlyDB sharedInstance] addToQueue:data];
    
	[self tick];
}

- (void)updateSessionWithDuration:(int)duration
{
	NSString *data = [NSString stringWithFormat:@"app_key=%@&device_id=%@&timestamp=%ld&session_duration=%d",
					  self.appKey,
					  [CountlyDeviceInfo udid],
					  time(NULL),
					  duration];
    
    [[CountlyDB sharedInstance] addToQueue:data];
    
	[self tick];
}

- (void)endSessionWithDuration:(int)duration
{
	NSString *data = [NSString stringWithFormat:@"app_key=%@&device_id=%@&timestamp=%ld&end_session=1&session_duration=%d",
					  self.appKey,
					  [CountlyDeviceInfo udid],
					  time(NULL),
					  duration];
    
    [[CountlyDB sharedInstance] addToQueue:data];
    
	[self tick];
}

- (void)recordEvents:(NSString *)events
{
	NSString *data = [NSString stringWithFormat:@"app_key=%@&device_id=%@&timestamp=%ld&events=%@",
					  self.appKey,
					  [CountlyDeviceInfo udid],
					  time(NULL),
					  events];
    
    [[CountlyDB sharedInstance] addToQueue:data];
    
	[self tick];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    NSArray* dataQueue = [[[CountlyDB sharedInstance] getQueue] copy];
    
	COUNTLY_LOG(@"Request Completed\n");
    
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
    UIApplication *app = [UIApplication sharedApplication];
    if (self.bgTask != UIBackgroundTaskInvalid)
    {
        [app endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }
#endif

    self.connection = nil;
    
    [[CountlyDB sharedInstance] removeFromQueue:dataQueue[0]];
    
    [dataQueue release];
    
    [self tick];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)err
{
    #if COUNTLY_DEBUG
        NSArray* dataQueue = [[[[CountlyDB sharedInstance] getQueue] copy] autorelease];
        COUNTLY_LOG(@"Request Failed \n %@: %@", [dataQueue[0] description], [err description]);
    #endif
    
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
    UIApplication *app = [UIApplication sharedApplication];
    if (self.bgTask != UIBackgroundTaskInvalid)
    {
        [app endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }
#endif
    
    self.connection = nil;
}

#if COUNTLY_IGNORE_INVALID_CERTIFICATES
- (void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust])
        [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
    
    [[challenge sender] continueWithoutCredentialForAuthenticationChallenge:challenge];
}
#endif

- (void)dealloc
{
	if (self.connection)
    {
		[self.connection cancel];
        self.connection = nil;
    }
	self.appKey = nil;
	self.appHost = nil;

	[super dealloc];
}

@end


#pragma mark - Countly Core

@implementation Countly

+ (instancetype)sharedInstance
{
    static Countly *s_sharedCountly = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedCountly = self.new;});
	return s_sharedCountly;
}

- (id)init
{
	if (self = [super init])
	{
		timer = nil;
		isSuspended = NO;
		unsentSessionLength = 0;
        eventQueue = [[CountlyEventQueue alloc] init];

#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(didEnterBackgroundCallBack:)
													 name:UIApplicationDidEnterBackgroundNotification
												   object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(willEnterForegroundCallBack:)
													 name:UIApplicationWillEnterForegroundNotification
												   object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self
												 selector:@selector(willTerminateCallBack:)
													 name:UIApplicationWillTerminateNotification
												   object:nil];
#endif
	}
	return self;
}

- (void)start:(NSString *)appKey withHost:(NSString *)appHost
{
	timer = [NSTimer scheduledTimerWithTimeInterval:COUNTLY_DEFAULT_UPDATE_INTERVAL
											 target:self
										   selector:@selector(onTimer:)
										   userInfo:nil
											repeats:YES];
	lastTime = CFAbsoluteTimeGetCurrent();
	[[CountlyConnectionQueue sharedInstance] setAppKey:appKey];
	[[CountlyConnectionQueue sharedInstance] setAppHost:appHost];
	[[CountlyConnectionQueue sharedInstance] beginSession];
}

- (void)startOnCloudWithAppKey:(NSString *)appKey
{
    [self start:appKey withHost:@"https://cloud.count.ly"];
}

- (void)recordEvent:(NSString *)key count:(int)count
{
    [eventQueue recordEvent:key count:count];
    
    if (eventQueue.count >= COUNTLY_EVENT_SEND_THRESHOLD)
        [[CountlyConnectionQueue sharedInstance] recordEvents:[eventQueue events]];
}

- (void)recordEvent:(NSString *)key count:(int)count sum:(double)sum
{
    [eventQueue recordEvent:key count:count sum:sum];
    
    if (eventQueue.count >= COUNTLY_EVENT_SEND_THRESHOLD)
        [[CountlyConnectionQueue sharedInstance] recordEvents:[eventQueue events]];
}

- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(int)count
{
    [eventQueue recordEvent:key segmentation:segmentation count:count];
    
    if (eventQueue.count >= COUNTLY_EVENT_SEND_THRESHOLD)
        [[CountlyConnectionQueue sharedInstance] recordEvents:[eventQueue events]];
}

- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(int)count sum:(double)sum
{
    [eventQueue recordEvent:key segmentation:segmentation count:count sum:sum];
    
    if (eventQueue.count >= COUNTLY_EVENT_SEND_THRESHOLD)
        [[CountlyConnectionQueue sharedInstance] recordEvents:[eventQueue events]];
}

- (void)onTimer:(NSTimer *)timer
{
	if (isSuspended == YES)
		return;
    
	double currTime = CFAbsoluteTimeGetCurrent();
	unsentSessionLength += currTime - lastTime;
	lastTime = currTime;
    
	int duration = unsentSessionLength;
	[[CountlyConnectionQueue sharedInstance] updateSessionWithDuration:duration];
	unsentSessionLength -= duration;
    
    if (eventQueue.count > 0)
        [[CountlyConnectionQueue sharedInstance] recordEvents:[eventQueue events]];
}

- (void)suspend
{
	isSuspended = YES;
    
    if (eventQueue.count > 0)
        [[CountlyConnectionQueue sharedInstance] recordEvents:[eventQueue events]];
    
	double currTime = CFAbsoluteTimeGetCurrent();
	unsentSessionLength += currTime - lastTime;
    
	int duration = unsentSessionLength;
	[[CountlyConnectionQueue sharedInstance] endSessionWithDuration:duration];
	unsentSessionLength -= duration;
}

- (void)resume
{
	lastTime = CFAbsoluteTimeGetCurrent();
    
	[[CountlyConnectionQueue sharedInstance] beginSession];
    
	isSuspended = NO;
}

- (void)exit
{
}

- (void)dealloc
{
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
    [[NSNotificationCenter defaultCenter] removeObserver:self];
#endif
    
	if (timer)
    {
        [timer invalidate];
        timer = nil;
    }
    
    [eventQueue release];
	
	[super dealloc];
}

- (void)didEnterBackgroundCallBack:(NSNotification *)notification
{
	COUNTLY_LOG(@"App didEnterBackground");
	[self suspend];
}

- (void)willEnterForegroundCallBack:(NSNotification *)notification
{
	COUNTLY_LOG(@"App willEnterForeground");
	[self resume];
}

- (void)willTerminateCallBack:(NSNotification *)notification
{
	COUNTLY_LOG(@"App willTerminate");
    [[CountlyDB sharedInstance] saveContext];
	[self exit];
}

#pragma mark - CrashReporting
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <arpa/inet.h>
#import <ifaddrs.h>

#define kCountlyCrashEvent   @"[CLY]_crash"

- (void)startCrashReporting
{
    NSSetUncaughtExceptionHandler(&CountlyUncaughtExceptionHandler);
}

void CountlyUncaughtExceptionHandler(NSException *exception)
{
    NSMutableDictionary* crashReport = NSMutableDictionary.dictionary;
    crashReport[@"name"] = exception.name;
    crashReport[@"description"] = exception.debugDescription;
    crashReport[@"stack"] = [exception.callStackSymbols componentsJoinedByString:@"\n"];
    crashReport[@"freeRAM"] = @(Countly.sharedInstance.freeRAM);
    crashReport[@"totalRAM"] = @(Countly.sharedInstance.totalRAM);
    crashReport[@"freeDisk"] = @(Countly.sharedInstance.freeDisk);
    crashReport[@"totalDisk"] = @(Countly.sharedInstance.totalDisk);
    crashReport[@"batteryLevel"] = @(Countly.sharedInstance.batteryLevel);
    crashReport[@"orientation"] = @(Countly.sharedInstance.orientation);
    crashReport[@"connection"] = @(Countly.sharedInstance.connectionType);
    crashReport[@"proximity"] = @(Countly.sharedInstance.isProximitySensorActive);
    crashReport[@"jailbroken"] = @(Countly.sharedInstance.isJailbroken);
    if(CountlyCustomCrashLogs)
        crashReport[@"customLogs"] = [CountlyCustomCrashLogs componentsJoinedByString:@"\n"];


   
    CountlyEvent *event = CountlyEvent.new.autorelease;
    event.key = kCountlyCrashEvent;
    event.segmentation = crashReport;
    event.count = 1;
    event.timestamp = time(NULL);
   
    NSString *urlString = [NSString stringWithFormat:@"%@/i?app_key=%@&device_id=%@&timestamp=%ld&events=%@",
                           CountlyConnectionQueue.sharedInstance.appHost,
                           CountlyConnectionQueue.sharedInstance.appKey,
                           [CountlyDeviceInfo udid],
                           time(NULL),
                           CountlyURLEscapedString(CountlyJSONFromObject(@[event.serializedData]))];
    
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]];

    COUNTLY_LOG(@"CrashReporting URL: %@", urlString);

    NSURLResponse* response = nil;
	NSError* error = nil;
	NSData* recvData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
	
	if (error || !recvData)
    {
        COUNTLY_LOG(@"CrashReporting failed, report stored to try again later");
        [CountlyConnectionQueue.sharedInstance recordEvents:CountlyURLEscapedString(CountlyJSONFromObject(@[event.serializedData]))];
    }
}

static NSMutableArray *CountlyCustomCrashLogs = nil;

void CCL(const char* function, NSUInteger line, NSString* message)
{
    static NSDateFormatter* df = nil;
    
    if( CountlyCustomCrashLogs == nil )
    {
        CountlyCustomCrashLogs = NSMutableArray.new;
        df = NSDateFormatter.new;
        df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    }

    NSString* f = [[NSString.alloc initWithUTF8String:function].autorelease stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-[]"]];
    NSString* log = [NSString stringWithFormat:@"[%@] <%@ %li> %@",[df stringFromDate:NSDate.date],f,(unsigned long)line,message];
    [CountlyCustomCrashLogs addObject:log];
}

- (unsigned long long)freeRAM
{
    vm_statistics_data_t vms;
    mach_msg_type_number_t ic = HOST_VM_INFO_COUNT;
    kern_return_t kr = host_statistics(mach_host_self(), HOST_VM_INFO, (host_info_t)&vms, &ic);
    if(kr != KERN_SUCCESS)
        return -1;

    return vm_page_size * (vms.free_count);
}

- (unsigned long long)totalRAM
{
    return NSProcessInfo.processInfo.physicalMemory;
}

- (unsigned long long)freeDisk
{
    return [[NSFileManager.defaultManager attributesOfFileSystemForPath:NSHomeDirectory() error:nil][NSFileSystemFreeSize] longLongValue];
}

- (unsigned long long)totalDisk
{
    return [[NSFileManager.defaultManager attributesOfFileSystemForPath:NSHomeDirectory() error:nil][NSFileSystemSize] longLongValue];
}

- (NSInteger)batteryLevel
{
    UIDevice.currentDevice.batteryMonitoringEnabled = YES;
    return UIDevice.currentDevice.batteryLevel*100;
}

- (NSInteger)orientation
{
    return UIDevice.currentDevice.orientation;
}

-(NSUInteger)connectionType
{
    typedef enum:NSInteger {CLYConnectionNone, CLYConnectionCellNetwork, CLYConnectionWiFi} CLYConnectionType;
    CLYConnectionType connType = CLYConnectionNone;
    
    @try
    {
        struct ifaddrs *interfaces, *i;
       
        if (!getifaddrs(&interfaces))
        {
            i = interfaces;
            
            while(i != NULL)
            {
                if(i->ifa_addr->sa_family == AF_INET)
                {
                    if([[NSString stringWithUTF8String:i->ifa_name] isEqualToString:@"pdp_ip0"])
                    {
                        connType = CLYConnectionCellNetwork;
                    }
                    else if([[NSString stringWithUTF8String:i->ifa_name] isEqualToString:@"en0"])
                    {
                        connType = CLYConnectionWiFi;
                        break;
                    }
                }
                
                i = i->ifa_next;
            }
        }
        
        freeifaddrs(interfaces);
    }
    @catch (NSException *exception)
    {
    
    }

    return connType;
}

- (BOOL)isProximitySensorActive
{
    return UIDevice.currentDevice.proximityState;
}

- (BOOL)isJailbroken
{
    FILE *f = fopen("/bin/bash", "r");
    BOOL isJailbroken = (f != NULL);
    fclose(f);
    return isJailbroken;
}
#endif
@end
