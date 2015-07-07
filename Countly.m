// Countly.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#pragma mark - Directives

#ifndef COUNTLY_DEBUG
#define COUNTLY_DEBUG 0
#endif

#ifndef COUNTLY_IGNORE_INVALID_CERTIFICATES
#define COUNTLY_IGNORE_INVALID_CERTIFICATES 0
#endif

#ifndef COUNTLY_PREFER_IDFA
#define COUNTLY_PREFER_IDFA 0
#endif

#if COUNTLY_DEBUG
#   define COUNTLY_LOG(fmt, ...) NSLog(fmt, ##__VA_ARGS__)
#else
#   define COUNTLY_LOG(...)
#endif

#define COUNTLY_SDK_VERSION "15.06.01"

#ifndef COUNTLY_TARGET_WATCHKIT
#define COUNTLY_DEFAULT_UPDATE_INTERVAL 60.0
#define COUNTLY_EVENT_SEND_THRESHOLD 10
#else
#define COUNTLY_DEFAULT_UPDATE_INTERVAL 10.0
#define COUNTLY_EVENT_SEND_THRESHOLD 3
#import <WatchKit/WatchKit.h>
#endif

#import "Countly.h"
#import "Countly_OpenUDID.h"
#import "CountlyDB.h"
#import <objc/runtime.h>

#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
#import <UIKit/UIKit.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <CoreTelephony/CTCarrier.h>
#if COUNTLY_PREFER_IDFA
#import <AdSupport/ASIdentifierManager.h>
#endif
#endif

#include <sys/types.h>
#include <sys/sysctl.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#include <libkern/OSAtomic.h>
#include <execinfo.h>

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
	
	return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
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
	return (NSString*)CFBridgingRelease(escaped);
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

@interface NSMutableData (AppendStringUTF8)
-(void)appendStringUTF8:(NSString*)string;
@end

@implementation NSMutableData (AppendStringUTF8)
-(void)appendStringUTF8:(NSString*)string
{
    [self appendData:[string dataUsingEncoding:NSUTF8StringEncoding]];
}
@end

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

+ (NSString *)bundleId;

@end

@implementation CountlyDeviceInfo

+ (NSString *)udid
{
#if COUNTLY_PREFER_IDFA && (TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR || COUNTLY_TARGET_WATCHKIT)
    return ASIdentifierManager.sharedManager.advertisingIdentifier.UUIDString;
#else
	return [Countly_OpenUDID value];
#endif
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
    NSString *modelString = @(model);
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
		CTTelephonyNetworkInfo *netinfo = [CTTelephonyNetworkInfo new];
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
	metricsDictionary[@"_device"] = CountlyDeviceInfo.device;
	metricsDictionary[@"_os"] = CountlyDeviceInfo.osName;
	metricsDictionary[@"_os_version"] = CountlyDeviceInfo.osVersion;
    
	NSString *carrier = CountlyDeviceInfo.carrier;
	if (carrier)
        metricsDictionary[@"_carrier"] = carrier;

	metricsDictionary[@"_resolution"] = CountlyDeviceInfo.resolution;
	metricsDictionary[@"_locale"] = CountlyDeviceInfo.locale;
	metricsDictionary[@"_app_version"] = CountlyDeviceInfo.appVersion;
	
	return CountlyURLEscapedString(CountlyJSONFromObject(metricsDictionary));
}

+ (NSString *)bundleId
{
    return [[NSBundle mainBundle] bundleIdentifier];
}

@end


#pragma mark - CountlyUserDetails
@interface CountlyUserDetails : NSObject

@property(nonatomic,strong) NSString* name;
@property(nonatomic,strong) NSString* username;
@property(nonatomic,strong) NSString* email;
@property(nonatomic,strong) NSString* organization;
@property(nonatomic,strong) NSString* phone;
@property(nonatomic,strong) NSString* gender;
@property(nonatomic,strong) NSString* picture;
@property(nonatomic,strong) NSString* picturePath;
@property(nonatomic,readwrite) NSInteger birthYear;
@property(nonatomic,strong) NSDictionary* custom;

+(CountlyUserDetails*)sharedUserDetails;
-(void)deserialize:(NSDictionary*)userDictionary;
-(NSString*)serialize;

@end

@implementation CountlyUserDetails

NSString* const kCLYUserName = @"name";
NSString* const kCLYUserUsername = @"username";
NSString* const kCLYUserEmail = @"email";
NSString* const kCLYUserOrganization = @"organization";
NSString* const kCLYUserPhone = @"phone";
NSString* const kCLYUserGender = @"gender";
NSString* const kCLYUserPicture = @"picture";
NSString* const kCLYUserPicturePath = @"picturePath";
NSString* const kCLYUserBirthYear = @"byear";
NSString* const kCLYUserCustom = @"custom";

+(CountlyUserDetails*)sharedUserDetails
{
    static CountlyUserDetails *s_CountlyUserDetails = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{s_CountlyUserDetails = CountlyUserDetails.new;});
    return s_CountlyUserDetails;
}

