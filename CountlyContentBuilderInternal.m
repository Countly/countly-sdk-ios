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
        CLY_LOG_I(@"Already entered for content zone, please exit from content zone first to start again");
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
            CLY_LOG_I(@"Fetch content details failed: %@", error);
            self->_isRequestQueueLocked = NO;
            return;
        }
        
        NSError *jsonError;
        NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        
        if (jsonError) {
            CLY_LOG_I(@"Failed to parse JSON: %@", jsonError);
            self->_isRequestQueueLocked = NO;
            return;
        }
        
        if (!jsonResponse) {
            CLY_LOG_I(@"Received empty or null response.");
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
    
    NSString* URLString = [NSString stringWithFormat:@"%@%@?%@",
                           CountlyConnectionManager.sharedInstance.host,
                           kCountlyEndpointContent,
                           queryString];
    
    NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:URLString]];
    return request;
}

- (CGSize)getWindowSize {
    CGSize size = CGSizeZero;

    // Attempt to retrieve the size from the connected scenes (for modern apps)
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *scenes = [[UIApplication sharedApplication] connectedScenes];
        for (UIScene *scene in scenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                UIWindow *window = windowScene.windows.firstObject;
                if (window) {
                    size = window.bounds.size;
                    return size; // Return immediately if we find a valid size
                }
            }
        }
    }

    // Fallback for legacy apps using AppDelegate
    id<UIApplicationDelegate> appDelegate = [[UIApplication sharedApplication] delegate];
    if ([appDelegate respondsToSelector:@selector(window)]) {
        UIWindow *legacyWindow = [appDelegate performSelector:@selector(window)];
        if (legacyWindow) {
            size = legacyWindow.bounds.size;
        }
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
    
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:resolutionDict options:0 error:nil];
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (void)showContentWithHtmlPath:(NSString *)urlString placementCoordinates:(NSDictionary *)placementCoordinates {
    // Convert pathToHtml to NSURL
    NSURL *url = [NSURL URLWithString:urlString];
    
    if (!url || !url.scheme || !url.host) {
        NSLog(@"The URL is not valid: %@", urlString);
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
    CLY_LOG_I(@"Showing content from URL: %@", url);
    CLY_LOG_I(@"Placement frame: %@", NSStringFromCGRect(frame));
    
    CountlyWebViewManager* webViewManager =  CountlyWebViewManager.new;
        [webViewManager createWebViewWithURL:url frame:frame appearBlock:^
         {
            CLY_LOG_I(@"Webview appeared");
            [self clearContentState];
        } dismissBlock:^
         {
            CLY_LOG_I(@"Webview dismissed");
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
