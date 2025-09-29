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

    CLY_LOG_D(@"%s loaded initial health check state: [%@]", __FUNCTION__, initialState);
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
        CLY_LOG_D(@"%s statusCode: [%d], errorResponse: [%@]", __FUNCTION__, (int)statusCode, errorResponse);
    });
}

- (void)logBackoffRequest {
    CLY_LOG_D(@"%s", __FUNCTION__);
    dispatch_async(self.hcQueue, ^{
        self.countBackoffRequest++;
        self.countConsecutiveBackoffRequest++;
    });
}

- (void)logConsecutiveBackoffRequest {
    CLY_LOG_D(@"%s", __FUNCTION__);
    dispatch_async(self.hcQueue, ^{
        self.consecutiveBackoffRequest = MAX(self.consecutiveBackoffRequest, self.countConsecutiveBackoffRequest);
        self.countConsecutiveBackoffRequest = 0;
    });
}

- (void)clearAndSave {
    CLY_LOG_D(@"%s", __FUNCTION__);
    dispatch_async(self.hcQueue, ^{
        [self clearValues];
        [CountlyPersistency.sharedInstance storeHealthCheckTrackerState:@{}];
    });
}

- (void)saveState {
    CLY_LOG_D(@"%s", __FUNCTION__);
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
    });
}

- (void)clearValues {
    CLY_LOG_W(@"%s clearing counters", __FUNCTION__);

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
        CLY_LOG_W(@"%s currently in temporary id mode, omitting", __FUNCTION__);
    }
    
    if (!CountlyServerConfig.sharedInstance.networkingEnabled)
    {
        CLY_LOG_D(@"%s 'sendHealthCheck' is aborted: SDK Networking is disabled from server config!", __FUNCTION__);
        return;
    }
    
    if (!_healthCheckEnabled || _healthCheckSent) {
        CLY_LOG_D(@"%s health check status, healthCheckSent: [%d], healthCheckEnabled: [%d]", __FUNCTION__, _healthCheckSent, _healthCheckEnabled);
    }
    
    NSURLSessionTask* task = [CountlyCommon.sharedInstance.URLSession dataTaskWithRequest:[self healthCheckRequest] completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
    {
        if (error)
        {
            CLY_LOG_W(@"%s error while sending health checks error: [%@]", __FUNCTION__, error);
            return;
        }
        
        NSError *jsonError;
        NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        
        if (jsonError || !jsonResponse) {
            CLY_LOG_I(@"%s error while sending health checks, Failed to parse JSON response error: [%@]", __FUNCTION__, jsonError);
            return;
        }
        
        if (!jsonResponse[@"result"]) {
            CLY_LOG_D(@"%s Retrieved request response does not match expected pattern response: [%@]", __FUNCTION__, jsonResponse);
            return;
        }
        
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
        CLY_LOG_W(@"%s failed to create json for hc request error: [%@]", __FUNCTION__, error);
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
    
    CLY_LOG_D(@"%s generated health check request: [%@]", __FUNCTION__, queryString);

    if (queryString.length > kCountlyGETRequestMaxLength || CountlyConnectionManager.sharedInstance.alwaysUsePOST)
    {
        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:hcSendURL]];
        request.HTTPMethod = @"POST";
        request.HTTPBody = [queryString cly_dataUTF8];
        return request.copy;
    }
    else
    {
        NSString* withQueryString = [hcSendURL stringByAppendingFormat:@"?%@", queryString];
        NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:withQueryString]];
        return request;
    }
}
@end
