// CountlyContent.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.
#import "CountlyContentBuilderInternal.h"
#import "CountlyWebViewManager.h"

//TODO: improve logging, check edge cases
NSString* const kCountlyEndpointContent = @"/o/sdk/content";
NSString* const kCountlyCBFetchContent  = @"queue";

@implementation CountlyContentBuilderInternal {
    BOOL _isRequestQueueLocked;
    BOOL _isCurrentlyContentShown;
    BOOL _refreshRunnablePending;
    // Bumped per presentation claim, so a deferred teardown can tell if a newer one took the slot.
    NSUInteger _presentationSequence;
    NSTimer *_requestTimer;
    NSTimer *_minuteTimer;
    dispatch_queue_t _contentQueue;
#if (TARGET_OS_IOS || TARGET_OS_VISION)
    // The presented content's manager, retained so the zone can close it. Main thread only.
    // Guarded: CountlyWebViewManager only exists on iOS/visionOS, and this file builds everywhere.
    CountlyWebViewManager *_webViewManager;
#endif
}

#if (TARGET_OS_IOS || TARGET_OS_VISION)
+ (instancetype)sharedInstance {
    static CountlyContentBuilderInternal *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init
{
    if (self = [super init])
    {
        self.zoneTimerInterval = 30.0;
        _requestTimer = nil;
        _isCurrentlyContentShown = NO;
        _contentQueue = dispatch_queue_create("ly.countly.content.queue", DISPATCH_QUEUE_SERIAL);
        _contentInitialDelay = 4;
    }
    
    return self;
}

#pragma mark - Thread-safe flag helpers

// Every BOOL flag below (_isRequestQueueLocked, _isCurrentlyContentShown,
// _refreshRunnablePending) is accessed only through these helpers so all reads/writes are
// serialized on the single serial _contentQueue. The blocks capture the raw ivar pointer,
// which is safe because this class is a never-released singleton (its ivars outlive any
// queued block).
- (BOOL)readFlag:(BOOL *)flag {
    if (!_contentQueue) {
        return *flag;
    }
    __block BOOL value = NO;
    dispatch_sync(_contentQueue, ^{
        value = *flag;
    });
    return value;
}

- (void)writeFlag:(BOOL *)flag value:(BOOL)value {
    if (!_contentQueue) {
        *flag = value;
        return;
    }
    dispatch_async(_contentQueue, ^{
        *flag = value;
    });
}

// Atomically set *flag to YES if it was NO. Returns YES only for the caller that made the
// NO->YES transition, so exactly one caller "wins" a contended flag.
- (BOOL)testAndSetFlag:(BOOL *)flag {
    __block BOOL acquired = NO;
    if (!_contentQueue) {
        if (!*flag) { *flag = YES; acquired = YES; }
        return acquired;
    }
    dispatch_sync(_contentQueue, ^{
        if (!*flag) { *flag = YES; acquired = YES; }
    });
    return acquired;
}

- (BOOL)isRequestQueueLockedThreadSafe {
    return [self readFlag:&_isRequestQueueLocked];
}

- (void)setRequestQueueLockedThreadSafe:(BOOL)locked {
    [self writeFlag:&_isRequestQueueLocked value:locked];
}

// Atomically claim the single "content is shown" slot. Returns YES if the caller acquired it,
// NO if content is already shown or a racing fetch already claimed it, in which case the caller
// MUST NOT present another web view. Previously the flag was set only when the web view was
// presented (after a network round trip), so two near-simultaneous fetches could both pass the
// guard and present two overlapping web views; this test-and-set closes that window.
- (BOOL)tryBeginContentPresentation {
    __block BOOL acquired = NO;

    if (!_contentQueue) {
        if (!_isCurrentlyContentShown) { _isCurrentlyContentShown = YES; _presentationSequence++; acquired = YES; }
        return acquired;
    }

    dispatch_sync(_contentQueue, ^{
        if (!self->_isCurrentlyContentShown) {
            self->_isCurrentlyContentShown = YES;
            self->_presentationSequence++;
            acquired = YES;
        }
    });

    return acquired;
}

- (NSUInteger)currentPresentationSequence {
    if (!_contentQueue) {
        return _presentationSequence;
    }
    __block NSUInteger value = 0;
    dispatch_sync(_contentQueue, ^{
        value = self->_presentationSequence;
    });
    return value;
}

// Release the content slot (called when the shown web view is dismissed, or on reset) so the
// next zone cycle can present again.
- (void)endContentPresentation {
    [self writeFlag:&_isCurrentlyContentShown value:NO];
}

- (BOOL)isContentShownThreadSafe {
    return [self readFlag:&_isCurrentlyContentShown];
}

// Whether a zone re-entry is scheduled. Read by tests.
- (BOOL)isZoneReentryTimerArmed {
    return _minuteTimer != nil;
}

- (void)enterContentZone {

    if([self isContentShownThreadSafe]){
        CLY_LOG_I(@"%s a content is already shown, skipping" ,__FUNCTION__);
        return;
    }

    [self enterContentZone:@[]];
}

- (void)enterContentZone:(NSArray<NSString *> *)tags {
    if([self isContentShownThreadSafe]){
        CLY_LOG_I(@"%s a content is already shown, skipping" ,__FUNCTION__);
        return;
    }

    [_minuteTimer invalidate];
    _minuteTimer = nil;
    
    if (!CountlyConsentManager.sharedInstance.consentForContent)
        return;
    
    if(_requestTimer != nil) {
        CLY_LOG_I(@"%s already entered for content zone, please exit from content zone first to start again", __FUNCTION__);
        return;
    }
    
    self.currentTags = tags;
    int contentDelay = 0;
    
    if (CountlyCommon.sharedInstance.timeSinceLaunch < _contentInitialDelay) {
        contentDelay = _contentInitialDelay;
    }
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(contentDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^
    {
        [self fetchContents];;
        self->_requestTimer = [NSTimer scheduledTimerWithTimeInterval:self->_zoneTimerInterval
                                                         target:self
                                                       selector:@selector(fetchContents)
                                                       userInfo:nil
                                                        repeats:YES];
    });
}

- (void)exitContentZone {
    [self clearContentState];
    // Also takes the content off screen. Internal cycles use clearContentState instead.
    [self closeShownContent];
}

// Dismisses the content on screen and frees the presentation slot, in one main-queue turn.
// The slot is deliberately not released earlier: that would let a fetch present a second web view
// mid-teardown.
- (void)closeShownContent {
    // Synchronous when already on the main thread, which is where exitContentZone is called from in
    // practice. Deferring the slot release would leave it claimed for the rest of the turn, so an
    // exitContentZone immediately followed by enterContentZone would silently no-op and dead-end
    // the zone.
    if ([NSThread isMainThread]) {
        [self tearDownShownContent];
        return;
    }

    NSUInteger requestedForSequence = [self currentPresentationSequence];

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self currentPresentationSequence] != requestedForSequence) {
            // A newer presentation owns the slot now; it is not ours to tear down.
            CLY_LOG_D(@"%s a newer presentation superseded this close request, skipping", __FUNCTION__);
            return;
        }

        [self tearDownShownContent];
    });
}

