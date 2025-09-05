// CountlyConfig.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import "CountlyRCData.h"
#import "CountlyAPMConfig.h"
#import "CountlyCrashesConfig.h"
#import "CountlySDKLimitsConfig.h"
#import "CountlyExperimentalConfig.h"
#import "CountlyContentConfig.h"

#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_TV )
#import <UIKit/UIKit.h>
#endif


NS_ASSUME_NONNULL_BEGIN

typedef enum : NSUInteger
{
    WIDGET_APPEARED,
    WIDGET_CLOSED,
} WidgetState;

typedef void (^WidgetCallback)(WidgetState widgetState);

//NOTE: Countly features
typedef NSString* CLYFeature NS_EXTENSIBLE_STRING_ENUM;
#if (TARGET_OS_IOS || TARGET_OS_VISION )
#ifndef COUNTLY_EXCLUDE_PUSHNOTIFICATIONS
extern CLYFeature const CLYPushNotifications;
#endif
extern CLYFeature const CLYCrashReporting;
extern CLYFeature const CLYAutoViewTracking DEPRECATED_MSG_ATTRIBUTE("Use 'config.enableAutomaticViewTracking' instead");
#elif (TARGET_OS_WATCH)
extern CLYFeature const CLYCrashReporting;
#elif (TARGET_OS_TV)
extern CLYFeature const CLYCrashReporting;
extern CLYFeature const CLYAutoViewTracking  DEPRECATED_MSG_ATTRIBUTE("Use 'config.enableAutomaticViewTracking' instead");
#elif (TARGET_OS_OSX)
#ifndef COUNTLY_EXCLUDE_PUSHNOTIFICATIONS
extern CLYFeature const CLYPushNotifications;
#endif
extern CLYFeature const CLYCrashReporting;
#endif


//NOTE: Device ID options
/**
 * Can be used as device ID to switch back to default device ID, if a custom device ID is set before.
 * @discussion It can be used as @c deviceID on initial configuration, or passed as an argument for @c deviceID parameter on @c setNewDeviceID:onServer: method.
 * @discussion On iOS and tvOS, default device ID is Identifier For Vendor (IDFV).
 * @discussion On watchOS and macOS, default device ID is a persistently stored random NSUUID string.
 */
extern NSString* const CLYDefaultDeviceID;

/**
 * Use this as device ID for keeping all requests on hold until the real device ID is set later.
 * @discussion It can be used as @c deviceID on initial configuration, or passed as an argument for @c deviceID parameter on @c setNewDeviceID:onServer: method.
 * @discussion As long as device ID is @c CLYTemporaryDeviceID, all requests will be on hold, but they will be persistently stored.
 * @discussion Later when the real device ID is set using @c setNewDeviceID:onServer: method, all requests kept on hold so far will start with the real device ID.
 * @discussion When in @c CLYTemporaryDeviceID mode, method calls for presenting feedback widgets and updating remote config will be ignored.
 */
extern NSString* const CLYTemporaryDeviceID;

//NOTE: Device ID Types
typedef NSString* CLYDeviceIDType NS_EXTENSIBLE_STRING_ENUM;
extern CLYDeviceIDType const CLYDeviceIDTypeCustom;
extern CLYDeviceIDType const CLYDeviceIDTypeTemporary;
extern CLYDeviceIDType const CLYDeviceIDTypeIDFV;
extern CLYDeviceIDType const CLYDeviceIDTypeNSUUID;

//NOTE: Available consents
typedef NSString* CLYConsent NS_EXTENSIBLE_STRING_ENUM;
extern CLYConsent const CLYConsentSessions;
extern CLYConsent const CLYConsentEvents;
extern CLYConsent const CLYConsentUserDetails;
extern CLYConsent const CLYConsentCrashReporting;
extern CLYConsent const CLYConsentPushNotifications;
extern CLYConsent const CLYConsentLocation;
extern CLYConsent const CLYConsentViewTracking;
extern CLYConsent const CLYConsentAttribution;
extern CLYConsent const CLYConsentPerformanceMonitoring;
extern CLYConsent const CLYConsentFeedback;
extern CLYConsent const CLYConsentRemoteConfig;
extern CLYConsent const CLYConsentContent;

