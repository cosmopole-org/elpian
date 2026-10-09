/**
 * RenderStack + Positioned parent data — Flutter's `Stack`.
 *
 * Non-positioned children are laid out with loose (or expanded) constraints
 * and the stack sizes to the largest; positioned children are placed by their
 * top/right/bottom/left/width/height against the stack's box. Children paint
 * in order, so z-order is the child order (lowering sorts by `z-index`).
 */
import type { Alignment } from '../../css/types.js';
import { RenderObject, biggest, constrain, loose, smallest, type Constraints } from '../object.js';
import type { ViewKind, ViewProps } from '../view.js';
import { alignOffset } from './basic.js';

/** props: { top, right, bottom, left, width, height } */
export class RenderPositioned extends RenderObject {
  get isPositioned(): boolean {
    const p = this.props;
    return p.top != null || p.right != null || p.bottom != null || p.left != null || p.width != null || p.height != null;
  }
  protected performLayout(c: Constraints): void {
    const child = this.child;
    if (child) {
      child.layout(c);
      child.offset = { x: 0, y: 0 };
      this.size = { ...child.size };
    } else {
      this.size = constrain(c, { width: this.props.width ?? 0, height: this.props.height ?? 0 });
    }
  }
}

/** props: { alignment, fit: 'loose'|'expand'|'passthrough', clip } */
export class RenderStack extends RenderObject {
  protected performLayout(c: Constraints): void {
    const alignment: Alignment = this.props.alignment ?? { x: -1, y: -1 };
    const fit = this.props.fit ?? 'loose';
    const nonPositioned: Constraints = fit === 'expand' ? { ...c, minWidth: biggest(c).width, maxWidth: biggest(c).width, minHeight: biggest(c).height, maxHeight: biggest(c).height } : fit === 'passthrough' ? c : loose(c);
    let hasNonPositioned = false;
    let width = c.minWidth;
    let height = c.minHeight;
    for (const child of this.children) {
      if (child instanceof RenderPositioned && child.isPositioned) continue;
      hasNonPositioned = true;
      child.layout(nonPositioned);
      width = Math.max(width, child.size.width);
      height = Math.max(height, child.size.height);
    }
    this.size = hasNonPositioned ? constrain(c, { width, height }) : biggest(c);
    if (!Number.isFinite(this.size.width) || !Number.isFinite(this.size.height)) {
      this.size = constrain(c, smallest(c));
    }
    for (const child of this.children) {
      if (child instanceof RenderPositioned && child.isPositioned) {
        this.layoutPositioned(child, alignment);
      } else {
        child.offset = alignOffset(alignment, this.size, child.size);
      }
    }
  }

  private layoutPositioned(child: RenderPositioned, alignment: Alignment): void {
    const p = child.props;
    const W = this.size.width;
    const H = this.size.height;
    let c: Constraints = { minWidth: 0, maxWidth: Number.POSITIVE_INFINITY, minHeight: 0, maxHeight: Number.POSITIVE_INFINITY };
    if (p.left != null && p.right != null) {
      const w = Math.max(0, W - p.right - p.left);
      c = { ...c, minWidth: w, maxWidth: w };
    } else if (p.width != null) {
      c = { ...c, minWidth: p.width, maxWidth: p.width };
    }
    if (p.top != null && p.bottom != null) {
      const h = Math.max(0, H - p.bottom - p.top);
      c = { ...c, minHeight: h, maxHeight: h };
    } else if (p.height != null) {
      c = { ...c, minHeight: p.height, maxHeight: p.height };
    }
    child.layout(c);
    let x: number;
    if (p.left != null) x = p.left;
    else if (p.right != null) x = W - p.right - child.size.width;
    else x = ((W - child.size.width) / 2) * (1 + alignment.x);
    let y: number;
    if (p.top != null) y = p.top;
    else if (p.bottom != null) y = H - p.bottom - child.size.height;
    else y = ((H - child.size.height) / 2) * (1 + alignment.y);
    child.offset = { x, y };
  }

  viewKind(): ViewKind | null {
    // A stack that clips needs its own view; otherwise it is layout-only.
    return this.props.clip ? 'view' : null;
  }

  viewProps(): Omit<ViewProps, 'frame'> {
    return { clip: !!this.props.clip };
  }

  protected computeMinIntrinsicWidth(h: number): number {
    let m = 0;
    for (const ch of this.children) if (!(ch instanceof RenderPositioned && ch.isPositioned)) m = Math.max(m, ch.minIntrinsicWidth(h));
    return m;
  }
  protected computeMaxIntrinsicWidth(h: number): number {
    let m = 0;
    for (const ch of this.children) if (!(ch instanceof RenderPositioned && ch.isPositioned)) m = Math.max(m, ch.maxIntrinsicWidth(h));
    return m;
  }
  protected computeMinIntrinsicHeight(w: number): number {
    let m = 0;
    for (const ch of this.children) if (!(ch instanceof RenderPositioned && ch.isPositioned)) m = Math.max(m, ch.minIntrinsicHeight(w));
    return m;
  }
  protected computeMaxIntrinsicHeight(w: number): number {
    let m = 0;
    for (const ch of this.children) if (!(ch instanceof RenderPositioned && ch.isPositioned)) m = Math.max(m, ch.maxIntrinsicHeight(w));
    return m;
  }
}
