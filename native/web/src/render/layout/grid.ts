/**
 * CSS grid layout.
 *
 * Flutter's HtmlDiv resolves `display: grid` into a column count — from
 * `repeat(auto-fill|auto-fit, minmax(Npx, …))`, `repeat(N, …)` or the number
 * of listed tracks — and lays the children out in equal-width cells that wrap
 * row by row. That behaviour is kept for those templates. Templates Flutter
 * cannot express (mixed `px`/`fr`/`%`/`auto` tracks, `minmax`, spans,
 * explicit placement, explicit row tracks) are sized with the CSS track
 * algorithm instead of being flattened to equal columns.
 */
import { splitTopLevel } from '../../css/parser.js';
import { INF, RenderObject, constrain, type Constraints } from '../object.js';

/** Parent data: props { colStart, colSpan, rowStart, rowSpan, justifySelf, alignSelf } */
export class RenderGridItem extends RenderObject {
  protected performLayout(c: Constraints): void {
    const child = this.child;
    if (child) {
      child.layout(c);
      child.offset = { x: 0, y: 0 };
      this.size = { ...child.size };
    } else this.size = constrain(c, { width: 0, height: 0 });
  }
}

type Track =
  | { kind: 'px'; value: number }
  | { kind: 'pct'; value: number }
  | { kind: 'fr'; value: number }
  | { kind: 'auto' }
  | { kind: 'minmax'; min: Track; max: Track };

interface ParsedTemplate {
  tracks: Track[];
  /** `repeat(auto-fill|auto-fit, …)` */
  autoRepeat: { tracks: Track[]; fit: boolean } | null;
  /** Insertion index of the auto-repeat block within [tracks]. */
  autoIndex: number;
}

function parseTrack(token: string): Track {
  const t = token.trim().toLowerCase();
  if (t.startsWith('minmax(')) {
    const inner = t.substring(7, t.length - 1);
    const [a, b] = splitTopLevel(inner, ',').map((s) => s.trim());
    return { kind: 'minmax', min: parseTrack(a ?? 'auto'), max: parseTrack(b ?? 'auto') };
  }
  if (t.startsWith('fit-content(')) return { kind: 'minmax', min: { kind: 'auto' }, max: parseTrack(t.substring(12, t.length - 1)) };
  if (t.endsWith('fr')) return { kind: 'fr', value: parseFloat(t) || 1 };
  if (t.endsWith('%')) return { kind: 'pct', value: parseFloat(t) || 0 };
  if (t === 'auto' || t === 'min-content' || t === 'max-content') return { kind: 'auto' };
  const n = parseFloat(t);
  if (Number.isFinite(n)) {
    if (t.endsWith('rem') || t.endsWith('em')) return { kind: 'px', value: n * 16 };
    return { kind: 'px', value: n };
  }
  return { kind: 'auto' };
}

export function parseTemplate(template: string | null | undefined): ParsedTemplate | null {
  if (!template) return null;
  const value = template.trim();
  if (value === '' || value === 'none') return null;
  const tracks: Track[] = [];
  let autoRepeat: ParsedTemplate['autoRepeat'] = null;
  let autoIndex = 0;
  for (const token of splitTopLevel(value, ' ')) {
    const t = token.trim();
    if (t.startsWith('[')) continue; // line names
    if (t.toLowerCase().startsWith('repeat(')) {
      const inner = t.substring(7, t.length - 1);
      const comma = inner.indexOf(',');
      const count = inner.substring(0, comma).trim().toLowerCase();
      const body = splitTopLevel(inner.substring(comma + 1).trim(), ' ').map(parseTrack);
      if (count === 'auto-fill' || count === 'auto-fit') {
        autoRepeat = { tracks: body, fit: count === 'auto-fit' };
        autoIndex = tracks.length;
      } else {
        const n = Math.max(1, Number.parseInt(count, 10) || 1);
        for (let i = 0; i < n; i++) tracks.push(...body);
      }
    } else {
      tracks.push(parseTrack(t));
    }
  }
  if (tracks.length === 0 && !autoRepeat) return null;
  return { tracks, autoRepeat, autoIndex };
}

