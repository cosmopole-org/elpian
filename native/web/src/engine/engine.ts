/**
 * ElpianEngine — the TypeScript twin of `elpian_engine.dart` + `ElpianServices`.
 *
 * `render(node)` resolves each element's cascaded style, honours
 * `display: none`, lowers the node through its registered widget builder,
 * and wraps event-bearing elements in a gesture region registered with the
 * event dispatcher — exactly the steps of the Flutter `_render`. The result is
 * a widget-descriptor tree the render owner reconciles and lays out.
 */
import { CanvasContextStore, CanvasExecutor } from '../canvas/store.js';
import { CSSParser } from '../css/parser.js';
import type { CSSStyle } from '../css/style.js';
import { StylesheetManager, type ElementFacts, type StyleMap } from '../css/stylesheet.js';
import { EventDispatcher, makeEvent, type ElpianEvent, type ElpianEventTypeName } from '../events/events.js';
import { MockGodotBinding, PlatformGodotBinding, type GodotBinding } from '../godot/controller.js';
import { GodotSceneController, SceneDsl } from '../godot/scene.js';
import { ElpianDOM } from '../host/dom.js';
import { classesOf, nodeFromJson, type ElpianNode } from '../model/node.js';
import { w, type W } from '../render/object.js';
import type { GestureKind, ViewEvent } from '../render/view.js';
import { isMap, stableKey, type JsonMap } from '../util/json.js';
import type { BuildContext, WidgetBuilder } from '../widgets/context.js';
import { registerDefaultWidgets } from '../widgets/registry.js';

export class ElpianServices {
  readonly events = new EventDispatcher();
  readonly stylesheets = new StylesheetManager();
  readonly canvasContexts = new CanvasContextStore();
  readonly canvas = new CanvasExecutor();
  readonly dom = new ElpianDOM();
  readonly registry = new Map<string, WidgetBuilder>();

  constructor(readonly appId: string = 'default') {}

  /** Namespace a guest-chosen id so mini apps never collide (`appId::id`). */
  scopeId(id: string): string {
    return `${this.appId}::${id}`;
  }

  dispose(): void {
    this.events.clear();
    this.events.bus.removeAllEventListeners();
    this.stylesheets.clear();
    this.canvasContexts.clearAll();
    this.canvas.clear();
    this.dom.clear();
  }
}

/** Callbacks from rendered content back into the hosting session. */
export interface EngineHost {
  /** A link (`a href`, `NextjsLink`) was activated. */
  navigate?(href: string, replace: boolean): void;
  /** Open an external URL. */
  openUrl?(url: string): void;
  /** A tap on a clickable Scene3D (ElpianSceneTaps). */
  sceneTap?(props: Record<string, any>): void;
  /** `NextjsForm` submission; resolves to an error message or null. */
  submitForm?(action: string, values: Record<string, any>): Promise<string | null>;
  /** The Godot transport for new Scene3D surfaces. */
  godotBinding?(): GodotBinding | null;
  /** Base URL for relative resource paths (ElpianResources.baseUrl). */
  baseUrl?(): string | null;
  /** The id of the drag target (DragTarget element) under a global point. */
  hitTestDragTarget?(x: number, y: number): string | null;
  /** Request a re-render (element state changed). */
  invalidate?(): void;
  /** Move input focus to the control rendered for the element with HTML id [id]. */
  focus?(id: string): void;
  log?(level: string, message: string): void;
}

interface SceneEntry {
  controller: GodotSceneController;
  sceneKey: string | null;
  attached: boolean;
}

const EVENT_GESTURES: Record<string, GestureKind> = {
  click: 'tap',
  tap: 'tap',
  doubletap: 'doubletap',
  dblclick: 'doubletap',
  longpress: 'longpress',
  contextmenu: 'longpress',
  tapdown: 'tapdown',
  tapup: 'tapup',
  tapcancel: 'tapcancel',
  drag: 'pan',
  dragstart: 'pan',
  dragend: 'pan',
  swipeleft: 'swipe',
  swiperight: 'swipe',
  swipeup: 'swipe',
  swipedown: 'swipe',
  pointerdown: 'pointer',
  pointerup: 'pointer',
  pointermove: 'pointer',
  pointercancel: 'pointer',
  pointerenter: 'hover',
  pointerexit: 'hover',
  pointerhover: 'hover',
  mouseenter: 'hover',
  mouseleave: 'hover',
  keydown: 'key',
  keyup: 'key',
  keypress: 'key',
  focus: 'focus',
  blur: 'focus',
  scalestart: 'scale',
  scaleupdate: 'scale',
  scaleend: 'scale',
  pinchstart: 'scale',
  pinchupdate: 'scale',
  pinchend: 'scale',
  rotatestart: 'scale',
  rotateupdate: 'scale',
  rotateend: 'scale',
  scroll: 'scroll',
};

