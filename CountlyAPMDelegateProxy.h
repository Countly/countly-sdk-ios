// CountlyAPMDelegateProxy.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyAPMDelegateProxy : NSObject <NSURLConnectionDelegate,NSURLConnectionDataDelegate>
+(instancetype)sharedInstance;
@property(nonatomic, strong) NSMutableArray* exceptionURLs;
@end
