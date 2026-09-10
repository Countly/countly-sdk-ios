// CountlyConnectionTest.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString* const kCountlyCTErrorTimeout;
extern NSString* const kCountlyCTErrorTransport;
extern NSString* const kCountlyCTErrorRedirected;
extern NSString* const kCountlyCTErrorNotRun;
extern NSString* const kCountlyCTErrorOpaque;

/// Server armed connection test: a top level 'ct' on a live behavior settings response runs one battery of
/// parameterless GET probes and queues one 'ct_results' report. Nothing about it is persisted.
@interface CountlyConnectionTest : NSObject <NSURLSessionTaskDelegate>

+ (instancetype)sharedInstance;
- (void)resetInstance;

/// Deadline of a single probe request, in seconds. Exposed so tests can shrink it.
@property (nonatomic) NSTimeInterval perRequestTimeout;
/// Slack added to the battery cap on top of the per request deadlines, in seconds. Exposed so tests can shrink it.
@property (nonatomic) NSTimeInterval batteryCapExtra;
/// YES while a battery is in flight. A second delivery meanwhile is ignored.
@property (nonatomic, readonly) BOOL isBatteryRunning;

/// Runs the battery on a background queue, once per delivery, and queues the report. scLatencyMs is the wall clock
/// of the behavior settings fetch that delivered the flag, negative when unknown.
- (void)startBatteryWithServerConfigLatency:(long long)scLatencyMs;

/// Resolves a probe path against the configured server URL, path prefix included, and appends the marker and cache buster.
+ (NSString *)probeURLForPath:(NSString *)path serverURL:(NSString *)serverURL;

/// Grades one probe outcome. Returns nil when the Countly application answered, otherwise the 'e' reason.
+ (nullable NSString *)gradeStatus:(NSInteger)status failure:(nullable NSString *)failure requiresSuccessStatus:(BOOL)requiresSuccessStatus;

/// Builds the 'ct_results' JSON from graded rows, enforcing the row, byte and 'e' length caps.
- (NSString *)buildReport:(NSArray<NSDictionary *> *)rows;

@end

NS_ASSUME_NONNULL_END