-(void)deserialize:(NSDictionary*)userDictionary
{
    if(userDictionary[kCLYUserName])
        self.name = userDictionary[kCLYUserName];
    if(userDictionary[kCLYUserUsername])
        self.username = userDictionary[kCLYUserUsername];
    if(userDictionary[kCLYUserEmail])
        self.email = userDictionary[kCLYUserEmail];
    if(userDictionary[kCLYUserOrganization])
        self.organization = userDictionary[kCLYUserOrganization];
    if(userDictionary[kCLYUserPhone])
        self.phone = userDictionary[kCLYUserPhone];
    if(userDictionary[kCLYUserGender])
        self.gender = userDictionary[kCLYUserGender];
    if(userDictionary[kCLYUserPicture])
        self.picture = userDictionary[kCLYUserPicture];
    if(userDictionary[kCLYUserPicturePath])
        self.picturePath = userDictionary[kCLYUserPicturePath];
    if(userDictionary[kCLYUserBirthYear])
        self.birthYear = [userDictionary[kCLYUserBirthYear] integerValue];
    if(userDictionary[kCLYUserCustom])
        self.custom = userDictionary[kCLYUserCustom];
}

- (NSString *)serialize
{
    NSMutableDictionary* userDictionary = [NSMutableDictionary dictionary];
    if(self.name)
        userDictionary[kCLYUserName] = self.name;
    if(self.username)
        userDictionary[kCLYUserUsername] = self.username;
    if(self.email)
        userDictionary[kCLYUserEmail] = self.email;
    if(self.organization)
        userDictionary[kCLYUserOrganization] = self.organization;
    if(self.phone)
        userDictionary[kCLYUserPhone] = self.phone;
    if(self.gender)
        userDictionary[kCLYUserGender] = self.gender;
    if(self.picture)
        userDictionary[kCLYUserPicture] = self.picture;
    if(self.picturePath)
        userDictionary[kCLYUserPicturePath] = self.picturePath;
    if(self.birthYear!=0)
        userDictionary[kCLYUserBirthYear] = @(self.birthYear);
    if(self.custom)
        userDictionary[kCLYUserCustom] = self.custom;
    
    return CountlyURLEscapedString(CountlyJSONFromObject(userDictionary));
}

-(NSString*)extractPicturePathFromURLString:(NSString*)URLString
{
    NSString* unescaped = CountlyURLUnescapedString(URLString);
    NSRange rPicturePathKey = [unescaped rangeOfString:kCLYUserPicturePath];
    if (rPicturePathKey.location == NSNotFound)
        return nil;

    NSString* picturePath = nil;

    @try
    {
        NSRange rSearchForEnding = (NSRange){0,unescaped.length};
        rSearchForEnding.location = rPicturePathKey.location+rPicturePathKey.length+3;
        rSearchForEnding.length = rSearchForEnding.length - rSearchForEnding.location;
        NSRange rEnding = [unescaped rangeOfString:@"\",\"" options:0 range:rSearchForEnding];
        picturePath = [unescaped substringWithRange:(NSRange){rSearchForEnding.location,rEnding.location-rSearchForEnding.location}];
        picturePath = [picturePath stringByReplacingOccurrencesOfString:@"\\/" withString:@"/"];
    
    }
    @catch (NSException *exception)
    {
        COUNTLY_LOG(@"Cannot extract picture path!");
        picturePath = @"";
    }

    COUNTLY_LOG(@"Extracted picturePath: %@", picturePath);
    return picturePath;
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
}

+ (CountlyEvent*)objectWithManagedObject:(NSManagedObject*)managedObject
{
	CountlyEvent* event = [CountlyEvent new];
	
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
	eventData[@"key"] = self.key;
	if (self.segmentation)
    {
		eventData[@"segmentation"] = self.segmentation;
	}
	eventData[@"count"] = @(self.count);
	eventData[@"sum"] = @(self.sum);
	eventData[@"timestamp"] = @(self.timestamp);
	return eventData;
}

@end


#pragma mark - CountlyEventQueue

@interface CountlyEventQueue : NSObject

@end


@implementation CountlyEventQueue

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
		NSArray* events = [[[CountlyDB sharedInstance] getEvents] copy];
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
        NSArray* events = [[[CountlyDB sharedInstance] getEvents] copy];
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
        
        CountlyEvent *event = [CountlyEvent new];
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
        NSArray* events = [[[CountlyDB sharedInstance] getEvents] copy];
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
        
        CountlyEvent *event = [CountlyEvent new];
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
        NSArray* events = [[[CountlyDB sharedInstance] getEvents] copy];
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
        
        CountlyEvent *event = [CountlyEvent new];
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
        NSArray* events = [[[CountlyDB sharedInstance] getEvents] copy];
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
        
        CountlyEvent *event = [CountlyEvent new];
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
@property (nonatomic) BOOL startedWithTest;
@property (nonatomic, strong) NSString *locationString;
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
    NSArray* dataQueue = [[[CountlyDB sharedInstance] getQueue] copy];
    
    if (self.connection != nil || [dataQueue count] == 0)
        return;

