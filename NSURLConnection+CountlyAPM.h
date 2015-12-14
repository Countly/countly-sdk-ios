// NSURLConnection+CountlyAPM.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface NSURLConnection (CountlyAPM)
@property (nonatomic, strong) id <NSURLConnectionDataDelegate,NSURLConnectionDelegate> _Nonnull originalDelegate;
@property (nonatomic, strong) CountlyAPMNetworkLog* _Nonnull apmNetworkLog;

+ (nullable NSData *)Countly_sendSynchronousRequest:(NSURLRequest  * _Nonnull )request returningResponse:(NSURLResponse * __nullable * __nullable)response error:(NSError * __nullable * __nullable)error;

+ (void)Countly_sendAsynchronousRequest:(NSURLRequest * _Nonnull) request
                          queue:(NSOperationQueue*_Nonnull) queue
              completionHandler:(void (^ _Nullable)(NSURLResponse* __nullable response, NSData* __nullable data, NSError* __nullable connectionError)) handler;

- (nullable instancetype)Countly_initWithRequest:(NSURLRequest * _Nonnull)request delegate:(nullable id)delegate;


- (nullable instancetype)Countly_initWithRequest:(NSURLRequest * _Nonnull)request delegate:(nullable id)delegate startImmediately:(BOOL)startImmediately;

- (void)Countly_start;

@end