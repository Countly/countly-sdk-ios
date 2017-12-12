// CountlyAPMNetworkLog.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>
#import "Countly.h"

@interface CountlyAPMNetworkLog : NSObject <NSURLConnectionDataDelegate, NSURLConnectionDelegate>
+ (instancetype)logWithRequest:(NSURLRequest *)request andOriginalDelegate:(id)originalDelegate startNow:(BOOL)startNow;
- (void)start;
- (void)updateWithResponse:(NSURLResponse *)response;
- (void)finish;
- (void)finishWithStatusCode:(NSInteger)statusCode andDataSize:(long long)dataSize;
@end
