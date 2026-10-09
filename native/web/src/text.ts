/**
 * Paragraphs: one function builds the DOM for a TextSpec, and the measurer
 * lays that same DOM out off-screen, so what the core measures is exactly what
 * the renderer paints (Flutter's TextPainter contract: width is the max
 * intrinsic width clamped to the constraint, height is the laid-out height,
 * baseline is the first line's alphabetic baseline).
 */
import type { TextMetrics, TextSpec } from '@elpian/native-core';
import { round, spanStyle } from './css.js';

const ALIGN: Record<TextSpec['align'], string> = { left: 'left', right: 'right', center: 'center', justify: 'justify', start: 'start', end: 'end' };

/** Paragraph-level styles. [width] is null for max-content layout. */
export function paragraphStyle(spec: TextSpec, width: number | null): string {
  const parts = [
    'margin:0',
    'padding:0',
    `text-align:${ALIGN[spec.align] ?? 'start'}`,
    `direction:${spec.direction}`,
    // Flutter wraps at word boundaries and breaks overlong words.
    spec.softWrap ? 'white-space:pre-wrap;overflow-wrap:break-word' : 'white-space:pre',
    `width:${width == null ? 'max-content' : `${round(width)}px`}`,
    '-webkit-font-smoothing:antialiased',
    'font-kerning:normal',
    'text-rendering:optimizeLegibility',
  ];
  if (spec.maxLines != null && spec.maxLines > 0) {
    parts.push('display:-webkit-box', '-webkit-box-orient:vertical', `-webkit-line-clamp:${spec.maxLines}`, 'overflow:hidden');
  } else if (spec.overflow === 'ellipsis' && !spec.softWrap) {
    parts.push('overflow:hidden', 'text-overflow:ellipsis');
  }
  if (spec.selectable) parts.push('user-select:text', '-webkit-user-select:text', 'cursor:text');
  else parts.push('user-select:none', '-webkit-user-select:none');
  return parts.join(';');
}

/** Fill [el] with the spans of [spec]; link spans carry `data-link`. */
export function fillParagraph(el: HTMLElement, spec: TextSpec, scale = 1): void {
  el.textContent = '';
  // Line height comes from the first span (the paragraph's strut).
  const first = spec.spans[0]?.style;
  if (first) {
    el.style.fontSize = `${round(first.fontSize * scale)}px`;
    el.style.lineHeight = first.height != null ? String(round(first.height)) : 'normal';
  }
  for (const span of spec.spans) {
    const s = document.createElement('span');
    s.setAttribute('style', spanStyle(span.style, scale));
    s.textContent = span.text;
    if (span.link != null) {
      s.dataset.link = span.link;
      s.style.cursor = 'pointer';
    }
    el.appendChild(s);
  }
  if (spec.overflow === 'fade' && !spec.softWrap) {
    el.style.maskImage = 'linear-gradient(to right, black 85%, transparent)';
    (el.style as any).webkitMaskImage = el.style.maskImage;
  }
}

// ---------------------------------------------------------------------------
// Measuring
// ---------------------------------------------------------------------------

let host: HTMLDivElement | null = null;
const cache = new Map<string, TextMetrics>();

function measureHost(): HTMLDivElement {
  if (host && host.isConnected) return host;
  host = document.createElement('div');
  host.setAttribute('aria-hidden', 'true');
  host.style.cssText = 'position:absolute;left:-100000px;top:0;visibility:hidden;pointer-events:none;contain:layout style;width:0;height:0;overflow:visible';
  document.body.appendChild(host);
  return host;
}

/** Forget cached metrics (fonts finished loading, text scale changed). */
export function clearTextCache(): void {
  cache.clear();
}

export function measureText(spec: TextSpec, maxWidth: number): TextMetrics {
  const bounded = Number.isFinite(maxWidth) && maxWidth >= 0;
  const key = JSON.stringify(spec) + '|' + (bounded ? round(maxWidth) : 'inf');
  const hit = cache.get(key);
  if (hit) return hit;
  const root = measureHost();

  // 1. Max-content width (the longest line with no wrapping beyond hard breaks).
  const intrinsic = layout(root, spec, null);
  let width = intrinsic.width;
  let metrics = intrinsic;
  // 2. Re-layout at the constraint when it is narrower and wrapping is on.
  if (bounded && intrinsic.width > maxWidth + 0.01) {
    if (spec.softWrap) {
      metrics = layout(root, spec, maxWidth);
      width = maxWidth;
    } else {
      width = maxWidth;
    }
  }
  // 3. maxLines: did the clamp cut anything?
  let exceeded = false;
  if (spec.maxLines != null && spec.maxLines > 0) {
    const unclamped = layout(root, { ...spec, maxLines: null }, bounded && spec.softWrap && intrinsic.width > maxWidth ? maxWidth : null);
    exceeded = unclamped.lineCount > spec.maxLines;
  } else if (!spec.softWrap && bounded && intrinsic.width > maxWidth + 0.01) {
    exceeded = spec.overflow !== 'visible';
  }
  const result: TextMetrics = {
    width: Math.ceil(width * 100) / 100,
    height: Math.ceil(metrics.height * 100) / 100,
    baseline: metrics.baseline,
    lineCount: spec.maxLines != null && spec.maxLines > 0 ? Math.min(metrics.lineCount, spec.maxLines) : metrics.lineCount,
    didExceedMaxLines: exceeded,
  };
  if (cache.size > 4000) cache.clear();
  cache.set(key, result);
  return result;
}

function layout(root: HTMLElement, spec: TextSpec, width: number | null): TextMetrics {
  const p = document.createElement('div');
  p.setAttribute('style', paragraphStyle(spec, width) + ';position:absolute;left:0;top:0');
  fillParagraph(p, spec);
  // A zero-size inline-block sits on the first line's baseline.
  const marker = document.createElement('span');
  marker.style.cssText = 'display:inline-block;width:0;height:0;vertical-align:baseline';
  p.insertBefore(marker, p.firstChild);
  root.appendChild(p);
  const rect = p.getBoundingClientRect();
  const baseline = marker.getBoundingClientRect().bottom - rect.top;
  let lineCount = 0;
  if (spec.spans.some((s) => s.text.length)) {
    const range = document.createRange();
    range.selectNodeContents(p);
    const tops = new Set<number>();
    for (const r of Array.from(range.getClientRects())) if (r.height > 0 && r.width >= 0) tops.add(Math.round(r.bottom));
    lineCount = Math.max(1, tops.size);
  } else {
    lineCount = 1;
  }
  root.removeChild(p);
  return { width: rect.width, height: rect.height, baseline: round(baseline), lineCount, didExceedMaxLines: false };
}