// Main thread only.
- (void)tearDownShownContent {
    CountlyWebViewManager *manager = self->_webViewManager;
    if (manager) {
        CLY_LOG_I(@"%s closing the currently shown content", __FUNCTION__);
        // Cleared first so the dismiss block skips re-arming the zone for an SDK-initiated close.
        self->_webViewManager = nil;
        [manager closeWebView];
    }

    // Released even with nothing retained, so a stranded claim cannot dead-end later enters.
    [self endContentPresentation];
}

- (void)changeContent:(NSArray<NSString *> *)tags {
    if (![tags isEqualToArray:self.currentTags]) {
        [self exitContentZone];
        [self enterContentZone:tags];
    }
}

- (void)previewContent:(NSString *)contentId {
    [self fetchContents:nil contentId:contentId];
}

- (void)refreshContentZone {
    if (![CountlyServerConfig.sharedInstance refreshContentZoneEnabled])
    {
        return;
    }
    if([self isContentShownThreadSafe]){
        CLY_LOG_I(@"%s a content is already shown, skipping" ,__FUNCTION__);
        return;
    }

    // Coalesce refreshes: only one refresh runnable may be pending at a time. Without this,
    // multiple refreshContentZone calls before the request queue flushes each append a runnable
    // (addQueueFlushRunnable does not dedup); they then all fire together and trigger N
    // concurrent content fetches (a burst against the edge) whose extra results are discarded.
    if (![self testAndSetFlag:&_refreshRunnablePending]) {
        CLY_LOG_I(@"%s a content refresh is already pending, skipping duplicate" ,__FUNCTION__);
        return;
    }

    __weak typeof(self) weakSelf = self;
    [CountlyConnectionManager.sharedInstance addQueueFlushRunnable:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        // Clear the pending flag first so a refresh requested during/after this flush can
        // schedule the next one.
        [strongSelf writeFlag:&strongSelf->_refreshRunnablePending value:NO];
        CLY_LOG_I(@"%s queue flueshed, will re-fetch contents" ,__FUNCTION__);
        // State only: a refresh must never pull content off screen
        [strongSelf clearContentState];
        [strongSelf enterContentZone];
    }];
    [CountlyConnectionManager.sharedInstance attemptToSendStoredRequests];
}

