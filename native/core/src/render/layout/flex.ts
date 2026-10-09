/**
 * RenderFlex (Row / Column) and Flexible / Expanded parent data — a port of
 * Flutter's flex algorithm:
 *
 *   1. lay out inflexible children with an unbounded main axis;
 *   2. divide the remaining space between flexible children by flex factor
 *      (tight fit for Expanded / CSS `flex:n`, loose for Flexible);
 *   3. size the box (`mainAxisSize` max/min), then distribute leftover space
 *      with `mainAxisAlignment` and place children on the cross axis.
 *
 * One deliberate extension: when inflexible children overflow a bounded main
 * axis, a box declared with `shrink: true` (HTML/CSS flex containers) shrinks
 * them proportionally to their `flex-shrink` — what a browser does — instead
 * of letting content spill past the edge the way Flutter's debug overflow
 * stripe shows. Flutter-DSL Row/Column keep Flutter's no-shrink semantics.
 */
import { INF, RenderObject, clampN, constrain, type Constraints } from '../object.js';

export type MainAxisAlignment = 'start' | 'end' | 'center' | 'spaceBetween' | 'spaceAround' | 'spaceEvenly';
export type CrossAxisAlignment = 'start' | 'end' | 'center' | 'stretch' | 'baseline';

/** Parent data for a flex child: props { flex, fit: 'tight'|'loose', shrink, alignSelf, basis } */
export class RenderFlexible extends RenderObject {
  protected performLayout(c: Constraints): void {
    const child = this.child;
    if (child) {
      child.layout(c);
      child.offset = { x: 0, y: 0 };
      this.size = { ...child.size };
    } else {
      this.size = constrain(c, { width: 0, height: 0 });
    }
  }
}

interface FlexInfo {
  flex: number;
  fit: 'tight' | 'loose';
  shrink: number;
  alignSelf: CrossAxisAlignment | null;
  /** CSS flex-basis in px (when it differs from the content size). */
  basis: number | null;
}

function flexInfo(child: RenderObject): FlexInfo {
  if (child instanceof RenderFlexible) {
    const p = child.props;
    return {
      flex: typeof p.flex === 'number' && p.flex > 0 ? p.flex : 0,
      fit: p.fit === 'loose' ? 'loose' : 'tight',
      shrink: typeof p.shrink === 'number' ? p.shrink : 1,
      alignSelf: p.alignSelf ?? null,
      basis: typeof p.basis === 'number' ? p.basis : null,
    };
  }
  return { flex: 0, fit: 'tight', shrink: 1, alignSelf: null, basis: null };
}

export function mainAxisAlignmentFromCss(value: string | null | undefined): MainAxisAlignment {
  switch ((value ?? '').toLowerCase()) {
    case 'center':
      return 'center';
    case 'flex-end':
    case 'end':
    case 'right':
      return 'end';
    case 'space-between':
      return 'spaceBetween';
    case 'space-around':
      return 'spaceAround';
    case 'space-evenly':
      return 'spaceEvenly';
    default:
      return 'start';
  }
}

export function crossAxisAlignmentFromCss(value: string | null | undefined): CrossAxisAlignment {
  switch ((value ?? '').toLowerCase()) {
    case 'center':
      return 'center';
    case 'flex-end':
    case 'end':
      return 'end';
    case 'stretch':
      return 'stretch';
    case 'baseline':
    case 'first baseline':
      return 'baseline';
    default:
      return 'start';
  }
}

/**
 * props: {
 *   direction: 'row' | 'column', reverse?: boolean,
 *   mainAxisAlignment, crossAxisAlignment, mainAxisSize: 'max' | 'min',
 *   verticalDirection?: 'down' | 'up', gap?: number, shrink?: boolean
 * }
 */
export class RenderFlex extends RenderObject {
  private overflow = 0;

  private get horizontal(): boolean {
    return this.props.direction !== 'column';
  }

  private main(s: { width: number; height: number }): number {
    return this.horizontal ? s.width : s.height;
  }
  private cross(s: { width: number; height: number }): number {
    return this.horizontal ? s.height : s.width;
  }

  /** Constraints for a child with the given main extent bounds. */
  private childConstraints(minMain: number, maxMain: number, c: Constraints, align: CrossAxisAlignment): Constraints {
    const stretch = align === 'stretch';
    if (this.horizontal) {
      const maxCross = c.maxHeight;
      return {
        minWidth: minMain,
        maxWidth: maxMain,
        minHeight: stretch && Number.isFinite(maxCross) ? maxCross : 0,
        maxHeight: maxCross,
      };
    }
    const maxCross = c.maxWidth;
    return {
      minWidth: stretch && Number.isFinite(maxCross) ? maxCross : 0,
      maxWidth: maxCross,
      minHeight: minMain,
      maxHeight: maxMain,
    };
  }

