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
- (void)recordException:(NSException *)exception isFatal:(BOOL)isFatal stackTrace:(NSArray *)stackTrace segmentation:(NSDictionary *)segmentation;
- (void)recordError:(NSString *)errorName isFatal:(BOOL)isFatal stackTrace:(NSArray *)stackTrace segmentation:(NSDictionary *)segmentation;
- (void)log:(NSString *)log;
- (void)clearCrashLogs;
@end


#if (TARGET_OS_OSX)
#import <Cocoa/Cocoa.h>
//NOTE: Due to some macOS innerworkings limitations, NSPrincipalClass in the app's Info.plist file needs to be set as CLYExceptionHandlingApplication.
@interface CLYExceptionHandlingApplication : NSApplication
@end
#endif
