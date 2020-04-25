// CountlyCrashReporter.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"
#import <mach-o/dyld.h>
#include <execinfo.h>

#if __has_include(<CrashReporter/CrashReporter.h>)
    #define COUNTLY_PLCRASHREPORTER_EXISTS true
    #import <CrashReporter/CrashReporter.h>
#else

#endif

NSString* const kCountlyExceptionUserInfoBacktraceKey = @"kCountlyExceptionUserInfoBacktraceKey";
NSString* const kCountlyExceptionUserInfoSignalCodeKey = @"kCountlyExceptionUserInfoSignalCodeKey";

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


@interface CountlyCrashReporter ()
@property (nonatomic) NSMutableArray* customCrashLogs;
@property (nonatomic) NSDateFormatter* dateFormatter;
@property (nonatomic) NSString* buildUUID;
@property (nonatomic) NSString* executableName;
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
    if (!self.isEnabledOnInitialConfig)
        return;

    if (!CountlyConsentManager.sharedInstance.consentForCrashReporting)
        return;

    if (self.shouldUsePLCrashReporter)
    {
#ifdef COUNTLY_PLCRASHREPORTER_EXISTS
        [self startPLCrashReporter];
#else
        [NSException raise:@"CountlyPLCrashReporterDependencyNotFoundException" format:@"PLCrashReporter dependency can not be found in Project"];
#endif
        return;
    }

    NSSetUncaughtExceptionHandler(&CountlyUncaughtExceptionHandler);

#if (TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_OSX)
    signal(SIGABRT, CountlySignalHandler);
    signal(SIGILL, CountlySignalHandler);
    signal(SIGSEGV, CountlySignalHandler);
    signal(SIGFPE, CountlySignalHandler);
    signal(SIGBUS, CountlySignalHandler);
    signal(SIGPIPE, CountlySignalHandler);
    signal(SIGTRAP, CountlySignalHandler);
#endif
}


- (void)stopCrashReporting
{
    if (!self.isEnabledOnInitialConfig)
        return;

    NSSetUncaughtExceptionHandler(NULL);

#if (TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_OSX)
    signal(SIGABRT, SIG_DFL);
    signal(SIGILL, SIG_DFL);
    signal(SIGSEGV, SIG_DFL);
    signal(SIGFPE, SIG_DFL);
    signal(SIGBUS, SIG_DFL);
    signal(SIGPIPE, SIG_DFL);
    signal(SIGTRAP, SIG_DFL);
#endif

    self.customCrashLogs = nil;
}

#ifdef COUNTLY_PLCRASHREPORTER_EXISTS

- (void)startPLCrashReporter
{
    PLCrashReporterSignalHandlerType type = self.shouldUseMachSignalHandler ? PLCrashReporterSignalHandlerTypeMach : PLCrashReporterSignalHandlerTypeBSD;
    PLCrashReporterConfig* config = [PLCrashReporterConfig.alloc initWithSignalHandlerType:type symbolicationStrategy:PLCrashReporterSymbolicationStrategyNone];

    self.crashReporter = [PLCrashReporter.alloc initWithConfiguration:config];

    if (self.crashReporter.hasPendingCrashReport)
        [self handlePendingCrashReport];
    else
        [CountlyPersistency.sharedInstance deleteCustomCrashLogFile];

    [self.crashReporter enableCrashReporter];
}

- (void)handlePendingCrashReport
{
    NSError *error;

    NSData* crashData = [self.crashReporter loadPendingCrashReportDataAndReturnError:&error];
    if (!crashData)
    {
        COUNTLY_LOG(@"Could not load crash report data: %@", error);
        return;
    }

    PLCrashReport *report = [PLCrashReport.alloc initWithData:crashData error:&error];
    if (!report)
    {
        COUNTLY_LOG(@"Could not initialize crash report using data %@", error);
        return;
    }

    NSString* reportText = [PLCrashReportTextFormatter stringValueForCrashReport:report withTextFormat:PLCrashReportTextFormatiOS];

    NSMutableDictionary* crashReport = NSMutableDictionary.dictionary;
    crashReport[kCountlyCRKeyError] = reportText;
    crashReport[kCountlyCRKeyOS] = CountlyDeviceInfo.osName;
    crashReport[kCountlyCRKeyAppVersion] = report.applicationInfo.applicationVersion;
    crashReport[kCountlyCRKeyPLCrash] = @YES;
    crashReport[kCountlyCRKeyCustom] = [CountlyPersistency.sharedInstance customCrashLogsFromFile];

    if (self.crashOccuredOnPreviousSessionCallback)
        self.crashOccuredOnPreviousSessionCallback(crashReport);

    BOOL shouldSend = YES;
    if (self.shouldSendCrashReportCallback)
    {
        COUNTLY_LOG(@"shouldSendCrashReportCallback is set, asking it if the report should be sent or not.");
        shouldSend = self.shouldSendCrashReportCallback(crashReport);

        if (shouldSend)
            COUNTLY_LOG(@"shouldSendCrashReportCallback returned YES, sending the report.");
        else
            COUNTLY_LOG(@"shouldSendCrashReportCallback returned NO, not sending the report.");
    }

    if (shouldSend)
    {
        [CountlyConnectionManager.sharedInstance sendCrashReport:[crashReport cly_JSONify] immediately:NO];
    }

    [CountlyPersistency.sharedInstance deleteCustomCrashLogFile];
    [self.crashReporter purgePendingCrashReport];
}

