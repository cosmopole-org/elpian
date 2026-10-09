/**
 * The render-object tree: a compact port of Flutter's box protocol.
 *
 * Lowering turns every Elpian node into a tree of *widget descriptors*
 * ([W]) — the same widget composition the Flutter engine builds
 * (Padding → ConstrainedBox → DecoratedBox → …). The reconciler keeps one
 * [RenderObject] per descriptor across renders (so animation state, scroll
 * offsets and text input survive a re-render), layout runs Flutter's
 * constraints-down / sizes-up algorithm, and the compositor turns the objects
 * that paint into native views.
 */
import type { ViewKind, ViewProps } from './view.js';
import type { RenderOwner } from './owner.js';

export interface Constraints {
  minWidth: number;
  maxWidth: number;
  minHeight: number;
  maxHeight: number;
}

export interface Size {
  width: number;
  height: number;
}

export const INF = Number.POSITIVE_INFINITY;

export function tight(width: number, height: number): Constraints {
  return { minWidth: width, maxWidth: width, minHeight: height, maxHeight: height };
}

export function loose(c: Constraints): Constraints {
  return { minWidth: 0, maxWidth: c.maxWidth, minHeight: 0, maxHeight: c.maxHeight };
}

export function tightFor(c: Constraints, width: number | null | undefined, height: number | null | undefined): Constraints {
  return {
    minWidth: width != null ? clampN(width, c.minWidth, c.maxWidth) : c.minWidth,
    maxWidth: width != null ? clampN(width, c.minWidth, c.maxWidth) : c.maxWidth,
    minHeight: height != null ? clampN(height, c.minHeight, c.maxHeight) : c.minHeight,
    maxHeight: height != null ? clampN(height, c.minHeight, c.maxHeight) : c.maxHeight,
  };
}

/** Flutter `BoxConstraints.enforce`: keep [inner] within [outer]. */
export function enforce(inner: Constraints, outer: Constraints): Constraints {
  return {
    minWidth: clampN(inner.minWidth, outer.minWidth, outer.maxWidth),
    maxWidth: clampN(inner.maxWidth, outer.minWidth, outer.maxWidth),
    minHeight: clampN(inner.minHeight, outer.minHeight, outer.maxHeight),
    maxHeight: clampN(inner.maxHeight, outer.minHeight, outer.maxHeight),
  };
}

export function deflate(c: Constraints, h: number, v: number): Constraints {
  const minW = Math.max(0, c.minWidth - h);
  const minH = Math.max(0, c.minHeight - v);
  return {
    minWidth: minW,
    maxWidth: Math.max(minW, c.maxWidth - h),
    minHeight: minH,
    maxHeight: Math.max(minH, c.maxHeight - v),
  };
}

export function constrain(c: Constraints, s: Size): Size {
  return { width: clampN(s.width, c.minWidth, c.maxWidth), height: clampN(s.height, c.minHeight, c.maxHeight) };
}

export function biggest(c: Constraints): Size {
  return {
    width: Number.isFinite(c.maxWidth) ? c.maxWidth : c.minWidth,
    height: Number.isFinite(c.maxHeight) ? c.maxHeight : c.minHeight,
  };
}

export function smallest(c: Constraints): Size {
  return { width: c.minWidth, height: c.minHeight };
}

export function isTight(c: Constraints): boolean {
  return c.minWidth >= c.maxWidth && c.minHeight >= c.maxHeight;
}

export function clampN(v: number, lo: number, hi: number): number {
  if (v < lo) return lo;
  if (v > hi) return hi;
  return v;
}

function constraintsEqual(a: Constraints | null, b: Constraints): boolean {
  return !!a && a.minWidth === b.minWidth && a.maxWidth === b.maxWidth && a.minHeight === b.minHeight && a.maxHeight === b.maxHeight;
}

/** A widget descriptor: what lowering produces and the reconciler consumes. */
export interface W {
  /** Render-object type (`padding`, `flex`, `text`, …). */
  t: string;
  /** Configuration. */
  p: Record<string, any>;
  c?: W[];
  /** Identity across renders (Flutter `Key`). */
  k?: string | null;
}

export function w(t: string, p: Record<string, any> = {}, c?: W[] | W | null, k?: string | null): W {
  const children = c == null ? undefined : Array.isArray(c) ? c : [c];
  return { t, p, c: children, k: k ?? null };
}

export abstract class RenderObject {
  type = '';
  key: string | null = null;
  props: Record<string, any> = {};
  parent: RenderObject | null = null;
  children: RenderObject[] = [];
  owner: RenderOwner | null = null;

  size: Size = { width: 0, height: 0 };
  /** Offset of this object's top-left inside its parent's coordinate space. */
  offset = { x: 0, y: 0 };

  needsLayout = true;
  private lastConstraints: Constraints | null = null;
  /** Cache of intrinsic queries, cleared on layout invalidation. */
  private intrinsicCache = new Map<string, number>();

  /** The native view this object owns, when it paints. */
  viewId: number | null = null;

  // ---------------------------------------------------------------------------
  // Lifecycle (driven by the reconciler)
  // ---------------------------------------------------------------------------

  /** First configuration. */
  init(props: Record<string, any>): void {
    this.props = props;
  }