const EVENT_TYPE_NAMES: Record<string, ElpianEventTypeName> = {
  click: 'click',
  tap: 'tap',
  doubletap: 'doubleClick',
  longpress: 'longPress',
  tapdown: 'tapDown',
  tapup: 'tapUp',
  tapcancel: 'tapCancel',
  pointerdown: 'pointerDown',
  pointerup: 'pointerUp',
  pointermove: 'pointerMove',
  pointerenter: 'pointerEnter',
  pointerexit: 'pointerExit',
  pointerhover: 'pointerHover',
  pointercancel: 'pointerCancel',
  dragstart: 'dragStart',
  drag: 'drag',
  dragend: 'dragEnd',
  dragenter: 'dragEnter',
  dragleave: 'dragLeave',
  dragover: 'dragOver',
  drop: 'drop',
  focus: 'focus',
  blur: 'blur',
  input: 'input',
  change: 'change',
  submit: 'submit',
  keydown: 'keyDown',
  keyup: 'keyUp',
  keypress: 'keyPress',
  scroll: 'scroll',
  swipeleft: 'swipeLeft',
  swiperight: 'swipeRight',
  swipeup: 'swipeUp',
  swipedown: 'swipeDown',
  scalestart: 'scaleStart',
  scaleupdate: 'scaleUpdate',
  scaleend: 'scaleEnd',
  pinchstart: 'pinchStart',
  pinchupdate: 'pinchUpdate',
  pinchend: 'pinchEnd',
  rotatestart: 'rotateStart',
  rotateupdate: 'rotateUpdate',
  rotateend: 'rotateEnd',
  load: 'load',
  select: 'select',
  reset: 'reset',
  resize: 'resize',
};

export function eventTypeFor(name: string): ElpianEventTypeName {
  return EVENT_TYPE_NAMES[name] ?? 'custom';
}

export class ElpianEngine {
  readonly services: ElpianServices;
  host: EngineHost;
  /** Per-element state that survives re-renders (details open, select value …). */
  private state = new Map<string, any>();
  private seen = new Set<string>();
  private scenes = new Map<string, SceneEntry>();
  /** Nodes registered with the dispatcher this render. */
  private registered = new Set<string>();
  private previousRegistered = new Set<string>();

  constructor(services?: ElpianServices, host: EngineHost = {}) {
    this.services = services ?? new ElpianServices();
    this.host = host;
    registerDefaultWidgets(this);
  }

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  registerWidget(type: string, builder: WidgetBuilder): void {
    this.services.registry.set(type, builder);
  }

  registerWidgets(builders: Record<string, WidgetBuilder>): void {
    for (const [k, v] of Object.entries(builders)) this.services.registry.set(k, v);
  }

  loadStylesheet(sheet: StyleMap | string): void {
    this.services.stylesheets.load(sheet);
  }

  clearStylesheets(): void {
    this.services.stylesheets.clear();
  }

  resolveUrl(src: string): string {
    if (!src || /^(https?:|data:|blob:|asset:|file:|content:)/i.test(src)) return src;
    const base = this.host.baseUrl?.() ?? null;
    if (!base) return src;
    if (src.startsWith('//')) return (base.startsWith('https') ? 'https:' : 'http:') + src;
    if (src.startsWith('/')) {
      const origin = /^[a-z]+:\/\/[^/]+/i.exec(base)?.[0] ?? base;
      return origin + src;
    }
    return base.replace(/\/+$/, '') + '/' + src;
  }

  // ---------------------------------------------------------------------------
  // Element state
  // ---------------------------------------------------------------------------

  /** State for [elementId], created by [init] on first use; kept while the element renders. */
  stateFor<T>(elementId: string, init: () => T): T {
    this.seen.add(elementId);
    if (!this.state.has(elementId)) this.state.set(elementId, init());
    return this.state.get(elementId) as T;
  }

  setState(elementId: string, patch: Record<string, any>): void {
    const current = this.state.get(elementId) ?? {};
    this.state.set(elementId, { ...current, ...patch });
    this.host.invalidate?.();
  }

