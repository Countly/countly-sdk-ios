// TouchDelegatingView.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.
#if (TARGET_OS_IOS)
#import <UIKit/UIKit.h>

@interface TouchDelegatingView : UIView

@property (nonatomic, weak) UIView *touchDelegate;

@end


@implementation TouchDelegatingView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
    UIView *view = [super hitTest:point withEvent:event];
    if (!view) {
        return nil;
    }

    if (view != self || !self.touchDelegate) {
        return view;
    }

    CGPoint convertedPoint = [self.touchDelegate convertPoint:point fromView:self];
    return [self.touchDelegate hitTest:convertedPoint withEvent:event];
}

@end
#endif
