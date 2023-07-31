// CountlyViewTracking.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

extern NSString* const kCountlyReservedEventView;

@interface CountlyViewTrackingInternal : NSObject
@property (nonatomic) BOOL isEnabledOnInitialConfig;
@property (nonatomic) NSString* currentViewID;
@property (nonatomic) NSString* previousViewID;

@property (nonatomic) BOOL useMultipleViewFlow;

+ (instancetype)sharedInstance;

- (void)startView:(NSString *)viewName customSegmentation:(NSDictionary *)customSegmentation;
- (void)endView;
- (void)pauseView;
- (void)resumeView;
#if (TARGET_OS_IOS || TARGET_OS_TV)
- (void)startAutoViewTracking;
- (void)stopAutoViewTracking;
- (void)addExceptionForAutoViewTracking:(NSString *)exception;
- (void)removeExceptionForAutoViewTracking:(NSString *)exception;
@property (nonatomic) BOOL isAutoViewTrackingActive;
#endif

- (void)setGlobalViewSegmentation:(NSDictionary *)segmentation;
- (void)updateGlobalViewSegmentation:(NSDictionary *)segmentation;
- (NSString *)startView:(NSString *)viewName segmentation:(NSDictionary *)segmentation;
- (void)stopViewWithName:(NSString *)viewName segmentation:(NSDictionary *)segmentation;
- (void)stopViewWithID:(NSString *)viewID segmentation:(NSDictionary *)segmentation;
- (void)pauseViewWithID:(NSString *)viewID;
- (void)resumeViewWithID:(NSString *)viewID;
@end