- (void)refreshContentZoneJTE {
    if (![CountlyServerConfig.sharedInstance refreshContentZoneEnabled])
    {
        CLY_LOG_D(@"%s, refresh content zone is disabled, skipping JTE content refresh", __FUNCTION__);
        return;
    }
    if([self isContentShownThreadSafe]){
        CLY_LOG_I(@"%s a content is already shown, skipping JTE content refresh" ,__FUNCTION__);
        return;
    }

    CLY_LOG_D(@"%s, Starting JTE content refresh with retries", __FUNCTION__);
    // State only: a journey trigger must never pull content off screen
    [self clearContentState];
    [self fetchContentsForJourneyWithMaxAttempts:3 currentAttempt:1];
}

- (void)fetchContentsForJourneyWithMaxAttempts:(NSInteger)maxAttempts currentAttempt:(NSInteger)currentAttempt {
    CLY_LOG_D(@"%s, JTE content fetch attempt %ld of %ld", __FUNCTION__, (long)currentAttempt, (long)maxAttempts);

    [self fetchContents:^{
        if (currentAttempt < maxAttempts) {
            CLY_LOG_D(@"Retrying JTE content fetch in 1 second (attempt %ld of %ld)", (long)(currentAttempt + 1), (long)maxAttempts);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self fetchContentsForJourneyWithMaxAttempts:maxAttempts currentAttempt:currentAttempt + 1];
            });
        } else {
            CLY_LOG_D(@"JTE content fetch exhausted all %ld attempts. Re-entering content zone.", (long)maxAttempts);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self enterContentZone];
            });
        }
    } contentId:nil];
}

#pragma mark - Private Methods

- (void)clearContentState {
    [_requestTimer invalidate];
    _requestTimer = nil;

    [_minuteTimer invalidate];
    _minuteTimer = nil;
    self.currentTags = nil;
    [self setRequestQueueLockedThreadSafe:NO];
}

- (void)resetInstance {
    CLY_LOG_I(@"%s", __FUNCTION__);
    [self clearContentState];
    // Also releases the shown slot. A second release here used to race its own deferred teardown:
    // freeing the slot early let a fetch claim it, which made the queued close skip and strand the
    // overlay with nothing left holding a reference to it.
    [self closeShownContent];
    [self writeFlag:&_refreshRunnablePending value:NO];
}

- (void)fetchContents {
    [self fetchContents:nil contentId:nil];
}

