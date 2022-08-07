// CountlyViewTracking.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface CountlyViewTracking ()
@property (nonatomic) NSString* lastView;
@property (nonatomic) NSTimeInterval lastViewStartTime;
@property (nonatomic) NSTimeInterval accumulatedTime;
@property (nonatomic) NSMutableArray* exceptionViewControllers;
@end

NSString* const kCountlyReservedEventView = @"[CLY]_view";

NSString* const kCountlyVTKeyName     = @"name";
NSString* const kCountlyVTKeySegment  = @"segment";
NSString* const kCountlyVTKeyVisit    = @"visit";
NSString* const kCountlyVTKeyStart    = @"start";
NSString* const kCountlyVTKeyBounce   = @"bounce";
NSString* const kCountlyVTKeyExit     = @"exit";
NSString* const kCountlyVTKeyView     = @"view";
NSString* const kCountlyVTKeyDomain   = @"domain";
NSString* const kCountlyVTKeyDur      = @"dur";

#if (TARGET_OS_IOS || TARGET_OS_TV)
@interface UIViewController (CountlyViewTracking)
- (void)Countly_viewDidAppear:(BOOL)animated;
- (void)Countly_viewDidDisappear:(BOOL)animated;
@end
#endif

@implementation CountlyViewTracking

+ (instancetype)sharedInstance
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return nil;

    static CountlyViewTracking* s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    if (self = [super init])
    {
        self.exceptionViewControllers =
        @[
            @"CLYInternalViewController",
            @"UINavigationController",
            @"UIAlertController",
            @"UIPageViewController",
            @"UITabBarController",
            @"UIReferenceLibraryViewController",
            @"UISplitViewController",
            @"UIInputViewController",
            @"UISearchController",
            @"UISearchContainerViewController",
            @"UIApplicationRotationFollowingController",
            @"MFMailComposeInternalViewController",
            @"MFMailComposeInternalViewController",
            @"MFMailComposePlaceholderViewController",
            @"UIInputWindowController",
            @"_UIFallbackPresentationViewController",
            @"UIActivityViewController",
            @"UIActivityGroupViewController",
            @"_UIActivityGroupListViewController",
            @"_UIActivityViewControllerContentController",
            @"UIKeyboardCandidateRowViewController",
            @"UIKeyboardCandidateGridCollectionViewController",
            @"UIPrintMoreOptionsTableViewController",
            @"UIPrintPanelTableViewController",
            @"UIPrintPanelViewController",
            @"UIPrintPaperViewController",
            @"UIPrintPreviewViewController",
            @"UIPrintRangeViewController",
            @"UIDocumentMenuViewController",
            @"UIDocumentPickerViewController",
            @"UIDocumentPickerExtensionViewController",
            @"UIInterfaceActionGroupViewController",
            @"UISystemInputViewController",
            @"UIRecentsInputViewController",
            @"UICompatibilityInputViewController",
            @"UIInputViewAnimationControllerViewController",
            @"UISnapshotModalViewController",
            @"UIMultiColumnViewController",
            @"UIKeyCommandDiscoverabilityHUDViewController"
        ].mutableCopy;
    }

    return self;
}

#pragma mark -

- (void)startView:(NSString *)viewName
{
    [self startView:viewName customSegmentation:nil];
}

- (void)startView:(NSString *)viewName customSegmentation:(NSDictionary *)customSegmentation
{
    if (!viewName.length)
        return;

    if (!CountlyConsentManager.sharedInstance.consentForViewTracking)
        return;

    viewName = viewName.copy;

    [self endView];

    CLY_LOG_D(@"View tracking started: %@", viewName);

    viewName = [viewName cly_truncatedKey:@"View name"];

    NSMutableDictionary* segmentation = NSMutableDictionary.new;
    segmentation[kCountlyVTKeyName] = viewName;
    segmentation[kCountlyVTKeySegment] = CountlyDeviceInfo.osName;
    segmentation[kCountlyVTKeyVisit] = @1;

    if (!self.lastView)
        segmentation[kCountlyVTKeyStart] = @1;

    if (customSegmentation)
    {
        NSMutableDictionary* mutableCustomSegmentation = customSegmentation.mutableCopy;
        [mutableCustomSegmentation removeObjectsForKeys:self.reservedViewTrackingSegmentationKeys];
        [segmentation addEntriesFromDictionary:mutableCustomSegmentation];
    }

    [Countly.sharedInstance recordReservedEvent:kCountlyReservedEventView segmentation:segmentation];

    self.lastView = viewName;
    self.lastViewStartTime = CountlyCommon.sharedInstance.uniqueTimestamp;
}

