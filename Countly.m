// Countly.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.


#ifndef COUNTLY_DEBUG
#define COUNTLY_DEBUG 0
#endif

#ifndef COUNTLY_IGNORE_INVALID_CERTIFICATES
#define COUNTLY_IGNORE_INVALID_CERTIFICATES 1
#endif

#if COUNTLY_DEBUG
#   define COUNTLY_LOG(fmt, ...) NSLog(fmt, ##__VA_ARGS__)
#else
#   define COUNTLY_LOG(...)
#endif

#define COUNTLY_VERSION "1.0"

#import "Countly.h"
#import "Countly_OpenUDID.h"
#import <UIKit/UIKit.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>

#include <sys/types.h>
#include <sys/sysctl.h>


/// Utilities for encoding and decoding URL arguments.
/// This code is from the project google-toolbox-for-mac
@interface NSString (GTMNSStringURLArgumentsAdditions)

/// Returns a string that is escaped properly to be a URL argument.
//
/// This differs from stringByAddingPercentEscapesUsingEncoding: in that it
/// will escape all the reserved characters (per RFC 3986
/// <http://www.ietf.org/rfc/rfc3986.txt>) which
/// stringByAddingPercentEscapesUsingEncoding would leave.
///
/// This will also escape '%', so this should not be used on a string that has
/// already been escaped unless double-escaping is the desired result.
- (NSString*)gtm_stringByEscapingForURLArgument;

/// Returns the unescaped version of a URL argument
//
/// This has the same behavior as stringByReplacingPercentEscapesUsingEncoding:,
/// except that it will also convert '+' to space.
- (NSString*)gtm_stringByUnescapingFromURLArgument;

@end

#define GTMNSMakeCollectable(cf) ((id)(cf))
#define GTMCFAutorelease(cf) ([GTMNSMakeCollectable(cf) autorelease])

@implementation NSString (GTMNSStringURLArgumentsAdditions)

- (NSString*)gtm_stringByEscapingForURLArgument {
	// Encode all the reserved characters, per RFC 3986
	// (<http://www.ietf.org/rfc/rfc3986.txt>)
	CFStringRef escaped = 
    CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                            (CFStringRef)self,
                                            NULL,
                                            (CFStringRef)@"!*'();:@&=+$,/?%#[]",
                                            kCFStringEncodingUTF8);
	return GTMCFAutorelease(escaped);
}

