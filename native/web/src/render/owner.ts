/**
 * The render owner: one per mounted surface. It owns the render tree's root,
 * schedules frames, drives tickers (animations), runs layout, and hands the
 * compositor's view operations to the platform.
 */
import type { Platform } from '../platform/platform.js';
import { stableKey } from '../util/json.js';
import { Compositor } from './compositor.js';
import { INF, tight, type Constraints, type RenderObject } from './object.js';
import type { TextMetrics, TextSpec, ViewEvent, ViewOp } from './view.js';

export interface Ticker {
  /** Advance to [nowMs]; return false once finished (it is then removed). */
  tick(nowMs: number): boolean;
}

/** Callbacks from the render tree back into the session. */
export interface OwnerHooks {
  /** A gesture/control event for the Elpian element [elementId]. */
  onElementEvent?(elementId: string, event: ViewEvent, ro: RenderObject): void;
  /** Navigation requested by a link (`a`, `NextjsLink`). */
  onNavigate?(href: string, replace: boolean): void;
  /** A tap on a clickable Scene3D surface. */
  onSceneTap?(props: Record<string, any>): void;
  /** A native form-ish submit (NextjsForm). */
  onFormSubmit?(action: string, values: Record<string, any>): Promise<string | null>;
  /** Called after each committed frame. */
  onFrameCommitted?(ops: number): void;
  log?(message: string): void;
}

export class RenderOwner {
  root: RenderObject | null = null;
  readonly compositor: Compositor;
  private tickers = new Set<Ticker>();
  private frameHandle: number | null = null;
  private dirtyPaint = new Set<RenderObject>();
  private needsFrame = false;
  private disposed = false;
  private textCache = new Map<string, TextMetrics>();
  private nextViewId = 1;
  /** When set, the root lays out with unbounded height (document mode measures content). */
  rootConstraints: Constraints | null = null;
  /** Monotonic frame clock (ms) as of the last tick. */
  frameTime = 0;
  /** Accessibility text scale. */
  textScale = 1;

  constructor(
    readonly surface: string,
    readonly platform: Platform,
    readonly hooks: OwnerHooks = {},
  ) {
    this.compositor = new Compositor(this);
  }

  allocateViewId(): number {
    return this.nextViewId++;
  }

  // ---------------------------------------------------------------------------
  // Scheduling
  // ---------------------------------------------------------------------------

  requestVisualUpdate(): void {
    if (this.disposed) return;
    this.needsFrame = true;
    if (this.frameHandle != null) return;
    this.frameHandle = this.platform.requestFrame((t) => {
      this.frameHandle = null;
      this.flush(t);
    });
  }

  markPaintDirty(ro: RenderObject): void {
    this.dirtyPaint.add(ro);
    this.requestVisualUpdate();
  }

  addTicker(ticker: Ticker): void {
    this.tickers.add(ticker);
    this.requestVisualUpdate();
  }

  removeTicker(ticker: Ticker): void {
    this.tickers.delete(ticker);
  }

  get hasActiveTickers(): boolean {
    return this.tickers.size > 0;
  }

  /** Run a frame now: tick animations, lay out, composite and commit. */
  flush(timeMs: number = this.platform.now()): ViewOp[] {
    if (this.disposed) return [];
    this.frameTime = timeMs;
    this.needsFrame = false;
    for (const ticker of [...this.tickers]) {
      let alive = false;
      try {
        alive = ticker.tick(timeMs);
      } catch (e) {
        this.platform.log('error', `Elpian animation tick failed: ${e}`);
      }
      if (!alive) this.tickers.delete(ticker);
    }
    const root = this.root;
    let ops: ViewOp[] = [];
    if (root) {
      const vp = this.platform.viewport(this.surface);
      const constraints = this.rootConstraints ?? tight(vp.width, vp.height);
      root.layout(constraints);
      this.updateHeroes(root);
      ops = this.compositor.composite(root);
    } else {
      ops = this.compositor.clear();
    }
    this.dirtyPaint.clear();
    if (ops.length) this.platform.commit(this.surface, ops);
    this.hooks.onFrameCommitted?.(ops.length);
    if (this.tickers.size > 0 || this.needsFrame) this.requestVisualUpdate();
    return ops;
  }

