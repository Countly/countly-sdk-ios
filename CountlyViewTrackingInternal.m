// CountlyViewTracking.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface CountlyViewTrackingInternal ()
#if (TARGET_OS_IOS || TARGET_OS_TV)
@property (nonatomic) NSMutableSet* automaticViewTrackingExclusionList;
#endif
@property (nonatomic, strong) NSMutableDictionary<NSString*, CountlyViewData *> * viewDataDictionary;
@property (nonatomic) NSMutableDictionary* viewSegmentation;
@property (nonatomic) BOOL isFirstView;
@end

NSString* const kCountlyReservedEventView = @"[CLY]_view";

NSString* const kCountlyCurrentView = @"cly_cvn";
NSString* const kCountlyPreviousView = @"cly_pvn";

NSString* const kCountlyPreviousEventName = @"cly_pen";

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

@implementation CountlyViewTrackingInternal

+ (instancetype)sharedInstance
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return nil;
    
    static CountlyViewTrackingInternal* s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    if (self = [super init])
    {
#if (TARGET_OS_IOS || TARGET_OS_TV)
        self.automaticViewTrackingExclusionList =
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
#endif
        
        self.viewDataDictionary = NSMutableDictionary.new;
        self.viewSegmentation = nil;
        self.isFirstView = YES;
    }
    
    return self;
}

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

#pragma mark - Public methods

- (void)setGlobalViewSegmentation:(NSMutableDictionary *)segmentation
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, segmentation);
    NSMutableDictionary *mutableSegmentation = segmentation.mutableCopy;
    [mutableSegmentation removeObjectsForKeys:self.reservedViewTrackingSegmentationKeys];
    NSDictionary *filteredSegmentation = mutableSegmentation.cly_filterSupportedDataTypes;
    self.viewSegmentation = filteredSegmentation.mutableCopy;
    
}

- (void)updateGlobalViewSegmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, segmentation);
    if (!self.viewSegmentation) {
        self.viewSegmentation = NSMutableDictionary.new;
    }
    
    NSMutableDictionary *mutableSegmentation = segmentation.mutableCopy;
    [mutableSegmentation removeObjectsForKeys:self.reservedViewTrackingSegmentationKeys];
    NSDictionary *filteredSegmentation = mutableSegmentation.cly_filterSupportedDataTypes;
    [self.viewSegmentation addEntriesFromDictionary:filteredSegmentation];
}

- (NSString *)startView:(NSString *)viewName segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, viewName, segmentation);
#if (TARGET_OS_IOS || TARGET_OS_TV)
    if (self.isAutoViewTrackingActive) {
        CLY_LOG_W(@"%s Manually start view tracking is not allowed when automatic tracking is enabled!", __FUNCTION__);
        return nil;
    }
#endif
    NSString* viewID = [self startViewInternal:viewName customSegmentation:segmentation];
    return viewID;
}

- (NSString *)startAutoStoppedView:(NSString *)viewName segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, viewName, segmentation);
#if (TARGET_OS_IOS || TARGET_OS_TV)
    if (self.isAutoViewTrackingActive) {
        CLY_LOG_W(@"%s Manually start view tracking is not allowed when automatic tracking is enabled!", __FUNCTION__);
        return nil;
    }
#endif
    NSString* viewID = [self startViewInternal:viewName customSegmentation:segmentation isAutoStoppedView:YES];
    return viewID;
}

- (void)stopViewWithName:(NSString *)viewName segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, viewName, segmentation);
#if (TARGET_OS_IOS || TARGET_OS_TV)
    if (self.isAutoViewTrackingActive) {
        CLY_LOG_W(@"%s Manually stop view tracking is not allowed when automatic tracking is enabled!", __FUNCTION__);
        return;
    }
#endif
    [self stopViewWithNameInternal:viewName customSegmentation:segmentation];
    
}

