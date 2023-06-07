//
//  CountlyRemoteConfig.m
//  CountlyTestApp-iOS
//
//  Created by Muhammad Junaid Akram on 07/06/2023.
//  Copyright © 2023 Countly. All rights reserved.
//

#import "CountlyCommon.h"

@implementation CountlyRemoteConfig

+ (instancetype)sharedInstance
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return nil;
    
    static CountlyRemoteConfig* s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    if (self = [super init])
    {
        
    }
    
    return self;
}

- (NSDictionary *)testingGetAllVariants
{
    CLY_LOG_I(@"%s", __FUNCTION__);
    
    return [CountlyRemoteConfigInternal.sharedInstance testingGetAllVariants];
}

- (NSArray *)testingGetVariantsForKey:(NSString *)key {
    
    CLY_LOG_I(@"%s %@", __FUNCTION__, key);
    
    return [CountlyRemoteConfigInternal.sharedInstance testingGetVariantsForKey:key];
}

- (void)testingEnrollIntoVariant:(NSString *)key variantName:(NSString *)variantName completionHandler:(RCVariantCallback)completionHandler {
    
    CLY_LOG_I(@"%s %@ %@ %@", __FUNCTION__, key, variantName , completionHandler);
    
    [CountlyRemoteConfigInternal.sharedInstance testingEnrollIntoVariant:key variantName:variantName completionHandler:completionHandler];
}

- (void)testingFetchAllVariants:(void (^)(CLYRequestResult response, NSError * error))completionHandler
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, completionHandler);
    
    [CountlyRemoteConfigInternal.sharedInstance testingDownloadAllVariants:nil completionHandler:completionHandler];
}

- (CountlyRCValue *)remoteConfigGetValue:(NSString *)key
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, key);
    return [CountlyRemoteConfigInternal.sharedInstance getValue:key];
}

- (NSDictionary<NSString*, CountlyRCValue *> *)remoteConfigGetAllValues
{
    CLY_LOG_I(@"%s", __FUNCTION__);
    return [CountlyRemoteConfigInternal.sharedInstance getAllValues];
}

- (void)remoteConfigEnrollIntoABTestsForKeys:(NSArray *)keys
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, keys);
    [CountlyRemoteConfigInternal.sharedInstance enrollIntoABTestsForKeys:keys];
}

- (void)remoteConfigExitABTestsForKeys:(NSArray *)keys
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, keys);
    [CountlyRemoteConfigInternal.sharedInstance exitABTestsForKeys:keys];
}

-(void)remoteConfigRegisterDownloadCallback:(RCDownloadCallback) callback
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, callback);
    [CountlyRemoteConfigInternal.sharedInstance registerDownloadCallback:callback];
}

-(void)remoteConfigRemoveDownloadCallback:(RCDownloadCallback) callback
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, callback);
    [CountlyRemoteConfigInternal.sharedInstance removeDownloadCallback:callback];
}

- (void)remoteConfigDownloadValues:(RCDownloadCallback)completionHandler
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, completionHandler);
    [CountlyRemoteConfigInternal.sharedInstance downloadValuesForKeys:nil omitKeys:nil completionHandler:^(CLYRequestResult  _Nonnull response, NSError * _Nonnull error, BOOL fullValueUpdate, NSDictionary * _Nonnull downloadedValues) {
        CLY_LOG_I(@"%@ %@ %d %lu",response.description, error.description, fullValueUpdate, (unsigned long)downloadedValues.allKeys.count);
    }];
    
}

- (void)remoteConfigDownloadSpecificValues:(NSArray *)keys completionHandler:(RCDownloadCallback)completionHandler
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, keys, completionHandler);
    [CountlyRemoteConfigInternal.sharedInstance downloadValuesForKeys:keys omitKeys:nil completionHandler:^(CLYRequestResult  _Nonnull response, NSError * _Nonnull error, BOOL fullValueUpdate, NSDictionary * _Nonnull downloadedValues) {
        CLY_LOG_I(@"%@ %@ %d %lu",response.description, error.description, fullValueUpdate, (unsigned long)downloadedValues.allKeys.count);
    }];
    
}

- (void)remoteConfigDownloadOmittingValues:(NSArray *)omitKeys completionHandler:(RCDownloadCallback)completionHandler
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, omitKeys, completionHandler);
    [CountlyRemoteConfigInternal.sharedInstance downloadValuesForKeys:nil omitKeys:omitKeys completionHandler:^(CLYRequestResult  _Nonnull response, NSError * _Nonnull error, BOOL fullValueUpdate, NSDictionary * _Nonnull downloadedValues) {
        CLY_LOG_I(@"%@ %@ %d %lu",response.description, error.description, fullValueUpdate, (unsigned long)downloadedValues.allKeys.count);
    }];
}

- (void)remoteConfigClearAllValues
{
    [CountlyRemoteConfigInternal.sharedInstance clearCachedRemoteConfig:YES];
}


@end
