/**
 * Single-child layout objects — ports of Flutter's RenderPadding,
 * RenderConstrainedBox, RenderPositionedBox (Align/Center), RenderAspectRatio,
 * RenderFractionallySizedOverflowBox, RenderLimitedBox,
 * RenderConstrainedOverflowBox, RenderFittedBox, RenderBaseline,
 * RenderRotatedBox, RenderIntrinsicWidth/Height, RenderOffstage and
 * RenderIndexedStack.
 */
import type { Alignment, EdgeInsets, Percent } from '../../css/types.js';
import { identity, multiply, rotationZ, scaling, translation } from '../../css/matrix.js';
import {
  INF,
  RenderObject,
  RenderProxy,
  biggest,
  clampN,
  constrain,
  deflate,
  enforce,
  loose,
  smallest,
  tight,
  type Constraints,
  type Size,
} from '../object.js';
import type { ViewKind, ViewProps } from '../view.js';

export function alignOffset(alignment: Alignment, outer: Size, inner: Size): { x: number; y: number } {
  return {
    x: ((outer.width - inner.width) / 2) * (1 + alignment.x),
    y: ((outer.height - inner.height) / 2) * (1 + alignment.y),
  };
}

// ----------------------------------------------------------------------------
// Padding
// ----------------------------------------------------------------------------

export class RenderPadding extends RenderObject {
  /** Padding with percentage sides resolved against the incoming max width (CSS). */
  resolvedPadding(c: Constraints | null): EdgeInsets {
    const p: EdgeInsets = this.props.padding ?? { top: 0, right: 0, bottom: 0, left: 0 };
    const pct: Partial<Record<keyof EdgeInsets, Percent>> | null = this.props.percent ?? null;
    if (!pct) return p;
    const basis = c && Number.isFinite(c.maxWidth) ? c.maxWidth : 0;
    const side = (k: keyof EdgeInsets) => (pct[k] ? (pct[k]!.pct / 100) * basis : p[k]);
    return { top: side('top'), right: side('right'), bottom: side('bottom'), left: side('left') };
  }

  protected performLayout(c: Constraints): void {
    const p = this.resolvedPadding(c);
    const h = Math.max(0, p.left + p.right);
    const v = Math.max(0, p.top + p.bottom);
    const child = this.child;
    if (!child) {
      this.size = constrain(c, { width: h, height: v });
      return;
    }
    child.layout(deflate(c, h, v));
    child.offset = { x: p.left, y: p.top };
    this.size = constrain(c, { width: child.size.width + h, height: child.size.height + v });
  }

  protected computeMinIntrinsicWidth(height: number): number {
    const p = this.resolvedPadding(null);
    const h = p.left + p.right;
    const v = p.top + p.bottom;
    return (this.child?.minIntrinsicWidth(Math.max(0, height - v)) ?? 0) + h;
  }
  protected computeMaxIntrinsicWidth(height: number): number {
    const p = this.resolvedPadding(null);
    return (this.child?.maxIntrinsicWidth(Math.max(0, height - p.top - p.bottom)) ?? 0) + p.left + p.right;
  }
  protected computeMinIntrinsicHeight(width: number): number {
    const p = this.resolvedPadding(null);
    return (this.child?.minIntrinsicHeight(Math.max(0, width - p.left - p.right)) ?? 0) + p.top + p.bottom;
  }
  protected computeMaxIntrinsicHeight(width: number): number {
    const p = this.resolvedPadding(null);
    return (this.child?.maxIntrinsicHeight(Math.max(0, width - p.left - p.right)) ?? 0) + p.top + p.bottom;
  }
}

// ----------------------------------------------------------------------------
// ConstrainedBox / SizedBox
// ----------------------------------------------------------------------------

/**
 * props: { minWidth, maxWidth, minHeight, maxHeight, width, height }
 * `width`/`height` produce tight constraints on that axis (SizedBox); the
 * min/max values are additional constraints (ConstrainedBox).
 */
