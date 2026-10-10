#!/usr/bin/env node
// Convert the vendored A2UI conformance cases (a2ui/conformance/*.yaml) to JSON
// (a2ui/conformance/json/*.json) so every Elpian engine — TypeScript, Dart,
// Kotlin, Swift — can read them without a YAML parser.
//
//   node a2ui/scripts/conformance-to-json.mjs           # (re)write the JSON files
//   node a2ui/scripts/conformance-to-json.mjs --check   # exit 1 when they are stale
//
// The YAML parser is the `yaml` package, a devDependency of the native/
// workspace (run `npm install` in native/ first). Output is the parsed YAML
// document verbatim (an array of cases), pretty-printed with two spaces and a
// trailing newline, so the files diff cleanly.
import { createRequire } from 'node:module';
import { readFileSync, readdirSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const repo = join(here, '..', '..');
const source = join(repo, 'a2ui', 'conformance');
const target = join(source, 'json');
const require = createRequire(join(repo, 'native', 'package.json'));
const YAML = require('yaml');

const check = process.argv.includes('--check');
let stale = 0;
if (!check) mkdirSync(target, { recursive: true });
for (const file of readdirSync(source).filter((f) => f.endsWith('.yaml')).sort()) {
  const doc = YAML.parse(readFileSync(join(source, file), 'utf8'), { merge: false });
  const name = file.replace(/\.yaml$/, '.json');
  const out = join(target, name);
  const text = JSON.stringify(doc, null, 2) + '\n';
  if (check) {
    if (!existsSync(out) || readFileSync(out, 'utf8') !== text) {
      console.error(`stale: ${out}`);
      stale++;
    }
  } else {
    writeFileSync(out, text);
    console.log(`${file} -> json/${name} (${Array.isArray(doc) ? doc.length : 0} cases)`);
  }
}
if (check && stale) {
  console.error('run: node a2ui/scripts/conformance-to-json.mjs');
  process.exit(1);
}
