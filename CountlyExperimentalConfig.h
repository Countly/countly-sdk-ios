//  CountlyExperimentalConfig.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

extern NSString* const kCountlySCKeySC;

@interface CountlyExperimentalConfig : NSObject

@property (nonatomic) BOOL enablePreviousNameRecording;
@property (nonatomic) BOOL enableVisibiltyTracking;

@end
