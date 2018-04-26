// CountlyCrashReporter.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyCrashReporter : NSObject
#if TARGET_OS_IOS
@property (nonatomic) BOOL isEnabledOnInitialConfig;
@property (nonatomic) NSDictionary* crashSegmentation;

+ (instancetype)sharedInstance;
- (void)startCrashReporting;
- (void)stopCrashReporting;
- (void)recordHandledException:(NSException *)exception withStackTrace:(NSArray *)stackTrace;
- (void)log:(NSString *)log;
#endif
@end
