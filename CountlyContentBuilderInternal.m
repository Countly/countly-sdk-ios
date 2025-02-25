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
    NSTimer *_requestTimer;
    NSTimer *_minuteTimer;
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
    }
    
    return self;
}

- (void)enterContentZone {
    [self enterContentZone:@[]];
}

- (void)enterContentZone:(NSArray<NSString *> *)tags {
    [_minuteTimer invalidate];
    _minuteTimer = nil;
    
    if (!CountlyConsentManager.sharedInstance.consentForContent)
        return;
    
    if(_requestTimer != nil) {
        CLY_LOG_I(@"%s, Already entered for content zone, please exit from content zone first to start again", __FUNCTION__);
        return;
    }
    
    self.currentTags = tags;
    
    [self fetchContents];;
    _requestTimer = [NSTimer scheduledTimerWithTimeInterval:self.zoneTimerInterval
                                                     target:self
                                                   selector:@selector(fetchContents)
                                                   userInfo:nil
                                                    repeats:YES];
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

#pragma mark - Private Methods

- (void)clearContentState {
    [_requestTimer invalidate];
    _requestTimer = nil;
    
    [_minuteTimer invalidate];
    _minuteTimer = nil;
    self.currentTags = nil;
    _isRequestQueueLocked = NO;
}

- (void)fetchContents {
    if (!CountlyConsentManager.sharedInstance.consentForContent)
        return;
    
    if  (_isRequestQueueLocked) {
        return;
    }
    
    _isRequestQueueLocked = YES;
    
    NSURLSessionTask *dataTask = [[NSURLSession sharedSession] dataTaskWithRequest:[self fetchContentsRequest] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            CLY_LOG_I(@"%s, Fetch content details failed: %@", __FUNCTION__, error);
            self->_isRequestQueueLocked = NO;
            return;
        }
        
        NSError *jsonError;
        NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        
        if (jsonError) {
            CLY_LOG_I(@"%s, Failed to parse JSON: %@", __FUNCTION__, jsonError);
            self->_isRequestQueueLocked = NO;
            return;
        }
        
        if (!jsonResponse) {
            CLY_LOG_I(@"%s, Received empty or null response.", __FUNCTION__);
            self->_isRequestQueueLocked = NO;
            return;
        }
        
        NSString *pathToHtml = jsonResponse[@"html"];
        NSDictionary *placementCoordinates = jsonResponse[@"geo"];
        if(pathToHtml) {
            [self showContentWithHtmlPath:pathToHtml placementCoordinates:placementCoordinates];
        }
        self->_isRequestQueueLocked = NO;
    }];
    
    [dataTask resume];
}

- (NSURLRequest *)fetchContentsRequest
{
    NSString* queryString = [CountlyConnectionManager.sharedInstance queryEssentials];
    NSString *resolutionJson = [self resolutionJson];
    queryString = [queryString stringByAppendingFormat:@"&%@=%@",
                   @"resolution", resolutionJson.cly_URLEscaped];
    
    queryString = [CountlyConnectionManager.sharedInstance appendChecksum:queryString];
    
    NSArray *components = [CountlyDeviceInfo.locale componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"_-"]];

    queryString = [queryString stringByAppendingFormat:@"&%@=%@",
                   @"la", components.firstObject];
    
    NSString* deviceType = CountlyDeviceInfo.deviceType;
    
    if(deviceType){
        queryString = [queryString stringByAppendingFormat:@"&%@=%@", @"dt", deviceType];
    }

    
    NSString* URLString = [NSString stringWithFormat:@"%@%@?%@",
                           CountlyConnectionManager.sharedInstance.host,
                           kCountlyEndpointContent,
                           queryString];
    
    NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:URLString]];
    return request;
}

- (CGSize)getWindowSize {
    UIWindow *window = nil;

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                window = ((UIWindowScene *)scene).windows.firstObject;
                break;
            }
        }
    } else {
        window = [[UIApplication sharedApplication].delegate window];
    }

    if (!window) return CGSizeZero;
    
    UIEdgeInsets safeArea = UIEdgeInsetsZero;
    CGFloat screenScale = [UIScreen mainScreen].scale;
    if (@available(iOS 11.0, *)) {
        safeArea = window.safeAreaInsets;
        safeArea.left /= screenScale;
        safeArea.bottom /= screenScale;
        safeArea.right /= screenScale;
    }
    
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    BOOL isLandscape = UIInterfaceOrientationIsLandscape(orientation);
    
    CGSize size = CGSizeMake(window.bounds.size.width, window.bounds.size.height);
    
    if(!isLandscape){
        size.width -= safeArea.left + safeArea.right;
        size.height -= safeArea.top + safeArea.bottom;
    }

    return size;
}

- (NSString *)resolutionJson {
    //TODO: check why area is not clickable and safearea things
    CGSize size = [self getWindowSize];
    
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    BOOL isLandscape = UIInterfaceOrientationIsLandscape(orientation);

    CGFloat lHpW = isLandscape ? size.height : size.width;
    CGFloat lWpH =  isLandscape ? size.width : size.height;
    
    NSDictionary *resolutionDict = @{
        @"portrait": @{@"height": @(lWpH), @"width": @(lHpW)},
        @"landscape": @{@"height": @(lHpW), @"width": @(lWpH)}
    };
    
    CLY_LOG_D(@"%s, %@", __FUNCTION__, resolutionDict);
    
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:resolutionDict options:0 error:nil];
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (void)showContentWithHtmlPath:(NSString *)urlString placementCoordinates:(NSDictionary *)placementCoordinates {
    // Convert pathToHtml to NSURL
    NSURL *url = [NSURL URLWithString:urlString];
    
    if (!url || !url.scheme || !url.host) {
        CLY_LOG_E(@"%s, The URL is not valid: %@", __FUNCTION__, urlString);
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
    CLY_LOG_I(@"%s, Showing content from URL: %@", __FUNCTION__, url);
    CLY_LOG_I(@"%s, Placement frame: %@", __FUNCTION__, NSStringFromCGRect(frame));
    
    CountlyWebViewManager* webViewManager =  CountlyWebViewManager.new;
        [webViewManager createWebViewWithURL:url frame:frame appearBlock:^
         {
            CLY_LOG_I(@"%s, Webview appeared", __FUNCTION__);
            [self clearContentState];
        } dismissBlock:^
         {
            CLY_LOG_I(@"%s, Webview dismissed", __FUNCTION__);
            self->_minuteTimer = [NSTimer scheduledTimerWithTimeInterval:60.0
                                                             target:self
                                                           selector:@selector(enterContentZone)
                                                           userInfo:nil
                                                            repeats:NO];
            if(self.contentCallback) {
                self.contentCallback(CLOSED, NSDictionary.new);
            }
        }];
    });
}
#endif
@end
