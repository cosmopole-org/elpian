/**
 * A surface's data model: one JSON document addressed by JSON Pointers, with
 * the write semantics the A2UI conformance suite (`data_model.yaml`,
 * `data_deletion.yaml`) fixes:
 *
 * - writes auto-vivify missing containers — a list when the next segment is
 *   an index, an object otherwise — and pad lists with `null`;
 * - writing through a primitive, a non-numeric (or leading-zero) list
 *   segment, or a list index above {@link MAX_LIST_INDEX} is a `DataError`,
 *   and leaves the model untouched;
 * - deleting removes an object key, but sets a list slot to `null` so list
 *   length is preserved; deleting the root resets it to `{}`;
 * - observers on a path fire when its value changes — writes to the path, to
 *   an ancestor, or to a descendant — but not on same-value rewrites.
 */
import { dataError } from './errors.js';
import { formatPointer, isIndexSegment, isPrefixOf, parsePointer } from './pointer.js';

export const MAX_LIST_INDEX = 10000;

export type DataObserver = (value: unknown, path: string) => void;

interface Watch {
  segments: string[];
  path: string;
  observer: DataObserver;
}

export class DataModel {
  private root: unknown;
  private watches: Watch[] = [];

  constructor(initial: unknown = {}) {
    this.root = initial === undefined ? {} : cloneJson(initial);
  }

  /** The value at [path], or `undefined` when nothing is there. */
  get(path = '/'): unknown {
    return lookup(this.root, parsePointer(path));
  }

  /** The whole document (do not mutate). */
  get value(): unknown {
    return this.root;
  }

  /** A deep copy of the whole document. */
  snapshot(): unknown {
    return cloneJson(this.root);
  }

  /** Write [value] at [path]; `undefined` deletes. */
  set(path: string, value: unknown): void {
    if (value === undefined) {
      this.delete(path);
      return;
    }
    const segments = parsePointer(path);
    const fresh = cloneJson(value);
    if (segments.length === 0) {
      this.mutate(segments, () => {
        this.root = fresh;
      });
      return;
    }
    checkWritable(this.root, segments, path);
    this.mutate(segments, () => {
      if (this.root === null || this.root === undefined) this.root = isIndexSegment(segments[0]) ? [] : {};
      let container = this.root as any;
      for (let i = 0; i < segments.length - 1; i++) {
        const seg = segments[i];
        const key = Array.isArray(container) ? Number(seg) : seg;
        if (Array.isArray(container)) padList(container, key as number);
        let child = own(container, key);
        if (child === undefined || child === null) {
          child = isIndexSegment(segments[i + 1]) ? [] : {};
          container[key] = child;
        }
        container = child;
      }
      const last = segments[segments.length - 1];
      if (Array.isArray(container)) {
        const index = Number(last);
        padList(container, index);
        container[index] = fresh;
      } else {
        container[last] = fresh;
      }
    });
  }

  /**
   * Remove the value at [path]: an object key is deleted, a list slot is set
   * to `null` (length preserved), the root resets to `{}`. A missing path is a
   * no-op that creates nothing.
   */
  delete(path: string): void {
    const segments = parsePointer(path);
    if (segments.length === 0) {
      this.mutate(segments, () => {
        this.root = {};
      });
      return;
    }
    const parent = lookup(this.root, segments.slice(0, -1));
    const last = segments[segments.length - 1];
    if (Array.isArray(parent)) {
      if (!isIndexSegment(last) || Number(last) >= parent.length) return;
      this.mutate(segments, () => {
        parent[Number(last)] = null;
      });
    } else if (parent !== null && typeof parent === 'object') {
      if (!Object.prototype.hasOwnProperty.call(parent, last)) return;
      this.mutate(segments, () => {
        delete (parent as any)[last];
      });
    }
  }

  /** Observe [path]; returns the unsubscribe function. */
  watch(path: string, observer: DataObserver): () => void {
    const segments = parsePointer(path);
    const entry: Watch = { segments, path: formatPointer(segments), observer };
    this.watches.push(entry);
    return () => {
      this.watches = this.watches.filter((w) => w !== entry);
    };
  }

  /** Detach every observer. */
  dispose(): void {
    this.watches = [];
  }

