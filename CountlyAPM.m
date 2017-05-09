// CountlyAPM.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface CountlyAPM ()
@property (nonatomic, strong) NSMutableArray* exceptionURLs;
@end

@implementation CountlyAPM

+ (instancetype)sharedInstance
{
    static CountlyAPM* s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    if (self)
    {
        NSURL * url = [NSURL URLWithString:CountlyConnectionManager.sharedInstance.host];
        NSString* hostAndPath = [url.host stringByAppendingString:url.path];
        self.exceptionURLs = [NSMutableArray arrayWithObject:hostAndPath];
    }

    return self;
}

- (void)startAPM
{
    NSArray* swizzling =
    @[
        @{@"c":NSURLConnection.class, @"f":@YES, @"s":[NSValue valueWithPointer:@selector(sendSynchronousRequest:returningResponse:error:)]},
        @{@"c":NSURLConnection.class, @"f":@YES, @"s":[NSValue valueWithPointer:@selector(sendAsynchronousRequest:queue:completionHandler:)]},
        @{@"c":NSURLConnection.class, @"f":@NO,  @"s":[NSValue valueWithPointer:@selector(initWithRequest:delegate:)]},
        @{@"c":NSURLConnection.class, @"f":@NO,  @"s":[NSValue valueWithPointer:@selector(initWithRequest:delegate:startImmediately:)]},
        @{@"c":NSURLConnection.class, @"f":@NO,  @"s":[NSValue valueWithPointer:@selector(start)]},
        @{@"c":NSURLSession.class,    @"f":@NO,  @"s":[NSValue valueWithPointer:@selector(dataTaskWithRequest:completionHandler:)]},
        @{@"c":NSURLSession.class,    @"f":@NO,  @"s":[NSValue valueWithPointer:@selector(downloadTaskWithRequest:completionHandler:)]},
        @{@"c":NSURLSessionTask.class,     @"f":@NO,  @"s":[NSValue valueWithPointer:@selector(resume)]}
    ];


    for (NSDictionary* dict in swizzling)
    {
        Class c = dict[@"c"];
        BOOL isClassMethod = [dict[@"f"] boolValue];
        SEL originalSelector = [dict[@"s"] pointerValue];
        SEL countlySelector = NSSelectorFromString([@"Countly_" stringByAppendingString:NSStringFromSelector(originalSelector)]);

        Method O_method = isClassMethod ? class_getClassMethod(c, originalSelector) : class_getInstanceMethod(c, originalSelector);
        Method C_method = isClassMethod ? class_getClassMethod(c, countlySelector) : class_getInstanceMethod(c, countlySelector);
        method_exchangeImplementations(O_method, C_method);
    }
}

- (void)addExceptionForAPM:(NSString *)string
{
    NSURL* url = [NSURL URLWithString:string];
    NSString* hostAndPath = [url.host stringByAppendingString:url.path];

    if (![CountlyAPM.sharedInstance.exceptionURLs containsObject:hostAndPath])
    {
        [CountlyAPM.sharedInstance.exceptionURLs addObject:hostAndPath];
    }
}

- (void)removeExceptionForAPM:(NSString *)string
{
    NSURL * url = [NSURL URLWithString:string];
    NSString* hostAndPath = [url.host stringByAppendingString:url.path];
    [CountlyAPM.sharedInstance.exceptionURLs removeObject:hostAndPath];
}

- (BOOL)isException:(NSURLRequest *)request
{
    NSString* hostAndPath = [request.URL.host stringByAppendingString:request.URL.path];
    __block BOOL isException = NO;

    [CountlyAPM.sharedInstance.exceptionURLs enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL* stop)
    {
        if ([request.URL.host isEqualToString:obj] || [hostAndPath hasPrefix:obj])
        {
            isException = YES;
            *stop = YES;
        }
    }];

    return isException;
}
@end


#pragma mark -


@implementation NSURLConnection (CountlyAPM)

- (CountlyAPMNetworkLog *)APMNetworkLog
{
    return objc_getAssociatedObject(self, @selector(APMNetworkLog));
}

