// ConfigCrashes.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.


#import <Foundation/Foundation.h>
#import "CountlyCrashFilterCallback.h"

@interface CountlyCrashesConfig : NSObject

@property (nonatomic, strong, nullable) id<CountlyCrashFilterCallback> crashFilterCallback;

- (void)setCrashFilterCallback:(id<CountlyCrashFilterCallback>_Nonnull)callback;

@end