  /**
   * Run [change] (which replaces or removes the value at [target]) and notify
   * every observer whose value changed: ancestors when the target changed,
   * the target itself, and descendants whose own value differs afterwards.
   */
  private mutate(target: string[], change: () => void): void {
    const related = this.watches.filter((w) => isPrefixOf(w.segments, target) || isPrefixOf(target, w.segments));
    const before = lookup(this.root, target);
    // The old subtree is replaced, never mutated, so these stay valid snapshots.
    const descendantsBefore = related.filter((w) => w.segments.length > target.length).map((w) => lookup(this.root, w.segments));
    change();
    if (related.length === 0) return;
    const after = lookup(this.root, target);
    const targetChanged = !jsonEqual(before, after);
    let d = 0;
    const fire: Watch[] = [];
    for (const w of related) {
      if (w.segments.length <= target.length) {
        if (targetChanged) fire.push(w);
      } else {
        const old = descendantsBefore[d++];
        if (!jsonEqual(old, lookup(this.root, w.segments))) fire.push(w);
      }
    }
    for (const w of fire) {
      try {
        w.observer(lookup(this.root, w.segments), w.path);
      } catch (e) {
        console.warn('A2UI data observer failed:', e);
      }
    }
  }
}

function own(container: any, key: string | number): any {
  if (Array.isArray(container)) return container[key as number];
  return Object.prototype.hasOwnProperty.call(container, key) ? container[key] : undefined;
}

function lookup(root: unknown, segments: readonly string[]): unknown {
  let current: any = root;
  for (const seg of segments) {
    if (Array.isArray(current)) {
      if (!isIndexSegment(seg)) return undefined;
      const i = Number(seg);
      if (i >= current.length) return undefined;
      current = current[i];
    } else if (current !== null && typeof current === 'object') {
      if (!Object.prototype.hasOwnProperty.call(current, seg)) return undefined;
      current = current[seg];
    } else {
      return undefined;
    }
    if (current === undefined) return undefined;
  }
  return current;
}

/** Validate a write before touching the model, so a failed write changes nothing. */
function checkWritable(root: unknown, segments: readonly string[], path: string): void {
  let current: any = root;
  let vivified = false;
  for (let i = 0; i < segments.length; i++) {
    const seg = segments[i];
    let isList: boolean;
    if (vivified || current === null || current === undefined) {
      // A missing or null slot (including a null root) becomes a container.
      isList = isIndexSegment(seg);
      vivified = true;
    } else if (Array.isArray(current)) {
      isList = true;
    } else if (typeof current === 'object') {
      isList = false;
    } else {
      throw dataError(`Cannot set path "${path}": "${formatPointer(segments.slice(0, i))}" holds a primitive value`);
    }
    if (isList) {
      if (!isIndexSegment(seg)) throw dataError(`Cannot set path "${path}": non-numeric segment "${seg}" addresses a list`);
      if (Number(seg) > MAX_LIST_INDEX) throw dataError(`Cannot set path "${path}": list index ${seg} exceeds the maximum of ${MAX_LIST_INDEX}`);
    }
    if (!vivified) {
      const next = Array.isArray(current) ? current[Number(seg)] : Object.prototype.hasOwnProperty.call(current, seg) ? current[seg] : undefined;
      if (next === undefined || next === null) vivified = true;
      current = next;
    }
  }
}

function padList(list: unknown[], index: number): void {
  while (list.length < index) list.push(null);
}

/** Deep copy of a JSON value (functions and `undefined` members dropped). */
export function cloneJson<T>(value: T): T {
  if (value === null || typeof value !== 'object') return value;
  if (Array.isArray(value)) return value.map((v) => (v === undefined ? null : cloneJson(v))) as any;
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
    if (v === undefined || typeof v === 'function') continue;
    out[k] = cloneJson(v);
  }
  return out as T;
}

/** Structural equality of JSON values (`-0` equals `0`). */
export function jsonEqual(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (a === null || b === null || typeof a !== 'object' || typeof b !== 'object') return false;
  if (Array.isArray(a) !== Array.isArray(b)) return false;
  if (Array.isArray(a)) {
    const bl = b as unknown[];
    if (a.length !== bl.length) return false;
    for (let i = 0; i < a.length; i++) if (!jsonEqual(a[i], bl[i])) return false;
    return true;
  }
  const ka = Object.keys(a as object);
  const kb = Object.keys(b as object);
  if (ka.length !== kb.length) return false;
  for (const k of ka) {
    if (!Object.prototype.hasOwnProperty.call(b, k)) return false;
    if (!jsonEqual((a as any)[k], (b as any)[k])) return false;
  }
  return true;
}
