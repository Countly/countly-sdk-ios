// CountlyRemoteConfig.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

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

- (void)testingDownloadVariantInformation:(RCVariantCallback)completionHandler
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, completionHandler);
    
    [CountlyRemoteConfigInternal.sharedInstance testingDownloadAllVariants:completionHandler];
}

- (CountlyRCData *)getValue:(NSString *)key
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, key);
    return [CountlyRemoteConfigInternal.sharedInstance getValue:key];
}

- (NSDictionary<NSString*, CountlyRCData *> *)getAllValues
{
    CLY_LOG_I(@"%s", __FUNCTION__);
    return [CountlyRemoteConfigInternal.sharedInstance getAllValues];
}

- (CountlyRCData *)getValueAndEnroll:(NSString *)key
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, key);
    return [CountlyRemoteConfigInternal.sharedInstance getValueAndEnroll:key];
}

- (NSDictionary<NSString*, CountlyRCData *> *)getAllValuesAndEnroll
{
    CLY_LOG_I(@"%s", __FUNCTION__);
    return [CountlyRemoteConfigInternal.sharedInstance getAllValuesAndEnroll];
}

- (void)enrollIntoABTestsForKeys:(NSArray *)keys
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, keys);
    [CountlyRemoteConfigInternal.sharedInstance enrollIntoABTestsForKeys:keys];
}

- (void)exitABTestsForKeys:(NSArray *)keys
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, keys);
    [CountlyRemoteConfigInternal.sharedInstance exitABTestsForKeys:keys];
}

-(void)registerDownloadCallback:(RCDownloadCallback) callback
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, callback);
    [CountlyRemoteConfigInternal.sharedInstance registerDownloadCallback:callback];
}

-(void)removeDownloadCallback:(RCDownloadCallback) callback
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, callback);
    [CountlyRemoteConfigInternal.sharedInstance removeDownloadCallback:callback];
}

- (void)downloadKeys:(RCDownloadCallback)completionHandler
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, completionHandler);
    [CountlyRemoteConfigInternal.sharedInstance downloadValuesForKeys:nil omitKeys:nil completionHandler:completionHandler];
    
}

- (void)downloadSpecificKeys:(NSArray *)keys completionHandler:(RCDownloadCallback)completionHandler
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, keys, completionHandler);
    [CountlyRemoteConfigInternal.sharedInstance downloadValuesForKeys:keys omitKeys:nil completionHandler:completionHandler];
    
}

- (void)downloadOmittingKeys:(NSArray *)omitKeys completionHandler:(RCDownloadCallback)completionHandler
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, omitKeys, completionHandler);
    [CountlyRemoteConfigInternal.sharedInstance downloadValuesForKeys:nil omitKeys:omitKeys completionHandler:completionHandler];
}

- (void) testingDownloadExperimentInformation:(RCVariantCallback)completionHandler;
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, completionHandler);
    
    [CountlyRemoteConfigInternal.sharedInstance testingDownloadExperimentInformation:completionHandler];
}

- (NSDictionary<NSString*, CountlyExperimentInformation*> *) testingGetAllExperimentInfo
{
    CLY_LOG_I(@"%s", __FUNCTION__);
    return [CountlyRemoteConfigInternal.sharedInstance testingGetAllExperimentInfo];
}

- (void)clearAll
{
    [CountlyRemoteConfigInternal.sharedInstance clearAll];
}


@end
