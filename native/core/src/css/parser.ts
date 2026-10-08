/**
 * The CSS value parser — a port of `CSSParser` (flutter/lib/src/css/css_parser.dart).
 *
 * `parse(map)` turns an inline/cascaded style map (camelCase or kebab-case
 * keys, numbers or CSS strings) into a resolved [CSSStyle]. Everything the
 * Flutter parser accepts is accepted here with the same result. Beyond that,
 * the CSS string forms Flutter silently drops — `border: 1px solid #ccc`,
 * `box-shadow: 0 2px 4px rgba(…)`, `transform: rotate(45deg)`, multi-value
 * `border-radius`, `em`/`rem` units, `filter: blur(4px)` — are parsed too, so
 * the native renderers can honour them.
 */
import { parseColor, type Color } from './color.js';
import { cssEnvironment, cssEnvironmentGeneration } from './environment.js';
import type { CSSStyle } from './style.js';
import {
  Align,
  type Alignment,
  type Border,
  type BorderRadius,
  type BorderSide,
  type BorderStyleName,
  type BoxFit,
  type BoxShadow,
  type EdgeInsets,
  type Filter,
  type FontWeight,
  type Gradient,
  type Keyframe,
  type Matrix4,
  type Offset,
  type Overflow,
  type Percent,
  type TextAlign,
  type TextDecoration,
  type TextOverflow,
  type TextShadow,
} from './types.js';
import { identity, multiply, rotationZ, scaling, skew, translation, fromCssMatrix } from './matrix.js';
import { stableKey } from '../util/json.js';

type StyleMap = Record<string, any>;

const MAX_CACHE = 512;
const cache = new Map<string, CSSStyle>();

/** Read a property by camelCase name, falling back to its kebab-case spelling. */
function pick(m: StyleMap, camel: string): any {
  const v = m[camel];
  if (v !== undefined && v !== null) return v;
  const kebab = camel.replace(/[A-Z]/g, (c) => '-' + c.toLowerCase());
  return kebab === camel ? undefined : m[kebab];
}

function str(v: any): string | null {
  if (v == null) return null;
  return typeof v === 'string' ? v : String(v);
}

const VIEWPORT_KEYS = [
  'width', 'height', 'minWidth', 'min-width', 'maxWidth', 'max-width', 'minHeight', 'min-height',
  'maxHeight', 'max-height', 'top', 'right', 'bottom', 'left', 'padding', 'margin', 'gap',
];

