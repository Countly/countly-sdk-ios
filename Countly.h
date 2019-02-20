// Countly.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import "CountlyUserDetails.h"
#import "CountlyConfig.h"
#if (TARGET_OS_IOS || TARGET_OS_OSX)
#import <UserNotifications/UserNotifications.h>
#endif

NS_ASSUME_NONNULL_BEGIN

@interface Countly : NSObject

#pragma mark - Core

/**
 * Returns @c Countly singleton to be used throughout the app.
 * @return The shared @c Countly object
 */
+ (instancetype)sharedInstance;

/**
 * Starts Countly with given configuration and begins session.
 * @param config @c CountlyConfig object that defines host, app key, optional features and other settings
 */
- (void)startWithConfig:(CountlyConfig *)config;

/**
 * Sets new device ID to be persistently stored and used in following requests.
 * @param deviceID New device ID
 * @param onServer If set, data on Countly Server will be merged automatically, otherwise device will be counted as a new device
 */
- (void)setNewDeviceID:(NSString * _Nullable)deviceID onServer:(BOOL)onServer;

/**
 * Sets the value of the custom HTTP header field to be sent with every request if @c customHeaderFieldName is set on initial configuration.
 * @discussion If @c customHeaderFieldValue on initial configuration can not be set on app launch, this method can be used to do so later.
 * @discussion Requests not started due to missing @c customHeaderFieldValue since app launch will start hereafter.
 * @param customHeaderFieldValue Custom header field value
 */
- (void)setCustomHeaderFieldValue:(NSString *)customHeaderFieldValue;

/**
 * Starts session and sends @c begin_session request with default metrics for manual session handling.
 * @discussion This method needs to be called for starting a session only if @c manualSessionHandling flag is set on initial configuration.
 * @discussion Otherwise; sessions will be handled automatically by default, and calling this method will have no effect.
 */
- (void)beginSession;

/**
 * Updates session and sends unsent session duration for manual session handling.
 * @discussion This method needs to be called for updating a session only if @c manualSessionHandling flag is set on initial configuration.
 * @discussion Otherwise; sessions will be handled automatically by default, and calling this method will have no effect.
 */
- (void)updateSession;

/**
 * Ends session and sends @c end_session request for manual session handling.
 * @discussion This method needs to be called for ending a session only if @c manualSessionHandling flag is set on initial configuration.
 * @discussion Otherwise; sessions will be handled automatically by default, and calling this method will have no effect.
 */
- (void)endSession;

#if TARGET_OS_WATCH
/**
 * Suspends Countly, adds recorded events to request queue and ends current session.
 * @discussion This method needs to be called manually only on @c watchOS, on other platforms it will be called automatically.
 */
- (void)suspend;

/**
 * Resumes Countly, begins a new session after the app comes to foreground.
 * @discussion This method needs to be called manually only on @c watchOS, on other platforms it will be called automatically.
 */
- (void)resume;
#endif



#pragma mark - Consents

/**
 * Grants consent to given feature and starts it.
 * @discussion If @c requiresConsent flag is set on initial configuration, each feature waits and ignores manual calls until explicit consent is given.
 * @discussion After giving consent to a feature, it is started and kept active henceforth.
 * @discussion If consent to the feature is already given before, calling this method will have no effect.
 * @discussion If @c requiresConsent flag is not set on initial configuration, calling this method will have no effect.
 * @param featureName Feature name to give consent to
 */
- (void)giveConsentForFeature:(NSString *)featureName;

/**
 * Grants consent to given features and starts them.
 * @discussion This is a convenience method for grating consent for multiple features at once.
 * @discussion Inner workings of @c giveConsentForFeature: method applies for this method as well.
 * @param features Array of feature names to give consent to
 */
- (void)giveConsentForFeatures:(NSArray *)features;

/**
 * Grants consent to all features and starts them.
 * @discussion This is a convenience method for grating consent for all features at once.
 * @discussion Inner workings of @c giveConsentForFeature: method applies for this method as well.
 */
- (void)giveConsentForAllFeatures;

/**
 * Cancels consent to given feature and stops it.
 * @discussion After cancelling consent to a feature, it is stopped and kept inactive henceforth.
 * @discussion If consent to the feature is already cancelled before, calling this method will have no effect.
 * @discussion If @c requiresConsent flag is not set on initial configuration, calling this method will have no effect.
 * @param featureName Feature name to cancel consent to
 */
