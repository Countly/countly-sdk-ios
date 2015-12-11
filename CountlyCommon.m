// CountlyCommon.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface CountlyCommon ()
{
    NSCalendar* gregorianCalendar;
    time_t startTime;
}
@end



@implementation CountlyCommon
+ (instancetype)sharedInstance
{
    static CountlyCommon *s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    if (self = [super init])
    {
        gregorianCalendar = [NSCalendar.alloc initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        startTime = time(NULL);
    }
    
    return self;
}


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
    return time(NULL)-startTime;
}

@end



NSString* CountlyJSONFromObject(id object)
{
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:&error];
    if(error){ COUNTLY_LOG(@"Cannot create JSON from object %@", error); }
    
    return [NSString.alloc initWithData:data encoding:NSUTF8StringEncoding];
}

@implementation NSString (URLEscaped)
- (NSString *)URLEscaped
{
    CFStringRef escaped = CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,(CFStringRef)self, NULL,
                                                                  (CFStringRef)@"!*'();:@&=+$,/?%#[]", kCFStringEncodingUTF8);
    return (NSString*)CFBridgingRelease(escaped);
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
- (void)appendStringUTF8:(NSString*)string
{
    [self appendData:[string dataUsingEncoding:NSUTF8StringEncoding]];
}
@end
