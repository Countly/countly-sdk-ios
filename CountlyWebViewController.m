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


@end