  protected performLayout(c: Constraints): void {
    const horizontal = this.horizontal;
    const gap: number = this.props.gap ?? 0;
    const crossAlign: CrossAxisAlignment = this.props.crossAxisAlignment ?? 'start';
    const maxMain = horizontal ? c.maxWidth : c.maxHeight;
    const canFlex = Number.isFinite(maxMain);
    const children = this.children;
    const infos = children.map(flexInfo);
    const gaps = Math.max(0, children.length - 1) * gap;

    let totalFlex = 0;
    let allocated = 0;
    const isFlex = infos.map((info) => canFlex && info.flex > 0);
    for (let i = 0; i < children.length; i++) {
      const child = children[i];
      const info = infos[i];
      if (isFlex[i]) {
        totalFlex += info.flex;
        continue;
      }
      const align = info.alignSelf ?? crossAlign;
      if (info.basis != null) {
        child.layout(this.childConstraints(info.basis, info.basis, c, align));
      } else {
        child.layout(this.childConstraints(0, INF, c, align));
      }
      allocated += this.main(child.size);
    }

    // CSS shrink: inflexible content overflowing a bounded main axis.
    if (this.props.shrink && canFlex && allocated + gaps > maxMain + 0.01) {
      this.shrinkChildren(c, infos, isFlex, maxMain - gaps);
      allocated = 0;
      for (let i = 0; i < children.length; i++) if (!isFlex[i]) allocated += this.main(children[i].size);
    }

    const freeSpace = Math.max(0, (canFlex ? maxMain : 0) - allocated - gaps);
    if (totalFlex > 0) {
      const perFlex = freeSpace / totalFlex;
      let lastFlexIndex = -1;
      for (let i = 0; i < children.length; i++) if (isFlex[i]) lastFlexIndex = i;
      let used = 0;
      for (let i = 0; i < children.length; i++) {
        if (!isFlex[i]) continue;
        const info = infos[i];
        const maxChild = i === lastFlexIndex ? Math.max(0, freeSpace - used) : perFlex * info.flex;
        const minChild = info.fit === 'tight' ? maxChild : 0;
        const align = info.alignSelf ?? crossAlign;
        children[i].layout(this.childConstraints(minChild, maxChild, c, align));
        const extent = this.main(children[i].size);
        used += extent;
        allocated += extent;
      }
    }

    const mainSizeMax = (this.props.mainAxisSize ?? 'max') === 'max';
    const allocatedWithGaps = allocated + gaps;
    const idealMain = mainSizeMax && canFlex ? maxMain : allocatedWithGaps;

    let crossSize = 0;
    let maxBaseline = 0;
    let maxBelowBaseline = 0;
    const baselines: (number | null)[] = [];
    for (let i = 0; i < children.length; i++) {
      const child = children[i];
      const align = infos[i].alignSelf ?? crossAlign;
      if (align === 'baseline' && horizontal) {
        const b = child.baseline() ?? child.size.height;
        baselines.push(b);
        maxBaseline = Math.max(maxBaseline, b);
        maxBelowBaseline = Math.max(maxBelowBaseline, child.size.height - b);
      } else {
        baselines.push(null);
        crossSize = Math.max(crossSize, this.cross(child.size));
      }
    }
    crossSize = Math.max(crossSize, maxBaseline + maxBelowBaseline);
    if (crossAlign === 'stretch') {
      const maxCross = horizontal ? c.maxHeight : c.maxWidth;
      if (Number.isFinite(maxCross)) crossSize = Math.max(crossSize, maxCross);
    }

    const size = constrain(
      c,
      horizontal ? { width: idealMain, height: crossSize } : { width: crossSize, height: idealMain },
    );
    this.size = size;
    const actualMain = this.main(size);
    const actualCross = this.cross(size);
    this.overflow = Math.max(0, allocatedWithGaps - actualMain);

    const remaining = Math.max(0, actualMain - allocatedWithGaps);
    const n = children.length;
    let leading = 0;
    let between = 0;
    switch (this.props.mainAxisAlignment ?? 'start') {
      case 'end':
        leading = remaining;
        break;
      case 'center':
        leading = remaining / 2;
        break;
      case 'spaceBetween':
        between = n > 1 ? remaining / (n - 1) : 0;
        break;
      case 'spaceAround':
        between = n > 0 ? remaining / n : 0;
        leading = between / 2;
        break;
      case 'spaceEvenly':
        between = n > 0 ? remaining / (n + 1) : 0;
        leading = between;
        break;
    }

    // Reverse order for row-reverse / column-reverse / verticalDirection up.
    const flip = this.props.reverse === true || (!horizontal && this.props.verticalDirection === 'up');
    let pos = leading;
    for (let k = 0; k < n; k++) {
      const i = flip ? n - 1 - k : k;
      const child = children[i];
      const align = infos[i].alignSelf ?? crossAlign;
      const childCross = this.cross(child.size);
      let crossPos = 0;
      switch (align) {
        case 'end':
          crossPos = actualCross - childCross;
          break;
        case 'center':
          crossPos = (actualCross - childCross) / 2;
          break;
        case 'baseline':
          crossPos = horizontal ? maxBaseline - (baselines[i] ?? 0) : 0;
          break;
        default:
          crossPos = 0;
      }
      if (!horizontal && this.props.verticalDirection === 'up' && align !== 'baseline') {
        // nothing extra: the order is flipped above
      }
      child.offset = horizontal ? { x: pos, y: crossPos } : { x: crossPos, y: pos };
      pos += this.main(child.size) + gap + between;
    }
  }

