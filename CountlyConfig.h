// CountlyConfig.h
//
// This code is provided under the MIT License.
//
// Please visit www.count.ly for more information.

#import <Foundation/Foundation.h>

//NOTE: Countly features
#if TARGET_OS_IOS
extern NSString* const CLYMessaging;
extern NSString* const CLYCrashReporting;
extern NSString* const CLYAutoViewTracking;
#endif
extern NSString* const CLYAPM;


//NOTE: Device ID options
#if TARGET_OS_IOS
extern NSString* const CLYIDFA;
extern NSString* const CLYIDFV;
extern NSString* const CLYOpenUDID;
#elif (!(TARGET_OS_IOS || TARGET_OS_TV || TARGET_OS_WATCH))
extern NSString* const CLYOpenUDID;
#endif

@interface CountlyConfig : NSObject

/**
 * County Server's URL without the last slash. E.g. https://mycountlyserver.com
 */
@property (nonatomic, strong) NSString* host;

/**
 * Application's App Key found on Countly Server's Management > Application section. Using API Key or App ID will not work.
 */
@property (nonatomic, strong) NSString* appKey;

/**
 * For specifiying which features Countly will start with.
 * @discussion Available features:
 * @discussion CLYMessaging for push notifications,
 * @discussion CLYCrashReporting for crash reporting,
 * @discussion CLYAutoViewTracking for auto view tracking and
 * @discussion CLYAPM for application performance management.
 */
@property (nonatomic, strong) NSArray* features;

/**
 * Required for CLYMessaging (push notifications) feature. It must be set to launchOptions parameter of application:didFinishLaunchingWithOptions: method. If not set, an NSAssertion will fail.
 */
@property (nonatomic, strong) NSDictionary* launchOptions;

/**
 * For manually marking a device as test device for CLYMessaging (push notifications) feature. Test push notifications can be to test devices by checking "Send to test device" checkbox on "Create Message" section.
 */
@property (nonatomic, readwrite) BOOL isTestDevice;

/**
 * For using custom crash segmentation with CLYCrashReporting feature.
 */
@property (nonatomic, strong) NSDictionary* crashSegmentation;

/**
 * @discussion Custom or system generated device ID. If not set, Identifier For Advertising (IDFA) will be used by default.
 * @discussion Available sytem generated device ID options:
 * @discussion CLYIDFA (Identifier For Advertising)
 * @discussion CLYIDFV (Identifier For Vendor)
 * @discussion CLYOpenUDID (OpenUDID)
 * @discussion Once set, deviceID will be stored persistently (even after app delete and re-install) and will not be changed even if you set another device ID on start, unless you set forceDeviceIDInitialization flag
 */
@property (nonatomic, strong) NSString* deviceID;

/**
 * For forcing device ID initialization on start. When it is set, persistenly stored device ID will be reset and new device ID will be re-initialized with deviceID property on CountlyConfig object.
 */
@property (nonatomic, readwrite) BOOL forceDeviceIDInitialization;

/**
 * Update session period is used to send events and update_session requests to server periodically. If not set, it will be 60 seconds for iOS, tvOS & OSX, and 20 seconds for watchOS by default.
 */
@property (nonatomic, readwrite) NSTimeInterval updateSessionPeriod;

/**
 * Event send threshold is used to send events requests to server when number of recorded custom events reach it, without waiting for next update_session tick defined by updateSessionPeriod. If not set, it will be 10 for iOS, tvOS & OSX, and 3 for watchOS by default.
 */
@property (nonatomic, readwrite) NSUInteger eventSendThreshold;

/**
 * Stored requests limit is used to limit number of request to be queued. In case Countly Server is down or unreachable for a very long time, queued request may reach excessive numbers, and it may cause problems with being delivered to server and being stored on the device. To prevent this, SDK will only store requests up to storedRequestsLimit. If number of stored requests reach storedRequestsLimit, SDK will start to drop oldest request while inserting the newest one instead. If not set, it will be 1000 by default.
 */
@property (nonatomic, readwrite) NSUInteger storedRequestsLimit;

/**
 * ISO Country Code can be specified in ISO 3166-1 alpha-2 format to be used for advanced segmentation. It will be sent with begin_session request.
 */
@property (nonatomic, strong) NSString* ISOCountryCode;

/**
 * City name can be specified as string to be used for advanced segmentation. It will be sent with begin_session request.
 */
@property (nonatomic, strong) NSString* city;

/**
 * Location latitude and longitude can be specified as CLLocationCoordinate2D struct to be used for advanced segmentation. It will be sent with begin_session request.
 */
@property (nonatomic, readwrite) CLLocationCoordinate2D location;

/**
 * For specifying bundled certificates to be used for public key pinning.
 * @discussion Certificates have to be DER encoded with one of the following extensions: .der .cer or .crt
 * @discussion  e.g. myserver.com.cer
 */
@property (nonatomic, strong) NSArray* pinnedCertificates;

@end