// CountlyCrashReporter.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"
#import <mach-o/dyld.h>

@interface CountlyCrashReporter ()
@end

NSString* const kCountlyExceptionUserInfoBacktraceKey = @"kCountlyExceptionUserInfoBacktraceKey";

@implementation CountlyCrashReporter

static NSMutableArray *customCrashLogs = nil;
static NSString *buildUUID;
static NSString *loadAddress;

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

- (void)recordHandledException:(NSException *)exception withStackTrace:(NSArray *)stackTrace
{
    if (stackTrace)
    {
        NSMutableDictionary* userInfo = [NSMutableDictionary dictionaryWithDictionary:exception.userInfo];
        userInfo[kCountlyExceptionUserInfoBacktraceKey] = stackTrace;
        exception = [NSException exceptionWithName:exception.name reason:exception.reason userInfo:userInfo];
    }

    CountlyExceptionHandler(exception, true);
}

void CountlyUncaughtExceptionHandler(NSException *exception)
{
    CountlyExceptionHandler(exception, false);
}

void CountlyExceptionHandler(NSException *exception, bool nonfatal)
{
    NSMutableDictionary* crashReport = NSMutableDictionary.dictionary;

    crashReport[@"_binary_images"] = [CountlyCrashReporter.sharedInstance binaryImages];

    crashReport[@"_os"] = CountlyDeviceInfo.osName;
    crashReport[@"_os_version"] = CountlyDeviceInfo.osVersion;
    crashReport[@"_device"] = CountlyDeviceInfo.device;
    crashReport[@"_architecture"] = CountlyDeviceInfo.architecture;
    crashReport[@"_resolution"] = CountlyDeviceInfo.resolution;
    crashReport[@"_app_version"] = CountlyDeviceInfo.appVersion;
    crashReport[@"_app_build"] = CountlyDeviceInfo.appBuild;
    crashReport[@"_build_uuid"] = buildUUID?:@"";
    crashReport[@"_load_address"] = loadAddress?:@"";
    crashReport[@"_executable_name"] = [NSString stringWithUTF8String:getprogname()];

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

    crashReport[@"_error"] = [stackArray componentsJoinedByString:@"\n"];

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

- (void)log:(NSString *)log
{
    static NSDateFormatter* df = nil;

    if ( customCrashLogs == nil )
    {
        customCrashLogs = NSMutableArray.new;
        df = NSDateFormatter.new;
        df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    }

    NSString* logWithDateTime = [NSString stringWithFormat:@"<%@> %@",[df stringFromDate:NSDate.date], log];
    [customCrashLogs addObject:logWithDateTime];
}

- (NSDictionary *)binaryImages
{
    NSMutableDictionary* binaryImages = NSMutableDictionary.new;

    uint32_t imageCount = _dyld_image_count();
    for (uint32_t i = 0; i < imageCount; i++)
    {
        const struct mach_header *imageHeader = _dyld_get_image_header(i);
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
            const struct segment_command_64 *segCmd = (struct segment_command_64 *)ptr;

            if (segCmd->cmd == LC_UUID)
            {
                const uint8_t *uuid = ((const struct uuid_command *)segCmd)->uuid;
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

        const char *imageNameChar = _dyld_get_image_name(i);
        if (imageNameChar == NULL)
        {
            COUNTLY_LOG(@"Image Name can not be retrieved!");
            continue;
        }

        NSString *imageName = [NSString stringWithUTF8String:imageNameChar].lastPathComponent;
        NSString *imageLoadAddress = [NSString stringWithFormat:@"0x%llX", (uint64_t)imageHeader];

        //NOTE: For first version symbolication support where server needs only main app's build uuid and load address in crash dictionary.
        //      Make sure this method (`binaryImages`) is called before setting build uuid and load address in crash dictionary.
        //      It will be unnecessary when server supports symbolication for all binary images
        if (imageHeader->filetype == MH_EXECUTE)
        {
            buildUUID = imageUUID;
            loadAddress = imageLoadAddress;
        }

        binaryImages[imageName] = @{@"la": imageLoadAddress, @"id": imageUUID};
    }

    return [NSDictionary dictionaryWithDictionary:binaryImages];
}
#endif
@end
