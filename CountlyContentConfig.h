//  CountlyContentConfig.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#if (TARGET_OS_IOS || TARGET_OS_VISION)
typedef enum : NSUInteger
{
    COMPLETED,
    CLOSED,
} ContentStatus;

typedef enum: NSUInteger
{
    IMMERSIVE,
    SAFE_AREA
} WebViewDisplayOption;

typedef void (^ContentCallback)(ContentStatus contentStatus, NSDictionary<NSString *, id>* contentData);

// Handler the host app can provide to take over opening a link tapped in the content web view
// (e.g. to route the app's own deep link to the right screen). Return YES if the app handled
// the URL; return NO to let the SDK open it in the system browser as usual. Called on the main
// thread.
typedef BOOL (^ContentURLHandler)(NSURL *url);
#endif

@interface CountlyContentConfig : NSObject

#if (TARGET_OS_IOS || TARGET_OS_VISION)
/**
 * This is an experimental feature and it can have breaking changes
 * Register global completion blocks to be executed on content.
 */
- (void)setGlobalContentCallback:(ContentCallback) callback;

/**
 * This is an experimental feature and it can have breaking changes
 * Get content callback
 */
- (ContentCallback) getGlobalContentCallback;

/**
 * This is an experimental feature and it can have breaking changes
 * Set the interval for the automatic content update calls
 * @param zoneTimerIntervalSeconds in seconds
 *
 */
-(void)setZoneTimerInterval:(NSUInteger)zoneTimerIntervalSeconds;

/**
 * This is an experimental feature and it can have breaking changes
 * Get zone timer interval
 */
- (NSUInteger) getZoneTimerInterval;

/**
 * To control how content and feedback widgets displayed. Default is IMMERSIVE (full screen contents)
 */
- (void) setWebviewDisplayOption:(WebViewDisplayOption) webViewDisplayOption;

- (WebViewDisplayOption)getWebViewDisplayOption;

/**
 * This is an experimental feature and it can have breaking changes.
 * Enables reloading the content web view when a load stalls (does not appear within ~1
 * second) instead of closing it. A reload reuses the already-warm connection and cached
 * assets, which recovers loads that fail because a server/edge drops the initial burst of
 * parallel resource connections. This is a one-way switch: once enabled it stays enabled.
 * Disabled by default.
 */
- (void)enableContentReloadOnStall;
- (BOOL)getEnableContentReloadOnStall;

/**
 * This is an experimental feature and it can have breaking changes.
 * Sets how long a content load may stall (not appear) before the SDK reloads it, in
 * milliseconds. Only used when reload-on-stall is enabled (see enableContentReloadOnStall).
 * Default is 1000 (1 second). Can be changed at any time before starting the SDK.
 */
- (void)setContentReloadOnStallTimeout:(NSUInteger)milliseconds;
- (NSUInteger)getContentReloadOnStallTimeout;

/**
 * This is an experimental feature and it can have breaking changes.
 * Disables user zoom (pinch and double-tap) in the content web view. The page's own
 * viewport width and initial scale are preserved; only zooming is turned off. This is a
 * one-way switch: once enabled it stays enabled. Disabled by default.
 */
- (void)disableZoom;
- (BOOL)getDisableZoom;

/**
 * This is an experimental feature and it can have breaking changes.
 * Pins displayed content to the portrait layout: it is placed with the portrait dimensions
 * whatever the device orientation is, and is not re-placed when the device is rotated. Content
 * follows the device orientation by default. This is a one-way switch and never applies to
 * feedback widgets.
 */
- (void)disableRotation;
- (BOOL)getDisableRotation;

/**
 * This is an experimental feature and it can have breaking changes.
 * Sets a handler that is called when a link is opened from the content web view (an external
 * link or the content "link" action), letting the host app take over instead of the SDK
 * opening the system browser. This is how an app routes its own deep links (custom scheme or
 * https) to the correct screen. The handler receives the URL and returns YES if it handled it;
 * returning NO (or not setting a handler) makes the SDK open the URL in the system browser as
 * before. Called on the main thread.
 */
- (void)setContentURLHandler:(nullable ContentURLHandler)handler;
- (nullable ContentURLHandler)getContentURLHandler;
#endif

NS_ASSUME_NONNULL_END

@end