#if (TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR) && (!COUNTLY_TARGET_WATCHKIT)
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
    NSMutableURLRequest * request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];

    if([data rangeOfString:@"&crash="].location != NSNotFound)
    {
        urlString = [NSString stringWithFormat:@"%@/i", self.appHost];
        request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
        request.HTTPMethod = @"POST";
        request.HTTPBody = [data dataUsingEncoding:NSUTF8StringEncoding];
    }
    
#if (TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR) && (!COUNTLY_TARGET_WATCHKIT)
    NSString* picturePath = [CountlyUserDetails.sharedUserDetails extractPicturePathFromURLString:urlString];
    if(picturePath && ![picturePath isEqualToString:@""])
    {
        COUNTLY_LOG(@"picturePath: %@", picturePath);

        NSArray* allowedFileTypes = @[@"gif",@"png",@"jpg",@"jpeg"];
        NSString* fileExt = picturePath.pathExtension.lowercaseString;
        NSInteger fileExtIndex = [allowedFileTypes indexOfObject:fileExt];
        
        if(fileExtIndex != NSNotFound)
        {
            NSData* imageData = [NSData dataWithContentsOfURL:[NSURL URLWithString:picturePath]];
            if (fileExtIndex == 1) imageData = UIImagePNGRepresentation([UIImage imageWithData:imageData]); //NOTE: for png upload fix. (png file data read directly from disk fails on upload)
            if (fileExtIndex == 2) fileExtIndex = 3; //NOTE: for mime type jpg -> jpeg
            
            if (imageData)
            {
                COUNTLY_LOG(@"local image retrieved from picturePath");
                
                NSString *boundary = @"c1c673d52fea01a50318d915b6966d5e";
                
                [request setHTTPMethod:@"POST"];
                NSString *contentType = [@"multipart/form-data; boundary=" stringByAppendingString:boundary];
                [request addValue:contentType forHTTPHeaderField: @"Content-Type"];
                
                NSMutableData *body = NSMutableData.data;
                [body appendStringUTF8:[NSString stringWithFormat:@"--%@\r\n", boundary]];
                [body appendStringUTF8:[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"pictureFile\"; filename=\"%@\"\r\n",picturePath.lastPathComponent]];
                [body appendStringUTF8:[NSString stringWithFormat:@"Content-Type: image/%@\r\n\r\n", allowedFileTypes[fileExtIndex]]];
                [body appendData:imageData];
                [body appendStringUTF8:[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary]];
                [request setHTTPBody:body];
            }
        }
    }
#endif

    self.connection = [NSURLConnection connectionWithRequest:request delegate:self];

    COUNTLY_LOG(@"Request Started \n %@", urlString);
}

- (void)beginSession
{
	NSString *data = [NSString stringWithFormat:@"app_key=%@&device_id=%@&timestamp=%ld&sdk_version="COUNTLY_SDK_VERSION"&begin_session=1&metrics=%@",
					  self.appKey,
					  [CountlyDeviceInfo udid],
					  time(NULL),
					  [CountlyDeviceInfo metrics]];
    
    [[CountlyDB sharedInstance] addToQueue:data];
    
	[self tick];
}

- (void)tokenSession:(NSString *)token
{
    // Test modes: 0 = production mode, 1 = development build, 2 = Ad Hoc build
    int testMode;
#ifndef __OPTIMIZE__
    testMode = 1;
#else
    testMode = self.startedWithTest ? 2 : 0;
#endif
    
    COUNTLY_LOG(@"Sending APN token in mode %d", testMode);
    
    NSString *data = [NSString stringWithFormat:@"app_key=%@&device_id=%@&timestamp=%ld&sdk_version="COUNTLY_SDK_VERSION"&token_session=1&ios_token=%@&test_mode=%d",
                      self.appKey,
                      [CountlyDeviceInfo udid],
                      time(NULL),
                      [token length] ? token : @"",
                      testMode];

    // Not right now to prevent race with begin_session=1 when adding new user
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[CountlyDB sharedInstance] addToQueue:data];
        [self tick];
    });
}

