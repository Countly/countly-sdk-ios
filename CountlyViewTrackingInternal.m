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
        self.isManualViewRestartActive = YES;
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
    CLY_LOG_I(@"%s global view segmentation will be set, key count: [%lu], keys: [%@]", __FUNCTION__, (unsigned long)segmentation.count, segmentation.allKeys);
    CLY_LOG_D(@"%s global view segmentation value detail, segmentation: [%@]", __FUNCTION__, segmentation);
    NSMutableDictionary *mutableSegmentation = segmentation.mutableCopy;
    [mutableSegmentation removeObjectsForKeys:self.reservedViewTrackingSegmentationKeys];
    if (mutableSegmentation.count != segmentation.count)
    {
        CLY_LOG_W(@"%s reserved keys will be dropped while setting global view segmentation, droppedKeyCount: [%lu], keptKeyCount: [%lu]", __FUNCTION__, (unsigned long)(segmentation.count - mutableSegmentation.count), (unsigned long)mutableSegmentation.count);
    }
    NSDictionary *filteredSegmentation = mutableSegmentation.cly_filterSupportedDataTypes;
    self.viewSegmentation = filteredSegmentation.mutableCopy;
    
}

- (void)updateGlobalViewSegmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s global view segmentation will be updated, key count: [%lu], keys: [%@]", __FUNCTION__, (unsigned long)segmentation.count, segmentation.allKeys);
    CLY_LOG_D(@"%s global view segmentation update value detail, segmentation: [%@]", __FUNCTION__, segmentation);
    if (!self.viewSegmentation) {
        self.viewSegmentation = NSMutableDictionary.new;
    }

    NSMutableDictionary *mutableSegmentation = segmentation.mutableCopy;
    [mutableSegmentation removeObjectsForKeys:self.reservedViewTrackingSegmentationKeys];
    if (mutableSegmentation.count != segmentation.count)
    {
        CLY_LOG_W(@"%s reserved keys will be dropped while updating global view segmentation, droppedKeyCount: [%lu], keptKeyCount: [%lu]", __FUNCTION__, (unsigned long)(segmentation.count - mutableSegmentation.count), (unsigned long)mutableSegmentation.count);
    }
    NSDictionary *filteredSegmentation = mutableSegmentation.cly_filterSupportedDataTypes;
    [self.viewSegmentation addEntriesFromDictionary:filteredSegmentation];
}

- (NSString *)startView:(NSString *)viewName segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s start view requested, name: [%@], segmentation key count: [%lu], segmentation keys: [%@]", __FUNCTION__, viewName, (unsigned long)segmentation.count, segmentation.allKeys);
    CLY_LOG_D(@"%s start view segmentation value detail, name: [%@], segmentation: [%@]", __FUNCTION__, viewName, segmentation);
#if (TARGET_OS_IOS || TARGET_OS_TV)
    if (self.isAutoViewTrackingActive) {
        CLY_LOG_W(@"%s manual start view is not allowed while automatic view tracking is active, name: [%@] will not be started", __FUNCTION__, viewName);
        return nil;
    }
#endif
    NSString* viewID = [self startViewInternal:viewName customSegmentation:segmentation];
    return viewID;
}

- (NSString *)startAutoStoppedView:(NSString *)viewName segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s start auto stopped view requested, name: [%@], segmentation key count: [%lu], segmentation keys: [%@]", __FUNCTION__, viewName, (unsigned long)segmentation.count, segmentation.allKeys);
    CLY_LOG_D(@"%s start auto stopped view segmentation value detail, name: [%@], segmentation: [%@]", __FUNCTION__, viewName, segmentation);
#if (TARGET_OS_IOS || TARGET_OS_TV)
    if (self.isAutoViewTrackingActive) {
        CLY_LOG_W(@"%s manual start auto stopped view is not allowed while automatic view tracking is active, name: [%@] will not be started", __FUNCTION__, viewName);
        return nil;
    }
#endif
    NSString* viewID = [self startViewInternal:viewName customSegmentation:segmentation isAutoStoppedView:YES];
    return viewID;
}

