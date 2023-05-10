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

@property (nonatomic) BOOL trackingEnabled;
@property (nonatomic) BOOL networkingEnabled;
#endif
@end

