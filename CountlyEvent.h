// CountlyEvent.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyEvent : NSObject

@property (nonatomic, strong) NSString* key;
@property (nonatomic, strong) NSDictionary* segmentation;
@property (nonatomic, assign) int count;
@property (nonatomic, assign) double sum;
@property (nonatomic, assign) NSTimeInterval timestamp;
@property (nonatomic, assign) NSUInteger hourOfDay;
@property (nonatomic, assign) NSUInteger dayOfWeek;
@property (nonatomic, assign) double duration;
- (NSDictionary *)dictionaryRepresentation;

@end
