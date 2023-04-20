//  CountlyServerConfig.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyServerConfig : NSObject
#if (TARGET_OS_IOS)
+ (instancetype)sharedInstance;

- (void)fetchServerConfig;

@property (nonatomic) NSUInteger updateSessionPeriod;
@property (nonatomic) NSUInteger eventSendThreshold;
@property (nonatomic) NSUInteger storedRequestsLimit;
@property (nonatomic) BOOL views;
@property (nonatomic) BOOL crashes;
@property (nonatomic) BOOL tracking;
@property (nonatomic) BOOL networking;
#endif
@end