  // ---------------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------------

  renderFromJson(json: JsonMap): W {
    return this.render(nodeFromJson(json));
  }

  render(root: ElpianNode): W {
    this.seen = new Set();
    this.formFields = new Map();
    this.imageMaps = collectMaps(root);
    this.datalists = collectDatalists(root);
    this.previousRegistered = this.registered;
    this.registered = new Set();
    const ctx: BuildContext = { engine: this, parentId: null, ancestors: [], path: 'r', elementId: 'r', formId: null };
    const result = this.renderNode(root, ctx, 0);
    this.collectGarbage();
    return result;
  }

  private collectGarbage(): void {
    for (const id of [...this.state.keys()]) if (!this.seen.has(id)) this.state.delete(id);
    for (const [id, entry] of [...this.scenes]) {
      if (!this.seen.has(id)) {
        entry.controller.dispose();
        this.scenes.delete(id);
      }
    }
    for (const id of this.previousRegistered) if (!this.registered.has(id)) this.services.events.unregisterNode(id);
  }

  /** Resolve the cascaded style of [node] (stylesheet + `@media` + inline + `!important`). */
  resolveStyle(node: ElpianNode, ancestors: ElementFacts[]): CSSStyle | null {
    const inline = isMap(node.props.style) ? (node.props.style as StyleMap) : null;
    const sheets = this.services.stylesheets;
    if (sheets.hasRules) {
      const computed = sheets.getComputedStyleMap(this.factsOf(node), { ancestors, inlineStyles: inline });
      return Object.keys(computed).length ? CSSParser.parse(computed) : null;
    }
    if (inline) return CSSParser.parse(sheets.substituteVariables(inline));
    return null;
  }

  factsOf(node: ElpianNode): ElementFacts {
    return {
      tagName: node.type,
      id: node.key ?? (typeof node.props.id === 'string' ? node.props.id : null),
      classes: classesOf(node),
      attributes: node.props,
    };
  }

  renderNode(node: ElpianNode, parentCtx: BuildContext, index: number): W {
    const path = `${parentCtx.path}/${index}`;
    const elementId = node.key ?? (typeof node.props.id === 'string' && node.props.id ? `#${node.props.id}` : `${path}:${node.type}`);
    this.seen.add(elementId);

    if (node.type === '#text') {
      return w('text', { text: String(node.props.text ?? '') });
    }

    const builder = this.services.registry.get(node.type);
    if (!builder) {
      this.host.log?.('warn', `Unknown widget type "${node.type}"`);
      return w('decorated', { decoration: { color: 0x33f44336 } }, w('padding', { padding: { top: 8, right: 8, bottom: 8, left: 8 } }, w('text', { text: `Unknown widget: ${node.type}` })));
    }

    const style = this.resolveStyle(node, parentCtx.ancestors) ?? node.style;
    const styled: ElpianNode = style !== node.style ? { ...node, style } : node;

    if (style?.display === 'none') return w('constrained', { width: 0, height: 0 });

    const hasEvents = !!node.events && Object.keys(node.events).length > 0;
    if (hasEvents || node.key != null) {
      this.services.events.registerNode(elementId, styled, parentCtx.parentId);
      this.registered.add(elementId);
    }

    const facts = this.factsOf(node);
    const ctx: BuildContext = {
      engine: this,
      parentId: hasEvents || node.key != null ? elementId : parentCtx.parentId,
      ancestors: [facts, ...parentCtx.ancestors],
      path,
      elementId,
      formId: node.type === 'form' || node.type === 'NextjsForm' ? elementId : parentCtx.formId,
    };

    // Resolve children's styles up-front so layout builders (HtmlDiv) can read them.
    const childNodes = styled.children.map((child) => {
      if (child.type === '#text') return child;
      const childStyle = this.resolveStyle(child, ctx.ancestors) ?? child.style;
      return childStyle !== child.style ? { ...child, style: childStyle } : child;
    });
    const withChildren: ElpianNode = { ...styled, children: childNodes };
    const children = childNodes.map((child, i) => this.renderNode(child, ctx, i));

    let result = builder(withChildren, children, { ...ctx, parentId: ctx.parentId, elementId });

    if (hasEvents) {
      result = this.wrapEvents(withChildren, elementId, result);
    }
    if (node.key != null && result.k == null) result = { ...result, k: node.key };
    return result;
  }

