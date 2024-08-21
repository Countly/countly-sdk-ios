// CountlyContent.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.
#import "CountlyContentBuilderInternal.h"
#import "CountlyWebViewManager.h"


NSString* const kCountlyEndpointContent = @"/o/sdk/content";
NSString* const kCountlyCBFetchContent  = @"queue";
NSString* const kCountlyCBCheckAvailbleContents  = @"check_available_contents";

@implementation CountlyContentBuilderInternal {
    BOOL _isRequestQueueLocked;
    NSTimer *_requestTimer;
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
        self.isContentConsentGiven = YES;
        self.latestChecksum = nil;
        self.density = 1; //TODO: [UIScreen mainScreen].scale;
        self.requestInterval = 30.0;
        _requestTimer = nil;
    }
    
    return self;
}

- (void)openForContent:(NSArray<NSString *> *)tags {
    if (!self.isContentConsentGiven) {
        return;
    }
    
    if(_requestTimer != nil) {
        CLY_LOG_I(@"Already open for content, please exit from content first to start again");
        return;
    }
    self.currentTags = tags;
    
    [self fetchContentDetailsForContentId:@"contentId"]; //TODO: [self sendContentCheckRequest];
    _requestTimer = [NSTimer scheduledTimerWithTimeInterval:self.requestInterval
                                                     target:self
                                                   selector:@selector(fetchContentDetailsForContentId) // TODO: sendContentCheckRequest
                                                   userInfo:nil
                                                    repeats:YES];
}

- (void)exitFromContent {
    [self clearContentState];
}

- (void)changeContent:(NSArray<NSString *> *)tags {
    if (![tags isEqualToArray:self.currentTags]) {
        [self exitFromContent];
        [self openForContent:tags];
    }
}

#pragma mark - Private Methods

- (void)clearContentState {
    [_requestTimer invalidate];
    _requestTimer = nil;
    self.currentTags = nil;
    self.latestChecksum = nil;
    _isRequestQueueLocked = NO;
}

- (void)sendContentCheckRequest {
    if (!self.isContentConsentGiven || _isRequestQueueLocked) {
        return;
    }
    
    _isRequestQueueLocked = YES;
    
    // Send request
    NSURLSessionTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:[self checkContentRequest] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            CLY_LOG_I(@"Content check request failed: %@", error);
            self->_isRequestQueueLocked = NO;
            return;
        }
        
        // Process the response
        NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSString *newChecksum = jsonResponse[@"checksum"];
        NSString *contentId = jsonResponse[@"content_id"];
        
        if (newChecksum && ![newChecksum isEqualToString:self.latestChecksum]) {
            self.latestChecksum = newChecksum;
            [self fetchContentDetailsForContentId:contentId];
        }
        
        self->_isRequestQueueLocked = NO;
    }];
    
    [task resume];
}

//TODO: remove this method
- (void) fetchContentDetailsForContentId {
    [self fetchContentDetailsForContentId:@""];
}
- (void)fetchContentDetailsForContentId:(NSString *)contentId {
    //TODO: removed _isRequestQueueLocked from this method when we are using 'sendContentCheckRequest'
    if  (_isRequestQueueLocked) {
        return;
    }
    
    _isRequestQueueLocked = YES;
    
    NSURLSessionTask *dataTask = [[NSURLSession sharedSession] dataTaskWithRequest:[self fetchContentDetailsRequest:contentId] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
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

- (NSURLRequest *)checkContentRequest
{
    NSString* queryString = [CountlyConnectionManager.sharedInstance queryEssentials];
    NSString *tagsString = [self.currentTags componentsJoinedByString:@","];
    
    queryString = [queryString stringByAppendingFormat:@"&%@=%@&%@=[%@]",
                   kCountlyQSKeyMethod, kCountlyCBCheckAvailbleContents,
                   @"tags", tagsString];
    
    queryString = [CountlyConnectionManager.sharedInstance appendChecksum:queryString];
    
    NSString* URLString = [NSString stringWithFormat:@"%@%@?%@",
                           CountlyConnectionManager.sharedInstance.host,
                           kCountlyEndpointContent,
                           queryString];
    
    NSURLRequest* request = [NSURLRequest requestWithURL:[NSURL URLWithString:URLString]];
    return request;
}

- (NSURLRequest *)fetchContentDetailsRequest:(NSString *)content_id
{
    NSString* queryString = [CountlyConnectionManager.sharedInstance queryEssentials];
    NSString *resolutionJson = [self resolutionJson];
    queryString = [queryString stringByAppendingFormat:@"&%@=%@&%@=%@&%@=%@",
                   kCountlyQSKeyMethod, kCountlyCBFetchContent,
                   @"content_id", content_id,
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
    
    // Extract placement coordinates and adjust for screen density
    CGFloat x = [coordinates[@"x"] floatValue] / self.density;
    CGFloat y = [coordinates[@"y"] floatValue] / self.density;
    CGFloat width = [coordinates[@"width"] floatValue] / self.density;
    CGFloat height = [coordinates[@"height"] floatValue] / self.density;
    
    CGRect frame = CGRectMake(x, y, width, height);
    
    // Log the URL and the frame
    CLY_LOG_I(@"Showing content from URL: %@", url);
    CLY_LOG_I(@"Placement frame: %@", NSStringFromCGRect(frame));
    
    CountlyWebViewManager* webViewManager =  CountlyWebViewManager.new;
        [webViewManager createWebViewWithURL:url frame:frame appearBlock:^
         {
            CLY_LOG_I(@"Webview appeared");
        } dismissBlock:^
         {
            CLY_LOG_I(@"Webview dismissed");
            if(self.contentCallback) {
                self.contentCallback(CLOSED, NSDictionary.new);
            }
        }];
    });
}
@end
