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
- (void)pauseView;
- (void)resumeView;
#if (TARGET_OS_IOS || TARGET_OS_TV)
- (void)startAutoViewTracking;
- (void)addExceptionForAutoViewTracking:(NSString *)exception;
- (void)removeExceptionForAutoViewTracking:(NSString *)exception;
@property (nonatomic) BOOL isAutoViewTrackingEnabled;
#endif
@property (nonatomic, strong) NSString* lastView;
@end

#if (TARGET_OS_IOS || TARGET_OS_TV)
@interface UIViewController (CountlyViewTracking)
- (void)Countly_viewDidAppear:(BOOL)animated;
@end
#endif
