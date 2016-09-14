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
- (void)logWithFormat:(NSString *)format andArguments:(va_list)args;
- (void)crashTest;
- (void)crashTest2;
- (void)crashTest3;
- (void)crashTest4;
- (void)crashTest5;
- (void)crashTest6;
#endif
@end
