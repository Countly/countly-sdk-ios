## 19.08
- Added temporary device ID mode
- Added support for Carthage
- Added custom URL session configuration support
- Added custom segmentation support on view tracking
- Added ability to change app key on the run
- Added ability to flush queues
- Added `pushTestMode` property and discarded `isTestDevice` property
- Fixed `WCSessionDelegate` interception
- Fixed title and message check in push notification payloads
- Fixed binary image name extraction for crash reports
- Fixed missing delegate forwarding for `userNotificationCenter:openSettingsForNotification:` method
- Fixed in-app alerts on iOS10+ devices when a silent notification with alert key arrives
- Discarded device ID persistency on Keychain
- Discarded OpenUDID device ID option
- Discarded IDFA device ID option
- Discarded zero IDFA fix
- Updated default device ID on tvOS as `identifierForVendor` 

- Other various improvements
    - Renamed `forceDeviceIDInitialization` flag as `resetStoredDeviceID`
    - Added lightweight generics for segmentation parameters
    - Added dSYM upload script to preserved paths in Podspec
    - Updated dSYM upload script to support paths with spaces     
    - Changed request cache policy to `NSURLRequestReloadIgnoringLocalCacheData`
    - Added battery level for watchOS 4.0+
    - Added JSON validity check before converting objects
    - Deleted unused `kCountlyCRKeyLoadAddress` constant
    - Improved internal logging in binary images processing for crash reports
    - Added persistency for generated `NSUUID`
    - Added precaution to prevent invalid requests from being added to queue
    - Discarded null check on request queue
    - Discarded all APM related files
    - Added length check for view tracking view name
    - Added length check for view tracking exceptions
    - Updated HeaderDocs, internal logs, inline notes and pragma marks 



## 19.02
- Added push notification support for macOS
- Added provisional push notification permission support for iOS12
- Added remote config feature
- Added `recordPushNotificationToken` method to be used after device ID changes
- Added `clearPushNotificationToken` method to be used after device ID changes
- Discarded `Push Open` event and replaced it with `Push Action` event
- Fixed push notification token not being sent on some iOS12 devices
- Fixed device ID change request delaying issue by discarding delay altogether
- Fixed internal view controller presenting failure when root view controller is not ready yet
- Fixed `openURL` freeze caused by iOS
- Fixed wrong `kCountlyQSKeyLocationIP` key in location info requests
- Fixed missing app key in feedback widget requests
- Fixed feedback widget dismiss button position

- Other various improvements
    - Discarded separate UIWindow usage for presenting feedback widgets
    - Added checksum to feedback widget requests
    - Improved internal logging for request queue



## 18.08
- Added feedback widgets support
- Added limit for number of custom crash logs (100 logs)
- Added limit for each custom crash log length (1000 chars)
- Added support for cancelling timed events
- Added support for recording fatal exceptions manually
- Added `userInfo` to crash report custom property
- Added delay before sending change device ID request (server requirement)
- Renamed `isAutoViewTrackingEnabled` as `isAutoViewTrackingActive`
- Fixed Xcode warnings for `askForNotificationPermission` method 
- Fixed `UIAlertController` leak in push notification manager
- Fixed `crashSegmentation` availability for manually recorded crashes
- Fixed `openURL:` call thread as main thread
- Updated minimum supported `macOS` version as `10.10`

- Other various improvements
  - Discarded separate `UIWindow` for presenting `UIAlertControllers`
  - Refactored `buildUUID` and `executableName` as properties
  - Refactored custom crash log array and date formatter
  - Updated HeaderDocs, inline notes, pragma marks 



## 18.04
- Added consent management for GDPR compliance
- Exposed device ID to be used for data export and/or removal requests
- Added precautions for SDK start state to prevent re-starting and early method calls
- Added mutability protection for core functions, configuration properties, events and user details
- Added `COUNTLY_EXCLUDE_IDFA` pre-processor flag to exclude IDFA references
- Added API availability checks and warnings for Apple Watch and Push Notifications
- Renamed `reportView:` method as `recordView:` 
- Fixed early ending of `UIBackgroundTask`
- Fixed getting file path form local storage URL (thanks @dsmo)
- Fixed not respecting `doNotShowAlertForNotifications` flag on iOS10+ devices
- Fixed not starting requests queue when `manualSessionHandling` is enabled
- Fixed `block implicitly retains self` warning in Star Rating
- Fixed local variable shadowing warnings
- Fixed Japanese language code for Star Rating dialog

- Other various improvements
  - Refactored all location info into Location Manager
  - Refactored `checkForAutoAsk` in Star Rating
  - Refactored event recording for consents compatibility
  - Refactored Apple Watch matching
  - Refactored auto view tracking
  - Added top view controller finding method
  - Replaced asserts with exceptions 
  - Deleted unneccessary method declarations in Push Notifications 
  - Deleted unnecessary reference for `WCSession.defaultSession.delegate`
  - Deleted unnecessary `TARGET_OS_OSX` definition
  - Standardized `nil` checks
  - Renamed and reordered some query string constants
  - Updated HeaderDocs, inline notes, pragma marks 
  - Performed whitespace cleaning



