/**
 * HTML table layout (`table` / `thead` / `tbody` / `tfoot` / `tr` / `td` / `th`
 * / `caption`), the CSS "auto" table algorithm:
 *
 *   * every cell reports its min-content and max-content width;
 *   * column widths start at the max-content widths when they fit, otherwise
 *     the space above the min-content widths is shared in proportion;
 *   * `colspan` cells spread their excess over the columns they span;
 *   * `rowspan` cells occupy the following rows, row heights grow to fit.
 *
 * The Flutter engine renders an empty table here; this is the real thing.
 */
import { INF, RenderObject, constrain, type Constraints } from '../object.js';
import type { ViewKind, ViewProps } from '../view.js';

/** A row: props { } — children are RenderTableCell. */
export class RenderTableRow extends RenderObject {
  protected performLayout(c: Constraints): void {
    // Rows are positioned by the table; standalone they stack their cells.
    let x = 0;
    let h = 0;
    for (const cell of this.children) {
      cell.layout({ minWidth: 0, maxWidth: INF, minHeight: 0, maxHeight: c.maxHeight });
      cell.offset = { x, y: 0 };
      x += cell.size.width;
      h = Math.max(h, cell.size.height);
    }
    this.size = constrain(c, { width: x, height: h });
  }
  viewKind(): ViewKind | null {
    return this.props.decorated ? 'view' : null;
  }
  viewProps(): Omit<ViewProps, 'frame'> {
    return { background: this.props.background ?? null };
  }
}

/** A cell: props { colSpan, rowSpan, verticalAlign: 'top'|'middle'|'bottom' } */
export class RenderTableCell extends RenderObject {
  protected performLayout(c: Constraints): void {
    const child = this.child;
    if (child) {
      child.layout({ minWidth: c.minWidth, maxWidth: c.maxWidth, minHeight: 0, maxHeight: c.maxHeight });
      this.size = constrain(c, child.size);
      const free = this.size.height - child.size.height;
      const va = this.props.verticalAlign ?? 'middle';
      child.offset = { x: 0, y: va === 'top' ? 0 : va === 'bottom' ? free : free / 2 };
    } else {
      this.size = constrain(c, { width: 0, height: 0 });
    }
  }
}

interface Cell {
  ro: RenderTableCell;
  row: number;
  col: number;
  colSpan: number;
  rowSpan: number;
}

/**
 * props: { borderSpacing, collapse, caption?: 'top'|'bottom' }
 * children: optional caption (RenderObject with props.isCaption) then rows.
 */
export class RenderTable extends RenderObject {
  private cells: Cell[] = [];
  private columns = 0;

  private collect(): { rows: RenderTableRow[]; caption: RenderObject | null } {
    const rows: RenderTableRow[] = [];
    let caption: RenderObject | null = null;
    for (const child of this.children) {
      if (child instanceof RenderTableRow) rows.push(child);
      else if (!caption) caption = child;
    }
    return { rows, caption };
  }

  private place(rows: RenderTableRow[]): void {
    this.cells = [];
    const occupied = new Set<string>();
    let columns = 0;
    rows.forEach((row, r) => {
      let col = 0;
      for (const cellRo of row.children) {
        if (!(cellRo instanceof RenderTableCell)) continue;
        while (occupied.has(r + ':' + col)) col++;
        const colSpan = Math.max(1, Math.trunc(cellRo.props.colSpan ?? 1));
        const rowSpan = Math.max(1, Math.min(rows.length - r, Math.trunc(cellRo.props.rowSpan ?? 1)));
        for (let rr = r; rr < r + rowSpan; rr++) for (let cc = col; cc < col + colSpan; cc++) occupied.add(rr + ':' + cc);
        this.cells.push({ ro: cellRo, row: r, col, colSpan, rowSpan });
        col += colSpan;
        columns = Math.max(columns, col);
      }
    });
    this.columns = columns;
  }