export class RenderConstrainedBox extends RenderObject {
  additional(): Constraints {
    const p = this.props;
    let c: Constraints = {
      minWidth: p.minWidth ?? 0,
      maxWidth: p.maxWidth ?? INF,
      minHeight: p.minHeight ?? 0,
      maxHeight: p.maxHeight ?? INF,
    };
    if (p.width != null) c = { ...c, minWidth: p.width, maxWidth: p.width };
    if (p.height != null) c = { ...c, minHeight: p.height, maxHeight: p.height };
    if (c.maxWidth < c.minWidth) c.maxWidth = c.minWidth;
    if (c.maxHeight < c.minHeight) c.maxHeight = c.minHeight;
    return c;
  }

  protected performLayout(c: Constraints): void {
    const inner = enforce(this.additional(), c);
    const child = this.child;
    if (child) {
      child.layout(inner);
      child.offset = { x: 0, y: 0 };
      this.size = { ...child.size };
    } else {
      this.size = constrain(inner, { width: 0, height: 0 });
    }
  }

  private clampW(v: number): number {
    const a = this.additional();
    return clampN(v, a.minWidth, a.maxWidth);
  }
  private clampH(v: number): number {
    const a = this.additional();
    return clampN(v, a.minHeight, a.maxHeight);
  }
  protected computeMinIntrinsicWidth(height: number): number {
    const a = this.additional();
    if (a.minWidth >= a.maxWidth && Number.isFinite(a.minWidth)) return a.minWidth;
    return this.clampW(this.child?.minIntrinsicWidth(height) ?? 0);
  }
  protected computeMaxIntrinsicWidth(height: number): number {
    const a = this.additional();
    if (a.minWidth >= a.maxWidth && Number.isFinite(a.minWidth)) return a.minWidth;
    return this.clampW(this.child?.maxIntrinsicWidth(height) ?? 0);
  }
  protected computeMinIntrinsicHeight(width: number): number {
    const a = this.additional();
    if (a.minHeight >= a.maxHeight && Number.isFinite(a.minHeight)) return a.minHeight;
    return this.clampH(this.child?.minIntrinsicHeight(width) ?? 0);
  }
  protected computeMaxIntrinsicHeight(width: number): number {
    const a = this.additional();
    if (a.minHeight >= a.maxHeight && Number.isFinite(a.minHeight)) return a.minHeight;
    return this.clampH(this.child?.maxIntrinsicHeight(width) ?? 0);
  }
}

// ----------------------------------------------------------------------------
// Align / Center
// ----------------------------------------------------------------------------

/** props: { alignment, widthFactor, heightFactor } */
export class RenderAlign extends RenderObject {
  protected performLayout(c: Constraints): void {
    const alignment: Alignment = this.props.alignment ?? { x: 0, y: 0 };
    const wf: number | null = this.props.widthFactor ?? null;
    const hf: number | null = this.props.heightFactor ?? null;
    const shrinkW = wf != null || !Number.isFinite(c.maxWidth);
    const shrinkH = hf != null || !Number.isFinite(c.maxHeight);
    const child = this.child;
    if (child) {
      child.layout(loose(c));
      this.size = constrain(c, {
        width: shrinkW ? child.size.width * (wf ?? 1) : INF,
        height: shrinkH ? child.size.height * (hf ?? 1) : INF,
      });
      child.offset = alignOffset(alignment, this.size, child.size);
    } else {
      this.size = constrain(c, { width: shrinkW ? 0 : INF, height: shrinkH ? 0 : INF });
    }
  }

  protected computeMinIntrinsicWidth(h: number): number {
    return (this.child?.minIntrinsicWidth(h) ?? 0) * (this.props.widthFactor ?? 1);
  }
  protected computeMaxIntrinsicWidth(h: number): number {
    return (this.child?.maxIntrinsicWidth(h) ?? 0) * (this.props.widthFactor ?? 1);
  }
  protected computeMinIntrinsicHeight(w: number): number {
    return (this.child?.minIntrinsicHeight(w) ?? 0) * (this.props.heightFactor ?? 1);
  }
  protected computeMaxIntrinsicHeight(w: number): number {
    return (this.child?.maxIntrinsicHeight(w) ?? 0) * (this.props.heightFactor ?? 1);
  }
}

// ----------------------------------------------------------------------------
// AspectRatio
// ----------------------------------------------------------------------------

