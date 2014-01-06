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

Note: If your project uses automatic reference counting (ARC), you should disable it for the 
sources `Countly.m`, `Countly_OpenUDID.m` and `CountlyDB.m`:

1. Select your project
2. Select the **Build Phases** tab
3. Open **Compile Sources** tab
4. Double click `Countly.m`, `Countly_OpenUDID.m` and `CountlyDB.m` and add `-fno-objc-arc` flag

Note: Before upgrading to a new SDK, do not forget to remove the existing, older SDK from your project.


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
