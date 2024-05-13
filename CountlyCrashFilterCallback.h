// CrashFilterCallback.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>
#import "CountlyCrashData.h"

typedef BOOL (^CountlyCrashFilterCallback)(CountlyCrashData *);
@protocol CountlyCrashFilterCallback <NSObject>

- (BOOL)filterCrash:(CountlyCrashData *)crash;

@end
