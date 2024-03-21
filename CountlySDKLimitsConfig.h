// CountlySDKLimitsConfig.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.


#import <Foundation/Foundation.h>



@interface CountlySDKLimitsConfig : NSObject

- (void)setMaxKeyLength:(int)maxKeyLength;
- (void)setMaxValueSize:(int)maxValueSize;
- (void)setMaxSegmentationValues:(int)maxSegmentationValues;
- (int)getMaxKeyLength;
- (int)getMaxValueSize;
- (int)getMaxSegmentationValues;


@end

