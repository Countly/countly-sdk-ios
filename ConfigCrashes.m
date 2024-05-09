//  ConfigCrashes.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "ConfigCrashes.h"

@implementation ConfigCrashes

- (instancetype)setCrashFilterCallback:(id<CrashFilterCallback>)callback {
    self.crashFilterCallback = callback;
    return self;
}

@end
