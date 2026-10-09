// Copy the runtime assets next to the package and bundle a single-file ESM build.
//
//   assets/fonts/MaterialIcons-Regular.ttf        (Icon widget font)
//   assets/runtime/wasm/elpian_vm/…               (Elpian VM, wasm-bindgen)
//   assets/runtime/vendor/quickjs-emscripten.*    (QuickJS guests)
//   dist/elpian-web.js                            (engine + DOM host, one module)
import { build } from 'esbuild';
import { cpSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = join(dirname(fileURLToPath(import.meta.url)), '..');
const repo = join(here, '..', '..');
const assets = join(here, 'assets');
mkdirSync(join(assets, 'fonts'), { recursive: true });
cpSync(join(here, '..', 'assets', 'fonts'), join(assets, 'fonts'), { recursive: true });
const runtime = join(repo, 'flutter', 'assets', 'web_runtime');
cpSync(join(runtime, 'wasm'), join(assets, 'runtime', 'wasm'), { recursive: true });
cpSync(join(runtime, 'vendor'), join(assets, 'runtime', 'vendor'), { recursive: true });

await build({
  entryPoints: [join(here, 'src', 'index.ts')],
  bundle: true,
  format: 'esm',
  target: 'es2020',
  outfile: join(here, 'dist', 'elpian-web.js'),
  sourcemap: true,
  logLevel: 'warning',
});
