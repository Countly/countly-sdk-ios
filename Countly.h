// Countly.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import "CountlyUserDetails.h"
#import "CountlyConfig.h"
#if TARGET_OS_IOS
#import <UserNotifications/UserNotifications.h>
#endif

@interface Countly : NSObject

#pragma mark - Countly Core

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
 * @param onServer If set, data on server will be merged automatically, otherwise device will be counted as a new device
 */
- (void)setNewDeviceID:(NSString *)deviceID onServer:(BOOL)onServer;

/**
 * Sets the value of the custom HTTP header field to be sent with every request if @c customHeaderFieldName is set on initial configuration.
 * @discussion If @c customHeaderFieldValue on initial configuration can not be set on app launch, this method can be used to do so later. Requests not started due to missing @c customHeaderFieldValue since app launch will start hereafter.
 * @param customHeaderFieldValue Custom header field value
 */
- (void)setCustomHeaderFieldValue:(NSString *)customHeaderFieldValue;

/**
 * Starts session and sends @c begin_session request with default metrics for manual session handling.
 * @discussion This method needs to be called for starting a session only if @c manualSessionHandling flag is set on initial configuration. Otherwise; sessions will be handled automatically by default, and calling this method will have no effect.
 */
- (void)beginSession;

/**
 * Updates session and sends unsent session duration for manual session handling.
 * @discussion This method needs to be called for updating a session only if @c manualSessionHandling flag is set on initial configuration. Otherwise; sessions will be handled automatically by default, and calling this method will have no effect.
 */
- (void)updateSession;

/**
 * Ends session and sends @c end_session request for manual session handling.
 * @discussion This method needs to be called for ending a session only if @c manualSessionHandling flag is set on initial configuration. Otherwise; sessions will be handled automatically by default, and calling this method will have no effect.
 */
- (void)endSession;


#if TARGET_OS_WATCH
/**
 * Suspends Countly, adds recorded events to request queue and ends current session.
 * @discussion This method needs to be called manually only on @c watchOS, on other platforms it will be called automatically.
 */
- (void)suspend;

/**
 * Resumes Countly, begins a new session after app comes to foreground.
 * @discussion This method needs to be called manually only on @c watchOS, on other platforms it will be called automatically.
 */
- (void)resume;
#endif



#pragma mark - Countly CustomEvents

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
 * @param sum Sum of any specific value to event (i.e. Total In-App Purchase amount)
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
 * @param sum Sum of any specific value to event (i.e. Total In-App Purchase amount)
 */
- (void)recordEvent:(NSString *)key count:(NSUInteger)count sum:(double)sum;

/**
 * Records event with given key and segmentation.
 * @param key Event key
 * @param segmentation Segmentation key-value pairs of event
 */
- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation;

/**
 * Records event with given key, segmentation and count.
 * @param key Event key
 * @param segmentation Segmentation key-value pairs of event
 * @param count Count of event occurrences
 */
- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(NSUInteger)count;

/**
 * Records event with given key, segmentation, count and sum.
 * @param key Event key
 * @param segmentation Segmentation key-value pairs of event
 * @param count Count of event occurrences
 * @param sum Sum of any specific value to event (i.e. Total In-App Purchase amount)
 */
- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(NSUInteger)count sum:(double)sum;

/**
 * Records event with given key, segmentation, count, sum and duration.
 * @param key Event key
 * @param segmentation Segmentation key-value pairs of event
 * @param count Count of event occurrences
 * @param sum Sum of any specific value to event (i.e. Total In-App Purchase amount)
 * @param duration Duration of event in seconds
 */
- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(NSUInteger)count sum:(double)sum duration:(NSTimeInterval)duration;

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
 * @param sum Sum of any specific value to event (i.e. Total In-App Purchase amount)
 */
- (void)endEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(NSUInteger)count sum:(double)sum;



#pragma mark - Countly PushNotifications
#if TARGET_OS_IOS
/**
 * Shows default system dialog that asks for user's permission to display notifications.
 * @discussion A unified convenience method that handles asking for notification permisson on both iOS10 and older iOS versions with badge, sound and alert notification types.
 */
- (void)askForNotificationPermission;

/**
 * Shows default system dialog that asks for user's permission to display notifications with given options and completion handler.
 * @discussion A more customizable version of unified convenience method that handles asking for notification permisson on both iOS10 and older iOS versions where notification types app wants to display can be specified using @c options parameter. Completion block has a @c BOOL parameter called @c granted which is @c YES if user gave permission, and an @c NSError parameter called @c error which indicates if there is an error.
 * @param options Bitwise combination of notification types (like badge, sound or alert) app wants to display
 * @param completionHandler A completion handler block to be executed when user answers notification permission dialog
 */
