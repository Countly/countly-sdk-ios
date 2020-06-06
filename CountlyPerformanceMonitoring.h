// CountlyPerformanceMonitoring.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@interface CountlyPerformanceMonitoring : NSObject
@property (nonatomic) BOOL isEnabledOnInitialConfig;

+ (instancetype)sharedInstance;

- (void)startPerformanceMonitoring;

- (void)recordNetworkTrace:(NSString *)traceName
        requestPayloadSize:(NSInteger)requestPayloadSize
       responsePayloadSize:(NSInteger)responsePayloadSize
        responseStatusCode:(NSInteger)responseStatusCode
                 startTime:(long long)startTime
                   endTime:(long long)endTime;

@end