- (void)cancelConsentForFeature:(NSString *)featureName;

/**
 * Cancels consent to given features and stops them.
 * @discussion This is a convenience method for cancelling consent for multiple features at once.
 * @discussion Inner workings of @c cancelConsentForFeature: method applies for this method as well.
 * @param features Array of feature names to cancel consent to
 */
- (void)cancelConsentForFeatures:(NSArray *)features;

/**
 * Cancels consent to all features and stops them.
 * @discussion This is a convenience method for cancelling consent for all features at once.
 * @discussion Inner workings of @c cancelConsentForFeature: method applies for this method as well.
 */
- (void)cancelConsentForAllFeatures;

/**
 * Returns current device ID being used for tracking.
 * @discussion Device ID can be used for handling data export and/or removal requests as part of data privacy compliance.
 */
- (NSString *)deviceID;



#pragma mark - Events

/**
 * Records event with given key.
 * @param key Event key
 */
- (void)recordEvent:(NSString *)key;

/**
 * Records event with given key and count.
 * @param key Event key
 * @param count Count of event occurrences
 */
- (void)recordEvent:(NSString *)key count:(NSUInteger)count;

/**
 * Records event with given key and sum.
 * @param key Event key
 * @param sum Sum of any specific value for event
 */
- (void)recordEvent:(NSString *)key sum:(double)sum;

/**
 * Records event with given key and duration.
 * @param key Event key
 * @param duration Duration of event in seconds
 */
- (void)recordEvent:(NSString *)key duration:(NSTimeInterval)duration;

/**
 * Records event with given key, count and sum.
 * @param key Event key
 * @param count Count of event occurrences
 * @param sum Sum of any specific value for event
 */
- (void)recordEvent:(NSString *)key count:(NSUInteger)count sum:(double)sum;

/**
 * Records event with given key and segmentation.
 * @param key Event key
 * @param segmentation Segmentation key-value pairs of event
 */
- (void)recordEvent:(NSString *)key segmentation:(NSDictionary * _Nullable)segmentation;

/**
 * Records event with given key, segmentation and count.
 * @param key Event key
 * @param segmentation Segmentation key-value pairs of event
 * @param count Count of event occurrences
 */
- (void)recordEvent:(NSString *)key segmentation:(NSDictionary * _Nullable)segmentation count:(NSUInteger)count;

/**
 * Records event with given key, segmentation, count and sum.
 * @param key Event key
 * @param segmentation Segmentation key-value pairs of event
 * @param count Count of event occurrences
 * @param sum Sum of any specific value for event
 */
- (void)recordEvent:(NSString *)key segmentation:(NSDictionary * _Nullable)segmentation count:(NSUInteger)count sum:(double)sum;

/**
 * Records event with given key, segmentation, count, sum and duration.
 * @param key Event key
 * @param segmentation Segmentation key-value pairs of event
 * @param count Count of event occurrences
 * @param sum Sum of any specific value for event
 * @param duration Duration of event in seconds
 */
- (void)recordEvent:(NSString *)key segmentation:(NSDictionary * _Nullable)segmentation count:(NSUInteger)count sum:(double)sum duration:(NSTimeInterval)duration;

/**
 * Starts a timed event with given key to be ended later. Duration of timed event will be calculated on ending.
 * @discussion Trying to start an event with already started key will have no effect.
 * @param key Event key
 */
- (void)startEvent:(NSString *)key;

/**
 * Ends a previously started timed event with given key.
 * @discussion Trying to end an event with already ended (or not yet started) key will have no effect.
 * @param key Event key
 */
- (void)endEvent:(NSString *)key;

/**
 * Ends a previously started timed event with given key, segmentation, count and sum.
 * @discussion Trying to end an event with already ended (or not yet started) key will have no effect.
 * @param key Event key
 * @param segmentation Segmentation key-value pairs of event
 * @param count Count of event occurrences
 * @param sum Sum of any specific value for event
 */
- (void)endEvent:(NSString *)key segmentation:(NSDictionary * _Nullable)segmentation count:(NSUInteger)count sum:(double)sum;

/**
 * Cancels a previously started timed event with given key.
 * @discussion Trying to cancel an event with already cancelled (or ended or not yet started) key will have no effect.
 * @param key Event key
 */
