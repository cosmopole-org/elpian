/**
 * The Godot controller — a port of `godot_binding.dart`, `godot_object.dart`
 * and `godot_controller.dart`.
 *
 * Ops are queued and flushed once per turn (a whole scene build costs one
 * crossing); reads (`request`) flush the queue and await the engine's reply.
 * Signals come back by callback id. The [GodotBinding] is the transport: the
 * platform's native engine (Android OpQueue / iOS GodotRuntimeHost / the web
 * page glue) or a recording mock when no engine is present.
 */
import type { GodotPlatformBinding } from '../platform/platform.js';
import {
  GFloat,
  GInt,
  GCallable,
  GodotColor,
  GodotOpException,
  GodotRef,
  GSignal,
  HandleAllocator,
  OpKey,
  Vector2,
  Vector3,
  decodeReplies,
  encodeOps,
  isWireError,
  marshal,
  marshalArgs,
  unmarshal,
  wireErrorMessage,
  type GodotHandle,
  type Op,
  type Wire,
} from './values.js';

export type GodotSignalCallback = (args: unknown[]) => void;

export interface GodotBinding {
  readonly isLive: boolean;
  send(ops: Op[]): Promise<Wire[]>;
  post(ops: Op[]): void;
  mountSurface(surfaceId: number, mountHandle: number): Promise<void>;
  releaseSurface(surfaceId: number): Promise<void>;
  onSignal: ((callbackId: number, args: unknown[]) => void) | null;
  stats(): Promise<Record<string, unknown> | null>;
  dispose(): void;
}

/** The transport over the platform's native engine bridge. */
export class PlatformGodotBinding implements GodotBinding {
  onSignal: ((callbackId: number, args: unknown[]) => void) | null = null;
  constructor(private readonly native: GodotPlatformBinding) {
    native.setSignalHandler((cb, argsJson) => {
      let args: unknown[] = [];
      try {
        const parsed = JSON.parse(argsJson);
        args = Array.isArray(parsed) ? parsed : [parsed];
      } catch {
        args = [];
      }
      this.onSignal?.(cb, args);
    });
  }
  get isLive(): boolean {
    return this.native.isLive;
  }
  async send(ops: Op[]): Promise<Wire[]> {
    if (ops.length === 0) return [];
    const reply = await this.native.send(encodeOps(ops));
    return reply ? decodeReplies(reply) : [];
  }
  post(ops: Op[]): void {
    if (ops.length) this.native.post(encodeOps(ops));
  }
  async mountSurface(surfaceId: number, mountHandle: number): Promise<void> {
    this.native.mountSurface(surfaceId, mountHandle);
  }
  async releaseSurface(surfaceId: number): Promise<void> {
    this.native.releaseSurface(surfaceId);
  }
  async stats(): Promise<Record<string, unknown> | null> {
    return (await this.native.stats?.()) ?? null;
  }
  dispose(): void {
    this.native.setSignalHandler(null);
  }
}

/** Records ops and echoes caller-allocated handles; used when no engine is linked. */
export class MockGodotBinding implements GodotBinding {
  readonly ops: Op[] = [];
  readonly surfaces = new Map<number, number>();
  private nextHostHandle = 1000000;
  onSignal: ((callbackId: number, args: unknown[]) => void) | null = null;
  get isLive(): boolean {
    return false;
  }
  private record(op: Op): Wire {
    this.ops.push(op);
    const produces = OpKey.create in op || op[OpKey.self] === true || op[OpKey.tree] === true || OpKey.singleton in op || OpKey.load in op;
    if (produces) {
      const def = op[OpKey.def];
      return typeof def === 'number' && def !== 0 ? def : this.nextHostHandle++;
    }
    return null;
  }
  async send(batch: Op[]): Promise<Wire[]> {
    return batch.map((op) => this.record(op));
  }
  post(batch: Op[]): void {
    for (const op of batch) this.record(op);
  }
  async mountSurface(surfaceId: number, mountHandle: number): Promise<void> {
    this.surfaces.set(surfaceId, mountHandle);
  }
  async releaseSurface(surfaceId: number): Promise<void> {
    this.surfaces.delete(surfaceId);
  }
  fireSignal(callbackId: number, args: unknown[]): void {
    this.onSignal?.(callbackId, args);
  }
  clear(): void {
    this.ops.length = 0;
  }
  async stats(): Promise<Record<string, unknown> | null> {
    return { pushed: this.ops.length, polls: 0, drained: this.ops.length };
  }
  dispose(): void {}
}

