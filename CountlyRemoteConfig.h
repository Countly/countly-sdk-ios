// CountlyLocationManager.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CountlyRemoteConfig : NSObject
@property (nonatomic) BOOL isEnabledOnInitialConfig;

+ (instancetype)sharedInstance;

- (void)startRemoteConfig;
- (id)remoteConfigValueForKey:(NSString *)key;
@end

NS_ASSUME_NONNULL_END
