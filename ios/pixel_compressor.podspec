#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint pixel_compressor.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'pixel_compressor'
  s.version          = '0.0.1'
  s.summary          = 'pixel_compressor Flutter plugin — iOS support.'
  s.description      = <<-DESC
Native image and video compression for Flutter, built on AVFoundation,
VideoToolbox, and ImageIO — no FFmpeg, no third-party native dependencies.
                       DESC
  s.homepage         = 'https://github.com/devamitkumartiwari/pixel_compressor'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Amit Kumar Tiwari' => 'amtechnovation@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'pixel_compressor/Sources/pixel_compressor/**/*.swift'
  s.dependency 'Flutter'
  s.platform = :ios, '16.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  s.resource_bundles = {'pixel_compressor_privacy' => ['pixel_compressor/Sources/pixel_compressor/PrivacyInfo.xcprivacy']}
end
