// PassThroughBackgroundView.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "PassThroughBackgroundView.h"

#if (TARGET_OS_IOS)
@implementation PassThroughBackgroundView

@synthesize webView;

- (instancetype)initWithFrame:(CGRect)frame {

    self = [super initWithFrame:frame];
#if (TARGET_OS_IOS)
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleScreenChange) name:UIDeviceOrientationDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleScreenChange) name:UIScreenModeDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleScreenChange) name:UIApplicationDidBecomeActiveNotification object:nil];
#endif
    return self;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    
    if (self.webView && CGRectContainsPoint(self.webView.frame, point)) {
        return YES;
    }
    if (self.dismissButton && CGRectContainsPoint(self.dismissButton.frame, point)) {
        return YES;
    }
    
    return NO;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    
    if (self.traitCollection.horizontalSizeClass != previousTraitCollection.horizontalSizeClass) {
        [self adjustWebViewForTraitCollection:self.traitCollection];
    }
}

- (void)adjustWebViewForTraitCollection:(UITraitCollection *)traitCollection {
    if (traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact) {
        [self handleScreenChange];
    }
}

CGSize getWindowSize(void) {
    UIWindow *window = nil;

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                window = ((UIWindowScene *)scene).windows.firstObject;
                break;
            }
        }
    } else {
        window = [[UIApplication sharedApplication].delegate window];
    }

    if (!window) return CGSizeZero;
    
    UIEdgeInsets safeArea = UIEdgeInsetsZero;
    CGFloat screenScale = [UIScreen mainScreen].scale;
    if (@available(iOS 11.0, *)) {
        safeArea = window.safeAreaInsets;
        safeArea.left /= screenScale;
        safeArea.bottom /= screenScale;
        safeArea.right /= screenScale;
    }
    
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    BOOL isLandscape = UIInterfaceOrientationIsLandscape(orientation);
    
    CGSize size = CGSizeMake(window.bounds.size.width, window.bounds.size.height);
    
    if(!isLandscape){
        size.width -= safeArea.left + safeArea.right;
        size.height -= safeArea.top + safeArea.bottom;
    }

    return size;
}

- (void)handleScreenChange {
    // Execute after a short delay to ensure properties are updated
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateWindowSize];
    });
}

- (void)updateWindowSize {
    CGSize size = getWindowSize();
    CGFloat width = size.width;
    CGFloat height = size.height;
    
    NSString *postMessage = [NSString stringWithFormat:
                            @"javascript:window.postMessage({type: 'resize', width: %f, height: %f}, '*');",
                             width,
                             height];
    [self.webView evaluateJavaScript:postMessage completionHandler:^(id result, NSError *err) {
        if (err != nil) {
            CLY_LOG_E(@"%s updateWindowSize, %@", __FUNCTION__, err);
        }
    }];
}

// Always remove observers when the view is deallocated
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
#endif
