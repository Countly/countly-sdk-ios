// CountlyCrashReporter.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyCrashReporter : NSObject
#if TARGET_OS_IOS
@property (nonatomic, strong) NSDictionary* crashSegmentation;

+ (instancetype)sharedInstance;
- (void)startCrashReporting;
- (void)recordHandledException:(NSException *)exception;

- (void)crashTest;
- (void)crashTest2;
- (void)crashTest3;
- (void)crashTest4;

void CCL(const char* function, NSUInteger line, NSString* message);
#define CountlyCrashLog(format, ...) CCL(__FUNCTION__,__LINE__, [NSString stringWithFormat:(format), ##__VA_ARGS__])
#endif
@end
