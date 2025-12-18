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

NSInteger const contentInitialDelay = 4;

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
    }
    
    [self enterContentZone:@[]];
}

- (void)enterContentZone:(NSArray<NSString *> *)tags {
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
    
    if (CountlyCommon.sharedInstance.timeSinceLaunch < contentInitialDelay) {
        contentDelay = contentInitialDelay;
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

- (void)refreshContentZone {
    if (![CountlyServerConfig.sharedInstance refreshContentZoneEnabled])
    {
        return;
    }
    if(_isCurrentlyContentShown){
        CLY_LOG_I(@"%s a content is already shown, skipping" ,__FUNCTION__);
    }
    
    [self exitContentZone];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [CountlyConnectionManager.sharedInstance attemptToSendStoredRequestsSync];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self enterContentZone]; // this touches to UI so it needs to be handled in the main queue
        });
    });

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
    if (!CountlyConsentManager.sharedInstance.consentForContent)
        return;

    if (!CountlyServerConfig.sharedInstance.networkingEnabled)
        return;
    if ([self isRequestQueueLockedThreadSafe]) {
        return;
    }
    
    [self setRequestQueueLockedThreadSafe:YES];
    
    NSURLSessionTask *dataTask = [[NSURLSession sharedSession] dataTaskWithRequest:[self fetchContentsRequest] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            CLY_LOG_I(@"%s fetch content details failed: [%@]", __FUNCTION__, error);
            [self setRequestQueueLockedThreadSafe:NO];
            return;
        }
        
        NSError *jsonError;
        NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        
        if (jsonError) {
            CLY_LOG_I(@"%s failed to parse JSON: [%@]", __FUNCTION__, jsonError);
            [self setRequestQueueLockedThreadSafe:NO];
            return;
        }
        
        if (!jsonResponse) {
            CLY_LOG_I(@"%s received empty or null response.", __FUNCTION__);
            [self setRequestQueueLockedThreadSafe:NO];
            return;
        }
        
        NSString *pathToHtml = jsonResponse[@"html"];
        NSDictionary *placementCoordinates = jsonResponse[@"geo"];
        if(pathToHtml) {
            [self showContentWithHtmlPath:pathToHtml placementCoordinates:placementCoordinates];
        }
    [self setRequestQueueLockedThreadSafe:NO];
    }];
    
    [dataTask resume];
}

- (NSURLRequest *)fetchContentsRequest
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

    queryString = [CountlyConnectionManager.sharedInstance appendChecksum:queryString];

    NSString *URLString = [NSString stringWithFormat:@"%@%@?%@", CountlyConnectionManager.sharedInstance.host, kCountlyEndpointContent, queryString];

    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:URLString]];
    return request;
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
