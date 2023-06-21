// CountlyLocationManager.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>
#import "CountlyRCData.h"

@interface CountlyRemoteConfigInternal : NSObject
@property (nonatomic) BOOL isRCAutomaticTriggersEnabled;
@property (nonatomic) BOOL isRCValueCachingEnabled;
@property (nonatomic, copy) void (^remoteConfigCompletionHandler)(NSError * error);
@property (nonatomic) NSMutableArray<RCDownloadCallback> *remoteConfigGlobalCallbacks;

+ (instancetype)sharedInstance;

- (void)startRemoteConfig;
- (void)clearCachedRemoteConfig:(BOOL)force;
- (id)remoteConfigValueForKey:(NSString *)key;
- (void)updateRemoteConfigForKeys:(NSArray *)keys omitKeys:(NSArray *)omitKeys completionHandler:(void (^)(NSError * error))completionHandler;


- (void)downloadRemoteConfigAutomatically;
- (CountlyRCData *)getValue:(NSString *)key;
- (void)downloadValuesForKeys:(NSArray *)keys omitKeys:(NSArray *)omitKeys completionHandler:(RCDownloadCallback)completionHandler;

- (NSDictionary *)testingGetAllVariants;
- (NSArray *)testingGetVariantsForKey:(NSString *)key;
- (void)testingDownloadAllVariants:(RCVariantCallback)completionHandler;
- (void)testingEnrollIntoVariant:(NSString *)key variantName:(NSString *)variantName completionHandler:(RCVariantCallback)completionHandler;

- (NSDictionary<NSString*, CountlyRCData *> *)getAllValues;
- (void)enrollIntoABTestsForKeys:(NSArray *)keys;
- (void)exitABTestsForKeys:(NSArray *)keys;

- (void)registerDownloadCallback:(RCDownloadCallback) callback;
- (void)removeDownloadCallback:(RCDownloadCallback) callback;
@end
