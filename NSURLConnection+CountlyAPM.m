// NSURLConnection+CountlyAPM.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

static void *CountlyAPMOriginalDelegateKey = &CountlyAPMOriginalDelegateKey;
static void *CountlyAPMNetworkLogKey = &CountlyAPMNetworkLogKey;

@implementation NSURLConnection (CountlyAPM)
+ (nullable NSData *)Countly_sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse **)response error:(NSError **)error
{
    CountlyAPMNetworkLog* nl = [CountlyAPMNetworkLog createWithRequest:request startImmediately:YES];

    NSData *data = [self Countly_sendSynchronousRequest:request returningResponse:response error:error];

    [nl finishWithStatusCode:((NSHTTPURLResponse*)*response).statusCode andDataSize:data.length];
    
    return data;
}

+ (void)Countly_sendAsynchronousRequest:(NSURLRequest*) request
                                  queue:(NSOperationQueue*) queue
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
    
    NSURLConnection* c = [self Countly_initWithRequest:request delegate:CountlyAPMDelegateProxy.sharedInstance startImmediately:NO];
    c.originalDelegate = delegate;
    c.apmNetworkLog = nl;
    [c start];
    
    return c;
}

- (nullable instancetype)Countly_initWithRequest:(NSURLRequest * _Nonnull)request delegate:(nullable id)delegate startImmediately:(BOOL)startImmediately
{
    CountlyAPMNetworkLog* nl = [CountlyAPMNetworkLog createWithRequest:request startImmediately:startImmediately];
    
    NSURLConnection* c = [self Countly_initWithRequest:request delegate:CountlyAPMDelegateProxy.sharedInstance startImmediately:NO];
    c.originalDelegate = delegate;
    c.apmNetworkLog = nl;
    if(startImmediately)
        [c start];
    
    return c;
}

- (void)Countly_start
{
    [self.apmNetworkLog start];

    [self Countly_start];
}

- (id)originalDelegate
{
    return objc_getAssociatedObject(self, CountlyAPMOriginalDelegateKey);
}

- (void)setOriginalDelegate:(id)originalDelegate
{
    objc_setAssociatedObject(self, CountlyAPMOriginalDelegateKey, originalDelegate, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (CountlyAPMNetworkLog*)apmNetworkLog
{
    return objc_getAssociatedObject(self, CountlyAPMNetworkLogKey);
}

- (void)setApmNetworkLog:(CountlyAPMNetworkLog*)apmNetworkLog
{
    objc_setAssociatedObject(self, CountlyAPMNetworkLogKey, apmNetworkLog, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end