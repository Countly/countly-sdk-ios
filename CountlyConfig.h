// CountlyConfig.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

//NOTE: Countly features
#if TARGET_OS_IOS
extern NSString* const CLYPushNotifications;
    extern NSString* const CLYMessaging DEPRECATED_MSG_ATTRIBUTE("Use CLYPushNotifications instead!");
extern NSString* const CLYCrashReporting;
extern NSString* const CLYAutoViewTracking;
#elif TARGET_OS_TV
extern NSString* const CLYAutoViewTracking;
#endif
//NOTE: Disable APM feature until server completely supports it
// extern NSString* const CLYAPM;


//NOTE: Device ID options
#if TARGET_OS_IOS
extern NSString* const CLYIDFV;
extern NSString* const CLYIDFA DEPRECATED_MSG_ATTRIBUTE("Use CLYIDFV instead!");
extern NSString* const CLYOpenUDID DEPRECATED_MSG_ATTRIBUTE("Use CLYIDFV instead!");
#elif (!(TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_WATCH))
extern NSString* const CLYOpenUDID DEPRECATED_MSG_ATTRIBUTE("Use custom device ID instead!");
#endif

@interface CountlyConfig : NSObject

/**
 * County Server's URL without the slash at the end.
 * @discussion e.g. https://example.com
 */
@property (nonatomic, strong) NSString* host;

/**
 * Application's App Key found on Countly Server's "Management > Applications" section.
 * @discussion Using API Key or App ID will not work.
 */
@property (nonatomic, strong) NSString* appKey;

/**
 * For specifiying which features Countly will start with.
 * @discussion Available features:
 * @discussion @c CLYPushNotifications for push notifications,
 * @discussion @c CLYCrashReporting for crash reporting,
 * @discussion @c CLYAutoViewTracking for auto view tracking and
 * @discussion @c CLYAPM for application performance management.
 */
@property (nonatomic, strong) NSArray* features;

/**
 * For enabling SDK debug mode which prints internal logs.
 * @discussion If set, SDK will print internal logs to console for debugging. Internal logging works only for Development environment where DEBUG flag is set in Build Settings.
 */
@property (nonatomic) BOOL enableDebug;

/**
 * For specifiying application's launch options dictionary.
 * @discussion Previously it was required for @c CLYPushNotifications feature, but not needed anymore. It is just kept for future use.
 */
@property (nonatomic, strong) NSDictionary* launchOptions;

/**
 * For manually marking a device as test device for @c CLYPushNotifications feature. 
 * @discussion Test push notifications can be sent to test devices by selecting "Development & test users only" on "Create Push Notification" section on Countly Server.
 */
@property (nonatomic) BOOL isTestDevice;

/**
 * For sending push tokens to Countly server even for users who have not granted permission to display notifications.
 * @discussion Push tokens from users who have not granted permission to display notifications, can be used to send silent notifications. But there will be no notification UI for users to interact. This may cause incorrect push notification interaction stats.
 */
@property (nonatomic) BOOL sendPushTokenAlways;

/**
 * For disabling automatically showing of message alerts by @c CLYPushNotifications feature.
 * @discussion If set, push notifications that contain a message or a URL visit request will not show alerts automatically. Push Open event will be recorded, but Push Action event needs to be recorded manually, as well as displaying the message manually.
 */
@property (nonatomic) BOOL doNotShowAlertForNotifications;

/**
 * For using custom crash segmentation with @c CLYCrashReporting feature.
 */
@property (nonatomic, strong) NSDictionary* crashSegmentation;

/**
 * @discussion Custom or system generated device ID. If not set, Identifier For Advertising (IDFA) will be used by default.
 * @discussion Available sytem generated device ID options:
 * @discussion @c CLYIDFA (Identifier For Advertising)
 * @discussion @c CLYIDFV (Identifier For Vendor)
 * @discussion @c CLYOpenUDID (OpenUDID)
 * @discussion Once set, device ID will be stored persistently (even after app delete and re-install) and will not be changed even if set another device ID is set on start, unless @c forceDeviceIDInitialization flag is set.
 */
@property (nonatomic, strong) NSString* deviceID;

/**
 * For forcing device ID initialization on start. When it is set, persistenly stored device ID will be reset and new device ID will be re-initialized with @c deviceID property on @c CountlyConfig object.
 */
@property (nonatomic) BOOL forceDeviceIDInitialization;

/**
 * For handling sessions manually.
 * @discussion If set, SDK does not handle beginning, updating and ending sessions automatically. Methods @c beginSession, @c updateSession and @c endSession need to be called manually.
 */
@property (nonatomic) BOOL manualSessionHandling;

/**
 * Update session period is used for updating sessions and sending queued events to server periodically.
 * @discussion If not set, it will be 60 seconds for @c iOS, @c tvOS & @c OSX, and 20 seconds for @c watchOS by default.
 */
