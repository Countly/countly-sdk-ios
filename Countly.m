// Countly.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#pragma mark - Countly Core

#import "CountlyCommon.h"

@interface Countly ()
{
    double unsentSessionLength;
    NSTimer *timer;
    double lastTime;
    BOOL isSuspended;
}

@property (nonatomic, strong) NSMutableDictionary *messageInfos;

@end

@implementation Countly

+ (instancetype)sharedInstance
{
    static Countly *s_sharedCountly = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedCountly = self.new;});
	return s_sharedCountly;
}

- (instancetype)init
{
	if (self = [super init])
	{
		timer = nil;
		isSuspended = NO;
        [CountlyCommon.sharedInstance timeSinceLaunch];  //NOTE: just to force loading of CountlyCommon class for recording app start time
		unsentSessionLength = 0;
        
        self.messageInfos = NSMutableDictionary.new;

#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
		[NSNotificationCenter.defaultCenter addObserver:self
												 selector:@selector(didEnterBackgroundCallBack:)
													 name:UIApplicationDidEnterBackgroundNotification
												   object:nil];
		[NSNotificationCenter.defaultCenter addObserver:self
												 selector:@selector(willEnterForegroundCallBack:)
													 name:UIApplicationWillEnterForegroundNotification
												   object:nil];
		[NSNotificationCenter.defaultCenter addObserver:self
												 selector:@selector(willTerminateCallBack:)
													 name:UIApplicationWillTerminateNotification
												   object:nil];
#endif
	}

    return self;
}

#pragma mark ---

- (void)start:(NSString *)appKey withHost:(NSString*)appHost
{
	timer = [NSTimer scheduledTimerWithTimeInterval:COUNTLY_DEFAULT_UPDATE_INTERVAL
											 target:self
										   selector:@selector(onTimer:)
										   userInfo:nil
											repeats:YES];
	lastTime = CFAbsoluteTimeGetCurrent();
	CountlyConnectionManager.sharedInstance.appKey = appKey;
	CountlyConnectionManager.sharedInstance.appHost = appHost;
	[CountlyConnectionManager.sharedInstance beginSession];
}

- (void)startOnCloudWithAppKey:(NSString*)appKey
{
    [self start:appKey withHost:@"https://cloud.count.ly"];
}

#if (TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR) && (!COUNTLY_TARGET_WATCHKIT)
- (void)startWithMessagingUsing:(NSString *)appKey withHost:(NSString *)appHost andOptions:(NSDictionary *)options
{
    [self start:appKey withHost:appHost];
    
    NSDictionary *notification = [options objectForKey:UIApplicationLaunchOptionsRemoteNotificationKey];
    if (notification) {
        COUNTLY_LOG(@"Got notification on app launch: %@", notification);
//        [self handleRemoteNotification:notification displayingMessage:NO];
    }
}

- (void)startWithTestMessagingUsing:(NSString *)appKey withHost:(NSString *)appHost andOptions:(NSDictionary *)options
{
    [self start:appKey withHost:appHost];
    CountlyConnectionManager.sharedInstance.startedWithTest = YES;
    
    NSDictionary *notification = [options objectForKey:UIApplicationLaunchOptionsRemoteNotificationKey];
    if (notification) {
        COUNTLY_LOG(@"Got notification on app launch: %@", notification);
        [self handleRemoteNotification:notification displayingMessage:NO];
    }
    
    [self withAppStoreId:^(NSString *appId) {
        COUNTLY_LOG(@"ID: %@", appId);
    }];
}
#endif

#pragma mark ---

- (void)recordEvent:(NSString *)key
{
    [self recordEvent:key duration:0 segmentation:nil count:1 sum:0];
}

- (void)recordEvent:(NSString *)key count:(int)count
{
    [self recordEvent:key duration:0 segmentation:nil count:count sum:0];
}

- (void)recordEvent:(NSString *)key sum:(double)sum
{
    [self recordEvent:key duration:0 segmentation:nil count:1 sum:sum];
}

- (void)recordEvent:(NSString *)key count:(int)count sum:(double)sum
{
    [self recordEvent:key duration:0 segmentation:nil count:count sum:sum];
}

- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation
{
    [self recordEvent:key duration:0 segmentation:segmentation count:1 sum:0];
}

- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(int)count
{
    [self recordEvent:key duration:0 segmentation:segmentation count:count sum:0];
}

- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(int)count sum:(double)sum
{
    [self recordEvent:key duration:0 segmentation:segmentation count:count sum:sum];
}