export class RenderAspectRatio extends RenderObject {
  private apply(c: Constraints): Size {
    const ar: number = this.props.aspectRatio > 0 ? this.props.aspectRatio : 1;
    if (c.minWidth >= c.maxWidth && c.minHeight >= c.maxHeight) return smallest(c);
    let width = c.maxWidth;
    let height: number;
    if (Number.isFinite(width)) height = width / ar;
    else {
      height = c.maxHeight;
      width = height * ar;
    }
    if (width > c.maxWidth) {
      width = c.maxWidth;
      height = width / ar;
    }
    if (height > c.maxHeight) {
      height = c.maxHeight;
      width = height * ar;
    }
    if (width < c.minWidth) {
      width = c.minWidth;
      height = width / ar;
    }
    if (height < c.minHeight) {
      height = c.minHeight;
      width = height * ar;
    }
    if (!Number.isFinite(width) || !Number.isFinite(height)) {
      // Unbounded on both axes: fall back to the child's own size.
      return { width: 0, height: 0 };
    }
    return constrain(c, { width, height });
  }

  protected performLayout(c: Constraints): void {
    this.size = this.apply(c);
    const child = this.child;
    if (child) {
      child.layout(tight(this.size.width, this.size.height));
      child.offset = { x: 0, y: 0 };
    }
  }

  protected computeMinIntrinsicWidth(height: number): number {
    return Number.isFinite(height) ? height * (this.props.aspectRatio || 1) : this.child?.minIntrinsicWidth(height) ?? 0;
  }
  protected computeMaxIntrinsicWidth(height: number): number {
    return Number.isFinite(height) ? height * (this.props.aspectRatio || 1) : this.child?.maxIntrinsicWidth(height) ?? 0;
  }
  protected computeMinIntrinsicHeight(width: number): number {
    return Number.isFinite(width) ? width / (this.props.aspectRatio || 1) : this.child?.minIntrinsicHeight(width) ?? 0;
  }
  protected computeMaxIntrinsicHeight(width: number): number {
    return Number.isFinite(width) ? width / (this.props.aspectRatio || 1) : this.child?.maxIntrinsicHeight(width) ?? 0;
  }
}

// ----------------------------------------------------------------------------
// FractionallySizedBox
// ----------------------------------------------------------------------------

/**
 * props: { widthFactor, heightFactor, alignment, fallbackWidth, fallbackHeight }
 * A factor applies only when the incoming axis is bounded; otherwise the
 * fallback pixel size is used (the CSS-percentage behaviour of applyStyle).
 */
export class RenderFractional extends RenderObject {
  protected performLayout(c: Constraints): void {
    const wf: number | null = this.props.widthFactor ?? null;
    const hf: number | null = this.props.heightFactor ?? null;
    let inner: Constraints = { ...c };
    if (wf != null) {
      if (Number.isFinite(c.maxWidth)) {
        const w = c.maxWidth * wf;
        inner = { ...inner, minWidth: w, maxWidth: w };
      } else if (this.props.fallbackWidth != null) {
        inner = { ...inner, minWidth: this.props.fallbackWidth, maxWidth: this.props.fallbackWidth };
      }
    }
    if (hf != null) {
      if (Number.isFinite(c.maxHeight)) {
        const h = c.maxHeight * hf;
        inner = { ...inner, minHeight: h, maxHeight: h };
      } else if (this.props.fallbackHeight != null) {
        inner = { ...inner, minHeight: this.props.fallbackHeight, maxHeight: this.props.fallbackHeight };
      }
    }
    const child = this.child;
    if (child) {
      child.layout(inner);
      this.size = constrain(c, child.size);
      child.offset = alignOffset(this.props.alignment ?? { x: 0, y: 0 }, this.size, child.size);
    } else {
      this.size = constrain(c, { width: inner.minWidth, height: inner.minHeight });
    }
  }
}

// ----------------------------------------------------------------------------
// LimitedBox / OverflowBox
// ----------------------------------------------------------------------------