//NOTE: Push Notification Test Modes
typedef NSString* CLYPushTestMode NS_EXTENSIBLE_STRING_ENUM;
extern CLYPushTestMode const CLYPushTestModeDevelopment;
extern CLYPushTestMode const CLYPushTestModeTestFlightOrAdHoc;

//NOTE: Default metrics
typedef NSString* CLYMetricKey NS_EXTENSIBLE_STRING_ENUM;
extern CLYMetricKey const CLYMetricKeyDevice;
extern CLYMetricKey const CLYMetricKeyDeviceType;
extern CLYMetricKey const CLYMetricKeyOS;
extern CLYMetricKey const CLYMetricKeyOSVersion;
extern CLYMetricKey const CLYMetricKeyAppVersion;
extern CLYMetricKey const CLYMetricKeyCarrier;
extern CLYMetricKey const CLYMetricKeyResolution;
extern CLYMetricKey const CLYMetricKeyDensity;
extern CLYMetricKey const CLYMetricKeyLocale;
extern CLYMetricKey const CLYMetricKeyHasWatch;
extern CLYMetricKey const CLYMetricKeyInstalledWatchApp;

extern NSString* const kCountlyAppVersionKey;

//NOTE: Attribution keys
typedef NSString* CLYAttributionKey NS_EXTENSIBLE_STRING_ENUM;
extern CLYAttributionKey const CLYAttributionKeyIDFA;
extern CLYAttributionKey const CLYAttributionKeyADID;

//NOTE: Response values of request
typedef NSString* CLYRequestResult NS_EXTENSIBLE_STRING_ENUM;
extern CLYRequestResult const CLYResponseNetworkIssue;
extern CLYRequestResult const CLYResponseSuccess;
extern CLYRequestResult const CLYResponseError;

typedef void (^RCVariantCallback)(CLYRequestResult response, NSError *_Nullable error);

typedef void (^RCDownloadCallback)(CLYRequestResult response, NSError *_Nullable error, BOOL fullValueUpdate, NSDictionary<NSString *, CountlyRCData *>* downloadedValues);


//NOTE: Internal log levels
typedef enum : NSUInteger
{
    CLYInternalLogLevelNone,
    CLYInternalLogLevelError,
    CLYInternalLogLevelWarning,
    CLYInternalLogLevelInfo,
    CLYInternalLogLevelDebug,
    CLYInternalLogLevelVerbose
} CLYInternalLogLevel;


@protocol CountlyLoggerDelegate<NSObject>
- (void)internalLog:(NSString *)log withLevel:(CLYInternalLogLevel)level;
@end


@protocol CountlyAutoViewTrackingName
@optional
- (NSString *)countlyAutoViewTrackingName;
@end




@interface CountlyConfig : NSObject

/**
 * County Server's URL without the slash at the end.
 * @discussion e.g. @c https://example.com
 * @discussion Host needs to be a non-zero length string, otherwise an exception is thrown.
 */
@property (nonatomic, copy) NSString* host;

/**
 * Application's App Key found on Countly Server's "Management > Applications" section.
 * @discussion Using API Key or App ID will not work.
 * @discussion App key needs to be a non-zero length string, otherwise an exception is thrown.
 */
@property (nonatomic, copy) NSString* appKey;

#pragma mark -

/**
 * For enabling SDK debugging mode which prints internal logs.
 * @discussion If set, SDK will print internal logs to console for debugging. Internal logging works only for Development environment where @c DEBUG flag is set in Build Settings.
 */
@property (nonatomic) BOOL enableDebug;

/**
 * For ignoring all SSL trust checks by setting server trust as exception.
 * @discussion Can be used for self-signed certificates.
 * @discussion Works only for Development environment where @c DEBUG flag is set in Build Settings.
 */
@property (nonatomic) BOOL shouldIgnoreTrustCheck;

/**
 * For receiving SDK's internal logs even in production builds.
 * @discussion If set, SDK will forward its internal logs to this delegate object regardless of @c enableDebug initial config value.
 * @discussion @c internalLog:withLevel: method declared as @c required in @c CountlyLoggerDelegate protocol will be called with log @c NSString.
 */
@property (nonatomic, weak) id <CountlyLoggerDelegate> loggerDelegate;

/**
 * For deciding which level SDK's internal logs should be printed at.
 * @discussion Default value is @c CLYInternalLogLevelDebug.
 */
@property (nonatomic) CLYInternalLogLevel internalLogLevel;

#pragma mark -

