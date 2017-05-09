// CountlyCrashReporter.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface CountlyCrashReporter ()
@end

NSString* const kCountlyExceptionUserInfoBacktraceKey = @"kCountlyExceptionUserInfoBacktraceKey";

@implementation CountlyCrashReporter

static NSMutableArray *customCrashLogs = nil;

#if TARGET_OS_IOS

+ (instancetype)sharedInstance
{
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
    }

    return self;
}

- (void)startCrashReporting
{
    NSSetUncaughtExceptionHandler(&CountlyUncaughtExceptionHandler);
    signal(SIGABRT, CountlySignalHandler);
    signal(SIGILL, CountlySignalHandler);
    signal(SIGSEGV, CountlySignalHandler);
    signal(SIGFPE, CountlySignalHandler);
    signal(SIGBUS, CountlySignalHandler);
    signal(SIGPIPE, CountlySignalHandler);
    signal(SIGTRAP, CountlySignalHandler);
}

- (void)recordHandledException:(NSException *)exception
{
    CountlyExceptionHandler(exception, true);
}

void CountlyUncaughtExceptionHandler(NSException *exception)
{
    CountlyExceptionHandler(exception, false);
}

void CountlyExceptionHandler(NSException *exception, bool nonfatal)
{
    NSMutableDictionary* crashReport = NSMutableDictionary.dictionary;

    crashReport[@"_os"] = CountlyDeviceInfo.osName;
    crashReport[@"_os_version"] = CountlyDeviceInfo.osVersion;
    crashReport[@"_device"] = CountlyDeviceInfo.device;
    crashReport[@"_architecture"] = CountlyDeviceInfo.architecture;
    crashReport[@"_resolution"] = CountlyDeviceInfo.resolution;
    crashReport[@"_app_version"] = CountlyDeviceInfo.appVersion;
    crashReport[@"_app_build"] = CountlyDeviceInfo.appBuild;
    crashReport[@"_build_uuid"] = CountlyDeviceInfo.buildUUID;
    crashReport[@"_executable_name"] = CountlyDeviceInfo.executableName;

    crashReport[@"_name"] = exception.description;
    crashReport[@"_type"] = exception.name;
    crashReport[@"_nonfatal"] = @(nonfatal);


    crashReport[@"_ram_current"] = @((CountlyDeviceInfo.totalRAM-CountlyDeviceInfo.freeRAM)/1048576);
    crashReport[@"_ram_total"] = @(CountlyDeviceInfo.totalRAM/1048576);
    crashReport[@"_disk_current"] = @((CountlyDeviceInfo.totalDisk-CountlyDeviceInfo.freeDisk)/1048576);
    crashReport[@"_disk_total"] = @(CountlyDeviceInfo.totalDisk/1048576);


    crashReport[@"_bat"] = @(CountlyDeviceInfo.batteryLevel);
    crashReport[@"_orientation"] = CountlyDeviceInfo.orientation;
    crashReport[@"_online"] = @((CountlyDeviceInfo.connectionType)? 1 : 0 );
    crashReport[@"_opengl"] = @(CountlyDeviceInfo.OpenGLESversion);
    crashReport[@"_root"] = @(CountlyDeviceInfo.isJailbroken);
    crashReport[@"_background"] = @(CountlyDeviceInfo.isInBackground);
    crashReport[@"_run"] = @(CountlyCommon.sharedInstance.timeSinceLaunch);

    if (CountlyCrashReporter.sharedInstance.crashSegmentation)
        crashReport[@"_custom"] = CountlyCrashReporter.sharedInstance.crashSegmentation;

    if (customCrashLogs)
        crashReport[@"_logs"] = [customCrashLogs componentsJoinedByString:@"\n"];

    NSArray* stackArray = exception.userInfo[kCountlyExceptionUserInfoBacktraceKey];
    if (!stackArray) stackArray = exception.callStackSymbols;

    UInt64 loadAddress = 0;

    NSMutableString* stackString = NSMutableString.string;
    for (NSString* line in stackArray)
    {
        [stackString appendString:line];
        [stackString appendString:@"\n"];

        if (loadAddress == 0)
        {
            NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:@"\\s+\\s" options:0 error:nil];
            NSString* trimmedLine = [regex stringByReplacingMatchesInString:line options:0 range:(NSRange){0,line.length} withTemplate:@" "];
            NSArray* lineComponents = [trimmedLine componentsSeparatedByString:@" "];

            if (lineComponents.count >= 3 && [lineComponents[1] isEqualToString:CountlyDeviceInfo.executableName])
            {
                NSString* address = lineComponents[2];
                NSString* offset = lineComponents.lastObject;
                UInt64 length = strtoull(address.UTF8String, NULL, 16);
                loadAddress = length - offset.integerValue;
            }
        }
    }

    crashReport[@"_load_address"] = [NSString stringWithFormat:@"0x%llx", loadAddress];
    crashReport[@"_error"] = stackString;

    if (nonfatal)
    {
        [CountlyConnectionManager.sharedInstance sendCrashReport:[crashReport cly_JSONify] immediately:NO];
        return;
    }

    [CountlyConnectionManager.sharedInstance sendCrashReport:[crashReport cly_JSONify] immediately:YES];

    NSSetUncaughtExceptionHandler(NULL);
    signal(SIGABRT, SIG_DFL);
    signal(SIGILL, SIG_DFL);
    signal(SIGSEGV, SIG_DFL);
    signal(SIGFPE, SIG_DFL);
    signal(SIGBUS, SIG_DFL);
    signal(SIGPIPE, SIG_DFL);
    signal(SIGTRAP, SIG_DFL);
}

void CountlySignalHandler(int signalCode)
{
    void* callstack[128];
    NSInteger frames = backtrace(callstack, 128);
    char **lines = backtrace_symbols(callstack, (int)frames);

    const NSInteger startOffset = 1;
    NSMutableArray *backtrace = [NSMutableArray arrayWithCapacity:frames];

    for (NSInteger i = startOffset; i < frames; i++)
        [backtrace addObject:[NSString stringWithUTF8String:lines[i]]];

    free(lines);

    NSMutableDictionary *userInfo = @{@"signal_code":@(signalCode)}.mutableCopy;
    userInfo[kCountlyExceptionUserInfoBacktraceKey] = backtrace;
    NSString *reason = [NSString stringWithFormat:@"App terminated by SIG%@", [NSString stringWithUTF8String:sys_signame[signalCode]].uppercaseString];
    NSException *e = [NSException exceptionWithName:@"Fatal Signal" reason:reason userInfo:userInfo];

    CountlyUncaughtExceptionHandler(e);
}

- (void)logWithFormat:(NSString *)format andArguments:(va_list)args
{
    static NSDateFormatter* df = nil;

    if ( customCrashLogs == nil )
    {
        customCrashLogs = NSMutableArray.new;
        df = NSDateFormatter.new;
        df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    }

    NSString* logFormat = [NSString stringWithFormat:@"<%@> %@",[df stringFromDate:NSDate.date], format];
    [customCrashLogs addObject:[NSString.alloc initWithFormat:logFormat arguments:args]];
}
#endif
@end