  /** A new configuration for an existing object. Default: relayout. */
  update(props: Record<string, any>): void {
    const old = this.props;
    this.props = props;
    this.didUpdate(old);
    this.markNeedsLayout();
  }

  /** Hook for subclasses to react to a configuration change (start animations …). */
  protected didUpdate(_old: Record<string, any>): void {}

  attach(owner: RenderOwner): void {
    this.owner = owner;
    this.onAttach();
  }

  detach(): void {
    this.onDetach();
    for (const c of this.children) c.detach();
    this.owner = null;
  }

  protected onAttach(): void {}
  protected onDetach(): void {}

  markNeedsLayout(): void {
    let node: RenderObject | null = this;
    while (node && !node.needsLayout) {
      node.needsLayout = true;
      node.intrinsicCache.clear();
      node = node.parent;
    }
    if (node) node.intrinsicCache.clear();
    this.owner?.requestVisualUpdate();
  }

  /** Paint-only change: re-emit this view's props without relayout. */
  markNeedsPaint(): void {
    this.owner?.markPaintDirty(this);
  }

  // ---------------------------------------------------------------------------
  // Layout
  // ---------------------------------------------------------------------------

  layout(c: Constraints): void {
    if (!this.needsLayout && constraintsEqual(this.lastConstraints, c)) return;
    this.lastConstraints = c;
    this.performLayout(c);
    if (!Number.isFinite(this.size.width)) this.size.width = Number.isFinite(c.minWidth) ? c.minWidth : 0;
    if (!Number.isFinite(this.size.height)) this.size.height = Number.isFinite(c.minHeight) ? c.minHeight : 0;
    this.needsLayout = false;
    this.intrinsicCache.clear();
  }

  get constraints(): Constraints | null {
    return this.lastConstraints;
  }

  protected abstract performLayout(c: Constraints): void;

  get child(): RenderObject | null {
    return this.children[0] ?? null;
  }

  // Intrinsics (Flutter getMin/MaxIntrinsicWidth/Height).
  minIntrinsicWidth(height: number): number {
    return this.cachedIntrinsic('minW', height, () => this.computeMinIntrinsicWidth(height));
  }
  maxIntrinsicWidth(height: number): number {
    return this.cachedIntrinsic('maxW', height, () => this.computeMaxIntrinsicWidth(height));
  }
  minIntrinsicHeight(width: number): number {
    return this.cachedIntrinsic('minH', width, () => this.computeMinIntrinsicHeight(width));
  }
  maxIntrinsicHeight(width: number): number {
    return this.cachedIntrinsic('maxH', width, () => this.computeMaxIntrinsicHeight(width));
  }

  private cachedIntrinsic(kind: string, extent: number, compute: () => number): number {
    const key = kind + ':' + extent;
    const hit = this.intrinsicCache.get(key);
    if (hit !== undefined) return hit;
    const v = compute();
    this.intrinsicCache.set(key, v);
    return v;
  }

  protected computeMinIntrinsicWidth(height: number): number {
    return this.child?.minIntrinsicWidth(height) ?? 0;
  }
  protected computeMaxIntrinsicWidth(height: number): number {
    return this.child?.maxIntrinsicWidth(height) ?? 0;
  }
  protected computeMinIntrinsicHeight(width: number): number {
    return this.child?.minIntrinsicHeight(width) ?? 0;
  }
  protected computeMaxIntrinsicHeight(width: number): number {
    return this.child?.maxIntrinsicHeight(width) ?? 0;
  }

  /** Distance from the top to the first alphabetic baseline, if any. */
  baseline(): number | null {
    const c = this.child;
    if (!c) return null;
    const b = c.baseline();
    return b == null ? null : b + c.offset.y;
  }

  // ---------------------------------------------------------------------------
  // Painting
  // ---------------------------------------------------------------------------

  /** The native view kind when this object owns a view, otherwise null. */
  viewKind(): ViewKind | null {
    return null;
  }

  /** This object's view props (frame excluded — the compositor fills it). */
  viewProps(): Omit<ViewProps, 'frame'> {
    return {};
  }

  /**
   * Offset added to children inside this object's own view (a scroll view's
   * children live in content space, so it reports none).
   */
  childOriginInView(): { x: number; y: number } {
    return { x: 0, y: 0 };
  }

  /** Whether [child] is painted (IndexedStack / Offstage hide some children). */
  paintsChild(_child: RenderObject): boolean {
    return true;
  }

  /** Called by the compositor when the platform reports an event on this view. */
  handleViewEvent(_event: import('./view.js').ViewEvent): void {}

  /** Visit descendants. */
  visit(fn: (ro: RenderObject) => void): void {
    fn(this);
    for (const c of this.children) c.visit(fn);
  }

  toString(): string {
    return `${this.type}${this.key ? `#${this.key}` : ''}(${this.size.width.toFixed(1)}x${this.size.height.toFixed(1)})`;
  }
}

/** A single-child object that sizes to its child (or the smallest size without one). */
export class RenderProxy extends RenderObject {
  protected performLayout(c: Constraints): void {
    const child = this.child;
    if (child) {
      child.layout(c);
      child.offset = { x: 0, y: 0 };
      this.size = { ...child.size };
    } else {
      this.size = smallest(c);
    }
  }
}
