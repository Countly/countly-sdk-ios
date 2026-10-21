// CountlyCrashReporter.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"
#import <mach-o/dyld.h>
#include <execinfo.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>

#if __has_include(<CrashReporter/CrashReporter.h>)
    #define COUNTLY_PLCRASHREPORTER_EXISTS true
    #import <CrashReporter/CrashReporter.h>
#else

#endif

NSString* const kCountlyExceptionUserInfoBacktraceKey = @"kCountlyExceptionUserInfoBacktraceKey";
NSString* const kCountlyExceptionUserInfoSignalCodeKey = @"kCountlyExceptionUserInfoSignalCodeKey";
NSString* const kCountlyExceptionUserInfoSegmentationOverrideKey = @"kCountlyExceptionUserInfoSegmentationOverrideKey";

NSString* const kCountlyCRKeyBinaryImages      = @"_binary_images";
NSString* const kCountlyCRKeyOS                = @"_os";
NSString* const kCountlyCRKeyOSVersion         = @"_os_version";
NSString* const kCountlyCRKeyDevice            = @"_device";
NSString* const kCountlyCRKeyArchitecture      = @"_architecture";
NSString* const kCountlyCRKeyResolution        = @"_resolution";
NSString* const kCountlyCRKeyAppVersion        = @"_app_version";
NSString* const kCountlyCRKeyAppBuild          = @"_app_build";
NSString* const kCountlyCRKeyBuildUUID         = @"_build_uuid";
NSString* const kCountlyCRKeyExecutableName    = @"_executable_name";
NSString* const kCountlyCRKeyName              = @"_name";
NSString* const kCountlyCRKeyType              = @"_type";
NSString* const kCountlyCRKeyError             = @"_error";
NSString* const kCountlyCRKeyNonfatal          = @"_nonfatal";
NSString* const kCountlyCRKeyRAMCurrent        = @"_ram_current";
NSString* const kCountlyCRKeyRAMTotal          = @"_ram_total";
NSString* const kCountlyCRKeyDiskCurrent       = @"_disk_current";
NSString* const kCountlyCRKeyDiskTotal         = @"_disk_total";
NSString* const kCountlyCRKeyBattery           = @"_bat";
NSString* const kCountlyCRKeyOrientation       = @"_orientation";
NSString* const kCountlyCRKeyOnline            = @"_online";
NSString* const kCountlyCRKeyRoot              = @"_root";
NSString* const kCountlyCRKeyBackground        = @"_background";
NSString* const kCountlyCRKeyRun               = @"_run";
NSString* const kCountlyCRKeyCustom            = @"_custom";
NSString* const kCountlyCRKeyLogs              = @"_logs";
NSString* const kCountlyCRKeyPLCrash           = @"_plcrash";
NSString* const kCountlyCRKeyImageLoadAddress  = @"la";
NSString* const kCountlyCRKeyImageBuildUUID    = @"id";
NSString* const kCountlyCRKeyOB                = @"_ob";


// Which mechanism, if any, currently has Countly's unhandled crash handlers installed. Tracking the
// mechanism instead of a plain flag keeps two things correct: 'stopCrashReporting' only tears down the
// handlers Countly itself installed, and a change of 'shouldUsePLCrashReporter' between calls is not
// mistaken for "already installed"
typedef NS_ENUM(NSInteger, CLYCrashHandlerInstallation)
{
    CLYCrashHandlerInstallationNone = 0,
    CLYCrashHandlerInstallationDefault,
    CLYCrashHandlerInstallationPLCrashReporter
};

void CountlyUncaughtExceptionHandler(NSException *exception);
void CountlySignalHandler(int signalCode);

static NSUncaughtExceptionHandler* s_previousExceptionHandler = NULL;
static BOOL s_hasInstalledExceptionHandler = NO;
static atomic_bool s_isHandlingUncaughtException = false;
// set by the first automatically detected crash, so the signal that ends the process after it, which a later crash
// tool can chain back into Countly, is not reported as a second crash
static atomic_bool s_hasReportedAutomaticCrash = false;

/// Installs Countly's uncaught exception handler, chaining to the one it replaces, and leaves a handler installed over it in place.
static void CountlyInstallUncaughtExceptionHandler(void)
{
    NSUncaughtExceptionHandler* current = NSGetUncaughtExceptionHandler();
    if (current == &CountlyUncaughtExceptionHandler)
        return;

    if (current && s_hasInstalledExceptionHandler && current != s_previousExceptionHandler)
        return;

    s_previousExceptionHandler = current;
    s_hasInstalledExceptionHandler = YES;
    NSSetUncaughtExceptionHandler(&CountlyUncaughtExceptionHandler);
}

/// Puts back the uncaught exception handler Countly replaced, unless another handler has replaced Countly's since, and then
/// forgets it, so the next install chains to whatever is live by then.
static void CountlyUninstallUncaughtExceptionHandler(void)
{
    // a handler installed over Countly's still chains into it, so the replaced one has to stay known for that chain
    if (NSGetUncaughtExceptionHandler() != &CountlyUncaughtExceptionHandler)
        return;

    NSSetUncaughtExceptionHandler(s_previousExceptionHandler);
    s_previousExceptionHandler = NULL;
    s_hasInstalledExceptionHandler = NO;
}

#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_TV || TARGET_OS_OSX)
static const int kCountlyCrashSignals[] = {SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGPIPE, SIGTRAP};
static const size_t kCountlyCrashSignalsCount = sizeof(kCountlyCrashSignals) / sizeof(kCountlyCrashSignals[0]);
static struct sigaction s_previousSignalActions[NSIG];
static BOOL s_hasPreviousSignalAction[NSIG];
// the thread reporting each signal, or the handed over mark once that is done, until Countly's handler is installed again
static _Atomic(pthread_t) s_signalHandlingThread[NSIG];
#define kCountlySignalHandedOver ((pthread_t)(uintptr_t)1)

