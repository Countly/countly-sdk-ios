##What's Countly?
Countly is an innovative, real-time, open source mobile analytics application. It collects data 
from mobile devices, and visualizes this information to analyze mobile application usage and end-user behavior. 
There are two parts of Countly: the server that collects and analyzes data, and mobile SDK that sends this 
data (for iOS, Android and Blackberry). Both parts are open source.


Countly Server;

- [Countly Server (countly-server)](https://github.com/Countly/countly-server)

Other Countly SDK repositories;

- [Countly Android SDK (countly-sdk-android)](https://github.com/Countly/countly-sdk-android)
- [Countly Blackberry Webworks SDK (countly-sdk-blackberry-webworks)](https://github.com/Countly/countly-sdk-blackberry-webworks)

##Installing iOS SDK

Countly iOS SDK includes necessary tools to track your application. In order to integrate SDK to your application, follow these steps.

1. Download Countly iOS SDK.
2. Add these files to your project under Xcode: `Countly.h` `Countly.m` `Countly_OpenUDID.h` `Countly_OpenUDID.m`
3. In the project navigator, select your project
4. Select your project
5. Select the **Build Phases** tab
6. Open **Link Binaries With Libraries** expander
7. Click the **+** button
8. Select CoreTelephony.framework, select **Optional** (instead of Required)
9. *(optional)* Drag and drop the added framework to the **Frameworks** group
10. In your application delegate, import `Countly.h`
and inside `application:didFinishLaunchingWithOptions:`  add the line;
`[[Countly sharedInstance] start:@"YOUR_APP_KEY" withHost:@"http://YOUR_API_HOST.com"];` at the beginning of the function.

Note that if you use Countly Cloud, you must set withHost parameter to http://cloud.count.ly for step 10.

It should finally look like this:

<pre class="prettyprint">
#import "Countly.h"  // newly added line
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
[[Countly sharedInstance] start:@"TYPE_HERE_YOUR_APP_KEY_GENERATED_IN_COUNTLY_ADMIN_DASHBOARD" withHost:@"http://TYPE_HERE_URL_WHERE_API_IS_HOSTED"]; // newly added line
// your code
}
</pre>

Note: If your project uses automatic reference counting (ARC), you should disable it for the sources `Countly_OpenUDID.m` and `Countly.m`:

1. Select your project
2. Select the **Build Phases** tab
3. Open **Compile Sources** tab
4. Double click `Countly.m` and `Countly_OpenUDID.m` and add `-fno-objc-arc` flag

Note: Before upgrading to a new SDK, do not forget to remove the existing, older SDK from your project.

##How can I help you with your efforts?
Glad you asked. We need ideas, feedbacks and constructive comments. All your suggestions will be taken care with upmost importance.

We are on [Twitter](http://twitter.com/gocountly) and [Facebook](http://www.facebook.com/Countly) if you would like to keep up with our fast progress!

##Home

[http://count.ly](http://count.ly "Countly")

##Community & support

[http://support.count.ly](http://support.count.ly "Countly Support")