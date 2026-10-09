/**
 * Flutter painting values → CSS, with Flutter's geometry: gradients are
 * remapped so a linear gradient runs exactly from `begin` to `end` within the
 * box (CSS's gradient line is defined differently), radial radii are fractions
 * of the shortest side, sweeps start at 3 o'clock, and shadow blur radii are
 * converted from Flutter's `blurRadius` to the CSS blur length.
 */
import { toCssColor, type Alignment, type Border, type BorderRadius, type BoxShadow, type Color, type Filter, type Gradient, type TextShadow, type TextStyleSpec } from '../lib.js';

export const css = toCssColor;

/** Flutter's `convertRadiusToSigma` (blurRadius·0.57735 + 0.5) expressed as a CSS blur length (2σ). */
export function blurLength(blurRadius: number): number {
  return blurRadius > 0 ? 2 * (blurRadius * 0.57735 + 0.5) : 0;
}

function stopsOf(g: Gradient): number[] {
  if (g.stops && g.stops.length === g.colors.length) return g.stops;
  const n = g.colors.length;
  return g.colors.map((_, i) => (n > 1 ? i / (n - 1) : 0));
}

const point = (a: Alignment | undefined, fallback: Alignment, w: number, h: number) => {
  const al = a ?? fallback;
  return { x: ((al.x + 1) / 2) * w, y: ((al.y + 1) / 2) * h };
};

/** One gradient as a CSS `background-image` layer for a box of [w]×[h]. */
export function gradientCss(g: Gradient, w: number, h: number): string {
  const stops = stopsOf(g);
  const W = Math.max(w, 0.0001);
  const H = Math.max(h, 0.0001);
  if (g.kind === 'linear') {
    const p0 = point(g.begin, { x: -1, y: 0 }, W, H);
    const p1 = point(g.end, { x: 1, y: 0 }, W, H);
    let dx = p1.x - p0.x;
    let dy = p1.y - p0.y;
    if (dx === 0 && dy === 0) dx = 1;
    // CSS: angle measured clockwise from "to top"; direction (sin θ, -cos θ).
    const theta = Math.atan2(dx, -dy);
    const dirX = Math.sin(theta);
    const dirY = -Math.cos(theta);
    const len = Math.abs(W * dirX) + Math.abs(H * dirY);
    const cx = W / 2;
    const cy = H / 2;
    const startX = cx - (dirX * len) / 2;
    const startY = cy - (dirY * len) / 2;
    const t = (p: { x: number; y: number }) => ((p.x - startX) * dirX + (p.y - startY) * dirY) / len;
    const t0 = t(p0);
    const t1 = t(p1);
    const list = g.colors.map((c, i) => `${css(c)} ${pct(t0 + stops[i] * (t1 - t0))}`).join(', ');
    return `${g.repeat ? 'repeating-' : ''}linear-gradient(${deg(theta)}, ${list})`;
  }
  if (g.kind === 'radial') {
    const c = point(g.center, { x: 0, y: 0 }, W, H);
    const r = Math.max(0.0001, (g.radius ?? 0.5) * Math.min(W, H));
    const list = g.colors.map((col, i) => `${css(col)} ${px(stops[i] * r)}`).join(', ');
    return `${g.repeat ? 'repeating-' : ''}radial-gradient(circle ${px(r)} at ${px(c.x)} ${px(c.y)}, ${list})`;
  }
  // Sweep: Flutter's 0 is 3 o'clock, CSS conic's 0 is 12 o'clock.
  const c = point(g.center, { x: 0, y: 0 }, W, H);
  const start = g.startAngle ?? 0;
  const end = g.endAngle ?? Math.PI * 2;
  const list = g.colors.map((col, i) => `${css(col)} ${deg(stops[i] * (end - start))}`).join(', ');
  return `${g.repeat ? 'repeating-' : ''}conic-gradient(from ${deg(start + Math.PI / 2)} at ${px(c.x)} ${px(c.y)}, ${list})`;
}

export function px(v: number): string {
  return `${round(v)}px`;
}
function pct(v: number): string {
  return `${round(v * 100)}%`;
}
function deg(rad: number): string {
  return `${round((rad * 180) / Math.PI)}deg`;
}
export function round(v: number): number {
  return Math.round(v * 1000) / 1000;
}

export function radiusCss(r: BorderRadius | null | undefined): string {
  if (!r) return '';
  return `${px(r.topLeft)} ${px(r.topRight)} ${px(r.bottomRight)} ${px(r.bottomLeft)}`;
}

export function applyBorder(style: CSSStyleDeclaration, b: Border | null | undefined): void {
  if (!b) {
    style.border = '';
    return;
  }
  const side = (s: Border['top']) => (s.style === 'none' || s.width <= 0 ? 'none' : `${px(s.width)} ${s.style} ${css(s.color)}`);
  style.borderTop = side(b.top);
  style.borderRight = side(b.right);
  style.borderBottom = side(b.bottom);
  style.borderLeft = side(b.left);
}

