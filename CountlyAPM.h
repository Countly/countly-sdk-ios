// CountlyAPM.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyAPM : NSObject
+ (instancetype)sharedInstance;
- (void)startAPM;
- (void)addExceptionForAPM:(NSString *)exceptionURL;
- (void)removeExceptionForAPM:(NSString* )exceptionURL;
- (BOOL)isException:(NSURLRequest *)request;
@end