- (void)endView
{
    if (!CountlyConsentManager.sharedInstance.consentForViewTracking)
        return;

    if (self.lastView)
    {
        NSMutableDictionary* segmentation = NSMutableDictionary.new;
        segmentation[kCountlyVTKeyName] = self.lastView;
        segmentation[kCountlyVTKeySegment] = CountlyDeviceInfo.osName;

        NSTimeInterval duration = NSDate.date.timeIntervalSince1970 - self.lastViewStartTime + self.accumulatedTime;
        self.accumulatedTime = 0;
        [Countly.sharedInstance recordReservedEvent:kCountlyReservedEventView segmentation:segmentation count:1 sum:0 duration:duration timestamp:self.lastViewStartTime];

        CLY_LOG_D(@"View tracking ended: %@ duration: %.17g", self.lastView, duration);
    }
}

- (void)pauseView
{
    if (self.lastViewStartTime)
        self.accumulatedTime = NSDate.date.timeIntervalSince1970 - self.lastViewStartTime;
}

- (void)resumeView
{
    self.lastViewStartTime = CountlyCommon.sharedInstance.uniqueTimestamp;
}

#pragma mark -

#if (TARGET_OS_IOS || TARGET_OS_TV)
- (void)startAutoViewTracking
{
    if (!self.isEnabledOnInitialConfig)
        return;

    if (!CountlyConsentManager.sharedInstance.consentForViewTracking)
        return;

    self.isAutoViewTrackingActive = YES;

    [self swizzleViewTrackingMethods];

    UIViewController* topVC = CountlyCommon.sharedInstance.topViewController;
    NSString* viewTitle = [CountlyViewTracking.sharedInstance titleForViewController:topVC];
    [self startView:viewTitle];
}

- (void)swizzleViewTrackingMethods
{
    static BOOL alreadySwizzled;
    if (alreadySwizzled)
        return;

    alreadySwizzled = YES;

    Method O_method = class_getInstanceMethod(UIViewController.class, @selector(viewDidAppear:));
    Method C_method = class_getInstanceMethod(UIViewController.class, @selector(Countly_viewDidAppear:));
    method_exchangeImplementations(O_method, C_method);
    O_method = class_getInstanceMethod(UIViewController.class, @selector(viewDidDisappear:));
    C_method = class_getInstanceMethod(UIViewController.class, @selector(Countly_viewDidDisappear:));
    method_exchangeImplementations(O_method, C_method);
}

- (void)stopAutoViewTracking
{
    self.isAutoViewTrackingActive = NO;

    self.lastView = nil;
    self.lastViewStartTime = 0;
    self.accumulatedTime = 0;
}

- (void)performAutoViewTrackingForViewController:(UIViewController *)viewController
{
    if (!self.isAutoViewTrackingActive)
        return;

    if (!CountlyConsentManager.sharedInstance.consentForViewTracking)
        return;

    NSString* viewTitle = [self titleForViewController:viewController];

    if ([self.lastView isEqualToString:viewTitle])
        return;

    BOOL isException = NO;

    for (NSString* exception in self.exceptionViewControllers)
    {
        isException = [viewTitle isEqualToString:exception] ||
                      [viewController isKindOfClass:NSClassFromString(exception)] ||
                      [NSStringFromClass(viewController.class) isEqualToString:exception];

        if (isException)
        {
            CLY_LOG_V(@"%@ is an exceptional view, so it will be ignored for view tracking.", viewTitle);
            break;
        }
    }

    if (!isException)
        [self startView:viewTitle];
}


#pragma mark -

- (void)setIsAutoViewTrackingActive:(BOOL)isAutoViewTrackingActive
{
    if (!self.isEnabledOnInitialConfig)
        return;

    if (!CountlyConsentManager.sharedInstance.consentForViewTracking)
        return;

    _isAutoViewTrackingActive = isAutoViewTrackingActive;
}