- (void)fetchContents:(void (^)(void))failureCallback contentId:(NSString *)contentId {
    if (!CountlyConsentManager.sharedInstance.consentForContent)
        return;

    if (!CountlyServerConfig.sharedInstance.networkingEnabled)
        return;

    if (CountlyDeviceInfo.sharedInstance.isDeviceIDTemporary)
    {
        CLY_LOG_W(@"%s content can not be fetched while in temporary device ID mode", __FUNCTION__);
        return;
    }

    if([self isContentShownThreadSafe]){
        CLY_LOG_I(@"%s a content is already shown, skipping" ,__FUNCTION__);
        return;
    }

    if ([self isRequestQueueLockedThreadSafe]) {
        return;
    }
    
    [self setRequestQueueLockedThreadSafe:YES];
    
    NSURLSessionTask *dataTask = [[CountlyCommon.sharedInstance ImmediateURLSession] dataTaskWithRequest:[self fetchContentsRequest:contentId] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        // IMMEDIATE REQUEST to find them better in search
        if (error) {
            CLY_LOG_I(@"%s fetch content details failed: [%@]", __FUNCTION__, error);
            [self setRequestQueueLockedThreadSafe:NO];
            if (failureCallback) {
                failureCallback();
            }
            return;
        }
        
        NSError *jsonError;
        NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];

        if (jsonError || !jsonResponse) {
            CLY_LOG_I(@"%s failed to parse JSON or empty response: [%@]", __FUNCTION__, jsonError);
            [self setRequestQueueLockedThreadSafe:NO];
            if (failureCallback) {
                failureCallback();
            }
            return;
        }
        
        NSString *pathToHtml = jsonResponse[@"html"];
        NSDictionary *placementCoordinates = jsonResponse[@"geo"];
        if(pathToHtml) {
            [self showContentWithHtmlPath:pathToHtml placementCoordinates:placementCoordinates];
        } else if (failureCallback) {
            failureCallback();
        }
        [self setRequestQueueLockedThreadSafe:NO];
    }];
    
    [dataTask resume];
}

- (NSURLRequest *)fetchContentsRequest:(NSString *)contentId
{
    NSString *queryString = [CountlyConnectionManager.sharedInstance queryEssentials];
    NSString *resolutionJson = [self resolutionJson];
    queryString = [queryString stringByAppendingFormat:@"&%@=%@", @"method", kCountlyCBFetchContent];
    queryString = [queryString stringByAppendingFormat:@"&%@=%@", @"resolution", resolutionJson.cly_URLEscaped];

    NSArray *components = [CountlyDeviceInfo.locale componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"_-"]];
    queryString = [queryString stringByAppendingFormat:@"&%@=%@", @"la", components.firstObject];

    NSString *deviceType = CountlyDeviceInfo.deviceType;
    if (deviceType)
    {
        queryString = [queryString stringByAppendingFormat:@"&%@=%@", @"dt", deviceType];
    }

    if (contentId) {
        queryString = [queryString stringByAppendingFormat:@"&%@=%@", @"content_id", contentId.cly_URLEscaped];
        queryString = [queryString stringByAppendingFormat:@"&%@=%@", @"preview", @"true"];
    }
    
    queryString = [CountlyConnectionManager.sharedInstance appendChecksum:queryString];

    NSString *contentEndpoint = [NSString stringWithFormat:@"%@%@", CountlyConnectionManager.sharedInstance.host, kCountlyEndpointContent];

    if (queryString.length > kCountlyGETRequestMaxLength || CountlyConnectionManager.sharedInstance.alwaysUsePOST)
    {
        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:contentEndpoint]];
        request.HTTPMethod = @"POST";
        request.HTTPBody = [queryString cly_dataUTF8];
        return request.copy;
    }
    else
    {
        NSString* withQueryString = [contentEndpoint stringByAppendingFormat:@"?%@", queryString];
        NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:withQueryString]];
        return request;
    }
}