let nextSurfaceId = 1;

function scheduleMicrotask(fn: () => void): void {
  const q = (globalThis as any).queueMicrotask;
  if (typeof q === 'function') q(fn);
  else void Promise.resolve().then(fn);
}

export class GodotController {
  readonly surfaceId: number;
  private readonly handles = new HandleAllocator();
  private readonly callbacks = new Map<number, GodotSignalCallback>();
  private pending: Op[] = [];
  private nextCallbackId = 1;
  private explicitBatch = false;
  private flushScheduled = false;
  private disposed = false;
  private mounted = false;
  readonly root: GodotObject;
  readonly g3: Godot3D;
  private listeners = new Set<() => void>();

  constructor(
    readonly binding: GodotBinding,
    surfaceId?: number,
  ) {
    this.surfaceId = surfaceId ?? nextSurfaceId++;
    binding.onSignal = (id, args) => this.dispatchSignal(id, args);
    this.root = new GodotObject(this, HandleAllocator.selfHandle);
    this.g3 = new Godot3D(this);
  }

  get isLive(): boolean {
    return this.binding.isLive;
  }

  get pendingOps(): number {
    return this.pending.length;
  }

  addListener(fn: () => void): void {
    this.listeners.add(fn);
  }

  removeListener(fn: () => void): void {
    this.listeners.delete(fn);
  }

  // ---- op submission ------------------------------------------------------

  enqueue(op: Op): void {
    if (this.disposed) return;
    this.pending.push(op);
    if (!this.explicitBatch) this.scheduleFlush();
  }

  async request(op: Op): Promise<unknown> {
    if (this.disposed) return null;
    const batch = [...this.pending, op];
    this.pending = [];
    const replies = await this.binding.send(batch);
    if (replies.length < batch.length) return null;
    const reply = replies[batch.length - 1];
    if (isWireError(reply)) throw new GodotOpException(wireErrorMessage(reply) ?? 'engine error', op);
    return unmarshal(reply);
  }

  beginBatch(): void {
    this.explicitBatch = true;
  }

  endBatch(): void {
    this.explicitBatch = false;
    this.flush();
  }

  flush(): void {
    if (this.pending.length === 0 || this.disposed) return;
    const batch = this.pending;
    this.pending = [];
    this.binding.post(batch);
  }

  private scheduleFlush(): void {
    if (this.flushScheduled) return;
    this.flushScheduled = true;
    scheduleMicrotask(() => {
      this.flushScheduled = false;
      this.flush();
    });
  }

  // ---- object creation (the GD facade) -----------------------------------

  create(className: string): GodotObject {
    const handle = this.handles.allocate();
    this.enqueue({ [OpKey.create]: className, [OpKey.def]: handle });
    return new GodotObject(this, handle);
  }

  createWith(className: string, properties: Record<string, unknown>): GodotObject {
    const node = this.create(className);
    node.setAll(properties);
    return node;
  }

  singleton(name: string): GodotObject {
    const handle = this.handles.allocate();
    this.enqueue({ [OpKey.singleton]: name, [OpKey.def]: handle });
    return new GodotObject(this, handle);
  }

  tree(): GodotObject {
    const handle = this.handles.allocate();
    this.enqueue({ [OpKey.tree]: true, [OpKey.def]: handle });
    return new GodotObject(this, handle);
  }

  load(path: string): GodotObject {
    const handle = this.handles.allocate();
    this.enqueue({ [OpKey.load]: path, [OpKey.def]: handle });
    return new GodotObject(this, handle);
  }

  mount(node: GodotObject): void {
    this.root.addChild(node);
  }

  constant(name: string): Promise<unknown> {
    return this.request({ [OpKey.constant]: name });
  }

  evaluate(expression: string, names: string[] = [], values: unknown[] = []): Promise<unknown> {
    return this.request({ [OpKey.expr]: expression, [OpKey.names]: names, [OpKey.values]: marshalArgs(values) });
  }

  async classes(): Promise<string[]> {
    const reply = await this.request({ [OpKey.classes]: true });
    return Array.isArray(reply) ? reply.map(String) : [];
  }

  async classInfo(className: string): Promise<Record<string, unknown>> {
    const reply = await this.request({ [OpKey.classInfo]: className });
    return reply && typeof reply === 'object' ? (reply as Record<string, unknown>) : {};
  }

