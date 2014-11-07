##What's Countly?

[Countly](http://count.ly) is an innovative, real-time, open source mobile analytics application. 
It collects data from mobile devices, and visualizes this information to analyze mobile application 
usage and end-user behavior. There are two parts of Countly: the server that collects and analyzes data, 
and mobile SDK that sends this data. Both parts are open source with different licensing terms.

This repository includes the SDK for iOS and Mac OS X.

##Installing the SDK

Countly iOS SDK includes necessary tools to track your application. In order to integrate SDK to your application, follow these steps.

1. Download Countly iOS SDK (or clone it in your project as a git submodule).
2. Add these files to your project under Xcode: `Countly.h` `Countly.m` `Countly_OpenUDID.h` `Countly_OpenUDID.m` `CountlyDB.h` `CountlyDB.m` and `Countly.xcdatamodeld`
3. For an OS X target, skip to step 11. For iOS, continue with step 4.
4. Select your project in the Project Navigator
5. Select the **Build Phases** tab
6. Open **Link Binaries With Libraries** expander
7. Click the **+** button
8. Select CoreTelephony.framework, select **Optional** (instead of Required)
9. Select CoreData.framework
10. *(optional)* Drag and drop the added framework to the **Frameworks** group
11. In your application delegate, import `Countly.h`
and inside `application:didFinishLaunchingWithOptions:`  add the line;
`[[Countly sharedInstance] start:@"YOUR_APP_KEY" withHost:@"https://YOUR_API_HOST.com"];` at the beginning of the function.

**Note:** if you use Countly Cloud, you must set withHost parameter to https://cloud.count.ly for step 11.
Or you can use `[[Countly sharedInstance] startOnCloudWithAppKey:@"YOUR_APP_KEY"];` directly.

**Note:** Make sure you use App Key (found under Management -> Applications) and not API Key or App ID. Entering API Key or App ID will not work.

It should finally look like this:

<pre class="prettyprint">
#import "Countly.h"  // newly added line
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
[[Countly sharedInstance] start:@"TYPE_HERE_YOUR_APP_KEY_GENERATED_IN_COUNTLY_ADMIN_DASHBOARD" withHost:@"http://TYPE_HERE_URL_WHERE_API_IS_HOSTED"]; // newly added line
// your code
}
</pre>

### Using ARC ###

If your project uses automatic reference counting (ARC), you should disable it for the 
sources `Countly.m`, `Countly_OpenUDID.m` and `CountlyDB.m`:

1. Select your project
2. Select the **Build Phases** tab
3. Open **Compile Sources** tab
4. Double click `Countly.m`, `Countly_OpenUDID.m` and `CountlyDB.m` and add `-fno-objc-arc` flag

Note: Before upgrading to a new SDK, do not forget to remove the existing, older SDK from your project.

### Using CocoaPods ###

Countly iOS SDK benefits from Cocoapods. For more information, go to [Countly CocoaPods Github directory](https://github.com/CocoaPods/Specs/tree/master/Countly)

##Countly Messaging support
This SDK can be used for Countly analytics, Countly Messaging push notification service or both at the same time. If the only thing you need is Countly analytics, you can skip this section. If you want yo use Countly Messaging, you'll need to add a few more lines of Countly code to your application delegate:
<pre class="prettyprint">
#import "Countly.h"  // newly added line
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    [[Countly sharedInstance] startWithMessagingUsing:@"TYPE_HERE_YOUR_APP_KEY_GENERATED_IN_COUNTLY_ADMIN_DASHBOARD" withHost:@"http://TYPE_HERE_URL_WHERE_API_IS_HOSTED" andOptions:launchOptions]; // newly added line
    UIUserNotificationSettings* notificationSettings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeAlert | UIUserNotificationTypeBadge | UIUserNotificationTypeSound categories:nil];
    [[UIApplication sharedApplication] registerUserNotificationSettings:notificationSettings];
    
    // your code

    return YES;
}

- (void)application:(UIApplication *)application didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings {
    [application registerForRemoteNotifications];
}

