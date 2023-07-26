// CountlyViewTracking.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@implementation CountlyViewTracking

+ (instancetype)sharedInstance
{
    if (!CountlyCommon.sharedInstance.hasStarted)
        return nil;
    
    static CountlyViewTracking* s_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{s_sharedInstance = self.new;});
    return s_sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    
    return self;
}

- (void)setGlobalViewSegmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, segmentation);
}

- (void)updateGlobalViewSegmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, segmentation);
}
- (NSString *)startView:(NSString *)viewName
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, viewName);
    return @"";
}
- (NSString *)startView:(NSString *)viewName segmentation:(NSDictionary *)segmentation;
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, viewName, segmentation);
    return @"";
}

- (void)stopViewWithName:(NSString *)viewName
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, viewName);
}
- (void)stopViewWithName:(NSString *)viewName segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, viewName, segmentation);
}

- (void)stopViewWithID:(NSString *)viewID
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, viewID);
}
- (void)stopViewWithID:(NSString *)viewID segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, viewID, segmentation);
}

- (void)pauseViewWithID:(NSString *)viewID
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, viewID);
}
- (void)resumeViewWithID:(NSString *)viewID
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, viewID);
}

@end
