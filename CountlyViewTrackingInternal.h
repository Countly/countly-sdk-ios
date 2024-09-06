// CountlyViewTracking.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

extern NSString* const kCountlyReservedEventView;

//TODO: Need discussion for its usage and then we decide to keep it or remove it
extern NSString* const kCountlyCurrentView;
extern NSString* const kCountlyPreviousView;
extern NSString* const kCountlyPreviousEventName;

@interface CountlyViewTrackingInternal : NSObject
@property (nonatomic) BOOL isEnabledOnInitialConfig;
@property (nonatomic) NSString* currentViewID;
@property (nonatomic) NSString* previousViewID;

@property (nonatomic) BOOL enableViewNameRecording;
//TODO: Need discussion for its usage and then we decide to keep it or remove it
@property (nonatomic) NSString* currentViewName;
@property (nonatomic) NSString* previousViewName;

+ (instancetype)sharedInstance;

#if (TARGET_OS_IOS || TARGET_OS_TV)
- (void)startAutoViewTracking;
- (void)stopAutoViewTracking;
- (void)addExceptionForAutoViewTracking:(NSString *)exception;
- (void)removeExceptionForAutoViewTracking:(NSString *)exception;
@property (nonatomic) BOOL isAutoViewTrackingActive;
#endif

- (void)setGlobalViewSegmentation:(NSDictionary *)segmentation;
- (void)updateGlobalViewSegmentation:(NSDictionary *)segmentation;
- (NSString *)startAutoStoppedView:(NSString *)viewName segmentation:(NSDictionary *)segmentation;
- (NSString *)startView:(NSString *)viewName segmentation:(NSDictionary *)segmentation;
- (void)stopViewWithName:(NSString *)viewName segmentation:(NSDictionary *)segmentation;
- (void)stopViewWithID:(NSString *)viewID segmentation:(NSDictionary *)segmentation;
- (void)pauseViewWithID:(NSString *)viewID;
- (void)resumeViewWithID:(NSString *)viewID;
- (void)stopAllViews:(NSDictionary *)segmentation;

- (void)applicationDidEnterBackground;
- (void)applicationWillEnterForeground;
- (void)applicationWillTerminate;
- (void)resetFirstView;

- (void)addSegmentationToViewWithID:(NSString *)viewID segmentation:(NSDictionary *)segmentation;
- (void)addSegmentationToViewWithName:(NSString *)viewName segmentation:(NSDictionary *)segmentation;

#if (TARGET_OS_IOS || TARGET_OS_TV)
- (void)addAutoViewTrackingExclutionList:(NSArray *)viewTrackingExclusionList;
#endif
@end
