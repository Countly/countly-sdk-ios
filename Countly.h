
// Countly.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

@class CountlyEventQueue;

@interface Countly : NSObject
{
	double unsentSessionLength;
	NSTimer *timer;
	double lastTime;
	BOOL isSuspended;
    CountlyEventQueue *eventQueue;
}

+ (instancetype)sharedInstance;

- (void)start:(NSString *)appKey withHost:(NSString *)appHost;

- (void)startOnCloudWithAppKey:(NSString *)appKey;

- (void)recordEvent:(NSString *)key count:(int)count;

- (void)recordEvent:(NSString *)key count:(int)count sum:(double)sum;

- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(int)count;

- (void)recordEvent:(NSString *)key segmentation:(NSDictionary *)segmentation count:(int)count sum:(double)sum;

- (void)recordUserDetails:(NSDictionary *)userDetails;
extern NSString* const kCLYUserName;
extern NSString* const kCLYUserUsername;
extern NSString* const kCLYUserEmail;
extern NSString* const kCLYUserOrganization;
extern NSString* const kCLYUserPhone;
extern NSString* const kCLYUserGender;
extern NSString* const kCLYUserPicture;
extern NSString* const kCLYUserPicturePath;
extern NSString* const kCLYUserBirthYear;
extern NSString* const kCLYUserCustom;

#pragma mark - Countly Messaging
#if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR
/**
 * Countly Messaging support
 */
- (void)startWithMessagingUsing:(NSString *)appKey withHost:(NSString *)appHost andOptions:(NSDictionary *)options;

/**
 * Make this device a test device, so only messages with test checkbox will arrive on it.
 */
- (void)startWithTestMessagingUsing:(NSString *)appKey withHost:(NSString *)appHost andOptions:(NSDictionary *)options;

- (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken;

- (void)didFailToRegisterForRemoteNotifications;

/**
 * Records user's location and sends it to the server with next updateSession. This value will be used instead of geoip lookup on the server when sending geolocation-aware push notifications.
 */
- (void)setLocation:(double)latitude longitude:(double)longitude;

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
#endif
@end


