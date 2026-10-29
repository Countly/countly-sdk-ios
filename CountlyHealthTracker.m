//
//  CountlyHealthTracker.m
//  CountlyTestApp-iOS
//
//  Created by Arif Burak Demiray on 20.05.2025.
//  Copyright © 2025 Countly. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <stdatomic.h>
#import "CountlyHealthTracker.h"
#import "CountlyCommon.h"

static atomic_bool s_isRecordingStoppedForCrash = false;

@interface CountlyHealthTracker ()

@property (nonatomic, assign) long countLogWarning;
@property (nonatomic, assign) long countLogError;
@property (nonatomic, assign) long countBackoffRequest;
@property (nonatomic, assign) long countConsecutiveBackoffRequest;
@property (nonatomic, assign) long consecutiveBackoffRequest;
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, copy) NSString *errorMessage;
@property (nonatomic, assign) BOOL healthCheckEnabled;
@property (nonatomic, assign) BOOL healthCheckSent;
// NO while the counters of the previous run are still to be read, the storage can not be read before the SDK starts
@property (nonatomic, assign) BOOL persistedStateLoaded;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary<NSString *, NSNumber *> *> *methodUsage;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *logCodes;

@property (nonatomic, strong) dispatch_queue_t hcQueue;
@end

@implementation CountlyHealthTracker

NSString * const keyLogError = @"LErr";
NSString * const keyLogWarning = @"LWar";
NSString * const keyStatusCode = @"RStatC";
NSString * const keyErrorMessage = @"REMsg";
NSString * const keyBackoffRequest = @"BReq";
NSString * const keyConsecutiveBackoffRequest = @"CBReq";
NSString * const keyMethodUsage = @"MU";
NSString * const keyLogCodes = @"LC";

NSString * const requestKeyErrorCount = @"el";
NSString * const requestKeyWarningCount = @"wl";
NSString * const requestKeyStatusCode = @"sc";
NSString * const requestKeyRequestError = @"em";
NSString * const requestKeyBackoffRequest = @"bom";
NSString * const requestKeyConsecutiveBackoffRequest = @"cbom";
NSString * const requestKeyMethodUsage = @"fu";
NSString * const requestKeyLogCodes = @"lc";

static const long kCountlyHealthCheckCountCap = 65535;

void CountlyHealthTrackerStopRecordingForCrash(void)
{
    atomic_store(&s_isRecordingStoppedForCrash, true);
}

void CountlyHealthTrackerResumeRecordingAfterCrash(void)
{
    atomic_store(&s_isRecordingStoppedForCrash, false);
}

