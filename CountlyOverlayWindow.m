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
#import "CountlyOverlayWindow.h"
#import "PassThroughBackgroundView.h"
#import "CountlyWebViewController.h"

@implementation CountlyOverlayWindow

- (instancetype)init {
    UIWindowScene *currentWindowScene = nil;

    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            currentWindowScene = (UIWindowScene *)scene;
            break;
        }
    }
    
    BOOL initialized = NO;

    if (currentWindowScene) {
        if(self = [super initWithWindowScene:currentWindowScene]){
            initialized = YES;
        }
    } else if (self = [super initWithFrame:UIScreen.mainScreen.bounds]){
        initialized = YES;
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
        if(vc.contentView && vc.contentView.hidden){
            return nil;
        }
    }
    return [super hitTest:point withEvent:event];
}

@end
#endif
