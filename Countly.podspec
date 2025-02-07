Pod::Spec.new do |s|
  s.name = 'Countly'
  s.version = '25.1.1'
  s.license = { :type => 'MIT', :file => 'LICENSE' }
  s.summary  = 'Countly is an innovative, real-time, open source mobile analytics platform.'
  s.homepage = 'https://github.com/Countly/countly-sdk-ios'
  s.social_media_url = 'https://twitter.com/gocountly'
  s.author = {'Countly' => 'hello@count.ly'}
  s.source = { :git => 'https://github.com/Countly/countly-sdk-ios.git', :tag => s.version.to_s }

  s.requires_arc = true
  s.default_subspecs = 'Core'
  s.ios.deployment_target = '10.0'
  s.osx.deployment_target = '10.14'
  s.watchos.deployment_target = '4.0'
  s.tvos.deployment_target = '10.0'

  s.subspec 'Core' do |core|
    core.source_files = '*.{h,m}'
    core.public_header_files = 'Countly.h', 'CountlyUserDetails.h', 'CountlyConfig.h', 'CountlyFeedbackWidget.h', 'CountlyRCData.h', 'CountlyRemoteConfig.h', 'CountlyViewTracking.h', 'CountlyExperimentInformation.h', 'CountlyAPMConfig.h', 'CountlySDKLimitsConfig.h', 'Resettable.h', "CountlyCrashesConfig.h", "CountlyCrashData.h", "CountlyContentBuilder.h", "CountlyExperimentalConfig.h", "CountlyContentConfig.h", "CountlyFeedbacks.h"
    core.preserve_path = 'countly_dsym_uploader.sh'
    core.ios.frameworks = ['Foundation', 'UIKit', 'UserNotifications', 'CoreLocation', 'WebKit', 'CoreTelephony', 'WatchConnectivity']
  end

  s.subspec 'NotificationService' do |ns|
    ns.source_files = 'CountlyNotificationService.{m,h}'
    ns.ios.deployment_target = '10.0'
    ns.ios.frameworks = ['Foundation', 'UserNotifications']
  end

end