- (void)cancelEvent:(NSString *)key;



#pragma mark - Push Notification
#if (TARGET_OS_IOS || TARGET_OS_OSX)
/**
 * Shows default system dialog that asks for user's permission to display notifications.
 * @discussion A unified convenience method that handles asking for notification permission on both iOS10 and older iOS versions with badge, sound and alert notification types.
 */
- (void)askForNotificationPermission;

/**
 * Shows default system dialog that asks for user's permission to display notifications with given options and completion handler.
 * @discussion A more customizable version of unified convenience method that handles asking for notification permission on both iOS10 and older iOS versions.
 * @discussion Notification types the app wants to display can be specified using @c options parameter.
 * @discussion Completion block has @c granted (@c BOOL) parameter which is @c YES if user granted permission, and @c error (@c NSError) parameter which is non-nil if there is an error.
 * @param options Bitwise combination of notification types (badge, sound or alert) the app wants to display
 * @param completionHandler A completion handler block to be executed when user answers notification permission dialog
 */
- (void)askForNotificationPermissionWithOptions:(UNAuthorizationOptions)options completionHandler:(void (^)(BOOL granted, NSError * error))completionHandler API_AVAILABLE(ios(10.0), macos(10.14));

/**
 * Records action event for a manually presented push notification with custom action buttons.
 * @discussion If a push notification with custom action buttons is handled and presented manually using custom UI, user's action needs to be reported manually.
 * @discussion With this convenience method user's action can be reported passing push notification dictionary and clicked button index.
 * @discussion Button index should be @c 0 for default action, @c 1 for the first action button and @c 2 for the second action button.
 * @param userInfo Manually presented push notification dictionary
 * @param buttonIndex Index of custom action button user clicked
 */
- (void)recordActionForNotification:(NSDictionary *)userInfo clickedButtonIndex:(NSInteger)buttonIndex;

/**
 * Records push notification token to Countly Server for current device ID.
 * @discussion Can be used to re-send push notification token for current device ID, after a new user logs in and device ID changes, without waiting for the app to be restarted.
 * @discussion In general, push notification token is handled automatically and this method does not need to be called manually.
 */
- (void)recordPushNotificationToken;

/**
 * Clears push notification token on Countly Server for current device ID.
 * @discussion Can be used to clear push notification token for current device ID, before the current user logs out and device ID changes, without waiting for the app to be restarted.
 */
- (void)clearPushNotificationToken;
#endif



#pragma mark - Location

/**
 * Records user's location info to be used for geo-location based push notifications and advanced user segmentation.
 * @discussion By default, Countly Server uses a geo-ip database for acquiring user's location.
 * @discussion If the app uses Core Location services and granted permission, a location with better accuracy can be provided using this method.
 * @discussion This method overrides @c location property specified on initial configuration, and sends an immediate request.
 * @param location User's location with latitude and longitude
 */
- (void)recordLocation:(CLLocationCoordinate2D)location;

/**
 * Records user's city and country info to be used for geo-location based push notifications and advanced user segmentation.
 * @discussion By default, Countly Server uses a geo-ip database for acquiring user's location.
 * @discussion If the app has information about user's city and/or country, these information can be provided using this method.
 * @discussion This method overrides @c city and @c ISOCountryCode properties specified on initial configuration, and sends an immediate request.
 * @param city User's city
 * @param ISOCountryCode User's ISO country code in ISO 3166-1 alpha-2 format
 */
- (void)recordCity:(NSString *)city andISOCountryCode:(NSString *)ISOCountryCode;

/**
 * Records user's IP address to be used for geo-location based push notifications and advanced user segmentation.
 * @discussion By default, Countly Server uses a geo-ip database for acquiring user's location.
 * @discussion If the app needs to explicitly specify the IP address due to network requirements, it can be provided using this method.
 * @discussion This method overrides @c IP property specified on initial configuration, and sends an immediate request.
 * @param IP User's explicit IP address
 */
- (void)recordIP:(NSString *)IP;

/**
 * Disables geo-location based push notifications by clearing all exsisting location info.
 * @discussion Once disabled, geo-location based push notifications can be enabled again by calling @c recordLocation: or @c recordCity:andISOCountryCode: or @c recordIP: method.
 */
