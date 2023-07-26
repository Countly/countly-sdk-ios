// CountlyViewData.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.


#import <Foundation/Foundation.h>

@interface CountlyViewData : NSObject

@property (nonatomic) NSString* viewID;
@property (nonatomic) NSString* viewName;
@property (nonatomic) NSTimeInterval viewStartTime;
@property (nonatomic) NSTimeInterval viewAccumulatedTime;

@end