- (void)stopViewWithName:(NSString *)viewName segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s stop view by name requested, name: [%@], segmentation key count: [%lu], segmentation keys: [%@]", __FUNCTION__, viewName, (unsigned long)segmentation.count, segmentation.allKeys);
    CLY_LOG_D(@"%s stop view by name segmentation value detail, name: [%@], segmentation: [%@]", __FUNCTION__, viewName, segmentation);
#if (TARGET_OS_IOS || TARGET_OS_TV)
    if (self.isAutoViewTrackingActive) {
        CLY_LOG_W(@"%s manual stop view by name is not allowed while automatic view tracking is active, name: [%@] will not be stopped", __FUNCTION__, viewName);
        return;
    }
#endif
    [self stopViewWithNameInternal:viewName customSegmentation:segmentation];
    
}

- (void)stopViewWithID:(NSString *)viewID segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s stop view by ID requested, view ID: [%@], segmentation key count: [%lu], segmentation keys: [%@]", __FUNCTION__, viewID, (unsigned long)segmentation.count, segmentation.allKeys);
    CLY_LOG_D(@"%s stop view by ID segmentation value detail, view ID: [%@], segmentation: [%@]", __FUNCTION__, viewID, segmentation);
#if (TARGET_OS_IOS || TARGET_OS_TV)
    if (self.isAutoViewTrackingActive) {
        CLY_LOG_W(@"%s manual stop view by ID is not allowed while automatic view tracking is active, view ID: [%@] will not be stopped", __FUNCTION__, viewID);
        return;
    }
#endif
    [self stopViewWithIDInternal:viewID customSegmentation:segmentation];
}

- (void)pauseViewWithID:(NSString *)viewID
{
    CLY_LOG_I(@"%s pause view requested, view ID: [%@]", __FUNCTION__, viewID);
#if (TARGET_OS_IOS || TARGET_OS_TV)
    if (self.isAutoViewTrackingActive) {
        CLY_LOG_W(@"%s manual pause view is not allowed while automatic view tracking is active, view ID: [%@] will not be paused", __FUNCTION__, viewID);
        return;
    }
#endif
    [self pauseViewWithIDInternal:viewID];
    
}
- (void)resumeViewWithID:(NSString *)viewID
{
    CLY_LOG_I(@"%s resume view requested, view ID: [%@]", __FUNCTION__, viewID);
#if (TARGET_OS_IOS || TARGET_OS_TV)
    if (self.isAutoViewTrackingActive) {
        CLY_LOG_W(@"%s manual resume view is not allowed while automatic view tracking is active, view ID: [%@] will not be resumed", __FUNCTION__, viewID);
        return;
    }
#endif
    [self resumeViewWithIDInternal:viewID];
}

- (void)stopAllViews:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s stop all views requested, segmentation key count: [%lu], segmentation keys: [%@]", __FUNCTION__, (unsigned long)segmentation.count, segmentation.allKeys);
    CLY_LOG_D(@"%s stop all views segmentation value detail, segmentation: [%@]", __FUNCTION__, segmentation);
#if (TARGET_OS_IOS || TARGET_OS_TV)
    if (self.isAutoViewTrackingActive) {
        CLY_LOG_W(@"%s manual stop all views is not allowed while automatic view tracking is active, no view will be stopped", __FUNCTION__);
        return;
    }
#endif
    [self stopAllViewsInternal:segmentation];
    
}

#if (TARGET_OS_IOS || TARGET_OS_TV)
- (void)addAutoViewTrackingExclutionList:(NSArray *)viewTrackingExclusionList
{
    CLY_LOG_I(@"%s auto view tracking exclusion list will be extended, incoming count: [%lu], current count: [%lu]", __FUNCTION__, (unsigned long)viewTrackingExclusionList.count, (unsigned long)self.automaticViewTrackingExclusionList.count);
    [self.automaticViewTrackingExclusionList addObjectsFromArray:viewTrackingExclusionList];
}

