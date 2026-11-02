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

/// Keeps the status code and the body of the last queued request the server answered with a failure, the body cut to 1000
/// characters. A body that is not UTF-8 text arrives as nil and is kept as an empty message, so its status code is still reported.
- (void)logFailedNetworkRequestWithStatusCode:(NSInteger)statusCode
                                errorResponse:(NSString *)errorResponse;

- (void)logBackoffRequest;

- (void)logConsecutiveBackoffRequest;

- (void)clearAndSave;

- (void)saveState;

- (void)sendHealthCheck;

/// Stops the health check request for the lifetime of the SDK instance, as the developer asked for in the configuration. The
/// counters keep counting, since the other modules keep reporting to the health tracker.
- (void)disableHealthCheck;

/// Counts one call of a public SDK method for the health check "fu" map, under its feature area ("sessions", "events", "views",
/// "crashes") and method name. A method the SDK called by itself carries the ":a" suffix, for example "begin:a". Nothing is
/// counted while the area's feature has no consent.
- (void)recordUsage:(NSString *)area method:(NSString *)method;

/// Counts one occurrence of an SDK log code for the health check "lc" map, a level letter and three digits such as "w740".
- (void)recordLogCode:(NSString *)code;

/// Counts several occurrences of an SDK log code at once, for a condition that several items met together, such as old
/// requests dropped from the queue in one go.
- (void)recordLogCode:(NSString *)code count:(NSUInteger)count;

/// Counts one occurrence of a log code that a public method of a feature area records, like recordUsage:method:, so nothing
/// is counted while the area's feature has no consent.
- (void)recordLogCode:(NSString *)code forUsageArea:(NSString *)area;

// Exposed for testing purposes only.
- (void)resetInstance;

@end

/// Makes recordUsage:method: and every recordLogCode: variant ignore every call until crash reporting starts again or the SDK is halted, so
/// reporting an automatically detected crash, which can run in a signal handler, never queues work on the health tracker. Async signal safe.
void CountlyHealthTrackerStopRecordingForCrash(void);
/// Lifts CountlyHealthTrackerStopRecordingForCrash once crash reporting starts again, since the app can outlive a reported crash
/// through a handler of its own.
void CountlyHealthTrackerResumeRecordingAfterCrash(void);
