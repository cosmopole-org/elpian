/**
 * Lowering helpers — the TypeScript twin of `CSSProperties.applyStyle` and of
 * Flutter's `Container` composition. They wrap a widget descriptor in the same
 * sequence of layout/paint objects the Flutter engine wraps its widgets in,
 * so the box model, stacking and clipping come out identical.
 */
import type { CSSStyle } from '../css/style.js';
import {
  borderAll,
  borderInsets,
  type Alignment,
  type Border,
  type BoxShadow,
  type EdgeInsets,
  type Gradient,
} from '../css/types.js';
import { identity, multiply, rotationZ, scaling, translation } from '../css/matrix.js';
import { w, type W } from '../render/object.js';
import type { Decoration } from '../render/paint/box.js';
import { textStyleFromCss, type TextStyle } from '../render/text-style.js';
import type { BuildContext } from './context.js';

export const SHRINK: W = w('constrained', { width: 0, height: 0 });

export function sizedBox(width: number | null, height: number | null, child?: W | null): W {
  return w('constrained', { width, height }, child ?? null);
}

export function padding(insets: EdgeInsets, child: W | null, percent?: any): W {
  return w('padding', { padding: insets, percent: percent ?? null }, child);
}

export function align(alignment: Alignment, child: W | null, factors?: { widthFactor?: number | null; heightFactor?: number | null }): W {
  return w('align', { alignment, widthFactor: factors?.widthFactor ?? null, heightFactor: factors?.heightFactor ?? null }, child);
}

export function center(child: W | null): W {
  return align({ x: 0, y: 0 }, child);
}

export function column(children: W[], opts: Record<string, any> = {}): W {
  return w('flex', { direction: 'column', mainAxisAlignment: 'start', crossAxisAlignment: 'center', mainAxisSize: 'max', ...opts }, children);
}

export function row(children: W[], opts: Record<string, any> = {}): W {
  return w('flex', { direction: 'row', mainAxisAlignment: 'start', crossAxisAlignment: 'center', mainAxisSize: 'max', ...opts }, children);
}

export function expanded(child: W, flex = 1): W {
  return w('flexible', { flex, fit: 'tight' }, child);
}

export function flexible(child: W, flex = 1, fit: 'tight' | 'loose' = 'loose'): W {
  return w('flexible', { flex, fit }, child);
}

export function text(value: string, style?: TextStyle | null, opts: Record<string, any> = {}): W {
  return w('text', { text: value, style: style ?? null, ...opts });
}

export function decorated(decoration: Decoration, child: W | null): W {
  return w('decorated', { decoration }, child);
}

/** `kElevationToShadow` from Flutter's material shadows. */
const ELEVATION_SHADOWS: Record<number, BoxShadow[]> = {
  0: [],
  1: [
    { dx: 0, dy: 2, blur: 1, spread: -1, color: 0x33000000 },
    { dx: 0, dy: 1, blur: 1, spread: 0, color: 0x24000000 },
    { dx: 0, dy: 1, blur: 3, spread: 0, color: 0x1f000000 },
  ],
  2: [
    { dx: 0, dy: 3, blur: 1, spread: -2, color: 0x33000000 },
    { dx: 0, dy: 2, blur: 2, spread: 0, color: 0x24000000 },
    { dx: 0, dy: 1, blur: 5, spread: 0, color: 0x1f000000 },
  ],
  3: [
    { dx: 0, dy: 3, blur: 3, spread: -2, color: 0x33000000 },
    { dx: 0, dy: 3, blur: 4, spread: 0, color: 0x24000000 },
    { dx: 0, dy: 1, blur: 8, spread: 0, color: 0x1f000000 },
  ],
  4: [
    { dx: 0, dy: 2, blur: 4, spread: -1, color: 0x33000000 },
    { dx: 0, dy: 4, blur: 5, spread: 0, color: 0x24000000 },
    { dx: 0, dy: 1, blur: 10, spread: 0, color: 0x1f000000 },
  ],
  6: [
    { dx: 0, dy: 3, blur: 5, spread: -1, color: 0x33000000 },
    { dx: 0, dy: 6, blur: 10, spread: 0, color: 0x24000000 },
    { dx: 0, dy: 1, blur: 18, spread: 0, color: 0x1f000000 },
  ],
  8: [
    { dx: 0, dy: 5, blur: 5, spread: -3, color: 0x33000000 },
    { dx: 0, dy: 8, blur: 10, spread: 1, color: 0x24000000 },
    { dx: 0, dy: 3, blur: 14, spread: 2, color: 0x1f000000 },
  ],
  12: [
    { dx: 0, dy: 7, blur: 8, spread: -4, color: 0x33000000 },
    { dx: 0, dy: 12, blur: 17, spread: 2, color: 0x24000000 },
    { dx: 0, dy: 5, blur: 22, spread: 4, color: 0x1f000000 },
  ],
  16: [
    { dx: 0, dy: 8, blur: 10, spread: -5, color: 0x33000000 },
    { dx: 0, dy: 16, blur: 24, spread: 2, color: 0x24000000 },
    { dx: 0, dy: 6, blur: 30, spread: 5, color: 0x1f000000 },
  ],
  24: [
    { dx: 0, dy: 11, blur: 15, spread: -7, color: 0x33000000 },
    { dx: 0, dy: 24, blur: 38, spread: 3, color: 0x24000000 },
    { dx: 0, dy: 9, blur: 46, spread: 8, color: 0x1f000000 },
  ],
};

