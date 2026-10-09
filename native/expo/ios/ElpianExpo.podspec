require 'json'

package = JSON.parse(File.read(File.join(__dir__, '..', 'package.json')))

# @elpian/expo on iOS: the Swift Elpian core (ElpianCore) and its UIKit host
# (Elpian), compiled into this pod from ios/vendor (staged by
# `npm run prepare-native` from native/ios), plus the Elpian VM's C ABI.
Pod::Spec.new do |s|
  s.name           = 'ElpianExpo'
  s.version        = package['version']
  s.summary        = package['description']
  s.license        = package['license']
  s.author         = 'Elpian'
  s.homepage       = 'https://github.com/cosmopole-org/elpian'
  s.platforms      = { :ios => '15.1' }
  s.swift_version  = '5.9'
  s.source         = { git: 'https://github.com/cosmopole-org/elpian.git' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  s.source_files = [
    '*.swift',
    'vendor/ElpianCore/**/*.swift',
    'vendor/Elpian/**/*.swift',
    'vendor/include/elpian_vm.h',
  ]
  s.public_header_files = 'vendor/include/elpian_vm.h'
  s.resources = ['vendor/fonts/MaterialIcons-Regular.ttf']
  s.frameworks = 'UIKit', 'CoreGraphics', 'CoreText', 'QuartzCore', 'AVFoundation', 'AVKit', 'WebKit', 'JavaScriptCore', 'CoreImage'

  # The Elpian VM (Rust) — built by native/ios/scripts/build-rust.sh.
  if File.exist?(File.join(__dir__, 'vendor', 'ElpianVM.xcframework'))
    s.vendored_frameworks = 'vendor/ElpianVM.xcframework'
    s.pod_target_xcconfig = { 'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => '$(inherited) ELPIAN_VM ELPIAN_SINGLE_MODULE' }
  else
    s.pod_target_xcconfig = { 'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => '$(inherited) ELPIAN_SINGLE_MODULE' }
  end

  # WASM guests run on WasmKit (Swift Package Manager only).
  if respond_to?(:spm_dependency, true)
    spm_dependency(s,
      url: 'https://github.com/swiftwasm/WasmKit.git',
      requirement: { kind: 'upToNextMinorVersion', minimumVersion: '0.2.0' },
      products: ['WasmKit']
    )
  end
end