/// Whether the given action runs CountlySignalHandler.
static BOOL CountlyIsCountlySignalAction(const struct sigaction *action)
{
    return !(action->sa_flags & SA_SIGINFO) && action->sa_handler == CountlySignalHandler;
}

/// Whether two actions run the same handler.
static BOOL CountlyIsSameSignalAction(const struct sigaction *action, const struct sigaction *other)
{
    return (action->sa_flags & SA_SIGINFO) == (other->sa_flags & SA_SIGINFO) && action->sa_handler == other->sa_handler;
}

/// Installs CountlySignalHandler for every crash signal the app does not ignore, keeping the replaced action and leaving later handlers in place.
static void CountlyInstallSignalHandlers(void)
{
    for (size_t i = 0; i < kCountlyCrashSignalsCount; i++)
    {
        int signalCode = kCountlyCrashSignals[i];
        struct sigaction current;
        if (sigaction(signalCode, NULL, &current) != 0 || CountlyIsCountlySignalAction(&current))
            continue;

        BOOL isPlainDisposition = !(current.sa_flags & SA_SIGINFO);
        if (isPlainDisposition && current.sa_handler == SIG_IGN)
            continue;

        BOOL isDefault = isPlainDisposition && current.sa_handler == SIG_DFL;
        // a broken pipe is often survived: only the app's own handler knows, so a SIGPIPE it handles is left to it like one it ignores
        if (signalCode == SIGPIPE && !isDefault)
            continue;

        BOOL isReplacedAction = s_hasPreviousSignalAction[signalCode] && CountlyIsSameSignalAction(&current, &s_previousSignalActions[signalCode]);
        if (s_hasPreviousSignalAction[signalCode] && !isDefault && !isReplacedAction)
            continue;

        struct sigaction action;
        memset(&action, 0, sizeof(action));
        action.sa_handler = CountlySignalHandler;
        sigemptyset(&action.sa_mask);

        struct sigaction previous;
        if (sigaction(signalCode, &action, &previous) == 0)
        {
            s_previousSignalActions[signalCode] = previous;
            s_hasPreviousSignalAction[signalCode] = YES;
            atomic_store(&s_signalHandlingThread[signalCode], NULL);
        }
    }
}

/// Puts back the actions Countly replaced, for the signals where Countly's handler is still the live one, and forgets those, so
/// the next install chains to whatever is live by then. A signal whose handler was installed over Countly's keeps its record.
static void CountlyUninstallSignalHandlers(void)
{
    for (size_t i = 0; i < kCountlyCrashSignalsCount; i++)
    {
        int signalCode = kCountlyCrashSignals[i];
        struct sigaction current;
        if (s_hasPreviousSignalAction[signalCode] && sigaction(signalCode, NULL, &current) == 0 && CountlyIsCountlySignalAction(&current))
        {
            sigaction(signalCode, &s_previousSignalActions[signalCode], NULL);
            memset(&s_previousSignalActions[signalCode], 0, sizeof(s_previousSignalActions[signalCode]));
            s_hasPreviousSignalAction[signalCode] = NO;
        }
    }
}

/// Restores the action Countly replaced, or the default one, and raises the signal again so it lands there once the handler returns.
static void CountlyHandOverSignal(int signalCode)
{
    if (s_hasPreviousSignalAction[signalCode] && !CountlyIsCountlySignalAction(&s_previousSignalActions[signalCode]))
        sigaction(signalCode, &s_previousSignalActions[signalCode], NULL);
    else
        signal(signalCode, SIG_DFL);

    raise(signalCode);
}
#endif

/// Forgets the handlers Countly replaced and the marks of a crash being handled, so the next install chains to whatever is live then.
static void CountlyForgetReplacedCrashHandlers(void)
{
    s_previousExceptionHandler = NULL;
    s_hasInstalledExceptionHandler = NO;
    atomic_store(&s_isHandlingUncaughtException, false);
    atomic_store(&s_hasReportedAutomaticCrash, false);
#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_TV || TARGET_OS_OSX)
    memset(s_previousSignalActions, 0, sizeof(s_previousSignalActions));
    memset(s_hasPreviousSignalAction, 0, sizeof(s_hasPreviousSignalAction));
    for (int signalCode = 0; signalCode < NSIG; signalCode++)
        atomic_store(&s_signalHandlingThread[signalCode], NULL);
#endif
}

@interface CountlyCrashReporter ()
@property (nonatomic) CLYCrashHandlerInstallation crashHandlerInstallation;
@property (nonatomic) NSMutableArray* customCrashLogs;
@property (nonatomic) NSDateFormatter* dateFormatter;
@property (nonatomic) NSString* buildUUID;
@property (nonatomic) NSString* executableName;
@property (nonatomic) NSString* architecture;
#ifdef COUNTLY_PLCRASHREPORTER_EXISTS
@property (nonatomic) PLCrashReporter* crashReporter;
#endif
@end


@implementation CountlyCrashReporter

+ (instancetype)sharedInstance
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return nil;

    static CountlyCrashReporter *s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    if (self = [super init])
    {
        self.crashSegmentation = nil;
        self.customCrashLogs = NSMutableArray.new;
        self.dateFormatter = NSDateFormatter.new;
        self.dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    }

    return self;
}

