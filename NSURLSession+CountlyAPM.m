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
    
    return [self Countly_dataTaskWithRequest:request completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error)
    {
        [nl finishWithStatusCode:((NSHTTPURLResponse*)response).statusCode andDataSize:data.length];
    
        if (completionHandler)
        {
            completionHandler(data, response, error);
        }
    }];
}

@end

@implementation NSURLSessionTask (CountlyAPM)

- (void)Countly_resume
{
    [CountlyAPMDelegateProxy.sharedInstance.listOfOngoingConnections.copy enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop)
    {
        CountlyAPMNetworkLog* nl = (CountlyAPMNetworkLog*)obj;
        if([nl.request isEqual:self.originalRequest])
        {
            [nl start];
            *stop = YES;
         }
     }];

    [self Countly_resume];
}

@end