  audit(): Promise<unknown> {
    return this.request({ [OpKey.audit]: true });
  }

  stats(): Promise<Record<string, unknown> | null> {
    return this.binding.stats();
  }

  renderingServer(): GodotObject {
    return this.singleton('RenderingServer');
  }
  physicsServer3D(): GodotObject {
    return this.singleton('PhysicsServer3D');
  }
  physicsServer2D(): GodotObject {
    return this.singleton('PhysicsServer2D');
  }
  audioServer(): GodotObject {
    return this.singleton('AudioServer');
  }
  displayServer(): GodotObject {
    return this.singleton('DisplayServer');
  }
  input(): GodotObject {
    return this.singleton('Input');
  }
  engine(): GodotObject {
    return this.singleton('Engine');
  }
  os(): GodotObject {
    return this.singleton('OS');
  }
  time(): GodotObject {
    return this.singleton('Time');
  }
  projectSettings(): GodotObject {
    return this.singleton('ProjectSettings');
  }
  resourceLoader(): GodotObject {
    return this.singleton('ResourceLoader');
  }

  // ---- callbacks ----------------------------------------------------------

  registerCallback(callback: GodotSignalCallback): number {
    const id = this.nextCallbackId++;
    this.callbacks.set(id, callback);
    return id;
  }

  unregisterCallback(id: number): void {
    this.callbacks.delete(id);
  }

  callable(callback: GodotSignalCallback): GCallable {
    return new GCallable(this.registerCallback(callback));
  }

  private dispatchSignal(id: number, args: unknown[]): void {
    const callback = this.callbacks.get(id);
    if (!callback) return;
    callback(args.map(unmarshal));
  }

  releaseHandle(handle: number): void {
    this.enqueue({ [OpKey.free]: handle, weak: true });
  }

  // ---- surface lifecycle ---------------------------------------------------

  async attachSurface(): Promise<void> {
    if (this.mounted || this.disposed) return;
    this.mounted = true;
    this.flush();
    await this.binding.mountSurface(this.surfaceId, this.root.handle);
    for (const l of [...this.listeners]) l();
  }

  async detachSurface(): Promise<void> {
    if (!this.mounted) return;
    this.mounted = false;
    await this.binding.releaseSurface(this.surfaceId);
  }

  get isAttached(): boolean {
    return this.mounted;
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.pending = [];
    this.callbacks.clear();
    void this.detachSurface();
    this.binding.onSignal = null;
    this.listeners.clear();
  }
}

export class GodotObject implements GodotHandle {
  constructor(
    readonly controller: GodotController,
    readonly handle: number,
  ) {}

  get ref(): GodotRef {
    return new GodotRef(this.handle);
  }

  call(method: string, args?: unknown[]): Promise<unknown> {
    return this.controller.request({ [OpKey.ref]: this.handle, [OpKey.method]: method, [OpKey.args]: marshalArgs(args) });
  }

  callVoid(method: string, args?: unknown[]): void {
    this.controller.enqueue({ [OpKey.ref]: this.handle, [OpKey.method]: method, [OpKey.args]: marshalArgs(args) });
  }

  get(property: string): Promise<unknown> {
    return this.controller.request({ [OpKey.ref]: this.handle, [OpKey.get]: property });
  }

  set(property: string, value: unknown): void {
    this.controller.enqueue({ [OpKey.ref]: this.handle, [OpKey.set]: property, [OpKey.value]: marshal(value) });
  }

  setAll(properties: Record<string, unknown>): void {
    const keys = Object.keys(properties);
    if (keys.length === 0) return;
    const props: Record<string, unknown> = {};
    for (const k of keys) props[k] = marshal(properties[k]);
    this.controller.enqueue({ [OpKey.ref]: this.handle, [OpKey.props]: props });
  }

  getIndexed(path: string): Promise<unknown> {
    return this.controller.request({ [OpKey.ref]: this.handle, [OpKey.getIndexed]: path });
  }

  setIndexed(path: string, value: unknown): void {
    this.controller.enqueue({ [OpKey.ref]: this.handle, [OpKey.setIndexed]: path, [OpKey.value]: marshal(value) });
  }

  connect(signal: string, callback: GodotSignalCallback, flags = 0): number {
    const id = this.controller.registerCallback(callback);
    const op: Op = { [OpKey.ref]: this.handle, [OpKey.connect]: signal, [OpKey.cb]: id };
    if (flags !== 0) op[OpKey.flags] = flags;
    this.controller.enqueue(op);
    return id;
  }

