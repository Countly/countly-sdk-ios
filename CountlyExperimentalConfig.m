//  CountlyExperimentalConfig.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@implementation CountlyExperimentalConfig

- (instancetype)init
{
    if (self = [super init])
    {
        self.enableVisibiltyTracking = NO;
        self.enablePreviousNameRecording = NO;
    }
    
    return self;
}

@end
