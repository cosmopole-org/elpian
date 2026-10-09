#!/usr/bin/env node
/**
 * Stages the native libraries this package ships:
 *  - android/maven: dev.elpian:elpian-core and dev.elpian:elpian-android,
 *    published from native/android (Gradle on PATH; the Android SDK in
 *    ANDROID_HOME or native/android/local.properties).
 *  - ios/vendor: the Swift sources of ElpianCore and Elpian, the C header of
 *    the Elpian VM and, when built (native/ios/scripts/build-rust.sh), its
 *    xcframework.
 *  - the Material Icons font for both.
 */
import { execFileSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, rmSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const pkg = resolve(here, '..');
const nativeRoot = resolve(pkg, '..');
const repoRoot = resolve(nativeRoot, '..');

// ---- Android ----
const maven = join(pkg, 'android', 'maven');
rmSync(maven, { recursive: true, force: true });
execFileSync('gradle', ['--no-daemon', '-q', `-Pelpian.repo=${maven}`, 'publish'], { cwd: join(nativeRoot, 'android'), stdio: 'inherit' });
console.log(`@elpian/expo: Android libraries published to ${maven}`);

// ---- iOS ----
const vendor = join(pkg, 'ios', 'vendor');
rmSync(vendor, { recursive: true, force: true });
mkdirSync(vendor, { recursive: true });
for (const target of ['ElpianCore', 'Elpian']) {
  const src = join(nativeRoot, 'ios', 'Sources', target);
  if (existsSync(src)) cpSync(src, join(vendor, target), { recursive: true, filter: (p) => !p.endsWith('.md') });
}
mkdirSync(join(vendor, 'include'), { recursive: true });
cpSync(join(repoRoot, 'rust', 'crates', 'elpian-ffi', 'include', 'elpian_vm.h'), join(vendor, 'include', 'elpian_vm.h'));
const xcframework = join(nativeRoot, 'ios', 'Frameworks', 'ElpianVM.xcframework');
if (existsSync(xcframework)) cpSync(xcframework, join(vendor, 'ElpianVM.xcframework'), { recursive: true });
else console.warn('@elpian/expo: ElpianVM.xcframework not built (native/ios/scripts/build-rust.sh); the Elpian VM runtime will report itself unavailable on iOS');
mkdirSync(join(vendor, 'fonts'), { recursive: true });
cpSync(join(nativeRoot, 'assets', 'fonts', 'MaterialIcons-Regular.ttf'), join(vendor, 'fonts', 'MaterialIcons-Regular.ttf'));
console.log(`@elpian/expo: iOS sources staged in ${vendor}`);
