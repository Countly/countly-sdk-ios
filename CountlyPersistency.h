// CountlyPersistency.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>
#import "CountlyConnectionManager.h"

@class CountlyEvent;

@interface CountlyPersistency : NSObject <Resettable>

+ (instancetype)sharedInstance;
/// Whether the queued request is a gathered log upload.
+ (BOOL)isSdkLogRequest:(NSString *)queryString;
/// Removes the values the SDK keeps in the standard user defaults, also those older SDK versions kept, since every one of them carries the "kCountly" prefix. The app's own values stay, and so does the PLCrashReporter suppression marker, so a crash between halt and the next start is still discarded.
+ (void)removeStoredUserDefaults;

/// Appends a request to the queue. Returns NO when it was refused: tracking is disabled by server config, or the request is empty.
- (BOOL)addToQueue:(NSString *)queryString;
- (void)removeFromQueue:(NSString *)queryString;
- (NSString *)firstItemInQueue;
/// Whether a gathered log upload waits in the request queue.
- (BOOL)queueContainsSdkLogs;
- (void)flushQueue;
- (NSUInteger)remainingRequestCount;
- (void)replaceAllTemporaryDeviceIDsInQueueWithDeviceID:(NSString *)deviceID;
- (void)replaceAllAppKeysInQueueWithCurrentAppKey;
- (void)removeDifferentAppKeysFromQueue;
- (void)removeOldAgeRequestsFromQueue;

- (void)recordEvent:(CountlyEvent *)event;
- (void)recordEvent:(CountlyEvent *)event callback:(CLYRequestCallback)callback;
- (NSString *)serializedRecordedEvents;
- (void)flushEvents;

- (void)recordTimedEvent:(CountlyEvent *)event;
- (CountlyEvent *)timedEventForKey:(NSString *)key;
- (void)clearAllTimedEvents;

- (void)writeCustomCrashLogToFile:(NSString *)log;
- (NSString *)customCrashLogsFromFile;
- (void)deleteCustomCrashLogFile;

- (void)saveToFile;
- (void)saveToFileSync;

- (NSString *)retrieveDeviceID;
- (void)storeDeviceID:(NSString *)deviceID;

- (NSString *)retrieveNSUUID;
- (void)storeNSUUID:(NSString *)UUID;

- (NSString *)retrieveWatchParentDeviceID;
- (void)storeWatchParentDeviceID:(NSString *)deviceID;

- (NSDictionary *)retrieveStarRatingStatus;
- (void)storeStarRatingStatus:(NSDictionary *)status;

- (BOOL)retrieveNotificationPermission;
- (void)storeNotificationPermission:(BOOL)allowed;

- (BOOL)retrieveIsCustomDeviceID;
- (void)storeIsCustomDeviceID:(BOOL)isCustomDeviceID;

- (NSDictionary *)retrieveRemoteConfig;
- (void)storeRemoteConfig:(NSDictionary *)remoteConfig;

- (NSMutableDictionary *)retrieveServerConfig;
- (void)storeServerConfig:(NSMutableDictionary *)serverConfig;

- (NSDictionary *)retrieveHealthCheckTrackerState;
- (void)storeHealthCheckTrackerState:(NSDictionary *)healthCheckTrackerState;

/// Counts an automatically detected crash the SDK reports, for the health check. Kept in memory and written with the request queue
/// by the save the crash report itself makes, so the crash handler, which can run in a signal handler, needs no other write. Never logs.
- (void)recordAutomaticCrashReport;
/// The automatically detected crashes counted since the last call, also those the previous run stored, and starts counting from zero.
- (NSUInteger)takeAutomaticCrashReportCount;

/// When automatic crash capture stopped being wanted while PLCrashReporter stays installed, or nil while it is wanted.
- (NSDate *)retrievePLCrashCaptureSuppressedSince;
/// Stores when automatic crash capture stopped being wanted, nil clears it.
- (void)storePLCrashCaptureSuppressedSince:(NSDate *)date;

-(BOOL)isOldRequest:(NSString*) queryString;

@property (nonatomic) NSUInteger eventSendThreshold;
@property (nonatomic) NSUInteger storedRequestsLimit;
@property (nonatomic) NSUInteger requestDropAgeHours;
@property (nonatomic, readonly) BOOL isQueueBeingModified;
@end
