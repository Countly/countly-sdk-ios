//
//  CountlyOverlayWindow.m
//  Countly
//
//  Created by Arif Burak Demiray on 20.01.2026.
//  Copyright © 2026 Countly. All rights reserved.
//


// CountlyOverlayWindow.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#if (TARGET_OS_IOS)
#import "PassThroughBackgroundView.h"
#import "CountlyWebViewController.h"
#import "CountlyOverlayWindow.h"

#endif


#if (TARGET_OS_IOS)
@implementation CountlyOverlayWindow
- (instancetype)init {
    BOOL initialized = NO;

    if (@available(iOS 13.0, *)) {
        UIWindowScene *currentWindowScene = nil;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
             if (s.activationState == UISceneActivationStateForegroundActive &&
                 [s isKindOfClass:UIWindowScene.class]) {
                 currentWindowScene = (UIWindowScene *)s;
                 break;
             }
         }
        
        if (currentWindowScene) {
            if(self = [super initWithWindowScene:currentWindowScene]){
                self.frame = currentWindowScene.coordinateSpace.bounds;
                initialized = YES;
            }
        }
    }

    if (!initialized){
        if (self = [super initWithFrame:UIScreen.mainScreen.bounds]){
            initialized = YES;
        }
    }
    
    if(initialized){
        self.windowLevel = UIWindowLevelAlert + 10;
        self.backgroundColor = UIColor.clearColor;
        self.hidden = YES;
    }
    
    return self;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if([self.rootViewController isKindOfClass:CountlyWebViewController.self]){
        CountlyWebViewController* vc = (CountlyWebViewController*)self.rootViewController;
        if(!vc.contentView || vc.contentView.hidden || vc.contentView.alpha < 0.01){
            return nil;
        }
        
        if(vc.contentView){
            CGPoint pointInContent = [self convertPoint:point toView:vc.contentView];
            if (![vc.contentView pointInside:pointInContent withEvent:event]) {
                return nil;
            }
        }
    }
    return [super hitTest:point withEvent:event];
}
@end
#endif
