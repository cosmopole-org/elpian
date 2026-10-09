/**
 * Godot values on the wire — a port of `protocol.dart` and `godot_values.dart`.
 *
 * Ops are JSON objects (`{"new": "MeshInstance3D", "def": 7}`,
 * `{"ref": 7, "set": "position", "value": {"vec3": [0, 1, 0]}}` …); typed
 * Godot values are single-key tagged objects. Handles are allocated on this
 * side, so a whole scene can be built and addressed before the engine has
 * rendered a frame.
 */

export type Wire = unknown;
export type Op = Record<string, unknown>;

export const OpKey = {
  create: 'new',
  def: 'def',
  self: 'self',
  tree: 'tree',
  singleton: 'singleton',
  load: 'load',
  free: 'free',
  ref: 'ref',
  get: 'get',
  set: 'set',
  getIndexed: 'geti',
  setIndexed: 'seti',
  value: 'value',
  props: 'props',
  method: 'method',
  args: 'args',
  static_: 'static',
  connect: 'connect',
  disconnect: 'disconnect',
  cb: 'cb',
  flags: 'flags',
  constant: 'const',
  expr: 'expr',
  names: 'names',
  values: 'values',
  classes: 'classes',
  classInfo: 'classinfo',
  audit: 'audit',
  mount: 'mount',
  surface: 'surface',
} as const;

export class GodotRef {
  constructor(readonly id: number) {}
  toWire(): Record<string, unknown> {
    return { ref: this.id };
  }
  static isRef(v: unknown): boolean {
    return !!v && typeof v === 'object' && Object.keys(v as object).length === 1 && Number.isInteger((v as any).ref);
  }
}

export class GodotCallbackRef {
  constructor(readonly id: number) {}
  toWire(): Record<string, unknown> {
    return { cb: this.id };
  }
}

export class HandleAllocator {
  static readonly selfHandle = 1;
  private next: number;
  constructor(start = HandleAllocator.selfHandle + 1) {
    this.next = start;
  }
  allocate(): number {
    return this.next++;
  }
  get issued(): number {
    return this.next - HandleAllocator.selfHandle - 1;
  }
}

export function wireError(message: string): Record<string, unknown> {
  return { __dart_error__: message };
}

export function isWireError(v: unknown): boolean {
  return !!v && typeof v === 'object' && '__dart_error__' in (v as object);
}

export function wireErrorMessage(v: unknown): string | null {
  return isWireError(v) ? String((v as any).__dart_error__) : null;
}

export class GodotOpException extends Error {
  constructor(
    message: string,
    readonly op?: Op,
  ) {
    super(op ? `GodotOpException: ${message} (op: ${JSON.stringify(op)})` : `GodotOpException: ${message}`);
  }
}

export function encodeOps(ops: Op[]): string {
  return JSON.stringify(ops);
}

export function decodeReplies(json: string): Wire[] {
  if (!json) return [];
  const decoded = JSON.parse(json);
  return Array.isArray(decoded) ? decoded : [decoded];
}

// ---------------------------------------------------------------------------
// Typed values
// ---------------------------------------------------------------------------

export abstract class GodotValue {
  abstract toWire(): Record<string, unknown>;
}

function tagged(tag: string, data: unknown): Record<string, unknown> {
  return { [tag]: data };
}