#pragma mark -

- (void)addExceptionForAutoViewTracking:(NSString *)exception
{
    if (!exception.length)
        return;

    if (![self.exceptionViewControllers containsObject:exception])
        [self.exceptionViewControllers addObject:exception];
}

- (void)removeExceptionForAutoViewTracking:(NSString *)exception
{
    [self.exceptionViewControllers removeObject:exception];
}

#pragma mark -

- (NSString*)titleForViewController:(UIViewController *)viewController
{
    if (!viewController)
        return nil;

    NSString* title = nil;

    if ([viewController respondsToSelector:@selector(countlyAutoViewTrackingName)])
    {
        CLY_LOG_I(@"Viewcontroller conforms to CountlyAutoViewTrackingName protocol for custom auto view tracking name.");
        title = [(id<CountlyAutoViewTrackingName>)viewController countlyAutoViewTrackingName];
    }

    if (!title)
        title = viewController.title;

    if (!title)
        title = [viewController.navigationItem.titleView isKindOfClass:UILabel.class] ? ((UILabel *)viewController.navigationItem.titleView).text : nil;

    if (!title)
        title = viewController.navigationItem.title;

    if (!title)
        title = NSStringFromClass(viewController.class);

    return title;
}

#endif

- (NSArray *)reservedViewTrackingSegmentationKeys
{
    NSArray* reservedViewTrackingSegmentationKeys =
    @[
        kCountlyVTKeyName,
        kCountlyVTKeySegment,
        kCountlyVTKeyVisit,
        kCountlyVTKeyStart,
        kCountlyVTKeyBounce,
        kCountlyVTKeyExit,
        kCountlyVTKeyView,
        kCountlyVTKeyDomain,
        kCountlyVTKeyDur
    ];

    return reservedViewTrackingSegmentationKeys;
}

@end

#pragma mark -

#if (TARGET_OS_IOS || TARGET_OS_TV)
@implementation UIViewController (CountlyViewTracking)
- (void)Countly_viewDidAppear:(BOOL)animated
{
    [self Countly_viewDidAppear:animated];

    [CountlyViewTracking.sharedInstance performAutoViewTrackingForViewController:self];

    if (self.isPageSheetModal)
    {
        //NOTE: Since iOS 13, modals with PageSheet presentation style
        //     does not trigger `viewDidAppear` on presenting view controller when they are dismissed.
        //      Also, `self.presentingViewController` property is nil in both `viewWillDisappear` and `viewDidDisappear`.
        //      So, we store it here in modal's `viewDidAppear` to be used for view tracking later.
        CLY_LOG_I(@"A modal view controller with PageSheet presentation style is presented on iOS 13+. Storing presenting view controller to be used later.");

        UIViewController* presenting = self.presentingViewController;
        if ([presenting isKindOfClass:UINavigationController.class])
        {
            presenting = ((UINavigationController *)presenting).topViewController;
        }

        self.presentingVC = presenting;
    }
}

- (void)Countly_viewDidDisappear:(BOOL)animated
{
    [self Countly_viewDidDisappear:animated];

    if (self.presentingVC)
    {
        CLY_LOG_I(@"A modal view controller with PageSheet presentation style is dismissed on iOS 13+. Forcing auto view tracking with stored presenting view controller.");
        [CountlyViewTracking.sharedInstance performAutoViewTrackingForViewController:self.presentingVC];
        self.presentingVC = nil;
    }
}

- (BOOL)isPageSheetModal
{
    //NOTE: iOS 13 check is not related to availability of UIModalPresentationPageSheet,
    //      but needed due to behavioral difference in presenting logic compared to previous iOS versions.
#if (TARGET_OS_IOS)
    if (@available(iOS 13.0, *))
    {
        if (self.modalPresentationStyle == UIModalPresentationPageSheet && self.isBeingPresented)
        {
            return YES;
        }
    }
#endif

    return NO;
}

- (void)setPresentingVC:(UIViewController *)presentingVC
{
    objc_setAssociatedObject(self, @selector(presentingVC), presentingVC, OBJC_ASSOCIATION_ASSIGN);
}

- (UIViewController *)presentingVC
{
    return objc_getAssociatedObject(self, @selector(presentingVC));
}

@end
#endif
