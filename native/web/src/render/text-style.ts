/**
 * Text styles: the inheritable `TextStyle` used while lowering, its merge
 * rules (Flutter `TextStyle.merge` / `DefaultTextStyle`), font-family
 * resolution (`CSSProperties.resolveFontFamily`) and the conversion to the
 * wire [TextStyleSpec] platforms render with.
 */
import { M3, type Color } from '../css/color.js';
import type { CSSStyle } from '../css/style.js';
import type { TextShadow } from '../css/types.js';
import type { TextStyleSpec } from './view.js';

export interface TextStyle {
  color?: Color | null;
  fontSize?: number | null;
  fontWeight?: number | null;
  italic?: boolean | null;
  fontFamily?: string | null;
  letterSpacing?: number | null;
  wordSpacing?: number | null;
  /** Height multiplier. */
  height?: number | null;
  /** Pixel line height (resolved against the final font size). */
  heightPx?: number | null;
  decoration?: number | null;
  decorationColor?: Color | null;
  decorationStyle?: string | null;
  decorationThickness?: number | null;
  shadows?: TextShadow[] | null;
  background?: Color | null;
  baselineShift?: number | null;
  textTransform?: string | null;
}

/** Later wins for every field it defines. */
export function mergeTextStyle(base: TextStyle | null | undefined, over: TextStyle | null | undefined): TextStyle {
  if (!base) return { ...(over ?? {}) };
  if (!over) return { ...base };
  const out: TextStyle = { ...base };
  for (const [k, v] of Object.entries(over)) {
    if (v !== undefined && v !== null) (out as any)[k] = v;
  }
  if (over.height != null) out.heightPx = null;
  if (over.heightPx != null) out.height = null;
  return out;
}

/** Material 3 `bodyMedium` — what Flutter's default `Text` uses inside a themed app. */
export const DEFAULT_TEXT_STYLE: Required<Pick<TextStyle, 'color' | 'fontSize' | 'fontWeight' | 'italic' | 'letterSpacing' | 'wordSpacing' | 'decoration'>> & TextStyle = {
  color: M3.onSurface,
  fontSize: 14,
  fontWeight: 400,
  italic: false,
  fontFamily: null,
  letterSpacing: 0.25,
  wordSpacing: 0,
  height: 20 / 14,
  decoration: 0,
};

/** Material 3 `labelLarge` (buttons). */
export const LABEL_LARGE: TextStyle = { fontSize: 14, fontWeight: 500, letterSpacing: 0.1, height: 20 / 14 };
/** Material 3 `titleLarge` (app bar titles). */
export const TITLE_LARGE: TextStyle = { fontSize: 22, fontWeight: 400, letterSpacing: 0, height: 28 / 22 };
/** Material 3 `bodyLarge` (text fields). */
export const BODY_LARGE: TextStyle = { fontSize: 16, fontWeight: 400, letterSpacing: 0.5, height: 24 / 16 };
/** Material 3 `labelSmall` (badges). */
export const LABEL_SMALL: TextStyle = { fontSize: 11, fontWeight: 500, letterSpacing: 0.5, height: 16 / 11 };

const SERIF = new Set([
  'serif', 'georgia', 'times', 'times new roman', 'cambria', 'garamond', 'cinzel', 'playfair display',
  'merriweather', 'crimson', 'crimson pro', 'pt serif', 'noto serif', 'liberation serif', 'roboto serif',
]);
const MONO = new Set([
  'monospace', 'courier', 'courier new', 'consolas', 'menlo', 'monaco', 'roboto mono', 'sf mono',
  'source code pro', 'fira code', 'jetbrains mono', 'liberation mono', 'ui-monospace',
]);
const SANS = new Set([
  'sans-serif', 'arial', 'helvetica', 'helvetica neue', 'roboto', 'inter', 'segoe ui', 'verdana',
  'tahoma', 'noto sans', 'liberation sans', 'ubuntu',
]);

/**
 * Resolve a CSS font-family list the way Flutter's engine does: generic and
 * well-known serif / monospace stacks map to `serif` / `monospace`, sans
 * stacks to the platform default (null), anything else is passed through as
 * a concrete family the host may have bundled.
 */
