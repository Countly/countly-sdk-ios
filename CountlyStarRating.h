//  CountlyStarRating.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyStarRating : NSObject
#if TARGET_OS_IOS
+ (instancetype)sharedInstance;

- (void)showDialog:(void(^)(NSInteger rating))completion;

@property (nonatomic, strong) NSString* message;
@property (nonatomic, strong) NSString* dismissButtonTitle;
#endif
@end