- (void)startAutoViewTracking
{
    // Gated on the resolved 'avt' value (seeded from the developer config, overridable by the server),
    // so the server can force-enable automatic view tracking even when the developer did not opt in
    if (!CountlyServerConfig.sharedInstance.automaticViewTrackingEnabled)
    {
        CLY_LOG_D(@"%s automatic view tracking is not enabled by behavior settings, it will not be started", __FUNCTION__);
        return;
    }

    if (!CountlyConsentManager.sharedInstance.consentForViewTracking)
    {
        CLY_LOG_V(@"%s no consent for views, automatic view tracking will not be started", __FUNCTION__);
        return;
    }

    self.isAutoViewTrackingActive = YES;

    [self swizzleViewTrackingMethods];

    UIViewController* topVC = CountlyCommon.sharedInstance.topViewController;
    NSString* viewTitle = [self titleForViewController:topVC];
    CLY_LOG_D(@"%s automatic view tracking enabled, top view will be started automatically, name: [%@]", __FUNCTION__, viewTitle);
    [self startViewInternal:viewTitle customSegmentation:nil];
}

- (void)stopAutoViewTracking
{
    CLY_LOG_D(@"%s automatic view tracking will be disabled, running view count: [%lu]", __FUNCTION__, (unsigned long)self.viewDataDictionary.count);
    self.isAutoViewTrackingActive = NO;
    
    //    self.currentView = nil;
    //    self.currentViewID = nil;
}

- (void)setIsAutoViewTrackingActive:(BOOL)isAutoViewTrackingActive
{
    // Only the enabling transition is gated. Enabling needs the resolved 'avt' value (seeded from the
    // developer config, overridable by the server) and view tracking consent, so a server or consent
    // driven disable can not be undone by the developer setter while automatic views would not be
    // recorded anyway. Disabling is always allowed, so a server force-enabled tracker can be turned off
    // and a consent revocation (which flips consent before calling 'stopAutoViewTracking') actually
    // clears the active state instead of leaving it stuck on.
    if (isAutoViewTrackingActive)
    {
        if (!CountlyServerConfig.sharedInstance.automaticViewTrackingEnabled)
        {
            CLY_LOG_D(@"%s automatic view tracking is not enabled by behavior settings, active state change to [%@] will be ignored", __FUNCTION__, isAutoViewTrackingActive ? @"YES" : @"NO");
            return;
        }

        if (!CountlyConsentManager.sharedInstance.consentForViewTracking)
        {
            CLY_LOG_V(@"%s no consent for views, automatic view tracking active state change will be ignored", __FUNCTION__);
            return;
        }
    }

    if (_isAutoViewTrackingActive != isAutoViewTrackingActive) {
        CLY_LOG_D(@"%s automatic view tracking active state changing from [%@] to [%@], all running views will be stopped", __FUNCTION__, _isAutoViewTrackingActive ? @"YES" : @"NO", isAutoViewTrackingActive ? @"YES" : @"NO");
        [self stopAllViewsInternal:nil];
    }

    _isAutoViewTrackingActive = isAutoViewTrackingActive;
}


#pragma mark - Public methods Deprecated

- (void)addExceptionForAutoViewTracking:(NSString *)exception
{
    CLY_LOG_W(@"%s deprecated API used, addAutoViewTrackingExclutionList should be used instead, exception: [%@]", __FUNCTION__, exception);

    if (!exception.length)
    {
        CLY_LOG_W(@"%s exception name is null or empty, it will not be added to the auto view tracking exclusion list", __FUNCTION__);
        return;
    }

    [self.automaticViewTrackingExclusionList addObject:exception];
}

- (void)removeExceptionForAutoViewTracking:(NSString *)exception
{
    CLY_LOG_W(@"%s deprecated API used, exception will be removed from the auto view tracking exclusion list, exception: [%@]", __FUNCTION__, exception);
    [self.automaticViewTrackingExclusionList removeObject:exception];
}

#endif

#pragma mark - Internal methods old
- (void)stopViewWithNameInternal:(NSString *) viewName customSegmentation:(NSDictionary *)customSegmentation
{
    if (!viewName || !viewName.length)
    {
        CLY_LOG_E(@"%s view name is null or empty, stop view by name will be ignored", __FUNCTION__);
        return;
    }

    if (!CountlyConsentManager.sharedInstance.consentForViewTracking)
    {
        CLY_LOG_V(@"%s no consent for views, stop view by name will be ignored, name: [%@]", __FUNCTION__, viewName);
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
        [self stopViewWithIDInternal:viewID customSegmentation:customSegmentation];
    }
    else {
        CLY_LOG_E(@"%s no view exists with the given name, it will not be stopped, name: [%@]", __FUNCTION__, viewName);
    }
}

