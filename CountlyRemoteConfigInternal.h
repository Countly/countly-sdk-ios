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
@property (nonatomic) BOOL enrollABOnRCDownload;
@property (nonatomic, copy) void (^remoteConfigCompletionHandler)(NSError * error);
@property (nonatomic) NSMutableArray<RCDownloadCallback> *remoteConfigGlobalCallbacks;

+ (instancetype)sharedInstance;

- (void)startRemoteConfig;
- (void)clearAll;
- (void)clearCachedRemoteConfig;
- (id)remoteConfigValueForKey:(NSString *)key;
- (void)updateRemoteConfigForKeys:(NSArray *)keys omitKeys:(NSArray *)omitKeys completionHandler:(void (^)(NSError * error))completionHandler;


- (void)downloadRemoteConfigAutomatically;

- (CountlyRCData *)getValue:(NSString *)key;
- (NSDictionary<NSString*, CountlyRCData *> *)getAllValues;

- (CountlyRCData *)getValueAndEnroll:(NSString *)key;
- (NSDictionary<NSString*, CountlyRCData *> *)getAllValuesAndEnroll;

- (void)downloadValuesForKeys:(NSArray *)keys omitKeys:(NSArray *)omitKeys completionHandler:(RCDownloadCallback)completionHandler;

- (NSDictionary *)testingGetAllVariants;
- (NSArray *)testingGetVariantsForKey:(NSString *)key;
- (void)testingDownloadAllVariants:(RCVariantCallback)completionHandler;
- (void)testingEnrollIntoVariant:(NSString *)key variantName:(NSString *)variantName completionHandler:(RCVariantCallback)completionHandler;

- (void) testingDownloadExperimentInformation:(RCVariantCallback)completionHandler;
- (NSDictionary<NSString*, CountlyExperimentInformation*> *) testingGetAllExperimentInfo;

- (void)enrollIntoABTestsForKeys:(NSArray *)keys;
- (void)exitABTestsForKeys:(NSArray *)keys;

- (void)registerDownloadCallback:(RCDownloadCallback) callback;
- (void)removeDownloadCallback:(RCDownloadCallback) callback;
@end
