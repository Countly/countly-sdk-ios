#import "CountlyConnectionManager.h"

@interface CountlyConnectionManager (Tests)
/// Whether a request answered after the given number of seconds starts the backoff, as the queue decides after every answer.
- (BOOL)backoff:(long)responseTimeSeconds queryString:(NSString *)queryString;
@end
