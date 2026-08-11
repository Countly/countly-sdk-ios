// PassThroughBackgroundView.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "PassThroughBackgroundView.h"

#if (TARGET_OS_IOS || TARGET_OS_VISION)
@implementation PassThroughBackgroundView

@synthesize webView;

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _baseWebViewFrame = CGRectNull;
    }
#if (TARGET_OS_IOS)
    // No device-orientation observer: rotation is driven by the controller's transition callback,
    // which fires once the new size has settled. This one fired mid-rotation and duplicated it.
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleScreenChange) name:UIScreenModeDidChangeNotification object:nil];
#endif
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(handleScreenChange) name:UIApplicationDidBecomeActiveNotification object:nil];
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
    // Execute after a short delay to ensure properties are updated
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateWindowSize];
    });
}

// Swaps a landscape measurement to its portrait equivalent, matching how resolutionJson transposes
// the dimensions it sends the server.
- (CGSize)portraitAdjustedSize:(CGSize)size {
    if (!self.reportPortraitSizeOnly || size.width <= size.height) {
        return size;
    }

    return CGSizeMake(size.height, size.width);
}

- (void)updateWindowSize {
    CGSize size = [self portraitAdjustedSize:[CountlyCommon.sharedInstance getWindowSize]];
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
