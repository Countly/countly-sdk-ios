// CountlyAPMNetworkLog.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>
#import "Countly.h"

@interface CountlyAPMNetworkLog : NSObject
@property(nonatomic, strong) NSURLRequest* request;
+ (instancetype)createWithRequest:(NSURLRequest *)request startImmediately:(BOOL)startImmediately;
- (void)start;
- (void)updateWithResponse:(NSURLResponse *)response;
- (void)finish;
- (void)finishWithStatusCode:(NSInteger)statusCode andDataSize:(long long)dataSize;
@end