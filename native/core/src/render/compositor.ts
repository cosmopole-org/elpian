/**
 * The compositor walks the laid-out render tree, assigns a native view to
 * every object that paints, and diffs the result against the previous frame
 * into [ViewOp]s: creates (parents before children), moves, prop updates and
 * removals. Layout-only objects (padding, alignment, flex…) never reach the
 * platform; they just shift the frames of the views below them.
 */
import type { RenderObject } from './object.js';
import type { RenderOwner } from './owner.js';
import { ROOT_VIEW_ID, type ViewKind, type ViewOp, type ViewProps } from './view.js';

interface ViewRecord {
  kind: ViewKind;
  parent: number;
  ro: RenderObject;
  /** Last emitted JSON of each prop, for diffing. */
  props: Map<string, string>;
}

interface Placement {
  id: number;
  parent: number;
  kind: ViewKind;
  ro: RenderObject;
  props: ViewProps;
}

/** Props sent when present and never diffed or reset (incremental payloads, one-shot requests). */
const ONE_SHOT = new Set(['commands', 'appendCommands', 'scrollTo']);

function round(v: number): number {
  return Math.round(v * 1000) / 1000;
}

export class Compositor {
  private views = new Map<number, ViewRecord>();
  private childLists = new Map<number, number[]>();
  private pendingCommands: ViewOp[] = [];

  constructor(private readonly owner: RenderOwner) {}

  objectFor(viewId: number): RenderObject | undefined {
    return this.views.get(viewId)?.ro;
  }

  hasView(viewId: number): boolean {
    return this.views.has(viewId);
  }

  /** Queue an imperative command for a view (focus, scroll, play…). */
  command(viewId: number, name: string, args?: any): void {
    this.pendingCommands.push({ op: 'command', id: viewId, name, args });
    this.owner.requestVisualUpdate();
  }

  /** Forget the last-sent value of [keys] so the next frame re-sends them (controlled inputs). */
  invalidateProps(viewId: number, keys: string[]): void {
    const record = this.views.get(viewId);
    if (!record) return;
    for (const k of keys) record.props.delete(k);
    this.owner.requestVisualUpdate();
  }

  /** The absolute frame of a view (sum of ancestor frames). */
  globalFrame(ro: RenderObject): { x: number; y: number; width: number; height: number } {
    let x = 0;
    let y = 0;
    let node: RenderObject | null = ro;
    while (node) {
      x += node.offset.x;
      y += node.offset.y;
      const parent: RenderObject | null = node.parent;
      if (parent && parent.viewKind() === 'scroll') {
        const scroll = (parent as any).scrollOffset as { x: number; y: number } | undefined;
        if (scroll) {
          x -= scroll.x;
          y -= scroll.y;
        }
      }
      node = parent;
    }
    return { x, y, width: ro.size.width, height: ro.size.height };
  }

