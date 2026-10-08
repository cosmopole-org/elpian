/**
 * Gesture recognition on DOM views with Flutter's arena semantics where it
 * matters: the innermost tap recognizer wins a tap, a pan beats a tap once the
 * pointer moves past the touch slop, a double-tap delays the single tap,
 * long-press fires after 500 ms without movement, and a fast pan end is also
 * reported as a swipe. Dismissible and Draggable gestures move the view (or a
 * floating copy of it) natively while they run.
 */
import type { GestureKind, ViewEvent } from '@elpian/native-core';

const SLOP = 18; // kTouchSlop
const DOUBLE_TAP_TIMEOUT = 300; // kDoubleTapTimeout
const LONG_PRESS_TIMEOUT = 500; // kLongPressTimeout
const SWIPE_VELOCITY = 600; // px/s (Dismissible's fling threshold is 700)

export interface GestureHost {
  /** Report an event for view [id]. */
  emit(event: ViewEvent): void;
  /** The surface root (for surface-relative coordinates). */
  root(): HTMLElement;
}

interface Tracked {
  id: number;
  x: number;
  y: number;
  startX: number;
  startY: number;
  t: number;
}

const TAP_KINDS: GestureKind[] = ['tap', 'doubletap', 'longpress', 'tapdown', 'tapup', 'tapcancel'];

export class GestureRecognizer {
  kinds = new Set<GestureKind>();
  dismissDirection = 'horizontal';
  dragData: unknown = null;
  tooltip: string | null = null;
  ripple: string | null = null;
  private pointers = new Map<number, Tracked>();
  private followers = new Map<number, () => void>();
  private mayPan = false;
  private panning = false;
  private claimed = false;
  private longPressTimer: number | null = null;
  private longPressed = false;
  private lastTapTime = 0;
  private pendingTap: number | null = null;
  private velocity: { t: number; x: number; y: number }[] = [];
  private scaleStart: { dist: number; angle: number } | null = null;
  private dismissOffset = 0;
  private feedback: HTMLElement | null = null;
  private tooltipEl: HTMLElement | null = null;
  private tooltipTimer: number | null = null;
  private readonly listeners: [string, EventListener][] = [];

  constructor(
    readonly el: HTMLElement,
    readonly viewId: number,
    private readonly host: GestureHost,
  ) {
    const on = (type: string, fn: (e: any) => void) => {
      el.addEventListener(type, fn as EventListener);
      this.listeners.push([type, fn as EventListener]);
    };
    on('pointerdown', (e: PointerEvent) => this.down(e));
    // Hover moves (no button down) arrive on the element itself; a pressed
    // pointer is followed at the window so nested recognizers all see it.
    on('pointermove', (e: PointerEvent) => {
      if (!this.pointers.has(e.pointerId)) this.move(e);
    });
    on('pointerenter', (e: PointerEvent) => this.hover('pointerenter', e));
    on('pointerleave', (e: PointerEvent) => this.hover('pointerexit', e));
    on('keydown', (e: KeyboardEvent) => this.key('keydown', e));
    on('keyup', (e: KeyboardEvent) => this.key('keyup', e));
    on('focus', () => this.has('focus') && this.emit({ type: 'focus' }));
    on('blur', () => this.has('focus') && this.emit({ type: 'blur' }));
    on('contextmenu', (e: Event) => {
      if (this.has('longpress')) e.preventDefault();
    });
  }

  configure(kinds: GestureKind[] | null | undefined): void {
    this.kinds = new Set(kinds ?? []);
    const el = this.el;
    // Let the browser keep scrolling unless this view drags on that axis.
    const pansBoth = this.has('pan') || this.has('scale') || this.has('draggable') || this.has('pointer');
    const dismissVertical = this.has('dismiss') && /vertical|up|down/.test(this.dismissDirection);
    el.style.touchAction = pansBoth ? 'none' : this.has('dismiss') ? (dismissVertical ? 'pan-x' : 'pan-y') : '';
    if (this.has('key') || this.has('focus')) {
      if (!el.hasAttribute('tabindex')) el.tabIndex = 0;
    }
  }

  has(k: GestureKind): boolean {
    return this.kinds.has(k);
  }

