// Countly.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.


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

#define COUNTLY_VERSION "1.0"

#define FAIL_LIMIT 5
#define QUEUE_SEND_TRESHOLD 10
#define TICK_DELAY_AFTER_FAIL 10

#import "Countly.h"
#import "Countly_OpenUDID.h"

#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR

#import <UIKit/UIKit.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
#import "CountlyDB.h"

#endif

#include <sys/types.h>
#include <sys/sysctl.h>


/// Utilities for encoding and decoding URL arguments.
/// This code is from the project google-toolbox-for-mac
@interface NSString (Countly_Additions)

/// Returns a string that is escaped properly to be a URL argument.
//
/// This differs from stringByAddingPercentEscapesUsingEncoding: in that it
/// will escape all the reserved characters (per RFC 3986
/// <http://www.ietf.org/rfc/rfc3986.txt>) which
/// stringByAddingPercentEscapesUsingEncoding would leave.
///
/// This will also escape '%', so this should not be used on a string that has
/// already been escaped unless double-escaping is the desired result.
- (NSString*)countly_stringByEscapingForURLArgument;

/// Returns the unescaped version of a URL argument
//
/// This has the same behavior as stringByReplacingPercentEscapesUsingEncoding:,
/// except that it will also convert '+' to space.
- (NSString*)countly_stringByUnescapingFromURLArgument;

@end

#define GTMNSMakeCollectable(cf) ((id)(cf))
#define GTMCFAutorelease(cf) ([GTMNSMakeCollectable(cf) autorelease])

@implementation NSString (Countly_Additions)