- (void)stopViewWithID:(NSString *)viewID segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, viewID, segmentation);
#if (TARGET_OS_IOS || TARGET_OS_TV)
    if (self.isAutoViewTrackingActive) {
        CLY_LOG_W(@"%s Manually stop view tracking is not allowed when automatic tracking is enabled!", __FUNCTION__);
        return;
    }
#endif
    [self stopViewWithIDInternal:viewID customSegmentation:segmentation];
}

- (void)pauseViewWithID:(NSString *)viewID
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, viewID);
#if (TARGET_OS_IOS || TARGET_OS_TV)
    if (self.isAutoViewTrackingActive) {
        CLY_LOG_W(@"%s Manually pause view tracking is not allowed when automatic tracking is enabled!", __FUNCTION__);
        return;
    }
#endif
    [self pauseViewWithIDInternal:viewID];
    
}
- (void)resumeViewWithID:(NSString *)viewID
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, viewID);
#if (TARGET_OS_IOS || TARGET_OS_TV)
    if (self.isAutoViewTrackingActive) {
        CLY_LOG_W(@"%s Manually resume view tracking is not allowed when automatic tracking is enabled!", __FUNCTION__);
        return;
    }
#endif
    [self resumeViewWithIDInternal:viewID];
}

- (void)stopAllViews:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, segmentation);
#if (TARGET_OS_IOS || TARGET_OS_TV)
    if (self.isAutoViewTrackingActive) {
        CLY_LOG_W(@"%s Manually stop view tracking is not allowed when automatic tracking is enabled!", __FUNCTION__);
        return;
    }
#endif
    [self stopAllViewsInternal:segmentation];
    
}

#if (TARGET_OS_IOS || TARGET_OS_TV)
- (void)addAutoViewTrackingExclutionList:(NSArray *)viewTrackingExclusionList
{
    [self.automaticViewTrackingExclusionList addObjectsFromArray:viewTrackingExclusionList];
}

- (void)startAutoViewTracking
{
    if (!self.isEnabledOnInitialConfig)
        return;
    
    if (!CountlyConsentManager.sharedInstance.consentForViewTracking)
        return;
    
    self.isAutoViewTrackingActive = YES;
    
    [self swizzleViewTrackingMethods];
    
    UIViewController* topVC = CountlyCommon.sharedInstance.topViewController;
    NSString* viewTitle = [self titleForViewController:topVC];
    [self startViewInternal:viewTitle customSegmentation:nil];
}

- (void)stopAutoViewTracking
{
    self.isAutoViewTrackingActive = NO;
    
    //    self.currentView = nil;
    //    self.currentViewID = nil;
}

- (void)setIsAutoViewTrackingActive:(BOOL)isAutoViewTrackingActive
{
    if (!self.isEnabledOnInitialConfig)
        return;
    
    if (!CountlyConsentManager.sharedInstance.consentForViewTracking)
        return;
    if (_isAutoViewTrackingActive != isAutoViewTrackingActive) {
        [self stopAllViewsInternal:nil];
    }
    
    _isAutoViewTrackingActive = isAutoViewTrackingActive;
}


#pragma mark - Public methods Deprecated

- (void)addExceptionForAutoViewTracking:(NSString *)exception
{
    if (!exception.length)
        return;
    
    [self.automaticViewTrackingExclusionList addObject:exception];
}

- (void)removeExceptionForAutoViewTracking:(NSString *)exception
{
    [self.automaticViewTrackingExclusionList removeObject:exception];
}

#endif

#pragma mark - Internal methods old
- (void)stopViewWithNameInternal:(NSString *) viewName customSegmentation:(NSDictionary *)customSegmentation
{
    if (!viewName || !viewName.length)
    {
        CLY_LOG_D(@"%s View name should not be null or empty", __FUNCTION__);
        return;
    }
    
    if (!CountlyConsentManager.sharedInstance.consentForViewTracking)
        return;
    __block NSString *viewID = nil;
    [self.viewDataDictionary enumerateKeysAndObjectsUsingBlock:^(NSString * key, CountlyViewData * viewData, BOOL * stop)
     {
        if ([viewData.viewName isEqualToString:viewName])
        {
            viewID = key;
            *stop = YES;
        }
        
    }];
    
    if (viewID)
    {
        [self stopViewWithIDInternal:viewID customSegmentation:customSegmentation];
    }
    else {
        CLY_LOG_D(@"%s No View exist with name: %@", __FUNCTION__, viewName);
    }
}

