//
//  CountlyRemoteConfig.h
//  CountlyTestApp-iOS
//
//  Created by Muhammad Junaid Akram on 07/06/2023.
//  Copyright © 2023 Countly. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CountlyRCValue.h"

@interface CountlyRemoteConfig : NSObject

+ (instancetype)sharedInstance;

- (NSDictionary *)testingGetAllVariants;

- (NSArray *)testingGetVariantsForKey:(NSString *)key;

- (void)testingFetchAllVariants:(void (^)(CLYRequestResult response, NSError * error))completionHandler;

- (void)testingEnrollIntoVariant:(NSString *)key variantName:(NSString *)variantName completionHandler:(RCVariantCallback)completionHandler;

- (void)remoteConfigClearAllValues;

- (CountlyRCValue *)remoteConfigGetValue:(NSString *)key;

- (NSDictionary<NSString*, CountlyRCValue *> *)remoteConfigGetAllValues;

-(void)remoteConfigRegisterDownloadCallback:(RCDownloadCallback) callback;

-(void)remoteConfigRemoveDownloadCallback:(RCDownloadCallback) callback;

- (void)remoteConfigDownloadValues:(RCDownloadCallback)completionHandler;

- (void)remoteConfigDownloadSpecificValues:(NSArray *)keys completionHandler:(RCDownloadCallback)completionHandler;

- (void)remoteConfigDownloadOmittingValues:(NSArray *)omitKeys completionHandler:(RCDownloadCallback)completionHandler;

- (void)remoteConfigEnrollIntoABTestsForKeys:(NSArray *)keys;

- (void)remoteConfigExitABTestsForKeys:(NSArray *)keys;

@end