export class Vector2 extends GodotValue {
  constructor(readonly x: number, readonly y: number) {
    super();
  }
  toWire() {
    return tagged('vec2', [this.x, this.y]);
  }
}
export class Vector2i extends GodotValue {
  constructor(readonly x: number, readonly y: number) {
    super();
  }
  toWire() {
    return tagged('vec2i', [this.x, this.y]);
  }
}
export class Vector3 extends GodotValue {
  constructor(readonly x: number, readonly y: number, readonly z: number) {
    super();
  }
  static all(v: number): Vector3 {
    return new Vector3(v, v, v);
  }
  plus(o: Vector3): Vector3 {
    return new Vector3(this.x + o.x, this.y + o.y, this.z + o.z);
  }
  minus(o: Vector3): Vector3 {
    return new Vector3(this.x - o.x, this.y - o.y, this.z - o.z);
  }
  times(s: number): Vector3 {
    return new Vector3(this.x * s, this.y * s, this.z * s);
  }
  toWire() {
    return tagged('vec3', [this.x, this.y, this.z]);
  }
}
export class Vector3i extends GodotValue {
  constructor(readonly x: number, readonly y: number, readonly z: number) {
    super();
  }
  toWire() {
    return tagged('vec3i', [this.x, this.y, this.z]);
  }
}
export class Vector4 extends GodotValue {
  constructor(readonly x: number, readonly y: number, readonly z: number, readonly w: number) {
    super();
  }
  toWire() {
    return tagged('vec4', [this.x, this.y, this.z, this.w]);
  }
}
export class Vector4i extends GodotValue {
  constructor(readonly x: number, readonly y: number, readonly z: number, readonly w: number) {
    super();
  }
  toWire() {
    return tagged('vec4i', [this.x, this.y, this.z, this.w]);
  }
}
export class GodotColor extends GodotValue {
  constructor(readonly r: number, readonly g: number, readonly b: number, readonly a = 1) {
    super();
  }
  static hex(rgb: number, a = 1): GodotColor {
    return new GodotColor(((rgb >> 16) & 0xff) / 255, ((rgb >> 8) & 0xff) / 255, (rgb & 0xff) / 255, a);
  }
  toWire() {
    return tagged('color', [this.r, this.g, this.b, this.a]);
  }
}
export class Rect2 extends GodotValue {
  constructor(readonly x: number, readonly y: number, readonly w: number, readonly h: number) {
    super();
  }
  toWire() {
    return tagged('rect2', [this.x, this.y, this.w, this.h]);
  }
}
export class Rect2i extends GodotValue {
  constructor(readonly x: number, readonly y: number, readonly w: number, readonly h: number) {
    super();
  }
  toWire() {
    return tagged('rect2i', [this.x, this.y, this.w, this.h]);
  }
}
export class Plane extends GodotValue {
  constructor(readonly nx: number, readonly ny: number, readonly nz: number, readonly d: number) {
    super();
  }
  toWire() {
    return tagged('plane', [this.nx, this.ny, this.nz, this.d]);
  }
}
export class Quaternion extends GodotValue {
  constructor(readonly x: number, readonly y: number, readonly z: number, readonly w: number) {
    super();
  }
  toWire() {
    return tagged('quat', [this.x, this.y, this.z, this.w]);
  }
}
export class AABB extends GodotValue {
  constructor(readonly px: number, readonly py: number, readonly pz: number, readonly sx: number, readonly sy: number, readonly sz: number) {
    super();
  }
  toWire() {
    return tagged('aabb', [this.px, this.py, this.pz, this.sx, this.sy, this.sz]);
  }
}
export class Basis extends GodotValue {
  constructor(readonly rows: number[][]) {
    super();
  }
  toWire() {
    return tagged('basis', this.rows);
  }
}
export class Transform2D extends GodotValue {
  constructor(readonly m: number[]) {
    super();
  }
  toWire() {
    return tagged('xform2d', this.m);
  }
}
export class Transform3D extends GodotValue {
  constructor(readonly m: number[]) {
    super();
  }
  toWire() {
    return tagged('xform3d', this.m);
  }
}
export class Projection extends GodotValue {
  constructor(readonly m: number[]) {
    super();
  }
  toWire() {
    return tagged('proj', this.m);
  }
}
export class StringName extends GodotValue {
  constructor(readonly value: string) {
    super();
  }
  toWire() {
    return tagged('sname', this.value);
  }
}
export class NodePath extends GodotValue {
  constructor(readonly value: string) {
    super();
  }
  toWire() {
    return tagged('npath', this.value);
  }
}
export class GRid extends GodotValue {
  constructor(readonly id: number) {
    super();
  }
  toWire() {
    return tagged('rid', this.id);
  }
}
export class GSignal extends GodotValue {
  constructor(readonly sourceHandle: number, readonly name: string) {
    super();
  }
  toWire() {
    return tagged('sig', [new GodotRef(this.sourceHandle).toWire(), this.name]);
  }
}
export class GCallable extends GodotValue {
  constructor(readonly callbackId: number) {
    super();
  }
  toWire() {
    return tagged('callable', this.callbackId);
  }
}
export class GInt extends GodotValue {
  constructor(readonly value: number) {
    super();
  }
  toWire() {
    return tagged('int', Math.trunc(this.value));
  }
}
export class GFloat extends GodotValue {
  constructor(readonly value: number) {
    super();
  }
  toWire() {
    return tagged('float', this.value);
  }
}
export class GDict extends GodotValue {
  constructor(readonly entries: [unknown, unknown][]) {
    super();
  }
  toWire() {
    return tagged('dictv', this.entries.map(([k, v]) => [marshal(k), marshal(v)]));
  }
}
export class Packed extends GodotValue {
  constructor(readonly tag: string, readonly data: unknown) {
    super();
  }
  static bytesBase64(b64: string) {
    return new Packed('u8', b64);
  }
  static i32(v: number[]) {
    return new Packed('i32', v);
  }
  static i64(v: number[]) {
    return new Packed('i64', v);
  }
  static f32(v: number[]) {
    return new Packed('f32', v);
  }
  static f64(v: number[]) {
    return new Packed('f64', v);
  }
  static strings(v: string[]) {
    return new Packed('strs', v);
  }
  static vector2s(flat: number[]) {
    return new Packed('pv2', flat);
  }
  static vector3s(flat: number[]) {
    return new Packed('pv3', flat);
  }
  static vector4s(flat: number[]) {
    return new Packed('pv4', flat);
  }
  static colors(flat: number[]) {
    return new Packed('pcol', flat);
  }
  toWire() {
    return tagged(this.tag, this.data);
  }
}