- (void)updateSessionWithDuration:(int)duration
{
	NSString *data = [NSString stringWithFormat:@"app_key=%@&device_id=%@&timestamp=%ld&session_duration=%d",
					  self.appKey,
					  [CountlyDeviceInfo udid],
					  time(NULL),
					  duration];
    
    if (self.locationString)
    {
        data = [data stringByAppendingFormat:@"&location=%@",self.locationString];
        self.locationString = nil;
    }
    
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

- (void)sendUserDetails
{
    NSString *data = [NSString stringWithFormat:@"app_key=%@&device_id=%@&timestamp=%ld&sdk_version="COUNTLY_SDK_VERSION"&user_details=%@",
                      self.appKey,
                      [CountlyDeviceInfo udid],
                      time(NULL),
                      [[CountlyUserDetails sharedUserDetails] serialize]];
    
    [[CountlyDB sharedInstance] addToQueue:data];
    
    [self tick];
}

- (void)storeCrashReportToTryLater:(NSString *)report
{
    NSString *data = [NSString stringWithFormat:@"app_key=%@&device_id=%@&timestamp=%ld&sdk_version="COUNTLY_SDK_VERSION"&crash=%@",
                      self.appKey,
                      [CountlyDeviceInfo udid],
                      time(NULL),
                      report];
    
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
    
#if (TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR) && (!COUNTLY_TARGET_WATCHKIT)
    UIApplication *app = [UIApplication sharedApplication];
    if (self.bgTask != UIBackgroundTaskInvalid)
    {
        [app endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }
#endif

    self.connection = nil;
    
    [[CountlyDB sharedInstance] removeFromQueue:dataQueue[0]];
    
    [self tick];
}


- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)err
{
    #if COUNTLY_DEBUG
        NSArray* dataQueue = [[[CountlyDB sharedInstance] getQueue] copy];
        COUNTLY_LOG(@"Request Failed \n %@: %@", [dataQueue[0] description], [err description]);
    #endif
    
#if (TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR) && (!COUNTLY_TARGET_WATCHKIT)
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
}

@end


#pragma mark - Countly Core

@interface Countly ()

@property (nonatomic, strong) NSMutableDictionary *messageInfos;
@property (nonatomic, strong) NSDictionary* crashCustom;

@end

@implementation Countly

+ (instancetype)sharedInstance
{
    static Countly *s_sharedCountly = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedCountly = self.new;});
	return s_sharedCountly;
}