export function resolveFontFamily(family: string | null | undefined): string | null {
  if (!family) return null;
  if (family === 'icons') return 'icons';
  for (const raw of family.split(',')) {
    const name = raw.trim().replace(/^['"]|['"]$/g, '').toLowerCase();
    if (name === '') continue;
    if (SERIF.has(name) || (name.includes('serif') && !name.includes('sans'))) return 'serif';
    if (MONO.has(name) || name.includes('mono')) return 'monospace';
    if (SANS.has(name) || name.includes('sans') || name === 'system-ui' || name.startsWith('-apple') || name === 'ui-sans-serif') {
      return null;
    }
    if (name === 'material icons' || name === 'materialicons') return 'icons';
    return raw.trim().replace(/^['"]|['"]$/g, '');
  }
  return null;
}

const DECO_UNDERLINE = 1;
const DECO_OVERLINE = 2;
const DECO_LINE_THROUGH = 4;
export const Decoration = { underline: DECO_UNDERLINE, overline: DECO_OVERLINE, lineThrough: DECO_LINE_THROUGH };

/** `CSSProperties.createTextStyle` — the text-relevant part of a resolved CSS style. */
export function textStyleFromCss(style: CSSStyle | null | undefined): TextStyle | null {
  if (!style) return null;
  const t: TextStyle = {};
  if (style.color != null) t.color = style.color;
  if (style.fontSize != null) t.fontSize = style.fontSize;
  if (style.fontWeight != null) t.fontWeight = style.fontWeight;
  if (style.fontStyle != null) t.italic = style.fontStyle === 'italic';
  if (style.fontFamily != null) t.fontFamily = resolveFontFamily(style.fontFamily) ?? '';
  if (style.letterSpacing != null) t.letterSpacing = style.letterSpacing;
  if (style.wordSpacing != null) t.wordSpacing = style.wordSpacing;
  if (style.lineHeight != null) t.height = style.lineHeight;
  if (style.lineHeightPx != null) t.heightPx = style.lineHeightPx;
  if (style.textDecoration != null) {
    const d = style.textDecoration;
    t.decoration = (d.underline ? DECO_UNDERLINE : 0) | (d.overline ? DECO_OVERLINE : 0) | (d.lineThrough ? DECO_LINE_THROUGH : 0);
  }
  if (style.textDecorationColor != null) t.decorationColor = style.textDecorationColor;
  if (style.textDecorationStyle != null) t.decorationStyle = style.textDecorationStyle;
  if (style.textDecorationThickness != null) t.decorationThickness = style.textDecorationThickness;
  if (style.textShadow != null) t.shadows = style.textShadow;
  if (style.textTransform != null) t.textTransform = style.textTransform;
  return t;
}

/** Resolve an inheritable style into the wire spec. */
export function toSpec(style: TextStyle, textScale = 1): TextStyleSpec {
  const merged = mergeTextStyle(DEFAULT_TEXT_STYLE, style);
  const fontSize = (merged.fontSize ?? 14) * textScale;
  let height = merged.height ?? null;
  if (merged.heightPx != null && fontSize > 0) height = (merged.heightPx * textScale) / fontSize;
  return {
    color: merged.color ?? M3.onSurface,
    fontSize,
    fontWeight: merged.fontWeight ?? 400,
    italic: !!merged.italic,
    fontFamily: merged.fontFamily === '' ? null : merged.fontFamily ?? null,
    letterSpacing: merged.letterSpacing ?? 0,
    wordSpacing: merged.wordSpacing ?? 0,
    height,
    decoration: merged.decoration ?? 0,
    decorationColor: merged.decorationColor ?? null,
    decorationStyle: merged.decorationStyle ?? null,
    decorationThickness: merged.decorationThickness ?? null,
    shadows: merged.shadows ?? null,
    background: merged.background ?? null,
    baselineShift: merged.baselineShift ?? 0,
  };
}

/** CSS `text-transform`. */
export function applyTextTransform(text: string, transform: string | null | undefined): string {
  switch (transform) {
    case 'uppercase':
      return text.toUpperCase();
    case 'lowercase':
      return text.toLowerCase();
    case 'capitalize':
      return text.replace(/(^|\s|[-(\["'])(\p{L})/gu, (_m, pre: string, ch: string) => pre + ch.toUpperCase());
    default:
      return text;
  }
}