  private emit(e: Omit<ViewEvent, 'id'>): void {
    this.host.emit({ id: this.viewId, ...e } as ViewEvent);
  }

  private coords(e: { clientX: number; clientY: number }) {
    const r = this.host.root().getBoundingClientRect();
    const l = this.el.getBoundingClientRect();
    return { x: e.clientX - r.left, y: e.clientY - r.top, localX: e.clientX - l.left, localY: e.clientY - l.top };
  }

  // ---------------------------------------------------------------------------
  // Pointer stream
  // ---------------------------------------------------------------------------

  private down(e: PointerEvent): void {
    if (this.kinds.size === 0 && !this.ripple) return;
    if (e.pointerType === 'mouse' && e.button !== 0 && !this.has('pointer')) return;
    const c = this.coords(e);
    if (this.has('pointer')) this.emit({ type: 'pointerdown', ...c, buttons: e.buttons, pressure: e.pressure, pointerId: e.pointerId });
    this.pointers.set(e.pointerId, { id: e.pointerId, x: e.clientX, y: e.clientY, startX: e.clientX, startY: e.clientY, t: performance.now() });
    this.follow(e.pointerId);
    if (this.pointers.size === 2 && this.has('scale')) {
      this.beginScale();
      return;
    }
    if (this.pointers.size > 1) return;

    const inner = (e as any).__elpianTapClaimed === true;
    const tapping = TAP_KINDS.some((k) => this.has(k));
    this.claimed = tapping && !inner;
    if (this.claimed) (e as any).__elpianTapClaimed = true;
    // Drags: the innermost recognizer that drags wins (Flutter's arena).
    const drags = this.has('pan') || this.has('swipe') || this.has('draggable') || this.has('dismiss');
    this.mayPan = drags && (e as any).__elpianPanClaimed !== true;
    if (this.mayPan) (e as any).__elpianPanClaimed = true;
    this.panning = false;
    this.longPressed = false;
    this.velocity = [{ t: performance.now(), x: e.clientX, y: e.clientY }];
    if (this.claimed) {
      if (this.has('tapdown')) this.emit({ type: 'tapdown', ...c });
      if (this.has('longpress') || this.tooltip) {
        this.longPressTimer = window.setTimeout(() => {
          this.longPressTimer = null;
          this.longPressed = true;
          if (this.has('longpress')) this.emit({ type: 'longpress', ...c });
          if (this.tooltip) this.showTooltip();
        }, LONG_PRESS_TIMEOUT);
      }
    }
    if (this.ripple && !inner) this.startRipple(c.localX, c.localY);
  }

  private move(e: PointerEvent): void {
    const p = this.pointers.get(e.pointerId);
    const c = this.coords(e);
    if (!p) {
      if (this.has('hover') && e.pointerType === 'mouse') this.emit({ type: 'pointerhover', ...c });
      return;
    }
    const dx = e.clientX - p.x;
    const dy = e.clientY - p.y;
    p.x = e.clientX;
    p.y = e.clientY;
    if (this.has('pointer')) this.emit({ type: 'pointermove', ...c, dx, dy, buttons: e.buttons, pressure: e.pressure, pointerId: e.pointerId });
    if (this.scaleStart && this.pointers.size >= 2) {
      this.updateScale();
      return;
    }
    this.velocity.push({ t: performance.now(), x: e.clientX, y: e.clientY });
    if (this.velocity.length > 20) this.velocity.shift();
    const travelled = Math.hypot(e.clientX - p.startX, e.clientY - p.startY);
    if (!this.panning && travelled > SLOP) {
      this.cancelLongPress();
      if (this.claimed && this.has('tapcancel')) this.emit({ type: 'tapcancel' });
      this.claimed = false;
      this.stopRipple();
      if (this.mayPan) {
        this.panning = true;
        if (this.has('pan')) this.emit({ type: 'dragstart', ...c });
        if (this.has('draggable')) this.startFeedback(e, c);
      }
    }
    if (this.panning) {
      if (this.has('pan')) this.emit({ type: 'drag', ...c, dx, dy });
      if (this.has('draggable')) this.moveFeedback(e, c);
      if (this.has('dismiss')) this.dragDismiss(e.clientX - p.startX, e.clientY - p.startY);
      e.preventDefault();
    }
  }