  // ---------------------------------------------------------------------------
  // Hero flights
  // ---------------------------------------------------------------------------

  private heroes = new Map<string, { ro: RenderObject; rect: { x: number; y: number; width: number; height: number } }>();

  /** A hero whose tag now belongs to a different object flies from the old rect. */
  private updateHeroes(root: RenderObject): void {
    const next = new Map<string, { ro: RenderObject; rect: { x: number; y: number; width: number; height: number } }>();
    root.visit((ro) => {
      if (ro.type !== 'hero' || ro.props.tag == null) return;
      next.set(String(ro.props.tag), { ro, rect: this.compositor.globalFrame(ro) });
    });
    for (const [tag, entry] of next) {
      const prev = this.heroes.get(tag);
      if (prev && prev.ro !== entry.ro && typeof (entry.ro as any).flyFrom === 'function') {
        (entry.ro as any).flyFrom(prev.rect, this);
      }
    }
    if (next.size || this.heroes.size) this.heroes = next;
  }

  // ---------------------------------------------------------------------------
  // Measurement
  // ---------------------------------------------------------------------------

  measureText(spec: TextSpec, maxWidth: number): TextMetrics {
    const width = Number.isFinite(maxWidth) ? Math.max(0, Math.round(maxWidth * 100) / 100) : INF;
    const key = width + '|' + stableKey(spec);
    const hit = this.textCache.get(key);
    if (hit) return hit;
    const metrics = this.platform.measureText(spec, width);
    if (this.textCache.size > 4000) this.textCache.clear();
    this.textCache.set(key, metrics);
    return metrics;
  }

  /** Fonts or the viewport changed: everything must be re-measured. */
  invalidateMeasurements(): void {
    this.textCache.clear();
    this.root?.visit((ro) => {
      ro.needsLayout = true;
    });
    this.requestVisualUpdate();
  }

  // ---------------------------------------------------------------------------
  // Images
  // ---------------------------------------------------------------------------

  private imageSizes = new Map<string, { width: number; height: number } | 'pending' | 'error'>();

  /** Natural size of [src], or null while unknown (a load is requested). */
  imageSize(src: string): { width: number; height: number } | null {
    const known = this.imageSizes.get(src);
    if (known && known !== 'pending' && known !== 'error') return known;
    if (known === undefined) {
      const direct = this.platform.imageSize?.(src) ?? null;
      if (direct) {
        this.imageSizes.set(src, direct);
        return direct;
      }
      this.imageSizes.set(src, 'pending');
      this.platform.preloadImage?.(src);
    }
    return null;
  }

  /** The platform finished decoding [src]; images showing it re-lay out. */
  imageLoaded(src: string, width: number, height: number): void {
    if (width > 0 && height > 0) this.imageSizes.set(src, { width, height });
    else this.imageSizes.set(src, 'error');
    this.root?.visit((ro) => {
      if (ro.type === 'image' && ro.props.src === src) ro.markNeedsLayout();
    });
  }

  // ---------------------------------------------------------------------------
  // Events
  // ---------------------------------------------------------------------------

  /** Route a platform event to the render object owning [event.id]. */
  dispatchViewEvent(event: ViewEvent): void {
    const ro = this.compositor.objectFor(event.id);
    if (!ro) return;
    ro.handleViewEvent(event);
  }

  dispose(): void {
    if (this.disposed) return;
    if (this.frameHandle != null) this.platform.cancelFrame(this.frameHandle);
    this.frameHandle = null;
    this.tickers.clear();
    const ops = this.compositor.clear();
    if (ops.length) this.platform.commit(this.surface, ops);
    this.root?.detach();
    this.root = null;
    this.disposed = true;
  }

  get isDisposed(): boolean {
    return this.disposed;
  }
}