- (void)stopViewWithIDInternal:(NSString *) viewKey customSegmentation:(NSDictionary *)customSegmentation
{
    [self stopViewWithIDInternal:viewKey customSegmentation:customSegmentation autoPaused:NO];
}

- (void)stopViewWithIDInternal:(NSString *) viewKey customSegmentation:(NSDictionary *)customSegmentation autoPaused:(BOOL) autoPaused{
    if (!viewKey || !viewKey.length)
    {
        CLY_LOG_E(@"%s view ID is null or empty, stop view by ID will be ignored", __FUNCTION__);
        return;
    }

    if (!CountlyConsentManager.sharedInstance.consentForViewTracking)
    {
        CLY_LOG_V(@"%s no consent for views, stop view by ID will be ignored, view ID: [%@]", __FUNCTION__, viewKey);
        return;
    }

    if (!CountlyServerConfig.sharedInstance.viewTrackingEnabled)
    {
        CLY_LOG_D(@"%s view tracking is disabled by server config, stop view by ID will be ignored, view ID: [%@]", __FUNCTION__, viewKey);
        return;
    }
    
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
            if (mutableCustomSegmentation.count != customSegmentation.count)
            {
                CLY_LOG_W(@"%s reserved keys will be dropped from the segmentation of the view being stopped, droppedKeyCount: [%lu], view ID: [%@]", __FUNCTION__, (unsigned long)(customSegmentation.count - mutableCustomSegmentation.count), viewKey);
            }
            NSDictionary *filteredSegmentation = mutableCustomSegmentation.cly_filterSupportedDataTypes;
            [segmentation addEntriesFromDictionary:filteredSegmentation];
        }
        
        NSDictionary* segmentationTruncated = [segmentation cly_truncated:@"View segmentation"];
        segmentation = [segmentationTruncated cly_limited:@"View segmentation"].mutableCopy;
        
        segmentation[kCountlyVTKeyName] = viewData.viewName;
        segmentation[kCountlyVTKeySegment] = CountlyDeviceInfo.osName;
        
        NSInteger duration = viewData.duration;
        [Countly.sharedInstance recordReservedEvent:kCountlyReservedEventView segmentation:segmentation count:1 sum:0 duration:duration ID:viewData.viewID timestamp:CountlyCommon.sharedInstance.uniqueTimestamp];
        
        CLY_LOG_D(@"%s view stopped, name: [%@], view ID: [%@], duration: [%ld], segmentation key count: [%lu], autoPaused: [%@]", __FUNCTION__, viewData.viewName, viewData.viewID, (long)duration, (unsigned long)segmentation.count, autoPaused ? @"YES" : @"NO");
        CLY_LOG_D(@"%s stopped view segmentation value detail, view ID: [%@], segmentation: [%@]", __FUNCTION__, viewData.viewID, segmentation);
        if (!autoPaused) {
            [self.viewDataDictionary removeObjectForKey:viewKey];
        }
    }
    else {
        CLY_LOG_E(@"%s no view exists with the given ID, it will not be stopped, view ID: [%@]", __FUNCTION__, viewKey);
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
        CLY_LOG_E(@"%s view name is null or empty, start view will be ignored", __FUNCTION__);
        return nil;
    }

    if (!CountlyConsentManager.sharedInstance.consentForViewTracking)
    {
        CLY_LOG_V(@"%s no consent for views, start view will be ignored, name: [%@]", __FUNCTION__, viewName);
        return nil;
    }

    if (!CountlyServerConfig.sharedInstance.viewTrackingEnabled)
    {
        CLY_LOG_D(@"%s view tracking is disabled by server config, start view will be ignored, name: [%@]", __FUNCTION__, viewName);
        return nil;
    }

    [self stopAutoStoppedView];

    viewName = viewName.copy;

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
        if (mutableCustomSegmentation.count != customSegmentation.count)
        {
            CLY_LOG_W(@"%s reserved keys will be dropped from the segmentation of the view being started, droppedKeyCount: [%lu], name: [%@]", __FUNCTION__, (unsigned long)(customSegmentation.count - mutableCustomSegmentation.count), viewName);
        }
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
    
    CLY_LOG_D(@"%s view started, name: [%@], view ID: [%@], previous view ID: [%@], segmentation key count: [%lu], customSegmentationKeyCount: [%lu], isAutoStoppedView: [%@]", __FUNCTION__, viewName, self.currentViewID, self.previousViewID, (unsigned long)segmentation.count, (unsigned long)customSegmentation.count, isAutoStoppedView ? @"YES" : @"NO");
    CLY_LOG_D(@"%s started view segmentation value detail, view ID: [%@], segmentation: [%@], customSegmentation: [%@]", __FUNCTION__, self.currentViewID, segmentation, customSegmentation);
    
    return self.currentViewID;
}

