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


- (CountlyRCData *)getValue:(NSString *)key;

- (NSDictionary<NSString*, CountlyRCData *> *)getAllValues;

-(void)registerDownloadCallback:(RCDownloadCallback) callback;

-(void)removeDownloadCallback:(RCDownloadCallback) callback;

- (void)downloadKeys:(RCDownloadCallback)completionHandler;

- (void)downloadSpecificKeys:(NSArray *)keys completionHandler:(RCDownloadCallback)completionHandler;

- (void)downloadOmittingKeys:(NSArray *)omitKeys completionHandler:(RCDownloadCallback)completionHandler;

- (void)enrollIntoABTestsForKeys:(NSArray *)keys;

- (void)exitABTestsForKeys:(NSArray *)keys;

- (NSDictionary *)testingGetAllVariants;

- (NSArray *)testingGetVariantsForKey:(NSString *)key;

- (void)testingDownloadVariantInformation:(RCVariantCallback)completionHandler;

- (void)testingEnrollIntoVariant:(NSString *)key variantName:(NSString *)variantName completionHandler:(RCVariantCallback)completionHandler;

- (void)clearAll;

@end
