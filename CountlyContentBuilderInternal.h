// CountlyContent.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#if (TARGET_OS_IOS)
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "CountlyCommon.h"

@interface CountlyContentBuilderInternal: NSObject

@property (nonatomic, strong) NSArray<NSString *> *currentTags;
@property (nonatomic, assign) NSTimeInterval requestInterval;
@property (nonatomic) ContentCallback contentCallback;

+ (instancetype)sharedInstance;

- (void)enterContentZone:(NSArray<NSString *> *)tags;
- (void)exitContentZone;
- (void)changeContent:(NSArray<NSString *> *)tags;

@end
#endif

