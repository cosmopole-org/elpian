/**
 * The Elpian event model — a port of `event_system.dart` and
 * `event_dispatcher.dart`.
 *
 * Events travel DOM-style: capturing from the root to the target, at the
 * target, then bubbling back up; a node's `events` map names the guest
 * function to call for an event type (`{"click": "onClick"}`). After a
 * dispatch completes (or propagation stops) the global handler sees the
 * event — that is where sessions route it into the VM.
 */
import type { ElpianNode } from '../model/node.js';

export type EventPhase = 'none' | 'capturing' | 'atTarget' | 'bubbling';

/** `ElpianEventType` — the camelCase name of each event kind. */
export const ElpianEventType = [
  'click', 'doubleClick', 'longPress', 'tap', 'tapDown', 'tapUp', 'tapCancel',
  'pointerDown', 'pointerUp', 'pointerMove', 'pointerEnter', 'pointerExit', 'pointerHover', 'pointerCancel',
  'dragStart', 'drag', 'dragEnd', 'dragEnter', 'dragLeave', 'dragOver', 'drop',
  'focus', 'blur', 'focusIn', 'focusOut',
  'input', 'change', 'submit',
  'keyDown', 'keyUp', 'keyPress',
  'scroll', 'reset', 'select', 'resize', 'load', 'unload',
  'touchStart', 'touchMove', 'touchEnd', 'touchCancel',
  'swipeLeft', 'swipeRight', 'swipeUp', 'swipeDown',
  'pinchStart', 'pinchUpdate', 'pinchEnd', 'scaleStart', 'scaleUpdate', 'scaleEnd',
  'rotateStart', 'rotateUpdate', 'rotateEnd', 'custom',
] as const;
export type ElpianEventTypeName = (typeof ElpianEventType)[number];

export interface Point {
  x: number;
  y: number;
}

export interface ElpianEvent {
  /** The wire name the `events` map is keyed by (`click`, `doubletap`, `pointerdown` …). */
  type: string;
  eventType: ElpianEventTypeName;
  target: string | null;
  currentTarget: string | null;
  timestamp: number;
  phase: EventPhase;
  data: Record<string, any>;
  // Pointer
  position?: Point;
  localPosition?: Point;
  delta?: Point;
  buttons?: number;
  pressure?: number;
  distance?: number;
  pointerId?: number;
  // Keyboard
  key?: string;
  keyCode?: number;
  altKey?: boolean;
  ctrlKey?: boolean;
  shiftKey?: boolean;
  metaKey?: boolean;
  // Input
  value?: any;
  inputType?: string | null;
  isComposing?: boolean;
  // Gesture
  velocity?: Point;
  scale?: number;
  rotation?: number;
  focalPoint?: Point;
  // Propagation flags
  propagationStopped?: boolean;
  immediatePropagationStopped?: boolean;
  defaultPrevented?: boolean;
}

export type EventKind = 'base' | 'pointer' | 'keyboard' | 'input' | 'gesture';

export function eventKind(e: ElpianEvent): EventKind {
  if (e.key !== undefined) return 'keyboard';
  if (e.velocity !== undefined || e.focalPoint !== undefined || e.scale !== undefined) return 'gesture';
  if (e.position !== undefined) return 'pointer';
  if ('value' in e) return 'input';
  return 'base';
}

export function makeEvent(type: string, eventType: ElpianEventTypeName, target: string | null, extra: Partial<ElpianEvent> = {}): ElpianEvent {
  return {
    type,
    eventType,
    target,
    currentTarget: target,
    timestamp: Date.now(),
    phase: 'none',
    data: {},
    ...extra,
  };
}

export function stopPropagation(e: ElpianEvent): void {
  e.propagationStopped = true;
}

export function preventDefault(e: ElpianEvent): void {
  e.defaultPrevented = true;
}

export type ElpianEventListener = (event: ElpianEvent) => void;

interface ListenerConfig {
  listener: ElpianEventListener;
  capture: boolean;
  once: boolean;
}

/** `ElpianEventTarget` mixin. */
export class EventTarget {
  private listeners = new Map<string, ListenerConfig[]>();

  addEventListener(type: string, listener: ElpianEventListener, options: { capture?: boolean; once?: boolean } = {}): void {
    const list = this.listeners.get(type) ?? [];
    list.push({ listener, capture: !!options.capture, once: !!options.once });
    this.listeners.set(type, list);
  }

