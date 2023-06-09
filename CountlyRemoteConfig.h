//
//  CountlyRemoteConfig.h
//  CountlyTestApp-iOS
//
//  Created by Muhammad Junaid Akram on 07/06/2023.
//  Copyright © 2023 Countly. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CountlyRCData.h"

@interface CountlyRemoteConfig : NSObject

+ (instancetype)sharedInstance;

- (NSDictionary *)testingGetAllVariants;

- (NSArray *)testingGetVariantsForKey:(NSString *)key;

- (void)testingDownloadVariantInformation:(RCVariantCallback)completionHandler;

- (void)testingEnrollIntoVariant:(NSString *)key variantName:(NSString *)variantName completionHandler:(RCVariantCallback)completionHandler;

- (void)remoteConfigClearAll;

- (CountlyRCData *)remoteConfigGetKey:(NSString *)key;

- (NSDictionary<NSString*, CountlyRCData *> *)remoteConfigGetAllKeys;

-(void)remoteConfigRegisterDownloadCallback:(RCDownloadCallback) callback;

-(void)remoteConfigRemoveDownloadCallback:(RCDownloadCallback) callback;

- (void)remoteConfigDownloadKeys:(RCDownloadCallback)completionHandler;

- (void)remoteConfigDownloadSpecificKeys:(NSArray *)keys completionHandler:(RCDownloadCallback)completionHandler;

- (void)remoteConfigDownloadOmittingKeys:(NSArray *)omitKeys completionHandler:(RCDownloadCallback)completionHandler;

- (void)remoteConfigEnrollIntoABTestsForKeys:(NSArray *)keys;

- (void)remoteConfigExitABTestsForKeys:(NSArray *)keys;

@end
