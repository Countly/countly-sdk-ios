// CountlyPersistency.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyPersistency : NSObject

+ (instancetype)sharedInstance;
- (void)addToQueue:(NSString*)queryString;
- (void)saveToFile;
- (void)saveToFileSync;

- (NSString*)retrieveStoredDeviceID;
- (void)storeDeviceID:(NSString*)deviceID;

- (NSString*)retrieveWatchParentDeviceID;
- (void)storeWatchParentDeviceID:(NSString*)deviceID;

@property (nonatomic, strong) NSMutableArray* recordedEvents;
@property (nonatomic, strong) NSMutableArray* queuedRequests;
@property (nonatomic, strong) NSMutableDictionary* startedEvents;
@end

