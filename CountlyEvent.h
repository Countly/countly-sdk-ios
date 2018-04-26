// CountlyEvent.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyEvent : NSObject <NSCoding>

@property (nonatomic, copy) NSString* key;
@property (nonatomic, copy) NSDictionary* segmentation;
@property (nonatomic) NSUInteger count;
@property (nonatomic) double sum;
@property (nonatomic) NSTimeInterval timestamp;
@property (nonatomic) NSUInteger hourOfDay;
@property (nonatomic) NSUInteger dayOfWeek;
@property (nonatomic) NSTimeInterval duration;
- (NSDictionary *)dictionaryRepresentation;

@end
