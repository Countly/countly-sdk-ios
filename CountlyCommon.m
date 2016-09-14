// CountlyCommon.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"
#include <CommonCrypto/CommonDigest.h>

@interface CountlyCommon ()
{
    NSCalendar* gregorianCalendar;
    NSTimeInterval startTime;
}
@property long lastTimestamp;
@end

NSString* const kCountlyParentDeviceIDTransferKey = @"kCountlyParentDeviceIDTransferKey";

@implementation CountlyCommon

+ (instancetype)sharedInstance
{
    static CountlyCommon *s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

+ (void)load
{
    [CountlyCommon.sharedInstance timeSinceLaunch];
    //NOTE: just to record app start time
}

- (instancetype)init
{
    if (self = [super init])
    {
        gregorianCalendar = [NSCalendar.alloc initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        startTime = NSDate.date.timeIntervalSince1970;
    }

    return self;
}


#pragma mark - Time/Date related methods
- (NSInteger)hourOfDay
{
    NSDateComponents* components = [gregorianCalendar components:NSCalendarUnitHour fromDate:NSDate.date];
    return components.hour;
}

- (NSInteger)dayOfWeek
{
    NSDateComponents* components = [gregorianCalendar components:NSCalendarUnitWeekday fromDate:NSDate.date];
    return components.weekday-1;
}

- (NSInteger)timeZone
{
    return NSTimeZone.systemTimeZone.secondsFromGMT / 60;
}

- (long)timeSinceLaunch
{
    return (long)NSDate.date.timeIntervalSince1970 - startTime;
}

- (NSTimeInterval)uniqueTimestamp
{
    long now = floor(NSDate.date.timeIntervalSince1970 * 1000);

    if(now <= self.lastTimestamp)
        self.lastTimestamp ++;
    else
        self.lastTimestamp = now;

    return (double)(self.lastTimestamp / 1000.0);
}

- (NSString *)optionalParameters
{
    NSMutableString *optinonalParameters = @"".mutableCopy;
    
    if(self.ISOCountryCode)
        [optinonalParameters appendFormat:@"&country_code=%@", self.ISOCountryCode];
    if(self.city)
        [optinonalParameters appendFormat:@"&city=%@", self.city];
    if(self.location)
        [optinonalParameters appendFormat:@"&location=%@", self.location];
    
    if(optinonalParameters.length)
        return optinonalParameters;
    
    return nil;
}

#pragma mark - Watch Connectivity

#if (TARGET_OS_IOS || TARGET_OS_WATCH)
- (void)activateWatchConnectivity
{
    if ([WCSession isSupported])
    {
        WCSession *session = WCSession.defaultSession;
        session.delegate = self;
        [session activateSession];
    }
}
#endif

#if (TARGET_OS_IOS)
- (void)transferParentDeviceID
{
    [self activateWatchConnectivity];

    if(WCSession.defaultSession.paired && WCSession.defaultSession.watchAppInstalled)
    {
        [WCSession.defaultSession transferUserInfo:@{kCountlyParentDeviceIDTransferKey:CountlyDeviceInfo.sharedInstance.deviceID}];
        COUNTLY_LOG(@"Transferring parent device ID %@ ...", CountlyDeviceInfo.sharedInstance.deviceID);
    }
}
#endif

#if (TARGET_OS_WATCH)
- (void)session:(WCSession *)session didReceiveUserInfo:(NSDictionary<NSString *, id> *)userInfo
{
    COUNTLY_LOG(@"Watch received user info: \n%@", userInfo);

    NSString* parentDeviceID = userInfo[kCountlyParentDeviceIDTransferKey];

    if(parentDeviceID && ![parentDeviceID isEqualToString:[CountlyPersistency.sharedInstance retrieveWatchParentDeviceID]])
    {
        [CountlyConnectionManager.sharedInstance sendParentDeviceID:parentDeviceID];

        COUNTLY_LOG(@"Parent device ID %@ added to queue.", parentDeviceID);

        [CountlyPersistency.sharedInstance storeWatchParentDeviceID:parentDeviceID];
    }
}
#endif

@end



#pragma mark - Categories
NSString* CountlyJSONFromObject(id object)
{
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    if(error){ COUNTLY_LOG(@"JSON can not be created: \n%@", error); }

    return [data stringUTF8];
}

@implementation NSString (URLEscaped)
- (NSString *)URLEscaped
{
    NSCharacterSet* charset = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"];
    return [self stringByAddingPercentEncodingWithAllowedCharacters:charset];
}

- (NSString *)SHA1
{
    const char* s = [self UTF8String];
    unsigned char digest[CC_SHA1_DIGEST_LENGTH];
    CC_SHA1(s, (CC_LONG)strlen(s), digest);

    NSMutableString* hash = NSMutableString.new;
    for(int i = 0; i < CC_SHA1_DIGEST_LENGTH; i++)
        [hash appendFormat:@"%02x", digest[i]];

    return hash;
}

- (NSData *)dataUTF8
{
    return [self dataUsingEncoding:NSUTF8StringEncoding];
}
@end

@implementation NSArray (JSONify)
- (NSString *)JSONify
{
    return [CountlyJSONFromObject(self) URLEscaped];
}
@end

@implementation NSDictionary (JSONify)
- (NSString *)JSONify
{
    return [CountlyJSONFromObject(self) URLEscaped];
}
@end

@implementation NSMutableData (AppendStringUTF8)
- (void)appendStringUTF8:(NSString *)string
{
    [self appendData:[string dataUTF8]];
}
@end

@implementation NSData (stringUTF8)
- (NSString *)stringUTF8
{
    return [NSString.alloc initWithData:self encoding:NSUTF8StringEncoding];
}
@end
