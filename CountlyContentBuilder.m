// CountlyContentBuilder.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyContentBuilder.h"
#import "CountlyContentBuilderInternal.h"
#import "CountlyCommon.h"

@implementation CountlyContentBuilder
#if (TARGET_OS_IOS)
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
- (void)refreshContentZone
{
    [CountlyContentBuilderInternal.sharedInstance refreshContentZone];

}
- (void)changeContent:(NSArray<NSString *> *)tags
{
    [CountlyContentBuilder.sharedInstance changeContent:tags];
}

#endif
@end
