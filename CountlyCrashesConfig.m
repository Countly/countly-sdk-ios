//  ConfigCrashes.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCrashesConfig.h"

@implementation CountlyCrashesConfig

@synthesize crashFilterCallback = _crashFilterCallback;

- (void)setCrashFilterCallback:(BOOL (^)(CountlyCrashData *))crashFilterCallback {
    if (_crashFilterCallback != crashFilterCallback) {
        _crashFilterCallback = [crashFilterCallback copy];
    }
}
@end
