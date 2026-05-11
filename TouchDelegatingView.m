//
//  TouchDelegatingView.m
//  Countly
//
//  Created by Arif Burak Demiray on 21.01.2026.
//  Copyright © 2026 Countly. All rights reserved.
//
#import "TouchDelegatingView.h"
#if (TARGET_OS_IOS)
@implementation TouchDelegatingView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
  UIView *view = [super hitTest:point withEvent:event];
  if (!view)
  {
    return nil;
  }

  if (view != self || !self.touchDelegate)
  {
    return view;
  }

  CGPoint convertedPoint = [self.touchDelegate convertPoint:point fromView:self];
  return [self.touchDelegate hitTest:convertedPoint withEvent:event];
}
@end
#endif
