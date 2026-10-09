/**
 * The declarative scene DSL and the scene controller — ports of
 * `scene_dsl.dart` and `GodotSceneController` (scene3d_widget.dart).
 *
 * ```json
 * { "environment": { "bg": "#0d1117", "ambient": "#8894b0" },
 *   "camera": { "position": [0, 3, 8], "rotation": [-18, 0, 0], "fov": 55 },
 *   "lights": [ { "type": "directional", "energy": 1.3, "shadow": true, "rotation": [-50, -30, 0] } ],
 *   "nodes":  [ { "type": "mesh", "shape": "torus", "id": "ring", "color": "#6699ff",
 *                 "position": [0, 1, 0], "children": [ … ] } ] }
 * ```
 */
import { GodotController, GodotObject, type GodotBinding } from './controller.js';
import { GodotColor } from './values.js';

export class GodotScene {
  constructor(
    readonly controller: GodotController,
    readonly nodesById: Map<string, GodotObject>,
    readonly roots: GodotObject[],
  ) {}
  byId(id: string): GodotObject | undefined {
    return this.nodesById.get(id);
  }
  require(id: string): GodotObject {
    const node = this.nodesById.get(id);
    if (!node) throw new Error(`no node with id "${id}" in the scene`);
    return node;
  }
}

/** `#RRGGBB`, `#RRGGBBAA`, `#RGB`, `[r,g,b(,a)]` (0..1) or a GodotColor. */
export function parseGodotColor(value: unknown): GodotColor | null {
  if (value == null) return null;
  if (value instanceof GodotColor) return value;
  if (Array.isArray(value) && value.length >= 3) {
    const at = (i: number, f: number) => (typeof value[i] === 'number' ? (value[i] as number) : f);
    return new GodotColor(at(0, 0), at(1, 0), at(2, 0), at(3, 1));
  }
  if (typeof value === 'string' && value.startsWith('#')) {
    let hex = value.substring(1);
    if (hex.length === 3) hex = hex.split('').map((c) => c + c).join('');
    if (hex.length !== 6 && hex.length !== 8) return null;
    const rgb = parseInt(hex.substring(0, 6), 16);
    if (!Number.isFinite(rgb)) return null;
    let alpha = 1;
    if (hex.length === 8) {
      const a = parseInt(hex.substring(6, 8), 16);
      if (Number.isFinite(a)) alpha = a / 255;
    }
    return GodotColor.hex(rgb, alpha);
  }
  return null;
}

function looksLikeColor(v: string): boolean {
  return v.startsWith('#') && (v.length === 7 || v.length === 9 || v.length === 4);
}

export class SceneDsl {
  constructor(readonly controller: GodotController) {}

  build(json: Record<string, unknown>): GodotScene {
    const byId = new Map<string, GodotObject>();
    const roots: GodotObject[] = [];
    const c = this.controller;
    c.beginBatch();
    try {
      const env = json.environment;
      if (env && typeof env === 'object') {
        const node = this.environment(env as Record<string, unknown>);
        c.mount(node);
        roots.push(node);
      }
      const camera = json.camera;
      if (camera && typeof camera === 'object') {
        const node = this.camera(camera as Record<string, unknown>);
        c.mount(node);
        roots.push(node);
        this.register(byId, camera as Record<string, unknown>, node);
      }
      const lights = json.lights;
      if (Array.isArray(lights)) {
        for (const light of lights) {
          if (!light || typeof light !== 'object') continue;
          const node = this.light(light as Record<string, unknown>);
          c.mount(node);
          roots.push(node);
          this.register(byId, light as Record<string, unknown>, node);
        }
      }
      const nodes = json.nodes;
      if (Array.isArray(nodes)) {
        for (const entry of nodes) {
          if (!entry || typeof entry !== 'object') continue;
          const node = this.node(entry as Record<string, unknown>, byId);
          if (!node) continue;
          c.mount(node);
          roots.push(node);
        }
      }
    } finally {
      c.endBatch();
    }
    return new GodotScene(c, byId, roots);
  }

  private register(byId: Map<string, GodotObject>, spec: Record<string, unknown>, node: GodotObject): void {
    const id = spec.id;
    if (typeof id === 'string' && id !== '') byId.set(id, node);
  }

