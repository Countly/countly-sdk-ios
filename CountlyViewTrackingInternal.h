// CountlyViewTracking.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

extern NSString* const kCountlyReservedEventView;

extern NSString* const kCountlyCurrentView;
extern NSString* const kCountlyPreviousView;
extern NSString* const kCountlyPreviousEventName;
extern NSString* const kCountlyVTKeyVisit;
extern NSString* const kCountlyVTKeyName;

@interface CountlyViewTrackingInternal : NSObject <Resettable>
@property (nonatomic) NSString* currentViewID;
@property (nonatomic) NSString* previousViewID;

@property (nonatomic) BOOL enablePreviousNameRecording;
@property (nonatomic) NSString* currentViewName;
@property (nonatomic) NSString* previousViewName;

@property (nonatomic) BOOL isManualViewRestartActive;

+ (instancetype)sharedInstance;

// Automatic view tracking is only implemented for iOS and tvOS, so the guard must not include
// visionOS: the methods below would be declared but have no definition there
#if (TARGET_OS_IOS || TARGET_OS_TV)
- (void)startAutoViewTracking;
- (void)stopAutoViewTracking;
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
/**
 * Returns the name of a running view as the app passed it, before the internal limits cut it.
 * @param viewID The ID of the view
 * @return The name, or nil for an unknown view
 */
- (NSString *)viewNameAsGivenForViewID:(NSString *)viewID;
- (void)addSegmentationToViewWithName:(NSString *)viewName segmentation:(NSDictionary *)segmentation;

#if (TARGET_OS_IOS || TARGET_OS_TV)
- (void)addAutoViewTrackingExclutionList:(NSArray *)viewTrackingExclusionList;
#endif
@end
