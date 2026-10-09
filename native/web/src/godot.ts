/**
 * The Godot HTML5 export as the Scene3D engine — the same page protocol as
 * Flutter's `WebGodotBinding` (godot/web/elpian_godot_web.js):
 * `__elpianGodotQueue` carries ops to Godot, `__elpianGodotReplies.pending`
 * carries replies and signals back, `__elpianGodotSurface(id)` hands out the
 * element hosting the engine canvas.
 */
import type { GodotPlatformBinding } from '@elpian/native-core';

type W = Window & {
  __elpianGodotQueue?: string[];
  __elpianGodotReplies?: { pending: string | null };
  __elpianGodotDrain?: () => string;
  __elpianGodotSurface?: (id: number | string) => HTMLElement;
};

const REPLY_TIMEOUT_MS = 2000;

export class WebGodotBinding implements GodotPlatformBinding {
  private nextRequest = 1;
  private readonly awaiting = new Map<number, { resolve(json: string): void; timer: number; count: number }>();
  private signalHandler: ((callbackId: number, argsJson: string) => void) | null = null;
  private poll: number | null = null;

  constructor() {
    const w = window as W;
    w.__elpianGodotQueue ??= [];
    this.ensurePolling();
  }

  get isLive(): boolean {
    return typeof (window as W).__elpianGodotDrain === 'function';
  }

  private ensurePolling(): void {
    if (this.poll != null) return;
    const tick = () => {
      this.poll = window.setTimeout(tick, this.isLive ? 16 : 1000);
      this.drainReplies();
    };
    this.poll = window.setTimeout(tick, 16);
  }

  private push(message: string): void {
    const w = window as W;
    (w.__elpianGodotQueue ??= []).push(message);
  }

  post(opsJson: string): void {
    this.push(`{"ops":${opsJson}}`);
  }

  send(opsJson: string): Promise<string> {
    const id = this.nextRequest++;
    let count = 0;
    try {
      count = (JSON.parse(opsJson) as unknown[]).length;
    } catch {
      count = 0;
    }
    return new Promise<string>((resolve) => {
      // A reply that never arrives must not wedge the caller.
      const timer = window.setTimeout(() => {
        this.awaiting.delete(id);
        resolve(JSON.stringify(new Array(count).fill(null)));
      }, REPLY_TIMEOUT_MS);
      this.awaiting.set(id, { resolve, timer, count });
      this.push(`{"ops":${opsJson},"req":${id}}`);
    });
  }

  mountSurface(surfaceId: number, mountHandle: number): void {
    this.push(JSON.stringify({ mount: surfaceId, node: mountHandle }));
  }

  releaseSurface(surfaceId: number): void {
    this.push(JSON.stringify({ release: surfaceId }));
  }

  setSignalHandler(handler: ((callbackId: number, argsJson: string) => void) | null): void {
    this.signalHandler = handler;
  }

  async stats(): Promise<Record<string, unknown>> {
    return { queued: (window as W).__elpianGodotQueue?.length ?? 0, awaiting: this.awaiting.size, live: this.isLive };
  }

  /** The element the export renders into for [surfaceId], when the glue is on the page. */
  surface(surfaceId: number): HTMLElement | null {
    const make = (window as W).__elpianGodotSurface;
    return typeof make === 'function' ? make(surfaceId) : null;
  }

  private drainReplies(): void {
    const replies = (window as W).__elpianGodotReplies;
    const raw = replies?.pending;
    if (!replies || !raw) return;
    replies.pending = null;
    let list: unknown;
    try {
      list = JSON.parse(raw);
    } catch (e) {
      console.warn('ElpianGodot(web): reply drain failed', e);
      return;
    }
    if (!Array.isArray(list)) return;
    for (const entry of list as any[]) {
      if (!entry || typeof entry !== 'object') continue;
      if (typeof entry.cb === 'number') {
        this.signalHandler?.(entry.cb, JSON.stringify(Array.isArray(entry.args) ? entry.args : []));
        continue;
      }
      if (typeof entry.req === 'number') {
        const w = this.awaiting.get(entry.req);
        if (!w) continue;
        this.awaiting.delete(entry.req);
        window.clearTimeout(w.timer);
        w.resolve(JSON.stringify(Array.isArray(entry.values) ? entry.values : []));
      }
    }
  }

  dispose(): void {
    if (this.poll != null) window.clearTimeout(this.poll);
    this.poll = null;
    for (const w of this.awaiting.values()) window.clearTimeout(w.timer);
    this.awaiting.clear();
  }
}
