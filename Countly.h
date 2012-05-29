
// Countly.h
// 
// This code is provided under the MIT License.
// 
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>


@interface Countly : NSObject {
	double unsentSessionLength;
	NSTimer *timer;
	double lastTime;
	BOOL isSuspended;
}

+ (Countly *)sharedInstance;

- (void)start:(NSString *)appKey;


@end
