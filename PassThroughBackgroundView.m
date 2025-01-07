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

- (void)handleScreenChange {
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    if (@available(iOS 11.0, *)) {
        CGFloat top = UIApplication.sharedApplication.keyWindow.safeAreaInsets.top;
        
        if (top) {
            screenBounds.origin.y += top + 5;
            screenBounds.size.height -= top + 5;
        } else {
            screenBounds.origin.y += 20.0;
            screenBounds.size.height -= 20.0;
        }
    } else {
        screenBounds.origin.y += 20.0;
        screenBounds.size.height -= 20.0;
    }
    
    CGFloat width = screenBounds.size.width;
    CGFloat height = screenBounds.size.height;
    
    NSString *postMessage = [NSString stringWithFormat:
                            @"javascript:window.postMessage({type: 'resize', width: %f, height: %f}, '*');",
                             width,
                             height];
    NSURL *uri = [NSURL URLWithString:postMessage];
    NSURLRequest *request = [NSURLRequest requestWithURL:uri];
    [self.webView loadRequest:request];
}


// Always remove observers when the view is deallocated
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
#endif
