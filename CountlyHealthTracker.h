//
//  CountlyHealthTracker.h
//  CountlyTestApp-iOS
//
//  Created by Arif Burak Demiray on 20.05.2025.
//  Copyright © 2025 Countly. All rights reserved.
//
#import <Foundation/Foundation.h>

@interface CountlyHealthTracker : NSObject

+ (instancetype)sharedInstance;

- (void)logWarning;

- (void)logError;

- (void)logFailedNetworkRequestWithStatusCode:(NSInteger)statusCode
                                errorResponse:(NSString *)errorResponse;

- (void)logBackoffRequest;

- (void)logConsecutiveBackoffRequest;

- (void)clearAndSave;

- (void)saveState;

- (void)sendHealthCheck;

/// Counts one call of a public SDK method for the health check "fu" map, under its feature area ("sessions", "events", "views",
/// "crashes") and method name. A method the SDK called by itself carries the ":a" suffix, for example "begin:a".
- (void)recordUsage:(NSString *)area method:(NSString *)method;

/// Counts one occurrence of an SDK log code for the health check "lc" map, a level letter and three digits such as "w740".
- (void)recordLogCode:(NSString *)code;

// Exposed for testing purposes only.
- (void)resetInstance;

@end

/// Makes recordUsage:method: and recordLogCode: ignore every call until crash reporting starts again or the SDK is halted, so
/// reporting an automatically detected crash, which can run in a signal handler, never queues work on the health tracker. Async signal safe.
void CountlyHealthTrackerStopRecordingForCrash(void);
/// Lifts CountlyHealthTrackerStopRecordingForCrash once crash reporting starts again, since the app can outlive a reported crash
/// through a handler of its own.
void CountlyHealthTrackerResumeRecordingAfterCrash(void);