  private environment(spec: Record<string, unknown>): GodotObject {
    return this.controller.g3.environment({
      bg: parseGodotColor(spec.bg),
      ambient: parseGodotColor(spec.ambient),
      ambientEnergy: typeof spec.ambientEnergy === 'number' ? spec.ambientEnergy : 0.6,
    });
  }

  private camera(spec: Record<string, unknown>): GodotObject {
    return this.controller.g3.camera({
      fov: typeof spec.fov === 'number' ? spec.fov : null,
      current: spec.current !== false,
      position: spec.position,
      rotation: spec.rotation,
    });
  }

  private light(spec: Record<string, unknown>): GodotObject {
    const g3 = this.controller.g3;
    const num = (v: unknown, f: number) => (typeof v === 'number' ? v : f);
    switch (spec.type) {
      case 'omni':
      case 'point':
        return g3.omniLight({ color: parseGodotColor(spec.color), energy: num(spec.energy, 1), range: typeof spec.range === 'number' ? spec.range : null, position: spec.position });
      case 'spot':
        return g3.spotLight({
          color: parseGodotColor(spec.color),
          energy: num(spec.energy, 1),
          range: typeof spec.range === 'number' ? spec.range : null,
          angle: typeof spec.angle === 'number' ? spec.angle : null,
          position: spec.position,
          rotation: spec.rotation,
        });
      default:
        return g3.dirLight({ color: parseGodotColor(spec.color), energy: num(spec.energy, 1), shadow: spec.shadow === true, position: spec.position, rotation: spec.rotation });
    }
  }

  private node(spec: Record<string, unknown>, byId: Map<string, GodotObject>): GodotObject | null {
    const type = typeof spec.type === 'string' ? spec.type : 'node';
    const c = this.controller;
    let node: GodotObject;
    switch (type) {
      case 'mesh': {
        const options: Record<string, unknown> = { ...spec };
        if (spec.color != null) options.color = parseGodotColor(spec.color);
        if (spec.emission != null) options.emission = parseGodotColor(spec.emission);
        node = c.g3.mesh(typeof spec.shape === 'string' ? spec.shape : 'box', options);
        break;
      }
      case 'node':
      case 'group':
        node = c.g3.node({ position: spec.position, rotation: spec.rotation, scale: spec.scale, visible: typeof spec.visible === 'boolean' ? spec.visible : null });
        break;
      case 'camera':
        node = this.camera(spec);
        break;
      case 'light':
        node = this.light(spec);
        break;
      default:
        // Any other value is a raw ClassDB class name.
        node = c.create(type);
        c.g3.setTransform(node, { position: spec.position, rotation: spec.rotation, scale: spec.scale, visible: typeof spec.visible === 'boolean' ? spec.visible : null });
    }
    const props = spec.props;
    if (props && typeof props === 'object') {
      const coerced: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(props as Record<string, unknown>)) {
        coerced[k] = typeof v === 'string' && looksLikeColor(v) ? parseGodotColor(v) ?? v : v;
      }
      node.setAll(coerced);
    }
    this.register(byId, spec, node);
    const children = spec.children;
    if (Array.isArray(children)) {
      for (const child of children) {
        if (!child || typeof child !== 'object') continue;
        const built = this.node(child as Record<string, unknown>, byId);
        if (built) node.addChild(built);
      }
    }
    return node;
  }
}

/** `GodotSceneController`: owns the engine controller and the built scene across renders. */
export class GodotSceneController {
  readonly godot: GodotController;
  private current: GodotScene | null = null;
  private disposed = false;
  private listeners = new Set<() => void>();

  constructor(binding: GodotBinding) {
    this.godot = new GodotController(binding);
  }

  get scene(): GodotScene | null {
    return this.current;
  }

  get isLive(): boolean {
    return this.godot.isLive;
  }

  node(id: string): GodotObject | undefined {
    return this.current?.byId(id);
  }

  adopt(scene: GodotScene): void {
    this.current = scene;
    if (!this.disposed) for (const l of [...this.listeners]) l();
  }

  replaceScene(json: Record<string, unknown>): GodotScene {
    for (const root of this.current?.roots ?? []) root.queueFree();
    const built = new SceneDsl(this.godot).build(json);
    this.adopt(built);
    return built;
  }

  addListener(fn: () => void): void {
    this.listeners.add(fn);
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.godot.dispose();
    this.listeners.clear();
  }
}
