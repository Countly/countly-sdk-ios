//  CountlyServerConfig.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

extern NSString* const kCountlySCKeySC;

@interface CountlyServerConfig : NSObject
+ (instancetype)sharedInstance;

- (void)fetchServerConfig;

- (BOOL)trackingEnabled;
- (BOOL)networkingEnabled;

@end

