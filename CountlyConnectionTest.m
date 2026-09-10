// CountlyConnectionTest.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"
#import <stdatomic.h>

NSString* const kCountlyCTErrorTimeout = @"timeout";
NSString* const kCountlyCTErrorTransport = @"transport error";
NSString* const kCountlyCTErrorRedirected = @"redirected";
NSString* const kCountlyCTErrorNotRun = @"not run: battery cap";
// success qualifier of opaque (browser) probes, never produced here, but by cross SDK rule it survives the size cap
NSString* const kCountlyCTErrorOpaque = @"opaque";

// report keys
NSString* const kCountlyCTKeyTimestamp = @"ts";
NSString* const kCountlyCTKeySDK = @"sdk";
NSString* const kCountlyCTKeySDKName = @"name";
NSString* const kCountlyCTKeySDKVersion = @"version";
NSString* const kCountlyCTKeyResults = @"results";
NSString* const kCountlyCTKeyFeature = @"f";
NSString* const kCountlyCTKeyOk = @"ok";
NSString* const kCountlyCTKeyStatus = @"st";
NSString* const kCountlyCTKeyLatency = @"ms";
NSString* const kCountlyCTKeyError = @"e";
NSString* const kCountlyCTKeyPathCount = @"n";

// row definition keys, internal
static NSString* const kRowFeature = @"feature";
static NSString* const kRowPaths = @"paths";
static NSString* const kRowRequiresSuccess = @"requiresSuccess";

static const NSTimeInterval kCountlyCTDefaultPerRequestTimeout = 10;
static const NSTimeInterval kCountlyCTDefaultBatteryCapExtra = 30;
static const NSUInteger kCountlyCTMaxRows = 32;
static const NSUInteger kCountlyCTMaxReportBytes = 8 * 1024;
static const NSUInteger kCountlyCTMaxErrorLength = 256;

@interface CountlyConnectionTest ()
{
    atomic_bool batteryRunning;
}
// atomic: set by the halting thread, read by the battery on the utility queue
@property (atomic) BOOL halted;
@end

@implementation CountlyConnectionTest

static CountlyConnectionTest *s_sharedInstance = nil;
static dispatch_once_t onceToken;

+ (instancetype)sharedInstance
{
    dispatch_once(&onceToken, ^{
        s_sharedInstance = self.new;
    });
    return s_sharedInstance;
}

- (instancetype)init
{
    if (self = [super init])
    {
        _perRequestTimeout = kCountlyCTDefaultPerRequestTimeout;
        _batteryCapExtra = kCountlyCTDefaultBatteryCapExtra;
        atomic_store(&batteryRunning, false);
    }
    return self;
}

- (void)resetInstance
{
    CLY_LOG_I(@"%s", __FUNCTION__);
    // a battery still in flight keeps the old instance alive and drops its report on seeing this
    self.halted = YES;
    onceToken = 0;
    s_sharedInstance = nil;
}

- (BOOL)isBatteryRunning
{
    return atomic_load(&batteryRunning);
}

/// Feature rows in report order. A row with no paths is the 'sc' row, measured from the fetch that armed the test.
/// Rows 'core' and 'feedback-assets' have no legitimate 4xx answer, so anything but a 2xx is a fault there.
+ (NSArray<NSDictionary *> *)rows
{
    static NSArray<NSDictionary *> *rows = nil;
    static dispatch_once_t rowsOnce;
    dispatch_once(&rowsOnce, ^{
        rows = @[
            @{kRowFeature: @"core", kRowRequiresSuccess: @YES, kRowPaths: @[@"/o/ping"]},
            @{kRowFeature: @"core-write", kRowRequiresSuccess: @NO, kRowPaths: @[@"/i"]},
            @{kRowFeature: @"sc", kRowRequiresSuccess: @NO, kRowPaths: @[]},
            @{kRowFeature: @"rc", kRowRequiresSuccess: @NO, kRowPaths: @[@"/o/sdk?method=rc"]},
            @{kRowFeature: @"ab", kRowRequiresSuccess: @NO, kRowPaths: @[@"/o/sdk?method=ab_fetch_variants"]},
            @{kRowFeature: @"feedback", kRowRequiresSuccess: @NO, kRowPaths: @[@"/o/sdk?method=feedback"]},
            @{kRowFeature: @"feedback-widget", kRowRequiresSuccess: @NO, kRowPaths: @[@"/o/surveys/nps/widget", @"/o/surveys/survey/widget", @"/o/feedback/widget"]},
            @{kRowFeature: @"feedback-submit", kRowRequiresSuccess: @NO, kRowPaths: @[@"/i/feedback/inputs"]},
            @{kRowFeature: @"content", kRowRequiresSuccess: @NO, kRowPaths: @[@"/o/sdk/content"]},
            @{kRowFeature: @"feedback-page", kRowRequiresSuccess: @NO, kRowPaths: @[@"/feedback/nps", @"/feedback/survey", @"/feedback/rating"]},
            @{kRowFeature: @"feedback-assets", kRowRequiresSuccess: @YES, kRowPaths: @[@"/surveys/images/ct-probe.png", @"/star-rating/images/ct-probe.png"]},
            @{kRowFeature: @"content-page", kRowRequiresSuccess: @NO, kRowPaths: @[@"/_external/content/"]},
        ];
    });
    return rows;
}

