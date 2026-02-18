Pod::Spec.new do |s|
  s.name             = 'rust_lib_elpian_vm'
  s.version          = '0.0.1'
  s.summary          = 'Elpian VM Rust library for Flutter (macOS)'
  s.description      = <<-DESC
Flutter Rust Bridge integration for the Elpian sandboxed VM.
                       DESC
  s.homepage         = 'https://github.com/aspect/elpian'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Elpian' => 'dev@elpian.io' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'

  s.osx.deployment_target = '10.14'

  s.dependency 'FlutterMacOS'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'

  s.script_phase = {
    :name => 'Build Rust library',
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../rust elpian_vm',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    :output_files => ["${BUILT_PRODUCTS_DIR}/libelpian_vm.a"],
  }
end
