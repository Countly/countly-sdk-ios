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
@property (nonatomic, assign) NSInteger statusCode;
@property (nonatomic, strong) NSString *errorMessage;

@end

@implementation CountlyHealthTracker

NSString * const keyLogError = @"LErr";
NSString * const keyLogWarning = @"LWar";
NSString * const keyStatusCode = @"RStatC";
NSString * const keyErrorMessage = @"REMsg";
NSString * const keyBackoffRequest = @"BReq";

NSString * const requestKeyErrorCount = @"el";
NSString * const requestKeyWarningCount = @"wl";
NSString * const requestKeyStatusCode = @"sc";
NSString * const requestKeyRequestError = @"em";
NSString * const requestKeyBackoffRequest = @"br";

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

        NSDictionary *initialState = [CountlyPersistency.sharedInstance retrieveHealtCheckTrackerState];
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

- (void)logSessionStartedWhileRunning {}
- (void)logSessionEndedWhileNotRunning {}
- (void)logSessionUpdatedWhileNotRunning {}

- (void)logBackoffRequest {
    self.countBackoffRequest++;
}

- (void)clearAndSave {
    [self clearValues];
    [CountlyPersistency.sharedInstance storeHealtCheckTrackerState:@{}];
}

- (void)saveState {
    NSDictionary *healtCheckState = @{
        keyLogWarning: @(self.countLogWarning),
        keyLogError: @(self.countLogError),
        keyStatusCode: @(self.statusCode),
        keyErrorMessage: self.errorMessage ?: @"",
        keyBackoffRequest: @(self.countBackoffRequest)
    };
    
    [CountlyPersistency.sharedInstance storeHealtCheckTrackerState:healtCheckState];
}

- (void)clearValues {
    CLY_LOG_W(@"%s, Clearing counters", __FUNCTION__);

    self.countLogWarning = 0;
    self.countLogError = 0;
    self.statusCode = -1;
    self.errorMessage = @"";
    self.countBackoffRequest = 0;
}

- (NSString *)createRequestParam {
    NSMutableString *sb = [NSMutableString stringWithString:@"&hc="];

    NSDictionary *json = @{
        requestKeyErrorCount: @(self.countLogError),
        requestKeyWarningCount: @(self.countLogWarning),
        requestKeyStatusCode: @(self.statusCode),
        requestKeyRequestError: self.errorMessage ?: @"",
        requestKeyBackoffRequest: @(self.countBackoffRequest)
    };

    NSError *error;
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:0 error:&error];
    NSString *encodedData = @"";

    if (!error && data) {
        NSString *jsonString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        encodedData = [jsonString stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
    } else {
        CLY_LOG_W(@"%s, Failed to create param for hc request, %@", __FUNCTION__, error);
    }

    [sb appendString:encodedData];
    return sb;
}

@end