/// One graded row of the report, without the optional reason and path count.
static NSMutableDictionary *CountlyCTResultRow(NSString *feature, BOOL ok, NSInteger status, long long latencyMs)
{
    return [@{kCountlyCTKeyFeature: feature, kCountlyCTKeyOk: @(ok), kCountlyCTKeyStatus: @(status), kCountlyCTKeyLatency: @(latencyMs)} mutableCopy];
}

#pragma mark - Battery

- (void)startBatteryWithServerConfigLatency:(long long)scLatencyMs
{
    if (self.halted)
    {
        CLY_LOG_D(@"%s, module halted, ignoring", __FUNCTION__);
        return;
    }

    if (!CountlyServerConfig.sharedInstance.networkingEnabled)
    {
        // the spec does not cover it, honouring the operator's own kill switch was judged safer than probe traffic
        CLY_LOG_D(@"%s, networking is disabled by server config, ignoring", __FUNCTION__);
        return;
    }

    bool expected = false;
    if (!atomic_compare_exchange_strong(&batteryRunning, &expected, true))
    {
        CLY_LOG_D(@"%s, a battery is already running, ignoring this delivery", __FUNCTION__);
        return;
    }

    CLY_LOG_I(@"%s, connection test armed by the server, running the probe battery", __FUNCTION__);

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [self runBatteryAndReport:scLatencyMs];
        atomic_store(&self->batteryRunning, false);
    });
}

/// Runs every row in order and queues the report, unless the instance was halted meanwhile.
- (void)runBatteryAndReport:(long long)scLatencyMs
{
    NSArray<NSDictionary *> *rows = [self runBattery:scLatencyMs];

    if (self.halted)
    {
        CLY_LOG_D(@"%s, halted during the battery, dropping the report", __FUNCTION__);
        return;
    }

    NSString *report = [self buildReport:rows];
    CLY_LOG_D(@"%s, queueing report [ %@ ]", __FUNCTION__, report);
    [CountlyConnectionManager.sharedInstance sendConnectionTestResults:report];
}

/// Probes every row sequentially against the configured host. Rows not reached before the battery cap report 'not run'.
- (NSArray<NSDictionary *> *)runBattery:(long long)scLatencyMs
{
    NSString *serverURL = CountlyConnectionManager.sharedInstance.host;
    NSURLSession *session = [self probeSession];

    NSUInteger requestCount = 0;
    for (NSDictionary *row in CountlyConnectionTest.rows)
        requestCount += ((NSArray *)row[kRowPaths]).count;
    NSTimeInterval cap = requestCount * self.perRequestTimeout + self.batteryCapExtra;
    NSDate *batteryStart = NSDate.date;

    NSMutableArray<NSDictionary *> *results = NSMutableArray.new;
    for (NSDictionary *row in CountlyConnectionTest.rows)
    {
        if (self.halted)
            break;

        NSArray<NSString *> *paths = row[kRowPaths];
        if (paths.count == 0)
        {
            if (scLatencyMs >= 0)
                [results addObject:CountlyCTResultRow(row[kRowFeature], YES, 200, scLatencyMs)];
            continue;
        }

        if (-[batteryStart timeIntervalSinceNow] > cap)
        {
            NSMutableDictionary *notRun = CountlyCTResultRow(row[kRowFeature], NO, 0, 0);
            notRun[kCountlyCTKeyError] = kCountlyCTErrorNotRun;
            [results addObject:notRun];
            continue;
        }

        [results addObject:[self probeRow:row serverURL:serverURL session:session]];
    }

    [session finishTasksAndInvalidate];
    return results.copy;
}

