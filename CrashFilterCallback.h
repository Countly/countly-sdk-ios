// CrashFilterCallback.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>
#import "CrashData.h"

@protocol CrashFilterCallback <NSObject>

- (BOOL)filterCrash:(CrashData *)crash;

@end
