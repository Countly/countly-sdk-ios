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

- (void)recordEvent:(CountlyEvent *)event;
- (NSString *)serializedRecordedEvents;

- (void)recordTimedEvent:(CountlyEvent *)event;
- (CountlyEvent *)timedEventForKey:(NSString *)key;
- (void)clearAllTimedEvents;

- (void)saveToFile;
- (void)saveToFileSync;

- (NSString *)retrieveStoredDeviceID;
- (void)storeDeviceID:(NSString *)deviceID;

- (NSString *)retrieveWatchParentDeviceID;
- (void)storeWatchParentDeviceID:(NSString *)deviceID;

- (NSDictionary *)retrieveStarRatingStatus;
- (void)storeStarRatingStatus:(NSDictionary *)status;

- (BOOL)retrieveNotificationPermission;
- (void)storeNotificationPermission:(BOOL)allowed;

@property (nonatomic) NSUInteger eventSendThreshold;
@property (nonatomic) NSUInteger storedRequestsLimit;
@end