- (void)startCrashReporting
{
#ifdef COUNTLY_PLCRASHREPORTER_EXISTS
    NSDictionary* pendingCrashReport = nil;
#endif

    // Serialized because the behavior settings response handler calls this from a background thread while
    // init and consent changes call it from another. 'stopCrashReporting' is deliberately left unlocked,
    // since it is also reached from the crash handler itself, where blocking on a lock is not acceptable.
    @synchronized (self)
    {
        // Gated on the resolved 'acr' value (seeded from the developer config, overridable by the server),
        // so the server can enable automatic crash reporting even when the developer did not opt in
        if (!CountlyServerConfig.sharedInstance.automaticCrashReportingEnabled)
        {
            CLY_LOG_D(@"%s crash handlers are not installed, automatic crash reporting is disabled", __FUNCTION__);
            return;
        }

        if (!CountlyConsentManager.sharedInstance.consentForCrashReporting)
        {
            CLY_LOG_V(@"%s no crashes consent given, crash handlers are not installed", __FUNCTION__);
            return;
        }

        if (self.shouldUsePLCrashReporter)
        {
            if (self.crashHandlerInstallation == CLYCrashHandlerInstallationPLCrashReporter)
            {
                CLY_LOG_D(@"%s PLCrashReporter based crash handlers are already installed, capture is wanted again", __FUNCTION__);
                [CountlyPersistency.sharedInstance storePLCrashCaptureSuppressedSince:nil];
                return;
            }

            if (self.crashHandlerInstallation == CLYCrashHandlerInstallationDefault)
            {
                // 'shouldUsePLCrashReporter' changed since the last install, so remove the default handlers
                // Countly put in place before handing over to PLCrashReporter
                CLY_LOG_D(@"%s built in crash handlers are being removed before handing over to PLCrashReporter", __FUNCTION__);
                [self uninstallDefaultCrashHandlers];
                self.crashHandlerInstallation = CLYCrashHandlerInstallationNone;
            }

            CLY_LOG_D(@"%s installing PLCrashReporter based crash handlers, useMachSignalHandler: [%@]", __FUNCTION__, self.shouldUseMachSignalHandler ? @"YES" : @"NO");
#ifdef COUNTLY_PLCRASHREPORTER_EXISTS
            pendingCrashReport = [self startPLCrashReporter];
            // 'startPLCrashReporter' does not report whether PLCrashReporter accepted the install
            self.crashHandlerInstallation = CLYCrashHandlerInstallationPLCrashReporter;
            [CountlyPersistency.sharedInstance storePLCrashCaptureSuppressedSince:nil];
#else
            // Logged rather than raised: this is a build configuration mistake, and this method is also reached
            // from the behavior settings response handler on a background thread, where raising would crash the
            // app, and from init, where it would abort the rest of 'startWithConfig'
            CLY_LOG_E(@"%s PLCrashReporter dependency can not be found in Project, automatic crash reporting will not start", __FUNCTION__);
#endif
        }
        else
        {
            if (self.crashHandlerInstallation == CLYCrashHandlerInstallationDefault)
                CLY_LOG_V(@"%s built in crash handlers are already installed, any of them that was removed is put back", __FUNCTION__);
            else
                CLY_LOG_D(@"%s installing the built in uncaught exception handler and signal handlers", __FUNCTION__);

            CountlyInstallUncaughtExceptionHandler();
#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_TV || TARGET_OS_OSX)
            CountlyInstallSignalHandlers();
#endif
            atomic_store(&s_hasReportedAutomaticCrash, false);
            self.crashHandlerInstallation = CLYCrashHandlerInstallationDefault;
        }
    }

#ifdef COUNTLY_PLCRASHREPORTER_EXISTS
    // outside the lock: the developer's callbacks run here and may call back into the SDK
    if (pendingCrashReport)
    {
        CountlyRunOnMainThread(^{
            [self processPendingCrashReport:pendingCrashReport];
        });
    }
#endif
}


- (void)stopCrashReporting
{
    // Cleared before the installation check: breadcrumbs are gathered under crash consent alone, so they
    // can exist even when no handler was ever installed (for example with 'acr' resolved to false), and a
    // consent revocation has to drop them either way
    [self clearCrashLogs];

    if (self.crashHandlerInstallation == CLYCrashHandlerInstallationNone)
    {
        CLY_LOG_D(@"%s crash handler uninstall is a no-op, no crash handlers were installed by the SDK", __FUNCTION__);
        return;
    }

    if (self.crashHandlerInstallation == CLYCrashHandlerInstallationPLCrashReporter)
    {
        // PLCrashReporter can not be uninstalled once enabled, and Countly never installed the default
        // handlers on that path, so they are left alone rather than clobbering handlers that belong to the
        // host app or another SDK. What it captures from now on is purged instead of sent.
        // NOTE: kept at Debug on purpose, this method is reachable from the signal handler and the Error and
        // Warning macros are not async signal safe
        CLY_LOG_D(@"%s PLCrashReporter can not be uninstalled, crashes it captures from now on will be discarded", __FUNCTION__);
        [self markPLCrashCaptureSuppressed];
    }
    else
    {
        CLY_LOG_D(@"%s uninstalling the uncaught exception handler and restoring the replaced signal handlers", __FUNCTION__);
        [self uninstallDefaultCrashHandlers];
    }

    self.crashHandlerInstallation = CLYCrashHandlerInstallationNone;
}

- (void)resetInstance
{
    if (self.crashHandlerInstallation == CLYCrashHandlerInstallationDefault)
    {
        CLY_LOG_D(@"%s putting back the crash handlers Countly replaced", __FUNCTION__);
        [self uninstallDefaultCrashHandlers];
        self.crashHandlerInstallation = CLYCrashHandlerInstallationNone;
    }
    else if (self.crashHandlerInstallation == CLYCrashHandlerInstallationPLCrashReporter)
    {
        CLY_LOG_D(@"%s PLCrashReporter stays installed, crashes it captures until the SDK starts again will be discarded", __FUNCTION__);
        [self markPLCrashCaptureSuppressed];
    }

    CountlyForgetReplacedCrashHandlers();
}

- (void)suppressAutomaticCrashCapture
{
    if (self.crashHandlerInstallation != CLYCrashHandlerInstallationPLCrashReporter)
        return;

    CLY_LOG_D(@"%s automatic crash reporting is off while PLCrashReporter stays installed, crashes it captures from now on will be discarded", __FUNCTION__);
    [self markPLCrashCaptureSuppressed];
}