export function elevationShadows(elevation: number): BoxShadow[] {
  if (elevation <= 0) return [];
  const keys = Object.keys(ELEVATION_SHADOWS).map(Number);
  let best = keys[0];
  for (const k of keys) if (Math.abs(k - elevation) < Math.abs(best - elevation)) best = k;
  return ELEVATION_SHADOWS[best];
}

/** The `BoxDecoration` a Flutter `Container` would build from this style. */
export function decorationFromStyle(style: CSSStyle, ctx?: BuildContext): Decoration {
  const gradients: Gradient[] = [];
  if (style.gradientLayers) gradients.push(...[...style.gradientLayers].reverse());
  if (style.gradient) gradients.push(style.gradient);
  let border: Border | null = style.border ?? null;
  if (!border && style.borderWidth != null && (style.borderColor != null || (style.borderStyle && style.borderStyle !== 'none'))) {
    border = borderAll({
      width: style.borderWidth,
      color: style.borderColor ?? style.color ?? 0xff000000,
      style: (style.borderStyle as any) && style.borderStyle !== 'solid' ? (style.borderStyle as any) : 'solid',
    });
  }
  const image = style.backgroundImage
    ? {
        src: ctx ? ctx.engine.resolveUrl(style.backgroundImage) : style.backgroundImage,
        fit: style.backgroundSize ?? null,
        alignment: style.backgroundPosition ?? null,
        repeat: style.backgroundRepeat ?? null,
        size: style.backgroundSizePx ?? null,
      }
    : null;
  return {
    color: style.backgroundColor ?? null,
    gradients: gradients.length ? gradients : null,
    image,
    border,
    radius: style.borderRadius ?? null,
    radiusPercent: style.borderRadiusPercent ?? null,
    shape: style.shape ?? null,
    shadows: style.boxShadow && style.boxShadow.length ? style.boxShadow : null,
    outline:
      style.outlineWidth != null && style.outlineWidth > 0 && style.outlineStyle !== 'none'
        ? { width: style.outlineWidth, color: style.outlineColor ?? style.color ?? 0xff000000, style: style.outlineStyle ?? 'solid', offset: style.outlineOffset ?? 0 }
        : null,
  };
}

function needsContainer(style: CSSStyle): boolean {
  return (
    style.padding != null ||
    style.paddingPercent != null ||
    style.backgroundColor != null ||
    style.gradient != null ||
    style.border != null ||
    style.borderRadius != null ||
    style.borderRadiusPercent != null ||
    style.boxShadow != null ||
    style.borderColor != null ||
    style.backgroundImage != null ||
    style.shape === 'circle' ||
    (style.outlineWidth != null && style.outlineWidth > 0)
  );
}

function clips(o: string | null | undefined): boolean {
  return o === 'hidden' || o === 'clip';
}

/** `_flexSingleChildAlignment`: centre a lone child inside a fixed-size flex box. */
function flexSingleChildAlignment(style: CSSStyle): Alignment {
  const isColumn = style.flexDirection === 'column' || style.flexDirection === 'column-reverse';
  const factor = (v: string | null | undefined) => {
    switch ((v ?? '').toLowerCase()) {
      case 'center':
        return 0;
      case 'flex-end':
      case 'end':
        return 1;
      default:
        return -1;
    }
  };
  const main = factor(style.justifyContent);
  const cross = factor(style.alignItems);
  return isColumn ? { x: cross, y: main } : { x: main, y: cross };
}

