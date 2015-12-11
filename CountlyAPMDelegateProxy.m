// CountlyAPMDelegateProxy.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@implementation CountlyAPMDelegateProxy
+(instancetype)sharedInstance
{
    static CountlyAPMDelegateProxy* s_sharedCountlyAPMDelegateProxy;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
        s_sharedCountlyAPMDelegateProxy = self.new;
        s_sharedCountlyAPMDelegateProxy.listOfOngoingConnections = NSMutableArray.new;

        NSURL * url = [NSURL URLWithString:CountlyConnectionManager.sharedInstance.appHost];
        NSString* hostAndPath = [url.host stringByAppendingString:url.path];
        s_sharedCountlyAPMDelegateProxy.exceptionURLs = [NSMutableArray arrayWithObject:hostAndPath];
    });
    return s_sharedCountlyAPMDelegateProxy;
}

-(void)connection:(NSURLConnection *)connection didFailWithError:(nonnull NSError *)error
{    
    [self.listOfOngoingConnections.copy enumerateObjectsUsingBlock:^(CountlyAPMNetworkLog* nl, NSUInteger idx, BOOL * _Nonnull stop)
    {
        if([nl.request isEqual:connection.originalRequest])
        {
            [nl finishWithStatusCode:-1 andDataSize:0];
            *stop = YES;
        }
    }];

    
    if (connection.originalDelegate &&
        [connection.originalDelegate respondsToSelector:@selector(connection:didFailWithError:)])
    {
        [connection.originalDelegate connection:connection didFailWithError:error];
    }
}


-(void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    [self.listOfOngoingConnections.copy enumerateObjectsUsingBlock:^(CountlyAPMNetworkLog* nl, NSUInteger idx, BOOL * _Nonnull stop)
    {
        if([nl.request isEqual:connection.originalRequest])
        {
            [nl updateWithResponse:response];
            *stop = YES;
         }
     }];
    
    if (connection.originalDelegate &&
        [connection.originalDelegate respondsToSelector:@selector(connection:didReceiveResponse:)])
    {
        [connection.originalDelegate connection:connection didReceiveResponse:response];
    }
}

-(void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    [self.listOfOngoingConnections.copy enumerateObjectsUsingBlock:^(CountlyAPMNetworkLog* nl, NSUInteger idx, BOOL * _Nonnull stop)
    {
        if([nl.request isEqual:connection.originalRequest])
        {
            [nl finish];
            *stop = YES;
        }
    }];
    
    if (connection.originalDelegate &&
        [connection.originalDelegate respondsToSelector:@selector(connectionDidFinishLoading:)])
    {
        [connection.originalDelegate connectionDidFinishLoading:connection];
    }
}

@end