//  CountlySDKLimitsConfig.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlySDKLimitsConfig.h"

@implementation CountlySDKLimitsConfig

int _maxKeyLength;

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

- (int)getMaxKeyLength
{
    return _maxKeyLength;
}

@end
