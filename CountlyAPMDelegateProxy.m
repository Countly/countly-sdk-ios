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
        NSURL * url = [NSURL URLWithString:CountlyConnectionManager.sharedInstance.appHost];
        NSString* hostAndPath = [url.host stringByAppendingString:url.path];
        s_sharedCountlyAPMDelegateProxy.exceptionURLs = [NSMutableArray arrayWithObject:hostAndPath];
    });
    return s_sharedCountlyAPMDelegateProxy;
}

-(void)connection:(NSURLConnection *)connection didFailWithError:(nonnull NSError *)error
{    
    [connection.apmNetworkLog finishWithStatusCode:-1 andDataSize:0];
    
    if (connection.originalDelegate &&
        [connection.originalDelegate respondsToSelector:@selector(connection:didFailWithError:)])
    {
        [connection.originalDelegate connection:connection didFailWithError:error];
    }
}


-(void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    [connection.apmNetworkLog updateWithResponse:response];
    
    if (connection.originalDelegate &&
        [connection.originalDelegate respondsToSelector:@selector(connection:didReceiveResponse:)])
    {
        [connection.originalDelegate connection:connection didReceiveResponse:response];
    }
}

-(void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    [connection.apmNetworkLog finish];
    
    if (connection.originalDelegate &&
        [connection.originalDelegate respondsToSelector:@selector(connectionDidFinishLoading:)])
    {
        [connection.originalDelegate connectionDidFinishLoading:connection];
    }
}

@end