/**
 * For specifying which features Countly will start with.
 * @discussion Available features for each platform:
 * @discussion @b iOS:
 * @discussion @c CLYPushNotifications for push notifications
 * @discussion @c CLYCrashReporting for crash reporting
 * @discussion @c CLYAutoViewTracking for auto view tracking
 * @discussion @b watchOS:
 * @discussion @c CLYCrashReporting for crash reporting
 * @discussion @b tvOS:
 * @discussion @c CLYCrashReporting for crash reporting
 * @discussion @c CLYAutoViewTracking for auto view tracking
 * @discussion @b macOS:
 * @discussion @c CLYPushNotifications for push notifications
 * @discussion @c CLYCrashReporting for crash reporting
 */
@property (nonatomic, copy) NSArray<CLYFeature>* features;

#pragma mark -

/**
 * For overriding default metrics (or adding extra ones) sent with @c begin_session requests.
 * @discussion Custom metrics should be an @c NSDictionary, with keys and values are both @c NSString 's only.
 * @discussion For overriding default metrics, keys should be @c CLYMetricKey 's.
 */
@property (nonatomic, copy) NSDictionary<NSString *, NSString *>* customMetrics;

#pragma mark -

#if (TARGET_OS_IOS || TARGET_OS_VISION || TARGET_OS_TV)
/**
 * For enabling automatic view tacking.
 * @discussion If set, views will automatically track.
 */
@property (nonatomic) BOOL enableAutomaticViewTracking;

/**
 * Automatic view exclusion list .
 * @discussion These views will exclude from automatic tracking.
 */
@property (nonatomic, copy) NSArray* automaticViewTrackingExclusionList;
#endif
/**
 * Global view segmentation.
 * @discussion If set, It will send with every view.
 */

@property (nonatomic, copy) NSDictionary* globalViewSegmentation;


#pragma mark -

/**
 * For limiting features based on user consent.
 * @discussion If set, SDK will wait for explicit consent to be given for features to work.
 */
@property (nonatomic) BOOL requiresConsent;

/**
 * For granting consents to features and starting them.
 * @discussion This should be an array of feature names to give consent to.
 * @discussion Just like in @c giveConsentForFeatures: method.
 */
@property (nonatomic, copy) NSArray<CLYConsent>* consents;

/**
 * For giving all consents during init.
 * @discussion If set, it will give all feature consents.
 */
@property (nonatomic) BOOL enableAllConsents;

#pragma mark -

/**
 * For specifying which test mode Countly Server should use for sending push notifications.
 * @discussion There are 2 test modes:
 * @discussion - @c CLYPushTestModeDevelopment: For development/debug builds signed with a development provisioning profile. Countly Server will send push notifications to Sandbox APNs.
 * @discussion - @c CLYPushTestModeTestFlightOrAdHoc: For TestFlight or AdHoc builds signed with a distribution provisioning profile. Countly Server will send push notifications to Production APNs.
 * @discussion If set, Test Users mark should be selected on Create Push Notification screen of Countly Server to send push notifications.
 * @discussion If not set (or set to @c nil ), Countly Server will use Production APNs by default.
 */
@property (nonatomic, copy) CLYPushTestMode _Nullable pushTestMode;

/**
 * For sending push tokens to Countly Server even for users who have not granted permission to display notifications.
 * @discussion Push tokens from users who have not granted permission to display notifications, can be used to send silent notifications. But there will be no notification UI for users to interact. This may cause incorrect push notification interaction stats.
 */
@property (nonatomic) BOOL sendPushTokenAlways;

/**
 * For disabling automatically showing of message alerts by @c CLYPushNotifications feature.
 * @discussion If set, push notifications that contain a message or a URL will not show alerts automatically.
 * @discussion Push Action event needs to be recorded manually, as well as displaying the message.
 */
@property (nonatomic) BOOL doNotShowAlertForNotifications;

/**
 * For handling push notifications for macOS apps on launch.
 * @discussion Needs to be set in @c applicationDidFinishLaunching: method of macOS apps that use @c CLYPushNotifications feature, in order to handle app launches by push notification click.
 */
@property (nonatomic, copy) NSNotification* launchNotification;

#pragma mark -