- (void)disableLocationInfo;

/**
 * @c isGeoLocationEnabled property is deprecated. Please use @c disableLocationInfo method instead.
 * @discussion Using this property will have no effect.
 */
@property (nonatomic) BOOL isGeoLocationEnabled DEPRECATED_MSG_ATTRIBUTE("Use 'disableLocationInfo' method instead!");



#pragma mark - Crash Reporting
#if TARGET_OS_IOS
/**
 * Records a handled exception manually.
 * @param exception Exception to be reported
 */
- (void)recordHandledException:(NSException *)exception;

/**
 * Records a handled exception and given stack trace manually.
 * @param exception Exception to be reported
 * @param stackTrace Stack trace to be reported
 */
- (void)recordHandledException:(NSException *)exception withStackTrace:(NSArray * _Nullable)stackTrace;

/**
 * Records an unhandled exception and given stack trace manually.
 * @discussion For recording non-native level fatal exceptions, where the app keeps running at native level and can recover.
 * @param exception Exception to be reported
 * @param stackTrace Stack trace to be reported
 */
- (void)recordUnhandledException:(NSException *)exception withStackTrace:(NSArray * _Nullable)stackTrace;

/**
 * Records custom logs to be delivered with crash report.
 * @discussion Logs recorded by this method are stored in a non-persistent structure, and delivered to Countly Server only in case of a crash.
 * @param log Custom log string to be recorded
 */
- (void)recordCrashLog:(NSString *)log;

/**
 * @c crashLog: method is deprecated. Please use @c recordCrashLog: method instead.
 * @discussion Be advised, parameter type chenged to plain @c NSString from string format, for better Swift compatibility.
 * @discussion Calling this method will have no effect.
 */
- (void)crashLog:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2) DEPRECATED_MSG_ATTRIBUTE("Use 'recordCrashLog:' method instead!");

#endif



#pragma mark - APM

/**
 * Adds exception URL for APM.
 * @discussion Added URLs (with or without specific path) will be ignored by APM.
 * @discussion Adding an already added URL again will have no effect.
 * @param exceptionURL Exception URL to be added
 */
- (void)addExceptionForAPM:(NSString *)exceptionURL;

/**
 * Removes exception URL for APM.
 * @discussion Removing an already removed (or not yet added) URL again will have no effect.
 * @param exceptionURL Exception URL to be removed
 */
- (void)removeExceptionForAPM:(NSString *)exceptionURL;



#pragma mark - View Tracking

/**
 * Records a visited view with given name.
 * @discussion Total duration of the view will be calculated on next @c recordView: call.
 * @discussion If AutoViewTracking feature is enabled on initial configuration, this method does not need to be called manually.
 * @param viewName Name of the view visited
 */
- (void)recordView:(NSString *)viewName;

/**
 * @c reportView: method is deprecated. Please use @c recordView: method instead.
 * @discussion Calling this method will have no effect.
 */
- (void)reportView:(NSString *)viewName DEPRECATED_MSG_ATTRIBUTE("Use 'recordView:' method instead!");

#if TARGET_OS_IOS
/**
 * Adds exception for AutoViewTracking.
 * @discussion @c UIViewControllers with specified title or class name will be ignored by AutoViewTracking and their appearances and disappearances will not be reported.
 * @discussion Adding an already added @c UIViewController title or subclass name again will have no effect.
 * @param exception @c UIViewController title or subclass name to be added as exception
 */
- (void)addExceptionForAutoViewTracking:(NSString *)exception;

/**
 * Removes exception for AutoViewTracking.
 * @discussion Removing an already removed (or not yet added) @c UIViewController title or subclass name will have no effect.
 * @param exception @c UIViewController title or subclass name to be removed
 */
- (void)removeExceptionForAutoViewTracking:(NSString *)exception;

/**
 * Temporarily activates or deactivates AutoViewTracking, if AutoViewTracking feature is enabled on initial configuration.
 * @discussion If AutoViewTracking feature is not enabled on initial configuration, this property has no effect.
 */
@property (nonatomic) BOOL isAutoViewTrackingActive;

/**
 * @c isAutoViewTrackingEnabled property is deprecated. Please use @c isAutoViewTrackingActive property instead.
 * @discussion Using this property will have no effect.
 */
