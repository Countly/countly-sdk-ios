// CountlyWebViewController.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.
//
#import "CountlyWebViewController.h"
#import "TouchDelegatingView.h"
#import "PassThroughBackgroundView.h"

#if (TARGET_OS_IOS)
@implementation CountlyWebViewController
- (BOOL)prefersStatusBarHidden
{
  return CountlyContentBuilderInternal.sharedInstance.webViewDisplayOption == IMMERSIVE ? YES : NO;
}

- (BOOL)prefersHomeIndicatorAutoHidden
{
  return CountlyContentBuilderInternal.sharedInstance.webViewDisplayOption == IMMERSIVE ? YES : NO;
}

- (UIStatusBarStyle)preferredStatusBarStyle
{
  return UIApplication.sharedApplication.keyWindow.rootViewController.preferredStatusBarStyle;
}

- (void)loadView
{
  self.view = [[TouchDelegatingView alloc] initWithFrame:UIApplication.sharedApplication.keyWindow.rootViewController.view.bounds];
}

- (void)viewDidLoad
{
  [super viewDidLoad];

  if ([self.view isKindOfClass:[TouchDelegatingView class]])
  {
    TouchDelegatingView *delegatingView = (TouchDelegatingView *)self.view;
    delegatingView.touchDelegate        = UIApplication.sharedApplication.keyWindow.rootViewController.view;
  }

  // Fully transparent controller background
  self.view.backgroundColor = [UIColor clearColor];
  if (@available(iOS 11.0, *))
  {
    self.view.insetsLayoutMarginsFromSafeArea = NO;
    self.view.directionalLayoutMargins        = NSDirectionalEdgeInsetsZero;
  }
  self.extendedLayoutIncludesOpaqueBars = YES;
  self.edgesForExtendedLayout           = UIRectEdgeAll;

  // Ensure underlying app stays visible
  self.view.opaque = NO;

  if (self.contentView)
  {
    self.contentView.frame            = self.view.bounds;
    self.contentView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    [self.view addSubview:self.contentView];
  }
}

- (void)updatePlacementRespectToSafeAreas
{
  if (@available(iOS 13.0, *))
  {
    UIEdgeInsets safeArea = self.view.safeAreaInsets;

    UIInterfaceOrientation orientation = self.view.window.windowScene.interfaceOrientation;
      
      if([self.contentView isKindOfClass:PassThroughBackgroundView.self]){
          PassThroughBackgroundView* content = (PassThroughBackgroundView*)self.contentView;
          CGRect frame = content.webView.frame;
          if (CountlyContentBuilderInternal.sharedInstance.webViewDisplayOption == SAFE_AREA || [self hasTopNotch:safeArea])
          {
            frame.origin.y += safeArea.top; // always respect notch if exists
          }
          if (orientation != UIInterfaceOrientationLandscapeLeft)
          { // regardless of given safe area, if notch is in left act for it
            frame.origin.x += MAX(safeArea.left, safeArea.right);
          }
            content.webView.frame = frame;
      }
   
  }
}

- (bool)hasTopNotch:(UIEdgeInsets)safeArea
{
  if (@available(iOS 11.0, *))
  {
    return safeArea.top >= 44;
  }
  else
  {
    return NO;
  }
}
@end
#endif
