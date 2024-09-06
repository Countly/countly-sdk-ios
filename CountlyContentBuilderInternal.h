// CountlyContent.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "CountlyCommon.h"
NS_ASSUME_NONNULL_BEGIN
@interface CountlyContentBuilderInternal: NSObject
#if (TARGET_OS_IOS)
@property (nonatomic, strong) NSArray<NSString *> *currentTags;
@property (nonatomic, assign) NSTimeInterval requestInterval;
@property (nonatomic) ContentCallback contentCallback;

+ (instancetype)sharedInstance;

- (void)enterContentZone:(NSArray<NSString *> *)tags;
- (void)exitContentZone;
- (void)changeContent:(NSArray<NSString *> *)tags;

#endif
NS_ASSUME_NONNULL_END
@end