/** The transform `applyStyle` builds (rotate / scale replace the matrix, as in Flutter). */
export function styleTransform(style: CSSStyle): number[] | null {
  if (style.transform == null && style.rotate == null && style.scale == null && style.translate == null && style.scaleX == null && style.scaleY == null) {
    return null;
  }
  let m = style.transform ?? identity();
  if (style.rotate != null) m = rotationZ((style.rotate * Math.PI) / 180);
  if (style.scale != null) m = scaling(style.scale, style.scale, 1);
  if (style.scaleX != null || style.scaleY != null) m = multiply(m, scaling(style.scaleX ?? 1, style.scaleY ?? 1, 1));
  if (style.translate) m = multiply(translation(style.translate.dx, style.translate.dy), m);
  return m;
}

export interface ApplyStyleOptions {
  applyFlex?: boolean;
  layoutHandled?: boolean;
}

/**
 * `CSSProperties.applyStyle` — wraps [child] with the style's effects, from
 * the innermost wrapper to the outermost, in Flutter's exact order:
 *
 *   flex-single-child Align → Opacity → Transform → Visibility → Align →
 *   scroll / clip → AspectRatio → ConstrainedBox+SizedBox → Container
 *   (padding + decoration) → margin → FractionallySizedBox → transitions →
 *   IgnorePointer → Flexible
 *
 * plus the properties Flutter parses but never applies (filters, outlines,
 * `visibility: hidden`, keyframe animations, `margin: auto`).
 */
