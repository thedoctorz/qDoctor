Pod::Spec.new do |s|
  s.name             = 'applemap'
  s.version          = '1.0.0'
  s.summary          = 'The system map on Apple platforms, as a Flutter widget'
  s.description      = <<~DESC
    A thin MapKit platform view: basemap, annotations, camera and the system
    location dot. No API key, no tile server, no account — MapKit is part of
    the OS.
  DESC
  s.homepage         = 'https://github.com/apfxtech'
  # The package's own copy, as flipperlib does it. A path up and out of the
  # module resolves from here but not from the symlink CocoaPods installs the
  # pod under, which is where the "license file does not resolve" warning came
  # from.
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'apfxtech' => 'aperturefoxtechnology@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.frameworks       = 'MapKit'

  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
  }
end
