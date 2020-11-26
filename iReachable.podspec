#
# Be sure to run `pod lib lint iReachable.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'iReachable'
  s.version          = '0.1.0'
  s.summary          = 'iReachable is the tools check the (WWAN\WiFi) is available.'
  s.homepage         = 'https://github.com/ws00801526/iReachable'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'ws00801526' => '3057600441@qq.com' }
  s.source           = { :git => 'https://github.com/ws00801526/iReachable.git', :tag => s.version.to_s }
  s.swift_version    = '5.0'
  s.ios.deployment_target = '10.0'
  s.source_files = 'iReachable/Classes/**/*'
  s.frameworks = 'Foundation', 'SystemConfiguration', 'CoreTelephony'
end