@property (nonatomic) NSTimeInterval updateSessionPeriod;

/**
 * Event send threshold is used for sending queued events to server when number of recorded events reaches to it, without waiting for next update session defined by @c updateSessionPeriod. 
 * @discussion If not set, it will be 10 for @c iOS, @c tvOS & @c OSX, and 3 for @c watchOS by default.
 */
@property (nonatomic) NSUInteger eventSendThreshold;

/**
 * Stored requests limit is used to limit number of request to be queued.
 * @discussion In case Countly Server is down or unreachable for a very long time, queued request may reach excessive numbers, and it may cause problems with being delivered to server and being stored on the device. To prevent this, SDK will only store requests up to @c storedRequestsLimit. If number of stored requests reach @c storedRequestsLimit, SDK will start to drop oldest request while inserting the newest one instead.
 * @discussion If not set, it will be 1000 by default.
 */
@property (nonatomic) NSUInteger storedRequestsLimit;

/**
 * For sending all requests using HTTP POST method.
 * @discussion If set, all requests will be sent using HTTP POST method. Otherwise; only the requests with a file upload or data size more than 2048 bytes will be sent using HTTP POST method.
 */
@property (nonatomic) BOOL alwaysUsePOST;

/**
 * Enables automatic handling of Apple Watch related features.
 * @discussion If set, Apple Watch related features like parent device matching, pairing status, and watch app installing status will be handled automatically. Required for using Countly on Apple Watch apps.
 */
@property (nonatomic) BOOL enableAppleWatch;

/**
 * ISO Country Code can be specified in ISO 3166-1 alpha-2 format to be used for advanced segmentation. 
 * @discussion It will be sent with @c begin_session request only.
 */
@property (nonatomic, strong) NSString* ISOCountryCode;

/**
 * City name can be specified as string to be used for advanced segmentation.
 * @discussion It will be sent with @c begin_session request only.
 */
@property (nonatomic, strong) NSString* city;

/**
 * Location latitude and longitude can be specified as CLLocationCoordinate2D struct to be used for advanced segmentation and geo-location based push notifications.
 * @discussion It will be sent with @c begin_session request only.
 */
@property (nonatomic) CLLocationCoordinate2D location;

/**
 * IP address can be specified as string to be used for advanced segmentation and geo-ip based push notifications.
 * @discussion It will be sent with @c begin_session request only.
 */
@property (nonatomic) NSString* IP;

/**
 * For specifying bundled certificates to be used for public key pinning.
 * @discussion Certificates have to be DER encoded with one of the following extensions: .der .cer or .crt
 * @discussion e.g. myserver.com.cer
 */
@property (nonatomic, strong) NSArray* pinnedCertificates;

/**
 * Name of the custom HTTP header field to be sent with every request.
 * @discussion e.g. X-My-Secret-Server-Token
 * @discussion If set, every request sent to Countly server will have this custom HTTP header and its value will be @c customHeaderFieldValue property. If @c customHeaderFieldValue is not set when Countly is started, requests will not start until it is set using @c setCustomHeaderFieldValue: method later.
 */
@property (nonatomic, strong) NSString* customHeaderFieldName;

/**
 * Value of the custom HTTP header field to be sent with every request if @c customHeaderFieldName is set.
 * @discussion If not set while @c customHeaderFieldName is set, requests will not start until it is set using @c setCustomHeaderFieldValue: method later.
 */
@property (nonatomic, strong) NSString* customHeaderFieldValue;

/**
 * Salt value to be used for parameter tampering protection.
 * @discussion If set, every request sent to Countly server will have @c checksum value generated by SHA1(request + secretSalt)
 */
@property (nonatomic, strong) NSString* secretSalt;

/**
 * For customizing star-rating dialog message.
 * @discussion If not set, it will be displayed in English: "How would you rate the app?" or corresponding supported (EN, TR, JP, ZH, RU) localized version.
 */
@property (nonatomic, strong) NSString* starRatingMessage;

/**
 * For displaying star-rating dialog depending on session count, once for each new version of the app.
 * @discussion If set, when total number of sessions reaches @c starRatingSessionCount, an alert view asking for 1 to 5 star-rating will be displayed automatically, once for each new version of the app.
 */
@property (nonatomic) NSUInteger starRatingSessionCount;

/**
 * Disables automatically displaying of star-rating dialog for each new version of the app.
 * @discussion If set, star-rating dialog will be displayed automatically only once for the whole life of the app. It will not be displayed for each new version.
 */
@property (nonatomic) BOOL starRatingDisableAskingForEachAppVersion;

/**
 * Completion block to be executed after star-rating dialog is shown automatically.
 * @discussion Completion block has a single NSInteger parameter that indicates 1 to 5 star-rating given by user. If user dismissed dialog without giving a rating, this value will be 0 and it will not be reported to server.
 */
@property (nonatomic, copy) void (^starRatingCompletion)(NSInteger rating);
@end