  /** CSS flex-shrink: reduce inflexible children so they fit [available]. */
  private shrinkChildren(c: Constraints, infos: FlexInfo[], isFlex: boolean[], available: number): void {
    const crossAlign: CrossAxisAlignment = this.props.crossAxisAlignment ?? 'start';
    const children = this.children;
    const base = children.map((ch) => this.main(ch.size));
    const minContent = children.map((ch, i) =>
      isFlex[i] ? 0 : this.horizontal ? ch.minIntrinsicWidth(INF) : ch.minIntrinsicHeight(c.maxWidth),
    );
    const frozen = children.map((_, i) => isFlex[i] || infos[i].shrink <= 0);
    const target = base.slice();
    // Iteratively shrink, freezing items that hit their min-content size.
    for (let iter = 0; iter < 8; iter++) {
      let used = 0;
      let weighted = 0;
      for (let i = 0; i < children.length; i++) {
        if (isFlex[i]) continue;
        used += target[i];
        if (!frozen[i]) weighted += infos[i].shrink * base[i];
      }
      const over = used - available;
      if (over <= 0.01 || weighted <= 0) break;
      let clamped = false;
      for (let i = 0; i < children.length; i++) {
        if (frozen[i]) continue;
        const share = (over * infos[i].shrink * base[i]) / weighted;
        const next = target[i] - share;
        if (next < minContent[i]) {
          target[i] = minContent[i];
          frozen[i] = true;
          clamped = true;
        } else {
          target[i] = next;
        }
      }
      if (!clamped) break;
    }
    for (let i = 0; i < children.length; i++) {
      if (isFlex[i] || Math.abs(target[i] - base[i]) < 0.01) continue;
      const align = infos[i].alignSelf ?? crossAlign;
      const extent = Math.max(0, target[i]);
      children[i].layout(this.childConstraints(extent, extent, c, align));
    }
  }

  get overflowExtent(): number {
    return this.overflow;
  }

  baseline(): number | null {
    // Flutter: a Row's baseline is that of its first child that has one.
    for (const child of this.children) {
      const b = child.baseline();
      if (b != null) return b + child.offset.y;
    }
    return null;
  }

  protected computeMinIntrinsicWidth(height: number): number {
    return this.intrinsicMain('min', true, height);
  }
  protected computeMaxIntrinsicWidth(height: number): number {
    return this.intrinsicMain('max', true, height);
  }
  protected computeMinIntrinsicHeight(width: number): number {
    return this.intrinsicMain('min', false, width);
  }
  protected computeMaxIntrinsicHeight(width: number): number {
    return this.intrinsicMain('max', false, width);
  }

  private intrinsicMain(kind: 'min' | 'max', widthAxis: boolean, extent: number): number {
    const gap: number = this.props.gap ?? 0;
    const gaps = Math.max(0, this.children.length - 1) * gap;
    const get = (ch: RenderObject) =>
      widthAxis
        ? kind === 'min'
          ? ch.minIntrinsicWidth(extent)
          : ch.maxIntrinsicWidth(extent)
        : kind === 'min'
          ? ch.minIntrinsicHeight(extent)
          : ch.maxIntrinsicHeight(extent);
    if (this.horizontal === widthAxis) {
      // Along the main axis: sum (flex children scaled to the largest per-flex).
      let inflexible = 0;
      let maxPerFlex = 0;
      let totalFlex = 0;
      for (const ch of this.children) {
        const info = flexInfo(ch);
        const v = get(ch);
        if (info.flex > 0) {
          totalFlex += info.flex;
          maxPerFlex = Math.max(maxPerFlex, v / info.flex);
        } else inflexible += v;
      }
      return inflexible + maxPerFlex * totalFlex + gaps;
    }
    // Across: the largest child.
    let m = 0;
    for (const ch of this.children) m = Math.max(m, get(ch));
    return m;
  }
}

export { clampN };
