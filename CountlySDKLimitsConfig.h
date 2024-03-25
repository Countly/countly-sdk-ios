// CountlySDKLimitsConfig.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.


#import <Foundation/Foundation.h>

extern const NSInteger kCountlyMaxKeyLength;
extern const NSInteger kCountlyMaxValueSize;
extern const NSInteger kCountlyMaxSegmentationValues;
extern const NSInteger kCountlyMaxBreadcrumbCount;
extern const NSInteger kCountlyMaxStackTraceLinesPerThread;
extern const NSInteger kCountlyMaxStackTraceLineLength;


@interface CountlySDKLimitsConfig : NSObject

- (void)setMaxKeyLength:(int)maxKeyLength;
- (void)setMaxValueSize:(int)maxValueSize;
- (void)setMaxSegmentationValues:(int)maxSegmentationValues;

- (void)setMaxBreadcrumbCount:(int)maxBreadcrumbCount;
- (void)setMaxStackTraceLinesPerThread:(int)maxStackTraceLinesPerThread;
- (void)setMaxStackTraceLineLength:(int)maxStackTraceLineLength;
- (int)getMaxKeyLength;
- (int)getMaxValueSize;
- (int)getMaxSegmentationValues;
- (int)getMaxBreadcrumbCount;
- (int)getMaxStackTraceLinesPerThread;
- (int)getMaxStackTraceLineLength;


@end