/**
 * Location latitude and longitude can be specified as @c CLLocationCoordinate2D struct to be used for geo-location based push notifications and advanced segmentation.
 * @discussion By default, Countly Server uses a geo-ip database for acquiring user's location. If the app uses Core Location services and granted permission, a location with better accuracy can be provided using this property.
 * @discussion It will be sent with @c begin_session requests only.
 */
@property (nonatomic) CLLocationCoordinate2D location;

/**
 * City name can be specified as string to be used for geo-location based push notifications and advanced segmentation.
 * @discussion By default, Countly Server uses a geo-ip database for acquiring user's location. If the app has information about user's city, it can be provided using this property.
 * @discussion It will be sent with @c begin_session requests only.
 */
@property (nonatomic, copy) NSString* city;

/**
 * ISO country code can be specified in ISO 3166-1 alpha-2 format to be used for geo-location based push notifications and advanced segmentation.
 * @discussion By default, Countly Server uses a geo-ip database for acquiring user's location. If the app has information about user's country, it can be provided using this property.
 * @discussion It will be sent with @c begin_session requests only.
 */
@property (nonatomic, copy) NSString* ISOCountryCode;

/**
 * IP address can be specified as string to be used for geo-location based push notifications and advanced segmentation.
 * @discussion By default, Countly Server uses a geo-ip database for acquiring user's location, and deduces the IP address from the connection. If the app needs to explicitly specify the IP address due to network requirements, it can be provided using this property.
 * @discussion It will be sent with @c begin_session requests only.
 */
@property (nonatomic, copy) NSString* IP;

/**
 * For disabling location tracking by clearing all existing location info..
 * @discussion If set, Location tracking is disabled
 * Once disabled, geo-location based push notifications can be enabled again by calling @c recordLocation: method.
*/
@property (nonatomic) BOOL disableLocation;

#pragma mark -

/**
 * @discussion Custom device ID.
 * @discussion If not set, default device ID will be used.
 * @discussion On iOS and tvOS, default device ID is Identifier For Vendor (IDFV).
 * @discussion On watchOS and macOS, default device ID is a persistently stored random NSUUID string.
 * @discussion Once set, device ID will be stored persistently and will not change even if another device ID is set on next start, unless @c resetStoredDeviceID flag is set.
 */
@property (nonatomic, copy) NSString* deviceID;

/**
 * This menthod will enable temporary device ID mode
 * @discussion All requests will be on hold, but they will be persistently stored.
 * @discussion When in temporary device ID mode, method calls for presenting feedback widgets and updating remote config will be ignored.
 */
- (void)enableTemporaryDeviceIDMode;

/**
 * For resetting persistently stored device ID on SDK start.
 * @discussion If set, persistently stored device ID will be reset and new device ID specified on @c deviceID property of @c CountlyConfig object will be stored and used.
 * @discussion It is meant to be used for debugging purposes only while developing.
 */
@property (nonatomic) BOOL resetStoredDeviceID;

#pragma mark -

/**
 * Update session period is used for updating sessions and sending queued events to Countly Server periodically.
 * @discussion If not set, it will be 60 seconds for @c iOS, @c tvOS & @c macOS, and 20 seconds for @c watchOS by default.
 */
@property (nonatomic) NSTimeInterval updateSessionPeriod;

/**
 * Event send threshold is used for sending queued events to Countly Server when number of recorded events reaches to it, without waiting for next update session defined by @c updateSessionPeriod.
 * @discussion If not set, it will be 100 by default.
 */
@property (nonatomic) NSUInteger eventSendThreshold;

/**
 * Stored requests limit is used for limiting the number of request to be stored on the device, in case Countly Server is not reachable.
 * @discussion In case Countly Server is down or unreachable for a very long time, queued request may reach excessive numbers, and this may cause problems with requests being sent to Countly Server and being stored on the device. To prevent this, SDK will only store requests up to @c storedRequestsLimit.
 * @discussion If number of stored requests reaches @c storedRequestsLimit, SDK will start to drop oldest request while appending the newest one.
 * @discussion If not set, it will be 1000 by default.
 */
@property (nonatomic) NSUInteger storedRequestsLimit;

/**
 * Age of a request is the difference between the current time and the creation time of the request. Requests will be removed from the queue if their age exceeds the request drop age set here.
 * @discussion If not set, it will not effect the requests.
 */
@property (nonatomic) NSUInteger requestDropAgeHours;

