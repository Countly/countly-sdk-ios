// CountlyViewTracking.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface CountlyViewTracking ()
@property (nonatomic) NSTimeInterval lastViewStartTime;
@property (nonatomic) NSTimeInterval accumulatedTime;
@property (nonatomic, strong) NSMutableArray* exceptionViewControllers;
@end

NSString* const kCountlyReservedEventView = @"[CLY]_view";

NSString* const kCountlyVTKeyName =     @"name";
NSString* const kCountlyVTKeySegment =  @"segment";
NSString* const kCountlyVTKeyVisit =    @"visit";
NSString* const kCountlyVTKeyStart =    @"start";

@implementation CountlyViewTracking

+ (instancetype)sharedInstance
{
    static CountlyViewTracking* s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    if (self)
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

- (void)reportView:(NSString *)viewName
{
    [self endView];

    COUNTLY_LOG(@"View tracking started: %@", viewName);

    NSMutableDictionary* segmentation =
    @{
        kCountlyVTKeyName: viewName,
        kCountlyVTKeySegment: CountlyDeviceInfo.osName,
        kCountlyVTKeyVisit: @1
    }.mutableCopy;

    if (!self.lastView)
        segmentation[kCountlyVTKeyStart] = @1;

    [Countly.sharedInstance recordEvent:kCountlyReservedEventView segmentation:segmentation];

    self.lastView = viewName;
    self.lastViewStartTime = CountlyCommon.sharedInstance.uniqueTimestamp;
}

- (void)endView
{
    if (self.lastView)
    {
        NSDictionary* segmentation =
        @{
            kCountlyVTKeyName: self.lastView,
            kCountlyVTKeySegment: CountlyDeviceInfo.osName,
        };

        NSTimeInterval duration = NSDate.date.timeIntervalSince1970 - self.lastViewStartTime + self.accumulatedTime;
        self.accumulatedTime = 0;
        [Countly.sharedInstance recordEvent:kCountlyReservedEventView segmentation:segmentation count:1 sum:0 duration:duration timestamp:self.lastViewStartTime];

        COUNTLY_LOG(@"View tracking ended: %@ duration: %f", self.lastView, duration);
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

#if (TARGET_OS_IOS || TARGET_OS_TV)
- (void)startAutoViewTracking
{
    self.isAutoViewTrackingEnabled = YES;

    Method O_method;
    Method C_method;

    O_method = class_getInstanceMethod(UIViewController.class, @selector(viewDidAppear:));
    C_method = class_getInstanceMethod(UIViewController.class, @selector(Countly_viewDidAppear:));
    method_exchangeImplementations(O_method, C_method);
}

- (void)addExceptionForAutoViewTracking:(NSString *)exception
{
    if (![self.exceptionViewControllers containsObject:exception])
        [self.exceptionViewControllers addObject:exception];
}

- (void)removeExceptionForAutoViewTracking:(NSString *)exception
{
    [self.exceptionViewControllers removeObject:exception];
}

#endif
@end

#pragma mark -

#if (TARGET_OS_IOS || TARGET_OS_TV)
@implementation UIViewController (CountlyViewTracking)
- (void)Countly_viewDidAppear:(BOOL)animated
{
    NSString* viewTitle = self.title;

    if (!viewTitle)
        viewTitle = [self.navigationItem.titleView isKindOfClass:UILabel.class] ? ((UILabel*)self.navigationItem.titleView).text : nil;

    if (!viewTitle)
        viewTitle = NSStringFromClass(self.class);

    if (CountlyViewTracking.sharedInstance.isAutoViewTrackingEnabled && ![CountlyViewTracking.sharedInstance.lastView isEqualToString:viewTitle])
    {
        BOOL isException = NO;

        for (NSString* exception in CountlyViewTracking.sharedInstance.exceptionViewControllers)
        {
            BOOL isExceptionClass = [self isKindOfClass:NSClassFromString(exception)] || [NSStringFromClass(self.class) isEqualToString:exception];
            BOOL isExceptionTitle = [self.title isEqualToString:exception];
            BOOL isExceptionCustomTitle = [self.navigationItem.titleView isKindOfClass:UILabel.class] && [((UILabel*)self.navigationItem.titleView).text isEqualToString:exception];

            if (isExceptionClass || isExceptionTitle || isExceptionCustomTitle)
            {
                isException = YES;
                break;
            }
        }

        if (!isException)
            [CountlyViewTracking.sharedInstance reportView:viewTitle];
    }

    [self Countly_viewDidAppear:animated];
}
@end
#endif
