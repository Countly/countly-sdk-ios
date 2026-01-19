//
//  CountlyWebViewController.m
//  Countly
//
//  Created by Arif Burak Demiray on 14.01.2026.
//  Copyright © 2026 Countly. All rights reserved.
//


//
//  CountlyWebViewController.m
//  CountlyTestApp-iOS
//
//  Created by Arif Burak Demiray on 19.11.2025.
//  Copyright © 2025 Countly. All rights reserved.
//
#import "CountlyWebViewController.h"

@implementation CountlyWebViewController

- (BOOL)prefersStatusBarHidden {
    return CountlyContentBuilderInternal.sharedInstance.webViewDisplayOption == IMMERSIVE ? YES : NO;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return CountlyContentBuilderInternal.sharedInstance.webViewDisplayOption == IMMERSIVE ? YES : NO;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // Fully transparent controller background
    self.view.backgroundColor = [UIColor clearColor];
    self.view.insetsLayoutMarginsFromSafeArea = NO;
    self.view.directionalLayoutMargins = NSDirectionalEdgeInsetsZero;
    self.extendedLayoutIncludesOpaqueBars = YES;
    self.edgesForExtendedLayout = UIRectEdgeAll;
    
    // Ensure underlying app stays visible
    self.view.opaque = NO;

    if (self.contentView) {
        self.contentView.frame = self.view.bounds;
        self.contentView.autoresizingMask =
            UIViewAutoresizingFlexibleWidth |
            UIViewAutoresizingFlexibleHeight;

        [self.view addSubview:self.contentView];
    }
}

- (void)updatePlacementRespectToSafeAreas {
    UIEdgeInsets safeArea = self.view.safeAreaInsets;
    if (@available(iOS 13.0, *)) {
        UIInterfaceOrientation orientation = self.view.window.windowScene.interfaceOrientation;
        
        CGRect frame = self.contentView.webView.frame;
        if(CountlyContentBuilderInternal.sharedInstance.webViewDisplayOption == SAFE_AREA || [self hasTopNotch:safeArea]){
            frame.origin.y += safeArea.top; // always respect notch if exists
        }
        if(CountlyContentBuilderInternal.sharedInstance.webViewDisplayOption == SAFE_AREA && orientation != UIInterfaceOrientationLandscapeLeft){
            frame.origin.x += MAX(safeArea.left, safeArea.right);
        }
        self.contentView.webView.frame = frame;
    }
}

- (bool) hasTopNotch:(UIEdgeInsets)safeArea
{
    if (@available(iOS 11.0, *)) {
        return safeArea.top >= 44;
    } else {
        return NO;
    }
}



@end