- (void)setAPMNetworkLog:(CountlyAPMNetworkLog *)APMNetworkLog
{
    objc_setAssociatedObject(self, @selector(APMNetworkLog), APMNetworkLog, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (NSData *)Countly_sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse **)response error:(NSError **)error
{
    CountlyAPMNetworkLog* nl = [CountlyAPMNetworkLog logWithRequest:request andOriginalDelegate:nil startNow:YES];

    NSData *data = [self Countly_sendSynchronousRequest:request returningResponse:response error:error];

    [nl finishWithStatusCode:((NSHTTPURLResponse*)*response).statusCode andDataSize:data.length];

    return data;
}

+ (void)Countly_sendAsynchronousRequest:(NSURLRequest *) request queue:(NSOperationQueue *) queue completionHandler:(void (^)(NSURLResponse* response, NSData* data, NSError* connectionError)) handler

{
    CountlyAPMNetworkLog* nl = [CountlyAPMNetworkLog logWithRequest:request andOriginalDelegate:nil startNow:YES];

    [self Countly_sendAsynchronousRequest:request queue:queue completionHandler:^(NSURLResponse * response, NSData * data, NSError * connectionError)
    {
        [nl finishWithStatusCode:((NSHTTPURLResponse*)response).statusCode andDataSize:data.length];

        if (handler)
            handler(response, data, connectionError);
    }];
};

- (instancetype)Countly_initWithRequest:(NSURLRequest *)request delegate:(id)delegate
{
    CountlyAPMNetworkLog* nl = [CountlyAPMNetworkLog logWithRequest:request andOriginalDelegate:delegate startNow:YES];
    NSURLConnection* conn = [self Countly_initWithRequest:request delegate:(nl ? nl : delegate) startImmediately:YES];
    conn.APMNetworkLog = nl;

    return conn;
}

- (instancetype)Countly_initWithRequest:(NSURLRequest *)request delegate:(id)delegate startImmediately:(BOOL)startImmediately
{
    CountlyAPMNetworkLog* nl = [CountlyAPMNetworkLog logWithRequest:request andOriginalDelegate:delegate startNow:startImmediately];
    NSURLConnection* conn = [self Countly_initWithRequest:request delegate:(nl ? nl : delegate) startImmediately:startImmediately];
    conn.APMNetworkLog = nl;

    return conn;
}

- (void)Countly_start
{
    [self.APMNetworkLog start];

    [self Countly_start];
}

@end


#pragma mark -


@implementation NSURLSessionTask (CountlyAPM)

- (CountlyAPMNetworkLog *)APMNetworkLog
{
    return objc_getAssociatedObject(self, @selector(APMNetworkLog));
}

- (void)setAPMNetworkLog:(id)APMNetworkLog
{
    objc_setAssociatedObject(self, @selector(APMNetworkLog), APMNetworkLog, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)Countly_resume
{
    [self.APMNetworkLog start];

    [self Countly_resume];
}

@end


@implementation NSURLSession (CountlyAPM)
- (NSURLSessionDataTask *)Countly_dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData * data, NSURLResponse * response, NSError * error))completionHandler
{
    CountlyAPMNetworkLog* nl = [CountlyAPMNetworkLog logWithRequest:request andOriginalDelegate:nil startNow:YES];

    NSURLSessionDataTask* dataTask = [self Countly_dataTaskWithRequest:request completionHandler:^(NSData * data, NSURLResponse * response, NSError * error)
    {
        [nl finishWithStatusCode:((NSHTTPURLResponse*)response).statusCode andDataSize:data.length];

        if (completionHandler)
            completionHandler(data, response, error);
    }];

    dataTask.APMNetworkLog = nl;

    return dataTask;
}

- (NSURLSessionDownloadTask *)Countly_downloadTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURL * location, NSURLResponse * response, NSError * error))completionHandler
{
    CountlyAPMNetworkLog* nl = [CountlyAPMNetworkLog logWithRequest:request andOriginalDelegate:nil startNow:YES];

    NSURLSessionDownloadTask* downloadTask = [self Countly_downloadTaskWithRequest:request completionHandler:^(NSURL * location, NSURLResponse * response, NSError * error)
    {
        NSHTTPURLResponse* HTTPresponse = (NSHTTPURLResponse*)response;
        long long dataSize = [[HTTPresponse allHeaderFields][@"Content-Length"] longLongValue];

        [nl finishWithStatusCode:((NSHTTPURLResponse*)response).statusCode andDataSize:dataSize];

        if (completionHandler)
            completionHandler(location, response, error);
    }];

    downloadTask.APMNetworkLog = nl;

    return downloadTask;
}

@end


