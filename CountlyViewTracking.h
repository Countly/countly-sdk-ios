// CountlyViewTracking.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

#if TARGET_OS_TV
#import <UIKit/UIKit.h>
#endif

@interface CountlyViewTracking : NSObject

+ (instancetype)sharedInstance;

- (void)reportView:(NSString *)viewName;
- (void)endView;
#if (TARGET_OS_IOS || TARGET_OS_TV)
- (void)startAutoViewTracking;
- (void)addExceptionForAutoViewTracking:(Class)exceptionViewControllerSubclass;
- (void)removeExceptionForAutoViewTracking:(Class)exceptionViewControllerSubclass;
@property (nonatomic) BOOL isAutoViewTrackingEnabled;
#endif
@end

#if (TARGET_OS_IOS || TARGET_OS_TV)
@interface UIViewController (CountlyViewTracking)
- (void)Countly_viewDidAppear:(BOOL)animated;
@end
#endif
