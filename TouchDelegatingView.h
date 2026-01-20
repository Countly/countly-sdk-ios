//
//  TouchDelegatingView.h
//  Countly
//
//  Created by Arif Burak Demiray on 20.01.2026.
//  Copyright © 2026 Countly. All rights reserved.
//
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
