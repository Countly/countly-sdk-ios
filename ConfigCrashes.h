// ConfigCrashes.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.


#import <Foundation/Foundation.h>
#import "CrashFilterCallback.h"

@interface ConfigCrashes : NSObject

@property (nonatomic, strong, nullable) id<CrashFilterCallback> crashFilterCallback;

- (void)setCrashFilterCallback:(id<CrashFilterCallback>_Nonnull)callback;

@end
