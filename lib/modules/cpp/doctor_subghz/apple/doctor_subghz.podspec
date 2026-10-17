Pod::Spec.new do |s|
  s.name             = 'doctor_subghz'
  s.version          = '0.0.1'
  s.summary          = 'Our Hitag2Hell engine (Metal GPU + CPU) as a Dart FFI lib.'
  s.description      = 'Canonical Hitag2Hell recovery mirroring the iOS app: '\
                       'Metal GPU search on Apple, CPU fallback elsewhere.'
  s.homepage         = 'https://localhost'
  s.license          = { :type => 'GPLv3' }
  s.author           = { 'doctor' => 'noreply@localhost' }
  s.source           = { :path => '.' }
  s.source_files     = 'doctor_subghz_unity.m'
  s.requires_arc     = true
  s.frameworks       = 'Metal', 'Foundation'
  s.ios.dependency 'Flutter'
  s.ios.deployment_target = '12.0'
  s.osx.dependency 'FlutterMacOS'
  s.osx.deployment_target = '10.15'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'GCC_C_LANGUAGE_STANDARD' => 'gnu11',
    'GCC_TREAT_WARNINGS_AS_ERRORS' => 'NO',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/.."',
    'OTHER_CFLAGS' => '-O3',
  }
end
