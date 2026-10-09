/**
 * A surface: one engine rendering into one platform container.
 *
 * It is the native counterpart of a mounted Flutter widget subtree. It
 * re-renders Elpian JSON through the engine, reconciles the widget
 * descriptors into the render tree, and lets the render owner lay out,
 * animate and commit view operations. Sessions (mini apps, streams, Next.js
 * pages) put content on a surface; the platform delivers viewport changes,
 * image loads and view events back to it.
 */
import { updateCssEnvironment } from '../css/environment.js';
import { ElpianEngine, ElpianServices, type EngineHost } from '../engine/engine.js';
import { platform } from '../platform/platform.js';
import { w, type RenderObject, type W } from '../render/object.js';
import { RenderOwner } from '../render/owner.js';
import { reconcileRoot } from '../render/reconciler.js';
import type { ViewEvent } from '../render/view.js';
import { M3 } from '../css/color.js';
import type { JsonMap } from '../util/json.js';

export interface SurfaceOptions {
  /** Share services (stylesheets, events, canvas contexts) with another engine. */
  services?: ElpianServices;
  /** An existing engine (e.g. one with custom widgets registered). */
  engine?: ElpianEngine;
  /** Render the content as a scrolling document (`wrapAsDocument`). */
  document?: boolean;
  /** Hooks the content can call back into (navigation, forms…). */
  host?: Partial<EngineHost>;
}

const surfaces = new Map<string, ElpianSurface>();

/** The surface registered under [id] (platform events are routed by it). */
export function surfaceById(id: string): ElpianSurface | undefined {
  return surfaces.get(id);
}

export class ElpianSurface {
  readonly engine: ElpianEngine;
  readonly owner: RenderOwner;
  private content: JsonMap | null = null;
  private overlay: W | null = null;
  private renderScheduled = false;
  private disposed = false;
  private readonly document: boolean;
  private readonly hostHooks: Partial<EngineHost>;
  private lastViewport = '';
  /** Wraps the lowered content each render (e.g. the stream's AnimatedSwitcher). */
  decorate: ((content: W) => W) | null = null;

  constructor(
    readonly id: string,
    options: SurfaceOptions = {},
  ) {
    this.document = options.document ?? false;
    this.hostHooks = options.host ?? {};
    const host: EngineHost = {
      ...this.hostHooks,
      invalidate: () => {
        this.hostHooks.invalidate?.();
        this.scheduleRender();
      },
      focus: (htmlId) => {
        if (this.hostHooks.focus) this.hostHooks.focus(htmlId);
        else this.focus(htmlId);
      },
      hitTestDragTarget: (x, y) => this.hostHooks.hitTestDragTarget?.(x, y) ?? this.hitTestDragTarget(x, y),
      log: (level, message) => (this.hostHooks.log ? this.hostHooks.log(level, message) : platform().log(level as any, message)),
    };
    if (options.engine) {
      this.engine = options.engine;
      this.engine.host = { ...this.engine.host, ...host };
    } else {
      this.engine = new ElpianEngine(options.services ?? new ElpianServices(id), host);
    }
    this.owner = new RenderOwner(id, platform(), {});
    surfaces.set(id, this);
    this.syncEnvironment();
  }

  get isDisposed(): boolean {
    return this.disposed;
  }

  get currentContent(): JsonMap | null {
    return this.content;
  }

  /** Replace the rendered Elpian JSON (null clears the surface). */
  setContent(json: JsonMap | null): void {
    this.content = json;
    this.overlay = null;
    this.scheduleRender();
  }

  /** Show a lowered widget instead of content (loading / error states). */
  setOverlay(widget: W | null): void {
    this.overlay = widget;
    this.scheduleRender();
  }

  /** Re-render on the next microtask (coalesces bursts of state changes). */
  scheduleRender(): void {
    if (this.renderScheduled || this.disposed) return;
    this.renderScheduled = true;
    Promise.resolve().then(() => {
      this.renderScheduled = false;
      this.renderNow();
    });
  }

