#import "CountlyHealthTracker.h"

@interface CountlyHealthTracker (Tests)
@property (nonatomic, strong) NSMutableDictionary *methodUsage;
@property (nonatomic, strong) NSMutableDictionary *logCodes;
@property (nonatomic, strong) dispatch_queue_t hcQueue;
- (NSURLRequest *)healthCheckRequest;
- (NSDictionary *)healthCheckSnapshot;
- (void)clearSentValues:(NSDictionary *)sent;
@end
