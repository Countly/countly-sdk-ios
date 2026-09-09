// CountlyContentBuilder.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyContentBuilder.h"
#import "CountlyContentBuilderInternal.h"
#import "CountlyCommon.h"

@implementation CountlyContentBuilder
#if (TARGET_OS_IOS || TARGET_OS_VISION)
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
    CLY_LOG_I(@"%s entering the content zone without tags", __FUNCTION__);
    [self enterContentZone:@[]];
}

- (void)enterContentZone:(NSArray<NSString *> *)tags
{
    CLY_LOG_I(@"%s entering the content zone, tags: [%@], tagCount: [%lu]", __FUNCTION__, tags, (unsigned long)tags.count);
    [CountlyContentBuilderInternal.sharedInstance enterContentZone:tags];
}
- (void)exitContentZone
{
    CLY_LOG_I(@"%s exiting the content zone", __FUNCTION__);
    [CountlyContentBuilderInternal.sharedInstance exitContentZone];
}
- (void)refreshContentZone
{
    CLY_LOG_I(@"%s refreshing the content zone", __FUNCTION__);
    [CountlyContentBuilderInternal.sharedInstance refreshContentZone];

}
- (void)changeContent:(NSArray<NSString *> *)tags
{
    CLY_LOG_I(@"%s changing the content zone tags, tags: [%@], tagCount: [%lu]", __FUNCTION__, tags, (unsigned long)tags.count);
    [CountlyContentBuilder.sharedInstance changeContent:tags];
}

- (void)previewContent:(NSString *)contentId
{
    CLY_LOG_I(@"%s previewing a content, contentId: [%@]", __FUNCTION__, contentId);
    if (!contentId || contentId.length == 0)
    {
        CLY_LOG_W(@"%s contentId is null or empty, skipping", __FUNCTION__);
        return;
    }

    [CountlyContentBuilderInternal.sharedInstance previewContent:contentId];
}

#endif
@end
