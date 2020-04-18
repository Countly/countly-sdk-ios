Pod::Spec.new do |s|
  s.name = 'Countly'
  s.version = '20.04'
  s.license = { :type => 'MIT', :file => 'LICENSE.md' }
  s.summary  = 'Countly is an innovative, real-time, open source mobile analytics platform.'
  s.homepage = 'https://github.com/Countly/countly-sdk-ios'
  s.social_media_url = 'https://twitter.com/gocountly'
  s.author = {'Countly' => 'hello@count.ly'}
  s.source = { :git => 'https://github.com/Countly/countly-sdk-ios.git', :tag => s.version.to_s }
  s.source_files = '*.{h,m}'
  s.public_header_files = 'Countly.h', 'CountlyUserDetails.h', 'CountlyConfig.h'
  s.preserve_path = 'countly_dsym_uploader.sh'
  s.requires_arc = true
  s.default_subspecs = :none
  s.ios.deployment_target = '8.0'
  s.osx.deployment_target = '10.10'
  s.watchos.deployment_target = '2.0'
  s.tvos.deployment_target = '9.0'

  s.subspec 'NotificationService' do |ns|
    ns.source_files = 'CountlyNotificationService.{m,h}'
  end

end