/**
 * Limit for the length of all string keys.
 * @discussion It affects:
 * @discussion - event names
 * @discussion - view names
 * @discussion - APM network trace names
 * @discussion - APM custom trace names
 * @discussion - APM custom trace metric keys
 * @discussion - segmentation keys
 * @discussion - custom metric keys
 * @discussion - custom user property keys
 * @discussion Keys longer than this limit will be truncated.
 * @discussion If not set, it will be 128 chars by default.
 */
@property(nonatomic) NSUInteger maxKeyLength DEPRECATED_MSG_ATTRIBUTE("Use 'sdkInternalLimits' CountlySDKLimitsConfig object instead");

/**
 * Limit for the length of values in all key-value pairs.
 * @discussion It affects:
 * @discussion - segmentation values
 * @discussion - APM custom trace metric values
 * @discussion - custom crash logs
 * @discussion - custom metric values
 * @discussion - custom user property values
 * @discussion Values longer than this limit will be truncated.
 * @discussion If not set, it will be 256 chars by default.
 */
@property(nonatomic) NSUInteger maxValueLength DEPRECATED_MSG_ATTRIBUTE("Use 'sdkInternalLimits' CountlySDKLimitsConfig object instead");

/**
 * Limit for the number of key-value pairs in segmentations.
 * @discussion If there are more key-value pairs than this limit, some of them will be removed.
 * @discussion As obviously there is no order among the keys of an NSDictionary, it is not defined which ones will be removed.
 * @discussion If not set, it will be 30 by default.
 */
@property(nonatomic) NSUInteger maxSegmentationValues DEPRECATED_MSG_ATTRIBUTE("Use 'sdkInternalLimits' CountlySDKLimitsConfig object instead");

/**
 * Variable to access sdkInternalLimits configurations.
 * @discussion SDK internal limits configurations for developer to interact with SDK.
 */
- (CountlySDKLimitsConfig *)sdkInternalLimits;

/**
 * For sending all requests using HTTP POST method.
 * @discussion If set, all requests will be sent using HTTP POST method. Otherwise; only the requests with a file upload or data size more than 2048 bytes will be sent using HTTP POST method.
 */
@property (nonatomic) BOOL alwaysUsePOST;

#pragma mark -

/**
 * For handling sessions manually.
 * @discussion If set, SDK does not handle beginning, updating and ending sessions automatically. Methods @c beginSession, @c updateSession and @c endSession need to be called manually.
 */
@property (nonatomic) BOOL manualSessionHandling;

/**
 * For handling start and stop sessions manually.
 * @discussion If set, SDK does not handle beginning and ending sessions automatically. Methods @c beginSession and @c endSession need to be called manually.
 * update session will handle auto automatically, no need to call @c updateSession when hybrid mode is enabled.
 * NOTE: It will work only when manualSessionHandling is enabled.
 */
@property (nonatomic) BOOL enableManualSessionControlHybridMode;

#pragma mark -

/**
 * For specifying attribution ID (IDFA).
 * @discussion If set, this attribution ID will be sent with all @c begin_session requests.
 */
@property (nonatomic, copy) NSString* attributionID DEPRECATED_MSG_ATTRIBUTE("Use 'campaignType' and 'campaignData' for direct attribution or  'indirectAttribution' for indirect attribution");

/**
 * For specifying direct attribution campaign type.
 * @discussion Currently supported campaign types are "countly" and "_special_test".
 */
@property (nonatomic, copy) NSString* campaignType;

/**
 * For specifying direct attribution campaign data.
 * @discussion Campaign data has to be in `{"cid":"CAMPAIGN_ID", "cuid":"CAMPAIGN_USER_ID"}` format.
 */
@property (nonatomic, copy) NSString* campaignData;

/**
 * For specifying indirect attribution with given key-value pairs.
 * @discussion Keys could be a predefined CLYAttributionKey or any non-zero length valid string.
 */
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> * indirectAttribution;

#pragma mark -

/**
 * For using custom crash segmentation with @c CLYCrashReporting feature.
 * @discussion Crash segmentation should be an @c NSDictionary, with keys and values are both @c NSString's only.
 * @discussion Custom objects in crash segmentation will cause crash report not to be sent to Countly Server.
 * @discussion Nested values in crash segmentation will be ignored by Countly Server.
 */
@property (nonatomic, copy) NSDictionary<NSString *, NSString *>* crashSegmentation;