- (instancetype)init
{
	if (self = [super init])
	{
		timer = nil;
        startTime = time(NULL);
		isSuspended = NO;
		unsentSessionLength = 0;
        eventQueue = [[CountlyEventQueue alloc] init];
        self.crashCustom = nil;
        
        self.messageInfos = [NSMutableDictionary new];

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

#if (TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR) && (!COUNTLY_TARGET_WATCHKIT)
- (void)startWithMessagingUsing:(NSString *)appKey withHost:(NSString *)appHost andOptions:(NSDictionary *)options
{
    [self start:appKey withHost:appHost];
    
    NSDictionary *notification = [options objectForKey:UIApplicationLaunchOptionsRemoteNotificationKey];
    if (notification) {
        COUNTLY_LOG(@"Got notification on app launch: %@", notification);
//        [self handleRemoteNotification:notification displayingMessage:NO];
    }
}

- (void)startWithTestMessagingUsing:(NSString *)appKey withHost:(NSString *)appHost andOptions:(NSDictionary *)options
{
    [self start:appKey withHost:appHost];
    [[CountlyConnectionQueue sharedInstance] setStartedWithTest:YES];
    
    NSDictionary *notification = [options objectForKey:UIApplicationLaunchOptionsRemoteNotificationKey];
    if (notification) {
        COUNTLY_LOG(@"Got notification on app launch: %@", notification);
        [self handleRemoteNotification:notification displayingMessage:NO];
    }
    
    [self withAppStoreId:^(NSString *appId) {
        NSLog(@"ID: %@", appId);
    }];
}

- (NSMutableSet *) countlyNotificationCategories {
    return [self countlyNotificationCategoriesWithActionTitles:@[@"Cancel", @"Open", @"Update", @"Review"]];
}

- (NSMutableSet *) countlyNotificationCategoriesWithActionTitles:(NSArray *)actions {
    UIMutableUserNotificationCategory *url = [UIMutableUserNotificationCategory new],
                                      *upd = [UIMutableUserNotificationCategory new],
                                      *rev = [UIMutableUserNotificationCategory new];
    
    url.identifier = @"[CLY]_url";
    upd.identifier = @"[CLY]_update";
    rev.identifier = @"[CLY]_review";

    UIMutableUserNotificationAction *cancel = [UIMutableUserNotificationAction new],
                                      *open = [UIMutableUserNotificationAction new],
                                    *update = [UIMutableUserNotificationAction new],
                                    *review = [UIMutableUserNotificationAction new];
    
    cancel.identifier = @"[CLY]_cancel";
    open.identifier   = @"[CLY]_open";
    update.identifier = @"[CLY]_update";
    review.identifier = @"[CLY]_review";
    
    cancel.title = actions[0];
    open.title   = actions[1];
    update.title = actions[2];
    review.title = actions[3];

    cancel.activationMode = UIUserNotificationActivationModeBackground;
    open.activationMode   = UIUserNotificationActivationModeForeground;
    update.activationMode = UIUserNotificationActivationModeForeground;
    review.activationMode = UIUserNotificationActivationModeForeground;
    
    cancel.destructive = NO;
    open.destructive   = NO;
    update.destructive = NO;
    review.destructive = NO;
    
    
    [url setActions:@[cancel, open] forContext:UIUserNotificationActionContextMinimal];
    [url setActions:@[cancel, open] forContext:UIUserNotificationActionContextDefault];
    
    [upd setActions:@[cancel, update] forContext:UIUserNotificationActionContextMinimal];
    [upd setActions:@[cancel, update] forContext:UIUserNotificationActionContextDefault];
    
    [rev setActions:@[cancel, review] forContext:UIUserNotificationActionContextMinimal];
    [rev setActions:@[cancel, review] forContext:UIUserNotificationActionContextDefault];
    
    NSMutableSet *set = [NSMutableSet setWithObjects:url, upd, rev, nil];
    
    return set;
}
#endif

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

- (void)recordUserDetails:(NSDictionary *)userDetails
{
    NSLog(@"%s",__FUNCTION__);
    [CountlyUserDetails.sharedUserDetails deserialize:userDetails];
    [CountlyConnectionQueue.sharedInstance sendUserDetails];
}

- (void)setLocation:(double)latitude longitude:(double)longitude
{
    CountlyConnectionQueue.sharedInstance.locationString = [NSString stringWithFormat:@"%f,%f", latitude, longitude];
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


#pragma mark - Countly Messaging
#if (TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR) && (!COUNTLY_TARGET_WATCHKIT)

#define kPushToMessage      1
#define kPushToOpenLink     2
#define kPushToUpdate       3
#define kPushToReview       4
#define kPushEventKeyOpen   @"[CLY]_push_open"
#define kPushEventKeyAction @"[CLY]_push_action"
#define kAppIdPropertyKey   @"[CLY]_app_id"
#define kCountlyAppId       @"695261996"

- (BOOL) handleRemoteNotification:(NSDictionary *)info withButtonTitles:(NSArray *)titles {
    return [self handleRemoteNotification:info displayingMessage:YES withButtonTitles:titles];
}

- (BOOL) handleRemoteNotification:(NSDictionary *)info {
    return [self handleRemoteNotification:info displayingMessage:YES];
}

- (BOOL) handleRemoteNotification:(NSDictionary *)info displayingMessage:(BOOL)displayMessage {
    return [self handleRemoteNotification:info displayingMessage:displayMessage
                         withButtonTitles:@[@"Cancel", @"Open", @"Update", @"Review"]];
}

- (BOOL) handleRemoteNotification:(NSDictionary *)info displayingMessage:(BOOL)displayMessage withButtonTitles:(NSArray *)titles {
    COUNTLY_LOG(@"Handling remote notification (display? %d): %@", displayMessage, info);
    
    NSDictionary *aps = info[@"aps"];
    NSDictionary *countly = info[@"c"];
    
    if (countly[@"i"]) {
        COUNTLY_LOG(@"Message id: %@", countly[@"i"]);

        [self recordPushOpenForCountlyDictionary:countly];
        NSString *appName = [[[NSBundle mainBundle] infoDictionary] objectForKey:(NSString*)kCFBundleNameKey];
        NSString *message = [aps objectForKey:@"alert"];
        
        int type = 0;
        NSString *action = nil;
        
        if ([aps objectForKey:@"content-available"]) {
            return NO;
        } else if (countly[@"l"]) {
            type = kPushToOpenLink;
            action = titles[1];
        } else if (countly[@"r"] != nil) {
            type = kPushToReview;
            action = titles[3];
        } else if (countly[@"u"] != nil) {
            type = kPushToUpdate;
            action = titles[2];
        } else if (displayMessage) {
            type = kPushToMessage;
            action = nil;
        }
        
        if (type && [message length]) {
            UIAlertView *alert;
            if (action) {
                alert = [[UIAlertView alloc] initWithTitle:appName message:message delegate:self
                                         cancelButtonTitle:titles[0] otherButtonTitles:action, nil];
            } else {
                alert = [[UIAlertView alloc] initWithTitle:appName message:message delegate:self
                                         cancelButtonTitle:titles[0] otherButtonTitles:nil];
            }
            alert.tag = type;
            
            _messageInfos[alert.description] = info;

            [alert show];
            return YES;
        }
    }
    
    return NO;
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    NSDictionary *info = [_messageInfos[alertView.description] copy];
    [_messageInfos removeObjectForKey:alertView.description];

    if (alertView.tag == kPushToMessage) {
        // do nothing
    } else if (buttonIndex != alertView.cancelButtonIndex) {
        if (alertView.tag == kPushToOpenLink) {
            [self recordPushActionForCountlyDictionary:info[@"c"]];
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:info[@"c"][@"l"]]];
        } else if (alertView.tag == kPushToUpdate) {
            if ([info[@"c"][@"u"] length]) {
                [self openUpdate:info[@"c"][@"u"] forInfo:info];
            } else {
                [self withAppStoreId:^(NSString *appStoreId) {
                    [self openUpdate:appStoreId forInfo:info];
                }];
            }
        } else if (alertView.tag == kPushToReview) {
            if ([info[@"c"][@"r"] length]) {
                [self openReview:info[@"c"][@"r"] forInfo:info];
            } else {
                [self withAppStoreId:^(NSString *appStoreId) {
                    [self openReview:appStoreId forInfo:info];
                }];
            }
        }
    }
}

- (void) withAppStoreId:(void (^)(NSString *))block{
    NSString *appStoreId = [[NSUserDefaults standardUserDefaults] stringForKey:kAppIdPropertyKey];
    if (appStoreId) {
        block(appStoreId);
    } else {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            NSString *appStoreId = nil;
            NSString *bundle = [CountlyDeviceInfo bundleId];
            NSString *appStoreCountry = [(NSLocale *)[NSLocale currentLocale] objectForKey:NSLocaleCountryCode];
            if ([appStoreCountry isEqualToString:@"150"]) {
                appStoreCountry = @"eu";
            } else if ([[appStoreCountry stringByReplacingOccurrencesOfString:@"[A-Za-z]{2}" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, 2)] length]) {
                appStoreCountry = @"us";
            }
            
            NSString *iTunesServiceURL = [NSString stringWithFormat:@"http://itunes.apple.com/%@/lookup", appStoreCountry];
            iTunesServiceURL = [iTunesServiceURL stringByAppendingFormat:@"?bundleId=%@", bundle];
            
            NSError *error = nil;
            NSURLResponse *response = nil;
            NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:iTunesServiceURL] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:10];
            NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
            NSInteger statusCode = ((NSHTTPURLResponse *)response).statusCode;
            if (data && statusCode == 200) {
                
                id json = [[NSJSONSerialization JSONObjectWithData:data options:(NSJSONReadingOptions)0 error:&error][@"results"] lastObject];
                
                if (!error && [json isKindOfClass:[NSDictionary class]]) {
                    NSString *bundleID = json[@"bundleId"];
                    if (bundleID && [bundleID isEqualToString:bundle]) {
                        appStoreId = [json[@"trackId"] stringValue];
                    }
                }
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSUserDefaults standardUserDefaults] setObject:appStoreId forKey:kAppIdPropertyKey];
                [[NSUserDefaults standardUserDefaults] synchronize];
                block(appStoreId);
            });
        });
    }

}

