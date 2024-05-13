//  ConfigCrashes.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCrashesConfig.h"

@implementation CountlyCrashesConfig

- (void)setCrashFilterCallback:(id<CountlyCrashFilterCallback>)callback {
    self.crashFilterCallback = callback;
}

@end
