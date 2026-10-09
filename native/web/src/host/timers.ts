/**
 * `setTimeout` / `setInterval` / `clearTimeout` / `clearInterval` for guests —
 * a port of `VmTimerHostApi` (flutter/lib/src/vm/timer_host_api.dart). Timers
 * run on the platform clock and call back into the guest by function name.
 */
import { platform } from '../platform/platform.js';
import { isMap, type JsonMap } from '../util/json.js';
import { OK_RESPONSE, makeResponse } from '../util/typed.js';

export type VmTimerInvoke = (funcName: string, inputJson: string | null) => Promise<void> | void;

const MAX_DELAY = 2 ** 31;

export class VmTimerHostApi {
  private nextId = 1;
  private readonly timeouts = new Map<number, number>();
  private readonly intervals = new Map<number, { handle: number }>();
  private disposed = false;

  constructor(
    private readonly invoke: VmTimerInvoke,
    private readonly onError?: (message: string) => void,
  ) {}

  handle(apiName: string, payload: string): string {
    try {
      switch (apiName) {
        case 'setTimeout':
          return this.setTimer(payload, false);
        case 'setInterval':
          return this.setTimer(payload, true);
        case 'clearTimeout':
        case 'clearInterval':
          return this.clear(payload);
        default:
          return OK_RESPONSE;
      }
    } catch (e) {
      this.onError?.(`VmTimerHostApi error (${apiName}): ${e}`);
      return OK_RESPONSE;
    }
  }

  /** Live timer count (governance usage). */
  get activeCount(): number {
    return this.timeouts.size + this.intervals.size;
  }

  dispose(): void {
    this.disposed = true;
    const p = platform();
    for (const h of this.timeouts.values()) p.clearTimeout(h);
    for (const i of this.intervals.values()) p.clearTimeout(i.handle);
    this.timeouts.clear();
    this.intervals.clear();
  }

  private setTimer(payload: string, repeat: boolean): string {
    const args = normalized(payload);
    const handler = args.handler ?? args.callback ?? args.fn;
    if (handler == null || String(handler) === '') return OK_RESPONSE;
    const name = String(handler);
    const delay = readDelay(args);
    const input = readInputJson(args);
    const id = this.nextId++;
    const p = platform();
    if (repeat) {
      // Periodic: re-arm after each tick (Timer.periodic semantics — ticks
      // never pile up while the guest is busy).
      const entry = { handle: 0 };
      const tick = () => {
        if (this.disposed || !this.intervals.has(id)) return;
        entry.handle = p.setTimeout(tick, Math.max(delay, 0));
        void this.safeInvoke(name, input);
      };
      entry.handle = p.setTimeout(tick, Math.max(delay, 0));
      this.intervals.set(id, entry);
    } else {
      this.timeouts.set(
        id,
        p.setTimeout(() => {
          this.timeouts.delete(id);
          if (!this.disposed) void this.safeInvoke(name, input);
        }, delay),
      );
    }
    return makeResponse('i64', id);
  }

  private clear(payload: string): string {
    const id = readId(payload);
    if (id == null) return OK_RESPONSE;
    const p = platform();
    const t = this.timeouts.get(id);
    if (t !== undefined) {
      p.clearTimeout(t);
      this.timeouts.delete(id);
    }
    const i = this.intervals.get(id);
    if (i) {
      p.clearTimeout(i.handle);
      this.intervals.delete(id);
    }
    return OK_RESPONSE;
  }

  private async safeInvoke(handler: string, input: string | null): Promise<void> {
    try {
      await this.invoke(handler, input);
    } catch (e) {
      this.onError?.(`VmTimerHostApi invoke error (${handler}): ${e}`);
    }
  }
}

function parsePayload(payload: string): any {
  if (!payload) return null;
  let parsed: any;
  try {
    parsed = JSON.parse(payload);
  } catch {
    if (payload.length >= 2 && payload.startsWith('"') && payload.endsWith('"')) return payload.substring(1, payload.length - 1);
    return payload;
  }
  if (Array.isArray(parsed)) return parsed.length ? parsed[0] : null;
  if (isMap(parsed) && isMap(parsed.data) && 'value' in parsed.data) return parsed.data.value;
  return parsed;
}

function normalized(payload: string): JsonMap {
  const p = parsePayload(payload);
  return isMap(p) ? p : {};
}

function readDelay(args: JsonMap): number {
  const raw = args.delay ?? args.ms ?? args.interval;
  let v = 0;
  if (typeof raw === 'number') v = Math.round(raw);
  else if (typeof raw === 'string' && /^-?\d+$/.test(raw.trim())) v = parseInt(raw, 10);
  return Math.max(0, Math.min(MAX_DELAY, Number.isFinite(v) ? v : 0));
}

function readInputJson(args: JsonMap): string | null {
  if (typeof args.inputJson === 'string') return args.inputJson;
  if ('input' in args) return JSON.stringify(args.input);
  return null;
}

function readId(payload: string): number | null {
  const p = parsePayload(payload);
  const v = isMap(p) ? p.id ?? p.timerId ?? p.value : p;
  if (typeof v === 'number') return Math.round(v);
  if (typeof v === 'string' && /^-?\d+$/.test(v.trim())) return parseInt(v, 10);
  return null;
}