/// Records when automatic capture stopped being wanted while PLCrashReporter stays installed. An earlier record is kept.
- (void)markPLCrashCaptureSuppressed
{
    if (![CountlyPersistency.sharedInstance retrievePLCrashCaptureSuppressedSince])
        [CountlyPersistency.sharedInstance storePLCrashCaptureSuppressedSince:NSDate.date];
}

/// Puts back the uncaught exception handler and the signal actions Countly replaced, where Countly's are still the live ones.
- (void)uninstallDefaultCrashHandlers
{
    CountlyUninstallUncaughtExceptionHandler();

#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_TV || TARGET_OS_OSX)
    CountlyUninstallSignalHandlers();
#endif
}

#ifdef COUNTLY_PLCRASHREPORTER_EXISTS

/// Enables PLCrashReporter and returns the report it left from the previous run, to be processed outside the lock, or nil when there is none to send.
- (NSDictionary *)startPLCrashReporter
{
    PLCrashReporterSignalHandlerType type = self.shouldUseMachSignalHandler ? PLCrashReporterSignalHandlerTypeMach : PLCrashReporterSignalHandlerTypeBSD;
    PLCrashReporterConfig* config = [PLCrashReporterConfig.alloc initWithSignalHandlerType:type symbolicationStrategy:PLCrashReporterSymbolicationStrategyNone];

    self.crashReporter = [PLCrashReporter.alloc initWithConfiguration:config];

    CLY_LOG_D(@"%s PLCrashReporter is configured, hasPendingCrashReport: [%@]", __FUNCTION__, self.crashReporter.hasPendingCrashReport ? @"YES" : @"NO");

    NSDictionary* pendingCrashReport = nil;
    if (self.crashReporter.hasPendingCrashReport)
        pendingCrashReport = [self loadPendingCrashReport];
    else
        [CountlyPersistency.sharedInstance deleteCustomCrashLogFile];

    [self.crashReporter enableCrashReporter];

    return pendingCrashReport;
}

/// Builds the pending PLCrashReporter crash report with its breadcrumbs and clears them, or purges it and returns nil when capture was not wanted.
- (NSDictionary *)loadPendingCrashReport
{
    NSError *error;

    NSData* crashData = [self.crashReporter loadPendingCrashReportDataAndReturnError:&error];
    if (!crashData)
    {
        CLY_LOG_E(@"%s pending crash report data could not be loaded from disk, error: [%@]", __FUNCTION__, error.localizedDescription);
        return nil;
    }

    PLCrashReport *report = [PLCrashReport.alloc initWithData:crashData error:&error];
    if (!report)
    {
        CLY_LOG_E(@"%s pending crash report could not be parsed from the loaded data, error: [%@]", __FUNCTION__, error.localizedDescription);
        return nil;
    }

    NSDate* suppressedSince = [CountlyPersistency.sharedInstance retrievePLCrashCaptureSuppressedSince];
    NSDate* crashedAt = report.systemInfo.timestamp;
    // a report without a time can not be shown to predate the window, so it is treated as captured inside it
    if (suppressedSince && (!crashedAt || [crashedAt compare:suppressedSince] != NSOrderedAscending))
    {
        CLY_LOG_D(@"%s pending crash report was captured while automatic crash reporting was not wanted, it will be discarded", __FUNCTION__);
        [CountlyPersistency.sharedInstance deleteCustomCrashLogFile];
        [self.crashReporter purgePendingCrashReport];
        return nil;
    }

    NSString* reportText = [PLCrashReportTextFormatter stringValueForCrashReport:report withTextFormat:PLCrashReportTextFormatiOS];

    NSMutableDictionary* crashReport = NSMutableDictionary.dictionary;
    crashReport[kCountlyCRKeyError] = reportText;
    crashReport[kCountlyCRKeyOS] = CountlyDeviceInfo.osName;
    crashReport[kCountlyCRKeyAppVersion] = report.applicationInfo.applicationVersion;
    crashReport[kCountlyCRKeyPLCrash] = @YES;
    crashReport[kCountlyCRKeyCustom] = [CountlyPersistency.sharedInstance customCrashLogsFromFile];

    [CountlyPersistency.sharedInstance deleteCustomCrashLogFile];

    return crashReport;
}

/// Hands the pending report to the developer's callbacks, queues it unless they decline it, then purges it. Main thread only.
- (void)processPendingCrashReport:(NSDictionary *)crashReport
{
    if (self.crashOccuredOnPreviousSessionCallback)
        self.crashOccuredOnPreviousSessionCallback(crashReport);

    BOOL shouldSend = YES;
    if (self.shouldSendCrashReportCallback)
    {
        CLY_LOG_D(@"%s asking shouldSendCrashReportCallback whether the pending report should be sent", __FUNCTION__);
        shouldSend = self.shouldSendCrashReportCallback(crashReport);

        CLY_LOG_D(@"%s shouldSendCrashReportCallback decision received, shouldSend: [%@]", __FUNCTION__, shouldSend ? @"YES" : @"NO");
    }

    if (shouldSend)
    {
        CLY_LOG_I(@"%s pending crash report recorded, isFatal: [%@], breadcrumbLength: [%lu], customSegmentationProvided: [%@]", __FUNCTION__, @"YES", (unsigned long)[(NSString *)crashReport[kCountlyCRKeyCustom] length], (self.crashSegmentation.count > 0) ? @"YES" : @"NO");
        CLY_LOG_D(@"%s pending crash report detail, report: [%@]", __FUNCTION__, crashReport);

        [CountlyConnectionManager.sharedInstance sendCrashReport:[crashReport cly_JSONify] immediately:NO];
    }

    [self.crashReporter purgePendingCrashReport];
}

#endif

