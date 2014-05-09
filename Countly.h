
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

#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
- (void)startCrashReporting;

void CCL(const char* function, NSUInteger line, NSString* message);
#define CountlyCrashLog(format, ...) CCL(__FUNCTION__,__LINE__, [NSString stringWithFormat:(format), ##__VA_ARGS__])
#endif
@end


