/**
 * Embedding API for web pages and frameworks.
 *
 *   import { installElpian, mountElpian } from '@elpian/web';
 *   installElpian({ assetBase: '/node_modules/@elpian/web/assets/' });
 *   const app = await mountElpian(div, 'miniapp', { runtime: 'quickjs', code, entryFunction: 'main' });
 *   app.on('println', (m) => console.log(m));
 *
 * or declaratively:
 *
 *   <elpian-view kind="nextjs" options='{"route":"/","serverBaseUrl":"https://…"}'></elpian-view>
 *
 * Session events (ready, error, println, updateApp, routeChanged, …) are
 * dispatched as `elpian:<event>` CustomEvents on the host element as well.
 */
import { SessionRegistry, setPlatform, type JsonMap } from '@elpian/native-core';
import { ICON_FAMILY } from './css.js';
import { WebPlatform, type WebPlatformOptions } from './platform.js';

let platform: WebPlatform | null = null;
let registry: SessionRegistry | null = null;
const listeners = new Map<string, Map<string, Set<(payload: any) => void>>>();
const elements = new Map<string, HTMLElement>();
let nextSurface = 1;

export interface ElpianSession {
  readonly surfaceId: string;
  readonly element: HTMLElement;
  /** Call a session method (see SessionRegistry): navigate, push, callFunction, usage, … */
  call(method: string, ...args: unknown[]): Promise<unknown>;
  on(event: string, listener: (payload: any) => void): () => void;
  close(): Promise<void>;
}

/** Install the web platform once (idempotent). */
export function installElpian(options: Partial<WebPlatformOptions> = {}): WebPlatform {
  if (platform) return platform;
  const assetBase = new URL(options.assetBase ?? new URL('../assets/', import.meta.url).toString(), location.href).toString();
  platform = new WebPlatform({ ...options, assetBase });
  setPlatform(platform);
  registry = new SessionRegistry((surface, event, payload) => {
    const byEvent = listeners.get(surface)?.get(event);
    if (byEvent) for (const l of [...byEvent]) l(payload);
    elements.get(surface)?.dispatchEvent(new CustomEvent(`elpian:${event}`, { detail: payload, bubbles: true }));
  });
  installFonts(assetBase);
  const p = platform;
  p.onImageLoaded((src, w, h) => registry!.imageLoaded(src, w, h));
  document.fonts?.addEventListener?.('loadingdone', () => {
    p.invalidateText();
    registry!.invalidateText();
  });
  watchDevicePixelRatio(() => {
    for (const id of elements.keys()) registry!.viewportChanged(id);
  });
  if (!customElements.get('elpian-view')) customElements.define('elpian-view', ElpianViewElement);
  return platform;
}

function installFonts(assetBase: string): void {
  if (document.getElementById('elpian-fonts')) return;
  const style = document.createElement('style');
  style.id = 'elpian-fonts';
  style.textContent = `@font-face{font-family:${ICON_FAMILY};font-style:normal;font-weight:400;font-display:block;src:url(${JSON.stringify(new URL('fonts/MaterialIcons-Regular.ttf', assetBase).toString())}) format('truetype');}`;
  document.head.appendChild(style);
  // Start the icon font immediately so first paints measure with it.
  void document.fonts?.load?.(`24px ${ICON_FAMILY}`);
}

function watchDevicePixelRatio(onChange: () => void): void {
  const listen = () => {
    const mq = window.matchMedia(`(resolution: ${window.devicePixelRatio}dppx)`);
    mq.addEventListener('change', () => {
      onChange();
      listen();
    }, { once: true });
  };
  if (typeof window.matchMedia === "function") listen();
}

/** Render a session of [kind] inside [element]. */
export async function mountElpian(element: HTMLElement, kind: string, options: JsonMap = {}): Promise<ElpianSession> {
  const p = installElpian();
  const reg = registry!;
  const surfaceId = `elpian-${nextSurface++}`;
  elements.set(surfaceId, element);
  if (!element.style.position || element.style.position === 'static') element.style.position = 'relative';
  element.style.overflow = 'hidden';
  p.attachSurface(surfaceId, element, { emit: (event) => reg.dispatchViewEvent(surfaceId, event) });
  const resize = new ResizeObserver(() => reg.viewportChanged(surfaceId));
  resize.observe(element);
  const dark = window.matchMedia?.('(prefers-color-scheme: dark)');
  const onTheme = () => reg.viewportChanged(surfaceId);
  dark?.addEventListener('change', onTheme);
  await reg.open(kind, surfaceId, options);
  let closed = false;
  return {
    surfaceId,
    element,
    call: (method, ...args) => reg.call(surfaceId, method, args),
    on(event, listener) {
      let m = listeners.get(surfaceId);
      if (!m) listeners.set(surfaceId, (m = new Map()));
      let s = m.get(event);
      if (!s) m.set(event, (s = new Set()));
      s.add(listener);
      return () => s!.delete(listener);
    },
    async close() {
      if (closed) return;
      closed = true;
      resize.disconnect();
      dark?.removeEventListener('change', onTheme);
      await reg.close(surfaceId);
      p.detachSurface(surfaceId);
      elements.delete(surfaceId);
      listeners.delete(surfaceId);
    },
  };
}

/**
 * `<elpian-view kind="miniapp|superapp|stream|nextjs|server|json" options='{…}'>`.
 * Changing `kind` or `options` re-opens the session; the `session` property
 * exposes the live handle.
 */
export class ElpianViewElement extends HTMLElement {
  static get observedAttributes(): string[] {
    return ['kind', 'options'];
  }

  session: ElpianSession | null = null;
  private pending: Promise<void> | null = null;
  private _options: JsonMap | null = null;

  /** Options as an object (wins over the `options` attribute). */
  get options(): JsonMap {
    if (this._options) return this._options;
    try {
      return JSON.parse(this.getAttribute('options') || '{}');
    } catch {
      return {};
    }
  }
  set options(v: JsonMap) {
    this._options = v;
    this.reopen();
  }

  connectedCallback(): void {
    if (!this.style.display) this.style.display = 'block';
    this.reopen();
  }

  disconnectedCallback(): void {
    const s = this.session;
    this.session = null;
    void s?.close();
  }

  attributeChangedCallback(): void {
    if (this.isConnected) this.reopen();
  }

  private reopen(): void {
    if (!this.isConnected) return;
    const run = async () => {
      await this.session?.close();
      this.session = null;
      const kind = this.getAttribute('kind') || 'json';
      this.session = await mountElpian(this, kind, this.options);
      this.dispatchEvent(new CustomEvent('elpian:mounted', { detail: this.session }));
    };
    this.pending = (this.pending ?? Promise.resolve()).then(run, run);
  }
}