  /** Track pointer [id] at the window until it lifts. */
  private follow(id: number): void {
    this.followers.get(id)?.();
    const move = (e: PointerEvent) => e.pointerId === id && this.move(e);
    const up = (e: PointerEvent) => e.pointerId === id && this.up(e, false);
    const cancel = (e: PointerEvent) => e.pointerId === id && this.up(e, true);
    window.addEventListener('pointermove', move, { passive: false });
    window.addEventListener('pointerup', up);
    window.addEventListener('pointercancel', cancel);
    this.followers.set(id, () => {
      window.removeEventListener('pointermove', move);
      window.removeEventListener('pointerup', up);
      window.removeEventListener('pointercancel', cancel);
    });
  }

  private up(e: PointerEvent, cancelled: boolean): void {
    const p = this.pointers.get(e.pointerId);
    if (!p) return;
    this.pointers.delete(e.pointerId);
    this.followers.get(e.pointerId)?.();
    this.followers.delete(e.pointerId);
    const c = this.coords(e);
    if (this.has('pointer')) this.emit({ type: cancelled ? 'pointercancel' : 'pointerup', ...c, pointerId: e.pointerId });
    if (this.scaleStart) {
      if (this.pointers.size < 2) {
        this.scaleStart = null;
        this.emit({ type: 'scaleend' });
      }
      return;
    }
    this.cancelLongPress();
    this.stopRipple();
    const v = this.flingVelocity();
    if (this.panning) {
      this.panning = false;
      if (this.has('pan')) this.emit({ type: 'dragend', ...c, vx: v.x, vy: v.y });
      if (this.has('swipe') && Math.max(Math.abs(v.x), Math.abs(v.y)) > SWIPE_VELOCITY) {
        const direction = Math.abs(v.x) > Math.abs(v.y) ? (v.x < 0 ? 'left' : 'right') : v.y < 0 ? 'up' : 'down';
        this.emit({ type: 'swipe', vx: v.x, vy: v.y, direction });
      }
      if (this.has('draggable')) this.endFeedback(c, cancelled);
      if (this.has('dismiss')) this.endDismiss(v);
      return;
    }
    if (cancelled || !this.claimed || this.longPressed) {
      if (this.claimed && this.has('tapcancel') && cancelled) this.emit({ type: 'tapcancel' });
      return;
    }
    if (this.has('tapup')) this.emit({ type: 'tapup', ...c });
    const now = performance.now();
    if (this.has('doubletap')) {
      if (this.pendingTap != null && now - this.lastTapTime < DOUBLE_TAP_TIMEOUT) {
        window.clearTimeout(this.pendingTap);
        this.pendingTap = null;
        this.emit({ type: 'doubletap', ...c });
        return;
      }
      this.lastTapTime = now;
      if (this.has('tap')) {
        // The single tap waits for the double-tap window, as in Flutter.
        this.pendingTap = window.setTimeout(() => {
          this.pendingTap = null;
          this.emit({ type: 'tap', ...c });
        }, DOUBLE_TAP_TIMEOUT);
      } else {
        this.pendingTap = window.setTimeout(() => (this.pendingTap = null), DOUBLE_TAP_TIMEOUT);
      }
      return;
    }
    if (this.has('tap')) this.emit({ type: 'tap', ...c });
  }

  private flingVelocity(): { x: number; y: number } {
    const s = this.velocity;
    if (s.length < 2) return { x: 0, y: 0 };
    const last = s[s.length - 1];
    let first = s[0];
    for (const p of s) if (last.t - p.t <= 100) {
      first = p;
      break;
    }
    const dt = (last.t - first.t) / 1000;
    if (dt <= 0) return { x: 0, y: 0 };
    return { x: (last.x - first.x) / dt, y: (last.y - first.y) / dt };
  }

  private cancelLongPress(): void {
    if (this.longPressTimer != null) window.clearTimeout(this.longPressTimer);
    this.longPressTimer = null;
  }

