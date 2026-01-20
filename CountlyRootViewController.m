// CountlyRootViewController.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#if (TARGET_OS_IOS)
#import "CountlyRootViewController.h"
#import "CountlyContentBuilderInternal.h"

@implementation CountlyRootViewController

- (BOOL)prefersStatusBarHidden {
    return CountlyContentBuilderInternal.sharedInstance.webViewDisplayOption == IMMERSIVE ? YES : NO;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

@end
#endif