- (void)recordEvent:(NSString *)key duration:(double)duration segmentation:(NSDictionary *)segmentation count:(int)count sum:(double)sum;
{
    @synchronized (self)
    {
        CountlyEvent *event = [CountlyEvent new];
        event.key = key;
        event.segmentation = segmentation;
        event.count = count;
        event.sum = sum;
        event.timestamp = time(NULL);
        event.hourOfDay = [CountlyCommon.sharedInstance hourOfDay];
        event.dayOfWeek = [CountlyCommon.sharedInstance dayOfWeek];
        event.duration = duration;
    
        [CountlyPersistency.sharedInstance.recordedEvents addObject:event];
    }
    
    if (CountlyPersistency.sharedInstance.recordedEvents.count >= COUNTLY_EVENT_SEND_THRESHOLD)
        [CountlyConnectionManager.sharedInstance sendEvents];
}

- (void)recordUserDetails:(NSDictionary *)userDetails
{
    [CountlyUserDetails.sharedInstance deserialize:userDetails];
    [CountlyConnectionManager.sharedInstance sendUserDetails];
}

- (void)setLocation:(double)latitude longitude:(double)longitude
{
    CountlyConnectionManager.sharedInstance.locationString = [NSString stringWithFormat:@"%f,%f", latitude, longitude];
}

#pragma mark ---

- (void)onTimer:(NSTimer *)timer
{
	if (isSuspended == YES)
		return;
    
	double currTime = CFAbsoluteTimeGetCurrent();
	unsentSessionLength += currTime - lastTime;
	lastTime = currTime;
    
	int duration = unsentSessionLength;
	[CountlyConnectionManager.sharedInstance updateSessionWithDuration:duration];
	unsentSessionLength -= duration;
    
    if (CountlyPersistency.sharedInstance.recordedEvents.count > 0)
        [CountlyConnectionManager.sharedInstance sendEvents];
}

- (void)suspend
{
	isSuspended = YES;
    
    if (CountlyPersistency.sharedInstance.recordedEvents.count > 0)
        [CountlyConnectionManager.sharedInstance sendEvents];
    
	double currTime = CFAbsoluteTimeGetCurrent();
	unsentSessionLength += currTime - lastTime;
    
	int duration = unsentSessionLength;
	[CountlyConnectionManager.sharedInstance endSessionWithDuration:duration];
	unsentSessionLength -= duration;
    
    [CountlyPersistency.sharedInstance saveToFile];
}

- (void)resume
{
	lastTime = CFAbsoluteTimeGetCurrent();
    
	[CountlyConnectionManager.sharedInstance beginSession];
    
	isSuspended = NO;
}

#pragma mark ---

- (void)didEnterBackgroundCallBack:(NSNotification *)notification
{
	COUNTLY_LOG(@"App didEnterBackground");
    [self suspend];
}

- (void)willEnterForegroundCallBack:(NSNotification *)notification
{
	COUNTLY_LOG(@"App willEnterForeground");
	[self resume];
}

- (void)willTerminateCallBack:(NSNotification *)notification
{
	COUNTLY_LOG(@"App willTerminate");
    [self suspend];
}

- (void)dealloc
{
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
    [NSNotificationCenter.defaultCenter removeObserver:self];
#endif
    
    if (timer)
    {
        [timer invalidate];
        timer = nil;
    }
}



#pragma mark - Countly Messaging
#if (TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR) && (!COUNTLY_TARGET_WATCHKIT)

#define kPushToMessage      1
#define kPushToOpenLink     2
#define kPushToUpdate       3
#define kPushToReview       4
#define kPushEventKeyOpen   @"[CLY]_push_open"
#define kPushEventKeyAction @"[CLY]_push_action"
#define kAppIdPropertyKey   @"[CLY]_app_id"
#define kCountlyAppId       @"695261996"

#pragma mark ---

- (BOOL)handleRemoteNotification:(NSDictionary *)info withButtonTitles:(NSArray *)titles
{
    return [self handleRemoteNotification:info displayingMessage:YES withButtonTitles:titles];
}

- (BOOL)handleRemoteNotification:(NSDictionary *)info
{
    return [self handleRemoteNotification:info displayingMessage:YES];
}

- (BOOL)handleRemoteNotification:(NSDictionary *)info displayingMessage:(BOOL)displayMessage
{
    return [self handleRemoteNotification:info displayingMessage:displayMessage
                         withButtonTitles:@[@"Cancel", @"Open", @"Update", @"Review"]];
}

