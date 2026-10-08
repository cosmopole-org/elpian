/**
 * What the core needs from the platform it runs on.
 *
 * The web host implements this directly in the browser; the Android and iOS
 * hosts implement it in Kotlin / Swift and expose it to the core's JS engine
 * as the `__elpianHost` global (see bridge/native-host.ts). Everything here is
 * synchronous except networking, so the core can lay out and paint inside a
 * single turn.
 */
import type { ControlMeasureSpec, Size, TextMetrics, TextSpec, ViewOp } from '../render/view.js';

export interface Viewport {
  width: number;
  height: number;
  devicePixelRatio: number;
  safeArea: { top: number; right: number; bottom: number; left: number };
  /** e.g. `en-US`. */
  locale: string;
  /** `android`, `ios`, `web`, … (Flutter's `defaultTargetPlatform`). */
  platform: string;
  isWeb: boolean;
  darkMode: boolean;
  /** System text scale factor (accessibility). */
  textScale: number;
  /** The page URL on the web; the deep link / app URL elsewhere. */
  href?: string;
}

export interface FetchRequest {
  url: string;
  method?: string;
  headers?: Record<string, string>;
  body?: string | null;
  timeoutMs?: number;
}

export interface FetchResponse {
  status: number;
  headers: Record<string, string>;
  body: string;
}

export interface StreamHandlers {
  onChunk(text: string): void;
  onDone(): void;
  onError(message: string): void;
}

/** A Godot transport to the native engine (see godot/binding.ts). */
export interface GodotPlatformBinding {
  readonly isLive: boolean;
  post(opsJson: string): void;
  send(opsJson: string): Promise<string>;
  mountSurface(surfaceId: number, mountHandle: number): void;
  releaseSurface(surfaceId: number): void;
  setSignalHandler(handler: ((callbackId: number, argsJson: string) => void) | null): void;
  stats?(): Promise<Record<string, unknown> | null>;
}

export interface Platform {
  readonly name: string;

  // ---- time and scheduling ----
  now(): number;
  setTimeout(callback: () => void, ms: number): number;
  clearTimeout(handle: number): void;
  /** Ask for [callback] on the next display frame (vsync). */
  requestFrame(callback: (timeMs: number) => void): number;
  cancelFrame(handle: number): void;

  // ---- rendering ----
  /** Apply a batch of view operations to [surface] (a session's root container). */
  commit(surface: string, ops: ViewOp[]): void;
  measureText(spec: TextSpec, maxWidth: number): TextMetrics;
  /** Intrinsic size of a native control; return null to use the core's Material defaults. */
  measureControl?(spec: ControlMeasureSpec, maxWidth: number): Size | null;
  /** Natural pixel size of an image once known (null while loading). */
  imageSize?(src: string): Size | null;
  /** Called by the core when it learns an image size is needed; the platform calls back `onImageLoaded`. */
  preloadImage?(src: string): void;
  viewport(surface: string): Viewport;

  // ---- services ----
  log(level: 'debug' | 'info' | 'warn' | 'error', message: string): void;
  openUrl?(url: string): void;
  fetch?(request: FetchRequest): Promise<FetchResponse>;
  fetchStream?(request: FetchRequest, handlers: StreamHandlers): () => void;
  storageGet?(key: string): string | null;
  storageSet?(key: string, value: string | null): void;
  /** Load a bundled asset (`asset:` URIs / Flutter asset paths) as text or base64. */
  loadAsset?(path: string, encoding: 'utf8' | 'base64'): Promise<string>;
  godot?: GodotPlatformBinding;
}

let current: Platform | null = null;

export function setPlatform(platform: Platform): void {
  current = platform;
}

export function platform(): Platform {
  if (!current) throw new Error('Elpian core: no platform installed (call setPlatform first)');
  return current;
}

export function hasPlatform(): boolean {
  return current != null;
}
