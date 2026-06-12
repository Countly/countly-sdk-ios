// CountlySDKLimitsConfig.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.


#import <Foundation/Foundation.h>

extern const NSUInteger kCountlyMaxKeyLength;
extern const NSUInteger kCountlyMaxValueSize;
extern const NSUInteger kCountlyMaxValueSizePicture;
extern const NSUInteger kCountlyMaxBreadcrumbCount;
extern const NSUInteger kCountlyMaxSegmentationValues;
extern const NSUInteger kCountlyMaxStackTraceLineLength;
extern const NSUInteger kCountlyMaxStackTraceLinesPerThread;


@interface CountlySDKLimitsConfig : NSObject

- (void)setMaxKeyLength:(NSUInteger)maxKeyLength;
- (void)setMaxValueSize:(NSUInteger)maxValueSize;
- (void)setMaxValueSizePicture:(NSUInteger)maxValueSizePicture;
- (void)setMaxBreadcrumbCount:(NSUInteger)maxBreadcrumbCount;
- (void)setMaxSegmentationValues:(NSUInteger)maxSegmentationValues;
- (void)setMaxStackTraceLineLength:(NSUInteger)maxStackTraceLineLength;
- (void)setMaxStackTraceLinesPerThread:(NSUInteger)maxStackTraceLinesPerThread;

- (NSUInteger)getMaxKeyLength;
- (NSUInteger)getMaxValueSize;
- (NSUInteger)getMaxValueSizePicture;
- (NSUInteger)getMaxBreadcrumbCount;
- (NSUInteger)getMaxSegmentationValues;
- (NSUInteger)getMaxStackTraceLineLength;
- (NSUInteger)getMaxStackTraceLinesPerThread;


@end

