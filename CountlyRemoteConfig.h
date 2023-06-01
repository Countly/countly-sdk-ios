// CountlyLocationManager.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>
#import "CountlyRCValue.h"

@interface CountlyRemoteConfig : NSObject
@property (nonatomic) BOOL isEnabledOnInitialConfig;
@property (nonatomic) BOOL IsEnabledRemoteConfigValueCaching;
@property (nonatomic, copy) void (^remoteConfigCompletionHandler)(NSError * error);
@property (nonatomic, copy) RCDownloadCallback remoteConfigGlobalCallback;

+ (instancetype)sharedInstance;

- (void)startRemoteConfig;
- (void)clearCachedRemoteConfig;
- (id)remoteConfigValueForKey:(NSString *)key;
- (void)updateRemoteConfigForKeys:(NSArray *)keys omitKeys:(NSArray *)omitKeys completionHandler:(void (^)(NSError * error))completionHandler;


- (NSArray<CountlyRCValue *> *)getAllValues;
- (CountlyRCValue *)getValue:(NSString *)key;
- (void)downloadValuesForKeys:(NSArray *)keys omitKeys:(NSArray *)omitKeys completionHandler:(RCDownloadCallback)completionHandler;

- (NSDictionary *)testingGetAllVariants;
- (NSArray *)testingGetVariantsForKey:(NSString *)key;
- (void)testingDownloadAllVariants:(NSArray *)keys completionHandler:(RCVariantCallback)completionHandler;
- (void)testingEnrollIntoVariant:(NSString *)key variantName:(NSString *)variantName completionHandler:(RCVariantCallback)completionHandler;
@end