function minOf(t: Track, basis: number): number {
  switch (t.kind) {
    case 'px':
      return t.value;
    case 'pct':
      return Number.isFinite(basis) ? (t.value / 100) * basis : 0;
    case 'minmax':
      return minOf(t.min, basis);
    default:
      return 0;
  }
}

function parsePlacement(raw: string | null | undefined): { start: number | null; span: number } {
  if (!raw) return { start: null, span: 1 };
  const parts = String(raw).split('/').map((p) => p.trim().toLowerCase());
  const spanMatch = /span\s+(\d+)/;
  let start: number | null = null;
  let span = 1;
  const first = parts[0] ?? '';
  const m1 = spanMatch.exec(first);
  if (m1) span = Math.max(1, Number.parseInt(m1[1], 10));
  else if (/^-?\d+$/.test(first)) start = Number.parseInt(first, 10);
  if (parts.length > 1) {
    const second = parts[1];
    const m2 = spanMatch.exec(second);
    if (m2) span = Math.max(1, Number.parseInt(m2[1], 10));
    else if (/^-?\d+$/.test(second) && start != null) span = Math.max(1, Number.parseInt(second, 10) - start);
  }
  return { start: start != null && start > 0 ? start - 1 : null, span };
}

/**
 * props: { columns, rows, autoRows, columnGap, rowGap, alignItems, justifyItems }
 */
export class RenderGrid extends RenderObject {
  private wrapFallback(c: Constraints, colGap: number, rowGap: number): void {
    // Flutter: an unbounded grid becomes a plain Wrap.
    let x = 0;
    let y = 0;
    let rowH = 0;
    let maxW = 0;
    const limit = c.maxWidth;
    for (const child of this.children) {
      child.layout({ minWidth: 0, maxWidth: limit, minHeight: 0, maxHeight: INF });
      if (x > 0 && x + child.size.width > limit) {
        x = 0;
        y += rowH + rowGap;
        rowH = 0;
      }
      child.offset = { x, y };
      x += child.size.width + colGap;
      rowH = Math.max(rowH, child.size.height);
      maxW = Math.max(maxW, x - colGap);
    }
    this.size = constrain(c, { width: maxW, height: this.children.length ? y + rowH : 0 });
  }

