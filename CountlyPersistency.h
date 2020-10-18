// CountlyPersistency.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@class CountlyEvent;

@interface CountlyPersistency : NSObject

+ (instancetype)sharedInstance;

- (void)addToQueue:(NSString *)queryString;
- (void)removeFromQueue:(NSString *)queryString;
- (NSString *)firstItemInQueue;
- (void)flushQueue;
- (void)replaceAllTemporaryDeviceIDsInQueueWithDeviceID:(NSString *)deviceID;
- (void)replaceAllAppKeysInQueueWithCurrentAppKey;
- (void)removeDifferentAppKeysFromQueue;

- (void)recordEvent:(CountlyEvent *)event;
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

@property (nonatomic) NSUInteger eventSendThreshold;
@property (nonatomic) NSUInteger storedRequestsLimit;
@property (nonatomic, readonly) BOOL isQueueBeingModified;
@end
