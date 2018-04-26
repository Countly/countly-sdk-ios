// CountlyCrashReporter.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"
#import <mach-o/dyld.h>
#include <execinfo.h>

NSString* const kCountlyExceptionUserInfoBacktraceKey = @"kCountlyExceptionUserInfoBacktraceKey";

NSString* const kCountlyCRKeyBinaryImages      = @"_binary_images";
NSString* const kCountlyCRKeyOS                = @"_os";
NSString* const kCountlyCRKeyOSVersion         = @"_os_version";
NSString* const kCountlyCRKeyDevice            = @"_device";
NSString* const kCountlyCRKeyArchitecture      = @"_architecture";
NSString* const kCountlyCRKeyResolution        = @"_resolution";
NSString* const kCountlyCRKeyAppVersion        = @"_app_version";
NSString* const kCountlyCRKeyAppBuild          = @"_app_build";
NSString* const kCountlyCRKeyBuildUUID         = @"_build_uuid";
NSString* const kCountlyCRKeyLoadAddress       = @"_load_address";
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
NSString* const kCountlyCRKeyOpenGL            = @"_opengl";
NSString* const kCountlyCRKeyRoot              = @"_root";
NSString* const kCountlyCRKeyBackground        = @"_background";
NSString* const kCountlyCRKeyRun               = @"_run";
NSString* const kCountlyCRKeyCustom            = @"_custom";
NSString* const kCountlyCRKeyLogs              = @"_logs";
NSString* const kCountlyCRKeySignalCode        = @"signal_code";
NSString* const kCountlyCRKeyImageLoadAddress  = @"la";
NSString* const kCountlyCRKeyImageBuildUUID    = @"id";

@implementation CountlyCrashReporter

static NSMutableArray *customCrashLogs = nil;
static NSString *buildUUID;
static NSString *executableName;

#if TARGET_OS_IOS

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
    }

    return self;
}

- (void)startCrashReporting
{
    if (!self.isEnabledOnInitialConfig)
        return;

    if (!CountlyConsentManager.sharedInstance.consentForCrashReporting)
        return;

    NSSetUncaughtExceptionHandler(&CountlyUncaughtExceptionHandler);
    signal(SIGABRT, CountlySignalHandler);
    signal(SIGILL, CountlySignalHandler);
    signal(SIGSEGV, CountlySignalHandler);
    signal(SIGFPE, CountlySignalHandler);
    signal(SIGBUS, CountlySignalHandler);
    signal(SIGPIPE, CountlySignalHandler);
    signal(SIGTRAP, CountlySignalHandler);
}


- (void)stopCrashReporting
{
    if (!self.isEnabledOnInitialConfig)
        return;

    NSSetUncaughtExceptionHandler(NULL);
    signal(SIGABRT, SIG_DFL);
    signal(SIGILL, SIG_DFL);
    signal(SIGSEGV, SIG_DFL);
    signal(SIGFPE, SIG_DFL);
    signal(SIGBUS, SIG_DFL);
    signal(SIGPIPE, SIG_DFL);
    signal(SIGTRAP, SIG_DFL);

    customCrashLogs = nil;
}


