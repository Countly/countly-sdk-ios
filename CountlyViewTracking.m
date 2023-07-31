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
    [CountlyViewTrackingInternal.sharedInstance setGlobalViewSegmentation:segmentation];
}

- (void)updateGlobalViewSegmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, segmentation);
    [CountlyViewTrackingInternal.sharedInstance updateGlobalViewSegmentation:segmentation];
}
- (NSString *)startView:(NSString *)viewName
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, viewName);
    
    return [CountlyViewTrackingInternal.sharedInstance startView:viewName segmentation:nil];
}
- (NSString *)startView:(NSString *)viewName segmentation:(NSDictionary *)segmentation;
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, viewName, segmentation);
    return [CountlyViewTrackingInternal.sharedInstance startView:viewName segmentation:segmentation];
}

- (void)stopViewWithName:(NSString *)viewName
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, viewName);
    [CountlyViewTrackingInternal.sharedInstance stopViewWithName:viewName segmentation:nil];
}
- (void)stopViewWithName:(NSString *)viewName segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, viewName, segmentation);
    [CountlyViewTrackingInternal.sharedInstance stopViewWithName:viewName segmentation:segmentation];
}

- (void)stopViewWithID:(NSString *)viewID
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, viewID);
    [CountlyViewTrackingInternal.sharedInstance stopViewWithID:viewID segmentation:nil];
}
- (void)stopViewWithID:(NSString *)viewID segmentation:(NSDictionary *)segmentation
{
    CLY_LOG_I(@"%s %@ %@", __FUNCTION__, viewID, segmentation);
    [CountlyViewTrackingInternal.sharedInstance stopViewWithID:viewID segmentation:segmentation];
}

- (void)pauseViewWithID:(NSString *)viewID
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, viewID);
    [CountlyViewTrackingInternal.sharedInstance pauseViewWithID:viewID];
}
- (void)resumeViewWithID:(NSString *)viewID
{
    CLY_LOG_I(@"%s %@", __FUNCTION__, viewID);
    [CountlyViewTrackingInternal.sharedInstance resumeViewWithID:viewID];
}

@end
