// Shared harness for the A2UI node tests: a headless Platform (fixed-width
// text metrics, recorded view ops, manual frames, scripted fetchStream) and
// paths to the vendored A2UI files.
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

process.env.TZ = 'UTC';

export const here = dirname(fileURLToPath(import.meta.url));
export const repo = join(here, '..', '..', '..', '..');
export const a2uiDir = join(repo, 'a2ui');

export const lib = await import('../../dist/lib.js');

export function readJson(...parts) {
  return JSON.parse(readFileSync(join(...parts), 'utf8'));
}

export function conformance(name) {
  return readJson(a2uiDir, 'conformance', 'json', `${name}.json`);
}

export function examples() {
  const dir = join(a2uiDir, 'spec', 'catalogs', 'basic', 'examples');
  return readdirSync(dir)
    .filter((f) => f.endsWith('.json'))
    .sort()
    .map((f) => ({ file: f, ...readJson(dir, f) }));
}

/** A headless platform. `streams` scripts fetchStream: url → { chunks, status }. */
export class TestPlatform {
  name = 'test';
  ops = [];
  requests = [];
  logs = [];
  streamScript = null;
  now() {
    return Date.now();
  }
  setTimeout(cb, ms) {
    return setTimeout(cb, ms);
  }
  clearTimeout(h) {
    clearTimeout(h);
  }
  requestFrame() {
    return 0;
  }
  cancelFrame() {}
  commit(surface, ops) {
    this.ops.push(...ops);
  }
  measureText(spec, maxWidth) {
    const text = spec.spans.map((s) => s.text ?? '').join('');
    const size = spec.spans[0]?.style?.fontSize ?? 14;
    const charW = size * 0.5;
    const full = text.length * charW;
    const width = Number.isFinite(maxWidth) && spec.softWrap ? Math.min(full, maxWidth) : full;
    const lines = Number.isFinite(maxWidth) && maxWidth > 0 && spec.softWrap ? Math.max(1, Math.ceil(full / maxWidth)) : 1;
    return { width, height: lines * size * 1.2, baseline: size, lineCount: lines, didExceedMaxLines: false };
  }
  viewport() {
    return { width: 400, height: 800, devicePixelRatio: 1, safeArea: { top: 0, right: 0, bottom: 0, left: 0 }, locale: 'en-US', platform: 'web', isWeb: false, darkMode: false, textScale: 1 };
  }
  log(level, message) {
    this.logs.push(`${level}: ${message}`);
  }
  openUrl(url) {
    this.opened = url;
  }
  fetchStream(request, handlers) {
    this.requests.push(request);
    const script = this.streamScript?.(request) ?? { chunks: [] };
    let cancelled = false;
    (async () => {
      for (const c of script.chunks) {
        await new Promise((r) => setTimeout(r, 1));
        if (cancelled) return;
        handlers.onChunk(c);
      }
      if (script.error) handlers.onError(script.error);
      else handlers.onDone();
    })();
    return () => {
      cancelled = true;
    };
  }
}

export const platform = new TestPlatform();
lib.setPlatform(platform);

/** Render [node] on a fresh surface: lower, reconcile, lay out and composite one frame. */
let surfaces = 0;
export function renderOnSurface(node) {
  const surface = new lib.ElpianSurface(`test-${++surfaces}`);
  surface.setContent(node);
  surface.renderNow();
  const ops = surface.owner.flush(0);
  return { surface, ops };
}

/** Walk a node JSON tree. */
export function walk(node, fn) {
  fn(node);
  for (const c of node.children ?? []) walk(c, fn);
}