export function applyStyle(child: W, style: CSSStyle | null | undefined, opts: ApplyStyleOptions = {}, ctx?: BuildContext): W {
  if (!style) return child;
  const applyFlex = opts.applyFlex ?? true;
  const animated = style.transitionDuration != null && style.transitionDuration > 0;
  const dur = style.transitionDuration ?? 0;
  const curve = style.transitionCurve ?? null;
  let result = child;

  if (!opts.layoutHandled && (style.display === 'flex' || style.display === 'inline-flex') && style.width != null && style.height != null) {
    const a = flexSingleChildAlignment(style);
    if (a.x !== -1 || a.y !== -1) result = align(a, result);
  }

  // Opacity (animated when the style transitions).
  if (style.opacity != null && (style.opacity < 1 || animated)) {
    result = animated
      ? w('animatedOpacity', { opacity: style.opacity, duration: dur, curve }, result)
      : w('opacity', { opacity: style.opacity }, result);
  }

  // Transform.
  const matrix = styleTransform(style);
  if (matrix) {
    result = animated
      ? w('animatedTransform', { transform: matrix, alignment: style.transformOrigin ?? { x: 0, y: 0 }, duration: dur, curve }, result)
      : w('transform', { transform: matrix, alignment: style.transformOrigin ?? { x: 0, y: 0 } }, result);
  }

  // Filters (blur, brightness, drop-shadow …) and blend modes.
  if (style.filter || style.backdropFilter || style.mixBlendMode) {
    result = w('filter', { filter: style.filter ?? null, backdrop: style.backdropFilter ?? null, blendMode: style.mixBlendMode ?? null }, result);
  }

  // Visibility.
  if (style.visible === false) result = w('visibility', { mode: 'gone' }, result);
  else if (style.visibility === 'hidden' || style.visibility === 'collapse') result = w('visibility', { mode: 'hidden' }, result);

  // Alignment.
  if (style.alignment) {
    result = animated ? w('animatedAlign', { alignment: style.alignment, duration: dur, curve }, result) : align(style.alignment, result);
  }

  // Overflow: scroll when the axis is bounded by this node, else clip.
  const overflowX = style.overflowX ?? style.overflow ?? null;
  const overflowY = style.overflowY ?? style.overflow ?? null;
  const boundedW = style.width != null || style.maxWidth != null || style.widthFactor != null;
  const boundedH = style.height != null || style.maxHeight != null || style.heightFactor != null;
  const scrollY = overflowY === 'scroll' && boundedH;
  const scrollX = overflowX === 'scroll' && boundedW;
  if (scrollY || scrollX) {
    result = w('scroll', { axis: scrollY && scrollX ? 'both' : scrollY ? 'vertical' : 'horizontal' }, result);
  } else if (clips(overflowX) || clips(overflowY) || overflowX === 'scroll' || overflowY === 'scroll') {
    result = w(
      'clip',
      { radius: style.borderRadius ?? null, oval: style.shape === 'circle' },
      result,
    );
  }

  // Aspect ratio.
  if (style.aspectRatio != null && !(style.width != null && style.height != null)) {
    result = w('aspectRatio', { aspectRatio: style.aspectRatio }, result);
  }

  // Size constraints (percentage axes are handled by the fractional wrapper below).
  const wf = style.widthFactor ?? null;
  const hf = style.heightFactor ?? null;
  const fixedWidth = wf == null ? style.width ?? null : null;
  const fixedHeight = hf == null ? style.height ?? null : null;
  if (fixedWidth != null || fixedHeight != null || style.minWidth != null || style.maxWidth != null || style.minHeight != null || style.maxHeight != null) {
    const sized = { width: fixedWidth, height: fixedHeight };
    const inner =
      fixedWidth != null || fixedHeight != null
        ? animated
          ? w('animatedConstrained', { ...sized, duration: dur, curve }, result)
          : w('constrained', sized, result)
        : result;
    result = w(
      'constrained',
      { minWidth: style.minWidth ?? 0, maxWidth: style.maxWidth ?? null, minHeight: style.minHeight ?? 0, maxHeight: style.maxHeight ?? null },
      inner,
    );
  }

  // Container: padding (+ border insets) and decoration.
  if (needsContainer(style)) {
    const decoration = decorationFromStyle(style, ctx);
    const insets = borderInsets(decoration.border);
    const pad = style.padding ?? { top: 0, right: 0, bottom: 0, left: 0 };
    const effective = { top: pad.top + insets.top, right: pad.right + insets.right, bottom: pad.bottom + insets.bottom, left: pad.left + insets.left };
    if (effective.top || effective.right || effective.bottom || effective.left || style.paddingPercent) {
      result = animated
        ? w('animatedPadding', { padding: effective, percent: style.paddingPercent ?? null, duration: dur, curve }, result)
        : padding(effective, result, style.paddingPercent);
    }
    const hasPaint =
      decoration.color != null ||
      decoration.gradients ||
      decoration.image ||
      decoration.border ||
      decoration.shadows ||
      decoration.outline ||
      decoration.radius ||
      decoration.radiusPercent ||
      decoration.shape === 'circle';
    if (hasPaint) {
      result = animated ? w('animatedDecorated', { decoration, duration: dur, curve }, result) : decorated(decoration, result);
    }
  }

  // Keyframe animation (`animation-name` resolved against the stylesheet).
  if (style.animationName && ctx) {
    const frames = (style.keyframes as any) ?? ctx.engine.services.stylesheets.keyframes(style.animationName);
    if (frames && frames.length) {
      result = w(
        'keyframes',
        {
          frames,
          duration: style.animationDuration ?? 1000,
          delay: style.animationDelay ?? 0,
          iterations: style.animationIterationCount ?? 1,
          direction: style.animationDirection ?? 'normal',
          fillMode: style.animationFillMode ?? 'none',
          timing: style.animationTimingFunction ?? 'ease',
          playState: style.animationPlayState ?? 'running',
        },
        result,
      );
    }
  }

  // Margin (with `auto` margins centring the box).
  if (style.margin || style.marginPercent) {
    const m = style.margin ?? { top: 0, right: 0, bottom: 0, left: 0 };
    if (m.top || m.right || m.bottom || m.left || style.marginPercent) result = padding(m, result, style.marginPercent);
  }
  if (style.marginAuto && (style.marginAuto.left || style.marginAuto.right)) {
    const ax = style.marginAuto.left && style.marginAuto.right ? 0 : style.marginAuto.left ? 1 : -1;
    // Expands horizontally within a bounded parent and places the box there.
    result = w('align', { alignment: { x: ax, y: -1 }, heightFactor: 1 }, result);
  }

  // Percentage width/height relative to the parent.
  if (wf != null || hf != null) {
    result = w(
      'fractional',
      { widthFactor: wf, heightFactor: hf, alignment: { x: -1, y: 0 }, fallbackWidth: wf != null ? style.width ?? null : null, fallbackHeight: hf != null ? style.height ?? null : null },
      result,
    );
  }

  // pointer-events: none.
  if (style.pointerEvents === 'none') result = w('ignorePointer', { ignoring: true }, result);

  // Flex (outermost, so it is a direct child of the flex box).
  if (applyFlex) result = wrapFlex(result, style);
  return result;
}

