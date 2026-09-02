Pod::Spec.new do |s|
  s.name             = 'rust_lib_elpian_vm'
  s.version          = '0.0.1'
  s.summary          = 'Elpian VM Rust library for Flutter'
  s.description      = <<-DESC
The Elpian sandboxed VM, built from rust/crates/elpian-vm and linked
into the app.
                       DESC
  s.homepage         = 'https://github.com/aspect/elpian'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Elpian' => 'dev@elpian.io' }
  s.source           = { :path => '.' }
  # An ffiPlugin ships no Objective-C: the Dart side reaches the Rust
  # library through dart:ffi. There is nothing to compile here, only a
  # static library to build and link.
  s.source_files     = ''

  s.ios.deployment_target = '12.0'

  s.dependency 'Flutter'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # Build the Rust static library before compiling, and link it.
  #
  # This used to invoke `../cargokit/build_pod.sh`, a directory that has never
  # existed in this repository, so the ios build could not succeed. The
  # script below is self-contained: it builds every architecture Xcode asks
  # for and lipos them into one library.
  s.script_phase = {
    :name => 'Build the Elpian VM',
    :script => 'bash "$PODS_TARGET_SRCROOT/../tool/build_apple.sh" ios "$BUILT_PRODUCTS_DIR"',
    :execution_position => :before_compile,
    :input_files => ['$(PODS_TARGET_SRCROOT)/../tool/build_apple.sh'],
    :output_files => ['$(BUILT_PRODUCTS_DIR)/libelpian_vm.a'],
  }

  s.vendored_libraries = 'libelpian_vm.a'
  s.libraries = 'elpian_vm'
  s.xcconfig = { 'OTHER_LDFLAGS' => '-L"$(BUILT_PRODUCTS_DIR)" -lelpian_vm' }
end
