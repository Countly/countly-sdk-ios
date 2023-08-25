// CountlyViewData.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.


#import <Foundation/Foundation.h>

@interface CountlyViewData : NSObject
/**
 * Unique Id of the view.
 * @discussion Set a unique id when starting a view.
 */
@property (nonatomic) NSString* viewID;
/**
 * Name of the view.
 * @discussion set the name of view when starting a view.
 */
@property (nonatomic) NSString* viewName;
/**
 * Starting time of view.
 * @discussion set the start time when starting a view.
 */
@property (nonatomic) NSTimeInterval viewStartTime;
/**
 * Is this view is auto stoppable.
 * @discussion If set then this view will automatically stopped when new view is started.
 */
@property (nonatomic) BOOL isAutoStoppedView;

/**
 * Is this view is automaticaly paused.
 * @discussion It sets true when app goes to backround, and view will resume on the basis of that flag when app goes to foreground.
 */
@property (nonatomic) BOOL isAutoPaused;

/**
 * Initialize view data
 * @discussion If set then this view will automatically stopped when new view is started.
 * @param viewID unique id of the view.
 * @param viewName view name
 */
- (instancetype)initWithID:(NSString *)viewID viewName:(NSString *)viewName;

/**
 * Duration of the view
 * @discussion it returns the duration of view in foreground after view started.
 */
- (NSTimeInterval)duration;

/**
 * Pause view
 * @discussion View is paused automatically base on the app background event.
 */
- (void)autoPauseView;

/**
 * Pause view
 * @discussion When the view is paused then that time will not consider when calculating the duration
 */
- (void)pauseView;

/**
 * Resume view
 * @discussion View time will resume
 */
- (void)resumeView;

@end