  removeEventListener(type: string, listener: ElpianEventListener): void {
    const list = this.listeners.get(type);
    if (!list) return;
    const next = list.filter((c) => c.listener !== listener);
    if (next.length) this.listeners.set(type, next);
    else this.listeners.delete(type);
  }

  removeAllEventListeners(type?: string): void {
    if (type) this.listeners.delete(type);
    else this.listeners.clear();
  }

  dispatchEvent(event: ElpianEvent): boolean {
    const list = this.listeners.get(event.type);
    if (!list || list.length === 0) return !event.defaultPrevented;
    const remove: ListenerConfig[] = [];
    for (const config of [...list]) {
      if (config.capture && event.phase !== 'capturing') continue;
      if (!config.capture && event.phase === 'capturing') continue;
      try {
        config.listener(event);
      } catch (e) {
        console.warn('Error in event listener:', e);
      }
      if (config.once) remove.push(config);
      if (event.immediatePropagationStopped) break;
    }
    if (remove.length) this.listeners.set(event.type, list.filter((c) => !remove.includes(c)));
    return !event.defaultPrevented;
  }

  hasEventListener(type: string): boolean {
    return (this.listeners.get(type)?.length ?? 0) > 0;
  }

  getListenerCount(type?: string): number {
    if (type) return this.listeners.get(type)?.length ?? 0;
    let n = 0;
    for (const l of this.listeners.values()) n += l.length;
    return n;
  }
}

export class EventBus extends EventTarget {
  broadcast(event: ElpianEvent): void {
    this.dispatchEvent(event);
  }
  subscribe(type: string, listener: ElpianEventListener): void {
    this.addEventListener(type, listener);
  }
  unsubscribe(type: string, listener: ElpianEventListener): void {
    this.removeEventListener(type, listener);
  }
}

/**
 * `EventDispatcher`: knows every event-bearing node and its parent, runs the
 * capture / target / bubble phases, and finally hands the event to the
 * global handler.
 */
export class EventDispatcher {
  private nodes = new Map<string, ElpianNode>();
  private parents = new Map<string, string | null>();
  readonly bus = new EventBus();
  globalEventHandler: ElpianEventListener | null = null;
  /** Host-side listeners attached to a node (`(event) => void` values in `events`). */
  private nativeHandlers = new Map<string, Map<string, ElpianEventListener>>();

  registerNode(id: string, node: ElpianNode, parentId: string | null): void {
    this.nodes.set(id, node);
    this.parents.set(id, parentId);
  }

  unregisterNode(id: string): void {
    this.nodes.delete(id);
    this.parents.delete(id);
  }

  getNode(id: string): ElpianNode | undefined {
    return this.nodes.get(id);
  }

  addNodeHandler(id: string, type: string, listener: ElpianEventListener): void {
    let m = this.nativeHandlers.get(id);
    if (!m) this.nativeHandlers.set(id, (m = new Map()));
    m.set(type, listener);
  }

  private chain(elementId: string): string[] {
    const out: string[] = [];
    const seen = new Set<string>();
    let current: string | null | undefined = elementId;
    while (current != null && !seen.has(current)) {
      seen.add(current);
      out.push(current);
      current = this.parents.get(current);
    }
    return out;
  }

  dispatchEvent(event: ElpianEvent, elementId: string): void {
    const chain = this.chain(elementId);
    if (chain.length === 0) {
      this.globalEventHandler?.(event);
      return;
    }
    // Capturing: root → target (exclusive).
    for (let i = chain.length - 1; i > 0; i--) {
      const node = this.nodes.get(chain[i]);
      if (!node) continue;
      const capturing = { ...event, currentTarget: chain[i], phase: 'capturing' as EventPhase };
      this.dispatchToNode(chain[i], node, capturing);
      if (capturing.propagationStopped) {
        this.globalEventHandler?.(capturing);
        return;
      }
    }
    // At target.
    const targetNode = this.nodes.get(elementId);
    if (targetNode) {
      const atTarget = { ...event, currentTarget: elementId, phase: 'atTarget' as EventPhase };
      this.dispatchToNode(elementId, targetNode, atTarget);
      if (atTarget.propagationStopped) {
        this.globalEventHandler?.(atTarget);
        return;
      }
      event = atTarget;
    }
    // Bubbling: target → root.
    for (let i = 1; i < chain.length; i++) {
      const node = this.nodes.get(chain[i]);
      if (!node) continue;
      const bubbling = { ...event, currentTarget: chain[i], phase: 'bubbling' as EventPhase };
      this.dispatchToNode(chain[i], node, bubbling);
      if (bubbling.propagationStopped) {
        this.globalEventHandler?.(bubbling);
        return;
      }
    }
    this.bus.broadcast(event);
    this.globalEventHandler?.(event);
  }

