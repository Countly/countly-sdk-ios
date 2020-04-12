// CountlyCrashReporter.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyCrashReporter : NSObject
@property (nonatomic) BOOL isEnabledOnInitialConfig;
@property (nonatomic) NSDictionary<NSString *, NSString *>* crashSegmentation;
@property (nonatomic) NSUInteger crashLogLimit;
@property (nonatomic) NSRegularExpression* crashFilter;
@property (nonatomic) BOOL shouldUsePLCrashReporter;
@property (nonatomic) BOOL shouldUseMachSignalHandler;
@property (nonatomic, copy) void (^crashOccuredOnPreviousSessionCallback)(NSDictionary * crashReport);
@property (nonatomic, copy) BOOL (^shouldSendCrashReportCallback)(NSDictionary * crashReport);

+ (instancetype)sharedInstance;
- (void)startCrashReporting;
- (void)stopCrashReporting;
- (void)recordException:(NSException *)exception withStackTrace:(NSArray *)stackTrace isFatal:(BOOL)isFatal;
- (void)log:(NSString *)log;
@end


#if (TARGET_OS_OSX)
#import <Cocoa/Cocoa.h>
//NOTE: Due to some macOS innerworkings limitations, NSPrincipalClass in the app's Info.plist file needs to be set as CLYExceptionHandlingApplication.
@interface CLYExceptionHandlingApplication : NSApplication
@end
#endif
