/**
 * RenderWrap — Flutter's `Wrap`: children flow along the main axis and wrap
 * into runs; `spacing` separates children in a run, `runSpacing` separates
 * runs; `alignment` places children within a run, `runAlignment` places runs
 * within the box, `crossAxisAlignment` aligns children within their run.
 */
import { INF, RenderObject, constrain, type Constraints } from '../object.js';

export type WrapAlignment = 'start' | 'end' | 'center' | 'spaceBetween' | 'spaceAround' | 'spaceEvenly';

export function wrapAlignmentFromCss(value: string | null | undefined): WrapAlignment {
  switch ((value ?? '').toLowerCase()) {
    case 'center':
      return 'center';
    case 'flex-end':
    case 'end':
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

function distribute(alignment: WrapAlignment, free: number, count: number): { leading: number; between: number } {
  switch (alignment) {
    case 'end':
      return { leading: free, between: 0 };
    case 'center':
      return { leading: free / 2, between: 0 };
    case 'spaceBetween':
      return { leading: 0, between: count > 1 ? free / (count - 1) : 0 };
    case 'spaceAround': {
      const b = count > 0 ? free / count : 0;
      return { leading: b / 2, between: b };
    }
    case 'spaceEvenly': {
      const b = count > 0 ? free / (count + 1) : 0;
      return { leading: b, between: b };
    }
    default:
      return { leading: 0, between: 0 };
  }
}

/**
 * props: { direction: 'horizontal'|'vertical', spacing, runSpacing, alignment,
 *          runAlignment, crossAxisAlignment: 'start'|'end'|'center',
 *          verticalDirection: 'down'|'up', reverse }
 */
export class RenderWrap extends RenderObject {
  protected performLayout(c: Constraints): void {
    const horizontal = this.props.direction !== 'vertical';
    const spacing: number = this.props.spacing ?? 0;
    const runSpacing: number = this.props.runSpacing ?? 0;
    const mainLimit = horizontal ? c.maxWidth : c.maxHeight;
    const childC: Constraints = horizontal
      ? { minWidth: 0, maxWidth: c.maxWidth, minHeight: 0, maxHeight: INF }
      : { minWidth: 0, maxWidth: INF, minHeight: 0, maxHeight: c.maxHeight };
    const main = (s: { width: number; height: number }) => (horizontal ? s.width : s.height);
    const cross = (s: { width: number; height: number }) => (horizontal ? s.height : s.width);

    interface Run {
      children: RenderObject[];
      main: number;
      cross: number;
    }
    const runs: Run[] = [];
    let run: Run = { children: [], main: 0, cross: 0 };
    for (const child of this.children) {
      child.layout(childC);
      const cm = main(child.size);
      const extra = run.children.length ? spacing : 0;
      if (run.children.length && run.main + extra + cm > mainLimit + 0.01) {
        runs.push(run);
        run = { children: [], main: 0, cross: 0 };
      }
      run.main += (run.children.length ? spacing : 0) + cm;
      run.cross = Math.max(run.cross, cross(child.size));
      run.children.push(child);
    }
    if (run.children.length) runs.push(run);

    let contentMain = 0;
    let contentCross = 0;
    for (const r of runs) {
      contentMain = Math.max(contentMain, r.main);
      contentCross += r.cross;
    }
    contentCross += Math.max(0, runs.length - 1) * runSpacing;

    this.size = constrain(c, horizontal ? { width: contentMain, height: contentCross } : { width: contentCross, height: contentMain });
    const boxMain = main(this.size);
    const boxCross = cross(this.size);

    const runDist = distribute(this.props.runAlignment ?? 'start', Math.max(0, boxCross - contentCross), runs.length);
    const flipCross = this.props.verticalDirection === 'up';
    let crossPos = runDist.leading;
    const runOrder = flipCross ? [...runs].reverse() : runs;
    for (const r of runOrder) {
      const dist = distribute(this.props.alignment ?? 'start', Math.max(0, boxMain - r.main), r.children.length);
      let mainPos = dist.leading;
      const children = this.props.reverse ? [...r.children].reverse() : r.children;
      for (const child of children) {
        let childCross = 0;
        switch (this.props.crossAxisAlignment ?? 'start') {
          case 'end':
            childCross = r.cross - cross(child.size);
            break;
          case 'center':
            childCross = (r.cross - cross(child.size)) / 2;
            break;
        }
        child.offset = horizontal ? { x: mainPos, y: crossPos + childCross } : { x: crossPos + childCross, y: mainPos };
        mainPos += main(child.size) + spacing + dist.between;
      }
      crossPos += r.cross + runSpacing + runDist.between;
    }
  }

  protected computeMinIntrinsicWidth(height: number): number {
    if (this.props.direction === 'vertical') return this.sum('w', height);
    let m = 0;
    for (const ch of this.children) m = Math.max(m, ch.minIntrinsicWidth(INF));
    return m;
  }
  protected computeMaxIntrinsicWidth(height: number): number {
    if (this.props.direction === 'vertical') {
      let m = 0;
      for (const ch of this.children) m = Math.max(m, ch.maxIntrinsicWidth(INF));
      return m;
    }
    return this.sum('w', height);
  }
  protected computeMinIntrinsicHeight(width: number): number {
    // Lay out at the given width to know the run structure.
    if (!Number.isFinite(width)) return this.computeMaxIntrinsicHeight(width);
    const saved = this.size;
    this.layout({ minWidth: 0, maxWidth: width, minHeight: 0, maxHeight: INF });
    const h = this.size.height;
    this.size = saved;
    this.needsLayout = true;
    return h;
  }
  protected computeMaxIntrinsicHeight(width: number): number {
    return this.computeMinIntrinsicHeight(Number.isFinite(width) ? width : this.computeMaxIntrinsicWidth(INF));
  }

  private sum(axis: 'w', extent: number): number {
    const spacing: number = this.props.spacing ?? 0;
    let total = 0;
    for (const ch of this.children) total += axis === 'w' ? ch.maxIntrinsicWidth(extent) : 0;
    return total + Math.max(0, this.children.length - 1) * spacing;
  }
}
