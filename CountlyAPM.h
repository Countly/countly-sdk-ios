// CountlyAPM.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyAPM : NSObject <NSURLConnectionDelegate,NSURLConnectionDataDelegate>

@property(nonatomic, strong) NSMutableArray* _Nonnull exceptionURLs;

+ (instancetype _Nonnull)sharedInstance;
- (void)startAPM;
- (void)addExceptionForAPM:(NSString* _Nonnull)exceptionURL;
- (void)removeExceptionForAPM:(NSString* _Nonnull)exceptionURL;
@end



#pragma mark -
@interface NSURLConnection (CountlyAPM)

@property (nonatomic, strong) id <NSURLConnectionDataDelegate,NSURLConnectionDelegate> _Nonnull originalDelegate;
@property (nonatomic, strong) CountlyAPMNetworkLog* _Nonnull APMNetworkLog;

+ (nullable NSData *)Countly_sendSynchronousRequest:(NSURLRequest  * _Nonnull )request
                                  returningResponse:(NSURLResponse * __nullable * __nullable)response
                                              error:(NSError * __nullable * __nullable)error;

+ (void)Countly_sendAsynchronousRequest:(NSURLRequest * _Nonnull) request
                                  queue:(NSOperationQueue*_Nonnull) queue
                      completionHandler:(void (^ _Nullable)(NSURLResponse* __nullable response, NSData* __nullable data, NSError* __nullable connectionError)) handler;

- (nullable instancetype)Countly_initWithRequest:(NSURLRequest * _Nonnull)request delegate:(nullable id)delegate;

- (nullable instancetype)Countly_initWithRequest:(NSURLRequest * _Nonnull)request delegate:(nullable id)delegate startImmediately:(BOOL)startImmediately;

- (void)Countly_start;

@end



#pragma mark -
@interface NSURLSession (CountlyAPM)
- (NSURLSessionDataTask * __nullable)Countly_dataTaskWithRequest:(NSURLRequest * _Nonnull)request
                                               completionHandler:(void (^ _Nullable)(NSData * __nullable data, NSURLResponse * __nullable response, NSError * __nullable error))completionHandler;

- (NSURLSessionDownloadTask * __nullable)Countly_downloadTaskWithRequest:(NSURLRequest * _Nonnull)request completionHandler:(void (^ _Nullable)(NSURL * __nullable location, NSURLResponse * __nullable response, NSError * __nullable error))completionHandler;

@end



@interface NSURLSessionTask (CountlyAPM)

@property (nonatomic, strong) CountlyAPMNetworkLog* _Nonnull APMNetworkLog;

- (void)Countly_resume;

@end