// CountlyEvent.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@implementation CountlyEvent

- (NSDictionary *)dictionaryRepresentation
{
    NSMutableDictionary* eventData = NSMutableDictionary.dictionary;
    eventData[@"key"] = self.key;
    if (self.segmentation)
    {
        eventData[@"segmentation"] = self.segmentation;
    }
    eventData[@"count"] = @(self.count);
    eventData[@"sum"] = @(self.sum);
    eventData[@"timestamp"] = @((long long)(self.timestamp * 1000));
    eventData[@"hour"] = @(self.hourOfDay);
    eventData[@"dow"] = @(self.dayOfWeek);
    eventData[@"dur"] = @(self.duration);
    return eventData;
}

- (id)initWithCoder:(NSCoder *)decoder
{
    self = [super init];
    if (!self)
    {
        return nil;
    }

    self.key = [decoder decodeObjectForKey:@"key"];
    self.segmentation = [decoder decodeObjectForKey:@"segmentation"];
    self.count = [decoder decodeIntegerForKey:@"count"];
    self.sum = [decoder decodeDoubleForKey:@"sum"];
    self.timestamp = [decoder decodeDoubleForKey:@"timestamp"];
    self.hourOfDay = [decoder decodeIntegerForKey:@"hourOfDay"];
    self.dayOfWeek = [decoder decodeIntegerForKey:@"dayOfWeek"];
    self.duration = [decoder decodeDoubleForKey:@"duration"];

    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeObject:self.key forKey:@"key"];
    [encoder encodeObject:self.segmentation forKey:@"segmentation"];
    [encoder encodeInteger:self.count forKey:@"count"];
    [encoder encodeDouble:self.sum forKey:@"sum"];
    [encoder encodeDouble:self.timestamp forKey:@"timestamp"];
    [encoder encodeInteger:self.hourOfDay forKey:@"hourOfDay"];
    [encoder encodeInteger:self.dayOfWeek forKey:@"dayOfWeek"];
    [encoder encodeDouble:self.duration forKey:@"duration"];
}
@end