- (void) application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    [[Countly sharedInstance] didRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
}

- (void) application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
    [[Countly sharedInstance] didFailToRegisterForRemoteNotifications];
}

</pre>
`startWithMessagingUsing:withHost:andOptions:`, `didRegisterForRemoteNotificationsWithDeviceToken:`, `didFailToRegisterForRemoteNotifications` are required for Countly Messaging to work properly. The latter Countly SDK method `handleRemoteNotification:` is the one that handles most of your Push Notification work for you. Here is what it does:

1. Analyzes notification in `userInfo` and if it's a Countly notification (has `"c"` dictionary in `userInfo`), processes it and returns `TRUE`. Otherwise, or if notification analysis says that you're responsible for message processing (see 'Silent' switch below), it returns `FALSE`.
2. Automatically makes callbacks to Countly Messaging server to calculate number of push notifications open and number of notifications with positive reactions.
3. Processes common types of notifications automagically. You don't have to do anything.
    * It displays `UIAlertView` when new message arrives and your app is in foreground.
    * It displays `UIAlertView` when new message arrives and your app is terminated or in background, but launched by tapping push notification with action (see link, app update and app review below).
    * It also displays special kinds of `UIAlertView`:
        * For notifications with **links** (you ask user to open a link to some blog post, for instance);
        * For **app update** notifications (you ask user to update the app, and pressing OK button takes a user to the app update page of App Store);
        * For **app review** notifications (you ask user to review the app, and pressing OK button takes a user to the app review page of App Store).
    * Doesn't do anything except for 'message open' callback to Countly Messaging server if you specify 'Silent' switch in dashboard. This effectively sets `content-available` to `true` in your message so you could process it in `application:didReceiveRemoteNotification:fetchCompletionHandler` method to do some background processing. And, in this case `handleRemoteNotification:` returns `FALSE`.
4.  Still lets you process push notifications as you whish in any of three application delegate methods. You can even disable Countly processing for all notifications, just don't call `handleRemoteNotification:` and pass nil as options in `startWithMessagingUsing:forHost:andOptions:`. But in this case don't forget to call `[[Countly sharedInstance] recordPushOpenForDictionary:` and `[[Countly sharedInstance] recordPushActionForDictionary:` with `"c"` dictionary from notification `userInfo` if you want to have correct metrics in dashboard.

### Push Notifications Localization
While push notifications in Countly Messaging are properly localized, there is still space for localization in the way notifications are displayed. By default, Countly uses your app name for a title of notification alert and following english words for alert button names: Cancel, OK, Open, Update, Review. If you want to customize them, there is a handy method `handleRemoteNotification:withButtonTitles:` which you can use instead of `handleRemoteNotification:` and provide `NSArray` of `NSString`s in the same order they are listed above.



### Other resources ###

Check Countly Server source code here: 

- [Countly Server](https://github.com/Countly/countly-server)

There are also other Countly SDK repositories below:

- [Countly iOS SDK](https://github.com/Countly/countly-sdk-ios)
- [Countly Android SDK](https://github.com/Countly/countly-sdk-android)
- [Countly Windows Phone SDK](https://github.com/Countly/countly-sdk-windows-phone)
- [Countly Blackberry Webworks SDK](https://github.com/Countly/countly-sdk-blackberry-webworks)
- [Countly Blackberry Cascades SDK](https://github.com/craigmj/countly-sdk-blackberry10-cascades) (Community supported)
- [Countly Appcelerator Titanium SDK](https://github.com/euforic/Titanium-Count.ly) (Community supported)
- [Countly Unity3D SDK](https://github.com/Countly/countly-sdk-unity) (Community supported)

##How can I help you with your efforts?
Glad you asked. We need ideas, feedbacks and constructive comments. All your suggestions will be taken care with upmost importance. 

We are on [Twitter](http://twitter.com/gocountly) and [Facebook](http://www.facebook.com/Countly) if you would like to keep up with our fast progress!

For community support page, see [http://support.count.ly](http://support.count.ly "Countly Support").