/// Probes every path of one row and combines them: ok only if all passed, first failing status and reason, summed latency.
- (NSDictionary *)probeRow:(NSDictionary *)row serverURL:(NSString *)serverURL session:(NSURLSession *)session
{
    NSArray<NSString *> *paths = row[kRowPaths];
    BOOL requiresSuccess = ((NSNumber *)row[kRowRequiresSuccess]).boolValue;

    NSInteger status = 0;
    long long latency = 0;
    NSString *error = nil;

    for (NSUInteger i = 0; i < paths.count; i++)
    {
        // a halted instance stops probing at the next path, the report is dropped anyway
        if (self.halted)
            break;

        NSString *url = [CountlyConnectionTest probeURLForPath:paths[i] serverURL:serverURL];
        NSDictionary *outcome = [self probe:url session:session];
        NSInteger outcomeStatus = ((NSNumber *)outcome[kCountlyCTKeyStatus]).integerValue;
        latency += ((NSNumber *)outcome[kCountlyCTKeyLatency]).longLongValue;

        NSString *failure = [CountlyConnectionTest gradeStatus:outcomeStatus failure:outcome[kCountlyCTKeyError] requiresSuccessStatus:requiresSuccess];
        CLY_LOG_V(@"%s, [ %@ ] %@ -> status[ %ld ] ms[ %@ ] failure[ %@ ]", __FUNCTION__, row[kRowFeature], url, (long)outcomeStatus, outcome[kCountlyCTKeyLatency], failure);

        // the first failing path decides the row's status and reason, otherwise the first status observed is reported
        if (failure && !error)
        {
            status = outcomeStatus;
            error = failure;
        }
        else if (i == 0)
            status = outcomeStatus;
    }

    NSMutableDictionary *result = CountlyCTResultRow(row[kRowFeature], error == nil, status, latency);
    if (error)
        result[kCountlyCTKeyError] = error;
    if (paths.count > 1)
        result[kCountlyCTKeyPathCount] = @(paths.count);
    return result.copy;
}

/// One bare GET, waited for synchronously. Returns the status (0 when none could be read), the wall clock latency
/// and, for a status of 0, whether it was a timeout or another transport error.
- (NSDictionary *)probe:(NSString *)url session:(NSURLSession *)session
{
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    request.HTTPMethod = @"GET";
    request.cachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
    request.timeoutInterval = self.perRequestTimeout;

    __block NSInteger status = 0;
    __block NSString *failure = nil;
    dispatch_semaphore_t done = dispatch_semaphore_create(0);
    NSDate *start = NSDate.date;

    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error)
    {
        if (error)
            failure = error.code == NSURLErrorTimedOut ? kCountlyCTErrorTimeout : kCountlyCTErrorTransport;
        else if ([response isKindOfClass:NSHTTPURLResponse.class])
            status = ((NSHTTPURLResponse *)response).statusCode;
        else
            failure = kCountlyCTErrorTransport;
        dispatch_semaphore_signal(done);
    }];
    [task resume];

    // the request's own deadline should fire first, this only guards against a completion that never comes
    if (dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)((self.perRequestTimeout + 5) * NSEC_PER_SEC))) != 0)
    {
        // cancelling makes the completion run, wait for it so its write cannot race the verdict below
        [task cancel];
        dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
        status = 0;
        failure = kCountlyCTErrorTimeout;
    }

    long long latency = (long long)(-[start timeIntervalSinceNow] * 1000);
    NSMutableDictionary *outcome = [@{kCountlyCTKeyStatus: @(status), kCountlyCTKeyLatency: @(latency)} mutableCopy];
    if (failure)
        outcome[kCountlyCTKeyError] = failure;
    return outcome.copy;
}

/// A session on the SDK's own configuration, so probes ride the same custom headers and, through the delegate,
/// the same pinning. Caching is off and redirects are not followed.
- (NSURLSession *)probeSession
{
    NSURLSessionConfiguration *userConfig = CountlyConnectionManager.sharedInstance.URLSessionConfiguration;
    NSURLSessionConfiguration *configuration = userConfig ? [userConfig copy] : NSURLSessionConfiguration.defaultSessionConfiguration;
    configuration.timeoutIntervalForRequest = self.perRequestTimeout;
    configuration.timeoutIntervalForResource = self.perRequestTimeout;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
    configuration.URLCache = nil;
    configuration.HTTPShouldSetCookies = NO;

    return [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
}

#pragma mark - NSURLSessionTaskDelegate

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest * _Nullable))completionHandler
{
    // a redirect must not be mistaken for a healthy answer, the 3xx itself becomes the task's response
    completionHandler(nil);
}

