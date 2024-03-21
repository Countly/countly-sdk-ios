//  CountlySDKLimitsConfig.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlySDKLimitsConfig.h"

@implementation CountlySDKLimitsConfig

int _maxKeyLength;
int _maxValueSize;
int _maxSegmentationValues;

- (instancetype)init
{
    if (self = [super init])
    {
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


@end