- (NSString*)gtm_stringByUnescapingFromURLArgument {
	NSMutableString *resultString = [NSMutableString stringWithString:self];
	[resultString replaceOccurrencesOfString:@"+"
								  withString:@" "
									 options:NSLiteralSearch
									   range:NSMakeRange(0, [resultString length])];
	return [resultString stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
}

@end


@interface DeviceInfo : NSObject
{
}
@end

@implementation DeviceInfo

+ (NSString *)udid
{
	return [Countly_OpenUDID value];
}

+ (NSString *)device
{
    size_t size;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    char *machine = malloc(size);
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *platform = [NSString stringWithUTF8String:machine];
    free(machine);
    return platform;
}

+ (NSString *)osVersion
{
	return [[UIDevice currentDevice] systemVersion];
}

+ (NSString *)carrier
{
	if (NSClassFromString(@"CTTelephonyNetworkInfo"))
	{
		CTTelephonyNetworkInfo *netinfo = [[[CTTelephonyNetworkInfo alloc] init] autorelease];
		CTCarrier *carrier = [netinfo subscriberCellularProvider];
		return [carrier carrierName];
	}

	return nil;
}

+ (NSString *)resolution
{
	CGRect bounds = [[UIScreen mainScreen] bounds];
	CGFloat scale = [[UIScreen mainScreen] respondsToSelector:@selector(scale)] ? [[UIScreen mainScreen] scale] : 1.f;
	CGSize res = CGSizeMake(bounds.size.width * scale, bounds.size.height * scale);
	NSString *result = [NSString stringWithFormat:@"%gx%g", res.width, res.height];

	return result;
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
	NSString *result = @"{";

	result = [result stringByAppendingFormat:@"\"%@\":\"%@\"", @"_device", [DeviceInfo device]];

	result = [result stringByAppendingFormat:@",\"%@\":\"%@\"", @"_os", @"iOS"];

	result = [result stringByAppendingFormat:@",\"%@\":\"%@\"", @"_os_version", [DeviceInfo osVersion]];

	NSString *carrier = [DeviceInfo carrier];
	if (carrier != nil)
		result = [result stringByAppendingFormat:@",\"%@\":\"%@\"", @"_carrier", carrier];

	result = [result stringByAppendingFormat:@",\"%@\":\"%@\"", @"_resolution", [DeviceInfo resolution]];

	result = [result stringByAppendingFormat:@",\"%@\":\"%@\"", @"_locale", [DeviceInfo locale]];

	result = [result stringByAppendingFormat:@",\"%@\":\"%@\"", @"_app_version", [DeviceInfo appVersion]];

	result = [result stringByAppendingString:@"}"];

	result = [result gtm_stringByEscapingForURLArgument];

	return result;
}

@end

@interface CountlyEvent : NSObject
{
}

@property (nonatomic, copy) NSString *key;
@property (nonatomic, retain) NSDictionary *segmentation;
@property (nonatomic, assign) int count;
@property (nonatomic, assign) double sum;
@property (nonatomic, assign) double timestamp;

@end

@implementation CountlyEvent

@synthesize key = key_;
@synthesize segmentation = segmentation_;
@synthesize count = count_;
@synthesize sum = sum_;
@synthesize timestamp = timestamp_;

- (id)init
{
    if (self = [super init])
    {
        key_ = nil;
        segmentation_ = nil;
        count_ = 0;
        sum_ = 0;
        timestamp_ = 0;
    }
    return self;
}

- (void)dealloc
{
    [key_ release];
    [segmentation_ release];
    [super dealloc];
}

@end

@interface EventQueue : NSObject
{
    NSMutableArray *events_;
}
@end

@implementation EventQueue

- (id)init
{
    if (self = [super init])
    {
        events_ = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [events_ release];
    [super dealloc];
}

- (NSUInteger)count
{
    @synchronized (self)
    {
        return [events_ count];
    }
}

- (NSString *)events
{
    NSString *result = @"[";
    
    @synchronized (self)
    {
        for (int i = 0; i < events_.count; ++i)
        {
            CountlyEvent *event = [events_ objectAtIndex:i];
        
            result = [result stringByAppendingString:@"{"];
        
            result = [result stringByAppendingFormat:@"\"%@\":\"%@\"", @"key", event.key];
        
            if (event.segmentation)
            {
                NSString *segmentation = @"{";
                
                NSArray *keys = [event.segmentation allKeys];
                for (int i = 0; i < keys.count; ++i)
                {
                    NSString *key = [keys objectAtIndex:i];
                    NSString *value = [event.segmentation objectForKey:key];
                    
                    segmentation = [segmentation stringByAppendingFormat:@"\"%@\":\"%@\"", key, value];
                    
                    if (i + 1 < keys.count)
                        segmentation = [segmentation stringByAppendingString:@","];
                }
                segmentation = [segmentation stringByAppendingString:@"}"];

                result = [result stringByAppendingFormat:@",\"%@\":%@", @"segmentation", segmentation];
            }
        
            result = [result stringByAppendingFormat:@",\"%@\":%d", @"count", event.count];
        
            if (event.sum > 0)
                result = [result stringByAppendingFormat:@",\"%@\":%g", @"sum", event.sum];
        
            result = [result stringByAppendingFormat:@",\"%@\":%ld", @"timestamp", (time_t)event.timestamp];
        
            result = [result stringByAppendingString:@"}"];
        
            if (i + 1 < events_.count)
                result = [result stringByAppendingString:@","];
        }

        [events_ release];
        events_ = [[NSMutableArray alloc] init];
    }
        
    result = [result stringByAppendingString:@"]"];
    
    result = [result gtm_stringByEscapingForURLArgument];

	return result;
}

- (void)recordEvent:(NSString *)key count:(int)count
{
    @synchronized (self)
    {
        for (CountlyEvent *event in events_)
        {
            if ([event.key isEqualToString:key])
            {
                event.count += count;
                event.timestamp = (event.timestamp + time(NULL)) / 2;
                return;
            }
        }
    
        CountlyEvent *event = [[CountlyEvent alloc] init];
        event.key = key;
        event.count = count;
        event.timestamp = time(NULL);
        [events_ addObject:event];
        [event release];
    }
}

- (void)recordEvent:(NSString *)key count:(int)count sum:(double)sum
{
    @synchronized (self)
    {
        for (CountlyEvent *event in events_)
        {
            if ([event.key isEqualToString:key])
            {
                event.count += count;
                event.sum += sum;
                event.timestamp = (event.timestamp + time(NULL)) / 2;
                return;
            }
        }
    
        CountlyEvent *event = [[CountlyEvent alloc] init];
        event.key = key;
        event.count = count;
        event.sum = sum;
        event.timestamp = time(NULL);
        [events_ addObject:event];
        [event release];
    }
}

- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(int)count;
{
    @synchronized (self)
    {
        for (CountlyEvent *event in events_)
        {
            if ([event.key isEqualToString:key] &&
                event.segmentation && [event.segmentation isEqualToDictionary:segmentation])
            {
                event.count += count;
                event.timestamp = (event.timestamp + time(NULL)) / 2;
                return;
            }
        }

        CountlyEvent *event = [[CountlyEvent alloc] init];
        event.key = key;
        event.segmentation = segmentation;
        event.count = count;
        event.timestamp = time(NULL);
        [events_ addObject:event];
        [event release];
    }
}

- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(int)count sum:(double)sum;
{
    @synchronized (self)
    {
        for (CountlyEvent *event in events_)
        {
            if ([event.key isEqualToString:key] &&
                event.segmentation && [event.segmentation isEqualToDictionary:segmentation])
            {
                event.count += count;
                event.sum += sum;
                event.timestamp = (event.timestamp + time(NULL)) / 2;
                return;
            }
        }
    
        CountlyEvent *event = [[CountlyEvent alloc] init];
        event.key = key;
        event.segmentation = segmentation;
        event.count = count;
        event.sum = sum;
        event.timestamp = time(NULL);
        [events_ addObject:event];
        [event release];
    }
}

@end

@interface ConnectionQueue : NSObject
{
	NSMutableArray *queue_;
	NSURLConnection *connection_;
	UIBackgroundTaskIdentifier bgTask_;
	NSString *appKey;
	NSString *appHost;
}

@property (nonatomic, copy) NSString *appKey;
@property (nonatomic, copy) NSString *appHost;

@end

static ConnectionQueue *s_sharedConnectionQueue = nil;

@implementation ConnectionQueue : NSObject

@synthesize appKey;
@synthesize appHost;

+ (ConnectionQueue *)sharedInstance
{
	if (s_sharedConnectionQueue == nil)
		s_sharedConnectionQueue = [[ConnectionQueue alloc] init];

	return s_sharedConnectionQueue;
}

- (id)init
{
	if (self = [super init])
	{
		queue_ = [[NSMutableArray alloc] init];
		connection_ = nil;
        bgTask_ = UIBackgroundTaskInvalid;
        appKey = nil;
        appHost = nil;
	}
	return self;
}

- (void) tick
{
    if (connection_ != nil || bgTask_ != UIBackgroundTaskInvalid || [queue_ count] == 0)
        return;

    UIApplication *app = [UIApplication sharedApplication];
    bgTask_ = [app beginBackgroundTaskWithExpirationHandler:^{
		[app endBackgroundTask:bgTask_];
		bgTask_ = UIBackgroundTaskInvalid;
    }];

    NSString *data = [queue_ objectAtIndex:0];
    NSString *urlString = [NSString stringWithFormat:@"%@/i?%@", self.appHost, data];
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    connection_ = [NSURLConnection connectionWithRequest:request delegate:self];
}

- (void)beginSession
{
	NSString *data = [NSString stringWithFormat:@"app_key=%@&device_id=%@&timestamp=%ld&sdk_version="COUNTLY_VERSION"&begin_session=1&metrics=%@",
					  appKey,
					  [DeviceInfo udid],
					  time(NULL),
					  [DeviceInfo metrics]];
	[queue_ addObject:data];
	[self tick];
}

- (void)updateSessionWithDuration:(int)duration
{
	NSString *data = [NSString stringWithFormat:@"app_key=%@&device_id=%@&timestamp=%ld&session_duration=%d",
					  appKey,
					  [DeviceInfo udid],
					  time(NULL),
					  duration];
	[queue_ addObject:data];
	[self tick];
}

- (void)endSessionWithDuration:(int)duration
{
	NSString *data = [NSString stringWithFormat:@"app_key=%@&device_id=%@&timestamp=%ld&end_session=1&session_duration=%d",
					  appKey,
					  [DeviceInfo udid],
					  time(NULL),
					  duration];
	[queue_ addObject:data];
	[self tick];
}

- (void)recordEvents:(NSString *)events
{
	NSString *data = [NSString stringWithFormat:@"app_key=%@&device_id=%@&timestamp=%ld&events=%@",
					  appKey,
					  [DeviceInfo udid],
					  time(NULL),
					  events];
	[queue_ addObject:data];
	[self tick];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
	COUNTLY_LOG(@"ok -> %@", [queue_ objectAtIndex:0]);

    UIApplication *app = [UIApplication sharedApplication];
    if (bgTask_ != UIBackgroundTaskInvalid)
    {
        [app endBackgroundTask:bgTask_];
        bgTask_ = UIBackgroundTaskInvalid;
    }

    connection_ = nil;

    [queue_ removeObjectAtIndex:0];

    [self tick];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)err
{
	COUNTLY_LOG(@"error -> %@: %@", [queue_ objectAtIndex:0], err);

    UIApplication *app = [UIApplication sharedApplication];
    if (bgTask_ != UIBackgroundTaskInvalid)
    {
        [app endBackgroundTask:bgTask_];
        bgTask_ = UIBackgroundTaskInvalid;
    }

    connection_ = nil;
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
	[super dealloc];
	
	if (connection_)
		[connection_ cancel];

	[queue_ release];
	
	self.appKey = nil;
	self.appHost = nil;
}

@end

static Countly *s_sharedCountly = nil;

@implementation Countly

+ (Countly *)sharedInstance
{
	if (s_sharedCountly == nil)
		s_sharedCountly = [[Countly alloc] init];

	return s_sharedCountly;
}

- (id)init
{
	if (self = [super init])
	{
		timer = nil;
		isSuspended = NO;
		unsentSessionLength = 0;
        eventQueue = [[EventQueue alloc] init];
		
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
	}
	return self;
}

- (void)start:(NSString *)appKey withHost:(NSString *)appHost
{
	timer = [NSTimer scheduledTimerWithTimeInterval:30.0
											 target:self
										   selector:@selector(onTimer:)
										   userInfo:nil
											repeats:YES];
	lastTime = CFAbsoluteTimeGetCurrent();
	[[ConnectionQueue sharedInstance] setAppKey:appKey];
	[[ConnectionQueue sharedInstance] setAppHost:appHost];
	[[ConnectionQueue sharedInstance] beginSession];
}

- (void)recordEvent:(NSString *)key count:(int)count
{
    [eventQueue recordEvent:key count:count];
    
    if (eventQueue.count >= 5)
        [[ConnectionQueue sharedInstance] recordEvents:[eventQueue events]];
}

- (void)recordEvent:(NSString *)key count:(int)count sum:(double)sum
{
    [eventQueue recordEvent:key count:count sum:sum];

    if (eventQueue.count >= 5)
        [[ConnectionQueue sharedInstance] recordEvents:[eventQueue events]];
}

- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(int)count
{
    [eventQueue recordEvent:key segmentation:segmentation count:count];

    if (eventQueue.count >= 5)
        [[ConnectionQueue sharedInstance] recordEvents:[eventQueue events]];
}

- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(int)count sum:(double)sum
{
    [eventQueue recordEvent:key segmentation:segmentation count:count sum:sum];

    if (eventQueue.count >= 5)
        [[ConnectionQueue sharedInstance] recordEvents:[eventQueue events]];
}

- (void)onTimer:(NSTimer *)timer
{
	if (isSuspended == YES)
		return;

	double currTime = CFAbsoluteTimeGetCurrent();
	unsentSessionLength += currTime - lastTime;
	lastTime = currTime;

	int duration = unsentSessionLength;
	[[ConnectionQueue sharedInstance] updateSessionWithDuration:duration];
	unsentSessionLength -= duration;

    if (eventQueue.count > 0)
        [[ConnectionQueue sharedInstance] recordEvents:[eventQueue events]];
}

- (void)suspend
{
	isSuspended = YES;

    if (eventQueue.count > 0)
        [[ConnectionQueue sharedInstance] recordEvents:[eventQueue events]];

	double currTime = CFAbsoluteTimeGetCurrent();
	unsentSessionLength += currTime - lastTime;

	int duration = unsentSessionLength;
	[[ConnectionQueue sharedInstance] endSessionWithDuration:duration];
	unsentSessionLength -= duration;
}

- (void)resume
{
	lastTime = CFAbsoluteTimeGetCurrent();

	[[ConnectionQueue sharedInstance] beginSession];

	isSuspended = NO;
}

- (void)exit
{
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillEnterForegroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillTerminateNotification object:nil];
	
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
	COUNTLY_LOG(@"Countly didEnterBackgroundCallBack");
	[self suspend];

}

- (void)willEnterForegroundCallBack:(NSNotification *)notification
{
	COUNTLY_LOG(@"Countly willEnterForegroundCallBack");
	[self resume];
}

- (void)willTerminateCallBack:(NSNotification *)notification
{
	COUNTLY_LOG(@"Countly willTerminateCallBack");
	[self exit];
}

@end