- (void)stopViewWithIDInternal:(NSString *) viewKey customSegmentation:(NSDictionary *)customSegmentation
{
    [self stopViewWithIDInternal:viewKey customSegmentation:customSegmentation autoPaused:NO];
}

- (void)stopViewWithIDInternal:(NSString *) viewKey customSegmentation:(NSDictionary *)customSegmentation autoPaused:(BOOL) autoPaused{
    if (!viewKey || !viewKey.length)
    {
        CLY_LOG_D(@"%s View ID should not be null or empty", __FUNCTION__);
        return;
    }
    
    if (!CountlyConsentManager.sharedInstance.consentForViewTracking)
        return;
    CountlyViewData* viewData = self.viewDataDictionary[viewKey];
    if (viewData)
    {
        NSMutableDictionary* segmentation = NSMutableDictionary.new;
        
        if (viewData.segmentation)
        {
            [segmentation addEntriesFromDictionary:viewData.segmentation];
        }
        
        if (self.viewSegmentation)
        {
            [segmentation addEntriesFromDictionary:self.viewSegmentation];
        }
        
        if (customSegmentation)
        {
            NSMutableDictionary* mutableCustomSegmentation = customSegmentation.mutableCopy;
            [mutableCustomSegmentation removeObjectsForKeys:self.reservedViewTrackingSegmentationKeys];
            NSDictionary *filteredSegmentation = mutableCustomSegmentation.cly_filterSupportedDataTypes;
            [segmentation addEntriesFromDictionary:filteredSegmentation];
        }
        
        NSDictionary* segmentationTruncated = [segmentation cly_truncated:@"View segmentation"];
        segmentation = [segmentationTruncated cly_limited:@"View segmentation"].mutableCopy;
        
        segmentation[kCountlyVTKeyName] = viewData.viewName;
        segmentation[kCountlyVTKeySegment] = CountlyDeviceInfo.osName;
        
        NSInteger duration = viewData.duration;
        [Countly.sharedInstance recordReservedEvent:kCountlyReservedEventView segmentation:segmentation count:1 sum:0 duration:duration ID:viewData.viewID timestamp:CountlyCommon.sharedInstance.uniqueTimestamp];
        
        CLY_LOG_D(@"%s View tracking ended: %@ duration: %ld", __FUNCTION__, viewData.viewName, (long)duration);
        if (!autoPaused) {
            [self.viewDataDictionary removeObjectForKey:viewKey];
        }
    }
    else {
        CLY_LOG_D(@"%s No View exist with ID: %@", __FUNCTION__, viewKey);
    }
}

- (NSString*)startViewInternal:(NSString *)viewName customSegmentation:(NSDictionary *)customSegmentation
{
    return [self startViewInternal:viewName customSegmentation:customSegmentation isAutoStoppedView:NO];
}

