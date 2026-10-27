#import "CountlyContentBuilderInternal.h"

#if (TARGET_OS_IOS)
@interface CountlyContentBuilderInternal (Tests)

// Single-content presentation latch (see .m). Exposed so tests can verify that a second
// concurrent presentation is rejected (no duplicate content web views).
- (BOOL)tryBeginContentPresentation;
- (void)endContentPresentation;
- (BOOL)isContentShownThreadSafe;

// Zone re-entry timer + presentation entry point, so tests can drive a real presentation.
- (BOOL)isZoneReentryTimerArmed;
- (void)showContentWithHtmlPath:(NSString *)urlString placementCoordinates:(NSDictionary *)placementCoordinates;

@end
#endif