  disconnect(signal: string, callbackId: number): void {
    this.controller.enqueue({ [OpKey.ref]: this.handle, [OpKey.disconnect]: signal, [OpKey.cb]: callbackId });
    this.controller.unregisterCallback(callbackId);
  }

  signal(name: string): GSignal {
    return new GSignal(this.handle, name);
  }

  emitSignal(name: string, args: unknown[] = []): void {
    this.callVoid('emit_signal', [name, ...args]);
  }

  addChild(child: GodotObject): void {
    this.callVoid('add_child', [child]);
  }

  removeChild(child: GodotObject): void {
    this.callVoid('remove_child', [child]);
  }

  addChildren(children: GodotObject[]): void {
    for (const c of children) this.addChild(c);
  }

  queueFree(): void {
    this.callVoid('queue_free');
  }

  freeNow(): void {
    this.controller.enqueue({ [OpKey.free]: this.handle });
  }

  release(): void {
    this.controller.releaseHandle(this.handle);
  }
}

/** The 3D convenience layer (`controller.g3`). */
export class Godot3D {
  constructor(private readonly c: GodotController) {}

  node(opts: { position?: unknown; rotation?: unknown; scale?: unknown; visible?: boolean | null } = {}): GodotObject {
    const n = this.c.create('Node3D');
    this.setTransform(n, opts);
    return n;
  }

  material(opts: { color?: GodotColor | null; metallic?: number | null; roughness?: number | null; emission?: GodotColor | null; emissionEnergy?: number | null; transparency?: boolean } = {}): GodotObject {
    const m = this.c.create('StandardMaterial3D');
    m.set('albedo_color', opts.color ?? new GodotColor(0.8, 0.82, 0.9, 1));
    if (opts.metallic != null) m.set('metallic', new GFloat(opts.metallic));
    if (opts.roughness != null) m.set('roughness', new GFloat(opts.roughness));
    if (opts.emission) {
      m.set('emission_enabled', true);
      m.set('emission', opts.emission);
      if (opts.emissionEnergy != null) m.set('emission_energy_multiplier', new GFloat(opts.emissionEnergy));
    }
    if (opts.transparency) m.set('transparency', new GInt(1));
    return m;
  }

  primitive(shape: string, options: Record<string, unknown> = {}): GodotObject {
    const n = (key: string, fallback: number) => (typeof options[key] === 'number' ? (options[key] as number) : fallback);
    switch (shape) {
      case 'sphere': {
        const mesh = this.c.create('SphereMesh');
        const r = n('radius', 0.5);
        mesh.set('radius', new GFloat(r));
        mesh.set('height', new GFloat(n('height', r * 2)));
        return mesh;
      }
      case 'cylinder': {
        const mesh = this.c.create('CylinderMesh');
        const r = n('radius', 0.5);
        mesh.set('top_radius', new GFloat(n('topRadius', r)));
        mesh.set('bottom_radius', new GFloat(n('bottomRadius', r)));
        mesh.set('height', new GFloat(n('height', 1)));
        return mesh;
      }
      case 'capsule': {
        const mesh = this.c.create('CapsuleMesh');
        mesh.set('radius', new GFloat(n('radius', 0.4)));
        mesh.set('height', new GFloat(n('height', 1.4)));
        return mesh;
      }
      case 'plane': {
        const mesh = this.c.create('PlaneMesh');
        mesh.set('size', new Vector2(n('width', 2), n('depth', 2)));
        return mesh;
      }
      case 'prism': {
        const mesh = this.c.create('PrismMesh');
        mesh.set('size', Godot3D.vec3(options.size, 1, 1, 1));
        return mesh;
      }
      case 'torus': {
        const mesh = this.c.create('TorusMesh');
        mesh.set('inner_radius', new GFloat(n('innerRadius', 0.3)));
        mesh.set('outer_radius', new GFloat(n('outerRadius', 0.6)));
        return mesh;
      }
      default: {
        const mesh = this.c.create('BoxMesh');
        mesh.set('size', Godot3D.vec3(options.size, 1, 1, 1));
        return mesh;
      }
    }
  }