export function boxShadowCss(shadows: BoxShadow[] | null | undefined): string {
  if (!shadows || !shadows.length) return '';
  return shadows.map((s) => `${s.inset ? 'inset ' : ''}${px(s.dx)} ${px(s.dy)} ${px(blurLength(s.blur))} ${px(s.spread)} ${css(s.color)}`).join(', ');
}

export function textShadowCss(shadows: TextShadow[] | null | undefined): string {
  if (!shadows || !shadows.length) return '';
  return shadows.map((s) => `${px(s.dx)} ${px(s.dy)} ${px(blurLength(s.blur))} ${css(s.color)}`).join(', ');
}

export function filterCss(f: Filter | null | undefined): string {
  if (!f) return '';
  const out: string[] = [];
  if (f.blur != null) out.push(`blur(${px(f.blur)})`);
  if (f.brightness != null) out.push(`brightness(${f.brightness})`);
  if (f.contrast != null) out.push(`contrast(${f.contrast})`);
  if (f.grayscale != null) out.push(`grayscale(${f.grayscale})`);
  if (f.hueRotate != null) out.push(`hue-rotate(${f.hueRotate}deg)`);
  if (f.invert != null) out.push(`invert(${f.invert})`);
  if (f.saturate != null) out.push(`saturate(${f.saturate})`);
  if (f.sepia != null) out.push(`sepia(${f.sepia})`);
  if (f.opacity != null) out.push(`opacity(${f.opacity})`);
  if (f.dropShadow) out.push(`drop-shadow(${px(f.dropShadow.dx)} ${px(f.dropShadow.dy)} ${px(blurLength(f.dropShadow.blur))} ${css(f.dropShadow.color)})`);
  return out.join(' ');
}

/** The CSS `mix-blend-mode` for a Flutter / CSS blend-mode name. */
export function blendCss(mode: string | null | undefined): string {
  if (!mode) return '';
  const m = mode.replace(/([A-Z])/g, '-$1').toLowerCase();
  const known = ['normal', 'multiply', 'screen', 'overlay', 'darken', 'lighten', 'color-dodge', 'color-burn', 'hard-light', 'soft-light', 'difference', 'exclusion', 'hue', 'saturation', 'color', 'luminosity', 'plus-lighter'];
  if (m === 'plus' || m === 'lighter') return 'plus-lighter';
  if (m === 'src-over') return 'normal';
  return known.includes(m) ? m : '';
}

// ---------------------------------------------------------------------------
// Fonts
// ---------------------------------------------------------------------------

/** Flutter web's default family stack (Roboto first). */
export const SANS = 'Roboto, system-ui, -apple-system, "Segoe UI", "Helvetica Neue", Arial, sans-serif';
export const ICON_FAMILY = 'ElpianMaterialIcons';

export function fontFamilyCss(family: string | null | undefined): string {
  if (family == null) return SANS;
  if (family === 'serif') return 'Georgia, "Times New Roman", serif';
  if (family === 'monospace') return '"Roboto Mono", Menlo, Consolas, "Liberation Mono", monospace';
  if (family === 'icons') return ICON_FAMILY;
  return `${/[\s,"']/.test(family) && !family.includes(',') ? JSON.stringify(family) : family}, ${SANS}`;
}

/** Inline styles for one text span. */
export function spanStyle(s: TextStyleSpec, scale = 1): string {
  const parts: string[] = [
    `color:${css(s.color)}`,
    `font-size:${px(s.fontSize * scale)}`,
    `font-weight:${s.fontWeight}`,
    `font-style:${s.italic ? 'italic' : 'normal'}`,
    `font-family:${fontFamilyCss(s.fontFamily)}`,
    `letter-spacing:${px(s.letterSpacing * scale)}`,
    `word-spacing:${px(s.wordSpacing * scale)}`,
    `line-height:${s.height != null ? round(s.height) : 'normal'}`,
  ];
  const deco: string[] = [];
  if (s.decoration & 1) deco.push('underline');
  if (s.decoration & 2) deco.push('overline');
  if (s.decoration & 4) deco.push('line-through');
  if (deco.length) {
    parts.push(`text-decoration-line:${deco.join(' ')}`);
    if (s.decorationColor != null) parts.push(`text-decoration-color:${css(s.decorationColor)}`);
    if (s.decorationStyle) parts.push(`text-decoration-style:${s.decorationStyle === 'double' ? 'double' : s.decorationStyle === 'dotted' ? 'dotted' : s.decorationStyle === 'dashed' ? 'dashed' : s.decorationStyle === 'wavy' ? 'wavy' : 'solid'}`);
    if (s.decorationThickness != null) parts.push(`text-decoration-thickness:${round(s.decorationThickness)}em`);
  }
  const shadow = textShadowCss(s.shadows);
  if (shadow) parts.push(`text-shadow:${shadow}`);
  if (s.background != null) parts.push(`background-color:${css(s.background)}`);
  if (s.baselineShift) parts.push(`position:relative`, `top:${px(s.baselineShift)}`);
  return parts.join(';');
}

export function colorOrNull(c: Color | null | undefined): string {
  return c == null ? '' : css(c);
}