/** Wrap [child] in Flexible when the style declares a flex factor (CSS `flex:n` → tight). */
export function wrapFlex(child: W, style: CSSStyle | null | undefined): W {
  if (!style) return child;
  const grow = style.flex ?? style.flexGrow ?? null;
  const basis = parseBasis(style.flexBasis);
  if (grow != null && grow > 0) {
    return w('flexible', { flex: grow, fit: 'tight', shrink: style.flexShrink ?? 1, alignSelf: alignSelfOf(style), basis }, child);
  }
  if (style.flexShrink != null || style.alignSelf != null || basis != null) {
    return w('flexible', { flex: 0, fit: 'loose', shrink: style.flexShrink ?? 1, alignSelf: alignSelfOf(style), basis }, child);
  }
  return child;
}

function parseBasis(basis: string | null | undefined): number | null {
  if (!basis || basis === 'auto' || basis === 'content') return null;
  const n = parseFloat(basis);
  if (!Number.isFinite(n) || basis.trim().endsWith('%')) return null;
  return n;
}

function alignSelfOf(style: CSSStyle): string | null {
  switch ((style.alignSelf ?? '').toLowerCase()) {
    case 'center':
      return 'center';
    case 'flex-end':
    case 'end':
      return 'end';
    case 'flex-start':
    case 'start':
      return 'start';
    case 'stretch':
      return 'stretch';
    case 'baseline':
      return 'baseline';
    default:
      return null;
  }
}

/** `CSSProperties.createTextStyle`. */
export function createTextStyle(style: CSSStyle | null | undefined): TextStyle | null {
  return textStyleFromCss(style);
}

/** Text widget props from a style (`textAlign`, `textOverflow`, `white-space`, line clamp). */
export function textOptionsFromStyle(style: CSSStyle | null | undefined): Record<string, any> {
  if (!style) return {};
  const out: Record<string, any> = {};
  if (style.textAlign) out.align = style.textAlign;
  if (style.textOverflow) out.overflow = style.textOverflow;
  if (style.whiteSpace === 'nowrap' || style.whiteSpace === 'pre') {
    out.softWrap = false;
    if (style.whiteSpace === 'nowrap') out.maxLines = 1;
  }
  if (style.lineClamp != null && style.lineClamp > 0) {
    out.maxLines = style.lineClamp;
    out.overflow = out.overflow ?? 'ellipsis';
  }
  return out;
}

/** Flutter `Container(width, height, padding, margin, alignment, decoration, child)`. */
export function container(opts: {
  child?: W | null;
  width?: number | null;
  height?: number | null;
  padding?: EdgeInsets | null;
  margin?: EdgeInsets | null;
  alignment?: Alignment | null;
  decoration?: Decoration | null;
  minWidth?: number | null;
  minHeight?: number | null;
}): W {
  let current: W | null = opts.child ?? null;
  const tightW = opts.width != null;
  const tightH = opts.height != null;
  if (!current && !(tightW && tightH)) {
    // Container with no child expands (LimitedBox(0,0) around an expanded box).
    current = w('limited', { maxWidth: 0, maxHeight: 0 }, w('constrained', { minWidth: Number.POSITIVE_INFINITY, minHeight: Number.POSITIVE_INFINITY }));
  }
  if (opts.alignment) current = align(opts.alignment, current);
  const borderPad = borderInsets(opts.decoration?.border);
  const p = opts.padding ?? { top: 0, right: 0, bottom: 0, left: 0 };
  const eff = { top: p.top + borderPad.top, right: p.right + borderPad.right, bottom: p.bottom + borderPad.bottom, left: p.left + borderPad.left };
  if (eff.top || eff.right || eff.bottom || eff.left) current = padding(eff, current);
  if (opts.decoration) current = decorated(opts.decoration, current);
  if (opts.width != null || opts.height != null || opts.minWidth != null || opts.minHeight != null) {
    current = w('constrained', { width: opts.width ?? null, height: opts.height ?? null, minWidth: opts.minWidth ?? 0, minHeight: opts.minHeight ?? 0 }, current);
  }
  if (opts.margin) current = padding(opts.margin, current);
  return current!;
}
