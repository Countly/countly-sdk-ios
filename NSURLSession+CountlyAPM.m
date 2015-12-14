// NSURLSession+CountlyAPM.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

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

    dataTask.apmNetworkLog = nl;
    
    return dataTask;
}

@end


static void *CountlyAPMNetworkLogKey = &CountlyAPMNetworkLogKey;
@implementation NSURLSessionTask (CountlyAPM)

- (void)Countly_resume
{
    [self.apmNetworkLog start];

    [self Countly_resume];
}

- (CountlyAPMNetworkLog*)apmNetworkLog
{
    return objc_getAssociatedObject(self, CountlyAPMNetworkLogKey);
}

- (void)setApmNetworkLog:(id)apmNetworkLog
{
    objc_setAssociatedObject(self, CountlyAPMNetworkLogKey, apmNetworkLog, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end