+ (instancetype)sharedInstance {
    static CountlyHealthTracker *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init{
    self = [super init];
    if (self) {
        _errorMessage = @"";
        _statusCode = -1;
        _healthCheckSent = NO;
        _healthCheckEnabled = YES;
        _methodUsage = NSMutableDictionary.new;
        _logCodes = NSMutableDictionary.new;

        // queue for health tracker state
        _hcQueue = dispatch_queue_create("ly.count.healthtracker.queue", DISPATCH_QUEUE_SERIAL);

        _persistedStateLoaded = NO;
        [self loadPersistedStateIfNeeded];
    }
    return self;
}

/// Adds the counters the previous run stored to the current ones, once the storage can be read, together with the automatically
/// detected crashes it reported. Those are kept with the request queue, since the crash handler must not call into this class.
/// Call from init or on the health tracker queue.
- (void)loadPersistedStateIfNeeded {
    if (self.persistedStateLoaded) {
        return;
    }

    CountlyPersistency *persistency = CountlyPersistency.sharedInstance;
    if (!persistency) {
        return;
    }

    self.persistedStateLoaded = YES;
    [self setupInitialCounters:[persistency retrieveHealthCheckTrackerState]];

    NSUInteger automaticCrashReportCount = [persistency takeAutomaticCrashReportCount];
    if (automaticCrashReportCount > 0) {
        [self addCount:(long)automaticCrashReportCount toUsageOfArea:@"crashes" method:@"record:a"];
        [persistency storeHealthCheckTrackerState:[self currentState]];
    }
}

/// Adds the stored counters to the ones counted so far, which may include warnings logged before the SDK started.
- (void)setupInitialCounters:(NSDictionary *)initialState {
    if (initialState == nil || [initialState count] == 0) {
        return;
    }

    self.countLogWarning += [initialState[keyLogWarning] longValue];
    self.countLogError += [initialState[keyLogError] longValue];
    if (self.statusCode == -1 && initialState[keyStatusCode]) {
        self.statusCode = [initialState[keyStatusCode] integerValue];
    }
    if (self.errorMessage.length == 0) {
        self.errorMessage = initialState[keyErrorMessage] ?: @"";
    }
    self.countBackoffRequest += [initialState[keyBackoffRequest] longValue];
    self.consecutiveBackoffRequest = MAX(self.consecutiveBackoffRequest, [initialState[keyConsecutiveBackoffRequest] longValue]);

    NSDictionary *storedUsage = initialState[keyMethodUsage];
    if ([storedUsage isKindOfClass:NSDictionary.class]) {
        [storedUsage enumerateKeysAndObjectsUsingBlock:^(id area, id methods, BOOL *stop) {
            if (![area isKindOfClass:NSString.class] || ![methods isKindOfClass:NSDictionary.class]) {
                return;
            }
            [(NSDictionary *)methods enumerateKeysAndObjectsUsingBlock:^(id method, id count, BOOL *innerStop) {
                if ([method isKindOfClass:NSString.class] && [count isKindOfClass:NSNumber.class]) {
                    [self addCount:[count longValue] toUsageOfArea:area method:method];
                }
            }];
        }];
    }

    NSDictionary *storedLogCodes = initialState[keyLogCodes];
    if ([storedLogCodes isKindOfClass:NSDictionary.class]) {
        [storedLogCodes enumerateKeysAndObjectsUsingBlock:^(id code, id count, BOOL *stop) {
            if ([code isKindOfClass:NSString.class] && [count isKindOfClass:NSNumber.class]) {
                [self addCount:[count longValue] toLogCode:code];
            }
        }];
    }

    // NOTE: this runs from -init inside the sharedInstance dispatch_once, and CountlyInternalLog
    // calls back into this class for Error and Warning levels. Keep every log on this path at
    // Debug or lower, otherwise the shared instance would be re-entered while being created.
    CLY_LOG_D(@"%s restored persisted counters, errorCount: [%ld], warningCount: [%ld], statusCode: [%ld], errorMessageLength: [%lu], backoffRequestCount: [%ld], consecutiveBackoffRequestCount: [%ld]", __FUNCTION__, self.countLogError, self.countLogWarning, (long)self.statusCode, (unsigned long)self.errorMessage.length, self.countBackoffRequest, self.consecutiveBackoffRequest);
}

- (void)logWarning {
    dispatch_async(self.hcQueue, ^{
        self.countLogWarning++;
    });
}

- (void)logError {
    dispatch_async(self.hcQueue, ^{
        self.countLogError++;
    });
}

- (void)recordUsage:(NSString *)area method:(NSString *)method {
    if (area.length == 0 || method.length == 0 || atomic_load(&s_isRecordingStoppedForCrash)) {
        return;
    }

    dispatch_async(self.hcQueue, ^{
        [self addCount:1 toUsageOfArea:area method:method];
    });
}

- (void)recordLogCode:(NSString *)code {
    if (code.length == 0 || atomic_load(&s_isRecordingStoppedForCrash)) {
        return;
    }

    dispatch_async(self.hcQueue, ^{
        [self addCount:1 toLogCode:code];
    });
}

/// Adds to the count of a method, up to the cap a health check reports. Call from init or on the health tracker queue.
- (void)addCount:(long)count toUsageOfArea:(NSString *)area method:(NSString *)method {
    if (count <= 0) {
        return;
    }

    NSMutableDictionary<NSString *, NSNumber *> *methods = self.methodUsage[area];
    if (!methods) {
        methods = NSMutableDictionary.new;
        self.methodUsage[area] = methods;
    }
    methods[method] = @(MIN([methods[method] longValue] + count, kCountlyHealthCheckCountCap));
}

/// Adds to the count of a log code, up to the cap a health check reports. Call from init or on the health tracker queue.
- (void)addCount:(long)count toLogCode:(NSString *)code {
    if (count <= 0) {
        return;
    }

    self.logCodes[code] = @(MIN([self.logCodes[code] longValue] + count, kCountlyHealthCheckCountCap));
}

/// A copy of the method usage map that later counts do not change. Call from init or on the health tracker queue.
- (NSDictionary *)methodUsageSnapshot {
    NSMutableDictionary *snapshot = NSMutableDictionary.new;
    [self.methodUsage enumerateKeysAndObjectsUsingBlock:^(NSString *area, NSMutableDictionary *methods, BOOL *stop) {
        snapshot[area] = methods.copy;
    }];
    return snapshot.copy;
}

/// The counters in the form they are persisted in. Call from init or on the health tracker queue.
- (NSDictionary *)currentState {
    return @{
        keyLogWarning: @(self.countLogWarning),
        keyLogError: @(self.countLogError),
        keyStatusCode: @(self.statusCode),
        keyErrorMessage: self.errorMessage ?: @"",
        keyBackoffRequest: @(self.countBackoffRequest),
        keyConsecutiveBackoffRequest: @(self.consecutiveBackoffRequest),
        keyMethodUsage: [self methodUsageSnapshot],
        keyLogCodes: self.logCodes.copy
    };
}

- (void)logFailedNetworkRequestWithStatusCode:(NSInteger)statusCode
                                errorResponse:(NSString *)errorResponse {
    if (statusCode <= 0 || statusCode >= 1000 || errorResponse == nil) {
        return;
    }
    
    dispatch_async(self.hcQueue, ^{
        self.statusCode = statusCode;

        if (errorResponse.length > 1000) {
            // copy ensures immutability even if errorResponse was NSMutableString
            self.errorMessage = [errorResponse substringToIndex:1000];
        } else {
            self.errorMessage = [errorResponse copy];
        }
        CLY_LOG_D(@"%s recorded failed network request, statusCode: [%ld], errorResponseLength: [%lu], storedErrorMessageLength: [%lu]", __FUNCTION__, (long)statusCode, (unsigned long)errorResponse.length, (unsigned long)self.errorMessage.length);
    });
}

- (void)logBackoffRequest {
    dispatch_async(self.hcQueue, ^{
        self.countBackoffRequest++;
        self.countConsecutiveBackoffRequest++;
        CLY_LOG_D(@"%s recorded a backed off request, backoffRequestCount: [%ld], currentConsecutiveBackoffRequestCount: [%ld]", __FUNCTION__, self.countBackoffRequest, self.countConsecutiveBackoffRequest);
    });
}

- (void)logConsecutiveBackoffRequest {
    dispatch_async(self.hcQueue, ^{
        self.consecutiveBackoffRequest = MAX(self.consecutiveBackoffRequest, self.countConsecutiveBackoffRequest);
        self.countConsecutiveBackoffRequest = 0;
        CLY_LOG_D(@"%s consecutive backoff streak closed, peakConsecutiveBackoffRequestCount: [%ld]", __FUNCTION__, self.consecutiveBackoffRequest);
    });
}

- (void)clearAndSave {
    dispatch_async(self.hcQueue, ^{
        [self clearValues];
        [CountlyPersistency.sharedInstance storeHealthCheckTrackerState:@{}];
        CLY_LOG_D(@"%s counters cleared and empty state persisted", __FUNCTION__);
    });
}

- (void)saveState {
    dispatch_async(self.hcQueue, ^{
        [self loadPersistedStateIfNeeded];
        [self logConsecutiveBackoffRequest];

        [CountlyPersistency.sharedInstance storeHealthCheckTrackerState:[self currentState]];
        CLY_LOG_D(@"%s counters persisted, errorCount: [%ld], warningCount: [%ld], statusCode: [%ld], errorMessageLength: [%lu], backoffRequestCount: [%ld], peakConsecutiveBackoffRequestCount: [%ld]", __FUNCTION__, self.countLogError, self.countLogWarning, (long)self.statusCode, (unsigned long)self.errorMessage.length, self.countBackoffRequest, self.consecutiveBackoffRequest);
    });
}

- (void)resetInstance {
    CountlyHealthTrackerResumeRecordingAfterCrash();

    // synchronous: halt goes on to free the shared state this block uses, and nothing on hcQueue waits for the caller
    dispatch_sync(self.hcQueue, ^{
        [self clearValues];
        self->_healthCheckSent = NO;
        self->_healthCheckEnabled = YES;
        self->_persistedStateLoaded = YES;
        [CountlyPersistency.sharedInstance storeHealthCheckTrackerState:@{}];
        CLY_LOG_D(@"%s health tracker reset, healthCheckSent and healthCheckEnabled restored to their initial values", __FUNCTION__);
    });
}

- (void)clearValues {
    // NOTE: Debug on purpose. A Warning or Error here would be counted by CountlyInternalLog
    // through logWarning/logError and would immediately repopulate the counters being cleared.
    CLY_LOG_D(@"%s clearing counters, discardedErrorCount: [%ld], discardedWarningCount: [%ld], discardedBackoffRequestCount: [%ld]", __FUNCTION__, self.countLogError, self.countLogWarning, self.countBackoffRequest);

    self.countLogWarning = 0;
    self.countLogError = 0;
    self.statusCode = -1;
    self.errorMessage = @"";
    self.countBackoffRequest = 0;
    self.consecutiveBackoffRequest = 0;
    self.countConsecutiveBackoffRequest = 0;
    [self.methodUsage removeAllObjects];
    [self.logCodes removeAllObjects];
}

/// Takes away what a health check the server accepted reported, so what was counted while it was on the way is reported next time.
/// The last failed request and the consecutive backoff peak are only cleared when they did not change since the report.
- (void)clearSentValues:(NSDictionary *)sent {
    dispatch_async(self.hcQueue, ^{
        self.countLogError = MAX(0, self.countLogError - [sent[requestKeyErrorCount] longValue]);
        self.countLogWarning = MAX(0, self.countLogWarning - [sent[requestKeyWarningCount] longValue]);
        self.countBackoffRequest = MAX(0, self.countBackoffRequest - [sent[requestKeyBackoffRequest] longValue]);

        if (self.consecutiveBackoffRequest == [sent[requestKeyConsecutiveBackoffRequest] longValue]) {
            self.consecutiveBackoffRequest = 0;
        }

        if (self.statusCode == [sent[requestKeyStatusCode] integerValue] && [self.errorMessage isEqualToString:sent[requestKeyRequestError] ?: @""]) {
            self.statusCode = -1;
            self.errorMessage = @"";
        }

        NSDictionary *sentUsage = sent[requestKeyMethodUsage];
        [sentUsage enumerateKeysAndObjectsUsingBlock:^(NSString *area, NSDictionary *methods, BOOL *stop) {
            NSMutableDictionary<NSString *, NSNumber *> *counted = self.methodUsage[area];
            [methods enumerateKeysAndObjectsUsingBlock:^(NSString *method, NSNumber *count, BOOL *innerStop) {
                long left = [counted[method] longValue] - count.longValue;
                counted[method] = left > 0 ? @(left) : nil;
            }];
            if (counted.count == 0) {
                [self.methodUsage removeObjectForKey:area];
            }
        }];

        NSDictionary *sentLogCodes = sent[requestKeyLogCodes];
        [sentLogCodes enumerateKeysAndObjectsUsingBlock:^(NSString *code, NSNumber *count, BOOL *stop) {
            long left = [self.logCodes[code] longValue] - count.longValue;
            self.logCodes[code] = left > 0 ? @(left) : nil;
        }];

        [CountlyPersistency.sharedInstance storeHealthCheckTrackerState:[self currentState]];
        CLY_LOG_D(@"%s reported counters taken away, errorCount left: [%ld], warningCount left: [%ld], usage areas left: [%lu], log codes left: [%lu]", __FUNCTION__, self.countLogError, self.countLogWarning, (unsigned long)self.methodUsage.count, (unsigned long)self.logCodes.count);
    });
}

- (void)sendHealthCheck {
    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary) {
        CLY_LOG_D(@"%s health check send skipped, sdk is in temporary device ID mode", __FUNCTION__);
        return;
    }

    if (!CountlyServerConfig.sharedInstance.networkingEnabled)
    {
        CLY_LOG_D(@"%s health check send skipped, networking is disabled by behavior settings", __FUNCTION__);
        return;
    }

    if (!_healthCheckEnabled || _healthCheckSent) {
        CLY_LOG_D(@"%s health check send skipped, healthCheckSent: [%@], healthCheckEnabled: [%@]", __FUNCTION__, _healthCheckSent ? @"YES" : @"NO", _healthCheckEnabled ? @"YES" : @"NO");
        return;
    }

    NSDictionary* healthCheck = [self healthCheckSnapshot];
    NSURLSessionTask* task = [CountlyCommon.sharedInstance immediateDataTaskWithRequest:[self healthCheckRequestWithHealthCheck:healthCheck] completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
    {
        // IMMEDIATE REQUEST to find them better in search
        if (error)
        {
            CLY_LOG_D(@"%s health check request failed at the transport level, it will be retried later, error: [%@]", __FUNCTION__, error.localizedDescription);
            return;
        }

        NSError *jsonError;
        NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];

        if (jsonError || ![jsonResponse isKindOfClass:NSDictionary.class]) {
            CLY_LOG_E(@"%s could not parse the health check response, counters will not be cleared, error: [%@]", __FUNCTION__, jsonError.localizedDescription);
            return;
        }

        if (!jsonResponse[@"result"]) {
            CLY_LOG_D(@"%s health check response does not carry the expected result key, counters will not be cleared, responseKeyCount: [%lu]", __FUNCTION__, (unsigned long)jsonResponse.count);
            return;
        }

        CLY_LOG_D(@"%s health check accepted by the server, the reported counters will be cleared", __FUNCTION__);
        [self clearSentValues:healthCheck];
        self->_healthCheckSent = YES;
    }];

    [task resume];
}

