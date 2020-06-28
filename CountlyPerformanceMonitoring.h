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
- (void)stopPerformanceMonitoring;
- (void)recordAppStartDurationTraceWithStartTime:(long long)startTime endTime:(long long)endTime;
- (void)endBackgroundTrace;

- (void)recordNetworkTrace:(NSString *)traceName
        requestPayloadSize:(NSInteger)requestPayloadSize
       responsePayloadSize:(NSInteger)responsePayloadSize
        responseStatusCode:(NSInteger)responseStatusCode
                 startTime:(long long)startTime
                   endTime:(long long)endTime;

- (void)startCustomTrace:(NSString *)traceName;
- (void)endCustomTrace:(NSString *)traceName metrics:(NSDictionary *)metrics;
- (void)cancelCustomTrace:(NSString *)traceName;
- (void)clearAllCustomTraces;

@end