- (void)recordException:(NSException *)exception isFatal:(BOOL)isFatal stackTrace:(NSArray *)stackTrace segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s exception recording requested, exceptionName: [%@], isFatal: [%@], stackTraceFrameCount: [%lu], segmentationKeyCount: [%lu]", __FUNCTION__, exception.name, isFatal ? @"YES" : @"NO", (unsigned long)stackTrace.count, (unsigned long)segmentation.count);
    CLY_LOG_D(@"%s exception recording detail, exception: [%@], stackTrace: [%@], segmentation: [%@]", __FUNCTION__, exception, stackTrace, segmentation);

    if (!CountlyConsentManager.sharedInstance.consentForCrashReporting)
    {
        CLY_LOG_V(@"%s no crashes consent given, exception is not recorded", __FUNCTION__);
        return;
    }

    if (stackTrace || segmentation)
    {
        NSMutableDictionary* userInfo = [NSMutableDictionary dictionaryWithDictionary:exception.userInfo];
        userInfo[kCountlyExceptionUserInfoBacktraceKey] = stackTrace;
        if(segmentation) {
            NSDictionary* truncatedSegmentation = [segmentation cly_truncated:@"Exception segmentation"];
            NSDictionary* limitedSegmentation = [truncatedSegmentation cly_limited:@"Exception segmentation"];
            userInfo[kCountlyExceptionUserInfoSegmentationOverrideKey] = limitedSegmentation.cly_filterSupportedDataTypes;
        }
        exception = [NSException exceptionWithName:exception.name reason:exception.reason userInfo:userInfo];
    }

    CountlyExceptionHandler(exception, isFatal, false);
}

- (void)recordError:(NSString *)errorName isFatal:(BOOL)isFatal stackTrace:(NSArray *)stackTrace segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s error recording requested, errorNameLength: [%lu], isFatal: [%@], stackTraceFrameCount: [%lu], segmentationKeyCount: [%lu]", __FUNCTION__, (unsigned long)errorName.length, isFatal ? @"YES" : @"NO", (unsigned long)stackTrace.count, (unsigned long)segmentation.count);
    CLY_LOG_D(@"%s error recording detail, errorName: [%@], stackTrace: [%@], segmentation: [%@]", __FUNCTION__, errorName, stackTrace, segmentation);

    NSException* exception = [NSException exceptionWithName:@"Swift Error" reason:errorName userInfo:nil];
    [self recordException:exception isFatal:isFatal stackTrace:stackTrace segmentation:segmentation];
}

/// The uncaught exception handler Countly installs: reports the crash, then passes it on to the handler Countly replaced.
void CountlyUncaughtExceptionHandler(NSException *exception)
{
    // a handler that chains back into Countly's would otherwise call the two in turn forever
    bool expected = false;
    if (!atomic_compare_exchange_strong(&s_isHandlingUncaughtException, &expected, true))
        return;

    CountlyExceptionHandler(exception, true, true);

    NSUncaughtExceptionHandler* previousHandler = s_previousExceptionHandler;
    if (previousHandler && previousHandler != &CountlyUncaughtExceptionHandler)
        previousHandler(exception);
}

