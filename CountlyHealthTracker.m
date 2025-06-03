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
@property (nonatomic, strong) NSString *errorMessage;
@property (nonatomic, assign) BOOL healthCheckEnabled;
@property (nonatomic, assign) BOOL healthCheckSent;

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

    CLY_LOG_D(@"%s, Loaded initial health check state: [%@]", __FUNCTION__, initialState);
}

- (void)logWarning {
    self.countLogWarning++;
}

- (void)logError {
    self.countLogError++;
}

- (void)logFailedNetworkRequestWithStatusCode:(NSInteger)statusCode
                                errorResponse:(NSString *)errorResponse {
    if (statusCode <= 0 || statusCode >= 1000 || errorResponse == nil) {
        return;
    }

    self.statusCode = statusCode;
    if (errorResponse.length > 1000) {
        self.errorMessage = [errorResponse substringToIndex:1000];
    } else {
        self.errorMessage = errorResponse;
    }
}

- (void)logBackoffRequest {
    self.countBackoffRequest++;
    self.countConsecutiveBackoffRequest++;
}

- (void)logConsecutiveBackoffRequest {
    self.consecutiveBackoffRequest = MAX(self.consecutiveBackoffRequest, self.countConsecutiveBackoffRequest);
    self.countConsecutiveBackoffRequest = 0;
}

- (void)clearAndSave {
    [self clearValues];
    [CountlyPersistency.sharedInstance storeHealthCheckTrackerState:@{}];
}

- (void)saveState {
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
}

- (void)clearValues {
    CLY_LOG_W(@"%s, Clearing counters", __FUNCTION__);

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
        CLY_LOG_W(@"%s, currently in temporary id mode, omitting", __FUNCTION__);
    }
    
    if (!_healthCheckEnabled || _healthCheckSent) {
        CLY_LOG_D(@"%s, health check status, sent: %d, not_enabled: %d", __FUNCTION__, _healthCheckSent, _healthCheckEnabled);
    }
    
    NSURLSessionTask* task = [CountlyCommon.sharedInstance.URLSession dataTaskWithRequest:[self healthCheckRequest] completionHandler:^(NSData* data, NSURLResponse* response, NSError* error)
    {
        if (error)
        {
            CLY_LOG_W(@"%s, error while sending health checks error: %@", __FUNCTION__, error);
            return;
        }
        
        NSError *jsonError;
        NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        
        if (jsonError || !jsonResponse) {
            CLY_LOG_I(@"%s, error while sending health checks, Failed to parse JSON response: %@", __FUNCTION__, jsonError);
            return;
        }
        
        if (!jsonResponse[@"result"]) {
            CLY_LOG_D(@"%s, Retrieved request response does not match expected pattern %@", __FUNCTION__, jsonResponse);
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
        CLY_LOG_W(@"%s, Failed to create json for hc request, %@", __FUNCTION__, error);
    }

    return encodedData;
}

- (NSURLRequest *)healthCheckRequest {
    NSString *queryString = [CountlyConnectionManager.sharedInstance queryEssentials];

    queryString = [queryString stringByAppendingFormat:@"&%@=%@", @"hc", [self dictionaryToJsonString:@{
        requestKeyErrorCount: @(self.countLogError),
        requestKeyWarningCount: @(self.countLogWarning),
        requestKeyStatusCode: @(self.statusCode),
        requestKeyRequestError: self.errorMessage ?: @"",
        requestKeyBackoffRequest: @(self.countBackoffRequest),
        requestKeyConsecutiveBackoffRequest: @(self.consecutiveBackoffRequest)
    }]];
    
    queryString = [queryString stringByAppendingFormat:@"&%@=%@", @"metrics", [self dictionaryToJsonString:@{
        kCountlyAppVersionKey: CountlyDeviceInfo.appVersion
    }]];

    queryString = [CountlyConnectionManager.sharedInstance appendChecksum:queryString];
    NSString* hcSendURL = [CountlyConnectionManager.sharedInstance.host stringByAppendingFormat:@"%@",kCountlyEndpointI];
    
    CLY_LOG_D(@"%s, generated health check request: %@", __FUNCTION__, queryString);

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
