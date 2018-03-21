// CountlyPersistency.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyConsentManager : NSObject

@property (nonatomic) BOOL requiresConsent;

+ (instancetype)sharedInstance;

@end
