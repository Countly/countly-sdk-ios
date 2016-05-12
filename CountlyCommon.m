// CountlyCommon.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface CountlyCommon ()
{
    NSCalendar* gregorianCalendar;
    NSTimeInterval startTime;
}
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

- (long)timeSinceLaunch
{
    return (long)NSDate.date.timeIntervalSince1970 - startTime;
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
        COUNTLY_LOG(@"Transferring Parent Device ID %@", CountlyDeviceInfo.sharedInstance.deviceID);
    }
}
#endif

#if (TARGET_OS_WATCH)
- (void)session:(WCSession *)session didReceiveUserInfo:(NSDictionary<NSString *, id> *)userInfo
{
    COUNTLY_LOG(@"didReceiveUserInfo %@", [userInfo description]);

    NSString* parentDeviceID = userInfo[kCountlyParentDeviceIDTransferKey];
    
    if(parentDeviceID && ![parentDeviceID isEqualToString:[CountlyPersistency.sharedInstance retrieveWatchParentDeviceID]])
    {
        [CountlyConnectionManager.sharedInstance sendParentDeviceID:parentDeviceID];
    
        [CountlyPersistency.sharedInstance storeWatchParentDeviceID:parentDeviceID];
    
        COUNTLY_LOG(@"Parent Device ID added queue %@", parentDeviceID);
    }
}
#endif

@end



#pragma mark - Categories
NSString* CountlyJSONFromObject(id object)
{
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    if(error){ COUNTLY_LOG(@"Cannot create JSON from object %@", error); }
    
    return [NSString.alloc initWithData:data encoding:NSUTF8StringEncoding];
}

@implementation NSArray (JSONify)
- (NSString *)JSONify
{
    return CountlyJSONFromObject(self);
}
@end

@implementation NSDictionary (JSONify)
- (NSString *)JSONify
{
    return CountlyJSONFromObject(self);
}
@end

@implementation NSMutableData (AppendStringUTF8)
- (void)appendStringUTF8:(NSString*)string
{
    [self appendData:[string dataUsingEncoding:NSUTF8StringEncoding]];
}
@end
