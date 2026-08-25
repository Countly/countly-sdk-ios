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
    CLY_LOG_I(@"%s all locally cached variants are requested", __FUNCTION__);
    
    return [CountlyRemoteConfigInternal.sharedInstance testingGetAllVariants];
}

- (NSArray *)testingGetVariantsForKey:(NSString *)key {
    
    CLY_LOG_I(@"%s locally cached variants are requested, key: [%@]", __FUNCTION__, key);
    
    return [CountlyRemoteConfigInternal.sharedInstance testingGetVariantsForKey:key];
}

- (void)testingEnrollIntoVariant:(NSString *)key variantName:(NSString *)variantName completionHandler:(RCVariantCallback)completionHandler {
    
    CLY_LOG_I(@"%s variant enrollment is requested, key: [%@], variantName: [%@], completionHandlerProvided: [%@]", __FUNCTION__, key, variantName, (completionHandler != nil) ? @"YES" : @"NO");
    
    [CountlyRemoteConfigInternal.sharedInstance testingEnrollIntoVariant:key variantName:variantName completionHandler:completionHandler];
}

- (void)testingDownloadVariantInformation:(RCVariantCallback)completionHandler
{
    CLY_LOG_I(@"%s variant information download is requested, completionHandlerProvided: [%@]", __FUNCTION__, (completionHandler != nil) ? @"YES" : @"NO");
    
    [CountlyRemoteConfigInternal.sharedInstance testingDownloadAllVariants:completionHandler];
}

- (CountlyRCData *)getValue:(NSString *)key
{
    CLY_LOG_I(@"%s remote config value is requested, key: [%@]", __FUNCTION__, key);
    return [CountlyRemoteConfigInternal.sharedInstance getValue:key];
}

- (NSDictionary<NSString*, CountlyRCData *> *)getAllValues
{
    CLY_LOG_I(@"%s all remote config values are requested", __FUNCTION__);
    return [CountlyRemoteConfigInternal.sharedInstance getAllValues];
}

- (CountlyRCData *)getValueAndEnroll:(NSString *)key
{
    CLY_LOG_I(@"%s remote config value is requested with AB test enrollment, key: [%@]", __FUNCTION__, key);
    return [CountlyRemoteConfigInternal.sharedInstance getValueAndEnroll:key];
}

- (NSDictionary<NSString*, CountlyRCData *> *)getAllValuesAndEnroll
{
    CLY_LOG_I(@"%s all remote config values are requested with AB test enrollment", __FUNCTION__);
    return [CountlyRemoteConfigInternal.sharedInstance getAllValuesAndEnroll];
}

- (void)enrollIntoABTestsForKeys:(NSArray *)keys
{
    CLY_LOG_I(@"%s AB test enrollment is requested, keys: [%@], keyCount: [%lu]", __FUNCTION__, keys, (unsigned long)keys.count);
    [CountlyRemoteConfigInternal.sharedInstance enrollIntoABTestsForKeys:keys];
}

- (void)exitABTestsForKeys:(NSArray *)keys
{
    CLY_LOG_I(@"%s AB test exit is requested, keys: [%@], keyCount: [%lu]", __FUNCTION__, keys, (unsigned long)keys.count);
    [CountlyRemoteConfigInternal.sharedInstance exitABTestsForKeys:keys];
}

-(void)registerDownloadCallback:(RCDownloadCallback) callback
{
    CLY_LOG_I(@"%s download callback registration is requested, callbackProvided: [%@]", __FUNCTION__, (callback != nil) ? @"YES" : @"NO");
    [CountlyRemoteConfigInternal.sharedInstance registerDownloadCallback:callback];
}

-(void)removeDownloadCallback:(RCDownloadCallback) callback
{
    CLY_LOG_I(@"%s download callback removal is requested, callbackProvided: [%@]", __FUNCTION__, (callback != nil) ? @"YES" : @"NO");
    [CountlyRemoteConfigInternal.sharedInstance removeDownloadCallback:callback];
}

- (void)downloadKeys:(RCDownloadCallback)completionHandler
{
    CLY_LOG_I(@"%s download of all remote config keys is requested, completionHandlerProvided: [%@]", __FUNCTION__, (completionHandler != nil) ? @"YES" : @"NO");
    [CountlyRemoteConfigInternal.sharedInstance downloadValuesForKeys:nil omitKeys:nil completionHandler:completionHandler];
    
}

- (void)downloadSpecificKeys:(NSArray *)keys completionHandler:(RCDownloadCallback)completionHandler
{
    CLY_LOG_I(@"%s download of specific remote config keys is requested, keys: [%@], keyCount: [%lu], completionHandlerProvided: [%@]", __FUNCTION__, keys, (unsigned long)keys.count, (completionHandler != nil) ? @"YES" : @"NO");
    [CountlyRemoteConfigInternal.sharedInstance downloadValuesForKeys:keys omitKeys:nil completionHandler:completionHandler];
    
}

- (void)downloadOmittingKeys:(NSArray *)omitKeys completionHandler:(RCDownloadCallback)completionHandler
{
    CLY_LOG_I(@"%s download omitting remote config keys is requested, omitKeys: [%@], omitKeyCount: [%lu], completionHandlerProvided: [%@]", __FUNCTION__, omitKeys, (unsigned long)omitKeys.count, (completionHandler != nil) ? @"YES" : @"NO");
    [CountlyRemoteConfigInternal.sharedInstance downloadValuesForKeys:nil omitKeys:omitKeys completionHandler:completionHandler];
}

- (void) testingDownloadExperimentInformation:(RCVariantCallback)completionHandler;
{
    CLY_LOG_I(@"%s experiment information download is requested, completionHandlerProvided: [%@]", __FUNCTION__, (completionHandler != nil) ? @"YES" : @"NO");
    
    [CountlyRemoteConfigInternal.sharedInstance testingDownloadExperimentInformation:completionHandler];
}

- (NSDictionary<NSString*, CountlyExperimentInformation*> *) testingGetAllExperimentInfo
{
    CLY_LOG_I(@"%s all locally cached experiment information is requested", __FUNCTION__);
    return [CountlyRemoteConfigInternal.sharedInstance testingGetAllExperimentInfo];
}

- (void)clearAll
{
    CLY_LOG_I(@"%s clearing all remote config values is requested", __FUNCTION__);
    [CountlyRemoteConfigInternal.sharedInstance clearAll];
}


@end