#endif

- (void)recordException:(NSException *)exception withStackTrace:(NSArray *)stackTrace isFatal:(BOOL)isFatal
{
    if (!CountlyConsentManager.sharedInstance.consentForCrashReporting)
        return;

    if (stackTrace)
    {
        NSMutableDictionary* userInfo = [NSMutableDictionary dictionaryWithDictionary:exception.userInfo];
        userInfo[kCountlyExceptionUserInfoBacktraceKey] = stackTrace;
        exception = [NSException exceptionWithName:exception.name reason:exception.reason userInfo:userInfo];
    }

    CountlyExceptionHandler(exception, isFatal, false);
}

void CountlyUncaughtExceptionHandler(NSException *exception)
{
    CountlyExceptionHandler(exception, true, true);
}

void CountlyExceptionHandler(NSException *exception, bool isFatal, bool isAutoDetect)
{
    const NSInteger kCLYMebibit = 1048576;

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

    NSMutableDictionary* crashReport = NSMutableDictionary.dictionary;
    crashReport[kCountlyCRKeyError] = stackTraceJoined;
    crashReport[kCountlyCRKeyBinaryImages] = [CountlyCrashReporter.sharedInstance binaryImagesForStackTrace:stackTrace];
    crashReport[kCountlyCRKeyOS] = CountlyDeviceInfo.osName;
    crashReport[kCountlyCRKeyOSVersion] = CountlyDeviceInfo.osVersion;
    crashReport[kCountlyCRKeyDevice] = CountlyDeviceInfo.device;
    crashReport[kCountlyCRKeyArchitecture] = CountlyDeviceInfo.architecture;
    crashReport[kCountlyCRKeyResolution] = CountlyDeviceInfo.resolution;
    crashReport[kCountlyCRKeyAppVersion] = CountlyDeviceInfo.appVersion;
    crashReport[kCountlyCRKeyAppBuild] = CountlyDeviceInfo.appBuild;
    crashReport[kCountlyCRKeyBuildUUID] = CountlyCrashReporter.sharedInstance.buildUUID ?: @"";
    crashReport[kCountlyCRKeyExecutableName] = CountlyCrashReporter.sharedInstance.executableName ?: @"";
    crashReport[kCountlyCRKeyName] = exception.description;
    crashReport[kCountlyCRKeyType] = exception.name;
    crashReport[kCountlyCRKeyNonfatal] = @(!isFatal);
    crashReport[kCountlyCRKeyRAMCurrent] = @((CountlyDeviceInfo.totalRAM - CountlyDeviceInfo.freeRAM) / kCLYMebibit);
    crashReport[kCountlyCRKeyRAMTotal] = @(CountlyDeviceInfo.totalRAM / kCLYMebibit);
    crashReport[kCountlyCRKeyDiskCurrent] = @((CountlyDeviceInfo.totalDisk - CountlyDeviceInfo.freeDisk) / kCLYMebibit);
    crashReport[kCountlyCRKeyDiskTotal] = @(CountlyDeviceInfo.totalDisk / kCLYMebibit);
    crashReport[kCountlyCRKeyBattery] = @(CountlyDeviceInfo.batteryLevel);
    crashReport[kCountlyCRKeyOrientation] = CountlyDeviceInfo.orientation;
    crashReport[kCountlyCRKeyOnline] = @((CountlyDeviceInfo.connectionType) ? 1 : 0 );
    crashReport[kCountlyCRKeyRoot] = @(CountlyDeviceInfo.isJailbroken);
    crashReport[kCountlyCRKeyBackground] = @(CountlyDeviceInfo.isInBackground);
    crashReport[kCountlyCRKeyRun] = @(CountlyCommon.sharedInstance.timeSinceLaunch);

    NSMutableDictionary* custom = NSMutableDictionary.new;
    if (CountlyCrashReporter.sharedInstance.crashSegmentation)
        [custom addEntriesFromDictionary:CountlyCrashReporter.sharedInstance.crashSegmentation];

    NSMutableDictionary* userInfo = exception.userInfo.mutableCopy;
    [userInfo removeObjectForKey:kCountlyExceptionUserInfoBacktraceKey];
    [userInfo removeObjectForKey:kCountlyExceptionUserInfoSignalCodeKey];
    [custom addEntriesFromDictionary:userInfo];

    if (custom.allKeys.count)
        crashReport[kCountlyCRKeyCustom] = custom;

    if (CountlyCrashReporter.sharedInstance.customCrashLogs)
        crashReport[kCountlyCRKeyLogs] = [CountlyCrashReporter.sharedInstance.customCrashLogs componentsJoinedByString:@"\n"];

    //NOTE: Do not send crash report if it is matching optional regex filter.
    if (!matchesFilter)
    {
        [CountlyConnectionManager.sharedInstance sendCrashReport:[crashReport cly_JSONify] immediately:isAutoDetect];
    }
    else
    {
        COUNTLY_LOG(@"Crash matches filter and it will not be processed.");
    }

    if (isAutoDetect)
        [CountlyCrashReporter.sharedInstance stopCrashReporting];
}

