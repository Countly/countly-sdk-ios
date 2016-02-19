// CountlyCrashReporter.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface CountlyCrashReporter ()
@end

@implementation CountlyCrashReporter

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

#define kCountlyCrashUserInfoKey @"[CLY]_stack_trace"

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
    crashReport[@"_resolution"] = CountlyDeviceInfo.resolution;
    crashReport[@"_app_version"] = CountlyDeviceInfo.appVersion;
    crashReport[@"_name"] = exception.debugDescription;
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
    
    if(CountlyCrashReporter.sharedInstance.crashSegmentation)
        crashReport[@"_custom"] = CountlyCrashReporter.sharedInstance.crashSegmentation;

    if(CountlyCustomCrashLogs)
        crashReport[@"_logs"] = [CountlyCustomCrashLogs componentsJoinedByString:@"\n"];

    NSArray* stackArray = exception.userInfo[kCountlyCrashUserInfoKey];
    if(!stackArray) stackArray = exception.callStackSymbols;

    NSMutableString* stackString = NSMutableString.string;
    for (NSString* line in stackArray)
    {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\s+\\s" options:0 error:nil];
        NSString *cleanLine = [regex stringByReplacingMatchesInString:line options:0 range:(NSRange){0,line.length} withTemplate:@"  "];
        [stackString appendString:cleanLine];
        [stackString appendString:@"\n"];
    }
    
    crashReport[@"_error"] = stackString;
   
    NSString *urlString = [NSString stringWithFormat:@"%@/i", CountlyConnectionManager.sharedInstance.appHost];

    NSString *queryString = [[CountlyConnectionManager.sharedInstance queryEssentials] stringByAppendingFormat:@"&crash=%@", [crashReport JSONify]];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [queryString dataUsingEncoding:NSUTF8StringEncoding];
    COUNTLY_LOG(@"CrashReporting URL: %@", urlString);

    NSURLResponse* response = nil;
	NSError* error = nil;
    NSData* recvData = nil;
    
    if(!nonfatal)
        recvData = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
	
	if (error || !recvData)
    {
        COUNTLY_LOG(@"CrashReporting failed, report stored to try again later");
        [CountlyConnectionManager.sharedInstance sendCrashReportLater:[crashReport JSONify]];
    }
    
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
    
	NSMutableDictionary *userInfo =[NSMutableDictionary dictionaryWithObject:@(signalCode) forKey:@"signal_code"];
	[userInfo setObject:backtrace forKey:kCountlyCrashUserInfoKey];
    NSString *reason = [NSString stringWithFormat:@"App terminated by SIG%@",[NSString stringWithUTF8String:sys_signame[signalCode]].uppercaseString];

    NSException *e = [NSException exceptionWithName:@"Fatal Signal" reason:reason userInfo:userInfo];

    CountlyUncaughtExceptionHandler(e);
}

static NSMutableArray *CountlyCustomCrashLogs = nil;

void CCL(const char* function, NSUInteger line, NSString* message)
{
    static NSDateFormatter* df = nil;
    
    if( CountlyCustomCrashLogs == nil )
    {
        CountlyCustomCrashLogs = NSMutableArray.new;
        df = NSDateFormatter.new;
        df.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    }

    NSString* f = [[NSString.alloc initWithUTF8String:function] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-[]"]];
    NSString* log = [NSString stringWithFormat:@"[%@] <%@ %li> %@",[df stringFromDate:NSDate.date],f,(unsigned long)line,message];
    [CountlyCustomCrashLogs addObject:log];
}


#pragma mark ---

- (void)crashTest
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wundeclared-selector"
    [self performSelector:@selector(thisIsTheUnrecognizedSelectorCausingTheCrash)];
#pragma clang diagnostic pop
}

- (void)crashTest2
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunused-variable"
    NSArray* anArray = @[@"one",@"two",@"three"];
    NSString* myCrashingString = anArray[5];
#pragma clang diagnostic pop
}

- (void)crashTest3
{
    int *nullPointer = NULL;
    *nullPointer = 2015;
}

- (void)crashTest4
{
    CGRect aRect = (CGRect){0.0/0.0, 0.0, 100.0, 100.0};
    UIView *crashView = UIView.new;
    crashView.frame = aRect;
}

#endif


@end
