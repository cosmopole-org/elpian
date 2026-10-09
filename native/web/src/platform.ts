/**
 * The browser as an Elpian platform: timers and vsync, DOM commits through
 * the renderer, paragraph measurement, viewports (with safe-area insets, dark
 * mode and locale), images, networking (with streaming), localStorage,
 * bundled assets, the Godot web transport and the three runtimes.
 */
import type { FetchRequest, FetchResponse, Platform, Size, StreamHandlers, TextMetrics, TextSpec, ViewOp, Viewport } from '@elpian/native-core';
import { WebGodotBinding } from './godot.js';
import { DomRenderer, type RendererHooks } from './renderer.js';
import { WebElpianVm, WebQuickJs, WebWasmEngine } from './runtimes.js';
import { clearTextCache, measureText } from './text.js';

export interface WebPlatformOptions {
  /** Base URL of the package's `assets/` folder (fonts and runtime files). */
  assetBase: string;
  /** Where `loadAsset(path)` resolves relative paths (defaults to the page). */
  appAssetBase?: string;
  /** Prefix for localStorage keys. */
  storagePrefix?: string;
}

interface SurfaceEntry {
  element: HTMLElement;
  renderer: DomRenderer;
}

export class WebPlatform implements Platform {
  readonly name = 'web';
  readonly godot: WebGodotBinding;
  readonly elpianVm: WebElpianVm;
  readonly jsSandbox: WebQuickJs;
  readonly wasm = new WebWasmEngine();
  private readonly surfaces = new Map<string, SurfaceEntry>();
  private readonly images = new Map<string, Size | 'loading' | 'error'>();
  private readonly imageListeners = new Set<(src: string, w: number, h: number) => void>();
  private safeAreaProbe: HTMLElement | null = null;

  constructor(readonly options: WebPlatformOptions) {
    const base = options.assetBase.endsWith('/') ? options.assetBase : `${options.assetBase}/`;
    this.elpianVm = new WebElpianVm(`${base}runtime/wasm/elpian_vm/elpian_vm.js`);
    this.jsSandbox = new WebQuickJs(`${base}runtime/vendor/quickjs-emscripten.mjs`, `${base}runtime/vendor/quickjs-emscripten.wasm`);
    this.godot = new WebGodotBinding();
  }

  // ---- surfaces ----

  attachSurface(id: string, element: HTMLElement, hooks: Omit<RendererHooks, 'imageLoaded' | 'godotSurface'>): DomRenderer {
    this.detachSurface(id);
    const renderer = new DomRenderer(element, {
      emit: hooks.emit,
      imageLoaded: (src, w, h) => this.imageLoaded(src, w, h),
      godotSurface: (sid) => this.godot.surface(sid),
    });
    this.surfaces.set(id, { element, renderer });
    return renderer;
  }

  detachSurface(id: string): void {
    const s = this.surfaces.get(id);
    if (!s) return;
    s.renderer.clear();
    this.surfaces.delete(id);
  }

  onImageLoaded(listener: (src: string, w: number, h: number) => void): () => void {
    this.imageListeners.add(listener);
    return () => this.imageListeners.delete(listener);
  }

  private imageLoaded(src: string, w: number, h: number): void {
    const prev = this.images.get(src);
    const next: Size | 'error' = w > 0 && h > 0 ? { width: w, height: h } : 'error';
    if (prev && typeof prev === 'object' && next !== 'error' && prev.width === w && prev.height === h) return;
    this.images.set(src, next);
    for (const l of this.imageListeners) l(src, w, h);
  }

  // ---- time ----

  now(): number {
    return performance.now();
  }
  setTimeout(callback: () => void, ms: number): number {
    return window.setTimeout(callback, ms);
  }
  clearTimeout(handle: number): void {
    window.clearTimeout(handle);
  }
  requestFrame(callback: (timeMs: number) => void): number {
    return window.requestAnimationFrame(callback);
  }
  cancelFrame(handle: number): void {
    window.cancelAnimationFrame(handle);
  }

  // ---- rendering ----

  commit(surface: string, ops: ViewOp[]): void {
    this.surfaces.get(surface)?.renderer.apply(ops, window.devicePixelRatio || 1);
  }

  measureText(spec: TextSpec, maxWidth: number): TextMetrics {
    return measureText(spec, maxWidth);
  }

  /** Fonts changed: drop cached metrics. */
  invalidateText(): void {
    clearTextCache();
  }

  imageSize(src: string): Size | null {
    const s = this.images.get(src);
    return s && typeof s === 'object' ? s : null;
  }