- (BOOL)handleRemoteNotification:(NSDictionary *)info displayingMessage:(BOOL)displayMessage withButtonTitles:(NSArray *)titles
{
    COUNTLY_LOG(@"Handling remote notification (display? %d): %@", displayMessage, info);
    
    NSDictionary *aps = info[@"aps"];
    NSDictionary *countly = info[@"c"];
    
    if (countly[@"i"]) {
        COUNTLY_LOG(@"Message id: %@", countly[@"i"]);

        [self recordPushOpenForCountlyDictionary:countly];
        NSString *appName = [[NSBundle.mainBundle infoDictionary] objectForKey:(NSString*)kCFBundleNameKey];
        NSString *message = [aps objectForKey:@"alert"];
        
        int type = 0;
        NSString *action = nil;
        
        if ([aps objectForKey:@"content-available"]) {
            return NO;
        } else if (countly[@"l"]) {
            type = kPushToOpenLink;
            action = titles[1];
        } else if (countly[@"r"] != nil) {
            type = kPushToReview;
            action = titles[3];
        } else if (countly[@"u"] != nil) {
            type = kPushToUpdate;
            action = titles[2];
        } else if (displayMessage) {
            type = kPushToMessage;
            action = nil;
        }
        
        if (type && [message length]) {
            UIAlertView *alert;
            if (action) {
                alert = [[UIAlertView alloc] initWithTitle:appName message:message delegate:self
                                         cancelButtonTitle:titles[0] otherButtonTitles:action, nil];
            } else {
                alert = [[UIAlertView alloc] initWithTitle:appName message:message delegate:self
                                         cancelButtonTitle:titles[0] otherButtonTitles:nil];
            }
            alert.tag = type;
            
            _messageInfos[alert.description] = info;

            [alert show];
            return YES;
        }
    }
    
    return NO;
}

#pragma mark ---

- (NSMutableSet *) countlyNotificationCategories
{
    return [self countlyNotificationCategoriesWithActionTitles:@[@"Cancel", @"Open", @"Update", @"Review"]];
}

- (NSMutableSet *) countlyNotificationCategoriesWithActionTitles:(NSArray *)actions
{
    UIMutableUserNotificationCategory *url = [UIMutableUserNotificationCategory new],
    *upd = [UIMutableUserNotificationCategory new],
    *rev = [UIMutableUserNotificationCategory new];
    
    url.identifier = @"[CLY]_url";
    upd.identifier = @"[CLY]_update";
    rev.identifier = @"[CLY]_review";
    
    UIMutableUserNotificationAction *cancel = [UIMutableUserNotificationAction new],
    *open = [UIMutableUserNotificationAction new],
    *update = [UIMutableUserNotificationAction new],
    *review = [UIMutableUserNotificationAction new];
    
    cancel.identifier = @"[CLY]_cancel";
    open.identifier   = @"[CLY]_open";
    update.identifier = @"[CLY]_update";
    review.identifier = @"[CLY]_review";
    
    cancel.title = actions[0];
    open.title   = actions[1];
    update.title = actions[2];
    review.title = actions[3];
    
    cancel.activationMode = UIUserNotificationActivationModeBackground;
    open.activationMode   = UIUserNotificationActivationModeForeground;
    update.activationMode = UIUserNotificationActivationModeForeground;
    review.activationMode = UIUserNotificationActivationModeForeground;
    
    cancel.destructive = NO;
    open.destructive   = NO;
    update.destructive = NO;
    review.destructive = NO;
    
    
    [url setActions:@[cancel, open] forContext:UIUserNotificationActionContextMinimal];
    [url setActions:@[cancel, open] forContext:UIUserNotificationActionContextDefault];
    
    [upd setActions:@[cancel, update] forContext:UIUserNotificationActionContextMinimal];
    [upd setActions:@[cancel, update] forContext:UIUserNotificationActionContextDefault];
    
    [rev setActions:@[cancel, review] forContext:UIUserNotificationActionContextMinimal];
    [rev setActions:@[cancel, review] forContext:UIUserNotificationActionContextDefault];
    
    NSMutableSet *set = [NSMutableSet setWithObjects:url, upd, rev, nil];
    
    return set;
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    NSDictionary *info = [_messageInfos[alertView.description] copy];
    [_messageInfos removeObjectForKey:alertView.description];

    if (alertView.tag == kPushToMessage) {
        // do nothing
    } else if (buttonIndex != alertView.cancelButtonIndex) {
        if (alertView.tag == kPushToOpenLink) {
            [self recordPushActionForCountlyDictionary:info[@"c"]];
            [[UIApplication sharedApplication] openURL:[NSURL URLWithString:info[@"c"][@"l"]]];
        } else if (alertView.tag == kPushToUpdate) {
            if ([info[@"c"][@"u"] length]) {
                [self openUpdate:info[@"c"][@"u"] forInfo:info];
            } else {
                [self withAppStoreId:^(NSString *appStoreId) {
                    [self openUpdate:appStoreId forInfo:info];
                }];
            }
        } else if (alertView.tag == kPushToReview) {
            if ([info[@"c"][@"r"] length]) {
                [self openReview:info[@"c"][@"r"] forInfo:info];
            } else {
                [self withAppStoreId:^(NSString *appStoreId) {
                    [self openReview:appStoreId forInfo:info];
                }];
            }
        }
    }
}

