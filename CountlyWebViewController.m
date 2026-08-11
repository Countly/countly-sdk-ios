// CountlyWebViewController.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.
//
#import "CountlyWebViewController.h"
#import "CountlyCommon.h"
#import "PassThroughBackgroundView.h"
#import "TouchDelegatingView.h"

#if (TARGET_OS_IOS || TARGET_OS_VISION)
@implementation CountlyWebViewController
{
    UIStatusBarStyle _cachedStatusBarStyle;
    BOOL _hasCachedStatusBarStyle;
}
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
    if (_hasCachedStatusBarStyle) {
        return _cachedStatusBarStyle;
    }
    
    UIWindow *keyWindow = [self getKeyWindow];

    if (keyWindow && keyWindow.rootViewController) {
        _cachedStatusBarStyle = keyWindow.rootViewController.preferredStatusBarStyle;
        _hasCachedStatusBarStyle = YES;
        return _cachedStatusBarStyle;
    }
    
    return UIStatusBarStyleLightContent;
}

// The view controller UIKit itself consults for this scene, or nil if unresolvable. This overlay
// can both widen and narrow what the whole scene allows (verified on iOS 18.4/26.0), so the mask
// must mirror the host: too wide rotates a locked app, too narrow force-rotates it out of
// landscape. Follows only window-filling presentations, and never descends into nav/tab children
// (UIKit asks the container) — which is why CountlyCommon.topViewController must not be reused.
- (UIViewController *)hostOrientationAuthority
{
    UIViewController *vc = [self getKeyWindow].rootViewController;

    if (!vc || vc == self)
    {
        return nil;
    }

    // Modals can be stacked; UIKit honours the topmost one that fills the window.
    while ([self fillsWindow:vc.presentedViewController] && vc.presentedViewController != self)
    {
        vc = vc.presentedViewController;
    }

    return vc;
}

// UIKit ignores the orientation preferences of sheet-style presentations.
- (BOOL)fillsWindow:(UIViewController *)viewController
{
    if (!viewController || viewController.isBeingDismissed)
    {
        return NO;
    }

    return viewController.modalPresentationStyle == UIModalPresentationFullScreen
        || viewController.modalPresentationStyle == UIModalPresentationOverFullScreen;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    UIViewController *authority = [self hostOrientationAuthority];

    // No resolvable host: stay permissive rather than constrain a scene we know nothing about.
    return authority ? [authority supportedInterfaceOrientations] : UIInterfaceOrientationMaskAll;
}

- (UIWindow *)getKeyWindow {
    // Unified key-window resolution (foreground-active scene, correct across multi-scene apps).
    return CountlyCommon.keyWindow;
}

// No shouldAutorotate override on purpose: UIViewController already defaults to YES, it is
// deprecated since iOS 16, and supportedInterfaceOrientations is what actually constrains rotation.

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    // Alongside the transition, not on completion: the view is already at the new size here, so the
    // page re-lays out during the rotation animation rather than a beat after it finishes.
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        if (self.sizeChangeHandler)
        {
            self.sizeChangeHandler(size);
        }
    } completion:nil];
}

- (void)loadView
{
    UIWindow *keyWindow = [self getKeyWindow];
    CGRect bounds = keyWindow.rootViewController.view.bounds;
    
    if (CGRectIsEmpty(bounds)) {
        bounds = CountlyCommon.screenBounds;
    }
    
    self.view = [[TouchDelegatingView alloc] initWithFrame:bounds];
}

- (void)viewDidLoad
{
  [super viewDidLoad];
    
    UIWindow *keyWindow = [self getKeyWindow];
    
    if (!_hasCachedStatusBarStyle) {
        if (keyWindow && keyWindow.rootViewController) {
            _cachedStatusBarStyle = keyWindow.rootViewController.preferredStatusBarStyle;
            _hasCachedStatusBarStyle = YES;
        }
    }


    if ([self.view isKindOfClass:[TouchDelegatingView class]])
    {
        TouchDelegatingView *delegatingView = (TouchDelegatingView *)self.view;
        if (keyWindow && keyWindow.rootViewController) {
            delegatingView.touchDelegate = keyWindow.rootViewController.view;
        }
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

    if ([self.contentView isKindOfClass:PassThroughBackgroundView.self])
    {
      PassThroughBackgroundView *content = (PassThroughBackgroundView *)self.contentView;
      // From the unadjusted placement, never the live frame: the shifts below are additive.
      CGRect                     frame   = CGRectIsNull(content.baseWebViewFrame) ? content.webView.frame : content.baseWebViewFrame;
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