  composite(root: RenderObject): ViewOp[] {
    const placements: Placement[] = [];
    const lists = new Map<number, number[]>();
    const walk = (ro: RenderObject, parentView: number, ox: number, oy: number) => {
      const x = ox + ro.offset.x;
      const y = oy + ro.offset.y;
      const kind = ro.viewKind();
      if (kind) {
        const previous = ro.viewId != null ? this.views.get(ro.viewId) : undefined;
        // A view that changed kind or parent is recreated under a new id (its
        // old subtree is removed wholesale), so the platform never has to
        // reparent native views.
        if (ro.viewId == null || (previous && (previous.kind !== kind || previous.parent !== parentView))) {
          ro.viewId = this.owner.allocateViewId();
        }
        const id = ro.viewId;
        const props: ViewProps = { frame: [round(x), round(y), round(ro.size.width), round(ro.size.height)], ...ro.viewProps() };
        placements.push({ id, parent: parentView, kind, ro, props });
        let list = lists.get(parentView);
        if (!list) lists.set(parentView, (list = []));
        list.push(id);
        const origin = ro.childOriginInView();
        for (const child of ro.children) if (ro.paintsChild(child)) walk(child, id, origin.x, origin.y);
      } else {
        for (const child of ro.children) if (ro.paintsChild(child)) walk(child, parentView, x, y);
      }
    };
    walk(root, ROOT_VIEW_ID, 0, 0);

    const ops: ViewOp[] = [];
    const nextIds = new Set(placements.map((p) => p.id));

    // Removals first — only the topmost removed view of each removed subtree.
    for (const [id, record] of this.views) {
      if (nextIds.has(id)) continue;
      // A view whose kind changed is recreated under the same id.
      const parentGone = record.parent !== ROOT_VIEW_ID && !nextIds.has(record.parent) && this.views.has(record.parent);
      if (!parentGone) ops.push({ op: 'remove', id });
    }
    for (const id of [...this.views.keys()]) if (!nextIds.has(id)) this.views.delete(id);

    // Which parents' child orders changed?
    const reordered = new Set<number>();
    for (const [parent, list] of lists) {
      const prev = this.childLists.get(parent);
      if (!prev || prev.length !== list.length || prev.some((id, i) => id !== list[i])) reordered.add(parent);
    }

    // Creates / moves / updates in tree order (parents before children).
    const indexOf = new Map<number, number>();
    for (const list of lists.values()) list.forEach((id, i) => indexOf.set(id, i));
    for (const p of placements) {
      const index = indexOf.get(p.id) ?? 0;
      const existing = this.views.get(p.id);
      if (!existing) {
        const record: ViewRecord = { kind: p.kind, parent: p.parent, ro: p.ro, props: new Map() };
        for (const [k, v] of Object.entries(p.props)) if (v !== undefined && !ONE_SHOT.has(k)) record.props.set(k, JSON.stringify(v));
        this.views.set(p.id, record);
        ops.push({ op: 'create', id: p.id, kind: p.kind, parent: p.parent, index, props: stripUndefined(p.props) });
        continue;
      }
      existing.ro = p.ro;
      if (reordered.has(p.parent)) {
        ops.push({ op: 'move', id: p.id, parent: p.parent, index });
        existing.parent = p.parent;
      }
      const changed: Partial<ViewProps> = {};
      let any = false;
      const seenKeys = new Set<string>();
      for (const [k, v] of Object.entries(p.props)) {
        if (v === undefined) continue;
        if (ONE_SHOT.has(k)) {
          if (v !== null) {
            (changed as any)[k] = v;
            any = true;
          }
          continue;
        }
        seenKeys.add(k);
        const json = JSON.stringify(v);
        if (existing.props.get(k) !== json) {
          existing.props.set(k, json);
          (changed as any)[k] = v;
          any = true;
        }
      }
      for (const k of [...existing.props.keys()]) {
        if (!seenKeys.has(k)) {
          existing.props.delete(k);
          (changed as any)[k] = null;
          any = true;
        }
      }
      if (any) ops.push({ op: 'update', id: p.id, props: changed });
    }

    this.childLists = lists;
    if (this.pendingCommands.length) {
      for (const cmd of this.pendingCommands) if (this.views.has(cmd.id)) ops.push(cmd);
      this.pendingCommands = [];
    }
    return ops;
  }

  /** Remove every view (unmount). */
  clear(): ViewOp[] {
    const ops: ViewOp[] = [];
    for (const [id, record] of this.views) {
      if (record.parent === ROOT_VIEW_ID) ops.push({ op: 'remove', id });
    }
    this.views.clear();
    this.childLists.clear();
    this.pendingCommands = [];
    return ops;
  }

  get viewCount(): number {
    return this.views.size;
  }
}

function stripUndefined(props: ViewProps): ViewProps {
  const out: any = {};
  for (const [k, v] of Object.entries(props)) if (v !== undefined) out[k] = v;
  return out;
}