  /** Lower and reconcile now; the owner commits on the next frame. */
  renderNow(): void {
    if (this.disposed) return;
    this.syncEnvironment();
    let widget: W | null = this.overlay;
    if (!widget && this.content) {
      try {
        const rendered = this.engine.renderFromJson(this.content);
        widget = this.document ? this.engine.wrapAsDocument(rendered, this.content) : rendered;
        if (this.decorate) widget = this.decorate(widget);
      } catch (e) {
        platform().log('error', `Elpian render error: ${e}`);
        widget = messageBox(`Render Error: ${e}`, 0xffff9800);
      }
    }
    if (!widget) {
      if (this.owner.root) {
        this.owner.root.detach();
        this.owner.root = null;
      }
      this.owner.requestVisualUpdate();
      return;
    }
    this.owner.root = reconcileRoot(this.owner.root, widget, this.owner);
    this.owner.requestVisualUpdate();
  }

  /** The platform reports a new size, safe area, text scale or theme. */
  viewportChanged(): void {
    if (this.syncEnvironment()) this.renderNow();
    else this.owner.requestVisualUpdate();
  }

  private syncEnvironment(): boolean {
    const vp = platform().viewport(this.id);
    const key = JSON.stringify([vp.width, vp.height, vp.safeArea, vp.devicePixelRatio, vp.textScale, vp.darkMode]);
    if (key === this.lastViewport) return false;
    this.lastViewport = key;
    updateCssEnvironment({
      viewportWidth: vp.width,
      viewportHeight: vp.height,
      safeArea: vp.safeArea,
      devicePixelRatio: vp.devicePixelRatio,
    });
    this.engine.services.stylesheets.darkMode = vp.darkMode;
    if (this.owner.textScale !== vp.textScale) {
      this.owner.textScale = vp.textScale;
      this.owner.invalidateMeasurements();
    }
    return true;
  }

  /** A native view reported an event (tap, change, scroll, load…). */
  dispatchViewEvent(event: ViewEvent): void {
    if (this.disposed) return;
    this.owner.dispatchViewEvent(event);
  }

  /** An image finished loading (or failed with 0×0). */
  imageLoaded(src: string, width: number, height: number): void {
    this.owner.imageLoaded(src, width, height);
  }

  /** Fonts changed or text metrics are otherwise stale. */
  invalidateText(): void {
    this.owner.invalidateMeasurements();
  }

  /** Focus the control rendered for the element with HTML id [htmlId] (`<label for>`). */
  focus(htmlId: string): boolean {
    let target: RenderObject | null = null;
    this.owner.root?.visit((ro) => {
      if (!target && ro.props.focusId === htmlId && ro.viewId != null) target = ro;
    });
    const found = target as RenderObject | null;
    if (!found || found.viewId == null) return false;
    this.owner.compositor.command(found.viewId, 'focus');
    return true;
  }

  /** The DragTarget element under a point in surface coordinates. */
  hitTestDragTarget(x: number, y: number): string | null {
    let hit: string | null = null;
    this.owner.root?.visit((ro) => {
      const id = ro.props.dragTargetId;
      if (!id) return;
      const f = this.owner.compositor.globalFrame(ro);
      if (x >= f.x && y >= f.y && x <= f.x + f.width && y <= f.y + f.height) hit = id;
    });
    return hit;
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    surfaces.delete(this.id);
    this.owner.dispose();
    this.engine.dispose();
  }
}

/** The red/orange diagnostic box Flutter shows for VM and render errors. */
export function messageBox(message: string, color: number): W {
  const tint = ((0x1a << 24) | (color & 0xffffff)) >>> 0;
  // Container(padding: 16, color: color @ 10%, child: Text(message, color)).
  return w('decorated', { decoration: { color: tint } }, w('padding', { padding: { top: 16, right: 16, bottom: 16, left: 16 } }, w('text', { text: message, style: { color } })));
}

/** `Center(CircularProgressIndicator())`. */
export function loadingIndicator(): W {
  return w(
    'align',
    { alignment: { x: 0, y: 0 } },
    w('control', { kind: 'progress', view: { variant: 'circular', value: null, strokeWidth: 4, colors: { indicator: M3.primary, track: null } } }),
  );
}