  mesh(shape: string, options: Record<string, unknown> = {}, material?: GodotObject | null): GodotObject {
    const mi = this.c.create('MeshInstance3D');
    const prim = this.primitive(shape, options);
    prim.set(
      'material',
      material ??
        this.material({
          color: (options.color as GodotColor) ?? null,
          metallic: (options.metallic as number) ?? null,
          roughness: (options.roughness as number) ?? null,
          emission: (options.emission as GodotColor) ?? null,
          emissionEnergy: (options.emissionEnergy as number) ?? null,
          transparency: options.transparency === true,
        }),
    );
    mi.set('mesh', prim);
    this.setTransform(mi, { position: options.position, rotation: options.rotation, scale: options.scale, visible: options.visible as boolean | null });
    return mi;
  }

  camera(opts: { fov?: number | null; current?: boolean; position?: unknown; rotation?: unknown } = {}): GodotObject {
    const cam = this.c.create('Camera3D');
    if (opts.fov != null) cam.set('fov', new GFloat(opts.fov));
    if (opts.current !== false) cam.set('current', true);
    this.setTransform(cam, { position: opts.position, rotation: opts.rotation });
    return cam;
  }

  dirLight(opts: { color?: GodotColor | null; energy?: number; shadow?: boolean; rotation?: unknown; position?: unknown } = {}): GodotObject {
    const l = this.c.create('DirectionalLight3D');
    l.set('light_color', opts.color ?? new GodotColor(1, 0.98, 0.92, 1));
    l.set('light_energy', new GFloat(opts.energy ?? 1));
    if (opts.shadow) l.set('shadow_enabled', true);
    this.setTransform(l, { position: opts.position, rotation: opts.rotation });
    return l;
  }

  omniLight(opts: { color?: GodotColor | null; energy?: number; range?: number | null; position?: unknown } = {}): GodotObject {
    const l = this.c.create('OmniLight3D');
    l.set('light_color', opts.color ?? new GodotColor(1, 1, 1, 1));
    l.set('light_energy', new GFloat(opts.energy ?? 1));
    if (opts.range != null) l.set('omni_range', new GFloat(opts.range));
    this.setTransform(l, { position: opts.position });
    return l;
  }

  spotLight(opts: { color?: GodotColor | null; energy?: number; range?: number | null; angle?: number | null; position?: unknown; rotation?: unknown } = {}): GodotObject {
    const l = this.c.create('SpotLight3D');
    l.set('light_color', opts.color ?? new GodotColor(1, 1, 1, 1));
    l.set('light_energy', new GFloat(opts.energy ?? 1));
    if (opts.range != null) l.set('spot_range', new GFloat(opts.range));
    if (opts.angle != null) l.set('spot_angle', new GFloat(opts.angle));
    this.setTransform(l, { position: opts.position, rotation: opts.rotation });
    return l;
  }

  environment(opts: { bg?: GodotColor | null; ambient?: GodotColor | null; ambientEnergy?: number } = {}): GodotObject {
    const we = this.c.create('WorldEnvironment');
    const env = this.c.create('Environment');
    env.set('background_mode', new GInt(1));
    env.set('background_color', opts.bg ?? new GodotColor(0.05, 0.06, 0.09, 1));
    env.set('ambient_light_source', new GInt(3));
    env.set('ambient_light_color', opts.ambient ?? new GodotColor(0.5, 0.55, 0.7, 1));
    env.set('ambient_light_energy', new GFloat(opts.ambientEnergy ?? 0.6));
    we.set('environment', env);
    return we;
  }

  async instanceScene(path: string): Promise<GodotObject | null> {
    const packed = this.c.load(path);
    const instance = await packed.call('instantiate');
    return instance instanceof GodotRef ? new GodotObject(this.c, instance.id) : null;
  }

  setTransform(node: GodotObject, opts: { position?: unknown; rotation?: unknown; scale?: unknown; visible?: boolean | null }): void {
    if (opts.position != null) node.set('position', Godot3D.vec3(opts.position, 0, 0, 0));
    if (opts.rotation != null) node.set('rotation_degrees', Godot3D.vec3(opts.rotation, 0, 0, 0));
    if (opts.scale != null) node.set('scale', Godot3D.vec3(opts.scale, 1, 1, 1));
    if (opts.visible != null) node.set('visible', opts.visible);
  }

  static vec3(v: unknown, dx: number, dy: number, dz: number): Vector3 {
    if (v instanceof Vector3) return v;
    if (typeof v === 'number') return new Vector3(v, v, v);
    if (Array.isArray(v) && v.length >= 3) return new Vector3(Number(v[0]), Number(v[1]), Number(v[2]));
    return new Vector3(dx, dy, dz);
  }
}
