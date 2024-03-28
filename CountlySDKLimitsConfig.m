//  CountlySDKLimitsConfig.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlySDKLimitsConfig.h"
#import "CountlyCommon.h"


const NSUInteger kCountlyMaxKeyLength = 128;
const NSUInteger kCountlyMaxValueSize = 256;
const NSUInteger kCountlyMaxSegmentationValues = 100;
const NSUInteger kCountlyMaxBreadcrumbCount = 100;
const NSUInteger kCountlyMaxStackTraceLinesPerThread = 30;
const NSUInteger kCountlyMaxStackTraceLineLength = 200;

@interface CountlySDKLimitsConfig ()
{
    NSUInteger _maxKeyLength;
    NSUInteger _maxValueSize;
    NSUInteger _maxSegmentationValues;
    NSUInteger _maxBreadcrumbCount;
    NSUInteger _maxStackTraceLinesPerThread;
    NSUInteger _maxStackTraceLineLength;
}
@end
@implementation CountlySDKLimitsConfig

- (instancetype)init
{
    if (self = [super init])
    {
        _maxKeyLength = kCountlyMaxKeyLength;
        _maxValueSize = kCountlyMaxValueSize;
        _maxSegmentationValues = kCountlyMaxSegmentationValues;
        _maxBreadcrumbCount = kCountlyMaxBreadcrumbCount;
        _maxStackTraceLinesPerThread = kCountlyMaxStackTraceLinesPerThread;
        _maxStackTraceLineLength = kCountlyMaxStackTraceLineLength;
    }
    
    return self;
}

- (void)setMaxKeyLength:(NSUInteger)maxKeyLength
{
    _maxKeyLength = maxKeyLength;
}

- (void)setMaxValueSize:(NSUInteger)maxValueSize
{
    _maxValueSize = maxValueSize;
}

- (void)setMaxSegmentationValues:(NSUInteger)maxSegmentationValues
{
    _maxSegmentationValues = maxSegmentationValues;
}

- (void)setMaxBreadcrumbCount:(NSUInteger)maxBreadcrumbCount
{
    _maxBreadcrumbCount = maxBreadcrumbCount;
}

- (void)setMaxStackTraceLineLength:(NSUInteger)maxStackTraceLineLength
{
    _maxStackTraceLineLength = maxStackTraceLineLength;
}

- (void)setMaxStackTraceLinesPerThread:(NSUInteger)maxStackTraceLinesPerThread
{
    _maxStackTraceLinesPerThread = maxStackTraceLinesPerThread;
}

- (NSUInteger)getMaxKeyLength
{
    return _maxKeyLength;
}

- (NSUInteger)getMaxValueSize
{
    return _maxValueSize;
}

- (NSUInteger)getMaxSegmentationValues
{
    return _maxSegmentationValues;
}

- (NSUInteger)getMaxBreadcrumbCount
{
    return _maxBreadcrumbCount;
}

- (NSUInteger)getMaxStackTraceLineLength
{
    return  _maxStackTraceLineLength;
}

- (NSUInteger)getMaxStackTraceLinesPerThread
{
    return  _maxStackTraceLinesPerThread;
}
@end
