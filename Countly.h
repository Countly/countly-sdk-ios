
// Countly.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@class CountlyEventQueue;

@interface Countly : NSObject
{
	double unsentSessionLength;
	NSTimer *timer;
	double lastTime;
	BOOL isSuspended;
    CountlyEventQueue *eventQueue;
}

+ (instancetype)sharedInstance;

- (void)start:(NSString *)appKey withHost:(NSString *)appHost;

- (void)startOnCloudWithAppKey:(NSString *)appKey;

- (void)recordEvent:(NSString *)key count:(int)count;

- (void)recordEvent:(NSString *)key count:(int)count sum:(double)sum;

- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(int)count;

- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(int)count sum:(double)sum;

@end