- (NSString*)startViewInternal:(NSString *)viewName customSegmentation:(NSDictionary *)customSegmentation isAutoStoppedView:(BOOL) isAutoStoppedView
{
    if (!viewName || !viewName.length)
    {
        CLY_LOG_D(@"%s View name should not be null or empty", __FUNCTION__);
        return nil;
    }
    
    if (!CountlyConsentManager.sharedInstance.consentForViewTracking)
        return nil;
    
    [self stopAutoStoppedView];
    
    viewName = viewName.copy;
    
    CLY_LOG_D(@"%s View tracking started: %@", __FUNCTION__, viewName);
    
    viewName = [viewName cly_truncatedKey:@"View name"];
    
    NSMutableDictionary* segmentation = NSMutableDictionary.new;
    
    if (self.viewSegmentation)
    {
        [segmentation addEntriesFromDictionary:self.viewSegmentation];
    }
    
    if (customSegmentation)
    {
        NSMutableDictionary* mutableCustomSegmentation = customSegmentation.mutableCopy;
        [mutableCustomSegmentation removeObjectsForKeys:self.reservedViewTrackingSegmentationKeys];
        NSDictionary *filteredSegmentation = mutableCustomSegmentation.cly_filterSupportedDataTypes;
        [segmentation addEntriesFromDictionary:filteredSegmentation];
    }
    
    NSDictionary* segmentationTruncated = [segmentation cly_truncated:@"View segmentation"];
    segmentation = [segmentationTruncated cly_limited:@"View segmentation"].mutableCopy;
    
    segmentation[kCountlyVTKeyName] = viewName;
    segmentation[kCountlyVTKeySegment] = CountlyDeviceInfo.osName;
    segmentation[kCountlyVTKeyVisit] = @1;
    
    if (self.isFirstView && [CountlyConnectionManager.sharedInstance isSessionStarted])
    {
        self.isFirstView = NO;
        segmentation[kCountlyVTKeyStart] = @1;
    }
    
    self.previousViewID = self.currentViewID;
    self.currentViewID = CountlyCommon.sharedInstance.randomEventID;
    
    self.previousViewName = self.currentViewName;
    self.currentViewName = viewName;
    
    CountlyViewData *viewData = [[CountlyViewData alloc] initWithID:self.currentViewID viewName:viewName];
    viewData.startSegmentation = customSegmentation.mutableCopy;
    viewData.isAutoStoppedView = isAutoStoppedView;
    self.viewDataDictionary[self.currentViewID] = viewData;
    
    [Countly.sharedInstance recordReservedEvent:kCountlyReservedEventView segmentation:segmentation ID:self.currentViewID];
    
    CLY_LOG_D(@"%s View name: %@ View ID: %@ isAutoStoppedView: %@", __FUNCTION__, viewName, self.currentViewID, isAutoStoppedView ? @"YES" : @"NO");
    
    return self.currentViewID;
}

- (void)pauseViewWithIDInternal:(NSString *) viewID
{
    if (!viewID || !viewID.length)
    {
        CLY_LOG_D(@"%s View ID should not be null or empty", __FUNCTION__);
        return;
    }
    
    if (!CountlyConsentManager.sharedInstance.consentForViewTracking)
        return;
    CountlyViewData* viewData = self.viewDataDictionary[viewID];
    if (viewData)
    {
        [self pauseViewInternal:viewData];
    }
    else {
        CLY_LOG_D(@"%s No View exist with ID: %@", __FUNCTION__, viewID);
    }
}

- (void)resumeViewWithIDInternal:(NSString *) viewID
{
    if (!viewID || !viewID.length)
    {
        CLY_LOG_D(@"%s View ID should not be null or empty", __FUNCTION__);
        return;
    }
    
    if (!CountlyConsentManager.sharedInstance.consentForViewTracking)
        return;
    CountlyViewData* viewData = self.viewDataDictionary[viewID];
    if (viewData)
    {
        [viewData resumeView];
    }
    
    else {
        CLY_LOG_D(@"%s No View exist with ID: %@", __FUNCTION__, viewID);
    }
}

-(CountlyViewData* ) currentView
{
    if (!self.currentViewID)
        return nil;
    return [self.viewDataDictionary objectForKey:self.currentViewID];
}

- (void)stopAutoStoppedView
{
    CountlyViewData* currentView = self.currentView;
    if (currentView && currentView.isAutoStoppedView && !currentView.willStartAgain)
    {
        [self stopViewWithIDInternal:self.currentView.viewID customSegmentation:nil];
    }
}


- (void)stopCurrentView
{
    if (self.currentView)
    {
        [self stopViewWithIDInternal:self.currentView.viewID customSegmentation:nil];
    }
}


- (void)stopRunningViewsInternal
{
    [self.viewDataDictionary enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, CountlyViewData * _Nonnull viewData, BOOL * _Nonnull stop) {
        viewData.willStartAgain = YES;
        [self stopViewWithIDInternal:viewData.viewID customSegmentation:nil autoPaused:YES];
    }];
}