void CountlyExceptionHandler(NSException *exception, bool isFatal, bool isAutoDetect)
{
    if (!CountlyServerConfig.sharedInstance.crashReportingEnabled)
        return;

    // Automatically detected crashes are additionally gated on the resolved 'acr' value, so a runtime
    // 'acr' = false from the server disables them without uninstalling the handler. Manually recorded
    // exceptions stay governed by 'crt' only.
    if (isAutoDetect && !CountlyServerConfig.sharedInstance.automaticCrashReportingEnabled)
        return;

    // a handler installed over Countly's can still chain into it after crash consent is withdrawn
    if (isAutoDetect && !CountlyConsentManager.sharedInstance.consentForCrashReporting)
        return;

    if (isAutoDetect)
    {
        if (atomic_exchange(&s_hasReportedAutomaticCrash, true))
            return;

        // the immediate send below waits for its completion, which logs on another thread and must not wait for a log
        // gathering lock this thread may hold
        CountlySDKLogsStopCaptureForCrash();
    }

    NSArray* stackTrace = exception.userInfo[kCountlyExceptionUserInfoBacktraceKey];
    if (!stackTrace)
        stackTrace = exception.callStackSymbols;
    
    NSString* stackTraceJoined = [stackTrace componentsJoinedByString:@"\n"];
    
    BOOL matchesFilter = NO;
    if (CountlyCrashReporter.sharedInstance.crashFilter)
    {
        matchesFilter = [CountlyCrashReporter.sharedInstance isMatchingFilter:stackTraceJoined] ||
        [CountlyCrashReporter.sharedInstance isMatchingFilter:exception.description] ||
        [CountlyCrashReporter.sharedInstance isMatchingFilter:exception.name];
    }
    
    NSMutableDictionary* custom = NSMutableDictionary.new;
    if (CountlyCrashReporter.sharedInstance.crashSegmentation)
        [custom addEntriesFromDictionary:CountlyCrashReporter.sharedInstance.crashSegmentation];
    
    NSDictionary* segmentationOverride = exception.userInfo[kCountlyExceptionUserInfoSegmentationOverrideKey];
    if (segmentationOverride)
        [custom addEntriesFromDictionary:segmentationOverride];
    
    NSMutableDictionary* userInfo = exception.userInfo.mutableCopy;
    [userInfo removeObjectForKey:kCountlyExceptionUserInfoBacktraceKey];
    [userInfo removeObjectForKey:kCountlyExceptionUserInfoSignalCodeKey];
    [userInfo removeObjectForKey:kCountlyExceptionUserInfoSegmentationOverrideKey];
    [custom addEntriesFromDictionary:userInfo];
    
    CountlyCrashData* crashData = [CountlyCrashReporter.sharedInstance prepareCrashDataWithError:stackTraceJoined name:exception.name description:exception.description isFatal:isFatal customSegmentation:custom];
    BOOL filterCrash = NO;
    if(CountlyCrashReporter.sharedInstance.crashFilterCallback) {
        // Directly passing the callback as we are doing prviouslt with download variant
        filterCrash = CountlyCrashReporter.sharedInstance.crashFilterCallback(crashData);
    }
    
    //NOTE: Do not send crash report if it is matching optional regex filter.
    if (matchesFilter || filterCrash)
    {
        CLY_LOG_D(@"%s crash report is filtered out and will not be processed, matchesRegexFilter: [%@], matchesFilterCallback: [%@]", __FUNCTION__, matchesFilter ? @"YES" : @"NO", filterCrash ? @"YES" : @"NO");
    }
    else
    {
        NSMutableDictionary* crashReport = [crashData.crashMetrics mutableCopy];
        crashReport[kCountlyCRKeyError] = crashData.stackTrace;
        crashReport[kCountlyCRKeyBinaryImages] = [CountlyCrashReporter.sharedInstance binaryImagesForStackTrace:stackTrace];
        crashReport[kCountlyCRKeyBuildUUID] = CountlyCrashReporter.sharedInstance.buildUUID ?: @"";
        crashReport[kCountlyCRKeyExecutableName] = CountlyCrashReporter.sharedInstance.executableName ?: @"";
        crashReport[kCountlyCRKeyArchitecture] = CountlyCrashReporter.sharedInstance.architecture ?: @"";
        crashReport[kCountlyCRKeyName] = crashData.crashDescription;
        crashReport[kCountlyCRKeyType] = crashData.name;
        crashReport[kCountlyCRKeyNonfatal] = @(!crashData.fatal);
        
        [crashData calculateChangedFields];
        NSNumber *obValue = [crashData getChangedFieldsAsInt];
        if(obValue && [obValue intValue] > 0) {
            crashReport[kCountlyCRKeyOB] = obValue;
        }
        
        if (crashData.crashSegmentation) {
            NSDictionary* truncatedCrashSegmentation = [crashData.crashSegmentation cly_truncated:@"Crash segmentation"];
            NSDictionary* limitedCrashSegmentation = [truncatedCrashSegmentation cly_limited:@"Crash segmentation"];
            crashReport[kCountlyCRKeyCustom] = limitedCrashSegmentation;
        }
        
        if (crashData.breadcrumbs) {
            crashReport[kCountlyCRKeyLogs] = [crashData.breadcrumbs componentsJoinedByString:@"\n"];
        }

        CLY_LOG_I(@"%s crash recorded, isFatal: [%@], isAutoDetected: [%@], customSegmentationKeyCount: [%lu], breadcrumbCount: [%lu]", __FUNCTION__, crashData.fatal ? @"YES" : @"NO", isAutoDetect ? @"YES" : @"NO", (unsigned long)crashData.crashSegmentation.count, (unsigned long)crashData.breadcrumbs.count);
        CLY_LOG_D(@"%s crash detail, breadcrumbs: [%@], crashSegmentation: [%@], stackTrace: [%@]", __FUNCTION__, crashData.breadcrumbs, crashData.crashSegmentation, crashData.stackTrace);

        [CountlyConnectionManager.sharedInstance sendCrashReport:[crashReport cly_JSONify] immediately:isAutoDetect];
    }

    if (isAutoDetect)
        [CountlyCrashReporter.sharedInstance stopCrashReporting];
}

void CountlySignalHandler(int signalCode)
{
#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_TV || TARGET_OS_OSX)
    pthread_t handlingThread = NULL;
    if (!atomic_compare_exchange_strong(&s_signalHandlingThread[signalCode], &handlingThread, pthread_self()))
    {
        if (handlingThread != pthread_self() && handlingThread != kCountlySignalHandedOver)
        {
            // another thread crashed with this signal first, its report goes out before its hand over ends the process
            struct timespec pollInterval = {0, 10 * NSEC_PER_MSEC};
            while (atomic_load(&s_signalHandlingThread[signalCode]) == handlingThread)
                nanosleep(&pollInterval, NULL);

            raise(signalCode);
            return;
        }

        // re-entered on the reporting thread or after the hand over, so a handler chains back into Countly's and the default action ends the loop
        signal(signalCode, SIG_DFL);
        raise(signalCode);
        return;
    }
#endif

    const unsigned int kCountlyStackFramesMax = 128;
    void *stack[kCountlyStackFramesMax];
    NSInteger frameCount = backtrace(stack, kCountlyStackFramesMax);
    char **lines = backtrace_symbols(stack, (int)frameCount);

    NSMutableArray *backtrace = [NSMutableArray arrayWithCapacity:frameCount];
    for (NSInteger i = 1; i < frameCount; i++)
    {
        if (lines[i] != NULL)
        {
            NSString *line = [NSString stringWithUTF8String:lines[i]];
            if (line)
                [backtrace addObject:line];
        }
    }

    free(lines);

    NSDictionary *userInfo = @{kCountlyExceptionUserInfoSignalCodeKey: @(signalCode), kCountlyExceptionUserInfoBacktraceKey: backtrace};
    NSString *reason = [NSString stringWithFormat:@"App terminated by SIG%@", [NSString stringWithUTF8String:sys_signame[signalCode]].uppercaseString];
    NSException *e = [NSException exceptionWithName:@"Fatal Signal" reason:reason userInfo:userInfo];

    CountlyExceptionHandler(e, true, true);

#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_TV || TARGET_OS_OSX)
    CountlyHandOverSignal(signalCode);
    atomic_store(&s_signalHandlingThread[signalCode], kCountlySignalHandedOver);
#endif
}

