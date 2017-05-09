// CountlyAPMNetworkLog.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface CountlyAPMNetworkLog ()
@property (nonatomic) NSTimeInterval startTime;
@property (nonatomic) NSTimeInterval endTime;
@property (nonatomic) NSInteger HTTPStatusCode;
@property (nonatomic) long long sentDataSize;
@property (nonatomic) long long receivedDataSize;
@property (nonatomic) NSInteger connectionType;
@property (nonatomic, strong) NSURLRequest* request;
@property (nonatomic, weak) id <NSURLConnectionDataDelegate, NSURLConnectionDelegate> originalDelegate;
@end

NSString* const kCountlyReservedEventAPM = @"[CLY]_apm";

@implementation CountlyAPMNetworkLog

+ (instancetype)logWithRequest:(NSURLRequest *)request andOriginalDelegate:(id)originalDelegate startNow:(BOOL)startNow
{
    if ([CountlyAPM.sharedInstance isException:request])
        return nil;

    CountlyAPMNetworkLog* nl = CountlyAPMNetworkLog.new;
    nl.request = request;
    nl.originalDelegate = originalDelegate;
    nl.sentDataSize = [self.class sentDataSizeForRequest:request];

    if (startNow)
    {
        nl.connectionType = CountlyDeviceInfo.connectionType;
        nl.startTime = NSDate.date.timeIntervalSince1970;
    }

    return nl;
}

- (void)start
{
    self.sentDataSize = [self.class sentDataSizeForRequest:self.request];
    self.connectionType = CountlyDeviceInfo.connectionType;
    self.startTime = NSDate.date.timeIntervalSince1970;
}

- (void)updateWithResponse:(NSURLResponse *)response
{
    self.HTTPStatusCode =((NSHTTPURLResponse*)response).statusCode;
    self.receivedDataSize = [response expectedContentLength];

    if (self.receivedDataSize == NSURLResponseUnknownLength)
        self.receivedDataSize = 0; //NOTE: sometimes expectedContentLength is not available
}

- (void)finishWithStatusCode:(NSInteger)statusCode andDataSize:(long long)dataSize
{
    self.HTTPStatusCode = statusCode;
    self.receivedDataSize = dataSize;

    [self finish];
}

- (void)finish
{
    self.endTime = NSDate.date.timeIntervalSince1970;

    NSDictionary* segmentation =
    @{
        @"n": self.request.URL.absoluteString,
        @"e": @(self.HTTPStatusCode),
        @"h": self.request.URL.host,
        @"p": self.request.URL.path,
        @"c": @(self.connectionType),
        @"H": @YES,
        @"u": @NO
    };

    [Countly.sharedInstance recordEvent:kCountlyReservedEventAPM segmentation:segmentation count:1 sum:self.sentDataSize + self.receivedDataSize duration:self.endTime - self.startTime timestamp:self.startTime];

    COUNTLY_LOG(@"APM log recorded:\n%@", self);
}

#pragma mark -

+ (long long)sentDataSizeForRequest:(NSURLRequest *)request
{
    __block long long sentDataSize = 0;
    [request.allHTTPHeaderFields enumerateKeysAndObjectsUsingBlock:^(NSString * key, NSString * obj, BOOL * stop)
    {
        sentDataSize += [key lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + [obj lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    }];
    sentDataSize += [request.URL.absoluteString lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
    sentDataSize += request.HTTPBody.length;

    return sentDataSize;
}

- (NSString *)description
{
    return [NSString stringWithFormat: @"Request <%p> \n"
                                        "Request host: %@ \n"
                                        "Request path: %@ \n"
                                        "Start Time: %f \n"
                                        "End Time: %f \n"
                                        "Time Elapsed: %f \n"
                                        "HTTP Status Code: %lu \n"
                                        "Sent Data Size: %lu \n"
                                        "Received Data Size: %lu \n"
                                        "Connection Type: %d \n"
                                        "Request Successful: %d \n"
                                        "\n\n",
                                        self.request,
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

#pragma mark - Delegate Forwarding


- (BOOL)respondsToSelector:(SEL)aSelector
{
    if ([super respondsToSelector:aSelector])
        return YES;

    if ([self.originalDelegate respondsToSelector:aSelector])
        return YES;

    return NO;
}

- (id)forwardingTargetForSelector:(SEL)aSelector
{
    if ([self.originalDelegate respondsToSelector:aSelector])
        return self.originalDelegate;

    return [super forwardingTargetForSelector:aSelector];
}

#pragma mark - Connection Delegate

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    [self finishWithStatusCode:-1 andDataSize:0];

    if ([self.originalDelegate respondsToSelector:@selector(connection:didFailWithError:)])
        [self.originalDelegate connection:connection didFailWithError:error];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    [self updateWithResponse:response];

    if ([self.originalDelegate respondsToSelector:@selector(connection:didReceiveResponse:)])
        [self.originalDelegate connection:connection didReceiveResponse:response];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    [self finish];

    if ([self.originalDelegate respondsToSelector:@selector(connectionDidFinishLoading:)])
        [self.originalDelegate connectionDidFinishLoading:connection];
}

@end