- (void)pauseViewWithIDInternal:(NSString *) viewID
{
    if (!viewID || !viewID.length)
    {
        CLY_LOG_E(@"%s view ID is null or empty, pause view will be ignored", __FUNCTION__);
        return;
    }

    if (!CountlyConsentManager.sharedInstance.consentForViewTracking)
    {
        CLY_LOG_V(@"%s no consent for views, pause view will be ignored, view ID: [%@]", __FUNCTION__, viewID);
        return;
    }

    if (!CountlyServerConfig.sharedInstance.viewTrackingEnabled)
    {
        CLY_LOG_D(@"%s view tracking is disabled by server config, pause view will be ignored, view ID: [%@]", __FUNCTION__, viewID);
        return;
    }

    CountlyViewData* viewData = self.viewDataDictionary[viewID];
    if (viewData)
    {
        CLY_LOG_D(@"%s view resolved for pausing, view ID: [%@], name: [%@]", __FUNCTION__, viewID, viewData.viewName);
        [self pauseViewInternal:viewData];
    }
    else {
        CLY_LOG_E(@"%s no view exists with the given ID, it will not be paused, view ID: [%@]", __FUNCTION__, viewID);
    }
}

- (void)resumeViewWithIDInternal:(NSString *) viewID
{
    if (!viewID || !viewID.length)
    {
        CLY_LOG_E(@"%s view ID is null or empty, resume view will be ignored", __FUNCTION__);
        return;
    }

    if (!CountlyConsentManager.sharedInstance.consentForViewTracking)
    {
        CLY_LOG_V(@"%s no consent for views, resume view will be ignored, view ID: [%@]", __FUNCTION__, viewID);
        return;
    }

    if (!CountlyServerConfig.sharedInstance.viewTrackingEnabled)
    {
        CLY_LOG_D(@"%s view tracking is disabled by server config, resume view will be ignored, view ID: [%@]", __FUNCTION__, viewID);
        return;
    }

    CountlyViewData* viewData = self.viewDataDictionary[viewID];
    if (viewData)
    {
        CLY_LOG_D(@"%s view resumed, view ID: [%@], name: [%@]", __FUNCTION__, viewID, viewData.viewName);
        [viewData resumeView];
    }

    else {
        CLY_LOG_E(@"%s no view exists with the given ID, it will not be resumed, view ID: [%@]", __FUNCTION__, viewID);
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
    CLY_LOG_D(@"%s running views will be stopped automatically and marked for restart, view count: [%lu]", __FUNCTION__, (unsigned long)self.viewDataDictionary.count);
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
    
    CLY_LOG_D(@"%s previously stopped views will be started automatically, view count: [%lu]", __FUNCTION__, (unsigned long)keysToStart.count);

    // Start the collected views after enumeration
    for (NSString *key in keysToStart)
    {
        CountlyViewData *viewData = self.viewDataDictionary[key];
        NSString *viewID = [self startViewInternal:viewData.viewName customSegmentation:viewData.startSegmentation isAutoStoppedView:viewData.isAutoStoppedView];

        CLY_LOG_V(@"%s view started automatically after restart, name: [%@], new view ID: [%@], previous view ID: [%@]", __FUNCTION__, viewData.viewName, viewID, key);

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
    {
        CLY_LOG_V(@"%s no consent for views, stop all views will be ignored", __FUNCTION__);
        return;
    }
    CLY_LOG_D(@"%s all views will be stopped, view count: [%lu], segmentation key count: [%lu]", __FUNCTION__, (unsigned long)self.viewDataDictionary.count, (unsigned long)segmentation.count);
    CLY_LOG_D(@"%s stop all views internal segmentation value detail, segmentation: [%@]", __FUNCTION__, segmentation);
    [self.viewDataDictionary enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, CountlyViewData * _Nonnull viewData, BOOL * _Nonnull stop) {
        [self stopViewWithIDInternal:key customSegmentation:segmentation];
    }];
}

- (void)addSegmentationToViewWithNameInternal:(NSString *) viewName segmentation:(NSDictionary *)segmentation
{
    if (!viewName || !viewName.length)
    {
        CLY_LOG_E(@"%s view name is null or empty, adding segmentation to view will be ignored", __FUNCTION__);
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
        CLY_LOG_E(@"%s no view exists with the given name, segmentation will not be added, name: [%@]", __FUNCTION__, viewName);
    }
}

- (void)addSegmentationToViewWithIDInternal:(NSString *) viewID segmentation:(NSDictionary *)segmentation{
    if (!viewID || !viewID.length)
    {
        CLY_LOG_E(@"%s view ID is null or empty, adding segmentation by view ID will be ignored", __FUNCTION__);
        return;
    }

    if (!CountlyConsentManager.sharedInstance.consentForViewTracking)
    {
        CLY_LOG_V(@"%s no consent for views, adding segmentation to view will be ignored, view ID: [%@]", __FUNCTION__, viewID);
        return;
    }
    CountlyViewData* viewData = self.viewDataDictionary[viewID];
    if (viewData)
    {
        NSMutableDictionary *mutableSegmentation = segmentation.mutableCopy;
        [mutableSegmentation removeObjectsForKeys:self.reservedViewTrackingSegmentationKeys];
        if (mutableSegmentation.count != segmentation.count)
        {
            CLY_LOG_W(@"%s reserved keys will be dropped while adding segmentation to a view, droppedKeyCount: [%lu], view ID: [%@]", __FUNCTION__, (unsigned long)(segmentation.count - mutableSegmentation.count), viewID);
        }
        NSDictionary *filteredSegmentation = mutableSegmentation.cly_filterSupportedDataTypes;
        CLY_LOG_D(@"%s segmentation will be added to view, view ID: [%@], name: [%@], key count: [%lu]", __FUNCTION__, viewID, viewData.viewName, (unsigned long)filteredSegmentation.count);
        CLY_LOG_D(@"%s segmentation added to view value detail, view ID: [%@], segmentation: [%@]", __FUNCTION__, viewID, filteredSegmentation);
        if(filteredSegmentation) {
            if(!viewData.segmentation) {
                viewData.segmentation = NSMutableDictionary.new;
            }
            [viewData.segmentation addEntriesFromDictionary:filteredSegmentation];
        }
        [self.viewDataDictionary setObject:viewData forKey:viewID];
    }
    else {
        CLY_LOG_E(@"%s no view exists with the given ID, segmentation will not be added, view ID: [%@]", __FUNCTION__, viewID);
    }
}


- (void)addSegmentationToViewWithID:(NSString *)viewID segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s add segmentation to view by ID requested, view ID: [%@], segmentation key count: [%lu], segmentation keys: [%@]", __FUNCTION__, viewID, (unsigned long)segmentation.count, segmentation.allKeys);
    CLY_LOG_D(@"%s add segmentation to view by ID value detail, view ID: [%@], segmentation: [%@]", __FUNCTION__, viewID, segmentation);
    [self addSegmentationToViewWithIDInternal:viewID segmentation:segmentation];
}

