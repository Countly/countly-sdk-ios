// CountlyEvent.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyEvent : NSObject <NSCoding>

@property (nonatomic, strong) NSString* key;
@property (nonatomic, strong) NSDictionary* segmentation;
@property (nonatomic, assign) NSUInteger count;
@property (nonatomic, assign) double sum;
@property (nonatomic, assign) NSTimeInterval timestamp;
@property (nonatomic, assign) NSUInteger hourOfDay;
@property (nonatomic, assign) NSUInteger dayOfWeek;
@property (nonatomic, assign) NSTimeInterval duration;
- (NSDictionary *)dictionaryRepresentation;

@end