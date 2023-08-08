// CountlyViewData.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.


#import <Foundation/Foundation.h>

@interface CountlyViewData : NSObject

@property (nonatomic) NSString* viewID;
@property (nonatomic) NSString* viewName;
@property (nonatomic) NSTimeInterval viewStartTime;
@property (nonatomic) NSTimeInterval viewCreationTime;
@property (nonatomic) NSTimeInterval viewAccumulatedTime;
@property (nonatomic) BOOL isAutoStopView;

- (instancetype)initWithID:(NSString *)viewID viewName:(NSString *)viewName;
- (NSTimeInterval)duration;
- (void)pauseView;
- (void)resumeView;

@end
