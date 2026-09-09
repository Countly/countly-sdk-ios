//
//  CountlyHealthTracker.m
//  CountlyTestApp-iOS
//
//  Created by Arif Burak Demiray on 20.05.2025.
//  Copyright © 2025 Countly. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CountlyHealthTracker.h"
#import "CountlyCommon.h"

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

@property (nonatomic, strong) dispatch_queue_t hcQueue;
@end

@implementation CountlyHealthTracker

NSString * const keyLogError = @"LErr";
NSString * const keyLogWarning = @"LWar";
NSString * const keyStatusCode = @"RStatC";
NSString * const keyErrorMessage = @"REMsg";
NSString * const keyBackoffRequest = @"BReq";
NSString * const keyConsecutiveBackoffRequest = @"CBReq";

NSString * const requestKeyErrorCount = @"el";
NSString * const requestKeyWarningCount = @"wl";
NSString * const requestKeyStatusCode = @"sc";
NSString * const requestKeyRequestError = @"em";
NSString * const requestKeyBackoffRequest = @"bom";
NSString * const requestKeyConsecutiveBackoffRequest = @"cbom";

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

        // queue for health tracker state
        _hcQueue = dispatch_queue_create("ly.count.healthtracker.queue", DISPATCH_QUEUE_SERIAL);

        NSDictionary *initialState = [CountlyPersistency.sharedInstance retrieveHealthCheckTrackerState];
        [self setupInitialCounters:initialState];
    }
    return self;
}

- (void)setupInitialCounters:(NSDictionary *)initialState {
    if (initialState == nil || [initialState count] == 0) {
        return;
    }

    self.countLogWarning = [initialState[keyLogWarning] longValue];
    self.countLogError = [initialState[keyLogError] longValue];
    self.statusCode = [initialState[keyStatusCode] integerValue];
    self.errorMessage = initialState[keyErrorMessage] ?: @"";
    self.countBackoffRequest = [initialState[keyBackoffRequest] longValue];
    self.consecutiveBackoffRequest = [initialState[keyConsecutiveBackoffRequest] longValue];

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
        [self logConsecutiveBackoffRequest];

        NSDictionary *healthCheckState = @{
            keyLogWarning: @(self.countLogWarning),
            keyLogError: @(self.countLogError),
            keyStatusCode: @(self.statusCode),
            keyErrorMessage: self.errorMessage ?: @"",
            keyBackoffRequest: @(self.countBackoffRequest),
            keyConsecutiveBackoffRequest: @(self.consecutiveBackoffRequest)
        };

        [CountlyPersistency.sharedInstance storeHealthCheckTrackerState:healthCheckState];
        CLY_LOG_D(@"%s counters persisted, errorCount: [%ld], warningCount: [%ld], statusCode: [%ld], errorMessageLength: [%lu], backoffRequestCount: [%ld], peakConsecutiveBackoffRequestCount: [%ld]", __FUNCTION__, self.countLogError, self.countLogWarning, (long)self.statusCode, (unsigned long)self.errorMessage.length, self.countBackoffRequest, self.consecutiveBackoffRequest);
    });
}

- (void)resetInstance {
    dispatch_async(self.hcQueue, ^{
        [self clearValues];
        self->_healthCheckSent = NO;
        self->_healthCheckEnabled = YES;
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

    NSURLSessionTask* task = [CountlyCommon.sharedInstance.ImmediateURLSession dataTaskWithRequest:[self healthCheckRequest] completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
    {
        // IMMEDIATE REQUEST to find them better in search
        if (error)
        {
            CLY_LOG_D(@"%s health check request failed at the transport level, it will be retried later, error: [%@]", __FUNCTION__, error.localizedDescription);
            return;
        }

        NSError *jsonError;
        NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];

        if (jsonError || !jsonResponse) {
            CLY_LOG_E(@"%s could not parse the health check response, counters will not be cleared, error: [%@]", __FUNCTION__, jsonError.localizedDescription);
            return;
        }

        if (!jsonResponse[@"result"]) {
            CLY_LOG_D(@"%s health check response does not carry the expected result key, counters will not be cleared, responseKeyCount: [%lu]", __FUNCTION__, (unsigned long)jsonResponse.count);
            return;
        }

        CLY_LOG_D(@"%s health check accepted by the server, counters will be cleared", __FUNCTION__);
        [self clearAndSave];
        self->_healthCheckSent = YES;
    }];

    [task resume];
}

- (NSString *)dictionaryToJsonString:(NSDictionary *)json {
    NSError *error;
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:&error];
    NSString *encodedData = @"";

    if (!error && data) {
        NSString *jsonString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        encodedData = [jsonString stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    } else {
        CLY_LOG_E(@"%s could not build the json payload for the health check request, an empty value will be sent, keyCount: [%lu], error: [%@]", __FUNCTION__, (unsigned long)json.count, error.localizedDescription);
    }

    return encodedData;
}

- (NSURLRequest *)healthCheckRequest {
    __block long snapshotLogError;
    __block long snapshotLogWarning;
    __block NSInteger snapshotStatusCode;
    __block NSString *snapshotErrorMessage;
    __block long snapshotBackoffRequest;
    __block long snapshotConsecutiveBackoffRequest;

    dispatch_sync(self.hcQueue, ^{
        snapshotLogError = self.countLogError;
        snapshotLogWarning = self.countLogWarning;
        snapshotStatusCode = self.statusCode;
        snapshotErrorMessage = [self.errorMessage copy] ?: @"";
        snapshotBackoffRequest = self.countBackoffRequest;
        snapshotConsecutiveBackoffRequest = self.consecutiveBackoffRequest;
    });

    NSString *queryString = [CountlyConnectionManager.sharedInstance queryEssentials];

    queryString = [queryString stringByAppendingFormat:@"&%@=%@", @"hc", [self dictionaryToJsonString:@{
        requestKeyErrorCount: @(snapshotLogError),
        requestKeyWarningCount: @(snapshotLogWarning),
        requestKeyStatusCode: @(snapshotStatusCode),
        requestKeyRequestError: snapshotErrorMessage,
        requestKeyBackoffRequest: @(snapshotBackoffRequest),
        requestKeyConsecutiveBackoffRequest: @(snapshotConsecutiveBackoffRequest)
    }]];
    
    queryString = [queryString stringByAppendingFormat:@"&%@=%@", @"metrics", [self dictionaryToJsonString:@{
        CLYMetricKeyAppVersion: CountlyDeviceInfo.appVersion
     }]];


    queryString = [CountlyConnectionManager.sharedInstance appendChecksum:queryString];
    NSString* hcSendURL = [CountlyConnectionManager.sharedInstance.host stringByAppendingFormat:@"%@",kCountlyEndpointI];
    
    CLY_LOG_I(@"%s sending health check request, errorCount: [%ld], warningCount: [%ld], statusCode: [%ld], errorMessageLength: [%lu], backoffRequestCount: [%ld], consecutiveBackoffRequestCount: [%ld]", __FUNCTION__, snapshotLogError, snapshotLogWarning, (long)snapshotStatusCode, (unsigned long)snapshotErrorMessage.length, snapshotBackoffRequest, snapshotConsecutiveBackoffRequest);

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
