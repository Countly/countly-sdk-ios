// CountlyRemoteConfig.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>
#import "CountlyRCData.h"
#import "CountlyExperimentInformation.h"

@interface CountlyRemoteConfig : NSObject

+ (instancetype)sharedInstance;


- (CountlyRCData *)getValue:(NSString *)key;

- (NSDictionary<NSString*, CountlyRCData *> *)getAllValues;

- (CountlyRCData *)getValueAndEnroll:(NSString *)key;

- (NSDictionary<NSString*, CountlyRCData *> *)getAllValuesAndEnroll;

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

- (void) testingDownloadExperimentInformation:(RCVariantCallback)completionHandler;
- (NSDictionary<NSString*, CountlyExperimentInformation*> *) testingGetAllExperimentInfo;

- (void)clearAll;

@end