void CountlySignalHandler(int signalCode)
{
    const NSInteger kCountlyStackFramesMax = 128;
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

    CountlyUncaughtExceptionHandler(e);
}

- (void)log:(NSString *)log
{
    if (!CountlyConsentManager.sharedInstance.consentForCrashReporting)
        return;

    const NSInteger kCountlyCustomCrashLogLengthLimit = 1000;

    if (log.length > kCountlyCustomCrashLogLengthLimit)
        log = [log substringToIndex:kCountlyCustomCrashLogLengthLimit];

    NSString* logWithDateTime = [NSString stringWithFormat:@"<%@> %@",[self.dateFormatter stringFromDate:NSDate.date], log];

    if (self.shouldUsePLCrashReporter)
    {
        [CountlyPersistency.sharedInstance writeCustomCrashLogToFile:logWithDateTime];
    }
    else
    {
        [self.customCrashLogs addObject:logWithDateTime];

        if (self.customCrashLogs.count > self.crashLogLimit)
            [self.customCrashLogs removeObjectAtIndex:0];
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
    for (uint32_t i = 0; i < imageCount; i++)
    {
        const char* imageNameChar = _dyld_get_image_name(i);
        if (imageNameChar == NULL)
        {
            COUNTLY_LOG(@"Image Name can not be retrieved!");
            continue;
        }

        NSString *imageName = [NSString stringWithUTF8String:imageNameChar].lastPathComponent;

        if (![binaryImagesInStack containsObject:imageName])
        {
            //NOTE: Image Name is not in the stack trace, so it will be ignored!
            continue;
        }

        COUNTLY_LOG(@"Image Name is in the stack trace, so it will be used!\n%@", imageName);

        const struct mach_header* imageHeader = _dyld_get_image_header(i);
        if (imageHeader == NULL)
        {
            COUNTLY_LOG(@"Image Header can not be retrieved!");
            continue;
        }

        BOOL is64bit = imageHeader->magic == MH_MAGIC_64 || imageHeader->magic == MH_CIGAM_64;
        uintptr_t ptr = (uintptr_t)imageHeader + (is64bit ? sizeof(struct mach_header_64) : sizeof(struct mach_header));
        NSString* imageUUID = nil;

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
            COUNTLY_LOG(@"Image UUID can not be retrieved!");
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

@end



#if (TARGET_OS_OSX)
@implementation CLYExceptionHandlingApplication

- (void)reportException:(NSException *)exception
{
    [super reportException:exception];

    //NOTE: Custom UncaughtExceptionHandler is called with an irrelevant stack trace, not the original crash call stack trace.
    //NOTE: And system's own UncaughtExceptionHandler handles the exception by just printing it to the Console.
    //NOTE: So, we intercept the exception here and record manually.
    [CountlyCrashReporter.sharedInstance recordException:exception withStackTrace:nil isFatal:NO];
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