## 18.01

- Added `attribution` config
- Added recording city and country for GeoLocation
- Added recording explicit IP address for GeoLocation
- Added disabling GeoLocation
- Updated `recordLocation` method to override inital `location` config
- Fixed reserved key for IP address query string
- Fixed a `CoreTelephony` related crash due to an iOS bug
- Replaced `NSUserDefaults` with `NSCachesDirectory` on tvOS for persistency
- Improved auto dSYM uploader script
- Improved performance on stored request limit execution

- Other various improvements
  - Fixed a placeholder type specifier for `NSNumber`
  - Deleted unnecessary `CLYMessaging` definition
  - Deleted unnecessary strong ownership qualifiers
  - Added Hindu translation for star rating dialog
  - Added change log file
  - Updated user details and star rating reserved keys as constants
  - Updated `OpenGLESVersion` method return type as `NSString`
  - Updated time related types as `NSTimeInterval`
  - Updated HeaderDocs



## 17.09

- Updated for Xcode 9 and iOS 11
- Added symbolication support for crash reports
- Added Automatic dSYM Uploading script
- Added extension subspec for integrating Rich Push Notifications with CocoaPods
- Added nullability specifiers for better Swift compatibility
- Added 28 new system UIViewController subclass exception for Auto View Tracking
- Added convenience method for recording action event for manually handled notifications
- Added convenience method for recording handled exception with stack trace
- Added precaution for invalid event keys
- Added precaution for corrupt request strings
- Made Zero-IDFA fix optional
- Fixed a view tracking duration problem where duration being reported as timestamp
- Replaced `crashLog` method with `recordCrashLog` and added deprecated warning
- Changed dispatch queue type for opening external URLs

- Other various improvements
  - Added Bengali translation for star rating dialog
  - Updated metric, event, view tracking and crash report reserved keys as constants
  - Deleted unnecessary gitattributes file
  - Deleted duplicate Zero-IDFA const
  - Rearranged file imports
  - Updated HeaderDocs
  - Cleaned whitespace



## 17.05

- Added Rich Push Notifications support (attachments and custom action buttons)
- Added manual session handling
- Added URL escaping for custom device ID and other user defined properties
- Added support for accidental extra slash in host
- Added architecture, executable name and load address for crash reporting
- Added IP optional parameter
- Added SDK metadata to all request
- Switched to SHA256 for parameter tampering protection
- Discarded `recordUserDetails` method and combined it with `save` method
- Improved `AutoViewTracking` active duration calculation
- Improved Countly payload check in notification dictionary
- Fixed inner event timestamp for 32 bit devices
- Fixed token cleaning when user's permission changes
- Fixed checksum calculation for `zero-IDFA` fix case
- Fixed OS version metric for `tvOS`
- Fixed double `suspend` method call when user kills the app using App Switcher
- Fixed a compiler warning for `macOS` targets
- Fixed `AutoViewTracking` for `macOS` targets
- Fixed showing of multiple alerts in succession

- Other various improvements
  - Refactored picture upload data preparation from request string using `NSURLComponents`
  - Refactored `zero-IDFA` check
  - Refactored additional info to be sent with begin session request
  - Refactored checksum appending
  - Refactored URLSession generation
  - Refactored opening external URLs on main thread
  - Refactored device model identifier method
  - Refactored sending crash report into connection manager
  - Replaced `__OPTIMIZED__` flag with `DEBUG` flag for push notification test mode detection
  - Replaced boundary method with constant string
  - Replaced text based dismiss button with cross dismiss button for star-rating
  - Redefined request query string keys as constants
  - Redefined push notification reserved keys as constants
  - Redefined GET request max length as a constant
  - Redefined server input endpoint as a constant
  - Redefined push notification test mode values as enum
  - Standardized some integer types
  - Standardized target checking preprocessor macro usage
  - Deleted unnecessary `init` override in push manager
  - Deleted unnecessary `updateSessionPeriod` property in connection manager
  - Deleted unnecessary `starRatingDismissButtonTitle` config property
  - Deleted internal crash test methods
  - Added Czech and Latvian localization for star-rating dialog
  - Changed example host URL for rebranding compatibility
  - Updated handling of notification on `iOS9` and older
  - Updated alert key handling in push notification payload
  - Updated HeaderDocs
  - Cleaned whitespace



## 16.12

- Refactored push notifications  
  - Made integration more easy
  - Added iOS10 push notifications handling
  - Added convenience method for asking push notifications permission covers all iOS versions
  - Renamed feature name from `CLYMessaging` to `CLYPushNotifications`
  - Added configuration option `doNotShowAlertForNotifications` to disable push triggered alerts
  - Discarded complicated `UIUserNotificationCategory` actions
  - Added configuration option `sendPushTokenAlways` to record push token always (for sending silent notification to users without notification permission)
  - Discarded App Store URL fetching with `NSURLConnection`  