- (void)recordHandledException:(NSException *)exception withStackTrace:(NSArray *)stackTrace
{
    if (!CountlyConsentManager.sharedInstance.consentForCrashReporting)
        return;

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

    NSArray* stackTrace = exception.userInfo[kCountlyExceptionUserInfoBacktraceKey];
    if (!stackTrace) stackTrace = exception.callStackSymbols;

    crashReport[kCountlyCRKeyBinaryImages] = [CountlyCrashReporter.sharedInstance binaryImagesForStackTrace:stackTrace];
    crashReport[kCountlyCRKeyOS] = CountlyDeviceInfo.osName;
    crashReport[kCountlyCRKeyOSVersion] = CountlyDeviceInfo.osVersion;
    crashReport[kCountlyCRKeyDevice] = CountlyDeviceInfo.device;
    crashReport[kCountlyCRKeyArchitecture] = CountlyDeviceInfo.architecture;
    crashReport[kCountlyCRKeyResolution] = CountlyDeviceInfo.resolution;
    crashReport[kCountlyCRKeyAppVersion] = CountlyDeviceInfo.appVersion;
    crashReport[kCountlyCRKeyAppBuild] = CountlyDeviceInfo.appBuild;
    crashReport[kCountlyCRKeyBuildUUID] = buildUUID ?: @"";
    crashReport[kCountlyCRKeyExecutableName] = executableName ?: @"";
    crashReport[kCountlyCRKeyName] = exception.description;
    crashReport[kCountlyCRKeyType] = exception.name;
    crashReport[kCountlyCRKeyNonfatal] = @(nonfatal);
    crashReport[kCountlyCRKeyRAMCurrent] = @((CountlyDeviceInfo.totalRAM-CountlyDeviceInfo.freeRAM) / 1048576);
    crashReport[kCountlyCRKeyRAMTotal] = @(CountlyDeviceInfo.totalRAM / 1048576);
    crashReport[kCountlyCRKeyDiskCurrent] = @((CountlyDeviceInfo.totalDisk-CountlyDeviceInfo.freeDisk) / 1048576);
    crashReport[kCountlyCRKeyDiskTotal] = @(CountlyDeviceInfo.totalDisk / 1048576);
    crashReport[kCountlyCRKeyBattery] = @(CountlyDeviceInfo.batteryLevel);
    crashReport[kCountlyCRKeyOrientation] = CountlyDeviceInfo.orientation;
    crashReport[kCountlyCRKeyOnline] = @((CountlyDeviceInfo.connectionType) ? 1 : 0 );
    crashReport[kCountlyCRKeyOpenGL] = CountlyDeviceInfo.OpenGLESversion;
    crashReport[kCountlyCRKeyRoot] = @(CountlyDeviceInfo.isJailbroken);
    crashReport[kCountlyCRKeyBackground] = @(CountlyDeviceInfo.isInBackground);
    crashReport[kCountlyCRKeyRun] = @(CountlyCommon.sharedInstance.timeSinceLaunch);

    if (CountlyCrashReporter.sharedInstance.crashSegmentation)
        crashReport[kCountlyCRKeyCustom] = CountlyCrashReporter.sharedInstance.crashSegmentation;

    if (customCrashLogs)
        crashReport[kCountlyCRKeyLogs] = [customCrashLogs componentsJoinedByString:@"\n"];

    crashReport[kCountlyCRKeyError] = [stackTrace componentsJoinedByString:@"\n"];

    if (nonfatal)
    {
        [CountlyConnectionManager.sharedInstance sendCrashReport:[crashReport cly_JSONify] immediately:NO];
        return;
    }

    [CountlyConnectionManager.sharedInstance sendCrashReport:[crashReport cly_JSONify] immediately:YES];

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
        [backtrace addObject:[NSString stringWithUTF8String:lines[i]]];

    free(lines);

    NSDictionary *userInfo = @{kCountlyCRKeySignalCode: @(signalCode), kCountlyExceptionUserInfoBacktraceKey: backtrace};
    NSString *reason = [NSString stringWithFormat:@"App terminated by SIG%@", [NSString stringWithUTF8String:sys_signame[signalCode]].uppercaseString];
    NSException *e = [NSException exceptionWithName:@"Fatal Signal" reason:reason userInfo:userInfo];

    CountlyUncaughtExceptionHandler(e);
}

- (void)log:(NSString *)log
{
    if (!CountlyConsentManager.sharedInstance.consentForCrashReporting)
        return;

    static NSDateFormatter* df = nil;

    if (!customCrashLogs)
    {
        customCrashLogs = NSMutableArray.new;
        df = NSDateFormatter.new;
        df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    }

    NSString* logWithDateTime = [NSString stringWithFormat:@"<%@> %@",[df stringFromDate:NSDate.date], log];
    [customCrashLogs addObject:logWithDateTime];
}

- (NSDictionary *)binaryImagesForStackTrace:(NSArray *)stackTrace
{
    NSMutableSet* binaryImagesInStack = NSMutableSet.new;
    for (NSString* line in stackTrace)
    {
        NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:@"\\s+\\s" options:0 error:nil];
        NSString* trimmedLine = [regex stringByReplacingMatchesInString:line options:0 range:(NSRange){0,line.length} withTemplate:@" "];
        NSArray* lineComponents = [trimmedLine componentsSeparatedByString:@" "];
        if (lineComponents.count > 1)
            [binaryImagesInStack addObject:lineComponents[1]];
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
            COUNTLY_LOG(@"Image Name is not in stack trace, so it is not needed!");
            continue;
        }


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
            buildUUID = imageUUID;
            executableName = imageName;
        }

        NSString *imageLoadAddress = [NSString stringWithFormat:@"0x%llX", (uint64_t)imageHeader];

        binaryImages[imageName] = @{kCountlyCRKeyImageLoadAddress: imageLoadAddress, kCountlyCRKeyImageBuildUUID: imageUUID};
    }

    return [NSDictionary dictionaryWithDictionary:binaryImages];
}
#endif
@end
