/**
 * RenderScroll — `SingleChildScrollView` / `ListView` / overflow:auto.
 *
 * The child is laid out unbounded along the scroll axis; the box itself takes
 * the incoming constraints. The platform owns the actual scrolling (native
 * scroll physics, momentum, scrollbars); it reports offsets back so hit
 * testing and drag targets account for them, and the core restores the
 * offset after a re-render.
 */
import { INF, RenderObject, constrain, type Constraints } from '../object.js';
import type { ViewEvent, ViewKind, ViewProps } from '../view.js';

/** props: { axis: 'vertical'|'horizontal'|'both', enabled, scrollbar, stretchCross } */
export class RenderScroll extends RenderObject {
  scrollOffset = { x: 0, y: 0 };
  private contentWidth = 0;
  private contentHeight = 0;

  private get axis(): 'vertical' | 'horizontal' | 'both' {
    return this.props.axis ?? 'vertical';
  }

  protected performLayout(c: Constraints): void {
    const axis = this.axis;
    const child = this.child;
    let inner: Constraints;
    if (axis === 'vertical') {
      inner = {
        minWidth: this.props.stretchCross ? c.maxWidth : c.minWidth,
        maxWidth: c.maxWidth,
        // A document root is at least as tall as the viewport (Flutter's
        // ConstrainedBox(minHeight: maxHeight) inside the scroll view).
        minHeight: this.props.fillViewport && Number.isFinite(c.maxHeight) ? c.maxHeight : 0,
        maxHeight: INF,
      };
      if (!Number.isFinite(inner.minWidth)) inner.minWidth = 0;
    } else if (axis === 'horizontal') {
      inner = { minWidth: 0, maxWidth: INF, minHeight: this.props.stretchCross ? c.maxHeight : c.minHeight, maxHeight: c.maxHeight };
      if (!Number.isFinite(inner.minHeight)) inner.minHeight = 0;
    } else {
      inner = { minWidth: 0, maxWidth: INF, minHeight: 0, maxHeight: INF };
    }
    if (child) {
      child.layout(inner);
      child.offset = { x: 0, y: 0 };
      this.contentWidth = child.size.width;
      this.contentHeight = child.size.height;
      this.size = constrain(c, child.size);
    } else {
      this.contentWidth = 0;
      this.contentHeight = 0;
      this.size = constrain(c, { width: 0, height: 0 });
    }
    // Keep the restored offset within the new content.
    this.scrollOffset = {
      x: Math.max(0, Math.min(this.scrollOffset.x, this.contentWidth - this.size.width)),
      y: Math.max(0, Math.min(this.scrollOffset.y, this.contentHeight - this.size.height)),
    };
  }

  viewKind(): ViewKind {
    return 'scroll';
  }

  viewProps(): Omit<ViewProps, 'frame'> {
    return {
      scrollAxis: this.axis,
      contentSize: [Math.max(this.contentWidth, this.size.width), Math.max(this.contentHeight, this.size.height)],
      scrollEnabled: this.props.enabled !== false,
      showScrollbar: this.props.scrollbar !== false,
      clip: true,
      gestures: this.props.reportScroll ? ['scroll'] : null,
    };
  }

  handleViewEvent(event: ViewEvent): void {
    if (event.type === 'scroll') {
      this.scrollOffset = { x: event.scrollX ?? this.scrollOffset.x, y: event.scrollY ?? this.scrollOffset.y };
      this.props.onScroll?.(event);
    }
  }

  protected computeMinIntrinsicWidth(h: number): number {
    return this.axis === 'vertical' ? this.child?.minIntrinsicWidth(h) ?? 0 : 0;
  }
  protected computeMaxIntrinsicWidth(h: number): number {
    return this.child?.maxIntrinsicWidth(h) ?? 0;
  }
  protected computeMinIntrinsicHeight(w: number): number {
    return this.axis === 'horizontal' ? this.child?.minIntrinsicHeight(w) ?? 0 : 0;
  }
  protected computeMaxIntrinsicHeight(w: number): number {
    return this.child?.maxIntrinsicHeight(w) ?? 0;
  }
}