  /** `EventEnabledWidget`: a gesture region recognising what the node listens for. */
  wrapEvents(node: ElpianNode, elementId: string, child: W): W {
    const gestures = new Set<GestureKind>();
    for (const name of Object.keys(node.events ?? {})) {
      const g = EVENT_GESTURES[name.toLowerCase()];
      if (g) gestures.add(g);
      if (g === 'key') gestures.add('focus');
    }
    if (gestures.size === 0) return child;
    const listensTap = gestures.has('tap');
    return w(
      'gesture',
      {
        gestures: [...gestures],
        cursor: listensTap ? node.style?.cursor ?? 'pointer' : node.style?.cursor ?? null,
        focusable: gestures.has('key') || gestures.has('focus'),
        onEvent: (event: ViewEvent) => this.handleGesture(elementId, node, event),
      },
      child,
      `ev:${elementId}`,
    );
  }

  /** Translate a platform gesture into Elpian events and dispatch them. */
  handleGesture(elementId: string, node: ElpianNode, event: ViewEvent): void {
    const events = node.events ?? {};
    const has = (name: string) => Object.prototype.hasOwnProperty.call(events, name);
    const pos = event.x != null ? { x: event.x, y: event.y ?? 0 } : undefined;
    const local = event.localX != null ? { x: event.localX, y: event.localY ?? 0 } : pos;
    const dispatch = (type: string, extra: Partial<ElpianEvent> = {}) =>
      this.services.events.dispatchEvent(makeEvent(type, eventTypeFor(type), elementId, extra), elementId);
    switch (event.type) {
      case 'tap':
        if (has('tap')) dispatch('tap', pos ? { position: pos, localPosition: local } : {});
        if (has('click')) dispatch('click', pos ? { position: pos, localPosition: local } : {});
        return;
      case 'doubletap':
        dispatch(has('dblclick') && !has('doubletap') ? 'dblclick' : 'doubletap');
        return;
      case 'longpress':
        dispatch(has('contextmenu') && !has('longpress') ? 'contextmenu' : 'longpress', pos ? { position: pos, localPosition: local } : {});
        return;
      case 'tapdown':
      case 'tapup':
        dispatch(event.type, { position: pos ?? { x: 0, y: 0 }, localPosition: local ?? { x: 0, y: 0 } });
        return;
      case 'tapcancel':
        dispatch('tapcancel');
        return;
      case 'dragstart':
        if (has('dragstart')) dispatch('dragstart', { position: pos ?? { x: 0, y: 0 }, localPosition: local ?? { x: 0, y: 0 } });
        return;
      case 'drag':
        if (has('drag')) dispatch('drag', { position: pos ?? { x: 0, y: 0 }, localPosition: local ?? { x: 0, y: 0 }, delta: { x: event.dx ?? 0, y: event.dy ?? 0 } });
        return;
      case 'dragend':
        if (has('dragend')) dispatch('dragend', { position: { x: 0, y: 0 }, localPosition: { x: 0, y: 0 } });
        return;
      case 'swipe': {
        const dir = event.direction ?? (Math.abs(event.vx ?? 0) > Math.abs(event.vy ?? 0) ? ((event.vx ?? 0) < 0 ? 'left' : 'right') : (event.vy ?? 0) < 0 ? 'up' : 'down');
        const name = `swipe${dir}`;
        if (has(name)) dispatch(name, { velocity: { x: event.vx ?? 0, y: event.vy ?? 0 }, scale: 1, rotation: 0, focalPoint: { x: 0, y: 0 } });
        return;
      }
      case 'pointerdown':
      case 'pointerup':
      case 'pointermove':
      case 'pointercancel':
      case 'pointerenter':
      case 'pointerexit':
      case 'pointerhover': {
        const alias = event.type === 'pointerenter' && !has('pointerenter') && has('mouseenter') ? 'mouseenter' : event.type === 'pointerexit' && !has('pointerexit') && has('mouseleave') ? 'mouseleave' : event.type;
        if (has(alias)) {
          dispatch(alias, {
            position: pos ?? { x: 0, y: 0 },
            localPosition: local ?? { x: 0, y: 0 },
            delta: { x: event.dx ?? 0, y: event.dy ?? 0 },
            buttons: event.buttons ?? 0,
            pressure: event.pressure ?? 1,
            pointerId: event.pointerId ?? 0,
          });
        }
        return;
      }
      case 'keydown':
      case 'keyup':
      case 'keypress':
        if (has(event.type)) {
          dispatch(event.type, {
            key: event.key ?? '',
            keyCode: event.keyCode ?? 0,
            altKey: !!event.altKey,
            ctrlKey: !!event.ctrlKey,
            shiftKey: !!event.shiftKey,
            metaKey: !!event.metaKey,
          });
        }
        return;
      case 'focus':
      case 'blur':
        if (has(event.type)) dispatch(event.type);
        return;
      case 'scalestart':
      case 'scaleupdate':
      case 'scaleend': {
        const suffix = event.type.substring(5);
        const extra = { velocity: { x: event.vx ?? 0, y: event.vy ?? 0 }, scale: event.scale ?? 1, rotation: event.rotation ?? 0, focalPoint: pos ?? { x: 0, y: 0 } };
        for (const prefix of ['scale', 'pinch', 'rotate']) if (has(prefix + suffix)) dispatch(prefix + suffix, extra);
        return;
      }
      case 'scroll':
        if (has('scroll')) dispatch('scroll', { data: { scrollX: event.scrollX ?? 0, scrollY: event.scrollY ?? 0 } });
        return;
      default:
        if (has(event.type)) dispatch(event.type, { value: event.value, data: event.data ?? {} });
    }
  }

