//  CountlyContentConfig.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface CountlyContentConfig ()
#if (TARGET_OS_IOS)
@property (nonatomic) ContentCallback contentCallback;
@property (nonatomic) NSUInteger zoneTimerInterval;
@property (nonatomic) WebViewDisplayOption webViewDisplayOption;
#endif
@end

@implementation CountlyContentConfig

- (instancetype)init
{
    if (self = [super init])
    {
    }
    
    return self;
}

#if (TARGET_OS_IOS)
-(void)setGlobalContentCallback:(ContentCallback) callback
{
    _contentCallback = callback;
}

- (ContentCallback) getGlobalContentCallback
{
    return _contentCallback;
}


-(void)setZoneTimerInterval:(NSUInteger)zoneTimerIntervalSeconds
{
    if (zoneTimerIntervalSeconds > 15) {
        _zoneTimerInterval = zoneTimerIntervalSeconds;
    }
}

- (NSUInteger) getZoneTimerInterval
{
    return _zoneTimerInterval;
}

- (void)setWebviewDisplayOption:(WebViewDisplayOption)webViewDisplayOption
{
    _webViewDisplayOption = webViewDisplayOption;
}

- (WebViewDisplayOption)getWebViewDisplayOption;
{
    return _webViewDisplayOption;
}
#endif

@end
