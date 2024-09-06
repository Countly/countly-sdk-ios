// CountlyContentBuilder.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.
#if (TARGET_OS_IOS)
#import "CountlyContentBuilder.h"
#import "CountlyContentBuilderInternal.h"
#import "CountlyCommon.h"

@implementation CountlyContentBuilder
+ (instancetype)sharedInstance
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return nil;
    
    static CountlyContentBuilder* s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    
    return self;
}

- (void)enterContentZone
{
    [self enterContentZone:@[]];
}

- (void)enterContentZone:(NSArray<NSString *> *)tags
{
    [CountlyContentBuilderInternal.sharedInstance enterContentZone:tags];
}
- (void)exitContentZone
{
    [CountlyContentBuilderInternal.sharedInstance exitContentZone];
}
- (void)changeContent:(NSArray<NSString *> *)tags
{
    [CountlyContentBuilder.sharedInstance changeContent:tags];
}

@end
#else
#import "CountlyContentBuilder.h"
@implementation CountlyContentBuilder
@end
#endif