export class RenderLimitedBox extends RenderObject {
  protected performLayout(c: Constraints): void {
    const limited: Constraints = {
      minWidth: c.minWidth,
      maxWidth: Number.isFinite(c.maxWidth) ? c.maxWidth : constrainLimit(c.minWidth, this.props.maxWidth),
      minHeight: c.minHeight,
      maxHeight: Number.isFinite(c.maxHeight) ? c.maxHeight : constrainLimit(c.minHeight, this.props.maxHeight),
    };
    const child = this.child;
    if (child) {
      child.layout(limited);
      child.offset = { x: 0, y: 0 };
      this.size = constrain(c, child.size);
    } else {
      this.size = constrain(limited, { width: 0, height: 0 });
    }
  }
}

function constrainLimit(min: number, limit: number | null | undefined): number {
  return limit == null ? INF : Math.max(min, limit);
}

/** props: { alignment, minWidth, maxWidth, minHeight, maxHeight } (null = parent's) */
export class RenderOverflowBox extends RenderObject {
  protected performLayout(c: Constraints): void {
    const p = this.props;
    const inner: Constraints = {
      minWidth: p.minWidth ?? c.minWidth,
      maxWidth: p.maxWidth ?? c.maxWidth,
      minHeight: p.minHeight ?? c.minHeight,
      maxHeight: p.maxHeight ?? c.maxHeight,
    };
    this.size = biggest(c);
    const child = this.child;
    if (child) {
      child.layout(inner);
      child.offset = alignOffset(p.alignment ?? { x: 0, y: 0 }, this.size, child.size);
    }
  }
}

// ----------------------------------------------------------------------------
// FittedBox — scales its child (paints a transform)
// ----------------------------------------------------------------------------

export class RenderFittedBox extends RenderObject {
  private scaleX = 1;
  private scaleY = 1;
  private childOffset = { x: 0, y: 0 };

  protected performLayout(c: Constraints): void {
    const child = this.child;
    if (!child) {
      this.size = smallest(c);
      return;
    }
    child.layout({ minWidth: 0, maxWidth: INF, minHeight: 0, maxHeight: INF });
    const cs = child.size;
    const fit: string = this.props.fit ?? 'contain';
    // constrainSizeAndAttemptToPreserveAspectRatio
    this.size = preserveAspect(c, cs);
    const { sx, sy } = fitScale(fit, cs, this.size);
    this.scaleX = sx;
    this.scaleY = sy;
    const scaled = { width: cs.width * sx, height: cs.height * sy };
    this.childOffset = alignOffset(this.props.alignment ?? { x: 0, y: 0 }, this.size, scaled);
    child.offset = { x: 0, y: 0 };
  }

  viewKind(): ViewKind {
    return 'view';
  }

  viewProps(): Omit<ViewProps, 'frame'> {
    return {
      clip: this.props.clip !== false,
      transform: null,
    };
  }

  childOriginInView(): { x: number; y: number } {
    return { x: 0, y: 0 };
  }

  /** The child is wrapped in a transform view by the compositor hook below. */
  get contentTransform() {
    return multiply(translation(this.childOffset.x, this.childOffset.y), scaling(this.scaleX, this.scaleY, 1));
  }
}

export function fitScale(fit: string, child: Size, box: Size): { sx: number; sy: number } {
  if (child.width <= 0 || child.height <= 0) return { sx: 1, sy: 1 };
  const rw = box.width / child.width;
  const rh = box.height / child.height;
  switch (fit) {
    case 'fill':
      return { sx: rw, sy: rh };
    case 'cover': {
      const s = Math.max(rw, rh);
      return { sx: s, sy: s };
    }
    case 'fitWidth':
      return { sx: rw, sy: rw };
    case 'fitHeight':
      return { sx: rh, sy: rh };
    case 'none':
      return { sx: 1, sy: 1 };
    case 'scaleDown': {
      const s = Math.min(1, Math.min(rw, rh));
      return { sx: s, sy: s };
    }
    case 'contain':
    default: {
      const s = Math.min(rw, rh);
      return { sx: s, sy: s };
    }
  }
}

