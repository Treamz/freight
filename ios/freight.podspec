#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint freight.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'freight'
  s.version          = '0.1.0'
  s.summary          = 'Deliver large assets outside your app bundle: iOS Managed Background Assets and Play Asset Delivery behind one Dart API.'
  s.description      = <<-DESC
Deliver large assets outside your app bundle: iOS Managed Background Assets and Play Asset Delivery behind one Dart API.
                       DESC
  s.homepage         = 'https://github.com/Treamz/freight'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Ivan Cernokniznikov' => 'chrnknzhnkv@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'freight/Sources/freight/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.9'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'freight_privacy' => ['freight/Sources/freight/PrivacyInfo.xcprivacy']}
end
