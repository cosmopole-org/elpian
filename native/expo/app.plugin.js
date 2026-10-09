/**
 * Expo config plugin for @elpian/expo.
 *
 * Android:
 *  - adds the Maven repository this package ships (android/maven: the
 *    dev.elpian:elpian-core / elpian-android AARs) to every project, since the
 *    app resolves the library's dependencies with its own repositories;
 *  - enables core library desugaring in the app (the WASM engine, Chicory,
 *    uses Java 11+ library APIs, and minSdk is 24).
 * iOS needs nothing beyond `pod install` (see ios/ElpianExpo.podspec).
 */
const path = require('path');
const { withAppBuildGradle, withProjectBuildGradle, createRunOncePlugin } = require('expo/config-plugins');

/** android/maven of this package, relative to the app's android/ folder. */
function mavenPath(androidRoot) {
  const dir = path.join(__dirname, 'android', 'maven');
  return path.relative(androidRoot, dir).split(path.sep).join('/');
}

const REPO_MARKER = '// @elpian/expo maven repository';
const DESUGAR_MARKER = '// @elpian/expo desugaring';

function withElpianRepository(config) {
  return withProjectBuildGradle(config, (cfg) => {
    if (cfg.modResults.language !== 'groovy') throw new Error('@elpian/expo: only Groovy android/build.gradle is supported');
    let src = cfg.modResults.contents;
    if (!src.includes(REPO_MARKER)) {
      const rel = mavenPath(cfg.modRequest.platformProjectRoot);
      const repo = `        ${REPO_MARKER}\n        maven { url(new File(rootDir, "${rel}")) }\n`;
      if (/allprojects\s*\{\s*repositories\s*\{/.test(src)) {
        src = src.replace(/allprojects\s*\{\s*repositories\s*\{\n?/, (m) => `${m}${repo}`);
      } else {
        src += `\nallprojects {\n    repositories {\n${repo}    }\n}\n`;
      }
      cfg.modResults.contents = src;
    }
    return cfg;
  });
}

function withElpianDesugaring(config) {
  return withAppBuildGradle(config, (cfg) => {
    if (cfg.modResults.language !== 'groovy') throw new Error('@elpian/expo: only Groovy android/app/build.gradle is supported');
    let src = cfg.modResults.contents;
    if (!src.includes(DESUGAR_MARKER)) {
      src = src.replace(/android\s*\{\n/, (m) => `${m}    ${DESUGAR_MARKER}\n    compileOptions { coreLibraryDesugaringEnabled true }\n`);
      src = src.replace(/dependencies\s*\{\n/, (m) => `${m}    coreLibraryDesugaring "com.android.tools:desugar_jdk_libs:2.1.3" ${DESUGAR_MARKER}\n`);
      cfg.modResults.contents = src;
    }
    return cfg;
  });
}

const withElpian = (config) => withElpianDesugaring(withElpianRepository(config));

module.exports = createRunOncePlugin(withElpian, '@elpian/expo', '1.0.0');
