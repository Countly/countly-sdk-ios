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
    NSTimer *_requestTimer;
    NSTimer *_minuteTimer;
    dispatch_queue_t _contentQueue;
}

#if (TARGET_OS_IOS)
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

- (BOOL)isRequestQueueLockedThreadSafe {
    __block BOOL locked = NO;
    if (!_contentQueue) {
        return _isRequestQueueLocked;
    }
    dispatch_sync(_contentQueue, ^{
        locked = self->_isRequestQueueLocked;
    });
    return locked;
}

- (void)setRequestQueueLockedThreadSafe:(BOOL)locked {
    if (!_contentQueue) {
        _isRequestQueueLocked = locked;
        return;
    }
    dispatch_async(_contentQueue, ^{
        self->_isRequestQueueLocked = locked;
    });
}

- (void)enterContentZone {
    
    if(_isCurrentlyContentShown){
        CLY_LOG_I(@"%s a content is already shown, skipping" ,__FUNCTION__);
        return;
    }
    
    [self enterContentZone:@[]];
}

- (void)enterContentZone:(NSArray<NSString *> *)tags {
    if(_isCurrentlyContentShown){
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
    if(_isCurrentlyContentShown){
        CLY_LOG_I(@"%s a content is already shown, skipping" ,__FUNCTION__);
        return;
    }
    
    [CountlyConnectionManager.sharedInstance addQueueFlushRunnable:^{
        CLY_LOG_I(@"%s queue flueshed, will re-fetch contents" ,__FUNCTION__);
        [self exitContentZone];
        [self enterContentZone];
    }];
    [CountlyConnectionManager.sharedInstance attemptToSendStoredRequests];
}

- (void)refreshContentZoneJTE {
    if (![CountlyServerConfig.sharedInstance refreshContentZoneEnabled])
    {
        CLY_LOG_D(@"%s, refresh content zone is disabled, skipping JTE content refresh", __FUNCTION__);
        return;
    }
    if(_isCurrentlyContentShown){
        CLY_LOG_I(@"%s a content is already shown, skipping JTE content refresh" ,__FUNCTION__);
        return;
    }

    CLY_LOG_D(@"%s, Starting JTE content refresh with retries", __FUNCTION__);
    [self exitContentZone];
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

    if(_isCurrentlyContentShown){
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
    
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
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

    
    dispatch_async(dispatch_get_main_queue(), ^ {
        // Detect screen orientation
        UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
        BOOL isLandscape = UIInterfaceOrientationIsLandscape(orientation);
            
        // Get the appropriate coordinates based on the orientation
        NSDictionary *coordinates = isLandscape ? placementCoordinates[@"l"] : placementCoordinates[@"p"];
        
        CGFloat x = [coordinates[@"x"] floatValue];
        CGFloat y = [coordinates[@"y"] floatValue];
        CGFloat width = [coordinates[@"w"] floatValue];
        CGFloat height = [coordinates[@"h"] floatValue];
        
        CGRect frame = CGRectMake(x, y, width, height);
        
        // Log the URL and the frame
        CLY_LOG_I(@"%s showing content from URL: [%@], frame: [%@]", __FUNCTION__, url, NSStringFromCGRect(frame));
        CountlyWebViewManager* webViewManager =  CountlyWebViewManager.new;
            [webViewManager createWebViewWithURL:url frame:frame appearBlock:^
             {
                CLY_LOG_I(@"%s webview should be appeared", __FUNCTION__);
            } dismissBlock:^
             {
                CLY_LOG_I(@"%s webview dismissed", __FUNCTION__);
                self->_isCurrentlyContentShown = NO;
                self->_minuteTimer = [NSTimer scheduledTimerWithTimeInterval:self->_zoneTimerInterval
                                                                 target:self
                                                               selector:@selector(enterContentZone)
                                                               userInfo:nil
                                                                repeats:NO];
                if(self.contentCallback) {
                    self.contentCallback(CLOSED, NSDictionary.new);
                }
            }];
            CLY_LOG_I(@"%s webview initiated pausing content calls ", __FUNCTION__);
            self->_isCurrentlyContentShown = YES;
            [self clearContentState];
    });
}
#endif
@end