- (void) openUpdate:(NSString *)appId forInfo:(NSDictionary *)info {
    if (!appId) appId = kCountlyAppId;

    NSString *urlFormat = nil;
#if TARGET_OS_IPHONE
    urlFormat = @"itms-apps://itunes.apple.com/app/id%@";
#else
    urlFormat = @"macappstore://itunes.apple.com/app/id%@";
#endif

    [self recordPushActionForCountlyDictionary:info[@"c"]];
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:urlFormat, appId]];
    [[UIApplication sharedApplication] openURL:url];
}

- (void) openReview:(NSString *)appId forInfo:(NSDictionary *)info{
    if (!appId) appId = kCountlyAppId;
    
    NSString *urlFormat = nil;
#if TARGET_OS_IPHONE
    float iOSVersion = [[UIDevice currentDevice].systemVersion floatValue];
    if (iOSVersion >= 7.0f && iOSVersion < 7.1f) {
        urlFormat = @"itms-apps://itunes.apple.com/app/id%@";
    } else {
        urlFormat = @"itms-apps://itunes.apple.com/WebObjects/MZStore.woa/wa/viewContentsUserReviews?type=Purple+Software&id=%@";
    }
#else
    urlFormat = @"macappstore://itunes.apple.com/app/id%@";
#endif

    [self recordPushActionForCountlyDictionary:info[@"c"]];
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:urlFormat, appId]];
    [[UIApplication sharedApplication] openURL:url];
}

- (void)recordPushOpenForCountlyDictionary:(NSDictionary *)c {
    [self recordEvent:kPushEventKeyOpen segmentation:@{@"i": c[@"i"]} count:1];
}

- (void)recordPushActionForCountlyDictionary:(NSDictionary *)c {
    [self recordEvent:kPushEventKeyAction segmentation:@{@"i": c[@"i"]} count:1];
}

- (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    const unsigned *tokenBytes = [deviceToken bytes];
    NSString *token = [NSString stringWithFormat:@"%08x%08x%08x%08x%08x%08x%08x%08x",
                       ntohl(tokenBytes[0]), ntohl(tokenBytes[1]), ntohl(tokenBytes[2]),
                       ntohl(tokenBytes[3]), ntohl(tokenBytes[4]), ntohl(tokenBytes[5]),
                       ntohl(tokenBytes[6]), ntohl(tokenBytes[7])];
    [[CountlyConnectionQueue sharedInstance] tokenSession:token];
}

- (void)didFailToRegisterForRemoteNotifications {
    [[CountlyConnectionQueue sharedInstance] tokenSession:nil];
}
#endif


#pragma mark - Countly CrashReporting
#if (TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR) && (!COUNTLY_TARGET_WATCHKIT)

