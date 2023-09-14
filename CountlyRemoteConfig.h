// CountlyRemoteConfig.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>
#import "CountlyRCData.h"
#import "CountlyExperimentInfo.h"

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

- (void) testingDownloadExperimentInformation:(RCVariantCallback)completionHandler;
- (NSDictionary<NSString*, CountlyExperimentInfo*> *) testingGetAllExperimentInfo;

- (void)clearAll;

@end