- (void)URLSession:(NSURLSession *)session didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential * _Nullable))completionHandler
{
    if (CountlyConnectionManager.sharedInstance.pinnedCertificates.count > 0)
    {
        // without this a pinned host would report 'transport error' while the SDK itself works
        [CountlyConnectionManager.sharedInstance URLSession:session didReceiveChallenge:challenge completionHandler:completionHandler];
        return;
    }

    completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
}

#pragma mark - Grading and report

+ (NSString *)probeURLForPath:(NSString *)path serverURL:(NSString *)serverURL
{
    NSString *base = serverURL ?: @"";
    while ([base hasSuffix:@"/"])
        base = [base substringToIndex:base.length - 1];

    NSString *joined = [path hasPrefix:@"/"] ? [base stringByAppendingString:path] : [NSString stringWithFormat:@"%@/%@", base, path];
    NSString *separator = [joined containsString:@"?"] ? @"&" : @"?";
    return [NSString stringWithFormat:@"%@%@ct=1&_=%lld", joined, separator, (long long)(NSDate.date.timeIntervalSince1970 * 1000)];
}

+ (nullable NSString *)gradeStatus:(NSInteger)status failure:(nullable NSString *)failure requiresSuccessStatus:(BOOL)requiresSuccessStatus
{
    if (status <= 0)
        return failure ?: kCountlyCTErrorTransport;
    if (status >= 200 && status < 300)
        return nil;
    if (status >= 300 && status < 400)
        return kCountlyCTErrorRedirected;
    // a 4xx other than 403 is the Countly application answering, unless this row has no legitimate 4xx answer
    if (!requiresSuccessStatus && status >= 400 && status < 500 && status != 403)
        return nil;
    return [NSString stringWithFormat:@"HTTP %ld", (long)status];
}

- (NSString *)buildReport:(NSArray<NSDictionary *> *)rows
{
    NSMutableArray<NSMutableDictionary *> *results = NSMutableArray.new;
    for (NSDictionary *row in rows)
    {
        if (results.count >= kCountlyCTMaxRows)
            break;

        NSMutableDictionary *result = row.mutableCopy;
        NSString *error = result[kCountlyCTKeyError];
        if (error.length > kCountlyCTMaxErrorLength)
            result[kCountlyCTKeyError] = [error substringToIndex:kCountlyCTMaxErrorLength];
        [results addObject:result];
    }

    NSString *report = [self serializedReportWithResults:results];
    if ([self utf8Length:report] > kCountlyCTMaxReportBytes)
    {
        CLY_LOG_W(@"%s, report is over the size cap, dropping error details", __FUNCTION__);
        for (NSMutableDictionary *result in results)
        {
            // the qualifier of an opaque success is not detail, dropping it would upgrade the row's apparent certainty
            if (![result[kCountlyCTKeyError] isEqualToString:kCountlyCTErrorOpaque])
                [result removeObjectForKey:kCountlyCTKeyError];
        }
        report = [self serializedReportWithResults:results];
    }

    while ([self utf8Length:report] > kCountlyCTMaxReportBytes && results.count > 0)
    {
        CLY_LOG_W(@"%s, report is still over the size cap, dropping the last row", __FUNCTION__);
        [results removeLastObject];
        report = [self serializedReportWithResults:results];
    }

    return report;
}

/// The report JSON for the given rows: device clock, SDK identity and the rows.
- (NSString *)serializedReportWithResults:(NSArray<NSDictionary *> *)results
{
    return CountlyJSONFromObject(@{
        kCountlyCTKeyTimestamp: @((long long)(NSDate.date.timeIntervalSince1970 * 1000)),
        kCountlyCTKeySDK: @{kCountlyCTKeySDKName: CountlyCommon.sharedInstance.SDKName, kCountlyCTKeySDKVersion: CountlyCommon.sharedInstance.SDKVersion},
        kCountlyCTKeyResults: results,
    });
}

/// Size of the report on the wire before URL escaping, which is what the server's cap is measured against.
- (NSUInteger)utf8Length:(NSString *)report
{
    return [report lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
}

@end
