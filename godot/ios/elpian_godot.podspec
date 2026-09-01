#
# The iOS side of the embedded-Godot plugin.
#
# The Godot runtime itself (libgodot.ios + the elpian_godot GDExtension built for
# arm64 iOS) is NOT vendored here — it is a large binary build artifact, the
# counterpart of android/libs/godot-lib.template_release.aar. Until a host app
# links it, `Scene3D` renders its placeholder. See README.md.
#
Pod::Spec.new do |s|
  s.name             = 'elpian_godot'
  s.version          = '0.1.0'
  s.summary          = 'Embedded Godot 4 engine for Elpian Scene3D.'
  s.description      = <<-DESC
The iOS platform view and op transport behind Elpian's Scene3D widget.
                       DESC
  s.homepage         = 'https://github.com/elpian'
  s.license          = { :type => 'BSD-3-Clause' }
  s.author           = { 'Elpian' => 'noreply@elpian.dev' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Godot 4 requires Metal; the runtime, when linked, brings its own frameworks.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.0'
end