  // ---------------------------------------------------------------------------
  // Forms and image maps
  // ---------------------------------------------------------------------------

  private formFields = new Map<string, Map<string, () => any>>();
  /** `<map name>` → its `<area>` nodes, collected before each render. */
  imageMaps = new Map<string, ElpianNode[]>();
  /** `<datalist id>` → its option values (feeds `<input list>` suggestions). */
  datalists = new Map<string, string[]>();

  /** `<label for>`: focus the control of the element with HTML id [id]. */
  focusElement(id: string): void {
    this.host.focus?.(id);
  }

  /** A named form control reports its current value through [read]. */
  registerFormField(formId: string | null, name: string | null | undefined, read: () => any): void {
    if (!formId || !name) return;
    let fields = this.formFields.get(formId);
    if (!fields) this.formFields.set(formId, (fields = new Map()));
    fields.set(name, read);
  }

  formValues(formId: string): Record<string, any> {
    const out: Record<string, any> = {};
    for (const [name, read] of this.formFields.get(formId) ?? []) out[name] = read();
    return out;
  }

  /** Submit [formId]: the form element receives `submit` with its field values. */
  submitForm(formId: string): void {
    const values = this.formValues(formId);
    this.services.events.dispatchEvent(makeEvent('submit', 'submit', formId, { data: { values }, value: values }), formId);
  }

  // ---------------------------------------------------------------------------
  // Drag and drop (Draggable / DragTarget)
  // ---------------------------------------------------------------------------

  private dragTarget: string | null = null;

  private dispatchTo(elementId: string, type: string, data: Record<string, any>): void {
    this.services.events.dispatchEvent(makeEvent(type, eventTypeFor(type), elementId, { data }), elementId);
  }

  /** A Draggable moved: update DragTarget enter / leave / over. */
  dragOver(sourceId: string, e: ViewEvent, data: unknown): void {
    const target = e.x != null ? this.host.hitTestDragTarget?.(e.x, e.y ?? 0) ?? null : null;
    if (target !== this.dragTarget) {
      if (this.dragTarget) this.dispatchTo(this.dragTarget, 'dragleave', { data, source: sourceId });
      if (target) this.dispatchTo(target, 'dragenter', { data, source: sourceId });
      this.dragTarget = target;
    }
    if (target) this.dispatchTo(target, 'dragover', { data, source: sourceId, x: e.x, y: e.y });
    this.dispatchTo(sourceId, 'drag', { x: e.x, y: e.y });
  }

  /** A Draggable was released: the target under the pointer accepts it. */
  dropAt(sourceId: string, e: ViewEvent, data: unknown): void {
    const target = e.x != null ? this.host.hitTestDragTarget?.(e.x, e.y ?? 0) ?? null : null;
    if (target) {
      this.dispatchTo(target, 'drop', { data, source: sourceId });
      this.dispatchTo(target, 'accept', { data, source: sourceId });
    }
    this.dispatchTo(sourceId, 'dragend', { accepted: target != null, target });
    if (this.dragTarget && this.dragTarget !== target) this.dispatchTo(this.dragTarget, 'dragleave', { data, source: sourceId });
    this.dragTarget = null;
  }

