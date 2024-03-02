// CountlyAPMConfig.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.


#import <Foundation/Foundation.h>



@interface CountlyAPMConfig : NSObject

/**
 * For enabling automatic foreground background  performance monitoring.
 * @discussion If set, Foreground/Background Monitoring will be started automatically on SDK start.
 */
@property (nonatomic) BOOL enableForegroundBackgroundTracking;
@property (nonatomic) BOOL enableAppStartTimeTracking;
@property (nonatomic) BOOL enableManualAppLoadedTrigger;

- (void)setAppStartTimestampOverride:(long long)appStartTimeTimestamp;
- (long long)getAppStartTimestampOverride;

@end
