/**
 * AnimationController and ImplicitValue — the two animation primitives the
 * render objects use.
 *
 * Controllers tick from the owner's frame clock (the platform's vsync), so
 * every animation on a surface advances in lock-step and stops scheduling
 * frames when idle — the same model as Flutter's Ticker.
 */
import type { RenderOwner, Ticker } from '../render/owner.js';
import { Curves, type Curve } from './curves.js';

export type AnimationStatus = 'dismissed' | 'forward' | 'reverse' | 'completed';

/** Flutter `AnimationController`: a 0..1 value driven over [duration] ms. */
export class AnimationController implements Ticker {
  value: number;
  status: AnimationStatus = 'dismissed';
  private owner: RenderOwner | null = null;
  private from = 0;
  private to = 1;
  private startTime: number | null = null;
  private running = false;
  private repeat = false;
  private reverseOnRepeat = false;
  private completer: (() => void) | null = null;
  private listeners = new Set<() => void>();
  private statusListeners = new Set<(s: AnimationStatus) => void>();

  constructor(
    public duration: number,
    initial = 0,
    public reverseDuration: number | null = null,
  ) {
    this.value = initial;
  }

  attach(owner: RenderOwner): void {
    this.owner = owner;
    if (this.running) owner.addTicker(this);
  }

  detach(): void {
    this.owner?.removeTicker(this);
    this.owner = null;
  }

  addListener(fn: () => void): void {
    this.listeners.add(fn);
  }
  removeListener(fn: () => void): void {
    this.listeners.delete(fn);
  }
  addStatusListener(fn: (s: AnimationStatus) => void): void {
    this.statusListeners.add(fn);
  }

  private setStatus(s: AnimationStatus): void {
    if (this.status === s) return;
    this.status = s;
    for (const l of [...this.statusListeners]) l(s);
  }

  get isAnimating(): boolean {
    return this.running;
  }

  private start(target: number): Promise<void> {
    this.from = this.value;
    this.to = target;
    this.startTime = null;
    this.running = true;
    this.setStatus(target >= this.from ? 'forward' : 'reverse');
    this.owner?.addTicker(this);
    return new Promise((resolve) => {
      this.completer?.();
      this.completer = resolve;
    });
  }

  forward(from?: number): Promise<void> {
    this.repeat = false;
    if (from != null) this.value = from;
    return this.start(1);
  }

  reverse(from?: number): Promise<void> {
    this.repeat = false;
    if (from != null) this.value = from;
    return this.start(0);
  }

  animateTo(target: number): Promise<void> {
    this.repeat = false;
    return this.start(target);
  }

  /** Loop 0→1 forever (ping-pong when [reverse]). */
  repeatAnimation(reverse = false): void {
    this.repeat = true;
    this.reverseOnRepeat = reverse;
    this.from = this.value >= 1 ? 0 : this.value;
    this.to = 1;
    this.startTime = null;
    this.running = true;
    this.setStatus('forward');
    this.owner?.addTicker(this);
  }

  stop(): void {
    this.running = false;
    this.repeat = false;
    this.owner?.removeTicker(this);
    this.completer?.();
    this.completer = null;
  }

  reset(value = 0): void {
    this.stop();
    this.value = value;
    this.setStatus('dismissed');
    this.notify();
  }

  private notify(): void {
    for (const l of [...this.listeners]) l();
  }

  tick(now: number): boolean {
    if (!this.running) return false;
    if (this.startTime == null) this.startTime = now;
    const goingBack = this.to < this.from;
    const duration = Math.max(1, goingBack && this.reverseDuration != null ? this.reverseDuration : this.duration);
    const span = Math.abs(this.to - this.from);
    const total = duration * span;
    const elapsed = now - this.startTime;
    const t = total <= 0 ? 1 : Math.min(1, elapsed / total);
    this.value = this.from + (this.to - this.from) * t;
    this.notify();
    if (t < 1) return true;
    if (this.repeat) {
      if (this.reverseOnRepeat) {
        const next = this.to >= 1 ? 0 : 1;
        this.from = this.value;
        this.to = next;
        this.setStatus(next === 1 ? 'forward' : 'reverse');
      } else {
        this.from = 0;
        this.to = 1;
        this.value = 0;
      }
      this.startTime = now;
      return true;
    }
    this.running = false;
    this.setStatus(this.to >= 1 ? 'completed' : 'dismissed');
    this.completer?.();
    this.completer = null;
    return false;
  }
}

export type Lerp<T> = (a: T, b: T, t: number) => T;

export const lerpNumber: Lerp<number> = (a, b, t) => a + (b - a) * t;

/**
 * An implicitly animated value (the engine of Flutter's `AnimatedFoo`
 * widgets): setting a new target animates from the current value over the
 * configured duration and curve; without a duration it jumps.
 */
export class ImplicitValue<T> {
  private controller: AnimationController | null = null;
  private begin: T;
  private end: T;
  private curve: Curve = Curves.linear;

  constructor(
    private value: T,
    private readonly lerp: Lerp<T>,
    private readonly equals: (a: T, b: T) => boolean,
    private readonly onChange: () => void,
  ) {
    this.begin = value;
    this.end = value;
  }

  get current(): T {
    return this.value;
  }

  get target(): T {
    return this.end;
  }

  get animating(): boolean {
    return this.controller?.isAnimating ?? false;
  }

  /** Set a new target; animate when [duration] > 0 and an owner is attached. */
  set(target: T, duration: number | null | undefined, curve: Curve | null | undefined, owner: RenderOwner | null): void {
    if (this.equals(target, this.end)) return;
    if (!duration || duration <= 0 || !owner) {
      this.controller?.stop();
      this.begin = this.end = this.value = target;
      this.onChange();
      return;
    }
    this.begin = this.value;
    this.end = target;
    this.curve = curve ?? Curves.linear;
    if (!this.controller) {
      this.controller = new AnimationController(duration);
      this.controller.addListener(() => {
        const t = this.curve(this.controller!.value);
        this.value = this.lerp(this.begin, this.end, t);
        this.onChange();
      });
    }
    this.controller.duration = duration;
    this.controller.attach(owner);
    void this.controller.forward(0);
  }

  /** Jump without animating (initial configuration). */
  jump(value: T): void {
    this.controller?.stop();
    this.begin = this.end = this.value = value;
  }

  dispose(): void {
    this.controller?.detach();
    this.controller?.stop();
  }
}