#define kCountlyCrashUserInfoKey @"[CLY]_stack_trace"

- (void)startCrashReporting
{
    NSSetUncaughtExceptionHandler(&CountlyUncaughtExceptionHandler);
    signal(SIGABRT, CountlySignalHandler);
	signal(SIGILL, CountlySignalHandler);
	signal(SIGSEGV, CountlySignalHandler);
	signal(SIGFPE, CountlySignalHandler);
	signal(SIGBUS, CountlySignalHandler);
	signal(SIGPIPE, CountlySignalHandler);
}

- (void)startCrashReportingWithSegments:(NSDictionary *)segments
{
    self.crashCustom = segments;
    [self startCrashReporting];
}

- (void)recordHandledException:(NSException *)exception
{
    CountlyExceptionHandler(exception, true);
}

- (void)crashTest
{
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wundeclared-selector"
    [self performSelector:@selector(thisIsTheUnrecognizedSelectorCausingTheCrash)];
    #pragma clang diagnostic pop
}

- (void)crashTest2
{
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wunused-variable"
    NSArray* anArray = @[@"one",@"two",@"three"];
    NSString* myCrashingString = anArray[5];
    #pragma clang diagnostic pop
}

- (void)crashTest3
{
    int *nullPointer = NULL;
    *nullPointer = 2015;
}

- (void)crashTest4
{
    CGRect aRect = (CGRect){0.0/0.0, 0.0, 100.0, 100.0};
    UIView *crashView = UIView.new;
    crashView.frame = aRect;
}

void CountlyUncaughtExceptionHandler(NSException *exception)
{
    CountlyExceptionHandler(exception, false);
}

void CountlyExceptionHandler(NSException *exception, bool nonfatal)
{
    NSMutableDictionary* crashReport = NSMutableDictionary.dictionary;
    
    crashReport[@"_os"] = CountlyDeviceInfo.osName;
    crashReport[@"_os_version"] = CountlyDeviceInfo.osVersion;
    crashReport[@"_device"] = CountlyDeviceInfo.device;
    crashReport[@"_resolution"] = CountlyDeviceInfo.resolution;
    crashReport[@"_app_version"] = CountlyDeviceInfo.appVersion;
    crashReport[@"_name"] = exception.debugDescription;
    crashReport[@"_nonfatal"] = @(nonfatal);
    

    crashReport[@"_ram_current"] = @((Countly.sharedInstance.totalRAM-Countly.sharedInstance.freeRAM)/1048576);
    crashReport[@"_ram_total"] = @(Countly.sharedInstance.totalRAM/1048576);
    crashReport[@"_disk_current"] = @((Countly.sharedInstance.totalDisk-Countly.sharedInstance.freeDisk)/1048576);
    crashReport[@"_disk_total"] = @(Countly.sharedInstance.totalDisk/1048576);
    
    
    crashReport[@"_bat"] = @(Countly.sharedInstance.batteryLevel);
    crashReport[@"_orientation"] = Countly.sharedInstance.orientation;
    crashReport[@"_online"] = @((Countly.sharedInstance.connectionType)? 1 : 0 );
    crashReport[@"_opengl"] = @(Countly.sharedInstance.OpenGLESversion);
    crashReport[@"_root"] = @(Countly.sharedInstance.isJailbroken);
    crashReport[@"_background"] = @(Countly.sharedInstance.isInBackground);
    crashReport[@"_run"] = @(Countly.sharedInstance.timeSinceLaunch);
    
    if(Countly.sharedInstance.crashCustom)
        crashReport[@"_custom"] = Countly.sharedInstance.crashCustom;

    if(CountlyCustomCrashLogs)
        crashReport[@"_logs"] = [CountlyCustomCrashLogs componentsJoinedByString:@"\n"];

    NSArray* stackArray = exception.userInfo[kCountlyCrashUserInfoKey];
    if(!stackArray) stackArray = exception.callStackSymbols;

    NSMutableString* stackString = NSMutableString.string;
    for (NSString* line in stackArray)
    {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\s+\\s" options:0 error:nil];
        NSString *cleanLine = [regex stringByReplacingMatchesInString:line options:0 range:(NSRange){0,line.length} withTemplate:@"  "];
        [stackString appendString:cleanLine];
        [stackString appendString:@"\n"];
    }
    
    crashReport[@"_error"] = stackString;
   
    NSString *urlString = [NSString stringWithFormat:@"%@/i", CountlyConnectionQueue.sharedInstance.appHost];

    NSString *queryString = [NSString stringWithFormat:@"app_key=%@&device_id=%@&timestamp=%ld&crash=%@",
                           CountlyConnectionQueue.sharedInstance.appKey,
                           [CountlyDeviceInfo udid],
                           time(NULL),
                           CountlyURLEscapedString(CountlyJSONFromObject(crashReport))];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [queryString dataUsingEncoding:NSUTF8StringEncoding];
    COUNTLY_LOG(@"CrashReporting URL: %@", urlString);

    NSURLResponse* response = nil;
	NSError* error = nil;
	NSData* recvData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
	
	if (error || !recvData)
    {
        COUNTLY_LOG(@"CrashReporting failed, report stored to try again later");
        [CountlyConnectionQueue.sharedInstance storeCrashReportToTryLater:CountlyURLEscapedString(CountlyJSONFromObject(crashReport))];
    }
    
    NSSetUncaughtExceptionHandler(NULL);
	signal(SIGABRT, SIG_DFL);
	signal(SIGILL, SIG_DFL);
	signal(SIGSEGV, SIG_DFL);
	signal(SIGFPE, SIG_DFL);
	signal(SIGBUS, SIG_DFL);
	signal(SIGPIPE, SIG_DFL);
}