/**
 * Crash log limit is used for limiting the number of crash logs to be stored on the device.
 * @discussion If number of stored crash logs reaches @c crashLogLimit, SDK will start to drop oldest crash log while appending the newest one.
 * @discussion If not set, it will be 100 by default.
 * @discussion If @c shouldUsePLCrashReporter flag is set on initial config, this limit will not be applied.
 */
@property (nonatomic) NSUInteger crashLogLimit DEPRECATED_MSG_ATTRIBUTE("Use 'sdkInternalLimits' CountlySDKLimitsConfig object instead");

/**
 * Regular expression used for filtering crash reports and preventing them from being sent to Countly Server.
 * @discussion If a crash's name, description or any line of stack trace matches given regular expression, it will not be sent to Countly Server.
 */
@property (nonatomic, copy) NSRegularExpression* crashFilter;

/**
 * For using PLCrashReporter instead of default crash handling mechanism.
 * @discussion If set, SDK will be using PLCrashReporter (1.x.x series) dependency for creating crash reports.
 * @discussion PLCrashReporter option is available only for iOS apps.
 * @discussion For more information about PLCrashReporter please see: https://github.com/microsoft/plcrashreporter
 */
@property (nonatomic) BOOL shouldUsePLCrashReporter;

/**
 * For using Mach type signal handler with PLCrashReporter.
 * @discussion PLCrashReporter has two different signal handling implementations with different traits:
 * @discussion 1) BSD: PLCrashReporterSignalHandlerTypeBSD
 * @discussion 2) Mach: PLCrashReporterSignalHandlerTypeMach
 * @discussion For more information about PLCrashReporter please see: https://github.com/microsoft/plcrashreporter
 * @discussion By default, BSD type will be used.
 */
@property (nonatomic) BOOL shouldUseMachSignalHandler;

/**
 * Callback block to be executed when the app is launched again following a crash which is detected by PLCrashReporter on the previous session.
 * @discussion It has an @c NSDictionary parameter that represents crash report object.
 * @discussion If @c shouldUsePLCrashReporter flag is not set on initial config, it will never be executed.
 */
@property (nonatomic, copy) void (^crashOccuredOnPreviousSessionCallback)(NSDictionary * crashReport);

/**
 * Callback block to decide whether the crash report detected by PLCrashReporter should be sent to Countly Server or not.
 * @discussion If not set, crash report will be sent to Countly Server by default.
 * @discussion If set, crash report will be sent to Countly Server only if `YES` is returned.
 * @discussion It has an @c NSDictionary parameter that represents crash report object.
 * @discussion If @c shouldUsePLCrashReporter flag is not set on initial config, it will never be executed.
 */
@property (nonatomic, copy) BOOL (^shouldSendCrashReportCallback)(NSDictionary * crashReport);

- (CountlyCrashesConfig *) crashes;

#pragma mark -

/**
 * For specifying bundled certificates to be used for public key pinning.
 * @discussion Certificates have to be DER encoded with one of the following extensions: @c .der @c .cer or @c .crt
 * @discussion e.g. @c myserver.com.cer
 */
@property (nonatomic, copy) NSArray* pinnedCertificates;

/**
 * Salt value to be used for parameter tampering protection.
 * @discussion If set, every request sent to Countly Server will have @c checksum256 value generated by SHA256(request + secretSalt)
 */
@property (nonatomic, copy) NSString* secretSalt;

/**
 * Custom URL session configuration to be used with all requests.
 * @discussion If not set, @c NSURLSessionConfiguration's @c defaultSessionConfiguration will be used by default.
 */
@property (nonatomic, copy) NSURLSessionConfiguration* URLSessionConfiguration;

#pragma mark -

/**
 * For customizing star-rating dialog message.
 * @discussion If not set, it will be displayed in English: "How would you rate the app?" or corresponding supported (@c en, @c tr, @c jp, @c zh, @c ru, @c lv, @c cz, @c bn) localized version.
 */
@property (nonatomic, copy) NSString* starRatingMessage;

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
 * @discussion Completion block has a single NSInteger parameter that indicates 1 to 5 star-rating given by user. If user dismissed dialog without giving a rating, this value will be 0 and it will not be reported to Countly Server.
 */
@property (nonatomic, copy) void (^starRatingCompletion)(NSInteger rating);

#pragma mark -

