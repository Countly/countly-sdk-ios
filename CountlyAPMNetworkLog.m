// CountlyAPMNetworkLog.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface CountlyAPMNetworkLog ()
@property(nonatomic, readwrite) NSTimeInterval startTime;
@property(nonatomic, readwrite) NSTimeInterval endTime;
@property(nonatomic, readwrite) NSInteger HTTPStatusCode;
@property(nonatomic, readwrite) long long sentDataSize;
@property(nonatomic, readwrite) long long receivedDataSize;
@property(nonatomic, readwrite) NSInteger connectionType;
@end


@implementation CountlyAPMNetworkLog

+(instancetype)createWithRequest:(NSURLRequest*)request
{
    return [self.class createWithRequest:request startImmediately:NO];
}

+(instancetype)createWithRequest:(NSURLRequest*)request startImmediately:(BOOL)startImmediately
{
    NSString* hostAndPath = [request.URL.host stringByAppendingString:request.URL.path];
    __block BOOL isException = NO;
        
    [CountlyAPMDelegateProxy.sharedInstance.exceptionURLs
     enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop)
    {
        if([obj isEqual:request.URL.host] || [obj isEqual:hostAndPath])
        {
            isException = YES;
            *stop = YES;
        }
    }];
    
    if (isException) return nil;
    
    CountlyAPMNetworkLog* nl = CountlyAPMNetworkLog.new;
    nl.request = request;
    nl.sentDataSize = [self.class sentDataSizeForRequest:request];
    [CountlyAPMDelegateProxy.sharedInstance.listOfOngoingConnections addObject:nl];
    
    if(startImmediately)
    {
        nl.connectionType = CountlyDeviceInfo.connectionType;
        nl.startTime = CFAbsoluteTimeGetCurrent();
    }
    
    return nl;
}

-(void)start
{
    self.sentDataSize = [self.class sentDataSizeForRequest:self.request];
    self.connectionType = CountlyDeviceInfo.connectionType;
    self.startTime = CFAbsoluteTimeGetCurrent();
}

-(void)updateWithResponse:(NSURLResponse *)response
{
    self.HTTPStatusCode =((NSHTTPURLResponse*)response).statusCode;
    self.receivedDataSize = [response expectedContentLength];
    
    if(self.receivedDataSize == NSURLResponseUnknownLength)
        self.receivedDataSize = 0; //NOTE: sometimes expectedContentLength is not available
}

-(void)finishWithStatusCode:(NSInteger)statusCode andDataSize:(long long)dataSize
{
    self.HTTPStatusCode = statusCode;
    self.receivedDataSize = dataSize;

    [self finish];
}

-(void)finish
{
    self.endTime = CFAbsoluteTimeGetCurrent();
    [CountlyAPMDelegateProxy.sharedInstance.listOfOngoingConnections removeObject:self];
    
    COUNTLY_LOG(@"%@",[self description]);
}

+(long long)sentDataSizeForRequest:(NSURLRequest*)request
{
    __block long long sentDataSize = 0;
    [request.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop)
    {
        sentDataSize += [key lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + [obj lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    }];
    sentDataSize += [request.URL.absoluteString lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    sentDataSize += request.HTTPBody.length;

    return sentDataSize;
}

-(NSString*)description
{
    return [NSString stringWithFormat: @"\n"
                                        "Request host: %@ \n"
                                        "Request path: %@ \n"
                                        "Start Time: %f \n"
                                        "End Time: %f \n"
                                        "Time Elapsed: %f \n"
                                        "HTTP Status Code: %lu \n"
                                        "Sent Data Size: %lu \n"
                                        "Received Data Size: %lu \n"
                                        "Connection Type: %i \n"
                                        "Request Successfull: %i \n"
                                        "\n\n",
                                        self.request.URL.host,
                                        self.request.URL.path,
                                        self.startTime,
                                        self.endTime,
                                        self.endTime-self.startTime,
                                        (long)self.HTTPStatusCode,
                                        (long)self.sentDataSize,
                                        (long)self.receivedDataSize,
                                        (int)self.connectionType,
                                        self.connectionType!=0 && self.HTTPStatusCode/100 == 2] ;
}

@end