- Discarded iOS7 support and deprecated method calls
- Switched to runtime controlled internal logging instead of preprocessor flag
- Added AutoViewTracking support for tvOS
- Added view controller title and custom titleView support for AutoViewTracking
- Improved AutoViewTracking performance and Swift compatibility
- Refactored suspending for crash reporting
- Switched to async file save for suspending
- Added user login and logout convenience methods
- Added configuration option to enable Apple Watch related features
- Moved archiving of queued request into sync block to prevent a very rare occurring crash
- Refactored unsent session duration
- Added completion callback for automatically displayed star-rating dialog
- Partially fixed but temporarily disabled APM feature until server completely supports it
- Fixed too long exception name in crash reports on iOS10
- Other various improvements
  - Refactored starting method
  - Switched to separate window based alert controller displaying for push notifications and star-rating dialogs
  - Renamed constant kCountlyStarRatingButtonSize to prevent compile time conflicts
  - Renamed server input endpoint variable for white label SDK renamer script compatibility
  - Updated star-rating reserved event key
  - Added internal log for successful initialization with SDK name and version
  - Fixed unused `UIAlertViewAssociatedObjectKey` warning for macOS
  - Removed old deviceID zero-IDFA fixer redundant request
  - Added internal logging for connection type retrieval exception
  - Added exception type info to crash reports
  - Fixed duplicate exception adding for AutoViewTracking
  - Prevented Countly internal view controllers from being tracked by AutoViewTracking
  - Prefixed all category methods to prevent possible conflicts
  - Changed timer's runloop mode
  - Updated timestamp type specifier (thanks to @scottlaw)
  - Changed SDK metadata sending to begin_session only
  - Replaced empty string checks with length checks
  - Cleared nullability specifiers
  - Updated HeaderDocs
  - Cleaned whitespace



## 16.06.4

- Fixed iOS10 zero-IDFA problem
- Fixed TARGET_OS_OSX warning for iOS10 SDK on Xcode 8.
- Fixed ending of background tasks.
- Added parameter tampering protection.
- Added density metric.
- Added alwaysUsePOST config property for using POST method for all requests regardless of the data size.
- Added timezone.
- Switched to millisecond timestamp.
- Disabled server response dictionary check.
- Other minor improvements like better internal logging, standardization, whitespacing, code cleaning, commenting, pragma marking and HeaderDocing



## 16.06.3

- Fixed a persistency related crash
- Improved thread safety of request queue and events
- Added Star-Rating, the simplest form of feedback from users, both automatically and manually.
- Improved event recording performance and safety for APM and Auto View Tracking.
- Added custom HTTP header field support for requests, both on initial configuration and later.
- Standardized internal logging grammar and formatting for easier debugging
- Improved headerdocs grammar and formatting for easier integration and usage
- Fixed some static analyzer warnings



## 16.06.2

- Added Star-Rating, the simplest form of feedback from users, both automatically and manually.
- Improved event recording performance and safety for APM and Auto View Tracking.
- Added custom HTTP header field support for requests, both on initial configuration and later.
- Standardized internal logging grammar and formatting for easier debugging
- Improved headerdocs grammar and formatting for easier integration and usage
- Fixed some static analyzer warnings



## 16.06.1

- Added support for certificate pinning.
- Added deleting of user details properties on server by setting them as NSNull.
- Implemented switching between GET and POST depending on data size on requests.
- Fixed a URL encoding issue which causes problems for Asian languages and some JSON payloads.
- Fixed custom crash log formatter.



## 16.06

- Fixed a problem with changing device ID (for system generated device IDs)
- Added isTestDevice flag to mark test devices for Push Notifications
- Improved Auto View Tracking by ignoring non-visible foundation UIViewController subclasses
- Implemented manually adding exception UIViewController subclasses for Auto View Tracking
- Changed default device ID type for tvOS from IDFA to NSUUID
- Added stored requests limit
- Added optional parameters ISOCountryCode, city and location for advanced segmentation
- Discarded timed events persistency
- Added buildUUID and build number to Crash Reports
- Added SDK name (language-origin-platform) to all requests
- Changed default alert title for push messages
- Other minor improvements like better internal logging, standardization, whitespacing, code cleaning, commenting, pragma marking and HeaderDocing



# 16.02.01

- Swithed to POST method for all requests by default
- Fixed some issues with Crash Reporting persistency
- Fixed some issues with CocoaPods v1.0.0
- Other minor fixes and improvements



## 16.02

Completely re-written iOS SDK with watchOS, tvOS & OSX support
- APM
- Manual/Auto ViewTracking
- UserDetails modifiers
- watchOS 2 support
- tvOS support
- Configurable starting
- Custom or system provided (IDFA, IDFV, OpenUDID) device ID
- Changing/merging device ID on runtime
- Persistency without CoreData
- Various performance improvements and minor bugfixes



## 15.06.01

Updated CocoaPods spec



## 15.06

- Added WatchKit support
- Added CrashReporting support
- Fixed minor problems with Messaging
- Added manually ending sessions on background fetch
- Switched to Ubuntu version numbering
