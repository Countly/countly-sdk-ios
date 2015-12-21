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
	eventData[@"timestamp"] = @((long)self.timestamp);
    eventData[@"hour"] = @(self.hourOfDay);
    eventData[@"dow"] = @(self.dayOfWeek);
    eventData[@"dur"] = @(self.duration);
    return eventData;
}
@end