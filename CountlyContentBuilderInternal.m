// CountlyContent.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyContentBuilderInternal.h"
#if (TARGET_OS_IOS)
#import "CountlyWebViewManager.h"

//TODO: improve logging, check edge cases
NSString* const kCountlyEndpointContent = @"/o/sdk/content";
NSString* const kCountlyCBFetchContent  = @"queue";

@implementation CountlyContentBuilderInternal {
    BOOL _isRequestQueueLocked;
    NSTimer *_requestTimer;
    NSTimer *_minuteTimer;
}
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
        self.requestInterval = 30.0;
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
    _requestTimer = [NSTimer scheduledTimerWithTimeInterval:self.requestInterval
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
        
        NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *pathToHtml = jsonResponse[@"pathToHtml"];
        NSDictionary *placementCoordinates = jsonResponse[@"placementCoordinates"];
        
        [self showContentWithHtmlPath:pathToHtml placementCoordinates:placementCoordinates];
        self->_isRequestQueueLocked = NO;
    }];
    
    [dataTask resume];
}

- (NSURLRequest *)fetchContentsRequest
{
    NSString* queryString = [CountlyConnectionManager.sharedInstance queryEssentials];
    NSString *resolutionJson = [self resolutionJson];
    queryString = [queryString stringByAppendingFormat:@"&%@=%@&%@=%@",
                   kCountlyQSKeyMethod, kCountlyCBFetchContent,
                   @"res", resolutionJson];
    
    queryString = [CountlyConnectionManager.sharedInstance appendChecksum:queryString];
    
    NSString* URLString = [NSString stringWithFormat:@"%@%@?%@",
                           CountlyConnectionManager.sharedInstance.host,
                           kCountlyEndpointContent,
                           queryString];
    
    NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:URLString]];
    return request;
}

- (NSString *)resolutionJson {
    //TODO: check why area is not clickable and safearea things
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    if (@available(iOS 11.0, *)) {
        CGFloat top = UIApplication.sharedApplication.keyWindow.safeAreaInsets.top;
        
        if (top) {
            screenBounds.origin.y += top + 5;
            screenBounds.size.height -= top + 5;
        } else {
            screenBounds.origin.y += 20.0;
            screenBounds.size.height -= 20.0;
        }
    } else {
        screenBounds.origin.y += 20.0;
        screenBounds.size.height -= 20.0;
    }
    
    CGFloat width = screenBounds.size.width;
    CGFloat height = screenBounds.size.height;
    
    NSDictionary *resolutionDict = @{
        @"p": @{@"h": @(height), @"w": @(width)},
        @"l": @{@"h": @(width), @"w": @(height)}
    };
    
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:resolutionDict options:0 error:nil];
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

- (void)showContentWithHtmlPath:(NSString *)pathToHtml placementCoordinates:(NSDictionary *)placementCoordinates {
    // Convert pathToHtml to NSURL
    NSURL *url = [NSURL URLWithString:pathToHtml];
    
    dispatch_async(dispatch_get_main_queue(), ^ {
    // Detect screen orientation
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    BOOL isLandscape = UIInterfaceOrientationIsLandscape(orientation);
        
    
    // Get the appropriate coordinates based on the orientation
    NSDictionary *coordinates = isLandscape ? placementCoordinates[@"landscape"] : placementCoordinates[@"portrait"];
    
    CGFloat x = [coordinates[@"x"] floatValue];
    CGFloat y = [coordinates[@"y"] floatValue];
    CGFloat width = [coordinates[@"width"] floatValue];
    CGFloat height = [coordinates[@"height"] floatValue];
    
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
@end
#else
@implementation CountlyContentBuilderInternal
@end
#endif