- (void)askForNotificationPermissionWithOptions:(UNAuthorizationOptions)options completionHandler:(void (^)(BOOL granted, NSError * error))completionHandler;

/**
 * Records user's location to be used for geo-location based push notifications and advanced segmentation.
 * @discussion By default, geoip database is used for acquiring user's location. If the app uses Core Location services, location with better accuracy can be provided using this method. Calling this method once or twice per app launch is enough, instead of each location update.
 * @param coordinate User's location with latitude and longitude
 */
- (void)recordLocation:(CLLocationCoordinate2D)coordinate;
#endif



#pragma mark - Countly CrashReporting
#if TARGET_OS_IOS
/**
 * Records a handled exception manually, besides automatically reported unhandled exceptions and crashes.
 * @param exception Exception to be reported
 */
- (void)recordHandledException:(NSException *)exception;

/**
 * Records custom logs to be delivered with crash report.
 * @discussion Logs recorded by `crashLog:` method are stored in a non-persistent structure, and delivered to server only in case of a crash.
 * @param format Custom log string or format to be recorded
 */
- (void)crashLog:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
#endif



#pragma mark - Countly APM

/**
 * Adds exception URL for APM. Added URLs (with or without specific path) will be ignored by APM. Adding an already added URL again will have no effect.
 * @param exceptionURL Exception URL to be added
 */
- (void)addExceptionForAPM:(NSString *)exceptionURL;

/**
 * Removes exception URL for APM. Removing an already removed (or not yet added) URL again will have no effect.
 * @param exceptionURL Exception URL to be removed
 */
- (void)removeExceptionForAPM:(NSString *)exceptionURL;



#pragma mark - Countly AutoViewTracking

/**
 * Reports a visited view with given name manually. 
 * @discussion If auto ViewTracking feature is activated on initial configuration, this method does not need to be called manually.
 * @param viewName Name of the view visited
 */
- (void)reportView:(NSString *)viewName;

#if TARGET_OS_IOS
/**
 * Adds exception for AutoViewTracking.
 * @discussion @c UIViewContollers with specified title or class name will be ignored by AutoViewTracking and their appearances and disappearances will not be reported. Adding an already added @c UIViewController title or subclass name again will have no effect.
 * @param exception @c UIViewContoller title or subclass name to be added as exception
 */
- (void)addExceptionForAutoViewTracking:(NSString *)exception;

/**
 * Removes exception for AutoViewTracking.
 * @discussion Removing an already removed (or not yet added) @c UIViewController title or subclass name will have no effect.
 * @param exception @c UIViewContoller title or subclass name to be removed
 */
- (void)removeExceptionForAutoViewTracking:(NSString *)exception;

/**
 * Enables or disables AutoViewTracking, if AutoViewTracking feature is activated on start configuration.
 * @discussion If AutoViewTracking feature is not activated on start configuration, this property has no effect on enabling or disabling it later.
 */
@property (nonatomic) BOOL isAutoViewTrackingEnabled;
#endif



#pragma mark - Countly UserDetails

/**
 * Returns @c CountlyUserDetails singleton to be used throughout the app.
 * @return The shared @c CountlyUserDetails object
 */
+ (CountlyUserDetails *)user;

/**
 * Handles switching from device ID to custom user ID for logged in users
 * @discussion When a user logs in, this user can be tracked with custom user ID instead of device ID. This is just a convenience method that handles setting user ID as new device ID and merging existing data on server.
 * @param userID Custom user ID uniquely defining the logged in user
 */
- (void)userLoggedIn:(NSString *)userID;

/**
 * Handles switching from custom user ID to device ID for logged out users
 * @discussion When a user logs out, all the data can be tracked with default device ID henceforth. This is just a convenience method that handles resetting device ID to default one and starting a new session.
 */
- (void)userLoggedOut;

#pragma mark - Countly StarRating
#if TARGET_OS_IOS
/**
 * Shows star-rating dialog manually and executes completion block after user's action.
 * @discussion Completion block has a single NSInteger parameter that indicates 1 to 5 star-rating given by user. If user dismissed dialog without giving a rating, this value will be 0 and it will not be reported to server.
 * @param completion A block object to be executed when user gives a star-rating or dismisses dialog without rating
 */
- (void)askForStarRating:(void(^)(NSInteger rating))completion;
#endif
@end