@property (nonatomic) BOOL isAutoViewTrackingEnabled DEPRECATED_MSG_ATTRIBUTE("Use 'isAutoViewTrackingActive' property instead!");

#endif



#pragma mark - User Details

/**
 * Returns @c CountlyUserDetails singleton to be used throughout the app.
 * @return The shared @c CountlyUserDetails object
 */
+ (CountlyUserDetails *)user;

/**
 * Handles switching from device ID to custom user ID for logged in users
 * @discussion When a user logs in, this user can be tracked with custom user ID instead of device ID.
 * @discussion This is just a convenience method that handles setting user ID as new device ID and merging existing data on Countly Server.
 * @param userID Custom user ID uniquely defining the logged in user
 */
- (void)userLoggedIn:(NSString *)userID;

/**
 * Handles switching from custom user ID to device ID for logged out users
 * @discussion When a user logs out, all the data can be tracked with default device ID henceforth.
 * @discussion This is just a convenience method that handles resetting device ID to default one and starting a new session.
 */
- (void)userLoggedOut;



#pragma mark - Star Rating
#if TARGET_OS_IOS
/**
 * Shows star-rating dialog manually and executes completion block after user's action.
 * @discussion Completion block has a single NSInteger parameter that indicates 1 to 5 star-rating given by user.
 * @discussion If user dismissed dialog without giving a rating, this value will be 0 and it will not be reported to Countly Server.
 * @param completion A block object to be executed when user gives a star-rating or dismisses dialog without rating
 */
- (void)askForStarRating:(void(^)(NSInteger rating))completion;

/**
 * Presents feedback widget with given ID in a WKWebView placed in a UIViewController.
 * @discussion First, the availability of the feedback widget will be checked asynchronously.
 * @discussion If the feedback widget with given ID is available, it will be modally presented.
 * @discussion Otherwise, @c completionHandler will be called with an @c NSError.
 * @discussion @c completionHandler will also be called with @c nil when feedback widget is dismissed by user.
 * @param widgetID ID of the feedback widget created on Countly Server.
 * @param completionHandler A completion handler block to be executed when feedback widget is dismissed by user or there is an error.
 */
- (void)presentFeedbackWidgetWithID:(NSString *)widgetID completionHandler:(void (^)(NSError * error))completionHandler;

#endif



#pragma mark - Remote Config
/**
 * Returns last retrieved remote config value for given key, if exists.
 * @discussion If remote config is never retrieved from Countly Server before, this method will return @c nil.
 * @discussion If @c key is not defined in remote config on Countly Server, this method will return @c nil.
 * @discussion If Countly Server is not reachable, this method will return the last retrieved value which is stored on device.
 * @param key Remote config key specified on Countly Server
 */
- (id)remoteConfigValueForKey:(NSString *)key;

/**
 * Manually updates all locally stored remote config values by fetching latest values from Countly Server, and executes completion handler.
 * @discussion @c completionHandler has an @c NSError parameter that will be either @ nil or an @c NSError object, depending on result.
 * @param completionHandler A completion handler block to be executed when updating of remote config is completed, either with success or failure.
 */
- (void)updateRemoteConfigWithCompletionHandler:(void (^)(NSError * error))completionHandler;

/**
 * Manually updates locally stored remote config values only for specified keys, by fetching latest values from Countly Server, and executes completion handler.
 * @discussion @c completionHandler has an @c NSError parameter that will be either @ nil or an @c NSError object, depending on result.
 * @param keys An array of remote config keys to update
 * @param completionHandler A completion handler block to be executed when updating of remote config is completed, either with success or failure
 */
- (void)updateRemoteConfigOnlyForKeys:(NSArray *)keys completionHandler:(void (^)(NSError * error))completionHandler;

/**
 * Manually updates locally stored remote config values except for specified keys, by fetching latest values from Countly Server, and executes completion handler.
 * @discussion @c completionHandler has an @c NSError parameter that will be either @ nil or an @c NSError object, depending on result.
 * @param omitKeys An array of remote config keys to omit from updating
 * @param completionHandler A completion handler block to be executed when updating of remote config is completed, either with success or failure
 */
- (void)updateRemoteConfigExceptForKeys:(NSArray *)omitKeys completionHandler:(void (^)(NSError * error))completionHandler;

NS_ASSUME_NONNULL_END

@end
