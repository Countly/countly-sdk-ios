#import "CountlyWebViewManager.h"
#import "PassThroughBackgroundView.h"

#if (TARGET_OS_IOS)
@interface CountlyWebViewManager (Tests)

@property(nonatomic) BOOL webViewClosed;
@property(nonatomic) BOOL hasAppeared;
@property(nonatomic, strong) NSTimer *loadTimeoutTimer;
@property(nonatomic, strong) NSDate *loadStartDate;
@property(nonatomic, copy) void (^dismissBlock)(void);
@property(nonatomic, copy) void (^appearBlock)(void);
@property(nonatomic, strong) PassThroughBackgroundView *backgroundView;

- (NSDictionary *)parseQueryString:(NSString *)url;
- (void)notifyPageLoaded;
- (void)loadDidTimeout;
- (void)closeWebView;

@end
#endif
