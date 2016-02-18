// CountlyViewTracking.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface CountlyViewTracking ()
@property(nonatomic, strong) NSString* _Nonnull lastView;
@property(nonatomic, readwrite) NSTimeInterval lastViewStartTime;
@end


@implementation CountlyViewTracking

+(instancetype)sharedInstance
{
    static CountlyViewTracking* s_sharedInstance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^
    {
                  s_sharedInstance = self.new;
    });
    return s_sharedInstance;
}

- (void)reportView:(NSString* _Nonnull)viewName
{
    COUNTLY_LOG(@"Started tracking view: %@", viewName);
    
    [self endView];

    CountlyEvent *event = [CountlyEvent new];
    event.key = @"[CLY]_view";
    
    NSDictionary* segmentation = @{
                                    @"name": viewName,
                                    @"segment": CountlyDeviceInfo.osName,
                                    @"visit": @1,
                                  };
    if(!self.lastView)
    {
        NSMutableDictionary* mutableSegmentation = segmentation.mutableCopy;
        mutableSegmentation[@"start"] = @1;
        segmentation = mutableSegmentation;
    }
    
    event.segmentation = segmentation;
    event.count = 1;
    event.timestamp = NSDate.date.timeIntervalSince1970;
    event.hourOfDay = [CountlyCommon.sharedInstance hourOfDay];
    event.dayOfWeek = [CountlyCommon.sharedInstance dayOfWeek];

    [CountlyPersistency.sharedInstance.recordedEvents addObject:event];
    
    self.lastView = viewName;
    self.lastViewStartTime = NSDate.date.timeIntervalSince1970;
}

- (void)endView
{
    if(self.lastView)
    {
        CountlyEvent *event = [CountlyEvent new];
        event.key = @"[CLY]_view";
        event.segmentation = @{
                                @"name": self.lastView,
                                @"segment": CountlyDeviceInfo.osName,
                              };
        event.count = 1;
        event.timestamp = self.lastViewStartTime;
        event.hourOfDay = [CountlyCommon.sharedInstance hourOfDay];
        event.dayOfWeek = [CountlyCommon.sharedInstance dayOfWeek];
        event.duration = NSDate.date.timeIntervalSince1970 - self.lastViewStartTime;

        [CountlyPersistency.sharedInstance.recordedEvents addObject:event];
    
        COUNTLY_LOG(@"Ended tracking view: %@ with duration %f", self.lastView, event.duration);
    }
}

#if TARGET_OS_IOS
- (void)startAutoViewTracking
{
    self.isAutoViewTrackingEnabled = YES;
    
    Method O_method;
    Method C_method;
    
    O_method = class_getInstanceMethod(UIViewController.class, @selector(viewDidAppear:));
    C_method = class_getInstanceMethod(UIViewController.class, @selector(Countly_viewDidAppear:));
    method_exchangeImplementations(O_method, C_method);
}
#endif
@end


#if TARGET_OS_IOS
@implementation UIViewController (CountlyViewTracking)
- (void)Countly_viewDidAppear:(BOOL)animated
{    
    if(CountlyViewTracking.sharedInstance.isAutoViewTrackingEnabled &&
       ![self isKindOfClass:UINavigationController.class])
    {
        NSString* viewTitle = self.title;
        
        if(!viewTitle)
            viewTitle = NSStringFromClass([self class]);
        
        [CountlyViewTracking.sharedInstance reportView:viewTitle];
    }
    
    [self Countly_viewDidAppear:animated];
}
@end
#endif