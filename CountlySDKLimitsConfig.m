//  CountlySDKLimitsConfig.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlySDKLimitsConfig.h"
#import "CountlyCommon.h"


const NSInteger kCountlyMaxKeyLength = 128;
const NSInteger kCountlyMaxValueSize = 256;
const NSInteger kCountlyMaxSegmentationValues = 100;
const NSInteger kCountlyMaxBreadcrumbCount = 100;
const NSInteger kCountlyMaxStackTraceLinesPerThread = 30;
const NSInteger kCountlyMaxStackTraceLineLength = 200;

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
        _maxKeyLength = kCountlyMaxKeyLength;
        _maxValueSize = kCountlyMaxValueSize;
        _maxSegmentationValues = kCountlyMaxSegmentationValues;
        _maxBreadcrumbCount = kCountlyMaxBreadcrumbCount;
        _maxStackTraceLinesPerThread = kCountlyMaxStackTraceLinesPerThread;
        _maxStackTraceLineLength = kCountlyMaxStackTraceLineLength;
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

- (void)setMaxBreadcrumbCount:(int)maxBreadcrumbCount
{
    if (maxBreadcrumbCount < 1) {
        maxBreadcrumbCount = 1;
    }
    _maxBreadcrumbCount = maxBreadcrumbCount;
}

- (void)setMaxStackTraceLinesPerThread:(int)maxStackTraceLinesPerThread
{
    CLY_LOG_W(@"%s This setter function is currently a placeholder and doesn't actively utilize the set values.", __FUNCTION__);
    if (maxStackTraceLinesPerThread < 1) {
        maxStackTraceLinesPerThread = 1;
    }
    _maxStackTraceLinesPerThread = maxStackTraceLinesPerThread;
}

- (void)setMaxStackTraceLineLength:(int)maxStackTraceLineLength
{
    CLY_LOG_W(@"%s This setter function is currently a placeholder and doesn't actively utilize the set values.", __FUNCTION__);
    if (maxStackTraceLineLength < 1) {
        maxStackTraceLineLength = 1;
    }
    _maxStackTraceLineLength = maxStackTraceLineLength;
}

- (int)getMaxKeyLength
{
    return _maxKeyLength;
}

- (int)getMaxValueSize
{
    return _maxValueSize;
}

- (int)getMaxSegmentationValues
{
    return _maxSegmentationValues;
}

- (int)getMaxBreadcrumbCount
{
    return _maxBreadcrumbCount;
}

- (int)getMaxStackTraceLinesPerThread
{
    return  _maxStackTraceLinesPerThread;
}

- (int)getMaxStackTraceLineLength
{
    return  _maxStackTraceLineLength;
}
@end
