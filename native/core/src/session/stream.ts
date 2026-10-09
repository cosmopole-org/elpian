/**
 * A view driven by a stream of commands — the port of `ElpianStreamWidget`
 * (flutter/lib/src/stream/elpian_stream_widget.dart). Commands are pushed in
 * (`push`), or read from a streaming HTTP response (`connect`, NDJSON or
 * server-sent events) through the platform.
 */
import { platform } from '../platform/platform.js';
import { w } from '../render/object.js';
import { deepMerge, isMap, type JsonMap } from '../util/json.js';
import { ElpianSurface, messageBox, type SurfaceOptions } from './surface.js';
import type { FetchRequest } from '../platform/platform.js';

export interface ElpianStreamCommand {
  action: string;
  view?: JsonMap | null;
  patch?: JsonMap | null;
  stylesheet?: JsonMap | null;
  animate?: boolean | null;
  animationDurationMs?: number | null;
  animationCurve?: string | null;
}

export function streamCommandFromDynamic(data: unknown): ElpianStreamCommand {
  if (typeof data === 'string') return streamCommandFromDynamic(JSON.parse(data));
  if (!isMap(data)) throw new Error(`Unsupported stream payload type: ${data === null ? 'null' : typeof data}.`);
  if ('type' in data && !('action' in data)) return { action: 'setView', view: data };
  const action = data.action != null ? String(data.action) : '';
  if (!action) throw new Error('Stream command must contain a non-empty "action".');
  const map = (v: unknown): JsonMap | null => {
    if (v == null) return null;
    if (isMap(v)) return v;
    throw new Error(`Expected a JSON object, got ${typeof v}.`);
  };
  const bool = (v: unknown): boolean | null => {
    if (v == null) return null;
    if (typeof v === 'boolean') return v;
    if (typeof v === 'string' && ['true', 'false'].includes(v.trim().toLowerCase())) return v.trim().toLowerCase() === 'true';
    throw new Error(`Expected a bool, got ${typeof v}.`);
  };
  const int = (v: unknown): number | null => {
    if (v == null) return null;
    if (typeof v === 'number') return Math.trunc(v);
    if (typeof v === 'string') {
      const n = parseInt(v, 10);
      return Number.isNaN(n) ? null : n;
    }
    throw new Error(`Expected an int, got ${typeof v}.`);
  };
  return {
    action,
    view: map(data.view),
    patch: map(data.patch),
    stylesheet: map(data.stylesheet),
    animate: bool(data.animate),
    animationDurationMs: int(data.animationDurationMs),
    animationCurve: data.animationCurve != null ? String(data.animationCurve) : null,
  };
}

const CURVES = new Set(['linear', 'easeIn', 'easeOut', 'easeInOut', 'fastOutSlowIn', 'bounceIn', 'bounceOut']);

export interface StreamSessionOptions {
  initialStylesheet?: JsonMap | null;
  onCommand?(command: ElpianStreamCommand): void;
  onStreamDone?(): void;
  onError?(message: string): void;
  defaultAnimationDurationMs?: number;
  defaultAnimationCurve?: string;
  surface?: SurfaceOptions;
}

export class StreamSession {
  readonly surface: ElpianSurface;
  private currentView: JsonMap | null = null;
  private errorMessage: string | null = null;
  private version = 0;
  private activeDuration = 0;
  private activeCurve = 'linear';
  private cancel: (() => void) | null = null;

  constructor(
    surfaceId: string,
    readonly options: StreamSessionOptions = {},
  ) {
    this.surface = new ElpianSurface(surfaceId, options.surface);
    if (options.initialStylesheet) this.surface.engine.loadStylesheet(options.initialStylesheet);
    // AnimatedSwitcher(KeyedSubtree(ValueKey(version))) around the content.
    this.surface.decorate = (content) =>
      w('animatedSwitcher', { duration: this.activeDuration, curve: this.activeCurve, transitionType: 'fade' }, [w('proxy', {}, content, `v${this.version}`)]);
    this.refresh();
  }

  get view(): JsonMap | null {
    return this.currentView;
  }

