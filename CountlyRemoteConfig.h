// CountlyLocationManager.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyRemoteConfig : NSObject
@property (nonatomic) BOOL isEnabledOnInitialConfig;
@property (nonatomic, copy) void (^remoteConfigCompletionHandler)(NSError * error);

+ (instancetype)sharedInstance;

- (void)startRemoteConfig;
- (void)clearCachedRemoteConfig;
- (id)remoteConfigValueForKey:(NSString *)key;
- (void)updateRemoteConfigForKeys:(NSArray *)keys omitKeys:(NSArray *)omitKeys completionHandler:(void (^)(NSError * error))completionHandler;

- (NSDictionary *)testingGetAllVariants;
- (NSArray *)testingGetVariantsForKey:(NSString *)key;
- (void)testingFetchVariantsForKeys:(NSArray *)keys completionHandler:(RCVariantCallback)completionHandler;
- (void)testingEnrollIntoVariant:(NSString *)key variantName:(NSString *)variantName completionHandler:(RCVariantCallback)completionHandler;
@end
