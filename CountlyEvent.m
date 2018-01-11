// CountlyEvent.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@implementation CountlyEvent

NSString* const kCountlyEventKeyKey           = @"key";
NSString* const kCountlyEventKeySegmentation  = @"segmentation";
NSString* const kCountlyEventKeyCount         = @"count";
NSString* const kCountlyEventKeySum           = @"sum";
NSString* const kCountlyEventKeyTimestamp     = @"timestamp";
NSString* const kCountlyEventKeyHourOfDay     = @"hour";
NSString* const kCountlyEventKeyDayOfWeek     = @"dow";
NSString* const kCountlyEventKeyDuration      = @"dur";

- (NSDictionary *)dictionaryRepresentation
{
    NSMutableDictionary* eventData = NSMutableDictionary.dictionary;
    eventData[kCountlyEventKeyKey] = self.key;
    if (self.segmentation)
    {
        eventData[kCountlyEventKeySegmentation] = self.segmentation;
    }
    eventData[kCountlyEventKeyCount] = @(self.count);
    eventData[kCountlyEventKeySum] = @(self.sum);
    eventData[kCountlyEventKeyTimestamp] = @((long long)(self.timestamp * 1000));
    eventData[kCountlyEventKeyHourOfDay] = @(self.hourOfDay);
    eventData[kCountlyEventKeyDayOfWeek] = @(self.dayOfWeek);
    eventData[kCountlyEventKeyDuration] = @(self.duration);
    return eventData;
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    if (self = [super init])
    {
        self.key = [decoder decodeObjectForKey:NSStringFromSelector(@selector(key))];
        self.segmentation = [decoder decodeObjectForKey:NSStringFromSelector(@selector(segmentation))];
        self.count = [decoder decodeIntegerForKey:NSStringFromSelector(@selector(count))];
        self.sum = [decoder decodeDoubleForKey:NSStringFromSelector(@selector(sum))];
        self.timestamp = [decoder decodeDoubleForKey:NSStringFromSelector(@selector(timestamp))];
        self.hourOfDay = [decoder decodeIntegerForKey:NSStringFromSelector(@selector(hourOfDay))];
        self.dayOfWeek = [decoder decodeIntegerForKey:NSStringFromSelector(@selector(dayOfWeek))];
        self.duration = [decoder decodeDoubleForKey:NSStringFromSelector(@selector(duration))];
    }

    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeObject:self.key forKey:NSStringFromSelector(@selector(key))];
    [encoder encodeObject:self.segmentation forKey:NSStringFromSelector(@selector(segmentation))];
    [encoder encodeInteger:self.count forKey:NSStringFromSelector(@selector(count))];
    [encoder encodeDouble:self.sum forKey:NSStringFromSelector(@selector(sum))];
    [encoder encodeDouble:self.timestamp forKey:NSStringFromSelector(@selector(timestamp))];
    [encoder encodeInteger:self.hourOfDay forKey:NSStringFromSelector(@selector(hourOfDay))];
    [encoder encodeInteger:self.dayOfWeek forKey:NSStringFromSelector(@selector(dayOfWeek))];
    [encoder encodeDouble:self.duration forKey:NSStringFromSelector(@selector(duration))];
}
@end
