#!/usr/bin/env node
/**
 * Copies the @elpian/web assets (icon font, Elpian VM and QuickJS runtimes)
 * into the Expo app's public/ folder, where `expo start --web` and
 * `expo export --platform web` serve them. Run from the app's root:
 *
 *   npx elpian-expo-web-assets [dest]     (default: public/elpian)
 *
 * A different dest needs a matching configureElpianWeb({ assetBase }).
 */
import { cpSync, existsSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';

const dest = resolve(process.argv[2] ?? join('public', 'elpian'));
// Resolve @elpian/web the way the app does (falling back to this package's copy).
const require = createRequire(join(process.cwd(), 'package.json'));
let pkg;
try {
  pkg = dirname(require.resolve('@elpian/web/package.json'));
} catch {
  pkg = dirname(createRequire(import.meta.url).resolve('@elpian/web/package.json'));
}
const src = join(pkg, 'assets');
if (!existsSync(src)) {
  console.error(`@elpian/expo: ${src} not found (is @elpian/web built?)`);
  process.exit(1);
}
cpSync(src, dest, { recursive: true });
console.log(`@elpian/expo: @elpian/web assets copied to ${dest}`);