- (void)withAppStoreId:(void (^)(NSString *))block
{
    NSString *appStoreId = [[NSUserDefaults standardUserDefaults] stringForKey:kAppIdPropertyKey];
    if (appStoreId) {
        block(appStoreId);
    } else {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            NSString *appStoreId = nil;
            NSString *bundle = [CountlyDeviceInfo bundleId];
            NSString *appStoreCountry = [(NSLocale *)[NSLocale currentLocale] objectForKey:NSLocaleCountryCode];
            if ([appStoreCountry isEqualToString:@"150"]) {
                appStoreCountry = @"eu";
            } else if ([[appStoreCountry stringByReplacingOccurrencesOfString:@"[A-Za-z]{2}" withString:@"" options:NSRegularExpressionSearch range:NSMakeRange(0, 2)] length]) {
                appStoreCountry = @"us";
            }
            
            NSString *iTunesServiceURL = [NSString stringWithFormat:@"http://itunes.apple.com/%@/lookup", appStoreCountry];
            iTunesServiceURL = [iTunesServiceURL stringByAppendingFormat:@"?bundleId=%@", bundle];
            
            NSError *error = nil;
            NSURLResponse *response = nil;
            NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:iTunesServiceURL] cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:10];
            NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
            NSInteger statusCode = ((NSHTTPURLResponse *)response).statusCode;
            if (data && statusCode == 200) {
                
                id json = [[NSJSONSerialization JSONObjectWithData:data options:(NSJSONReadingOptions)0 error:&error][@"results"] lastObject];
                
                if (!error && [json isKindOfClass:[NSDictionary class]]) {
                    NSString *bundleID = json[@"bundleId"];
                    if (bundleID && [bundleID isEqualToString:bundle]) {
                        appStoreId = [json[@"trackId"] stringValue];
                    }
                }
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [[NSUserDefaults standardUserDefaults] setObject:appStoreId forKey:kAppIdPropertyKey];
                [[NSUserDefaults standardUserDefaults] synchronize];
                block(appStoreId);
            });
        });
    }

}

- (void)openUpdate:(NSString *)appId forInfo:(NSDictionary *)info
{
    if (!appId) appId = kCountlyAppId;

    NSString *urlFormat = nil;
#if TARGET_OS_IPHONE
    urlFormat = @"itms-apps://itunes.apple.com/app/id%@";
#else
    urlFormat = @"macappstore://itunes.apple.com/app/id%@";
#endif

    [self recordPushActionForCountlyDictionary:info[@"c"]];
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:urlFormat, appId]];
    [[UIApplication sharedApplication] openURL:url];
}

- (void)openReview:(NSString *)appId forInfo:(NSDictionary *)info
{
    if (!appId) appId = kCountlyAppId;
    
    NSString *urlFormat = nil;
#if TARGET_OS_IPHONE
    float iOSVersion = [[UIDevice currentDevice].systemVersion floatValue];
    if (iOSVersion >= 7.0f && iOSVersion < 7.1f) {
        urlFormat = @"itms-apps://itunes.apple.com/app/id%@";
    } else {
        urlFormat = @"itms-apps://itunes.apple.com/WebObjects/MZStore.woa/wa/viewContentsUserReviews?type=Purple+Software&id=%@";
    }
#else
    urlFormat = @"macappstore://itunes.apple.com/app/id%@";
#endif

    [self recordPushActionForCountlyDictionary:info[@"c"]];
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:urlFormat, appId]];
    [[UIApplication sharedApplication] openURL:url];
}

#pragma mark ---

- (void)recordPushOpenForCountlyDictionary:(NSDictionary *)c
{
    [self recordEvent:kPushEventKeyOpen segmentation:@{@"i": c[@"i"]} count:1];
}

