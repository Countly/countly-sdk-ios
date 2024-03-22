//  CountlySDKLimitsConfig.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlySDKLimitsConfig.h"

@interface CountlySDKLimitsConfig ()
{
    int _maxKeyLength;
    int _maxValueSize;
    int _maxSegmentationValues;
    int _maxBreadcrumbCount;
    int _maxStackTraceLinesPerThread;
    int _maxStackTraceLineLength;
}
@end
@implementation CountlySDKLimitsConfig



- (instancetype)init
{
    if (self = [super init])
    {
        _maxKeyLength = 128;
        _maxValueSize = 256;
        _maxSegmentationValues = 100;
        _maxBreadcrumbCount = 100;
        _maxStackTraceLinesPerThread = 30;
        _maxStackTraceLineLength = 200;
    }
    
    return self;
}

- (void)setMaxKeyLength:(int)maxKeyLength
{
    if (maxKeyLength < 1) {
        maxKeyLength = 1;
    }
    _maxKeyLength = maxKeyLength;
}

- (void)setMaxValueSize:(int)maxValueSize
{
    if (maxValueSize < 1) {
        maxValueSize = 1;
    }
    _maxValueSize = maxValueSize;
}

- (void)setMaxSegmentationValues:(int)maxSegmentationValues
{
    if (maxSegmentationValues < 1) {
        maxSegmentationValues = 1;
    }
    _maxSegmentationValues = maxSegmentationValues;
}

- (int)getMaxKeyLength
{
    return _maxKeyLength;
}

- (int)getMaxValueSize
{
    return _maxValueSize;
}


- (int)getMaxSegmentationValues {
    return _maxSegmentationValues;
}

@end