- (NSString*)countly_stringByEscapingForURLArgument {
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

- (NSString*)countly_stringByUnescapingFromURLArgument {
	NSMutableString *resultString = [NSMutableString stringWithString:self];
	[resultString replaceOccurrencesOfString:@"+"
								  withString:@" "
									 options:NSLiteralSearch
									   range:NSMakeRange(0, [resultString length])];
	return [resultString stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
}

@end

@interface DeviceInfo : NSObject

+ (NSString *)udid;
+ (NSString *)device;
+ (NSString *)osVersion;
+ (NSString *)carrier;
+ (NSString *)resolution;
+ (NSString *)locale;
+ (NSString *)appVersion;

+ (NSString *)metrics;

@end

@implementation DeviceInfo

+ (NSString *)udid {
	return [Countly_OpenUDID value];
}

+ (NSString *)device {
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

+ (NSString *)os
{
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
    return @"iOS";
#else
    return @"OS X";
#endif
}

+ (NSString *)osVersion {
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
	return UIDevice.currentDevice.systemVersion;
#else
    SInt32 majorVersion, minorVersion, bugFixVersion;
    Gestalt(gestaltSystemVersionMajor, &majorVersion);
    Gestalt(gestaltSystemVersionMinor, &minorVersion);
    Gestalt(gestaltSystemVersionBugFix, &bugFixVersion);
    if (bugFixVersion > 0) {
    	return [NSString stringWithFormat:@"%d.%d.%d", majorVersion, minorVersion, bugFixVersion];
    } else {
    	return [NSString stringWithFormat:@"%d.%d", majorVersion, minorVersion];
    }
#endif
}

+ (NSString *)carrier {
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
	if (!NSClassFromString(@"CTTelephonyNetworkInfo"))
		return nil;
	
	CTTelephonyNetworkInfo *netinfo = [CTTelephonyNetworkInfo.new autorelease];
	CTCarrier *carrier = netinfo.subscriberCellularProvider;
	return carrier.carrierName;
#endif
	return nil;
}

+ (NSString *)resolution {
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
	CGRect bounds = UIScreen.mainScreen.bounds;
	CGFloat scale = [UIScreen.mainScreen respondsToSelector:@selector(scale)] ? UIScreen.mainScreen.scale : 1.f;
	CGSize res = CGSizeMake(bounds.size.width * scale, bounds.size.height * scale);
	NSString *result = [NSString stringWithFormat:@"%gx%g", res.width, res.height];
    
	return result;
#else
    NSRect screenRect = NSScreen.mainScreen.frame;
    return [NSString stringWithFormat:@"%.1fx%.1f", screenRect.size.width, screenRect.size.height];
#endif
}

+ (NSString *)locale {
	return [NSLocale.currentLocale localeIdentifier];
}

+ (NSString *)appVersion {
    NSString *result = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (result.length == 0)
        result = [NSBundle.mainBundle objectForInfoDictionaryKey:(NSString*)kCFBundleVersionKey];
    
    return result;
}

+ (NSString *)metrics {
	NSMutableDictionary* metricsDictionary = NSMutableDictionary.dictionary;
	[metricsDictionary setObject:DeviceInfo.device forKey:@"_device"];
	[metricsDictionary setObject:@"iOS" forKey:@"_os"];
	[metricsDictionary setObject:DeviceInfo.osVersion forKey:@"_os_version"];
    
	NSString *carrier = DeviceInfo.carrier;
	if (carrier) {
		[metricsDictionary setObject:carrier forKey:@"_carrier"];
	}

	[metricsDictionary setObject:DeviceInfo.resolution forKey:@"_resolution"];
	[metricsDictionary setObject:DeviceInfo.locale forKey:@"_locale"];
	[metricsDictionary setObject:DeviceInfo.appVersion forKey:@"_app_version"];
	
	NSString* json = _countly_jsonFromObject(metricsDictionary);
    
	return [json countly_stringByEscapingForURLArgument];
}

@end

@interface CountlyEvent : NSObject

@property (nonatomic, copy) NSString *key;
@property (nonatomic, retain) NSDictionary *segmentation;
@property (nonatomic, assign) int count;
@property (nonatomic, assign) double sum;
@property (nonatomic, assign) NSTimeInterval timestamp;

@end

@implementation CountlyEvent

- (void)dealloc {
	self.key = nil;
	self.segmentation = nil;
    [super dealloc];
}

- (NSDictionary*)serializedData {
	NSMutableDictionary* eventData = NSMutableDictionary.dictionary;
	[eventData setObject:self.key forKey:@"key"];
	if (self.segmentation) {
		[eventData setObject:self.segmentation forKey:@"segmentation"];
	}
	[eventData setObject:@(self.count) forKey:@"count"];
	[eventData setObject:@(self.sum) forKey:@"sum"];
	[eventData setObject:@(self.timestamp) forKey:@"timestamp"];
	return eventData;
}
+ (CountlyEvent*)objectWithManagedObject:(NSManagedObject*)managedObject {
	CountlyEvent* event = [CountlyEvent.new autorelease];
	
	event.key = [managedObject valueForKey:@"key"];
	event.count = [[managedObject valueForKey:@"count"] doubleValue];
	event.sum = [[managedObject valueForKey:@"sum"] doubleValue];
	event.timestamp = [[managedObject valueForKey:@"timestamp"] doubleValue];
	event.segmentation = [managedObject valueForKey:@"segmentation"];
    return event;
}

@end

@interface EventQueue : NSObject

- (NSUInteger)count;
- (NSString *)events;
- (void)recordEvent:(NSString *)key count:(int)count;
- (void)recordEvent:(NSString *)key count:(int)count sum:(double)sum;
- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(int)count;
- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(int)count sum:(double)sum;

@end

@implementation EventQueue

- (void)dealloc {
    [super dealloc];
}

- (NSUInteger)count {
    @synchronized (self) {
        return CountlyDB.sharedInstance.eventCount;
    }
}

- (NSString *)events {
	NSMutableArray* result = NSMutableArray.array;

	@synchronized (self) {
		
		NSArray* events = [[CountlyDB.sharedInstance.events copy] autorelease];
		for (id managedEventObject in events) {
			CountlyEvent* event = [CountlyEvent objectWithManagedObject:managedEventObject];
            
			[result addObject:event.serializedData];
            
            [CountlyDB.sharedInstance removeFromQueue:managedEventObject];
        }
        
    }
    
	return [_countly_jsonFromObject(result) countly_stringByEscapingForURLArgument];
}
- (void)recordEvent:(NSString *)key count:(int)count {
    @synchronized (self) {
		NSArray* events = [[CountlyDB.sharedInstance.events copy] autorelease];
        for (NSManagedObject* managedObject in events) {
            CountlyEvent *event = [CountlyEvent objectWithManagedObject:managedObject];
            if (![event.key isEqualToString:key]) continue;
			
			event.count += count;
			event.timestamp = (event.timestamp + time(NULL)) / 2;
			
			[managedObject setValue:@(event.count) forKey:@"count"];
			[managedObject setValue:@(event.timestamp) forKey:@"timestamp"];
			
			[CountlyDB.sharedInstance saveContext];
			return;
        }
        
        CountlyEvent *event = [CountlyEvent.new autorelease];
        event.key = key;
        event.count = count;
        event.timestamp = time(NULL);

        [CountlyDB.sharedInstance createEvent:event.key count:event.count sum:event.sum segmentation:event.segmentation timestamp:event.timestamp];
    }
}
- (void)recordEvent:(NSString *)key count:(int)count sum:(double)sum {
    @synchronized (self) {
		NSArray* events = [[CountlyDB.sharedInstance.events copy] autorelease];
        for (NSManagedObject* managedObject in events) {
            CountlyEvent *event = [CountlyEvent objectWithManagedObject:managedObject];
            if (![event.key isEqualToString:key]) continue;

			event.count += count;
			event.sum += sum;
			event.timestamp = (event.timestamp + time(NULL)) / 2;
			
			[managedObject setValue:@(event.count) forKey:@"count"];
			[managedObject setValue:@(event.sum) forKey:@"sum"];
			[managedObject setValue:@(event.timestamp) forKey:@"timestamp"];
			
			[CountlyDB.sharedInstance saveContext];
			return;
        }
        
        CountlyEvent *event = [CountlyEvent.new autorelease];
        event.key = key;
        event.count = count;
        event.sum = sum;
        event.timestamp = time(NULL);
        
        [CountlyDB.sharedInstance createEvent:event.key count:event.count sum:event.sum segmentation:event.segmentation timestamp:event.timestamp];
    }
}
- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(int)count {
    @synchronized (self) {
        
		NSArray* events = [[CountlyDB.sharedInstance.events copy] autorelease];
        for (NSManagedObject* managedObject in events) {
            CountlyEvent *event = [CountlyEvent objectWithManagedObject:managedObject];
            if (![event.key isEqualToString:key] || ![event.segmentation isEqualToDictionary:segmentation]) continue;

			event.count += count;
			event.timestamp = (event.timestamp + time(NULL)) / 2; // STRANGE.. wrong.
			
			[managedObject setValue:@(event.count) forKey:@"count"];
			[managedObject setValue:@(event.timestamp) forKey:@"timestamp"];
			
			[CountlyDB.sharedInstance saveContext];
			return;
        }
        
        CountlyEvent *event = [CountlyEvent.new autorelease];
        event.key = key;
        event.segmentation = segmentation;
        event.count = count;
        event.timestamp = time(NULL);
        
        [CountlyDB.sharedInstance createEvent:event.key count:event.count sum:event.sum segmentation:event.segmentation timestamp:event.timestamp];
    }
}
- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(int)count sum:(double)sum {
    @synchronized (self) {
        
		NSArray* events = [[CountlyDB.sharedInstance.events copy] autorelease];
        for (NSManagedObject* managedObject in events) {
            CountlyEvent *event = [CountlyEvent objectWithManagedObject:managedObject];
            if (![event.key isEqualToString:key] || ![event.segmentation isEqualToDictionary:segmentation]) continue;
			
			event.count += count;
			event.sum += sum;
			event.timestamp = (event.timestamp + time(NULL)) / 2; // STRANGE.. wrong.
			
			[managedObject setValue:@(event.count) forKey:@"count"];
			[managedObject setValue:@(event.sum) forKey:@"sum"];
			[managedObject setValue:@(event.timestamp) forKey:@"timestamp"];
			
			[CountlyDB.sharedInstance saveContext];
			
			return;
        }
        
        CountlyEvent *event = [CountlyEvent.new autorelease];
        event.key = key;
        event.segmentation = segmentation;
        event.count = count;
        event.sum = sum;
        event.timestamp = time(NULL);
        
        [CountlyDB.sharedInstance createEvent:event.key count:event.count sum:event.sum segmentation:event.segmentation timestamp:event.timestamp];
    }
}

@end

@interface ConnectionQueue : NSObject
{
       int failCount;
}
+ (ConnectionQueue *)sharedInstance;

@property (nonatomic, copy) NSString *appKey;
@property (nonatomic, copy) NSString *appHost;
@property (nonatomic, retain) NSURLConnection *connection;
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
@property (nonatomic, assign) UIBackgroundTaskIdentifier bgTask;
#endif

@end

static ConnectionQueue *s_sharedConnectionQueue = nil;
@implementation ConnectionQueue : NSObject

+ (instancetype)sharedInstance {
	if (!s_sharedConnectionQueue) {
		static dispatch_once_t onceToken;
		dispatch_once(&onceToken, ^{
			if ( /*still*/ !s_sharedConnectionQueue) {
				s_sharedConnectionQueue = self.new;
			}
		});
	}
	
	return s_sharedConnectionQueue;
}

- (void)dealloc {
	if (self.connection) {
		[self.connection cancel];
		self.connection = nil;
	}
	if (self.bgTask != UIBackgroundTaskInvalid) {
		[self stopBackgroundTask];
	}
	
	self.appKey = nil;
	self.appHost = nil;
	[super dealloc];
}

- (void)tick {
    NSArray* dataQueue = [[CountlyDB.sharedInstance.queue copy] autorelease];
    
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
    if (_connection || _bgTask != UIBackgroundTaskInvalid || dataQueue.count == 0)
        return;
    
    UIApplication *app = [UIApplication sharedApplication];
    self.bgTask = [app beginBackgroundTaskWithExpirationHandler:^{
		[app endBackgroundTask:self.bgTask];
		self.bgTask = UIBackgroundTaskInvalid;
    }];
#else
    if (_connection != nil || dataQueue.count == 0)
        return;
#endif
    
    NSString *data = [[dataQueue objectAtIndex:0] valueForKey:@"post"];

    NSString *urlString = [NSString stringWithFormat:@"%@/i?%@", self.appHost, data];
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    self.connection = [NSURLConnection connectionWithRequest:request delegate:self];
    
}

- (void)beginSession {
	NSString *data = [NSString stringWithFormat:@"app_key=%@&device_id=%@&timestamp=%ld&sdk_version="COUNTLY_VERSION"&begin_session=1&metrics=%@",
					  self.appKey,
					  [DeviceInfo udid],
					  time(NULL),
					  [DeviceInfo metrics]];
    
    [CountlyDB.sharedInstance addToQueue:data];
    
	[self tick];
}

- (void)updateSessionWithDuration:(int)duration {
	NSString *data = [NSString stringWithFormat:@"app_key=%@&device_id=%@&timestamp=%ld&session_duration=%d",
					  self.appKey,
					  [DeviceInfo udid],
					  time(NULL),
					  duration];
    
    [CountlyDB.sharedInstance addToQueue:data];
    
	[self tick];
}

- (void)endSessionWithDuration:(int)duration {
	NSString *data = [NSString stringWithFormat:@"app_key=%@&device_id=%@&timestamp=%ld&end_session=1&session_duration=%d",
					  self.appKey,
					  [DeviceInfo udid],
					  time(NULL),
					  duration];
    
    [CountlyDB.sharedInstance addToQueue:data];
    
	[self tick];
}

- (void)recordEvents:(NSString *)events {
	NSString *data = [NSString stringWithFormat:@"app_key=%@&device_id=%@&timestamp=%ld&events=%@",
					  self.appKey,
					  [DeviceInfo udid],
					  time(NULL),
					  events];
    
    [CountlyDB.sharedInstance addToQueue:data];
    
	[self tick];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    
    NSArray* dataQueue = [[CountlyDB.sharedInstance.queue copy] autorelease];
    
	COUNTLY_LOG(@"ok -> %@", [dataQueue objectAtIndex:0]);
    
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
	if (dataQueue.count == 0)
		[self stopBackgroundTask];
#endif
    
    self.connection = nil;
    failCount = 0;
    
    [CountlyDB.sharedInstance removeFromQueue:[dataQueue objectAtIndex:0]];
    
    [self tick];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)err {
    NSArray* dataQueue = [[CountlyDB.sharedInstance.queue copy] autorelease];
#if COUNTLY_DEBUG
    COUNTLY_LOG(@"error -> %@: %@", [dataQueue objectAtIndex:0], err);
#endif
    failCount++;

    
    if (dataQueue.count == 0 || failCount > FAIL_LIMIT) {
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
		[self stopBackgroundTask];
#endif
		return;
	}
	
    self.connection = nil;
    [self performSelector:@selector(tick) withObject:nil afterDelay:TICK_DELAY_AFTER_FAIL];
}

#if COUNTLY_IGNORE_INVALID_CERTIFICATES
- (void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust])
        [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
    
    [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
}

- (BOOL)connection:(NSURLConnection *)connection canAuthenticateAgainstProtectionSpace:(NSURLProtectionSpace *)protectionSpace
{
    return [protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust];
}

- (void)connection:(NSURLConnection *)connection didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge
{
    [self connection:connection willSendRequestForAuthenticationChallenge:challenge];
}

#endif

- (void)stopBackgroundTask {
	UIApplication *app = [UIApplication sharedApplication];
    if (self.bgTask != UIBackgroundTaskInvalid) {
        [app endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }
}

@end

static Countly *s_sharedCountly = nil;
@implementation Countly

+ (instancetype)sharedInstance {
	if (!s_sharedCountly) {
		static dispatch_once_t onceToken;
		dispatch_once(&onceToken, ^{
			if ( /*still*/ !s_sharedCountly) {
				s_sharedCountly = self.new;
			}
		});
	}
	
	return s_sharedCountly;
}

- (void)dealloc {
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
    [NSNotificationCenter.defaultCenter removeObserver:self];
#endif
	
	if (timer) {
        [timer invalidate];
        timer = nil;
    }
    
    [eventQueue release];
	[super dealloc];
}
- (id)init {
	if (self = [super init]) {
        eventQueue = EventQueue.new;
		
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
		[NSNotificationCenter.defaultCenter addObserver:self
											   selector:@selector(didEnterBackgroundCallBack:)
												   name:UIApplicationDidEnterBackgroundNotification
												 object:nil];
		[NSNotificationCenter.defaultCenter addObserver:self
											   selector:@selector(willEnterForegroundCallBack:)
												   name:UIApplicationWillEnterForegroundNotification
												 object:nil];
		[NSNotificationCenter.defaultCenter addObserver:self
											   selector:@selector(willTerminateCallBack:)
												   name:UIApplicationWillTerminateNotification
												 object:nil];
#endif
	}
	return self;
}

- (void)start:(NSString *)appKey withHost:(NSString *)appHost {
	timer = [NSTimer scheduledTimerWithTimeInterval:self.updateInterval
											 target:self
										   selector:@selector(onTimer:)
										   userInfo:nil
											repeats:YES];
	lastTime = CFAbsoluteTimeGetCurrent();
	ConnectionQueue.sharedInstance.appKey = appKey;
	ConnectionQueue.sharedInstance.appHost = appHost;
	[ConnectionQueue.sharedInstance beginSession];
}

- (void)recordEvent:(NSString *)key count:(int)count {
    [eventQueue recordEvent:key count:count];
    
    if (eventQueue.count >= QUEUE_SEND_TRESHOLD)
        [ConnectionQueue.sharedInstance recordEvents:eventQueue.events];
}
- (void)recordEvent:(NSString *)key count:(int)count sum:(double)sum {
    [eventQueue recordEvent:key count:count sum:sum];
    
    if (eventQueue.count >= QUEUE_SEND_TRESHOLD)
        [ConnectionQueue.sharedInstance recordEvents:eventQueue.events];
}
- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(int)count {
    [eventQueue recordEvent:key segmentation:segmentation count:count];
    
    if (eventQueue.count >= QUEUE_SEND_TRESHOLD)
        [ConnectionQueue.sharedInstance recordEvents:eventQueue.events];
}
- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(int)count sum:(double)sum {
    [eventQueue recordEvent:key segmentation:segmentation count:count sum:sum];
    
    if (eventQueue.count >= QUEUE_SEND_TRESHOLD)
        [ConnectionQueue.sharedInstance recordEvents:eventQueue.events];
}

- (void)onTimer:(NSTimer *)timer {
	if (isSuspended == YES)
		return;
    
	double currTime = CFAbsoluteTimeGetCurrent();
	unsentSessionLength += currTime - lastTime;
	lastTime = currTime;
    
	int duration = unsentSessionLength;
	[ConnectionQueue.sharedInstance updateSessionWithDuration:duration];
	unsentSessionLength -= duration;
    
    if (eventQueue.count > 0)
        [ConnectionQueue.sharedInstance recordEvents:eventQueue.events];
}

- (void)flushQueue {
    if (eventQueue.count > 0)
        [ConnectionQueue.sharedInstance recordEvents:eventQueue.events];
}

- (void)suspend {
	isSuspended = YES;
    
    if (eventQueue.count > 0)
        [ConnectionQueue.sharedInstance recordEvents:eventQueue.events];
    
	double currTime = CFAbsoluteTimeGetCurrent();
	unsentSessionLength += currTime - lastTime;
    
	int duration = unsentSessionLength;
	[ConnectionQueue.sharedInstance endSessionWithDuration:duration];
	unsentSessionLength -= duration;
}
- (void)resume {
	lastTime = CFAbsoluteTimeGetCurrent();
    
	[ConnectionQueue.sharedInstance beginSession];
    
	isSuspended = NO;
}
- (void)exit {

}

- (void)didEnterBackgroundCallBack:(NSNotification *)notification {
	COUNTLY_LOG(@"Countly didEnterBackgroundCallBack");
	[self suspend];
}
- (void)willEnterForegroundCallBack:(NSNotification *)notification {
	COUNTLY_LOG(@"Countly willEnterForegroundCallBack");
	[self resume];
}
- (void)willTerminateCallBack:(NSNotification *)notification {
	COUNTLY_LOG(@"Countly willTerminateCallBack");
    [[CountlyDB sharedInstance] saveContext];
	[self exit];
}

@end

NSString* _countly_jsonFromObject(id object) {
	NSError *err = nil;
	
	NSData *data = [NSJSONSerialization dataWithJSONObject:object
												   options:0
													 error:&err];
	
	if (err)
		NSLog(@"%@", [err description]);
	
	return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].autorelease;
}
