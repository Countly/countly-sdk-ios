// NSURLSession+CountlyAPM.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface NSURLSession (CountlyAPM)
- (NSURLSessionDataTask * __nullable)Countly_dataTaskWithRequest:(NSURLRequest * _Nonnull)request completionHandler:(void (^ _Nullable)(NSData * __nullable data, NSURLResponse * __nullable response, NSError * __nullable error))completionHandler;
@end

@interface NSURLSessionTask (CountlyAPM)
@property (nonatomic, strong) CountlyAPMNetworkLog* _Nonnull apmNetworkLog;
- (void)Countly_resume;
@end