- (void)pauseViewInternal:(CountlyViewData*) viewData
{
    [self stopViewWithIDInternal:viewData.viewID customSegmentation:nil autoPaused:YES];
    [viewData pauseView];
}

- (void)startStoppedViewsInternal
{
    // Create an array to store keys for views that need to be removed
    NSMutableArray<NSString *> *keysToRemove = [NSMutableArray array];
    NSMutableArray<NSString *> *keysToStart = [NSMutableArray array];
    
    // Collect keys without modifying the dictionary
    [self.viewDataDictionary enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, CountlyViewData * _Nonnull viewData, BOOL * _Nonnull stop) {
        if (viewData.willStartAgain)
        {
            [keysToStart addObject:key];
            [keysToRemove addObject:viewData.viewID];
        }
    }];
    
    // Start the collected views after enumeration
    for (NSString *key in keysToStart)
    {
        CountlyViewData *viewData = self.viewDataDictionary[key];
        NSString *viewID = [self startViewInternal:viewData.viewName customSegmentation:viewData.startSegmentation isAutoStoppedView:viewData.isAutoStoppedView];
        
        // Retrieve and update the newly created viewData
        CountlyViewData *viewDataNew = self.viewDataDictionary[viewID];
        viewDataNew.segmentation = viewData.segmentation.mutableCopy;
    }
    
    // Remove the entries from the dictionary
    [self.viewDataDictionary removeObjectsForKeys:keysToRemove];
}


- (void)stopAllViewsInternal:(NSDictionary *)segmentation
{
    // TODO: Should apply all the segmenation operations here at one place instead of doing it for individual view
    if (!CountlyConsentManager.sharedInstance.consentForViewTracking)
        return;
    [self.viewDataDictionary enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, CountlyViewData * _Nonnull viewData, BOOL * _Nonnull stop) {
        [self stopViewWithIDInternal:key customSegmentation:segmentation];
    }];
}

- (void)addSegmentationToViewWithNameInternal:(NSString *) viewName segmentation:(NSDictionary *)segmentation
{
    if (!viewName || !viewName.length)
    {
        CLY_LOG_D(@"%s View name should not be null or empty", __FUNCTION__);
        return;
    }
    
    __block NSString *viewID = nil;
    [self.viewDataDictionary enumerateKeysAndObjectsUsingBlock:^(NSString * key, CountlyViewData * viewData, BOOL * stop)
     {
        if ([viewData.viewName isEqualToString:viewName])
        {
            viewID = key;
            *stop = YES;
        }
        
    }];
    
    if (viewID)
    {
        [self addSegmentationToViewWithIDInternal:viewID segmentation:segmentation];
    }
    else {
        CLY_LOG_D(@"%s No View exist with name: %@", __FUNCTION__, viewName);
    }
}

- (void)addSegmentationToViewWithIDInternal:(NSString *) viewID segmentation:(NSDictionary *)segmentation{
    if (!viewID || !viewID.length)
    {
        CLY_LOG_D(@"%s View ID should not be null or empty", __FUNCTION__);
        return;
    }
    
    if (!CountlyConsentManager.sharedInstance.consentForViewTracking)
        return;
    CountlyViewData* viewData = self.viewDataDictionary[viewID];
    if (viewData)
    {
        NSMutableDictionary *mutableSegmentation = segmentation.mutableCopy;
        [mutableSegmentation removeObjectsForKeys:self.reservedViewTrackingSegmentationKeys];
        NSDictionary *filteredSegmentation = mutableSegmentation.cly_filterSupportedDataTypes;
        if(filteredSegmentation) {
            if(!viewData.segmentation) {
                viewData.segmentation = NSMutableDictionary.new;
            }
            [viewData.segmentation addEntriesFromDictionary:filteredSegmentation];
        }
        [self.viewDataDictionary setObject:viewData forKey:viewID];
    }
    else {
        CLY_LOG_D(@"%s No View exist with ID: %@", __FUNCTION__, viewID);
    }
}


