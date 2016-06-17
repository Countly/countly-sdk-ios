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
#if TARGET_OS_IOS
- (void)startAutoViewTracking;
- (void)addExceptionForAutoViewTracking:(Class _Nullable)exceptionViewControllerSubclass;
- (void)removeExceptionForAutoViewTracking:(Class _Nullable)exceptionViewControllerSubclass;
@property (nonatomic, readwrite) BOOL isAutoViewTrackingEnabled;
#endif
@end

#if TARGET_OS_IOS
@interface UIViewController (CountlyViewTracking)
- (void)Countly_viewDidAppear:(BOOL)animated;
@end
#endif