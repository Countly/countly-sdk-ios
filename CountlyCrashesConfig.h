// ConfigCrashes.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.


#import <Foundation/Foundation.h>
#import "CountlyCrashData.h"

@interface CountlyCrashesConfig : NSObject

@property (nonatomic, copy)  BOOL (^crashFilterCallback)(CountlyCrashData *);
- (void)setCrashFilterCallback:(BOOL (^)(CountlyCrashData *))crashFilterCallback;

@end
