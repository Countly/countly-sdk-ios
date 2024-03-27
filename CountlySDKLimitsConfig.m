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
        CLY_LOG_W(@"%s Ignoring provided value of %d for maxKeyLength because it's less than 1", __FUNCTION__, maxKeyLength);
        return;
    }
    _maxKeyLength = maxKeyLength;
}

- (void)setMaxValueSize:(int)maxValueSize
{
    if (maxValueSize < 1) {
        CLY_LOG_W(@"%s Ignoring provided value of %d for maxValueSize because it's less than 1", __FUNCTION__, maxValueSize);
        return;
    }
    _maxValueSize = maxValueSize;
}

- (void)setMaxSegmentationValues:(int)maxSegmentationValues
{
    if (maxSegmentationValues < 1) {
        CLY_LOG_W(@"%s Ignoring provided value of %d for maxSegmentationValues because it's less than 1", __FUNCTION__, maxSegmentationValues);
        return;
    }
    _maxSegmentationValues = maxSegmentationValues;
}

- (void)setMaxBreadcrumbCount:(int)maxBreadcrumbCount
{
    if (maxBreadcrumbCount < 1) {
        CLY_LOG_W(@"%s Ignoring provided value of %d for maxBreadcrumbCount because it's less than 1", __FUNCTION__, maxBreadcrumbCount);
        return;
    }
    _maxBreadcrumbCount = maxBreadcrumbCount;
}

- (void)setMaxStackTraceLineLength:(int)maxStackTraceLineLength
{
    CLY_LOG_W(@"%s This setter function is currently a placeholder and doesn't actively utilize the set values.", __FUNCTION__);
    if (maxStackTraceLineLength < 1) {
        CLY_LOG_W(@"%s Ignoring provided value of %d for maxStackTraceLineLength because it's less than 1", __FUNCTION__, maxStackTraceLineLength);
        return;
    }
    _maxStackTraceLineLength = maxStackTraceLineLength;
}

- (void)setMaxStackTraceLinesPerThread:(int)maxStackTraceLinesPerThread
{
    CLY_LOG_W(@"%s This setter function is currently a placeholder and doesn't actively utilize the set values.", __FUNCTION__);
    if (maxStackTraceLinesPerThread < 1) {
        CLY_LOG_W(@"%s Ignoring provided value of %d for maxStackTraceLinesPerThread because it's less than 1", __FUNCTION__, maxStackTraceLinesPerThread);
        return;
    }
    _maxStackTraceLinesPerThread = maxStackTraceLinesPerThread;
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

- (int)getMaxStackTraceLineLength
{
    return  _maxStackTraceLineLength;
}

- (int)getMaxStackTraceLinesPerThread
{
    return  _maxStackTraceLinesPerThread;
}
@end