function hasViewportUnits(m: StyleMap): boolean {
  for (const key of VIEWPORT_KEYS) {
    const v = m[key];
    if (typeof v === 'string' && /%|vw|vh|vmin|vmax|calc\(|env\(/.test(v)) return true;
  }
  return false;
}

export const CSSParser = {
  parse(styleMap: StyleMap): CSSStyle {
    const viewportDependent = hasViewportUnits(styleMap);
    const key = (viewportDependent ? 'g' + cssEnvironmentGeneration() + ':' : '') + stableKey(styleMap);
    const hit = cache.get(key);
    if (hit) {
      cache.delete(key);
      cache.set(key, hit);
      return hit;
    }
    const style = parseUncached(styleMap);
    if (cache.size >= MAX_CACHE) cache.delete(cache.keys().next().value as string);
    cache.set(key, style);
    return style;
  },
  clearCache(): void {
    cache.clear();
  },
  get cacheSize(): number {
    return cache.size;
  },
  parseColor,
  parseDouble,
  parseDimension,
  parseAlignment,
  parseOffset,
  parseDuration,
  parseEdgeInsets,
  parseGradient,
  parseBoxShadow,
  parseTransform,
  stripImportant,
  isImportant,
};

export function stripImportant(value: any): any {
  if (typeof value === 'string') {
    const re = /\s*!\s*important\s*$/i;
    if (re.test(value)) return value.replace(re, '').trim();
  }
  return value;
}

export function isImportant(value: any): boolean {
  return typeof value === 'string' && /!\s*important\s*$/i.test(value);
}

function parseUncached(m: StyleMap): CSSStyle {
  const s: CSSStyle = {};
  const fontSize = parseFontSize(pick(m, 'fontSize'));

  // ---- sizing --------------------------------------------------------------
  s.width = parseDimension(m.width, true);
  s.height = parseDimension(m.height, false);
  s.widthFactor = percentFactor(m.width);
  s.heightFactor = percentFactor(m.height);
  s.aspectRatio = parseAspectRatio(pick(m, 'aspectRatio'));
  s.minWidth = parseDimension(pick(m, 'minWidth'), true);
  s.maxWidth = parseDimension(pick(m, 'maxWidth'), true);
  s.minHeight = parseDimension(pick(m, 'minHeight'), false);
  s.maxHeight = parseDimension(pick(m, 'maxHeight'), false);
  if (s.maxWidth == null && /^\s*none\s*$/i.test(str(pick(m, 'maxWidth')) ?? '')) s.maxWidth = null;

  // ---- spacing -------------------------------------------------------------
  const pad = parseEdgeInsetsFor(m, 'padding', fontSize);
  s.padding = pad.insets;
  s.paddingPercent = pad.percent;
  const mar = parseEdgeInsetsFor(m, 'margin', fontSize);
  s.margin = mar.insets;
  s.marginPercent = mar.percent;
  s.marginAuto = mar.auto;

  // ---- positioning ---------------------------------------------------------
  s.alignment = parseAlignment(m.alignment);
  s.position = str(m.position);
  s.top = parseDimension(m.top, false);
  s.right = parseDimension(m.right, true);
  s.bottom = parseDimension(m.bottom, false);
  s.left = parseDimension(m.left, true);
  s.zIndex = parseDouble(pick(m, 'zIndex'));

  // ---- layout --------------------------------------------------------------
  s.display = str(m.display)?.trim() ?? null;
  s.flexDirection = str(pick(m, 'flexDirection'));
  s.justifyContent = str(pick(m, 'justifyContent'));
  s.alignItems = str(pick(m, 'alignItems'));
  s.alignContent = str(pick(m, 'alignContent'));
  s.alignSelf = str(pick(m, 'alignSelf'));
  parseFlexShorthand(m, s);
  s.flexWrap = str(pick(m, 'flexWrap'));
  const flow = str(pick(m, 'flexFlow'));
  if (flow) {
    for (const token of flow.split(/\s+/)) {
      if (token.startsWith('row') || token.startsWith('column')) s.flexDirection ??= token;
      else if (token.startsWith('wrap') || token === 'nowrap') s.flexWrap ??= token;
    }
  }
  s.order = parseInt(m.order);
  const gap = str(m.gap);
  if (gap && gap.trim().includes(' ')) {
    // `gap: <row> <column>`
    const [rg, cg] = gap.trim().split(/\s+/);
    s.rowGap = parseDouble(rg, fontSize);
    s.columnGap = parseDouble(cg, fontSize);
    s.gap = s.columnGap;
  } else {
    s.gap = parseDouble(m.gap, fontSize);
    s.rowGap = parseDouble(pick(m, 'rowGap'), fontSize);
    s.columnGap = parseDouble(pick(m, 'columnGap'), fontSize);
  }
  s.overflow = parseOverflow(m.overflow);
  s.overflowX = parseOverflow(pick(m, 'overflowX'));
  s.overflowY = parseOverflow(pick(m, 'overflowY'));
  s.boxSizing = str(pick(m, 'boxSizing'));

  // ---- grid ----------------------------------------------------------------
  s.gridTemplateColumns = str(pick(m, 'gridTemplateColumns'));
  s.gridTemplateRows = str(pick(m, 'gridTemplateRows'));
  s.gridTemplateAreas = str(pick(m, 'gridTemplateAreas'));
  s.gridAutoColumns = str(pick(m, 'gridAutoColumns'));
  s.gridAutoRows = str(pick(m, 'gridAutoRows'));
  s.gridAutoFlow = str(pick(m, 'gridAutoFlow'));
  s.gridColumnGap = parseDouble(
    pick(m, 'gridColumnGap') ?? pick(m, 'columnGap') ?? (s.columnGap != null ? s.columnGap : undefined),
    fontSize,
  );
  s.gridRowGap = parseDouble(pick(m, 'gridRowGap') ?? pick(m, 'rowGap') ?? (s.rowGap != null ? s.rowGap : undefined), fontSize);
  s.gridGap = parseDouble(pick(m, 'gridGap'), fontSize);
  s.gridColumn = str(pick(m, 'gridColumn'));
  s.gridRow = str(pick(m, 'gridRow'));
  s.gridArea = str(pick(m, 'gridArea'));
  s.justifyItems = str(pick(m, 'justifyItems'));
  s.justifySelf = str(pick(m, 'justifySelf'));

  // ---- background ----------------------------------------------------------
  const background = m.background;
  const bgLayers = typeof background === 'string' ? parseBackgroundShorthand(background) : null;
  s.backgroundColor = parseColor(pick(m, 'backgroundColor')) ?? bgLayers?.color ?? null;
  const bgImage = str(pick(m, 'backgroundImage'));
  s.backgroundImage = bgImage && !isGradientValue(bgImage) ? extractUrl(bgImage) : bgLayers?.image ?? null;
  s.backgroundSize = parseBoxFit(pick(m, 'backgroundSize'));
  s.backgroundSizePx = parseBackgroundSizePx(pick(m, 'backgroundSize'));
  s.backgroundPosition = parseAlignment(pick(m, 'backgroundPosition'));
  s.backgroundRepeat = str(pick(m, 'backgroundRepeat'));
  const gradients: Gradient[] = [];
  const explicit = parseGradient(m.gradient);
  if (explicit) gradients.push(explicit);
  if (bgImage && isGradientValue(bgImage)) gradients.push(...parseGradientLayers(bgImage));
  if (bgLayers) gradients.push(...bgLayers.gradients);
  s.gradient = gradients[0] ?? null;
  s.gradientLayers = gradients.length > 1 ? gradients.slice(1) : null;
  s.gradientColors = parseColorList(pick(m, 'gradientColors'));
  s.gradientStops = parseNumberList(pick(m, 'gradientStops'));

  // ---- border --------------------------------------------------------------
  s.borderColor = parseColor(pick(m, 'borderColor'));
  s.borderWidth = parseDouble(pick(m, 'borderWidth'), fontSize);
  s.borderStyle = str(pick(m, 'borderStyle'));
  s.border = parseBorder(m, s, fontSize);
  const radius = parseBorderRadius(m, fontSize);
  s.borderRadius = radius.px;
  s.borderRadiusPercent = radius.percent;
  s.outlineColor = parseColor(pick(m, 'outlineColor'));
  s.outlineWidth = parseDouble(pick(m, 'outlineWidth'), fontSize);
  s.outlineStyle = str(pick(m, 'outlineStyle'));
  s.outlineOffset = parseDouble(pick(m, 'outlineOffset'), fontSize);
  const outline = str(m.outline);
  if (outline) {
    const side = parseBorderSideString(outline, fontSize);
    if (side) {
      s.outlineColor ??= side.color;
      s.outlineWidth ??= side.width;
      s.outlineStyle ??= side.style;
    }
  }

  // ---- text ----------------------------------------------------------------
  s.color = parseColor(m.color);
  s.fontSize = fontSize;
  s.fontWeight = parseFontWeight(pick(m, 'fontWeight'));
  s.fontStyle = parseFontStyle(pick(m, 'fontStyle'));
  s.fontFamily = str(pick(m, 'fontFamily'));
  parseFontShorthand(m.font, s);
  s.letterSpacing = parseDouble(pick(m, 'letterSpacing'), fontSize ?? 16);
  s.wordSpacing = parseDouble(pick(m, 'wordSpacing'), fontSize ?? 16);
  parseLineHeight(pick(m, 'lineHeight'), s);
  s.textAlign = parseTextAlign(pick(m, 'textAlign'));
  const deco = parseTextDecoration(pick(m, 'textDecoration') ?? pick(m, 'textDecorationLine'));
  s.textDecoration = deco.decoration;
  s.textDecorationColor = parseColor(pick(m, 'textDecorationColor')) ?? deco.color;
  s.textDecorationStyle = str(pick(m, 'textDecorationStyle')) ?? deco.style;
  s.textDecorationThickness = parseDouble(pick(m, 'textDecorationThickness'));
  s.textOverflow = parseTextOverflow(pick(m, 'textOverflow'));
  s.textTransform = str(pick(m, 'textTransform'));
  s.whiteSpace = str(pick(m, 'whiteSpace'));
  const collapse = str(pick(m, 'borderCollapse'));
  s.borderCollapse = collapse === 'collapse' || collapse === 'separate' ? collapse : null;
  s.borderSpacing = CSSParser.parseDouble(pick(m, 'borderSpacing'));
  s.verticalAlign = str(pick(m, 'verticalAlign'));
  s.writingMode = str(pick(m, 'writingMode'));
  s.wordBreak = str(pick(m, 'wordBreak'));
  s.lineClamp = parseInt(pick(m, 'lineClamp') ?? pick(m, 'WebkitLineClamp') ?? m['-webkit-line-clamp']);

  // ---- effects -------------------------------------------------------------
  s.boxShadow = parseBoxShadow(pick(m, 'boxShadow'));
  s.textShadow = parseTextShadow(pick(m, 'textShadow'));
  s.transform = parseTransform(m.transform);
  s.rotate = parseAngleDegrees(m.rotate);
  const scaleRaw = m.scale;
  if (typeof scaleRaw === 'string' && scaleRaw.trim().includes(' ')) {
    const [sx, sy] = scaleRaw.trim().split(/\s+/).map((t) => parseFloat(t));
    s.scaleX = Number.isFinite(sx) ? sx : null;
    s.scaleY = Number.isFinite(sy) ? sy : null;
  } else {
    s.scale = parseDouble(scaleRaw);
  }
  s.scaleX ??= parseDouble(pick(m, 'scaleX'));
  s.scaleY ??= parseDouble(pick(m, 'scaleY'));
  s.translate = parseOffset(m.translate) ?? parseTranslateString(m.translate);
  s.transformOrigin = parseAlignment(pick(m, 'transformOrigin')) ?? parseOriginString(pick(m, 'transformOrigin'));
  s.opacity = parseDouble(m.opacity);
  s.visible = typeof m.visible === 'boolean' ? m.visible : null;
  s.visibility = str(m.visibility);
  s.filter = parseFilter(m.filter);
  s.backdropFilter = parseFilter(pick(m, 'backdropFilter'));
  s.mixBlendMode = str(pick(m, 'mixBlendMode'));

  // ---- interaction ---------------------------------------------------------
  s.cursor = str(m.cursor);
  s.pointerEvents = str(pick(m, 'pointerEvents'));
  s.userSelect = str(pick(m, 'userSelect'));
  s.touchAction = str(pick(m, 'touchAction'));

  // ---- media / shape -------------------------------------------------------
  s.objectFit = parseBoxFit(pick(m, 'objectFit'));
  s.objectPosition = parseAlignment(pick(m, 'objectPosition'));
  s.clipBehavior = str(pick(m, 'clipBehavior'));
  const shape = str(m.shape)?.toLowerCase();
  s.shape = shape === 'circle' ? 'circle' : shape === 'rectangle' ? 'rectangle' : null;

  // ---- transitions / animation --------------------------------------------
  s.transitionDuration = parseDuration(pick(m, 'transitionDuration'));
  s.transitionCurve = normalizeCurve(pick(m, 'transitionCurve') ?? pick(m, 'transitionTimingFunction'));
  s.transitionProperty = str(pick(m, 'transitionProperty'));
  s.transitionDelay = parseDuration(pick(m, 'transitionDelay'));
  const transition = str(m.transition);
  if (transition) parseTransitionShorthand(transition, s);
  s.animationName = str(pick(m, 'animationName'));
  s.animationDuration = parseDuration(pick(m, 'animationDuration'));
  s.animationTimingFunction = str(pick(m, 'animationTimingFunction'));
  s.animationDelay = parseDuration(pick(m, 'animationDelay'));
  s.animationIterationCount = parseInt(pick(m, 'animationIterationCount'));
  s.animationDirection = str(pick(m, 'animationDirection'));
  s.animationFillMode = str(pick(m, 'animationFillMode'));
  s.animationPlayState = str(pick(m, 'animationPlayState'));
  const animation = str(m.animation);
  if (animation) parseAnimationShorthand(animation, s);
  s.animateOnBuild = asBool(pick(m, 'animateOnBuild'));
  s.staggerDelay = parseDuration(pick(m, 'staggerDelay'));
  s.staggerChildren = parseInt(pick(m, 'staggerChildren'));
  s.animationFrom = parseDouble(pick(m, 'animationFrom'));
  s.animationTo = parseDouble(pick(m, 'animationTo'));
  s.slideBegin = parseOffset(pick(m, 'slideBegin'));
  s.slideEnd = parseOffset(pick(m, 'slideEnd'));
  s.scaleBegin = parseDouble(pick(m, 'scaleBegin'));
  s.scaleEnd = parseDouble(pick(m, 'scaleEnd'));
  s.rotationBegin = parseDouble(pick(m, 'rotationBegin'));
  s.rotationEnd = parseDouble(pick(m, 'rotationEnd'));
  s.fadeBegin = parseDouble(pick(m, 'fadeBegin'));
  s.fadeEnd = parseDouble(pick(m, 'fadeEnd'));
  s.colorBegin = parseColor(pick(m, 'colorBegin'));
  s.colorEnd = parseColor(pick(m, 'colorEnd'));
  s.paddingBegin = parseEdgeInsets(pick(m, 'paddingBegin'));
  s.paddingEnd = parseEdgeInsets(pick(m, 'paddingEnd'));
  s.alignmentBegin = parseAlignment(pick(m, 'alignmentBegin'));
  s.alignmentEnd = parseAlignment(pick(m, 'alignmentEnd'));
  s.shimmerBaseColor = parseColor(pick(m, 'shimmerBaseColor'));
  s.shimmerHighlightColor = parseColor(pick(m, 'shimmerHighlightColor'));
  s.animationAutoReverse = asBool(pick(m, 'animationAutoReverse'));
  s.animationRepeat = asBool(pick(m, 'animationRepeat'));
  s.keyframes = parseKeyframes(m.keyframes);

  // Drop the nulls so `{...a, ...b}` merges behave and the object stays small.
  for (const key of Object.keys(s) as (keyof CSSStyle)[]) {
    if (s[key] == null) delete s[key];
  }
  return s;
}

// ============================================================================
// Numbers and lengths
// ============================================================================

function asBool(v: any): boolean | null {
  if (typeof v === 'boolean') return v;
  if (v === 'true') return true;
  if (v === 'false') return false;
  return null;
}

/**
 * Flutter's `parseDouble`: numbers pass through; strings have their unit
 * stripped. `em`/`rem` are honoured (×[emBase] / ×root size) rather than read
 * as bare pixel counts.
 */
export function parseDouble(value: any, emBase?: number | null): number | null {
  if (value == null) return null;
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (typeof value === 'boolean') return null;
  const raw = String(stripImportant(value)).trim();
  if (raw === '') return null;
  const lower = raw.toLowerCase();
  if (lower.endsWith('rem')) {
    const n = parseFloat(lower);
    return Number.isFinite(n) ? n * cssEnvironment().rootFontSize : null;
  }
  if (lower.endsWith('em') && !lower.endsWith('rem')) {
    const n = parseFloat(lower);
    return Number.isFinite(n) ? n * (emBase ?? cssEnvironment().rootFontSize) : null;
  }
  if (/^-?[\d.]+(vw|vh|vmin|vmax)$/.test(lower)) return resolveLength(lower, true);
  const n = parseFloat(raw.replace(/[^0-9.\-eE+]/g, ''));
  if (!Number.isFinite(n)) {
    const fallback = Number.parseFloat(raw.replace(/[^0-9.\-]/g, ''));
    return Number.isFinite(fallback) ? fallback : null;
  }
  return n;
}

function parseInt(value: any): number | null {
  if (value == null) return null;
  if (typeof value === 'number') return Math.trunc(value);
  if (typeof value === 'string') {
    const t = value.trim().toLowerCase();
    if (t === 'infinite') return -1;
    const n = Number.parseInt(t, 10);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

function parseFontSize(value: any): number | null {
  if (value == null) return null;
  if (typeof value === 'string') {
    const t = value.trim().toLowerCase();
    const keywords: Record<string, number> = {
      'xx-small': 9, 'x-small': 10, small: 13, medium: 16, large: 18, 'x-large': 24, 'xx-large': 32, 'xxx-large': 48,
    };
    if (t in keywords) return keywords[t];
    if (t.endsWith('%')) {
      const n = parseFloat(t);
      return Number.isFinite(n) ? (n / 100) * cssEnvironment().rootFontSize : null;
    }
  }
  return parseDouble(value);
}

function percentFactor(value: any): number | null {
  if (typeof value !== 'string') return null;
  const raw = String(stripImportant(value)).trim();
  if (!raw.endsWith('%')) return null;
  const n = parseFloat(raw.substring(0, raw.length - 1));
  return Number.isFinite(n) ? n / 100 : null;
}

export function parseDimension(value: any, isWidth: boolean): number | null {
  if (value == null) return null;
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (typeof value !== 'string') return null;
  const raw = String(stripImportant(value)).trim();
  if (raw === '' || raw === 'auto' || raw === 'none' || raw === 'fit-content' || raw === 'max-content' || raw === 'min-content') {
    return null;
  }
  if (raw.includes('calc(')) return evalCalc(raw, isWidth);
  if (/^(min|max|clamp)\(/.test(raw)) return evalMathFn(raw, isWidth);
  return resolveLength(raw, isWidth);
}

function resolveLength(raw: string, isWidth: boolean): number | null {
  const t = raw.trim().toLowerCase();
  if (t === '') return null;
  if (t.startsWith('env(')) return resolveEnv(t, isWidth);
  if (t.startsWith('var(')) return null;
  if (t.includes('*') || t.includes('/') || t.includes('(')) return null;
  const n = parseFloat(t.replace(/[^0-9.\-eE+]/g, ''));
  if (!Number.isFinite(n)) return null;
  const env = cssEnvironment();
  const w = env.viewportWidth;
  const h = env.viewportHeight;
  if (t.endsWith('vmin')) return (n / 100) * Math.min(w, h);
  if (t.endsWith('vmax')) return (n / 100) * Math.max(w, h);
  if (t.endsWith('vw')) return (n / 100) * w;
  if (t.endsWith('vh') || t.endsWith('dvh') || t.endsWith('svh') || t.endsWith('lvh')) return (n / 100) * h;
  if (t.endsWith('%')) return (n / 100) * (isWidth ? w : h);
  if (t.endsWith('rem')) return n * env.rootFontSize;
  if (t.endsWith('em')) return n * env.rootFontSize;
  if (t.endsWith('pt')) return (n * 4) / 3;
  return n;
}

function evalCalc(raw: string, isWidth: boolean): number | null {
  const m = /^calc\(([\s\S]*)\)$/.exec(raw.trim());
  const body = m?.[1]?.trim();
  if (!body) return null;
  return evalSum(body, isWidth);
}

function evalSum(body: string, isWidth: boolean): number | null {
  let sum = 0;
  let sign = 1;
  let start = 0;
  let depth = 0;
  for (let i = 0; i < body.length; i++) {
    const c = body[i];
    if (c === '(') depth++;
    else if (c === ')') depth--;
    else if (depth === 0 && (c === '+' || c === '-') && i > 0 && body[i - 1] === ' ' && body[i + 1] === ' ') {
      const v = evalProduct(body.substring(start, i).trim(), isWidth);
      if (v == null) return null;
      sum += sign * v;
      sign = c === '+' ? 1 : -1;
      start = i + 1;
    }
  }
  const last = evalProduct(body.substring(start).trim(), isWidth);
  if (last == null) return null;
  return sum + sign * last;
}

function evalProduct(term: string, isWidth: boolean): number | null {
  // `a * b` / `a / b` with at most one length operand.
  const mul = /^(.+?)\s*([*/])\s*(.+)$/.exec(term);
  if (mul && !term.startsWith('env(') && !term.startsWith('calc(')) {
    const left = evalAtom(mul[1].trim(), isWidth);
    const right = evalAtom(mul[3].trim(), isWidth);
    if (left == null || right == null) return null;
    return mul[2] === '*' ? left * right : right === 0 ? null : left / right;
  }
  return evalAtom(term, isWidth);
}

function evalAtom(atom: string, isWidth: boolean): number | null {
  const t = atom.trim();
  if (t.startsWith('(') && t.endsWith(')')) return evalSum(t.substring(1, t.length - 1).trim(), isWidth);
  if (t.startsWith('calc(')) return evalCalc(t, isWidth);
  if (/^(min|max|clamp)\(/.test(t)) return evalMathFn(t, isWidth);
  return resolveLength(t, isWidth);
}

function evalMathFn(raw: string, isWidth: boolean): number | null {
  const m = /^(min|max|clamp)\(([\s\S]*)\)$/.exec(raw.trim());
  if (!m) return null;
  const args = splitTopLevel(m[2], ',').map((a) => evalSum(a.trim(), isWidth));
  if (args.some((a) => a == null)) return null;
  const nums = args as number[];
  if (m[1] === 'min') return Math.min(...nums);
  if (m[1] === 'max') return Math.max(...nums);
  if (nums.length !== 3) return null;
  return Math.min(Math.max(nums[1], nums[0]), nums[2]);
}

function resolveEnv(raw: string, isWidth: boolean): number | null {
  const m = /^env\(\s*([a-z-]+)\s*(?:,\s*([^)]+))?\)$/.exec(raw.trim());
  if (!m) return null;
  const insets = cssEnvironment().safeArea;
  switch (m[1]) {
    case 'safe-area-inset-top':
      return insets.top;
    case 'safe-area-inset-right':
      return insets.right;
    case 'safe-area-inset-bottom':
      return insets.bottom;
    case 'safe-area-inset-left':
      return insets.left;
  }
  return m[2] != null ? resolveLength(m[2].trim(), isWidth) ?? 0 : 0;
}

function parseAspectRatio(value: any): number | null {
  if (typeof value === 'number') return value > 0 ? value : null;
  if (typeof value !== 'string') return null;
  const raw = value.trim().toLowerCase();
  if (raw === '' || raw === 'auto') return null;
  const parts = raw.split('/');
  if (parts.length === 2) {
    const w = parseFloat(parts[0]);
    const h = parseFloat(parts[1]);
    return Number.isFinite(w) && Number.isFinite(h) && h !== 0 ? w / h : null;
  }
  const v = parseFloat(raw);
  return Number.isFinite(v) && v > 0 ? v : null;
}

function parseFlexShorthand(m: StyleMap, s: CSSStyle): void {
  const flex = m.flex;
  s.flexGrow = parseDouble(pick(m, 'flexGrow'));
  s.flexShrink = parseDouble(pick(m, 'flexShrink'));
  s.flexBasis = str(pick(m, 'flexBasis'));
  if (flex == null) return;
  if (typeof flex === 'number') {
    s.flex = flex;
    return;
  }
  const t = String(flex).trim().toLowerCase();
  if (t === 'none') {
    s.flexShrink ??= 0;
    return;
  }
  if (t === 'auto') {
    s.flex = 1;
    s.flexBasis ??= 'auto';
    return;
  }
  const parts = t.split(/\s+/);
  const grow = parseFloat(parts[0]);
  if (Number.isFinite(grow)) {
    // Flutter reads `flex` with parseInt — `flex: "1 1 0%"` → 1.
    s.flex = grow;
    if (parts.length > 1) {
      const shrink = parseFloat(parts[1]);
      if (Number.isFinite(shrink)) s.flexShrink ??= shrink;
      else s.flexBasis ??= parts[1];
    }
    if (parts.length > 2) s.flexBasis ??= parts[2];
  } else {
    s.flexBasis ??= parts[0];
  }
}

// ============================================================================
// Edge insets, alignment, offsets
// ============================================================================

type Side = 'top' | 'right' | 'bottom' | 'left';

function expandFour<T>(parts: T[]): [T, T, T, T] {
  if (parts.length === 1) return [parts[0], parts[0], parts[0], parts[0]];
  if (parts.length === 2) return [parts[0], parts[1], parts[0], parts[1]];
  if (parts.length === 3) return [parts[0], parts[1], parts[2], parts[1]];
  return [parts[0], parts[1], parts[2], parts[3]];
}

export function parseEdgeInsets(value: any, emBase?: number | null): EdgeInsets | null {
  if (value == null) return null;
  if (typeof value === 'object' && !Array.isArray(value)) {
    return {
      top: parseDouble(value.top, emBase) ?? 0,
      right: parseDouble(value.right, emBase) ?? 0,
      bottom: parseDouble(value.bottom, emBase) ?? 0,
      left: parseDouble(value.left, emBase) ?? 0,
    };
  }
  if (Array.isArray(value)) {
    const nums = value.map((v) => parseDouble(v, emBase) ?? 0);
    if (nums.length === 0) return null;
    const [t, r, b, l] = expandFour(nums);
    return { top: t, right: r, bottom: b, left: l };
  }
  if (typeof value === 'number' || typeof value === 'string') {
    const parts = String(stripImportant(value)).trim().split(/\s+/).filter((p) => p !== '');
    if (parts.length === 0 || parts.length > 4) return null;
    const nums = parts.map((p) => (p === 'auto' ? 0 : parseLengthToken(p, emBase) ?? 0));
    const [t, r, b, l] = expandFour(nums);
    return { top: t, right: r, bottom: b, left: l };
  }
  return null;
}

function parseLengthToken(token: string, emBase?: number | null): number | null {
  const t = token.trim().toLowerCase();
  if (t.endsWith('%')) return null; // handled as a percentage by the caller
  if (/vw$|vh$|vmin$|vmax$|^calc\(|^env\(/.test(t)) return parseDimension(t, true);
  return parseDouble(t, emBase);
}

interface InsetsResult {
  insets: EdgeInsets | null;
  percent: Partial<Record<Side, Percent>> | null;
  auto: { top: boolean; right: boolean; bottom: boolean; left: boolean } | null;
}

function parseEdgeInsetsFor(m: StyleMap, base: string, emBase: number | null): InsetsResult {
  const percent: Partial<Record<Side, Percent>> = {};
  const auto = { top: false, right: false, bottom: false, left: false };
  let any = false;
  const values: Record<Side, number | null> = { top: null, right: null, bottom: null, left: null };

  const shorthandRaw = m[base];
  if (shorthandRaw != null) {
    if (typeof shorthandRaw === 'object') {
      const e = parseEdgeInsets(shorthandRaw, emBase);
      if (e) {
        Object.assign(values, e);
        any = true;
      }
    } else {
      const parts = String(stripImportant(shorthandRaw)).trim().split(/\s+/).filter((p) => p !== '');
      if (parts.length > 0 && parts.length <= 4) {
        const four = expandFour(parts);
        (['top', 'right', 'bottom', 'left'] as Side[]).forEach((side, i) => applyInsetToken(four[i], side, values, percent, auto, emBase));
        any = true;
      }
    }
  }

  const cap = base.charAt(0).toUpperCase() + base.substring(1);
  for (const side of ['top', 'right', 'bottom', 'left'] as Side[]) {
    const sideCap = side.charAt(0).toUpperCase() + side.substring(1);
    const raw = m[`${base}${sideCap}`] ?? m[`${base}-${side}`];
    if (raw != null) {
      applyInsetToken(String(stripImportant(raw)), side, values, percent, auto, emBase);
      any = true;
    }
  }
  // `paddingX`/`paddingY` convenience forms, plus the CSS logical properties.
  const x = m[`${base}X`] ?? m[`${base}Inline`] ?? m[`${base}-inline`];
  const y = m[`${base}Y`] ?? m[`${base}Block`] ?? m[`${base}-block`];
  if (x != null) {
    const parts = String(x).trim().split(/\s+/);
    applyInsetToken(parts[0], 'left', values, percent, auto, emBase, true);
    applyInsetToken(parts[1] ?? parts[0], 'right', values, percent, auto, emBase, true);
    any = true;
  }
  if (y != null) {
    const parts = String(y).trim().split(/\s+/);
    applyInsetToken(parts[0], 'top', values, percent, auto, emBase, true);
    applyInsetToken(parts[1] ?? parts[0], 'bottom', values, percent, auto, emBase, true);
    any = true;
  }
  void cap;
  if (!any) return { insets: null, percent: null, auto: null };
  return {
    insets: { top: values.top ?? 0, right: values.right ?? 0, bottom: values.bottom ?? 0, left: values.left ?? 0 },
    percent: Object.keys(percent).length ? percent : null,
    auto: auto.top || auto.right || auto.bottom || auto.left ? auto : null,
  };
}

function applyInsetToken(
  token: string,
  side: Side,
  values: Record<Side, number | null>,
  percent: Partial<Record<Side, Percent>>,
  auto: Record<Side, boolean>,
  emBase: number | null | undefined,
  onlyIfUnset = false,
): void {
  if (onlyIfUnset && values[side] != null) return;
  const t = String(token).trim().toLowerCase();
  if (t === 'auto') {
    auto[side] = true;
    values[side] = 0;
    delete percent[side];
    return;
  }
  auto[side] = false;
  if (t.endsWith('%')) {
    const n = parseFloat(t);
    if (Number.isFinite(n)) {
      percent[side] = { pct: n };
      values[side] = 0;
    }
    return;
  }
  delete percent[side];
  values[side] = parseLengthToken(t, emBase) ?? 0;
}

const alignmentMap: Record<string, Alignment> = {
  center: Align.center,
  topleft: Align.topLeft,
  'top-left': Align.topLeft,
  topcenter: Align.topCenter,
  'top-center': Align.topCenter,
  topright: Align.topRight,
  'top-right': Align.topRight,
  centerleft: Align.centerLeft,
  'center-left': Align.centerLeft,
  centerright: Align.centerRight,
  'center-right': Align.centerRight,
  bottomleft: Align.bottomLeft,
  'bottom-left': Align.bottomLeft,
  bottomcenter: Align.bottomCenter,
  'bottom-center': Align.bottomCenter,
  bottomright: Align.bottomRight,
  'bottom-right': Align.bottomRight,
};

export function parseAlignment(value: any): Alignment | null {
  if (value == null) return null;
  if (typeof value === 'string') {
    const key = value.trim().toLowerCase();
    const direct = alignmentMap[key];
    if (direct) return direct;
    // CSS position keywords: `top`, `left`, `center center`, `right bottom`, `25% 75%`.
    return parsePositionKeywords(key);
  }
  if (typeof value === 'object') {
    return { x: parseDouble(value.x) ?? 0, y: parseDouble(value.y) ?? 0 };
  }
  return null;
}

function parsePositionKeywords(key: string): Alignment | null {
  const tokens = key.split(/\s+/).filter((t) => t !== '');
  if (tokens.length === 0 || tokens.length > 2) return null;
  let x: number | null = null;
  let y: number | null = null;
  const unresolved: string[] = [];
  for (const t of tokens) {
    if (t === 'left') x = -1;
    else if (t === 'right') x = 1;
    else if (t === 'top') y = -1;
    else if (t === 'bottom') y = 1;
    else if (t.endsWith('%')) {
      const n = parseFloat(t);
      if (!Number.isFinite(n)) return null;
      const v = n / 50 - 1;
      if (x == null) x = v;
      else y = v;
    } else if (t === 'center') unresolved.push(t);
    else return null;
  }
  for (const _ of unresolved) {
    if (x == null) x = 0;
    else if (y == null) y = 0;
  }
  if (x == null && y == null) return null;
  return { x: x ?? 0, y: y ?? 0 };
}

function parseOriginString(value: any): Alignment | null {
  if (typeof value !== 'string') return null;
  return parsePositionKeywords(value.trim().toLowerCase());
}

export function parseOffset(value: any): Offset | null {
  if (value == null) return null;
  if (Array.isArray(value) && value.length === 2) {
    return { dx: parseDouble(value[0]) ?? 0, dy: parseDouble(value[1]) ?? 0 };
  }
  if (typeof value === 'object' && !Array.isArray(value)) {
    return { dx: parseDouble(value.x ?? value.dx) ?? 0, dy: parseDouble(value.y ?? value.dy) ?? 0 };
  }
  return null;
}

function parseTranslateString(value: any): Offset | null {
  if (typeof value !== 'string') return null;
  const parts = value.trim().split(/\s+/);
  const dx = parseDouble(parts[0]);
  if (dx == null) return null;
  return { dx, dy: parseDouble(parts[1]) ?? 0 };
}

// ============================================================================
// Enumerations
// ============================================================================

const fontWeightMap: Record<string, FontWeight> = {
  thin: 100, hairline: 100, extralight: 200, 'extra-light': 200, ultralight: 200,
  light: 300, normal: 400, regular: 400, medium: 500, semibold: 600, 'semi-bold': 600,
  demibold: 600, bold: 700, extrabold: 800, 'extra-bold': 800, black: 900, heavy: 900,
  bolder: 700, lighter: 300,
};

function parseFontWeight(value: any): FontWeight | null {
  if (value == null) return null;
  if (typeof value === 'number') {
    const idx = Math.min(9, Math.max(1, Math.trunc(value / 100)));
    return (idx * 100) as FontWeight;
  }
  const t = String(value).trim().toLowerCase();
  if (fontWeightMap[t]) return fontWeightMap[t];
  const n = Number.parseInt(t.startsWith('w') ? t.substring(1) : t, 10);
  if (Number.isFinite(n)) {
    const idx = Math.min(9, Math.max(1, Math.trunc(n / 100)));
    return (idx * 100) as FontWeight;
  }
  return null;
}

function parseFontStyle(value: any): 'normal' | 'italic' | null {
  if (typeof value !== 'string') return null;
  const t = value.trim().toLowerCase();
  if (t === 'italic' || t === 'oblique') return 'italic';
  if (t === 'normal') return 'normal';
  return null;
}

function parseFontShorthand(value: any, s: CSSStyle): void {
  if (typeof value !== 'string') return;
  // [style] [variant] [weight] size[/line-height] family
  const m = /^\s*((?:(?:italic|oblique|normal|bold|bolder|lighter|small-caps|\d{3})\s+)*)([\d.]+(?:px|em|rem|pt|%)?)(?:\s*\/\s*([\d.]+(?:px|em|rem|%)?))?\s+(.+)$/i.exec(
    value,
  );
  if (!m) return;
  for (const token of m[1].trim().split(/\s+/).filter((t) => t)) {
    const lower = token.toLowerCase();
    if (lower === 'italic' || lower === 'oblique') s.fontStyle ??= 'italic';
    else {
      const w = parseFontWeight(lower);
      if (w && lower !== 'normal') s.fontWeight ??= w;
    }
  }
  s.fontSize ??= parseFontSize(m[2]);
  if (m[3]) parseLineHeight(m[3], s);
  s.fontFamily ??= m[4].trim();
}

function parseLineHeight(value: any, s: CSSStyle): void {
  if (value == null) return;
  if (typeof value === 'number') {
    s.lineHeight = value;
    return;
  }
  const t = String(stripImportant(value)).trim().toLowerCase();
  if (t === 'normal') return;
  if (/^[\d.]+$/.test(t)) {
    s.lineHeight = parseFloat(t);
    return;
  }
  if (t.endsWith('%')) {
    s.lineHeight = parseFloat(t) / 100;
    return;
  }
  if (t.endsWith('em') && !t.endsWith('rem')) {
    s.lineHeight = parseFloat(t);
    return;
  }
  const px = parseDouble(t);
  if (px != null) s.lineHeightPx = px;
}

const textAlignMap: Record<string, TextAlign> = {
  left: 'left', right: 'right', center: 'center', justify: 'justify', start: 'start', end: 'end',
};

function parseTextAlign(value: any): TextAlign | null {
  if (typeof value !== 'string') return null;
  return textAlignMap[value.trim().toLowerCase()] ?? null;
}

function parseTextDecoration(value: any): { decoration: TextDecoration | null; color: Color | null; style: string | null } {
  if (typeof value !== 'string') return { decoration: null, color: null, style: null };
  const deco: TextDecoration = { underline: false, overline: false, lineThrough: false };
  let color: Color | null = null;
  let style: string | null = null;
  let known = false;
  for (const token of splitTopLevel(value.trim().toLowerCase(), ' ').filter((t) => t)) {
    if (token === 'underline') (deco.underline = true), (known = true);
    else if (token === 'overline') (deco.overline = true), (known = true);
    else if (token === 'line-through' || token === 'linethrough') (deco.lineThrough = true), (known = true);
    else if (token === 'none') known = true;
    else if (['solid', 'double', 'dotted', 'dashed', 'wavy'].includes(token)) style = token;
    else color = parseColor(token) ?? color;
  }
  return { decoration: known ? deco : null, color, style };
}

const textOverflowMap: Record<string, TextOverflow> = { ellipsis: 'ellipsis', clip: 'clip', fade: 'fade', visible: 'visible' };

function parseTextOverflow(value: any): TextOverflow | null {
  if (typeof value !== 'string') return null;
  return textOverflowMap[value.trim().toLowerCase()] ?? null;
}

const overflowMap: Record<string, Overflow> = { visible: 'visible', hidden: 'hidden', clip: 'clip', auto: 'scroll', scroll: 'scroll', overlay: 'scroll' };

function parseOverflow(value: any): Overflow | null {
  if (typeof value !== 'string') return null;
  const token = value.trim().toLowerCase().split(/\s+/)[0];
  return overflowMap[token] ?? null;
}

const boxFitMap: Record<string, BoxFit> = {
  fill: 'fill', contain: 'contain', cover: 'cover', fitwidth: 'fitWidth', 'fit-width': 'fitWidth',
  fitheight: 'fitHeight', 'fit-height': 'fitHeight', none: 'none', scaledown: 'scaleDown', 'scale-down': 'scaleDown',
  '100% 100%': 'fill',
};

function parseBoxFit(value: any): BoxFit | null {
  if (typeof value !== 'string') return null;
  return boxFitMap[value.trim().toLowerCase()] ?? null;
}

function parseBackgroundSizePx(value: any): { width: number | null; height: number | null } | null {
  if (typeof value !== 'string') return null;
  const t = value.trim().toLowerCase();
  if (boxFitMap[t]) return null;
  const parts = t.split(/\s+/);
  const w = parts[0] === 'auto' ? null : parseDouble(parts[0]);
  const h = parts.length > 1 ? (parts[1] === 'auto' ? null : parseDouble(parts[1])) : null;
  if (w == null && h == null) return null;
  return { width: w, height: h };
}

// ============================================================================
// Borders and radii
// ============================================================================

const borderStyles: BorderStyleName[] = ['solid', 'dashed', 'dotted', 'double', 'none'];

function parseBorderSideMap(value: any, emBase: number | null): BorderSide | null {
  if (value == null || typeof value !== 'object') return null;
  const style = String(value.style ?? 'solid').toLowerCase() as BorderStyleName;
  return {
    color: parseColor(value.color) ?? 0xff000000,
    width: parseDouble(value.width, emBase) ?? 1,
    style: borderStyles.includes(style) ? style : 'solid',
  };
}

function parseBorderSideString(value: string, emBase: number | null): BorderSide | null {
  const t = String(stripImportant(value)).trim();
  if (t === '' ) return null;
  if (/^(none|0|hidden)$/i.test(t)) return { width: 0, color: 0xff000000, style: 'none' };
  let width: number | null = null;
  let style: BorderStyleName | null = null;
  let color: Color | null = null;
  for (const token of splitTopLevel(t, ' ').filter((p) => p)) {
    const lower = token.toLowerCase();
    if ((borderStyles as string[]).includes(lower) || lower === 'groove' || lower === 'ridge' || lower === 'inset' || lower === 'outset') {
      style = (borderStyles as string[]).includes(lower) ? (lower as BorderStyleName) : 'solid';
    } else if (lower === 'thin') width = 1;
    else if (lower === 'medium') width = 3;
    else if (lower === 'thick') width = 5;
    else if (/^-?[\d.]/.test(lower)) width = parseDouble(lower, emBase);
    else color = parseColor(token) ?? color;
  }
  return { width: width ?? 3, style: style ?? 'none', color: color ?? 0xff000000 };
}

function parseBorderSideAny(value: any, emBase: number | null): BorderSide | null {
  if (value == null) return null;
  if (typeof value === 'object') return parseBorderSideMap(value, emBase);
  return parseBorderSideString(String(value), emBase);
}

function parseBorder(m: StyleMap, s: CSSStyle, emBase: number | null): Border | null {
  const none: BorderSide = { width: 0, color: 0xff000000, style: 'none' };
  let top: BorderSide | null = null, right: BorderSide | null = null, bottom: BorderSide | null = null, left: BorderSide | null = null;
  let any = false;

  const all = m.border;
  if (all != null) {
    if (typeof all === 'object' && !Array.isArray(all)) {
      // Flutter's map form: { top: {color,width}, right: …, … }
      if ('top' in all || 'right' in all || 'bottom' in all || 'left' in all) {
        top = parseBorderSideMap(all.top, emBase) ?? none;
        right = parseBorderSideMap(all.right, emBase) ?? none;
        bottom = parseBorderSideMap(all.bottom, emBase) ?? none;
        left = parseBorderSideMap(all.left, emBase) ?? none;
      } else {
        const side = parseBorderSideMap(all, emBase);
        top = right = bottom = left = side;
      }
      any = true;
    } else {
      const side = parseBorderSideString(String(all), emBase);
      if (side) {
        top = right = bottom = left = side;
        any = true;
      }
    }
  }

  for (const sideName of ['top', 'right', 'bottom', 'left'] as Side[]) {
    const cap = sideName.charAt(0).toUpperCase() + sideName.substring(1);
    const raw = m[`border${cap}`] ?? m[`border-${sideName}`];
    let side: BorderSide | null = raw != null ? parseBorderSideAny(raw, emBase) : null;
    const width = parseDouble(m[`border${cap}Width`] ?? m[`border-${sideName}-width`], emBase);
    const color = parseColor(m[`border${cap}Color`] ?? m[`border-${sideName}-color`]);
    const styleRaw = m[`border${cap}Style`] ?? m[`border-${sideName}-style`];
    if (width != null || color != null || styleRaw != null) {
      const base = side ?? (sideName === 'top' ? top : sideName === 'right' ? right : sideName === 'bottom' ? bottom : left);
      side = {
        width: width ?? base?.width ?? 1,
        color: color ?? base?.color ?? s.borderColor ?? 0xff000000,
        style: (styleRaw ? String(styleRaw).toLowerCase() : base?.style ?? 'solid') as BorderStyleName,
      };
    }
    if (side) {
      any = true;
      if (sideName === 'top') top = side;
      else if (sideName === 'right') right = side;
      else if (sideName === 'bottom') bottom = side;
      else left = side;
    }
  }

  // `border-color` / `border-width` / `border-style` multi-value shorthands
  // refine a border declared elsewhere (Flutter combines borderColor +
  // borderWidth into Border.all — that case is handled in lowering).
  const widthRaw = pick(m, 'borderWidth');
  const colorRaw = pick(m, 'borderColor');
  const styleRaw = pick(m, 'borderStyle');
  const multi = (v: any) => typeof v === 'string' && splitTopLevel(v.trim(), ' ').filter((p) => p).length > 1;
  if (any && (widthRaw != null || colorRaw != null || styleRaw != null)) {
    const widths = widthRaw != null ? expandFour(splitTopLevel(String(widthRaw).trim(), ' ').filter((p) => p).map((w) => parseDouble(w, emBase) ?? 0)) : null;
    const colors = colorRaw != null ? expandFour(splitTopLevel(String(colorRaw).trim(), ' ').filter((p) => p).map((c) => parseColor(c) ?? 0xff000000)) : null;
    const styles = styleRaw != null ? expandFour(String(styleRaw).trim().split(/\s+/).map((x) => x.toLowerCase() as BorderStyleName)) : null;
    const sides = [top, right, bottom, left].map((side, i) =>
      side
        ? {
            width: widths?.[i] ?? side.width,
            color: colors?.[i] ?? side.color,
            style: styles?.[i] ?? side.style,
          }
        : side,
    );
    [top, right, bottom, left] = sides;
  } else if (!any && (multi(widthRaw) || multi(colorRaw) || multi(styleRaw)) && (widthRaw != null || styleRaw != null)) {
    const widths = expandFour(splitTopLevel(String(widthRaw ?? '1').trim(), ' ').filter((p) => p).map((w) => parseDouble(w, emBase) ?? 0));
    const colors = expandFour(splitTopLevel(String(colorRaw ?? '#000').trim(), ' ').filter((p) => p).map((c) => parseColor(c) ?? 0xff000000));
    const styles = expandFour(String(styleRaw ?? 'solid').trim().split(/\s+/).map((x) => x.toLowerCase() as BorderStyleName));
    [top, right, bottom, left] = [0, 1, 2, 3].map((i) => ({ width: widths[i], color: colors[i], style: styles[i] }));
    any = true;
  }

  if (!any) return null;
  return { top: top ?? none, right: right ?? none, bottom: bottom ?? none, left: left ?? none };
}

function parseBorderRadius(m: StyleMap, emBase: number | null): { px: BorderRadius | null; percent: BorderRadius | null } {
  const px: BorderRadius = { topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0 };
  const pct: BorderRadius = { topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0 };
  let anyPx = false;
  let anyPct = false;
  const corners: (keyof BorderRadius)[] = ['topLeft', 'topRight', 'bottomRight', 'bottomLeft'];

  const assign = (corner: keyof BorderRadius, token: any) => {
    if (token == null) return;
    if (typeof token === 'string' && token.trim().endsWith('%')) {
      const n = parseFloat(token);
      if (Number.isFinite(n)) {
        pct[corner] = n;
        px[corner] = 0;
        anyPct = true;
      }
      return;
    }
    const n = parseDouble(token, emBase);
    if (n != null) {
      px[corner] = n;
      pct[corner] = 0;
      anyPx = true;
    }
  };

  const all = pick(m, 'borderRadius');
  if (all != null) {
    if (typeof all === 'object' && !Array.isArray(all)) {
      for (const c of corners) assign(c, all[c] ?? all[c.replace(/[A-Z]/g, (x) => '-' + x.toLowerCase())]);
    } else if (typeof all === 'number') {
      for (const c of corners) assign(c, all);
    } else {
      // `a b c d` (elliptical `/` forms use the horizontal radius).
      const horizontal = String(stripImportant(all)).split('/')[0].trim().split(/\s+/).filter((p) => p);
      if (horizontal.length) {
        const four = expandFour(horizontal);
        corners.forEach((c, i) => assign(c, four[i]));
      }
    }
  }
  const longhand: Record<keyof BorderRadius, string> = {
    topLeft: 'borderTopLeftRadius',
    topRight: 'borderTopRightRadius',
    bottomRight: 'borderBottomRightRadius',
    bottomLeft: 'borderBottomLeftRadius',
  };
  for (const c of corners) assign(c, pick(m, longhand[c]));
  return { px: anyPx ? px : null, percent: anyPct ? pct : null };
}

// ============================================================================
// Shadows
// ============================================================================

export function parseBoxShadow(value: any): BoxShadow[] | null {
  if (value == null) return null;
  if (Array.isArray(value)) {
    return value.map((shadow) => {
      if (shadow && typeof shadow === 'object') {
        const offset = parseOffset(shadow.offset) ?? { dx: parseDouble(shadow.dx ?? shadow.x) ?? 0, dy: parseDouble(shadow.dy ?? shadow.y) ?? 0 };
        return {
          color: parseColor(shadow.color) ?? 0x42000000,
          dx: offset.dx,
          dy: offset.dy,
          blur: parseDouble(shadow.blurRadius ?? shadow.blur) ?? 0,
          spread: parseDouble(shadow.spreadRadius ?? shadow.spread) ?? 0,
          inset: shadow.inset === true,
        };
      }
      if (typeof shadow === 'string') return parseShadowString(shadow) ?? zeroShadow();
      return zeroShadow();
    });
  }
  if (typeof value === 'object') return parseBoxShadow([value]);
  if (typeof value === 'string') {
    const t = value.trim();
    if (t === '' || t === 'none') return null;
    const out = splitTopLevel(t, ',').map((s) => parseShadowString(s)).filter((s): s is BoxShadow => s != null);
    return out.length ? out : null;
  }
  return null;
}

function zeroShadow(): BoxShadow {
  return { color: 0xff000000, dx: 0, dy: 0, blur: 0, spread: 0 };
}

function parseShadowString(raw: string): BoxShadow | null {
  const tokens = splitTopLevel(raw.trim(), ' ').filter((p) => p);
  const lengths: number[] = [];
  let color: Color | null = null;
  let inset = false;
  for (const token of tokens) {
    if (token.toLowerCase() === 'inset') inset = true;
    else if (/^-?[\d.]/.test(token)) lengths.push(parseDouble(token) ?? 0);
    else color = parseColor(token) ?? color;
  }
  if (lengths.length < 2) return null;
  return {
    dx: lengths[0],
    dy: lengths[1],
    blur: lengths[2] ?? 0,
    spread: lengths[3] ?? 0,
    color: color ?? 0xff000000,
    inset,
  };
}

function parseTextShadow(value: any): TextShadow[] | null {
  if (value == null) return null;
  if (typeof value === 'string' || (typeof value === 'object' && !Array.isArray(value))) {
    const boxes = parseBoxShadow(value);
    return boxes?.map((b) => ({ color: b.color, dx: b.dx, dy: b.dy, blur: b.blur })) ?? null;
  }
  if (Array.isArray(value)) {
    return value.map((shadow) => {
      if (shadow && typeof shadow === 'object') {
        const offset = parseOffset(shadow.offset) ?? { dx: 0, dy: 0 };
        return {
          color: parseColor(shadow.color) ?? 0x42000000,
          dx: offset.dx,
          dy: offset.dy,
          blur: parseDouble(shadow.blurRadius ?? shadow.blur) ?? 0,
        };
      }
      const parsed = typeof shadow === 'string' ? parseShadowString(shadow) : null;
      return parsed ? { color: parsed.color, dx: parsed.dx, dy: parsed.dy, blur: parsed.blur } : { color: 0xff000000, dx: 0, dy: 0, blur: 0 };
    });
  }
  return null;
}

// ============================================================================
// Transforms
// ============================================================================

function parseAngleDegrees(value: any): number | null {
  if (value == null) return null;
  if (typeof value === 'number') return value;
  const t = String(value).trim().toLowerCase();
  const n = parseFloat(t);
  if (!Number.isFinite(n)) return null;
  if (t.endsWith('rad')) return (n * 180) / Math.PI;
  if (t.endsWith('turn')) return n * 360;
  if (t.endsWith('grad')) return n * 0.9;
  return n;
}

function angleRadians(token: string): number {
  return ((parseAngleDegrees(token) ?? 0) * Math.PI) / 180;
}

export function parseTransform(value: any): Matrix4 | null {
  if (value == null) return null;
  if (Array.isArray(value) && value.length === 16) return value.map((e) => Number(e));
  if (typeof value !== 'string') return null;
  const t = value.trim();
  if (t === '' || t === 'none') return null;
  const re = /([a-zA-Z0-9]+)\(([^)]*)\)/g;
  let matrix = identity();
  let match: RegExpExecArray | null;
  let any = false;
  while ((match = re.exec(t)) !== null) {
    const fn = match[1].toLowerCase();
    const args = match[2].split(/[\s,]+/).filter((a) => a !== '');
    let step: Matrix4 | null = null;
    switch (fn) {
      case 'translate':
        step = translation(parseDouble(args[0]) ?? 0, parseDouble(args[1]) ?? 0, 0);
        break;
      case 'translatex':
        step = translation(parseDouble(args[0]) ?? 0, 0, 0);
        break;
      case 'translatey':
        step = translation(0, parseDouble(args[0]) ?? 0, 0);
        break;
      case 'translate3d':
        step = translation(parseDouble(args[0]) ?? 0, parseDouble(args[1]) ?? 0, parseDouble(args[2]) ?? 0);
        break;
      case 'rotate':
      case 'rotatez':
        step = rotationZ(angleRadians(args[0] ?? '0'));
        break;
      case 'scale': {
        const sx = parseFloat(args[0] ?? '1');
        const sy = args.length > 1 ? parseFloat(args[1]) : sx;
        step = scaling(sx, sy, 1);
        break;
      }
      case 'scalex':
        step = scaling(parseFloat(args[0] ?? '1'), 1, 1);
        break;
      case 'scaley':
        step = scaling(1, parseFloat(args[0] ?? '1'), 1);
        break;
      case 'skew':
        step = skew(angleRadians(args[0] ?? '0'), angleRadians(args[1] ?? '0'));
        break;
      case 'skewx':
        step = skew(angleRadians(args[0] ?? '0'), 0);
        break;
      case 'skewy':
        step = skew(0, angleRadians(args[0] ?? '0'));
        break;
      case 'matrix':
      case 'matrix3d':
        step = fromCssMatrix(args.map((a) => parseFloat(a)));
        break;
      default:
        step = null;
    }
    if (step) {
      matrix = multiply(matrix, step);
      any = true;
    }
  }
  return any ? matrix : null;
}

// ============================================================================
// Gradients and backgrounds
// ============================================================================

export function isGradientValue(value: any): boolean {
  return typeof value === 'string' && value.includes('gradient(');
}

function extractUrl(value: string): string | null {
  const m = /url\(\s*(['"]?)(.*?)\1\s*\)/.exec(value);
  if (m) return m[2];
  const t = value.trim();
  return t === '' || t === 'none' ? null : t;
}

export function splitTopLevel(input: string, separator: string): string[] {
  const out: string[] = [];
  let depth = 0;
  let quote: string | null = null;
  let start = 0;
  for (let i = 0; i < input.length; i++) {
    const ch = input[i];
    if (quote) {
      if (ch === quote) quote = null;
      continue;
    }
    if (ch === '"' || ch === "'") quote = ch;
    else if (ch === '(') depth++;
    else if (ch === ')') depth = Math.max(0, depth - 1);
    else if (depth === 0 && (separator === ' ' ? /\s/.test(ch) : ch === separator)) {
      out.push(input.substring(start, i));
      start = i + 1;
    }
  }
  out.push(input.substring(start));
  return separator === ' ' ? out.filter((s) => s.trim() !== '') : out;
}

function angleForSideKeyword(side: string): number {
  switch (side.replace(/\s+/g, ' ').trim()) {
    case 'top':
      return 0;
    case 'top right':
    case 'right top':
      return 45;
    case 'right':
      return 90;
    case 'bottom right':
    case 'right bottom':
      return 135;
    case 'bottom':
      return 180;
    case 'bottom left':
    case 'left bottom':
      return 225;
    case 'left':
      return 270;
    case 'top left':
    case 'left top':
      return 315;
    default:
      return 180;
  }
}

/**
 * Begin/end alignments for a CSS angle. Flutter snaps to the nearest 45°
 * (eight compass directions); arbitrary angles are expressed exactly here
 * with alignments on the unit square, which is the same line for the eight
 * snapped angles.
 */
export function beginEndForAngle(deg: number): [Alignment, Alignment] {
  const a = (((deg % 360) + 360) % 360) * (Math.PI / 180);
  // CSS: 0deg points up, angles turn clockwise.
  const dx = Math.sin(a);
  const dy = -Math.cos(a);
  const scale = 1 / Math.max(Math.abs(dx), Math.abs(dy));
  const ex = dx * scale;
  const ey = dy * scale;
  const round = (v: number) => (Math.abs(v) < 1e-9 ? 0 : v);
  return [
    { x: round(-ex), y: round(-ey) },
    { x: round(ex), y: round(ey) },
  ];
}

function parseCssGradientString(raw: string): Gradient | null {
  const s = raw.trim();
  const lower = s.toLowerCase();
  const kind: Gradient['kind'] = lower.includes('radial-gradient') ? 'radial' : lower.includes('conic-gradient') ? 'sweep' : 'linear';
  const repeat = lower.startsWith('repeating-');
  const open = s.indexOf('(');
  const close = s.lastIndexOf(')');
  if (open < 0 || close <= open) return null;
  const parts = splitTopLevel(s.substring(open + 1, close), ',');
  if (parts.length === 0) return null;

  let angleDeg: number | null = null;
  let center: Alignment | undefined;
  let startAngle = 0;
  let colorParts = parts;
  const first = parts[0].trim().toLowerCase();
  if (kind === 'linear') {
    if (/^-?[\d.]+(deg|rad|turn|grad)$/.test(first)) {
      angleDeg = parseAngleDegrees(first);
      colorParts = parts.slice(1);
    } else if (first.startsWith('to ')) {
      angleDeg = angleForSideKeyword(first.substring(3));
      colorParts = parts.slice(1);
    }
  } else if (kind === 'radial') {
    if (!looksLikeColorStop(first)) {
      const at = first.indexOf('at ');
      if (at >= 0) center = parsePositionKeywords(first.substring(at + 3).trim()) ?? undefined;
      colorParts = parts.slice(1);
    }
  } else {
    if (!looksLikeColorStop(first)) {
      const from = /from\s+(-?[\d.]+\w*)/.exec(first);
      if (from) startAngle = angleRadians(from[1]);
      const at = first.indexOf('at ');
      if (at >= 0) center = parsePositionKeywords(first.substring(at + 3).trim()) ?? undefined;
      colorParts = parts.slice(1);
    }
  }

  const colors: Color[] = [];
  const stops: (number | null)[] = [];
  for (const part of colorParts) {
    const t = part.trim();
    if (t === '') continue;
    const tokens = splitTopLevel(t, ' ');
    const color = parseColor(tokens[0]);
    if (color == null) continue;
    const positions = tokens.slice(1).map((p) => parseStopPosition(p));
    if (positions.length === 0) {
      colors.push(color);
      stops.push(null);
    } else {
      for (const pos of positions) {
        colors.push(color);
        stops.push(pos);
      }
    }
  }
  if (colors.length === 0) return null;
  if (colors.length === 1) {
    colors.push(colors[0]);
    stops.push(null);
  }
  const resolvedStops = resolveStops(stops);

  if (kind === 'radial') {
    return { kind, colors, stops: resolvedStops, center: center ?? Align.center, radius: 0.5, repeat };
  }
  if (kind === 'sweep') {
    // CSS conic gradients start at 12 o'clock; Flutter sweeps start at 3 o'clock.
    return {
      kind,
      colors,
      stops: resolvedStops,
      center: center ?? Align.center,
      startAngle: startAngle - Math.PI / 2,
      endAngle: startAngle - Math.PI / 2 + Math.PI * 2,
      repeat,
    };
  }
  const [begin, end] = beginEndForAngle(angleDeg ?? 180);
  return { kind, colors, stops: resolvedStops, begin, end, repeat };
}

function looksLikeColorStop(token: string): boolean {
  return parseColor(splitTopLevel(token, ' ')[0]) != null;
}

function parseStopPosition(token: string): number | null {
  const t = token.trim();
  if (t.endsWith('%')) {
    const n = parseFloat(t);
    return Number.isFinite(n) ? Math.max(0, Math.min(1, n / 100)) : null;
  }
  if (/deg$|turn$/.test(t)) return (parseAngleDegrees(t) ?? 0) / 360;
  return null;
}

/** Fill missing stop positions by spreading evenly between known ones (CSS rules). */
function resolveStops(stops: (number | null)[]): number[] | null {
  if (stops.every((s) => s == null)) return null;
  const out = stops.slice();
  if (out[0] == null) out[0] = 0;
  if (out[out.length - 1] == null) out[out.length - 1] = 1;
  let i = 0;
  while (i < out.length) {
    if (out[i] != null) {
      i++;
      continue;
    }
    const startIdx = i - 1;
    let endIdx = i;
    while (out[endIdx] == null) endIdx++;
    const a = out[startIdx] as number;
    const b = out[endIdx] as number;
    const span = endIdx - startIdx;
    for (let k = startIdx + 1; k < endIdx; k++) out[k] = a + ((b - a) * (k - startIdx)) / span;
    i = endIdx;
  }
  // Monotonic, as CSS requires.
  for (let k = 1; k < out.length; k++) if ((out[k] as number) < (out[k - 1] as number)) out[k] = out[k - 1];
  return out as number[];
}

function parseGradientLayers(value: string): Gradient[] {
  return splitTopLevel(value, ',')
    .map((layer) => layer.trim())
    .filter((layer) => isGradientValue(layer))
    .map((layer) => parseCssGradientString(layer))
    .filter((g): g is Gradient => g != null);
}

export function parseGradient(value: any): Gradient | null {
  if (value == null) return null;
  if (typeof value === 'string') {
    const layers = parseGradientLayers(value);
    return layers[0] ?? null;
  }
  if (typeof value === 'object' && !Array.isArray(value)) {
    const type = String(value.type ?? 'linear').toLowerCase();
    const colors = Array.isArray(value.colors) ? value.colors.map((c: any) => parseColor(c) ?? 0x00000000) : null;
    if (!colors || colors.length === 0) return null;
    const stops = parseNumberList(value.stops);
    if (type === 'linear') {
      return {
        kind: 'linear',
        colors,
        stops,
        begin: parseAlignment(value.begin) ?? Align.topCenter,
        end: parseAlignment(value.end) ?? Align.bottomCenter,
      };
    }
    if (type === 'radial') {
      return { kind: 'radial', colors, stops, center: parseAlignment(value.center) ?? Align.center, radius: parseDouble(value.radius) ?? 0.5 };
    }
    if (type === 'sweep') {
      return {
        kind: 'sweep',
        colors,
        stops,
        center: parseAlignment(value.center) ?? Align.center,
        startAngle: parseDouble(value.startAngle) ?? 0,
        endAngle: parseDouble(value.endAngle) ?? Math.PI * 2,
      };
    }
  }
  return null;
}

function parseBackgroundShorthand(value: string): { color: Color | null; gradients: Gradient[]; image: string | null } {
  const layers = splitTopLevel(value.trim(), ',');
  const gradients: Gradient[] = [];
  let color: Color | null = null;
  let image: string | null = null;
  for (const layer of layers) {
    const t = layer.trim();
    if (isGradientValue(t)) {
      const g = parseCssGradientString(t.substring(t.search(/(repeating-)?(linear|radial|conic)-gradient\(/)));
      if (g) gradients.push(g);
      continue;
    }
    if (t.includes('url(')) {
      image = extractUrl(t);
    }
    for (const token of splitTopLevel(t, ' ')) {
      const c = parseColor(token);
      if (c != null) color = c;
    }
  }
  return { color, gradients, image };
}

function parseColorList(value: any): Color[] | null {
  if (!Array.isArray(value)) return null;
  const out = value.map((c) => parseColor(c)).filter((c): c is Color => c != null);
  return out.length ? out : null;
}

function parseNumberList(value: any): number[] | null {
  if (!Array.isArray(value)) return null;
  const out = value.map((c) => parseDouble(c)).filter((c): c is number => c != null);
  return out.length ? out : null;
}

// ============================================================================
// Filters
// ============================================================================

function parseFilter(value: any): Filter | null {
  if (typeof value !== 'string') return null;
  const t = value.trim();
  if (t === '' || t === 'none') return null;
  const f: Filter = {};
  const re = /([a-z-]+)\(([^()]*(?:\([^()]*\)[^()]*)*)\)/gi;
  let m: RegExpExecArray | null;
  const amount = (arg: string, def: number) => {
    const a = arg.trim();
    if (a === '') return def;
    if (a.endsWith('%')) return parseFloat(a) / 100;
    return parseFloat(a);
  };
  while ((m = re.exec(t)) !== null) {
    const name = m[1].toLowerCase();
    const arg = m[2];
    switch (name) {
      case 'blur':
        f.blur = parseDouble(arg) ?? 0;
        break;
      case 'brightness':
        f.brightness = amount(arg, 1);
        break;
      case 'contrast':
        f.contrast = amount(arg, 1);
        break;
      case 'grayscale':
        f.grayscale = amount(arg, 1);
        break;
      case 'hue-rotate':
        f.hueRotate = parseAngleDegrees(arg) ?? 0;
        break;
      case 'invert':
        f.invert = amount(arg, 1);
        break;
      case 'saturate':
        f.saturate = amount(arg, 1);
        break;
      case 'sepia':
        f.sepia = amount(arg, 1);
        break;
      case 'opacity':
        f.opacity = amount(arg, 1);
        break;
      case 'drop-shadow': {
        const s = parseShadowString(arg);
        if (s) f.dropShadow = { color: s.color, dx: s.dx, dy: s.dy, blur: s.blur };
        break;
      }
    }
  }
  return Object.keys(f).length ? f : null;
}

// ============================================================================
// Time
// ============================================================================

/** Milliseconds. Flutter: ints are ms; `s`/`ms` suffixes are honoured. */
export function parseDuration(value: any): number | null {
  if (value == null) return null;
  if (typeof value === 'number') return Math.trunc(value);
  if (typeof value !== 'string') return null;
  const t = value.trim().toLowerCase();
  if (t.endsWith('ms')) {
    const n = parseFloat(t);
    return Number.isFinite(n) ? Math.trunc(n) : null;
  }
  if (t.endsWith('s')) {
    const n = parseFloat(t);
    return Number.isFinite(n) ? Math.trunc(n * 1000) : null;
  }
  const n = Number.parseInt(t.replace(/[^0-9]/g, ''), 10);
  return Number.isFinite(n) ? n : null;
}

/** Normalise a curve name to the lowercase, dash-free key the curve table uses. */
export function normalizeCurve(value: any): string | null {
  if (typeof value !== 'string') return null;
  const t = value.trim();
  if (t === '') return null;
  if (t.startsWith('cubic-bezier(') || t.startsWith('steps(')) return t.toLowerCase();
  return t.toLowerCase().replace(/[-_\s]/g, '');
}

function parseTransitionShorthand(value: string, s: CSSStyle): void {
  // `transition: opacity 300ms ease-in-out 100ms` (first layer wins).
  const first = splitTopLevel(value, ',')[0];
  const tokens = splitTopLevel(first, ' ');
  const times: number[] = [];
  for (const token of tokens) {
    if (/^[\d.]+m?s$/.test(token)) times.push(parseDuration(token) ?? 0);
    else if (/^(ease|linear|step|cubic-bezier|steps)/.test(token)) s.transitionCurve ??= normalizeCurve(token);
    else s.transitionProperty ??= token;
  }
  if (times.length > 0) s.transitionDuration ??= times[0];
  if (times.length > 1) s.transitionDelay ??= times[1];
}

function parseAnimationShorthand(value: string, s: CSSStyle): void {
  const first = splitTopLevel(value, ',')[0];
  const tokens = splitTopLevel(first, ' ');
  const times: number[] = [];
  for (const token of tokens) {
    const lower = token.toLowerCase();
    if (/^[\d.]+m?s$/.test(lower)) times.push(parseDuration(lower) ?? 0);
    else if (/^(ease|linear|step|cubic-bezier|steps)/.test(lower)) s.animationTimingFunction ??= lower;
    else if (lower === 'infinite') s.animationIterationCount ??= -1;
    else if (/^\d+$/.test(lower)) s.animationIterationCount ??= Number.parseInt(lower, 10);
    else if (['normal', 'reverse', 'alternate', 'alternate-reverse'].includes(lower)) s.animationDirection ??= lower;
    else if (['forwards', 'backwards', 'both'].includes(lower)) s.animationFillMode ??= lower;
    else if (['running', 'paused'].includes(lower)) s.animationPlayState ??= lower;
    else if (lower !== 'none') s.animationName ??= token;
  }
  if (times.length > 0) s.animationDuration ??= times[0];
  if (times.length > 1) s.animationDelay ??= times[1];
}

function parseKeyframes(value: any): Keyframe[] | null {
  if (!Array.isArray(value)) return null;
  const out: Keyframe[] = [];
  for (const frame of value) {
    if (frame && typeof frame === 'object' && !Array.isArray(frame)) {
      const offset = parseDouble(frame.offset);
      const styles = frame.styles;
      if (offset != null && styles && typeof styles === 'object') out.push({ offset, styles });
      else out.push({ offset: offset ?? 0, styles: frame as Record<string, unknown> });
    }
  }
  return out.length ? out : null;
}