  /** Deliver one stream message (a command object, a bare view, or JSON text). */
  push(data: unknown): void {
    try {
      const command = streamCommandFromDynamic(data);
      this.options.onCommand?.(command);
      this.apply(command);
      if (this.errorMessage != null) {
        this.errorMessage = null;
        this.refresh();
      }
    } catch (e) {
      this.error(e);
    }
  }

  error(e: unknown): void {
    this.errorMessage = String(e instanceof Error ? e.message : e);
    this.options.onError?.(this.errorMessage);
    this.refresh();
  }

  done(): void {
    this.options.onStreamDone?.();
  }

  /**
   * Read commands from a streaming response: newline-delimited JSON, or
   * server-sent events (`data:` lines). Replaces any previous connection.
   */
  connect(request: FetchRequest): void {
    this.cancel?.();
    const fetchStream = platform().fetchStream;
    if (!fetchStream) {
      this.error('This platform cannot stream HTTP responses.');
      return;
    }
    let buffer = '';
    let sse: string[] = [];
    const line = (raw: string) => {
      const l = raw.replace(/\r$/, '');
      if (l.startsWith('data:')) {
        sse.push(l.substring(5).replace(/^ /, ''));
        return;
      }
      if (l === '') {
        if (sse.length) {
          const payload = sse.join('\n');
          sse = [];
          if (payload.trim()) this.push(payload);
        }
        return;
      }
      if (l.startsWith(':') || /^(event|id|retry):/.test(l)) return;
      if (l.trim()) this.push(l);
    };
    this.cancel = fetchStream(request, {
      onChunk: (text) => {
        buffer += text;
        let i: number;
        while ((i = buffer.indexOf('\n')) >= 0) {
          line(buffer.substring(0, i));
          buffer = buffer.substring(i + 1);
        }
      },
      onDone: () => {
        if (buffer) line(buffer);
        line('');
        buffer = '';
        this.done();
      },
      onError: (m) => this.error(m),
    });
  }

  private apply(c: ElpianStreamCommand): void {
    const animate = c.animate ?? false;
    const duration = c.animationDurationMs == null ? this.options.defaultAnimationDurationMs ?? 240 : Math.max(0, Math.min(30000, c.animationDurationMs));
    const curve = c.animationCurve && CURVES.has(c.animationCurve.trim()) ? c.animationCurve.trim() : this.options.defaultAnimationCurve ?? 'easeInOut';
    const setActive = () => {
      this.activeDuration = animate ? duration : 0;
      this.activeCurve = curve;
    };
    switch (c.action) {
      case 'setView':
        if (!c.view) throw new Error('setView requires "view" object.');
        setActive();
        this.update({ ...c.view });
        return;
      case 'patchView':
        if (!c.patch) throw new Error('patchView requires "patch" object.');
        if (!this.currentView) throw new Error('patchView received before any setView command.');
        setActive();
        this.update(deepMerge(this.currentView, c.patch));
        return;
      case 'setStylesheet':
        if (!c.stylesheet) throw new Error('setStylesheet requires "stylesheet" object.');
        this.surface.engine.loadStylesheet(c.stylesheet);
        setActive();
        this.refresh();
        return;
      case 'renderWithStylesheet':
        if (!c.stylesheet || !c.view) throw new Error('renderWithStylesheet requires both "stylesheet" and "view".');
        this.surface.engine.loadStylesheet(c.stylesheet);
        setActive();
        this.update({ ...c.view });
        return;
      case 'clear':
        this.currentView = null;
        this.version++;
        setActive();
        this.refresh();
        return;
      default:
        throw new Error(`Unknown stream action: ${c.action}.`);
    }
  }

  private update(view: JsonMap): void {
    this.currentView = view;
    this.version++;
    this.refresh();
  }

  private refresh(): void {
    if (this.errorMessage != null) {
      this.surface.setOverlay(messageBox(`Stream Error: ${this.errorMessage}`, 0xfff44336));
      return;
    }
    this.surface.setContent(this.currentView);
  }

  dispose(): void {
    this.cancel?.();
    this.cancel = null;
    this.surface.dispose();
  }
}