- (void)log:(NSString *)log
{
    if (!CountlyConsentManager.sharedInstance.consentForCrashReporting)
    {
        CLY_LOG_V(@"%s no crashes consent given, breadcrumb is not recorded", __FUNCTION__);
        return;
    }
    
    log = [log cly_truncatedValue:@"Custom Crash log"];

    CLY_LOG_D(@"%s breadcrumb text detail, log: [%@]", __FUNCTION__, log);

    if (self.shouldUsePLCrashReporter)
    {
        CLY_LOG_D(@"%s breadcrumb is being written to the crash log file", __FUNCTION__);
        [CountlyPersistency.sharedInstance writeCustomCrashLogToFile:log];
    }
    else
    {
        [self.customCrashLogs addObject:log];

        if (self.customCrashLogs.count > self.crashLogLimit)
        {
            CLY_LOG_D(@"%s breadcrumb buffer is full, the oldest breadcrumb is dropped, breadcrumbCount: [%lu], limit: [%lu]", __FUNCTION__, (unsigned long)self.customCrashLogs.count, (unsigned long)self.crashLogLimit);
            [self.customCrashLogs removeObjectAtIndex:0];
        }
        else
        {
            CLY_LOG_D(@"%s breadcrumb added to the in memory buffer, breadcrumbCount: [%lu]", __FUNCTION__, (unsigned long)self.customCrashLogs.count);
        }
    }
}

- (void)clearCrashLogs
{
    CLY_LOG_D(@"%s breadcrumbs are being cleared, breadcrumbCount: [%lu]", __FUNCTION__, (unsigned long)self.customCrashLogs.count);

    if (self.shouldUsePLCrashReporter)
    {
        [CountlyPersistency.sharedInstance deleteCustomCrashLogFile];
    }
    else
    {
        [self.customCrashLogs removeAllObjects];
    }
}

