// CountlyRCData.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyRCData : NSObject

@property (nonatomic) id value;
@property (nonatomic) BOOL isCurrentUsersData;

- (instancetype)initWithValue:(id)value isCurrentUsersData:(BOOL)isCurrentUsersData;

@end