export function preserveAspect(c: Constraints, s: Size): Size {
  if (c.minWidth >= c.maxWidth && c.minHeight >= c.maxHeight) return smallest(c);
  let width = s.width;
  let height = s.height;
  if (width <= 0 || height <= 0) return constrain(c, s);
  const ar = width / height;
  if (width > c.maxWidth) {
    width = c.maxWidth;
    height = width / ar;
  }
  if (height > c.maxHeight) {
    height = c.maxHeight;
    width = height * ar;
  }
  if (width < c.minWidth) {
    width = c.minWidth;
    height = width / ar;
  }
  if (height < c.minHeight) {
    height = c.minHeight;
    width = height * ar;
  }
  return constrain(c, { width, height });
}

/**
 * The scaled content of a FittedBox: a transform view the FittedBox's child
 * is placed in. Kept as a separate object so the child keeps its natural
 * size and the platform only needs a matrix.
 */
export class RenderFittedContent extends RenderObject {
  protected performLayout(c: Constraints): void {
    const child = this.child;
    if (child) {
      child.layout(c);
      child.offset = { x: 0, y: 0 };
      this.size = { ...child.size };
    } else this.size = smallest(c);
  }
  viewKind(): ViewKind {
    return 'view';
  }
  viewProps(): Omit<ViewProps, 'frame'> {
    const fitted = this.parent as RenderFittedBox | null;
    return { transform: fitted instanceof RenderFittedBox ? fitted.contentTransform : identity(), transformOrigin: [0, 0] };
  }
}

// ----------------------------------------------------------------------------
// Baseline
// ----------------------------------------------------------------------------

export class RenderBaseline extends RenderObject {
  protected performLayout(c: Constraints): void {
    const child = this.child;
    if (!child) {
      this.size = smallest(c);
      return;
    }
    child.layout(loose(c));
    const target: number = this.props.baseline ?? 0;
    const childBaseline = child.baseline() ?? child.size.height;
    const top = target - childBaseline;
    child.offset = { x: 0, y: top };
    this.size = constrain(c, { width: child.size.width, height: top + child.size.height });
  }
}

// ----------------------------------------------------------------------------
// RotatedBox — rotates by quarter turns, swapping the axes
// ----------------------------------------------------------------------------

export class RenderRotatedBox extends RenderObject {
  private get turns(): number {
    return ((((this.props.quarterTurns ?? 0) as number) % 4) + 4) % 4;
  }

  protected performLayout(c: Constraints): void {
    const odd = this.turns % 2 === 1;
    const child = this.child;
    if (!child) {
      this.size = smallest(c);
      return;
    }
    child.layout(odd ? { minWidth: c.minHeight, maxWidth: c.maxHeight, minHeight: c.minWidth, maxHeight: c.maxWidth } : c);
    this.size = odd ? { width: child.size.height, height: child.size.width } : { ...child.size };
    child.offset = { x: 0, y: 0 };
  }

  viewKind(): ViewKind {
    return 'view';
  }

  viewProps(): Omit<ViewProps, 'frame'> {
    const child = this.child;
    if (!child) return {};
    const t = this.turns;
    // Rotate the child's box about its centre, then centre it in ours.
    const cw = child.size.width;
    const ch = child.size.height;
    const m = multiply(
      translation(this.size.width / 2, this.size.height / 2),
      multiply(rotationZ((t * Math.PI) / 2), translation(-cw / 2, -ch / 2)),
    );
    return { transform: m, transformOrigin: [0, 0] };
  }

  protected computeMinIntrinsicWidth(h: number): number {
    return this.turns % 2 ? this.child?.minIntrinsicHeight(h) ?? 0 : this.child?.minIntrinsicWidth(h) ?? 0;
  }
  protected computeMaxIntrinsicWidth(h: number): number {
    return this.turns % 2 ? this.child?.maxIntrinsicHeight(h) ?? 0 : this.child?.maxIntrinsicWidth(h) ?? 0;
  }
}

// ----------------------------------------------------------------------------
// IntrinsicWidth / IntrinsicHeight
// ----------------------------------------------------------------------------