  private hover(type: 'pointerenter' | 'pointerexit', e: PointerEvent): void {
    if (e.pointerType !== 'mouse') return;
    if (this.has('hover')) this.emit({ type, ...this.coords(e) });
    if (this.tooltip) {
      if (type === 'pointerenter') this.tooltipTimer = window.setTimeout(() => this.showTooltip(), LONG_PRESS_TIMEOUT);
      else this.hideTooltip();
    }
  }

  private key(type: 'keydown' | 'keyup', e: KeyboardEvent): void {
    if (!this.has('key')) return;
    this.emit({ type, key: e.key, keyCode: e.keyCode, altKey: e.altKey, ctrlKey: e.ctrlKey, shiftKey: e.shiftKey, metaKey: e.metaKey });
    if (type === 'keydown' && e.key.length === 1) this.emit({ type: 'keypress', key: e.key, keyCode: e.keyCode, altKey: e.altKey, ctrlKey: e.ctrlKey, shiftKey: e.shiftKey, metaKey: e.metaKey });
  }

  // ---------------------------------------------------------------------------
  // Scale (pinch / rotate)
  // ---------------------------------------------------------------------------

  private pair(): [Tracked, Tracked] {
    const [a, b] = [...this.pointers.values()];
    return [a, b];
  }

  private beginScale(): void {
    this.cancelLongPress();
    this.claimed = false;
    const [a, b] = this.pair();
    this.scaleStart = { dist: Math.hypot(b.x - a.x, b.y - a.y) || 1, angle: Math.atan2(b.y - a.y, b.x - a.x) };
    const focal = this.coords({ clientX: (a.x + b.x) / 2, clientY: (a.y + b.y) / 2 });
    this.emit({ type: 'scalestart', x: focal.x, y: focal.y, scale: 1, rotation: 0 });
  }

  private updateScale(): void {
    const [a, b] = this.pair();
    const s = this.scaleStart!;
    const focal = this.coords({ clientX: (a.x + b.x) / 2, clientY: (a.y + b.y) / 2 });
    this.emit({ type: 'scaleupdate', x: focal.x, y: focal.y, scale: Math.hypot(b.x - a.x, b.y - a.y) / s.dist, rotation: Math.atan2(b.y - a.y, b.x - a.x) - s.angle });
  }

  // ---------------------------------------------------------------------------
  // Dismissible
  // ---------------------------------------------------------------------------

  private dragDismiss(dx: number, dy: number): void {
    const dir = this.dismissDirection;
    const vertical = /vertical|up|down/.test(dir);
    let d = vertical ? dy : dx;
    if (dir === 'endToStart' && d > 0) d = 0;
    if (dir === 'startToEnd' && d < 0) d = 0;
    if (dir === 'up' && d > 0) d = 0;
    if (dir === 'down' && d < 0) d = 0;
    this.dismissOffset = d;
    this.el.style.transition = 'none';
    this.el.style.translate = vertical ? `0 ${d}px` : `${d}px 0`;
  }

  private endDismiss(v: { x: number; y: number }): void {
    const vertical = /vertical|up|down/.test(this.dismissDirection);
    const extent = vertical ? this.el.offsetHeight : this.el.offsetWidth;
    const fling = vertical ? v.y : v.x;
    const d = this.dismissOffset;
    const passes = Math.abs(d) > extent * 0.4 || (Math.abs(fling) > 700 && Math.sign(fling) === Math.sign(d) && d !== 0);
    this.el.style.transition = 'translate 200ms ease-out';
    if (!passes) {
      this.el.style.translate = '0 0';
      this.dismissOffset = 0;
      return;
    }
    const sign = Math.sign(d) || 1;
    this.el.style.translate = vertical ? `0 ${sign * extent}px` : `${sign * extent}px 0`;
    const direction = vertical ? (sign < 0 ? 'up' : 'down') : sign < 0 ? 'endToStart' : 'startToEnd';
    window.setTimeout(() => this.emit({ type: 'dismissed', direction }), 200);
  }

  // ---------------------------------------------------------------------------
  // Draggable
  // ---------------------------------------------------------------------------