- (void)addSegmentationToViewWithName:(NSString *)viewName segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s add segmentation to view by name requested, name: [%@], segmentation key count: [%lu], segmentation keys: [%@]", __FUNCTION__, viewName, (unsigned long)segmentation.count, segmentation.allKeys);
    CLY_LOG_D(@"%s add segmentation to view by name value detail, name: [%@], segmentation: [%@]", __FUNCTION__, viewName, segmentation);
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

    CLY_LOG_D(@"%s UIViewController appearance methods swizzled for automatic view tracking", __FUNCTION__);
}

- (void)performAutoViewTrackingForViewController:(UIViewController *)viewController
{
    if (!self.isAutoViewTrackingActive)
    {
        CLY_LOG_V(@"%s automatic view tracking is not active, appeared view controller will be ignored", __FUNCTION__);
        return;
    }

    // Checked per view appearance so a runtime 'avt' = false from the server takes effect immediately
    if (!CountlyServerConfig.sharedInstance.automaticViewTrackingEnabled)
    {
        CLY_LOG_D(@"%s automatic view tracking is disabled by behavior settings, appeared view controller will be ignored", __FUNCTION__);
        return;
    }

    if (!CountlyConsentManager.sharedInstance.consentForViewTracking)
    {
        CLY_LOG_V(@"%s no consent for views, automatic view start will be ignored", __FUNCTION__);
        return;
    }

    NSString* viewTitle = [self titleForViewController:viewController];

    if (self.currentView && [self.currentView.viewName isEqualToString:viewTitle])
    {
        CLY_LOG_V(@"%s appeared view controller is already the current view, it will not be started again, name: [%@]", __FUNCTION__, viewTitle);
        return;
    }
    
    BOOL isException = NO;
    
    for (NSString* exception in self.automaticViewTrackingExclusionList)
    {
        isException = [viewTitle isEqualToString:exception] ||
        [viewController isKindOfClass:NSClassFromString(exception)] ||
        [NSStringFromClass(viewController.class) isEqualToString:exception];
        
        if (isException)
        {
            CLY_LOG_V(@"%s view is in the automatic view tracking exclusion list, it will be ignored, name: [%@], exception: [%@]", __FUNCTION__, viewTitle, exception);
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
        CLY_LOG_V(@"%s view controller conforms to the CountlyAutoViewTrackingName protocol, its custom auto view tracking name will be used", __FUNCTION__);
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
#if (TARGET_OS_IOS || TARGET_OS_TV)
    if (!self.isAutoViewTrackingActive && self.isManualViewRestartActive) {
        CLY_LOG_D(@"%s app entered foreground with manual view restart active, stopped views will be started automatically", __FUNCTION__);
        [self startStoppedViewsInternal];
    }
#else
    if (self.isManualViewRestartActive) {
        CLY_LOG_D(@"%s app entered foreground on a non UIKit platform, stopped views will be started automatically", __FUNCTION__);
        [self startStoppedViewsInternal];
    }
#endif
}
- (void)applicationDidEnterBackground {
#if (TARGET_OS_IOS || TARGET_OS_TV)
    if (self.isAutoViewTrackingActive) {
        CLY_LOG_D(@"%s app entered background while automatic view tracking is active, current view will be stopped automatically", __FUNCTION__);
        [self stopCurrentView];
    }
    else if (self.isManualViewRestartActive) {
        CLY_LOG_D(@"%s app entered background with manual view restart active, running views will be stopped automatically", __FUNCTION__);
        [self stopRunningViewsInternal];
    }
#else
    if (self.isManualViewRestartActive) {
        CLY_LOG_D(@"%s app entered background on a non UIKit platform, running views will be stopped automatically", __FUNCTION__);
        [self stopRunningViewsInternal];
    }
#endif
}

- (void)applicationWillTerminate {
    [self stopAllViewsInternal:nil];
}


- (void)resetFirstView
{
    CLY_LOG_D(@"%s first view flag reset, the next started view will be marked as the session start view", __FUNCTION__);
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
        CLY_LOG_D(@"%s a modal view controller with PageSheet presentation style is presented, presenting view controller will be stored for later automatic view tracking", __FUNCTION__);

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
        CLY_LOG_D(@"%s a modal view controller with PageSheet presentation style is dismissed, automatic view tracking will be forced with the stored presenting view controller", __FUNCTION__);
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

