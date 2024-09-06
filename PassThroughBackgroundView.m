// PassThroughBackgroundView.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "PassThroughBackgroundView.h"

@implementation PassThroughBackgroundView

@synthesize webView;

- (instancetype)initWithFrame:(CGRect)frame {
#if (TARGET_OS_IOS)
    self = [super initWithFrame:frame];
    if (self) {
    }
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

#endif
@end
