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

#ifndef COUNTLY_PREFER_IDFA
#define COUNTLY_PREFER_IDFA 0
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
#if COUNTLY_PREFER_IDFA
#import <AdSupport/ASIdentifierManager.h>
#endif
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

@end

@implementation CountlyDeviceInfo

+ (NSString *)udid
{
#if COUNTLY_PREFER_IDFA && (TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR)
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
    NSMutableURLRequest * request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    
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
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
            if (fileExtIndex == 1) imageData = UIImagePNGRepresentation([UIImage imageWithData:imageData]); //NOTE: for png upload fix. (png file data read directly from disk fails on upload)
#endif
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

- (void)sendUserDetails
{
    NSString *data = [NSString stringWithFormat:@"app_key=%@&device_id=%@&timestamp=%ld&sdk_version="COUNTLY_VERSION"&user_details=%@",
                      self.appKey,
                      [CountlyDeviceInfo udid],
                      time(NULL),
                      [[CountlyUserDetails sharedUserDetails] serialize]];
    
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

- (void)recordUserDetails:(NSDictionary *)userDetails
{
    NSLog(@"%s",__FUNCTION__);
    [CountlyUserDetails.sharedUserDetails deserialize:userDetails];
    [CountlyConnectionQueue.sharedInstance sendUserDetails];
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

@end