- (NSString *)resolutionJson {
    //TODO: check why area is not clickable and safearea things
    CGSize size = [CountlyCommon.sharedInstance getWindowSize];
    
    UIInterfaceOrientation orientation = [CountlyCommon.sharedInstance interfaceOrientation];
    BOOL isLandscape = UIInterfaceOrientationIsLandscape(orientation);

    CGFloat lHpW = isLandscape ? size.height : size.width;
    CGFloat lWpH =  isLandscape ? size.width : size.height;
    
    NSDictionary *resolutionDict = @{
        @"portrait": @{@"height": @(lWpH), @"width": @(lHpW)},
        @"landscape": @{@"height": @(lHpW), @"width": @(lWpH)}
    };
    
    CLY_LOG_D(@"%s, resolutionDict: [%@]", __FUNCTION__, resolutionDict);
    
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:resolutionDict options:0 error:nil];
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (void)showContentWithHtmlPath:(NSString *)urlString placementCoordinates:(NSDictionary *)placementCoordinates {
    // Convert pathToHtml to NSURL
    NSURL *url = [NSURL URLWithString:urlString];
    
    if (!url || !url.scheme || !url.host) {
        CLY_LOG_E(@"%s the URL is not valid: [%@]", __FUNCTION__, urlString);
        return;
    }

    // Claim the single content slot before dispatching to main. If content is already shown,
    // or a racing content fetch already claimed it, skip: never present a second overlapping
    // web view for the same zone.
    if (![self tryBeginContentPresentation]) {
        CLY_LOG_I(@"%s a content is already shown, skipping duplicate presentation", __FUNCTION__);
        return;
    }

    NSUInteger claimedSequence = [self currentPresentationSequence];

    dispatch_async(dispatch_get_main_queue(), ^ {
        // The zone can be exited while this is in flight, which releases our claim. Do not present
        // content the app has already exited, and do not ride a claim a newer fetch has taken.
        if (![self isContentShownThreadSafe] || [self currentPresentationSequence] != claimedSequence) {
            CLY_LOG_I(@"%s the presentation claim was released before presenting, skipping", __FUNCTION__);
            return;
        }

        // Detect screen orientation
        UIInterfaceOrientation orientation = [CountlyCommon.sharedInstance interfaceOrientation];
        // disableRotation pins content to the portrait layout, whatever the device is doing.
        BOOL isLandscape = self.disableRotation ? NO : UIInterfaceOrientationIsLandscape(orientation);

        // Initial placement only; from here on the page's resize_me reply drives the size.
        NSDictionary *coordinates = isLandscape ? placementCoordinates[@"l"] : placementCoordinates[@"p"];

        CGFloat x = [coordinates[@"x"] floatValue];
        CGFloat y = [coordinates[@"y"] floatValue];
        CGFloat width = [coordinates[@"w"] floatValue];
        CGFloat height = [coordinates[@"h"] floatValue];

        CGRect frame = CGRectMake(x, y, width, height);

        // Append the current theme so the content renders matching the app (resolved on the main
        // thread here, where the trait collection is safe to read).
        NSURL *themedURL = [NSURL URLWithString:[CountlyDeviceInfo URLStringByAppendingThemeMode:urlString]] ?: url;

        // Log the URL and the frame
        CLY_LOG_I(@"%s showing content from URL: [%@], frame: [%@]", __FUNCTION__, themedURL, NSStringFromCGRect(frame));
        CountlyWebViewManager* webViewManager =  CountlyWebViewManager.new;
        // Retained so exitContentZone / resetInstance can dismiss what we present
        self->_webViewManager = webViewManager;
        // Weak: the manager owns this block, so a strong capture would be a retain cycle.
        __weak CountlyWebViewManager *weakManager = webViewManager;
            [webViewManager createWebViewWithURL:themedURL frame:frame appearBlock:^
             {
                CLY_LOG_I(@"%s webview should be appeared", __FUNCTION__);
            } dismissBlock:^
             {
                CLY_LOG_I(@"%s webview dismissed", __FUNCTION__);

                // Only the current content's dismissal may touch shared zone state; this block can
                // belong to a superseded web view.
                if (self->_webViewManager == weakManager) {
                    self->_webViewManager = nil;
                    [self endContentPresentation];
                    self->_minuteTimer = [NSTimer scheduledTimerWithTimeInterval:self->_zoneTimerInterval
                                                                     target:self
                                                                   selector:@selector(enterContentZone)
                                                                   userInfo:nil
                                                                    repeats:NO];
                }

                // Reported regardless: this web view really did close.
                if(self.contentCallback) {
                    self.contentCallback(CLOSED, NSDictionary.new);
                }
            }];
            CLY_LOG_I(@"%s webview initiated pausing content calls ", __FUNCTION__);
            // The shown slot was already claimed synchronously by tryBeginContentPresentation
            // above, before this async block was dispatched.
            [self clearContentState];
    });
}
#endif
@end