  /** Every node on the path that declares a handler for [event.type], nearest first. */
  handlersAlongPath(event: ElpianEvent, elementId: string): { nodeId: string; handler: any }[] {
    const out: { nodeId: string; handler: any }[] = [];
    for (const id of this.chain(elementId)) {
      const handler = this.nodes.get(id)?.events?.[event.type];
      if (handler != null) out.push({ nodeId: id, handler });
    }
    return out;
  }

  private dispatchToNode(id: string, node: ElpianNode, event: ElpianEvent): void {
    const native = this.nativeHandlers.get(id)?.get(event.type);
    if (native) {
      try {
        native(event);
      } catch (e) {
        console.warn('Error executing event handler:', e);
      }
    }
    const handler = node.events?.[event.type];
    if (typeof handler === 'function') {
      try {
        handler(event);
      } catch (e) {
        console.warn('Error executing event handler:', e);
      }
    }
  }

  onGlobalEvent(listener: ElpianEventListener): void {
    this.globalEventHandler = listener;
  }

  onEventType(type: ElpianEventTypeName, listener: ElpianEventListener): void {
    this.bus.addEventListener(type, listener);
  }

  // Convenience dispatchers (mirroring the Dart API).
  dispatchClick(id: string, position?: Point): void {
    this.dispatchEvent(makeEvent('click', 'click', id, position ? { position, localPosition: position } : {}), id);
  }
  dispatchChange(id: string, value: any): void {
    this.dispatchEvent(makeEvent('change', 'change', id, { value }), id);
  }
  dispatchInput(id: string, value: any): void {
    this.dispatchEvent(makeEvent('input', 'input', id, { value }), id);
  }
  dispatchSubmit(id: string, data: Record<string, any> = {}): void {
    this.dispatchEvent(makeEvent('submit', 'submit', id, { data }), id);
  }
  dispatchFocus(id: string): void {
    this.dispatchEvent(makeEvent('focus', 'focus', id), id);
  }
  dispatchBlur(id: string): void {
    this.dispatchEvent(makeEvent('blur', 'blur', id), id);
  }

  clear(): void {
    this.nodes.clear();
    this.parents.clear();
    this.nativeHandlers.clear();
  }

  getStats(): { nodes: number; parents: number } {
    return { nodes: this.nodes.size, parents: this.parents.size };
  }
}

/** The event JSON delivered to guest handlers (`_eventToJson` in elpian_vm_widget.dart). */
export function eventToJson(event: ElpianEvent): Record<string, any> {
  const base: Record<string, any> = {
    type: event.type,
    eventType: event.eventType,
    target: event.target,
    currentTarget: event.currentTarget,
    timestamp: new Date(event.timestamp).toISOString(),
    phase: event.phase,
    data: event.data,
  };
  switch (eventKind(event)) {
    case 'pointer':
      Object.assign(base, {
        position: { x: event.position!.x, y: event.position!.y },
        localPosition: { x: event.localPosition?.x ?? event.position!.x, y: event.localPosition?.y ?? event.position!.y },
        delta: { x: event.delta?.x ?? 0, y: event.delta?.y ?? 0 },
        buttons: event.buttons ?? 0,
        pressure: event.pressure ?? 1,
        distance: event.distance ?? 0,
        pointerId: event.pointerId ?? 0,
      });
      break;
    case 'keyboard':
      Object.assign(base, {
        key: event.key,
        keyCode: event.keyCode ?? 0,
        altKey: !!event.altKey,
        ctrlKey: !!event.ctrlKey,
        shiftKey: !!event.shiftKey,
        metaKey: !!event.metaKey,
      });
      break;
    case 'input':
      Object.assign(base, { value: event.value, inputType: event.inputType ?? null });
      break;
    case 'gesture':
      Object.assign(base, {
        velocity: { x: event.velocity?.x ?? 0, y: event.velocity?.y ?? 0 },
        scale: event.scale ?? 1,
        rotation: event.rotation ?? 0,
        focalPoint: { x: event.focalPoint?.x ?? 0, y: event.focalPoint?.y ?? 0 },
      });
      break;
  }
  return base;
}