  private startFeedback(e: PointerEvent, c: { x: number; y: number; localX: number; localY: number }): void {
    const r = this.el.getBoundingClientRect();
    const copy = this.el.cloneNode(true) as HTMLElement;
    copy.style.position = 'fixed';
    copy.style.left = `${r.left}px`;
    copy.style.top = `${r.top}px`;
    copy.style.opacity = '0.7';
    copy.style.pointerEvents = 'none';
    copy.style.zIndex = '2147483647';
    copy.style.translate = '';
    (copy as any).__grab = { dx: e.clientX - r.left, dy: e.clientY - r.top };
    document.body.appendChild(copy);
    this.feedback = copy;
    this.el.style.opacity = '0.3';
    this.emit({ type: 'dragstart', ...c, data: this.dragData });
  }

  private moveFeedback(e: PointerEvent, c: { x: number; y: number }): void {
    const f = this.feedback;
    if (!f) return;
    const g = (f as any).__grab;
    f.style.left = `${e.clientX - g.dx}px`;
    f.style.top = `${e.clientY - g.dy}px`;
    this.emit({ type: 'dragupdate', x: c.x, y: c.y, data: this.dragData });
  }

  private endFeedback(c: { x: number; y: number }, cancelled: boolean): void {
    this.feedback?.remove();
    this.feedback = null;
    this.el.style.opacity = '';
    this.emit({ type: cancelled ? 'dragend' : 'drop', x: c.x, y: c.y, data: this.dragData });
  }

  // ---------------------------------------------------------------------------
  // Ripple and tooltip
  // ---------------------------------------------------------------------------

  private rippleEl: HTMLElement | null = null;

  private startRipple(x: number, y: number): void {
    const el = this.el;
    const size = Math.hypot(Math.max(x, el.offsetWidth - x), Math.max(y, el.offsetHeight - y)) * 2;
    const layer = document.createElement('span');
    layer.style.cssText = `position:absolute;inset:0;overflow:hidden;border-radius:inherit;pointer-events:none;z-index:2147483646`;
    const dot = document.createElement('span');
    dot.style.cssText = `position:absolute;left:${x - size / 2}px;top:${y - size / 2}px;width:${size}px;height:${size}px;border-radius:50%;background:${this.ripple};transform:scale(0.1);opacity:1;transition:transform 225ms cubic-bezier(0.4,0,0.2,1),opacity 150ms linear`;
    layer.appendChild(dot);
    el.appendChild(layer);
    this.rippleEl = layer;
    requestAnimationFrame(() => (dot.style.transform = 'scale(1)'));
  }

  private stopRipple(): void {
    const layer = this.rippleEl;
    if (!layer) return;
    this.rippleEl = null;
    const dot = layer.firstChild as HTMLElement | null;
    if (dot) dot.style.opacity = '0';
    window.setTimeout(() => layer.remove(), 200);
  }

  private showTooltip(): void {
    if (!this.tooltip || this.tooltipEl) return;
    const r = this.el.getBoundingClientRect();
    const tip = document.createElement('div');
    tip.textContent = this.tooltip;
    // Material Tooltip: grey 700 @ 90%, 4 px radius, 12 px white text, 24 px below.
    tip.style.cssText = `position:fixed;left:${r.left + r.width / 2}px;top:${r.bottom + 24}px;transform:translateX(-50%);background:rgba(97,97,97,0.9);color:#fff;font:12px ${'Roboto, system-ui, sans-serif'};padding:4px 8px;border-radius:4px;pointer-events:none;z-index:2147483647;white-space:pre;min-height:24px;box-sizing:border-box;display:flex;align-items:center`;
    document.body.appendChild(tip);
    this.tooltipEl = tip;
    window.setTimeout(() => this.hideTooltip(), 1500);
  }

  private hideTooltip(): void {
    if (this.tooltipTimer != null) window.clearTimeout(this.tooltipTimer);
    this.tooltipTimer = null;
    this.tooltipEl?.remove();
    this.tooltipEl = null;
  }

  dispose(): void {
    for (const [t, f] of this.listeners) this.el.removeEventListener(t, f);
    for (const stop of this.followers.values()) stop();
    this.followers.clear();
    this.cancelLongPress();
    if (this.pendingTap != null) window.clearTimeout(this.pendingTap);
    this.feedback?.remove();
    this.hideTooltip();
  }
}
