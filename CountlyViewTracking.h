// CountlyViewTracking.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyViewTracking : NSObject

+ (instancetype _Nonnull)sharedInstance;

- (void)reportView:(NSString* _Nonnull)viewName;
- (void)endView;
@end