void CountlySignalHandler(int signalCode)
{
    void* callstack[128];
    NSInteger frames = backtrace(callstack, 128);
    char **lines = backtrace_symbols(callstack, (int)frames);
    
    const NSInteger startOffset = 1;
	NSMutableArray *backtrace = [NSMutableArray arrayWithCapacity:frames];
    
    for (NSInteger i = startOffset; i < frames; i++)
        [backtrace addObject:[NSString stringWithUTF8String:lines[i]]];
    
    free(lines);
    
	NSMutableDictionary *userInfo =[NSMutableDictionary dictionaryWithObject:@(signalCode) forKey:@"signal_code"];
	[userInfo setObject:backtrace forKey:kCountlyCrashUserInfoKey];
    NSString *reason = [NSString stringWithFormat:@"App terminated by SIG%@",[NSString stringWithUTF8String:sys_signame[signalCode]].uppercaseString];

    NSException *e = [NSException exceptionWithName:@"Fatal Signal" reason:reason userInfo:userInfo];

    CountlyUncaughtExceptionHandler(e);
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

    NSString* f = [[NSString.alloc initWithUTF8String:function] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-[]"]];
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
    return abs((int)(UIDevice.currentDevice.batteryLevel*100));
}

- (NSString*)orientation
{
    NSArray *orientations = @[@"Unknown", @"Portrait", @"PortraitUpsideDown", @"LandscapeLeft", @"LandscapeRight", @"FaceUp", @"FaceDown"];
    return orientations[UIDevice.currentDevice.orientation];
}

- (NSUInteger)connectionType
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

- (float)OpenGLESversion
{
    EAGLContext *aContext;
    
    aContext = [EAGLContext.alloc initWithAPI:kEAGLRenderingAPIOpenGLES3];
    if(aContext)
        return 3.0;
    
    aContext = [EAGLContext.alloc initWithAPI:kEAGLRenderingAPIOpenGLES2];
    if(aContext)
        return 2.0;
    
    return 1.0;
}

- (long)timeSinceLaunch
{
    return time(NULL)-startTime;
}

- (BOOL)isJailbroken
{
    FILE *f = fopen("/bin/bash", "r");
    BOOL isJailbroken = (f != NULL);
    fclose(f);
    return isJailbroken;
}

- (BOOL)isInBackground
{
    return UIApplication.sharedApplication.applicationState == UIApplicationStateBackground;
}

#endif

#pragma mark - Countly Background Fetch Session Ending
#if (TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR) && (!COUNTLY_TARGET_WATCHKIT)

- (void)endBackgroundSessionWithCompletionHandler:(void (^)(UIBackgroundFetchResult result))completionHandler
{
    if (eventQueue.count > 0)
    {
        NSString *eventsQueryString = [NSString stringWithFormat:@"app_key=%@&device_id=%@&timestamp=%ld&events=%@",
                                       CountlyConnectionQueue.sharedInstance.appKey,
                                       [CountlyDeviceInfo udid],
                                       time(NULL),
                                       [eventQueue events]];
        
        [CountlyDB.sharedInstance addToQueue:eventsQueryString];
    }
    
    double currTime = CFAbsoluteTimeGetCurrent();
    unsentSessionLength += currTime - lastTime;
    int duration = unsentSessionLength;
    
    NSString *endSessionQueryString = [NSString stringWithFormat:@"app_key=%@&device_id=%@&timestamp=%ld&end_session=1&session_duration=%d",
                                       CountlyConnectionQueue.sharedInstance.appKey,
                                       [CountlyDeviceInfo udid],
                                       time(NULL),
                                       duration];
    
    NSString *urlString = [NSString stringWithFormat:@"%@/i?%@", CountlyConnectionQueue.sharedInstance.appHost, endSessionQueryString];
    [NSURLConnection sendAsynchronousRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:urlString]]
                                       queue:NSOperationQueue.mainQueue
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError)
    {
        if(connectionError)
        {
            completionHandler(UIBackgroundFetchResultFailed);
        }
        else
        {
            COUNTLY_LOG(@"Background session end successful");
            unsentSessionLength -= duration;
            completionHandler(UIBackgroundFetchResultNewData);
        }
    }];
}
#endif

@end