- (NSDictionary *)binaryImagesForStackTrace:(NSArray *)stackTrace
{
    NSMutableSet* binaryImagesInStack = NSMutableSet.new;
    for (NSString* line in stackTrace)
    {
        //NOTE: See _BACKTRACE_FORMAT in https://opensource.apple.com/source/Libc/Libc-498/gen/backtrace.c.auto.html
        NSRange rangeOfBinaryImageName = (NSRange){4, 35};
        if (line.length >= rangeOfBinaryImageName.location + rangeOfBinaryImageName.length)
        {
            NSString* binaryImageName = [line substringWithRange:rangeOfBinaryImageName];
            binaryImageName = [binaryImageName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            [binaryImagesInStack addObject:binaryImageName];
        }
    }

    NSMutableDictionary* binaryImages = NSMutableDictionary.new;

    uint32_t imageCount = _dyld_image_count();
    cpu_type_t cpuType;
    cpu_subtype_t cpuSubType;
    for (uint32_t i = 0; i < imageCount; i++)
    {
        const char* imageNameChar = _dyld_get_image_name(i);
        if (imageNameChar == NULL)
        {
            CLY_LOG_V(@"%s binary image name can not be retrieved, it will be skipped, imageIndex: [%u]", __FUNCTION__, i);
            continue;
        }

        NSString *imageName = [NSString stringWithUTF8String:imageNameChar].lastPathComponent;

        if (![binaryImagesInStack containsObject:imageName])
        {
            CLY_LOG_V(@"%s, imageName:[%@] is not in the stack trace, so it will be ignored!", __FUNCTION__, imageName);
            continue;
        }

        CLY_LOG_V(@"%s, imageName:[%@] is in the stack trace, so it will be used!", __FUNCTION__, imageName);

        const struct mach_header* imageHeader = _dyld_get_image_header(i);
        if (imageHeader == NULL)
        {
            CLY_LOG_V(@"%s binary image header can not be retrieved, it will be skipped, imageName: [%@]", __FUNCTION__, imageName);
            continue;
        }

        BOOL is64bit = imageHeader->magic == MH_MAGIC_64 || imageHeader->magic == MH_CIGAM_64;
        uintptr_t ptr = (uintptr_t)imageHeader + (is64bit ? sizeof(struct mach_header_64) : sizeof(struct mach_header));
        NSString* imageUUID = nil;
        if(imageHeader->cputype){
            cpuType = imageHeader->cputype;
        }
        if (imageHeader->cpusubtype && (cpuSubType == 0 || imageHeader->cpusubtype > cpuSubType)) {
            cpuSubType = imageHeader->cpusubtype;
        }

        for (uint32_t j = 0; j < imageHeader->ncmds; j++)
        {
            const struct segment_command_64* segCmd = (struct segment_command_64*)ptr;

            if (segCmd->cmd == LC_UUID)
            {
                const uint8_t* uuid = ((const struct uuid_command*)segCmd)->uuid;
                imageUUID = [NSUUID.alloc initWithUUIDBytes:uuid].UUIDString;
                break;
            }
            ptr += segCmd->cmdsize;
        }
        
        if (!imageUUID)
        {
            CLY_LOG_V(@"%s binary image UUID can not be retrieved, symbolication may fail for it, imageName: [%@]", __FUNCTION__, imageName);
            continue;
        }

        //NOTE: Include app's own build UUID directly in crash report object, as Countly Server needs it for fast lookup
        if (imageHeader->filetype == MH_EXECUTE)
        {
            CountlyCrashReporter.sharedInstance.buildUUID = imageUUID;
            CountlyCrashReporter.sharedInstance.executableName = imageName;
        }

        NSString *imageLoadAddress = [NSString stringWithFormat:@"0x%llX", (uint64_t)imageHeader];

        binaryImages[imageName] = @{kCountlyCRKeyImageLoadAddress: imageLoadAddress, kCountlyCRKeyImageBuildUUID: imageUUID};
    }
    
    CountlyCrashReporter.sharedInstance.architecture = [CountlyDeviceInfo architectureNameForCPUType:cpuType subtype:cpuSubType];

    CLY_LOG_D(@"%s binary images resolved for the stack trace, loadedImageCount: [%u], matchedImageCount: [%lu]", __FUNCTION__, imageCount, (unsigned long)binaryImages.count);

    return [NSDictionary dictionaryWithDictionary:binaryImages];
}

- (BOOL)isMatchingFilter:(NSString *)string
{
    if (!self.crashFilter)
        return NO;

    NSUInteger numberOfMatches = [self.crashFilter numberOfMatchesInString:string options:0 range:(NSRange){0, string.length}];

    if (numberOfMatches == 0)
        return NO;

    return YES;
}

-(void) setCrashSegmentation:(NSDictionary<NSString *, NSString *>*) crashSegmentation
{
    CLY_LOG_I(@"%s global crash segmentation is being set, keyCount: [%lu], keys: [%@]", __FUNCTION__, (unsigned long)crashSegmentation.count, crashSegmentation.allKeys);
    CLY_LOG_D(@"%s global crash segmentation detail, segmentation: [%@]", __FUNCTION__, crashSegmentation);

    NSDictionary* truncatedSegmentation = [crashSegmentation cly_truncated:@"Crash segmentation"];
    _crashSegmentation = [truncatedSegmentation cly_limited:@"Crash segmentation"];
}

- (CountlyCrashData *)prepareCrashDataWithError:(NSString *)error name:(NSString *)name description:(NSString *)description isFatal:(BOOL)isFatal customSegmentation:(NSMutableDictionary *)customSegmentation {
    if(error == nil) {
        CLY_LOG_D(@"%s crash data is being prepared with a nil stack trace, crashName: [%@], isFatal: [%@]", __FUNCTION__, name, isFatal ? @"YES" : @"NO");
    }
    
    NSDictionary* truncatedSegmentation = [customSegmentation cly_truncated:@"Exception segmentation"];
    NSDictionary* limitedSegmentation = [truncatedSegmentation cly_limited:@"[CountlyCrashReporter] prepareCrashData"];
    
    return [[CountlyCrashData alloc] initWithStackTrace:error name:name description:description crashSegmentation:limitedSegmentation breadcrumbs:self.customCrashLogs crashMetrics:[self getCrashMetrics] fatal:isFatal];
}

- (NSMutableDictionary*)getCrashMetrics
{
    const NSInteger kCLYMebibit = 1048576;
    NSMutableDictionary* crashReport = NSMutableDictionary.dictionary;
    
    crashReport[kCountlyCRKeyOS] = CountlyDeviceInfo.osName;
    crashReport[kCountlyCRKeyOSVersion] = CountlyDeviceInfo.osVersion;
    crashReport[kCountlyCRKeyDevice] = CountlyDeviceInfo.device;
    // crashReport[kCountlyCRKeyArchitecture] = CountlyDeviceInfo.architecture; not here any more because it is not precise to extract architecture info here
    crashReport[kCountlyCRKeyResolution] = CountlyDeviceInfo.resolution;
    crashReport[kCountlyCRKeyAppVersion] = CountlyDeviceInfo.appVersion;
    crashReport[kCountlyCRKeyAppBuild] = CountlyDeviceInfo.appBuild;
   
    crashReport[kCountlyCRKeyRAMCurrent] = @((CountlyDeviceInfo.totalRAM - CountlyDeviceInfo.freeRAM) / kCLYMebibit);
    crashReport[kCountlyCRKeyRAMTotal] = @(CountlyDeviceInfo.totalRAM / kCLYMebibit);
    crashReport[kCountlyCRKeyDiskCurrent] = @((CountlyDeviceInfo.totalDisk - CountlyDeviceInfo.freeDisk) / kCLYMebibit);
    crashReport[kCountlyCRKeyDiskTotal] = @(CountlyDeviceInfo.totalDisk / kCLYMebibit);
    NSInteger batteryLevel = CountlyDeviceInfo.batteryLevel;
    // We will add battery level only if there is a valid value.
    if (batteryLevel >= 0)
    {
        crashReport[kCountlyCRKeyBattery] = @(batteryLevel);
    }
    crashReport[kCountlyCRKeyOrientation] = CountlyDeviceInfo.orientation;
    crashReport[kCountlyCRKeyOnline] = @((CountlyDeviceInfo.connectionType) ? 1 : 0 );
    crashReport[kCountlyCRKeyRoot] = @(CountlyDeviceInfo.isJailbroken);
    crashReport[kCountlyCRKeyBackground] = @(CountlyDeviceInfo.isInBackground);
    crashReport[kCountlyCRKeyRun] = @(CountlyCommon.sharedInstance.timeSinceLaunch);
    
    return crashReport;
}

@end



#if (TARGET_OS_OSX)
@implementation CLYExceptionHandlingApplication

- (void)reportException:(NSException *)exception
{
    [super reportException:exception];

    // the exception is captured without the app asking, so it follows automatic crash reporting as the uncaught handler does
    if (!CountlyServerConfig.sharedInstance.automaticCrashReportingEnabled)
    {
        CLY_LOG_D(@"%s exception caught by the application class is not recorded, automatic crash reporting is disabled", __FUNCTION__);
        return;
    }

    //NOTE: Custom UncaughtExceptionHandler is called with an irrelevant stack trace, not the original crash call stack trace.
    //NOTE: And system's own UncaughtExceptionHandler handles the exception by just printing it to the Console.
    //NOTE: So, we intercept the exception here and record manually.
    [CountlyCrashReporter.sharedInstance recordException:exception isFatal:NO stackTrace:nil segmentation:nil];
}

- (void)sendEvent:(NSEvent *)theEvent
{
    //NOTE: Exceptions caused by UI related events (which run on main thread by default) seem to not trigger reportException: method.
    //NOTE: So, we execute sendEvent: in a try-catch block to catch them.

    @try
    {
        [super sendEvent:theEvent];
    }
    @catch (NSException *exception)
    {
        [self reportException:exception];
    }
}

@end
#endif
