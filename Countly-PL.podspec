Pod::Spec.new do |s|
  s.name = 'Countly-PL'
  s.version = '22.09.0'
  s.license = { :type => 'MIT', :file => 'LICENSE.md' }
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
    core.public_header_files = 'Countly.h', 'CountlyUserDetails.h', 'CountlyConfig.h', 'CountlyFeedbackWidget.h'
    core.preserve_path = 'countly_dsym_uploader.sh'
    core.ios.frameworks = ['Foundation', 'UIKit', 'UserNotifications', 'CoreLocation', 'WebKit', 'CoreTelephony', 'WatchConnectivity']
  end

  s.subspec 'NotificationService' do |ns|
    ns.source_files = 'CountlyNotificationService.{m,h}'
    ns.ios.deployment_target = '10.0'
    ns.ios.frameworks = ['Foundation', 'UserNotifications']
  end

  s.subspec 'PL' do |pl|
    pl.platform = :ios
    pl.dependency 'Countly/Core'
    pl.dependency 'PLCrashReporter', '~> 1'

    # It is not possible to set static_framework attribute on subspecs.
    # So, we have to set it on main spec.
    # But it affects the main spec even when this subspec is not used.
    # Asked this on CocoaPods GitHub page: https://github.com/CocoaPods/CocoaPods/issues/7355#issuecomment-619261908
    s.static_framework = true
  end

end