export class RenderIntrinsicWidth extends RenderObject {
  protected performLayout(c: Constraints): void {
    const child = this.child;
    if (!child) {
      this.size = smallest(c);
      return;
    }
    let inner = c;
    // `onlyWhenUnbounded` (Flutter's `_flexSafe`): pass bounded constraints through.
    const applies = !this.props.onlyWhenUnbounded || !Number.isFinite(c.maxWidth);
    if (applies && !(c.minWidth >= c.maxWidth)) {
      const w = clampN(child.maxIntrinsicWidth(c.maxHeight), c.minWidth, c.maxWidth);
      inner = { ...c, minWidth: w, maxWidth: w };
    }
    child.layout(inner);
    child.offset = { x: 0, y: 0 };
    this.size = { ...child.size };
  }
}

export class RenderIntrinsicHeight extends RenderObject {
  protected performLayout(c: Constraints): void {
    const child = this.child;
    if (!child) {
      this.size = smallest(c);
      return;
    }
    let inner = c;
    if (!(c.minHeight >= c.maxHeight)) {
      const h = clampN(child.maxIntrinsicHeight(c.maxWidth), c.minHeight, c.maxHeight);
      inner = { ...c, minHeight: h, maxHeight: h };
    }
    child.layout(inner);
    child.offset = { x: 0, y: 0 };
    this.size = { ...child.size };
  }
}

// ----------------------------------------------------------------------------
// Offstage / IndexedStack
// ----------------------------------------------------------------------------

/** Lays the child out but takes no space and paints nothing (`offstage: true`). */
export class RenderOffstage extends RenderProxy {
  protected performLayout(c: Constraints): void {
    if (this.props.offstage === false) {
      super.performLayout(c);
      return;
    }
    this.child?.layout(c);
    this.size = smallest(c);
  }
  paintsChild(): boolean {
    return this.props.offstage === false;
  }
}

/** props: { index, alignment } — every child keeps its state; only one paints. */
export class RenderIndexedStack extends RenderObject {
  protected performLayout(c: Constraints): void {
    const alignment: Alignment = this.props.alignment ?? { x: -1, y: -1 };
    let w = 0;
    let h = 0;
    const inner = loose(c);
    for (const child of this.children) {
      child.layout(inner);
      w = Math.max(w, child.size.width);
      h = Math.max(h, child.size.height);
    }
    this.size = this.children.length ? constrain(c, { width: w, height: h }) : biggest(c);
    for (const child of this.children) child.offset = alignOffset(alignment, this.size, child.size);
  }

  paintsChild(child: RenderObject): boolean {
    const index = Math.max(0, Math.min(this.children.length - 1, Math.trunc(this.props.index ?? 0)));
    return this.children[index] === child;
  }
}

// ----------------------------------------------------------------------------
// SafeArea — pads by the platform's safe-area insets
// ----------------------------------------------------------------------------

/** props: { top, right, bottom, left } (booleans; default all true) */
export class RenderSafeArea extends RenderPadding {
  resolvedPadding(): EdgeInsets {
    const owner = this.owner;
    const inset = owner ? owner.platform.viewport(owner.surface).safeArea : { top: 0, right: 0, bottom: 0, left: 0 };
    const p = this.props;
    return {
      top: p.top !== false ? inset.top : 0,
      right: p.right !== false ? inset.right : 0,
      bottom: p.bottom !== false ? inset.bottom : 0,
      left: p.left !== false ? inset.left : 0,
    };
  }
}

// ----------------------------------------------------------------------------
// FillAxis — `SizedBox(width: double.infinity)` only when the axis is bounded
// ----------------------------------------------------------------------------

/** props: { width?: boolean, height?: boolean } */
export class RenderFillAxis extends RenderObject {
  protected performLayout(c: Constraints): void {
    const fillW = this.props.width && Number.isFinite(c.maxWidth);
    const fillH = this.props.height && Number.isFinite(c.maxHeight);
    const inner: Constraints = {
      minWidth: fillW ? c.maxWidth : c.minWidth,
      maxWidth: c.maxWidth,
      minHeight: fillH ? c.maxHeight : c.minHeight,
      maxHeight: c.maxHeight,
    };
    const child = this.child;
    if (child) {
      child.layout(inner);
      child.offset = { x: 0, y: 0 };
      this.size = { ...child.size };
    } else {
      this.size = constrain(inner, { width: 0, height: 0 });
    }
  }
}
