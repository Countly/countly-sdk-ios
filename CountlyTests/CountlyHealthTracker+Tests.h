#import "CountlyHealthTracker.h"

@interface CountlyHealthTracker (Tests)
@property (nonatomic, strong) NSMutableDictionary *methodUsage;
@property (nonatomic, strong) NSMutableDictionary *logCodes;
- (NSURLRequest *)healthCheckRequest;
@end