- (void)recordPushActionForCountlyDictionary:(NSDictionary *)c
{
    [self recordEvent:kPushEventKeyAction segmentation:@{@"i": c[@"i"]} count:1];
}

#pragma mark ---

- (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
    const unsigned *tokenBytes = [deviceToken bytes];
    NSString *token = [NSString stringWithFormat:@"%08x%08x%08x%08x%08x%08x%08x%08x",
                       ntohl(tokenBytes[0]), ntohl(tokenBytes[1]), ntohl(tokenBytes[2]),
                       ntohl(tokenBytes[3]), ntohl(tokenBytes[4]), ntohl(tokenBytes[5]),
                       ntohl(tokenBytes[6]), ntohl(tokenBytes[7])];
    [CountlyConnectionManager.sharedInstance sendPushToken:token];
}

- (void)didFailToRegisterForRemoteNotifications
{
    [CountlyConnectionManager.sharedInstance sendPushToken:nil];
}
#endif



#pragma mark - Countly CrashReporting

#if (TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR) && (!COUNTLY_TARGET_WATCHKIT)
- (void)startCrashReporting
{
    [CountlyCrashReporter.sharedInstance startCrashReporting];
}

- (void)startCrashReportingWithSegments:(NSDictionary *)segments
{
    [CountlyCrashReporter.sharedInstance startCrashReportingWithSegments:segments];
}

- (void)recordHandledException:(NSException *)exception
{
    [CountlyCrashReporter.sharedInstance recordHandledException:exception];
}
#endif



#pragma mark - Countly APM

-(void)startAPM
{
    Method O_method;
    Method C_method;
    
    O_method = class_getClassMethod(NSURLConnection.class, @selector(sendSynchronousRequest:returningResponse:error:));
    C_method = class_getClassMethod(NSURLConnection.class, @selector(Countly_sendSynchronousRequest:returningResponse:error:));
    method_exchangeImplementations(O_method, C_method);
    
    O_method = class_getClassMethod(NSURLConnection.class, @selector(sendAsynchronousRequest:queue:completionHandler:));
    C_method = class_getClassMethod(NSURLConnection.class, @selector(Countly_sendAsynchronousRequest:queue:completionHandler:));
    method_exchangeImplementations(O_method, C_method);
    
    O_method = class_getInstanceMethod(NSURLConnection.class, @selector(initWithRequest:delegate:));
    C_method = class_getInstanceMethod(NSURLConnection.class, @selector(Countly_initWithRequest:delegate:));
    method_exchangeImplementations(O_method, C_method);
    
    O_method = class_getInstanceMethod(NSURLConnection.class, @selector(initWithRequest:delegate:startImmediately:));
    C_method = class_getInstanceMethod(NSURLConnection.class, @selector(Countly_initWithRequest:delegate:startImmediately:));
    method_exchangeImplementations(O_method, C_method);
    
    O_method = class_getInstanceMethod(NSURLConnection.class, @selector(start));
    C_method = class_getInstanceMethod(NSURLConnection.class, @selector(Countly_start));
    method_exchangeImplementations(O_method, C_method);
    
    O_method = class_getInstanceMethod(NSURLSession.class, @selector(dataTaskWithRequest:completionHandler:));
    C_method = class_getInstanceMethod(NSURLSession.class, @selector(Countly_dataTaskWithRequest:completionHandler:));
    method_exchangeImplementations(O_method, C_method);
    
    O_method = class_getInstanceMethod(NSClassFromString(@"__NSCFLocalDataTask"), @selector(resume));
    C_method = class_getInstanceMethod(NSClassFromString(@"__NSCFLocalDataTask"), @selector(Countly_resume));

#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
    if(NSFoundationVersionNumber <= NSFoundationVersionNumber_iOS_8_0)
    {
        O_method = class_getInstanceMethod(NSURLSessionTask.class, @selector(resume));
        C_method = class_getInstanceMethod(NSURLSessionTask.class, @selector(Countly_resume));
    }
#endif

    method_exchangeImplementations(O_method, C_method);
}

-(void)addExceptionForAPM:(NSString*)string
{
    NSURL* url = [NSURL URLWithString:string];
    NSString* hostAndPath = [url.host stringByAppendingString:url.path];
    [CountlyAPM.sharedInstance.exceptionURLs addObject:hostAndPath];
}

-(void)removeExceptionForAPM:(NSString*)string
{
    NSURL * url = [NSURL URLWithString:string];
    NSString* hostAndPath = [url.host stringByAppendingString:url.path];
    [CountlyAPM.sharedInstance.exceptionURLs removeObject:hostAndPath];
}

@end