- (void)addSegmentationToViewWithID:(NSString *)viewID segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, viewID, segmentation);
    [self addSegmentationToViewWithIDInternal:viewID segmentation:segmentation];
}

- (void)addSegmentationToViewWithName:(NSString *)viewName segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, viewName, segmentation);
    [self addSegmentationToViewWithNameInternal:viewName segmentation:segmentation];
}

#pragma mark - Internal auto view tracking methods

#if (TARGET_OS_IOS || TARGET_OS_TV)

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

- (void)performAutoViewTrackingForViewController:(UIViewController *)viewController
{
    if (!self.isAutoViewTrackingActive)
        return;
    
    if (!CountlyConsentManager.sharedInstance.consentForViewTracking)
        return;
    
    NSString* viewTitle = [self titleForViewController:viewController];
    
    if (self.currentView && [self.currentView.viewName isEqualToString:viewTitle])
        return;
    
    BOOL isException = NO;
    
    for (NSString* exception in self.automaticViewTrackingExclusionList)
    {
        isException = [viewTitle isEqualToString:exception] ||
        [viewController isKindOfClass:NSClassFromString(exception)] ||
        [NSStringFromClass(viewController.class) isEqualToString:exception];
        
        if (isException)
        {
            CLY_LOG_V(@"%s %@ is an exceptional view, so it will be ignored for view tracking.", __FUNCTION__, viewTitle);
            break;
        }
    }
    
    if (!isException)
        [self startViewInternal:viewTitle customSegmentation:nil];
}


- (NSString*)titleForViewController:(UIViewController *)viewController
{
    if (!viewController)
        return nil;
    
    NSString* title = nil;
    
    if ([viewController respondsToSelector:@selector(countlyAutoViewTrackingName)])
    {
        CLY_LOG_I(@"%s Viewcontroller conforms to CountlyAutoViewTrackingName protocol for custom auto view tracking name.", __FUNCTION__);
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

#pragma mark - Public function for application state

- (void)applicationWillEnterForeground {
#if (TARGET_OS_IOS  || TARGET_OS_VISION || TARGET_OS_TV)
    if (!self.isAutoViewTrackingActive) {
        [self startStoppedViewsInternal];
    }
#else
    [self startStoppedViewsInternal];
#endif
}
- (void)applicationDidEnterBackground {
#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_TV)
    if (self.isAutoViewTrackingActive) {
        [self stopCurrentView];
    }
    else {
        [self stopRunningViewsInternal];
    }
#else
    [self stopRunningViewsInternal];
#endif
}

- (void)applicationWillTerminate {
    [self stopAllViewsInternal:nil];
}


- (void)resetFirstView
{
    self.isFirstView = YES;
}


@end

#pragma mark -

#if (TARGET_OS_IOS || TARGET_OS_TV)
@implementation UIViewController (CountlyViewTracking)
- (void)Countly_viewDidAppear:(BOOL)animated
{
    [self Countly_viewDidAppear:animated];

    [CountlyViewTrackingInternal.sharedInstance performAutoViewTrackingForViewController:self];

    if (self.isPageSheetModal)
    {
        //NOTE: Since iOS 13, modals with PageSheet presentation style
        //     does not trigger `viewDidAppear` on presenting view controller when they are dismissed.
        //      Also, `self.presentingViewController` property is nil in both `viewWillDisappear` and `viewDidDisappear`.
        //      So, we store it here in modal's `viewDidAppear` to be used for view tracking later.
        CLY_LOG_I(@"%s A modal view controller with PageSheet presentation style is presented on iOS 13+. Storing presenting view controller to be used later.", __FUNCTION__);

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
        CLY_LOG_I(@"%s A modal view controller with PageSheet presentation style is dismissed on iOS 13+. Forcing auto view tracking with stored presenting view controller.", __FUNCTION__);
        [CountlyViewTrackingInternal.sharedInstance performAutoViewTrackingForViewController:self.presentingVC];
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

