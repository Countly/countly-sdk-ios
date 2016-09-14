// Countly.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import "CountlyUserDetails.h"
#import "CountlyCrashReporter.h"
#import "CountlyConfig.h"

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
 * Suspends Countly, add recorded events to request queue and ends current session.
 * @discussion This method needs to be called manually only on @c watchOS, on other platforms it will be called automatically.
 */
- (void)suspend;

/**
 * Resumes Countly, begins a new session after app comes to foreground.
 * @discussion This method needs to be called manually only on @c watchOS, on other platforms it will be called automatically.
 */
- (void)resume;



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



#pragma mark - Countly Messaging
#if TARGET_OS_IOS
- (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken;

- (void)didFailToRegisterForRemoteNotifications;

/**
 * Create a set of UIMutableUserNotificationCategory'ies which you can register in addition to your ones to enable iOS 8 actions.
 */
- (NSMutableSet *) countlyNotificationCategories;

/**
 * Create a set of UIMutableUserNotificationCategory'ies which you can register in addition to your ones to enable iOS 8 actions. This method gives you ability to provide localized or just different versions of your action titles.
 * @param titles Array of NSString objects in following order: Cancel, Open, Update, Review
 */
- (NSMutableSet *) countlyNotificationCategoriesWithActionTitles:(NSArray *)actions;

/**
 * Method that does automatic processing for Countly Messaging:
 * - It records that the message has been received.
 * - In case of standard Countly messages (Message, URL, Update, Review) it displays alert with app name as a title:
 * --- for Message - just alert with message text and button OK;
 * --- for URL - Cancel & Open buttons;
 * --- for Update - Cancel & Update buttons;
 * --- for Review - Cancel & Review buttons.
 * Whenever user presses one of (Open, Update, Review) buttons Countly performs corresponding action (opens up a Safari for URL type, opens your app page in App Store for Update and review section of your app in App Store for Review) and records Action event so you could then see conversion rates in Countly Dashboard.
 * @param info Dictionary you got from application:didReceiveRemoteNotification:
 * @param titles Array of NSString objects in following order: Cancel, Open, Update, Review
 * @return TRUE When Countly has successfully handled notification and presented alert, FALSE otherwise.
 */
- (BOOL)handleRemoteNotification:(NSDictionary *)info withButtonTitles:(NSArray *)titles;

/**
 * Same as previous method, but with default button titles Cancel, OK, URL, Update, Review.
 */
- (BOOL)handleRemoteNotification:(NSDictionary *)info;

/**
 * Method records push opened event. Quite handy if you do not call handleRemoteNotification: method, but still want to see conversions in Countly Dashboard.
 * @param c NSDictionary of @"c" userInfo key.
 */
- (void)recordPushOpenForCountlyDictionary:(NSDictionary *)c;

/**
 * Method records push action event. Quite handy if you do not call handleRemoteNotification: method, but still want to see conversions in Countly Dashboard.
 * @param c NSDictionary of @"c" userInfo key.
 */
- (void)recordPushActionForCountlyDictionary:(NSDictionary *)c;


/**
 * Records location with given coordinate to be used for location-aware push notifications.
 * @param coordinate CLLocationCoordinate2D struct with latitude and longitude
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
 * @discussion If auto ViewTracking feature is activated on start configuration, this method does not need to be called manually.
 * @param viewName Name of the view visited
 */
- (void)reportView:(NSString *)viewName;

#if TARGET_OS_IOS
/**
 * Adds exception @c UIViewController subclass for AutoViewTracking.
 * @discussion Added @c UIViewContoller subclasses will be ignored by AutoViewTracking and their appearances and disappearances will not be reported. Adding an already added @c UIViewController subclass again will have no effect.
 * @param exceptionViewControllerSubclass Exception @c UIViewController subclass to be added
 */
- (void)addExceptionForAutoViewTracking:(Class)exceptionViewControllerSubclass;

/**
 * Removes exception @c UIViewController subclass for AutoViewTracking.
 * @discussion Removing an already removed (or not yet added) @c UIViewController subclass again will have no effect.
 * @param exceptionViewControllerSubclass Exception @c UIViewController subclass to be removed
 */
- (void)removeExceptionForAutoViewTracking:(Class)exceptionViewControllerSubclass;

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


#pragma mark - Countly StarRating
#if TARGET_OS_IOS
/**
 * Shows star-rating dialog manually and executes completion block after user's action.
 * @discussion Completion block takes a single NSInteger argument that indicates 1 to 5 star-rating given by user. If user dismissed dialog without giving a rating, this value will be 0 and it will not be reported to server.
 * @param completion A block object to be executed when user gives a star-rating or dismisses dialog without rating
 */
- (void)askForStarRating:(void(^)(NSInteger rating))completion;
#endif
@end