/// The health check parameter as it is sent, taken from the current counters. "fu" and "lc" are always present, empty when
/// nothing was counted, so the server can tell an SDK that reports them from one that does not.
- (NSDictionary *)healthCheckSnapshot {
    __block NSDictionary *healthCheck;
    dispatch_sync(self.hcQueue, ^{
        [self loadPersistedStateIfNeeded];
        healthCheck = @{
            requestKeyErrorCount: @(self.countLogError),
            requestKeyWarningCount: @(self.countLogWarning),
            requestKeyStatusCode: @(self.statusCode),
            requestKeyRequestError: [self.errorMessage copy] ?: @"",
            requestKeyBackoffRequest: @(self.countBackoffRequest),
            requestKeyConsecutiveBackoffRequest: @(self.consecutiveBackoffRequest),
            requestKeyMethodUsage: [self methodUsageSnapshot],
            requestKeyLogCodes: self.logCodes.copy
        };
    });
    return healthCheck;
}

/// The health check request for the current counters.
- (NSURLRequest *)healthCheckRequest {
    return [self healthCheckRequestWithHealthCheck:[self healthCheckSnapshot]];
}

/// The health check request carrying the given health check parameter.
- (NSURLRequest *)healthCheckRequestWithHealthCheck:(NSDictionary *)healthCheck {
    NSString *queryString = [CountlyConnectionManager.sharedInstance queryEssentials];

    // fully escaped, as the error message is a server response that can hold '&', '=' or '+'
    queryString = [queryString stringByAppendingFormat:@"&%@=%@", @"hc", [healthCheck cly_JSONify]];
    queryString = [queryString stringByAppendingFormat:@"&%@=%@", @"metrics", [@{CLYMetricKeyAppVersion: CountlyDeviceInfo.appVersion} cly_JSONify]];

    queryString = [CountlyConnectionManager.sharedInstance appendChecksum:queryString];
    NSString* hcSendURL = [CountlyConnectionManager.sharedInstance.host stringByAppendingFormat:@"%@",kCountlyEndpointI];
    
    CLY_LOG_I(@"%s sending health check request, errorCount: [%@], warningCount: [%@], statusCode: [%@], errorMessageLength: [%lu], backoffRequestCount: [%@], consecutiveBackoffRequestCount: [%@], usageAreaCount: [%lu], logCodeCount: [%lu]", __FUNCTION__, healthCheck[requestKeyErrorCount], healthCheck[requestKeyWarningCount], healthCheck[requestKeyStatusCode], (unsigned long)[healthCheck[requestKeyRequestError] length], healthCheck[requestKeyBackoffRequest], healthCheck[requestKeyConsecutiveBackoffRequest], (unsigned long)[healthCheck[requestKeyMethodUsage] count], (unsigned long)[healthCheck[requestKeyLogCodes] count]);

    if (queryString.length > kCountlyGETRequestMaxLength || CountlyConnectionManager.sharedInstance.alwaysUsePOST)
    {
        CLY_LOG_D(@"%s health check request prepared as POST, queryLength: [%lu]", __FUNCTION__, (unsigned long)queryString.length);
        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:hcSendURL]];
        request.HTTPMethod = @"POST";
        request.HTTPBody = [queryString cly_dataUTF8];
        return request.copy;
    }
    else
    {
        CLY_LOG_D(@"%s health check request prepared as GET, queryLength: [%lu]", __FUNCTION__, (unsigned long)queryString.length);
        NSString* withQueryString = [hcSendURL stringByAppendingFormat:@"?%@", queryString];
        NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:withQueryString]];
        return request;
    }
}
@end