/** Anything that exposes a [GodotRef] (GodotObject). */
export interface GodotHandle {
  readonly ref: GodotRef;
}

function isHandle(v: unknown): v is GodotHandle {
  return !!v && typeof v === 'object' && (v as any).ref instanceof GodotRef;
}

export function marshal(v: unknown): unknown {
  if (v == null || typeof v === 'boolean' || typeof v === 'string' || typeof v === 'number') return v;
  if (v instanceof GodotValue) return v.toWire();
  if (v instanceof GodotRef) return v.toWire();
  if (v instanceof GodotCallbackRef) return v.toWire();
  if (isHandle(v)) return v.ref.toWire();
  if (Array.isArray(v)) return v.map(marshal);
  if (typeof v === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, val] of Object.entries(v as Record<string, unknown>)) out[k] = marshal(val);
    return { dict: out };
  }
  return v;
}

export function marshalArgs(args: unknown[] | null | undefined): unknown[] {
  return args ? args.map(marshal) : [];
}

export function unmarshal(v: unknown): unknown {
  if (Array.isArray(v)) return v.map(unmarshal);
  if (!v || typeof v !== 'object') return v;
  const map = v as Record<string, any>;
  if ('__dart_error__' in map) return v;
  const keys = Object.keys(map);
  if (keys.length !== 1) return v;
  const key = keys[0];
  const data = map[key];
  const nums = () => (data as unknown[]).map((e) => Number(e));
  const ints = () => (data as unknown[]).map((e) => Math.trunc(Number(e)));
  switch (key) {
    case 'ref':
      return new GodotRef(data);
    case 'vec2': {
      const n = nums();
      return new Vector2(n[0], n[1]);
    }
    case 'vec2i': {
      const n = ints();
      return new Vector2i(n[0], n[1]);
    }
    case 'vec3': {
      const n = nums();
      return new Vector3(n[0], n[1], n[2]);
    }
    case 'vec3i': {
      const n = ints();
      return new Vector3i(n[0], n[1], n[2]);
    }
    case 'vec4': {
      const n = nums();
      return new Vector4(n[0], n[1], n[2], n[3]);
    }
    case 'vec4i': {
      const n = ints();
      return new Vector4i(n[0], n[1], n[2], n[3]);
    }
    case 'color': {
      const n = nums();
      return new GodotColor(n[0], n[1], n[2], n[3]);
    }
    case 'rect2': {
      const n = nums();
      return new Rect2(n[0], n[1], n[2], n[3]);
    }
    case 'rect2i': {
      const n = ints();
      return new Rect2i(n[0], n[1], n[2], n[3]);
    }
    case 'plane': {
      const n = nums();
      return new Plane(n[0], n[1], n[2], n[3]);
    }
    case 'quat': {
      const n = nums();
      return new Quaternion(n[0], n[1], n[2], n[3]);
    }
    case 'aabb': {
      const n = nums();
      return new AABB(n[0], n[1], n[2], n[3], n[4], n[5]);
    }
    case 'basis':
      return new Basis((data as unknown[][]).map((row) => row.map((e) => Number(e))));
    case 'xform2d':
      return new Transform2D(nums());
    case 'xform3d':
      return new Transform3D(nums());
    case 'proj':
      return new Projection(nums());
    case 'sname':
      return new StringName(String(data));
    case 'npath':
      return new NodePath(String(data));
    case 'rid':
      return new GRid(Number(data));
    case 'int':
      return Math.trunc(Number(data));
    case 'float':
      return Number(data);
    case 'callable':
      return new GCallable(Number(data));
    case 'dict': {
      const out: Record<string, unknown> = {};
      for (const [k, val] of Object.entries(data as Record<string, unknown>)) out[k] = unmarshal(val);
      return out;
    }
    case 'dictv':
      return new GDict((data as unknown[][]).map((pair) => [unmarshal(pair[0]), unmarshal(pair[1])]));
    case 'u8':
    case 'i32':
    case 'i64':
    case 'f32':
    case 'f64':
    case 'strs':
    case 'pv2':
    case 'pv3':
    case 'pv4':
    case 'pcol':
      return new Packed(key, data);
    default:
      return v;
  }
}