  protected performLayout(c: Constraints): void {
    const colGap: number = this.props.columnGap ?? 0;
    const rowGap: number = this.props.rowGap ?? 0;
    const template = parseTemplate(this.props.columns);
    const children = this.children;
    const W = c.maxWidth;
    if (!template || !Number.isFinite(W)) {
      this.wrapFallback(c, colGap, rowGap);
      return;
    }

    // ---- column tracks ----
    let tracks: Track[];
    if (template.autoRepeat) {
      const fixed = template.tracks.reduce((s, t) => s + minOf(t, W), 0) + template.tracks.length * colGap;
      const unit = template.autoRepeat.tracks;
      const unitMin = unit.reduce((s, t) => s + Math.max(minOf(t, W), t.kind === 'fr' || t.kind === 'auto' ? 1 : 0), 0);
      const unitGaps = unit.length * colGap;
      let reps = Math.max(1, Math.floor((W - fixed + colGap) / (unitMin + unitGaps)));
      // Flutter caps the count at the number of items (so few items stretch).
      if (template.tracks.length === 0 && unit.length === 1) reps = Math.min(reps, Math.max(1, children.length));
      tracks = [...template.tracks.slice(0, template.autoIndex)];
      for (let i = 0; i < reps; i++) {
        // An auto-fill `minmax(min, X)` behaves like `minmax(min, 1fr)` once the count is fixed.
        tracks.push(...unit.map((t): Track => (t.kind === 'minmax' ? { kind: 'minmax', min: t.min, max: { kind: 'fr', value: 1 } } : t)));
      }
      tracks.push(...template.tracks.slice(template.autoIndex));
    } else {
      tracks = template.tracks;
    }
    const colCount = Math.max(1, tracks.length);

    // ---- placement ----
    interface Item {
      ro: RenderObject;
      col: number;
      row: number;
      colSpan: number;
      rowSpan: number;
    }
    const items: Item[] = [];
    const occupied = new Set<string>();
    const isFree = (row: number, col: number, colSpan: number, rowSpan: number) => {
      if (col + colSpan > colCount) return false;
      for (let r = row; r < row + rowSpan; r++) for (let k = col; k < col + colSpan; k++) if (occupied.has(r + ':' + k)) return false;
      return true;
    };
    const occupy = (row: number, col: number, colSpan: number, rowSpan: number) => {
      for (let r = row; r < row + rowSpan; r++) for (let k = col; k < col + colSpan; k++) occupied.add(r + ':' + k);
    };
    let cursorRow = 0;
    let cursorCol = 0;
    for (const child of children) {
      const pd = child instanceof RenderGridItem ? child.props : {};
      const colP = parsePlacement(pd.column);
      const rowP = parsePlacement(pd.row);
      const colSpan = Math.min(colCount, colP.span);
      const rowSpan = rowP.span;
      let row = rowP.start ?? -1;
      let col = colP.start ?? -1;
      if (col >= colCount) col = colCount - colSpan;
      if (row >= 0 && col >= 0) {
        // fully explicit
      } else if (row >= 0) {
        col = 0;
        while (!isFree(row, col, colSpan, rowSpan)) {
          col++;
          if (col + colSpan > colCount) {
            col = 0;
            row++;
          }
        }
      } else if (col >= 0) {
        row = 0;
        while (!isFree(row, col, colSpan, rowSpan)) row++;
      } else {
        row = cursorRow;
        col = cursorCol;
        while (!isFree(row, col, colSpan, rowSpan)) {
          col++;
          if (col + colSpan > colCount) {
            col = 0;
            row++;
          }
        }
        cursorRow = row;
        cursorCol = col + colSpan;
        if (cursorCol >= colCount) {
          cursorCol = 0;
          cursorRow++;
        }
      }
      occupy(row, col, colSpan, rowSpan);
      items.push({ ro: child, col, row, colSpan, rowSpan });
    }

    // ---- column sizing ----
    const widths = new Array<number>(colCount).fill(0);
    let fixedTotal = 0;
    let frTotal = 0;
    for (let i = 0; i < colCount; i++) {
      const t = tracks[i] ?? { kind: 'fr', value: 1 };
      const base = t.kind === 'minmax' ? t.max : t;
      if (base.kind === 'fr') frTotal += base.value;
      else if (base.kind === 'auto') {
        let m = minOf(t, W);
        for (const it of items) if (it.col === i && it.colSpan === 1) m = Math.max(m, it.ro.maxIntrinsicWidth(INF));
        widths[i] = m;
        fixedTotal += m;
      } else {
        widths[i] = Math.max(minOf(t, W), minOf(base, W));
        fixedTotal += widths[i];
      }
    }
    const gaps = (colCount - 1) * colGap;
    let free = W - fixedTotal - gaps;
    if (frTotal > 0) {
      // Distribute free space to fr tracks, respecting minmax minimums.
      const frTracks = tracks.map((t, i) => ({ i, t: t.kind === 'minmax' ? t : null, base: t.kind === 'minmax' ? t.max : t })).filter((x) => x.base.kind === 'fr');
      let remaining = Math.max(0, free);
      let pool = frTracks.slice();
      for (let iter = 0; iter < 4 && pool.length; iter++) {
        const totalFr = pool.reduce((s, x) => s + (x.base as { value: number }).value, 0);
        const perFr = remaining / totalFr;
        const stuck = pool.filter((x) => x.t && minOf(x.t.min, W) > perFr * (x.base as { value: number }).value);
        if (stuck.length === 0) {
          for (const x of pool) widths[x.i] = perFr * (x.base as { value: number }).value;
          pool = [];
          break;
        }
        for (const x of stuck) {
          widths[x.i] = minOf(x.t!.min, W);
          remaining -= widths[x.i];
        }
        pool = pool.filter((x) => !stuck.includes(x));
      }
      free = 0;
    } else if (free < 0) {
      // Over-constrained auto columns shrink proportionally (never below 0).
      const autoIdx = tracks.map((t, i) => (t.kind === 'auto' ? i : -1)).filter((i) => i >= 0);
      const autoSum = autoIdx.reduce((s, i) => s + widths[i], 0);
      if (autoSum > 0) for (const i of autoIdx) widths[i] = Math.max(0, widths[i] + (free * widths[i]) / autoSum);
    }

    const colX = new Array<number>(colCount);
    let acc = 0;
    for (let i = 0; i < colCount; i++) {
      colX[i] = acc;
      acc += widths[i] + colGap;
    }
    const spanWidth = (col: number, span: number) => {
      let s = 0;
      for (let k = col; k < Math.min(colCount, col + span); k++) s += widths[k];
      return s + (Math.min(span, colCount - col) - 1) * colGap;
    };

    // ---- rows ----
    const rowCount = items.reduce((m, it) => Math.max(m, it.row + it.rowSpan), 0);
    const rowTemplate = parseTemplate(this.props.rows);
    const autoRowTrack = this.props.autoRows ? parseTrack(String(this.props.autoRows)) : null;
    const heights = new Array<number>(rowCount).fill(0);
    const rowFixed = new Array<boolean>(rowCount).fill(false);
    for (let r = 0; r < rowCount; r++) {
      const t = rowTemplate?.tracks[r] ?? autoRowTrack;
      if (t && (t.kind === 'px' || (t.kind === 'minmax' && t.min.kind === 'px'))) {
        heights[r] = minOf(t, c.maxHeight);
        rowFixed[r] = t.kind === 'px';
      }
    }
    const stretch = (this.props.alignItems ?? 'start') === 'stretch';
    for (const it of items) {
      const width = spanWidth(it.col, it.colSpan);
      it.ro.layout({ minWidth: width, maxWidth: width, minHeight: 0, maxHeight: INF });
      if (it.rowSpan === 1 && !rowFixed[it.row]) heights[it.row] = Math.max(heights[it.row], it.ro.size.height);
    }
    // Spanning items grow their last row if needed.
    for (const it of items) {
      if (it.rowSpan === 1) continue;
      let h = 0;
      for (let r = it.row; r < it.row + it.rowSpan; r++) h += heights[r];
      h += (it.rowSpan - 1) * rowGap;
      const last = it.row + it.rowSpan - 1;
      if (it.ro.size.height > h && !rowFixed[last]) heights[last] += it.ro.size.height - h;
    }
    const rowY = new Array<number>(rowCount);
    let y = 0;
    for (let r = 0; r < rowCount; r++) {
      rowY[r] = y;
      y += heights[r] + rowGap;
    }
    const totalH = rowCount ? y - rowGap : 0;

    for (const it of items) {
      let cellH = 0;
      for (let r = it.row; r < it.row + it.rowSpan; r++) cellH += heights[r];
      cellH += (it.rowSpan - 1) * rowGap;
      if (stretch || rowFixed[it.row]) {
        const width = spanWidth(it.col, it.colSpan);
        it.ro.layout({ minWidth: width, maxWidth: width, minHeight: stretch ? cellH : 0, maxHeight: stretch ? cellH : Math.max(cellH, 0) });
      }
      let dy = 0;
      const align = (it.ro.props.alignSelf as string | undefined) ?? this.props.alignItems;
      if (align === 'center') dy = (cellH - it.ro.size.height) / 2;
      else if (align === 'end' || align === 'flex-end') dy = cellH - it.ro.size.height;
      it.ro.offset = { x: colX[it.col], y: rowY[it.row] + dy };
    }
    this.size = constrain(c, { width: W, height: totalH });
  }

  protected computeMaxIntrinsicWidth(h: number): number {
    let m = 0;
    for (const ch of this.children) m = Math.max(m, ch.maxIntrinsicWidth(h));
    const template = parseTemplate(this.props.columns);
    const cols = template?.tracks.length || 1;
    return m * cols + (cols - 1) * (this.props.columnGap ?? 0);
  }
  protected computeMinIntrinsicWidth(h: number): number {
    let m = 0;
    for (const ch of this.children) m = Math.max(m, ch.minIntrinsicWidth(h));
    return m;
  }
}