  // ---------------------------------------------------------------------------
  // Scene3D
  // ---------------------------------------------------------------------------

  /** The scene controller of a Scene3D element, building / replacing its DSL scene. */
  sceneFor(elementId: string, sceneJson: Record<string, unknown> | null): GodotSceneController {
    this.seen.add(elementId);
    let entry = this.scenes.get(elementId);
    if (!entry) {
      const binding = this.host.godotBinding?.() ?? new MockGodotBinding();
      entry = { controller: new GodotSceneController(binding), sceneKey: null, attached: false };
      this.scenes.set(elementId, entry);
    }
    const key = sceneJson ? stableKey(sceneJson) : null;
    if (sceneJson && key !== entry.sceneKey) {
      if (entry.sceneKey == null) {
        entry.controller.adopt(new SceneDsl(entry.controller.godot).build(sceneJson));
      } else {
        entry.controller.replaceScene(sceneJson);
      }
      entry.sceneKey = key;
    }
    if (!entry.attached) {
      entry.attached = true;
      void entry.controller.godot.attachSurface();
    }
    return entry.controller;
  }

  /** The Scene3D controllers currently alive, by element id. */
  get sceneControllers(): ReadonlyMap<string, SceneEntry> {
    return this.scenes;
  }

  // ---------------------------------------------------------------------------
  // Documents
  // ---------------------------------------------------------------------------

  /**
   * `wrapAsDocument`: a screen root scrolls vertically like `<body>` unless it
   * is a viewport-locked stage (`position: fixed`, `height: 100vh|100%`, or
   * it embeds a Scene3D).
   */
  wrapAsDocument(rendered: W, root: JsonMap | null): W {
    if (!root || this.isViewportLockedRoot(root)) return rendered;
    return w('scroll', { axis: 'vertical', stretchCross: true, fillViewport: true }, rendered);
  }

  private isViewportLockedRoot(root: JsonMap): boolean {
    const props = isMap(root.props) ? root.props : {};
    const className = root.className ?? props.className;
    const classes = typeof className === 'string' ? className.split(' ') : Array.isArray(className) ? className.map(String) : null;
    const inline = root.style ?? props.style;
    const raw = this.services.stylesheets.getComputedStyleMap(
      { tagName: String(root.type ?? 'div'), id: (root.key as string) ?? null, classes, attributes: props },
      { inlineStyles: isMap(inline) ? inline : null },
    );
    if (String(raw.position ?? '') === 'fixed') return true;
    const h = raw.height != null ? String(raw.height).trim() : null;
    if (h && (h.includes('vh') || h === '100%')) return true;
    return containsScene(root, 0);
  }

  dispose(): void {
    for (const entry of this.scenes.values()) entry.controller.dispose();
    this.scenes.clear();
    this.state.clear();
  }
}

function collectMaps(root: ElpianNode): Map<string, ElpianNode[]> {
  const out = new Map<string, ElpianNode[]>();
  const visit = (n: ElpianNode) => {
    if (n.type === 'map' && typeof n.props.name === 'string') {
      const areas: ElpianNode[] = [];
      const collect = (c: ElpianNode) => {
        if (c.type === 'area') areas.push(c);
        c.children.forEach(collect);
      };
      n.children.forEach(collect);
      out.set(n.props.name, areas);
    }
    n.children.forEach(visit);
  };
  visit(root);
  return out;
}

function collectDatalists(root: ElpianNode): Map<string, string[]> {
  const out = new Map<string, string[]>();
  const visit = (n: ElpianNode) => {
    if (n.type === 'datalist' && n.props.id != null) {
      const values: string[] = [];
      for (const c of n.children) {
        if (c.type !== 'option') continue;
        const v = c.props.value ?? c.props.text ?? c.children.map((t) => t.props.text ?? '').join('');
        if (v != null && String(v) !== '') values.push(String(v));
      }
      out.set(String(n.props.id), values);
    }
    n.children.forEach(visit);
  };
  visit(root);
  return out;
}

function containsScene(node: JsonMap, depth: number): boolean {
  if (depth > 6) return false;
  if (node.type === 'Scene3D' || node.type === 'scene3d') return true;
  if (Array.isArray(node.children)) {
    for (const c of node.children) if (isMap(c) && containsScene(c, depth + 1)) return true;
  }
  return false;
}

export { PlatformGodotBinding };
