// CountlyViewData.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.


#import <Foundation/Foundation.h>

@interface CountlyViewData : NSObject
/**
 * Unique Id of the view.
 * @discussion Set a unique id of when starting a view.
 */
@property (nonatomic) NSString* viewID;
@property (nonatomic) NSString* viewName;
@property (nonatomic) NSTimeInterval viewStartTime;
@property (nonatomic) NSTimeInterval viewAccumulatedTime;
@property (nonatomic) BOOL isAutoStoppedView;

- (instancetype)initWithID:(NSString *)viewID viewName:(NSString *)viewName;
- (NSTimeInterval)duration;
- (void)pauseView;
- (void)resumeView;

@end