  private columnWidths(available: number, spacing: number): number[] {
    const n = this.columns;
    const minW = new Array<number>(n).fill(0);
    const maxW = new Array<number>(n).fill(0);
    const spans = this.cells.slice().sort((a, b) => a.colSpan - b.colSpan);
    for (const cell of spans) {
      const cmin = cell.ro.minIntrinsicWidth(INF);
      const cmax = cell.ro.maxIntrinsicWidth(INF);
      const fixed: number | null = cell.ro.props.width ?? null;
      if (cell.colSpan === 1) {
        minW[cell.col] = Math.max(minW[cell.col], fixed ?? cmin);
        maxW[cell.col] = Math.max(maxW[cell.col], fixed ?? cmax);
      } else {
        const cols = Array.from({ length: cell.colSpan }, (_, k) => cell.col + k).filter((k) => k < n);
        const inner = (cell.colSpan - 1) * spacing;
        const curMin = cols.reduce((s, k) => s + minW[k], 0) + inner;
        const curMax = cols.reduce((s, k) => s + maxW[k], 0) + inner;
        if (cmin > curMin) for (const k of cols) minW[k] += (cmin - curMin) / cols.length;
        if (cmax > curMax) for (const k of cols) maxW[k] += (cmax - curMax) / cols.length;
      }
    }
    for (let k = 0; k < n; k++) maxW[k] = Math.max(maxW[k], minW[k]);
    const gaps = (n + 1) * spacing;
    const sumMax = maxW.reduce((a, b) => a + b, 0);
    const sumMin = minW.reduce((a, b) => a + b, 0);
    const room = available - gaps;
    if (!Number.isFinite(available) || sumMax <= room) {
      if (this.props.fullWidth && Number.isFinite(available) && sumMax > 0 && sumMax < room) {
        return maxW.map((w) => w + ((room - sumMax) * w) / sumMax);
      }
      return maxW;
    }
    if (sumMin >= room) return minW;
    const extra = room - sumMin;
    const flexTotal = sumMax - sumMin;
    return minW.map((w, k) => w + (flexTotal > 0 ? (extra * (maxW[k] - minW[k])) / flexTotal : extra / n));
  }

  protected performLayout(c: Constraints): void {
    const spacing: number = this.props.collapse === false ? this.props.borderSpacing ?? 2 : 0;
    const { rows, caption } = this.collect();
    this.place(rows);
    const widths = this.columnWidths(c.maxWidth, spacing);
    const colX: number[] = [];
    let x = spacing;
    for (const w of widths) {
      colX.push(x);
      x += w + spacing;
    }
    const tableWidth = Math.max(x, c.minWidth);
    const spanW = (col: number, span: number) => {
      let s = 0;
      for (let k = col; k < col + span && k < widths.length; k++) s += widths[k];
      return s + (span - 1) * spacing;
    };

    const rowH = new Array<number>(rows.length).fill(0);
    for (const cell of this.cells) {
      const w = spanW(cell.col, cell.colSpan);
      cell.ro.layout({ minWidth: w, maxWidth: w, minHeight: 0, maxHeight: INF });
      if (cell.rowSpan === 1) rowH[cell.row] = Math.max(rowH[cell.row], cell.ro.size.height);
    }
    for (const cell of this.cells) {
      if (cell.rowSpan === 1) continue;
      let h = 0;
      for (let r = cell.row; r < cell.row + cell.rowSpan; r++) h += rowH[r];
      h += (cell.rowSpan - 1) * spacing;
      if (cell.ro.size.height > h) rowH[cell.row + cell.rowSpan - 1] += cell.ro.size.height - h;
    }

    let y = 0;
    let captionHeight = 0;
    const captionBottom = this.props.caption === 'bottom';
    if (caption) {
      caption.layout({ minWidth: tableWidth, maxWidth: tableWidth, minHeight: 0, maxHeight: INF });
      captionHeight = caption.size.height;
      if (!captionBottom) {
        caption.offset = { x: 0, y: 0 };
        y = captionHeight;
      }
    }
    const rowY: number[] = [];
    y += spacing;
    for (let r = 0; r < rows.length; r++) {
      rowY.push(y);
      y += rowH[r] + spacing;
    }
    // Each row spans the full table width; cells are positioned inside it.
    rows.forEach((row, r) => {
      row.size = { width: tableWidth, height: rowH[r] };
      row.offset = { x: 0, y: rowY[r] };
      (row as any).needsLayout = false;
    });
    for (const cell of this.cells) {
      let h = 0;
      for (let rr = cell.row; rr < cell.row + cell.rowSpan; rr++) h += rowH[rr];
      h += (cell.rowSpan - 1) * spacing;
      const w = spanW(cell.col, cell.colSpan);
      cell.ro.layout({ minWidth: w, maxWidth: w, minHeight: h, maxHeight: h });
      cell.ro.offset = { x: colX[cell.col], y: 0 };
      if (cell.rowSpan > 1) cell.ro.offset.y = 0;
    }
    if (caption && captionBottom) {
      caption.offset = { x: 0, y };
      y += captionHeight;
    }
    this.size = constrain(c, { width: tableWidth, height: y });
  }

  protected computeMinIntrinsicWidth(): number {
    const { rows } = this.collect();
    this.place(rows);
    return this.columnWidths(0, 0).reduce((a, b) => a + b, 0);
  }
  protected computeMaxIntrinsicWidth(): number {
    const { rows } = this.collect();
    this.place(rows);
    return this.columnWidths(INF, 0).reduce((a, b) => a + b, 0);
  }
}
