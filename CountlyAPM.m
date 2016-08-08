// CountlyAPM.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

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
        NSURL * url = [NSURL URLWithString:CountlyConnectionManager.sharedInstance.appHost];
        NSString* hostAndPath = [url.host stringByAppendingString:url.path];
        self.exceptionURLs = [NSMutableArray arrayWithObject:hostAndPath];
    }
    
    return self;
}

- (void)startAPM
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

    O_method = class_getInstanceMethod(NSURLSession.class, @selector(downloadTaskWithRequest:completionHandler:));
    C_method = class_getInstanceMethod(NSURLSession.class, @selector(Countly_downloadTaskWithRequest:completionHandler:));
    method_exchangeImplementations(O_method, C_method);


    O_method = class_getInstanceMethod(NSClassFromString(@"__NSCFLocalDataTask"), @selector(resume));
    C_method = class_getInstanceMethod(NSClassFromString(@"__NSCFLocalDataTask"), @selector(Countly_resume));

#if TARGET_OS_IOS
    if(NSFoundationVersionNumber <= NSFoundationVersionNumber_iOS_8_0)
    {
        O_method = class_getInstanceMethod(NSURLSessionTask.class, @selector(resume));
        C_method = class_getInstanceMethod(NSURLSessionTask.class, @selector(Countly_resume));
    }
#endif

    method_exchangeImplementations(O_method, C_method);
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


#pragma mark -

- (void)connection:(NSURLConnection *)connection didFailWithError:(nonnull NSError *)error
{
    [connection.APMNetworkLog finishWithStatusCode:-1 andDataSize:0];

    if (connection.originalDelegate &&
        [connection.originalDelegate respondsToSelector:@selector(connection:didFailWithError:)])
    {
        [connection.originalDelegate connection:connection didFailWithError:error];
    }
}


- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    [connection.APMNetworkLog updateWithResponse:response];

    if (connection.originalDelegate &&
        [connection.originalDelegate respondsToSelector:@selector(connection:didReceiveResponse:)])
    {
        [connection.originalDelegate connection:connection didReceiveResponse:response];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    [connection.APMNetworkLog finish];

    if (connection.originalDelegate &&
        [connection.originalDelegate respondsToSelector:@selector(connectionDidFinishLoading:)])
    {
        [connection.originalDelegate connectionDidFinishLoading:connection];
    }
}

@end



#pragma mark -
@implementation NSURLConnection (CountlyAPM)
@dynamic originalDelegate, APMNetworkLog;

+ (nullable NSData *)Countly_sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse **)response error:(NSError **)error
{
    CountlyAPMNetworkLog* nl = [CountlyAPMNetworkLog createWithRequest:request startImmediately:YES];

    NSData *data = [self Countly_sendSynchronousRequest:request returningResponse:response error:error];

    [nl finishWithStatusCode:((NSHTTPURLResponse*)*response).statusCode andDataSize:data.length];

    return data;
}

+ (void)Countly_sendAsynchronousRequest:(NSURLRequest *) request
                                  queue:(NSOperationQueue *) queue
                      completionHandler:(void (^)(NSURLResponse* response, NSData* data, NSError* connectionError)) handler

{
    CountlyAPMNetworkLog* nl = [CountlyAPMNetworkLog createWithRequest:request startImmediately:YES];

    [self Countly_sendAsynchronousRequest:request queue:queue completionHandler:^(NSURLResponse * _Nullable response, NSData * _Nullable data, NSError * _Nullable connectionError)
    {
        [nl finishWithStatusCode:((NSHTTPURLResponse*)response).statusCode andDataSize:data.length];

        if (handler)
        {
            handler(response, data, connectionError);
        }
    }];
};

- (nullable instancetype)Countly_initWithRequest:(NSURLRequest * _Nonnull)request delegate:(nullable id)delegate
{
    CountlyAPMNetworkLog* nl = [CountlyAPMNetworkLog createWithRequest:request startImmediately:NO];

    NSURLConnection* c = [self Countly_initWithRequest:request delegate:CountlyAPM.sharedInstance startImmediately:NO];
    c.originalDelegate = delegate;
    c.APMNetworkLog = nl;
    [c start];

    return c;
}

- (nullable instancetype)Countly_initWithRequest:(NSURLRequest * _Nonnull)request delegate:(nullable id)delegate startImmediately:(BOOL)startImmediately
{
    CountlyAPMNetworkLog* nl = [CountlyAPMNetworkLog createWithRequest:request startImmediately:startImmediately];

    NSURLConnection* c = [self Countly_initWithRequest:request delegate:CountlyAPM.sharedInstance startImmediately:NO];
    c.originalDelegate = delegate;
    c.APMNetworkLog = nl;
    if(startImmediately)
        [c start];

    return c;
}

- (void)Countly_start
{
    [self.APMNetworkLog start];

    [self Countly_start];
}

- (id)originalDelegate
{
    return objc_getAssociatedObject(self, @selector(originalDelegate));
}

- (void)setOriginalDelegate:(id)originalDelegate
{
    objc_setAssociatedObject(self, @selector(originalDelegate), originalDelegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (CountlyAPMNetworkLog *)APMNetworkLog
{
    return objc_getAssociatedObject(self, @selector(APMNetworkLog));
}

- (void)setAPMNetworkLog:(CountlyAPMNetworkLog *)APMNetworkLog
{
    objc_setAssociatedObject(self, @selector(APMNetworkLog), APMNetworkLog, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end



#pragma mark -
@implementation NSURLSession (CountlyAPM)
- (NSURLSessionDataTask *)Countly_dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData * __nullable data, NSURLResponse * __nullable response, NSError * __nullable error))completionHandler
{
    CountlyAPMNetworkLog* nl = [CountlyAPMNetworkLog createWithRequest:request startImmediately:YES];

    NSURLSessionDataTask* dataTask = [self Countly_dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error)
    {
        [nl finishWithStatusCode:((NSHTTPURLResponse*)response).statusCode andDataSize:data.length];

        if (completionHandler)
        {
            completionHandler(data, response, error);
        }
    }];

    dataTask.APMNetworkLog = nl;

    return dataTask;
}

- (NSURLSessionDownloadTask * __nullable)Countly_downloadTaskWithRequest:(NSURLRequest * _Nonnull)request completionHandler:(void (^ _Nullable)(NSURL * __nullable location, NSURLResponse * __nullable response, NSError * __nullable error))completionHandler
{
    CountlyAPMNetworkLog* nl = [CountlyAPMNetworkLog createWithRequest:request startImmediately:YES];

    NSURLSessionDownloadTask* downloadTask = [self Countly_downloadTaskWithRequest:request completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error)
    {
        NSHTTPURLResponse* HTTPresponse = (NSHTTPURLResponse*)response;
        long long dataSize = [[HTTPresponse allHeaderFields][@"Content-Length"] longLongValue];

        [nl finishWithStatusCode:((NSHTTPURLResponse*)response).statusCode andDataSize:dataSize];

        if (completionHandler)
        {
            completionHandler(location, response, error);
        }
    }];

    downloadTask.APMNetworkLog = nl;

    return downloadTask;
}

@end



@implementation NSURLSessionTask (CountlyAPM)
@dynamic APMNetworkLog;

- (void)Countly_resume
{
    [self.APMNetworkLog start];

    [self Countly_resume];
}

- (CountlyAPMNetworkLog *)APMNetworkLog
{
    return objc_getAssociatedObject(self, @selector(APMNetworkLog));
}

- (void)setAPMNetworkLog:(id)APMNetworkLog
{
    objc_setAssociatedObject(self, @selector(APMNetworkLog), APMNetworkLog, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end