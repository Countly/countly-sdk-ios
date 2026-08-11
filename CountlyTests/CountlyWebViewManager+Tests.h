#import "CountlyWebViewManager.h"
#import "PassThroughBackgroundView.h"

#if (TARGET_OS_IOS)
@interface CountlyWebViewManager (Tests)

@property(nonatomic) BOOL webViewClosed;
@property(nonatomic) BOOL hasAppeared;
@property(nonatomic) NSInteger resourceRetryCount;
@property(nonatomic, copy) dispatch_block_t pendingReloadBlock;
@property(nonatomic, strong) NSTimer *loadTimeoutTimer;
@property(nonatomic, strong) NSTimer *contentShownDeadlineTimer;
@property(nonatomic, strong) NSDate *loadStartDate;
@property(nonatomic, copy) void (^dismissBlock)(void);
@property(nonatomic, copy) void (^appearBlock)(void);
@property(nonatomic, strong) PassThroughBackgroundView *backgroundView;

- (NSDictionary *)parseQueryString:(NSString *)url;
- (void)notifyPageLoaded;
- (void)loadDidTimeout;
- (void)closeWebView;
- (void)retryOrCloseWebViewForReason:(NSString *)reason;
- (void)cancelPendingReload;
- (void)contentShownDeadlineReached;
- (void)recordEventsWithJSONString:(NSString *)jsonString;
- (void)resizeWebViewWithJSONString:(NSString *)jsonString;
- (BOOL)isFeedbackWidgetURL:(NSURL *)url;

// Rotation, so tests can drive a size change without a real device rotation.
@property(nonatomic) BOOL isFeedbackWidget;
- (void)handleInterfaceSizeChange:(CGSize)newSize;

@end
#endif
