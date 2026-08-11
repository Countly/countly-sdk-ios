//  CountlyContentConfig.m
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import "CountlyCommon.h"

@interface CountlyContentConfig ()
#if (TARGET_OS_IOS || TARGET_OS_VISION)
@property (nonatomic) ContentCallback contentCallback;
@property (nonatomic) NSUInteger zoneTimerInterval;
@property (nonatomic) WebViewDisplayOption webViewDisplayOption;
@property (nonatomic) BOOL contentReloadOnStallEnabled;
@property (nonatomic) NSUInteger contentReloadOnStallTimeoutMs;
@property (nonatomic) BOOL zoomDisabled;
@property (nonatomic) BOOL rotationDisabled;
@property (nonatomic, copy) ContentURLHandler contentURLHandler;
#endif
@end

@implementation CountlyContentConfig

- (instancetype)init
{
    if (self = [super init])
    {
#if (TARGET_OS_IOS || TARGET_OS_VISION)
        _contentReloadOnStallTimeoutMs = 1000; // default 1 second
#endif
    }

    return self;
}

#if (TARGET_OS_IOS || TARGET_OS_VISION)
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

- (void)enableContentReloadOnStall
{
    _contentReloadOnStallEnabled = YES;
}

- (BOOL)getEnableContentReloadOnStall
{
    return _contentReloadOnStallEnabled;
}

- (void)setContentReloadOnStallTimeout:(NSUInteger)milliseconds
{
    _contentReloadOnStallTimeoutMs = milliseconds;
}

- (NSUInteger)getContentReloadOnStallTimeout
{
    return _contentReloadOnStallTimeoutMs;
}

- (void)disableZoom
{
    _zoomDisabled = YES;
}

- (BOOL)getDisableZoom
{
    return _zoomDisabled;
}

- (void)disableRotation
{
    _rotationDisabled = YES;
}

- (BOOL)getDisableRotation
{
    return _rotationDisabled;
}

- (void)setContentURLHandler:(ContentURLHandler)handler
{
    _contentURLHandler = handler;
}

- (ContentURLHandler)getContentURLHandler
{
    return _contentURLHandler;
}
#endif

@end