/**
 * For enabling automatic fetching of remote config values.
 * @discussion If set, Remote Config values specified on Countly Server will be fetched on beginning of sessions.
 */
@property (nonatomic) BOOL enableRemoteConfig DEPRECATED_MSG_ATTRIBUTE("Use 'enableRemoteConfigAutomaticTriggers' instead");

/**
 * Completion block to be executed after remote config is fetched from Countly Server, on start or device ID change.
 * @discussion This completion block can be used to detect updating of remote config values is completed, either with success or failure.
 * @discussion It has an @c NSError parameter that will be either @ nil or an @c NSError object, depending of request result.
 * @discussion If there is no error, it will be executed with an @c nil, which means latest remote config values are ready to be used.
 * @discussion If Countly Server is not reachable or if there is another error, it will be executed with an @c NSError indicating the problem.
 * @discussion If @c enableRemoteConfig flag is not set on initial config, it will never be executed.
 */
@property (nonatomic, copy) void (^remoteConfigCompletionHandler)(NSError * _Nullable error) DEPRECATED_MSG_ATTRIBUTE("Use 'remoteConfigRegisterGlobalCallback' instead");

/**
 * For enabling automatic fetching of remote config values.
 * @discussion If set, Remote Config values specified on Countly Server will be fetched on beginning of sessions, exit temporary device id and changing device id onserver.
 */
@property (nonatomic) BOOL enableRemoteConfigAutomaticTriggers;

/**
 * For enabling remote config caching.
 * @discussion If set, Remote Config values of previous device id will be cache.
 */
@property (nonatomic) BOOL enableRemoteConfigValueCaching;


/**
 * Register global completion blocks to be executed after remote config is fetched from Countly Server.
 */
- (void)remoteConfigRegisterGlobalCallback:(RCDownloadCallback) callback;

/**
 * Get a list of registered global completion blocks.
 */
- (NSMutableArray<RCDownloadCallback> *) getRemoteConfigGlobalCallbacks;

/**
 * For enabling automatic AB enrolling on download.
 * @discussion If set, user will will automatically be enrolled in relevant AB tests when downloading RC values.
 */
@property (nonatomic) BOOL enrollABOnRCDownload;


#pragma mark -

/**
 * For enabling automatic performance monitoring.
 * @discussion If set, Performance Monitoring feature will be started automatically on SDK start.
 */
@property (nonatomic) BOOL enablePerformanceMonitoring DEPRECATED_MSG_ATTRIBUTE("Use 'apm' CountlyAPMConfig object instead");

/**
 * Variable to access apm configurations.
 * @discussion APM configurations for developer to interact with SDK.
 */
- (CountlyAPMConfig *) apm;

#pragma mark -

/**
 * For enabling automatic user interface orientation tracking.
 * @discussion If set, user interface orientation tracking feature will be enabled.
 * @discussion An event will be sent whenever user interface orientation changes.
 * @discussion Orientation event will not be sent if consent for @c CLYConsentUserDetails is not given,
 * while @c requiresConsent flag is set on initial configuration.
 * @discussion Automatic user interface orientation tracking is enabled by default.
 * @discussion For disabling it, please set this flag to @c NO.
 */
@property (nonatomic) BOOL enableOrientationTracking;

/**
 * This is an experimental feature and it can have breaking changes
 * For enabling fetching and application of server config values.
 * @discussion If set, Server Config values from Countly Server will be fetched at the beginning of a session.
 */
@property(nonatomic) BOOL enableServerConfiguration DEPRECATED_MSG_ATTRIBUTE("Will do nothing");
;

/**
 * Set the server configuration to be set while initializing the SDK
 */
@property(nonatomic, copy) NSString *sdkBehaviorSettings;

/**
 * Disable the server configuration updates to the server
 */
@property(nonatomic) BOOL disableSDKBehaviorSettingsUpdates;

/**
 * Will disable back off mechanism
 */
@property (nonatomic) BOOL disableBackoffMechanism;

#if (TARGET_OS_IOS)
/**
 * Variable to access content configurations.
 * @discussion Content configurations for developer to interact with SDK.
 */
- (CountlyContentConfig *) content;
#endif

/**
 * This is an experimental feature and it can have breaking changes
 * Variable to access experimental configurations.
 * @discussion Experimental configurations for developer to interact with SDK.
 */
- (CountlyExperimentalConfig *) experimental;
NS_ASSUME_NONNULL_END

@end