  preloadImage(src: string): void {
    if (this.images.has(src)) return;
    this.images.set(src, 'loading');
    const img = new Image();
    img.decoding = 'async';
    img.onload = () => this.imageLoaded(src, img.naturalWidth, img.naturalHeight);
    img.onerror = () => this.imageLoaded(src, 0, 0);
    img.src = src;
  }

  viewport(surface: string): Viewport {
    const el = this.surfaces.get(surface)?.element;
    const width = el ? el.clientWidth : window.innerWidth;
    const height = el ? el.clientHeight : window.innerHeight;
    return {
      width,
      height,
      devicePixelRatio: window.devicePixelRatio || 1,
      safeArea: this.safeArea(),
      locale: navigator.language || 'en-US',
      platform: 'web',
      isWeb: true,
      darkMode: window.matchMedia?.('(prefers-color-scheme: dark)').matches ?? false,
      textScale: 1,
      href: location.href,
    };
  }

  private safeArea(): Viewport['safeArea'] {
    if (!this.safeAreaProbe) {
      const p = document.createElement('div');
      p.style.cssText = 'position:fixed;visibility:hidden;pointer-events:none;padding:env(safe-area-inset-top) env(safe-area-inset-right) env(safe-area-inset-bottom) env(safe-area-inset-left)';
      document.body.appendChild(p);
      this.safeAreaProbe = p;
    }
    const cs = getComputedStyle(this.safeAreaProbe);
    return { top: parseFloat(cs.paddingTop) || 0, right: parseFloat(cs.paddingRight) || 0, bottom: parseFloat(cs.paddingBottom) || 0, left: parseFloat(cs.paddingLeft) || 0 };
  }

  // ---- services ----

  log(level: 'debug' | 'info' | 'warn' | 'error', message: string): void {
    (console[level] ?? console.log)(`[elpian] ${message}`);
  }

  openUrl(url: string): void {
    window.open(url, '_blank', 'noopener,noreferrer');
  }

  async fetch(request: FetchRequest): Promise<FetchResponse> {
    const ctl = new AbortController();
    const timer = request.timeoutMs ? window.setTimeout(() => ctl.abort(), request.timeoutMs) : null;
    try {
      const res = await window.fetch(request.url, { method: request.method ?? 'GET', headers: request.headers ?? {}, body: request.body ?? undefined, signal: ctl.signal });
      const headers: Record<string, string> = {};
      res.headers.forEach((v, k) => (headers[k] = v));
      return { status: res.status, headers, body: await res.text() };
    } catch (e) {
      if (ctl.signal.aborted) throw new Error(`request to ${request.url} timed out`);
      throw new Error(`network error reaching ${request.url}: ${e}`);
    } finally {
      if (timer != null) window.clearTimeout(timer);
    }
  }

  fetchStream(request: FetchRequest, handlers: StreamHandlers): () => void {
    const ctl = new AbortController();
    let done = false;
    (async () => {
      try {
        const res = await window.fetch(request.url, { method: request.method ?? 'GET', headers: request.headers ?? {}, body: request.body ?? undefined, signal: ctl.signal });
        if (!res.ok || !res.body) throw new Error(`HTTP status ${res.status}`);
        const reader = res.body.getReader();
        const decoder = new TextDecoder();
        for (;;) {
          const { value, done: end } = await reader.read();
          if (end) break;
          handlers.onChunk(decoder.decode(value, { stream: true }));
        }
        const tail = decoder.decode();
        if (tail) handlers.onChunk(tail);
        done = true;
        handlers.onDone();
      } catch (e) {
        if (done || ctl.signal.aborted) return;
        handlers.onError(String(e instanceof Error ? e.message : e));
      }
    })();
    return () => ctl.abort();
  }

  storageGet(key: string): string | null {
    try {
      return localStorage.getItem((this.options.storagePrefix ?? '') + key);
    } catch {
      return null;
    }
  }

  storageSet(key: string, value: string | null): void {
    try {
      const k = (this.options.storagePrefix ?? '') + key;
      if (value == null) localStorage.removeItem(k);
      else localStorage.setItem(k, value);
    } catch {
      /* storage unavailable */
    }
  }

  async loadAsset(path: string, encoding: 'utf8' | 'base64'): Promise<string> {
    const url = new URL(path.replace(/^asset:\/*/, ''), this.options.appAssetBase ?? location.href).toString();
    const res = await window.fetch(url);
    if (!res.ok) throw new Error(`asset ${path}: HTTP ${res.status}`);
    if (encoding === 'utf8') return res.text();
    const bytes = new Uint8Array(await res.arrayBuffer());
    let bin = '';
    for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
    return btoa(bin);
  }
}
