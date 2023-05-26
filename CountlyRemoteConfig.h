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
- (NSDictionary *)getAllRCVariants;
- (id)remoteConfigValueForKey:(NSString *)key;
- (void)fetchRCVariantsForKeys:(NSArray *)keys completionHandler:(void (^)(NSError * error))completionHandler;
- (void)updateRemoteConfigForKeys:(NSArray *)keys omitKeys:(NSArray *)omitKeys completionHandler:(void (^)(NSError * error))completionHandler;
@end
