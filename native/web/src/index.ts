/**
 * @elpian/web — host Elpian mini apps in web pages and web frameworks with
 * native browser elements: DOM views, Canvas2D, <video>, <iframe>, form
 * controls, and the Godot HTML5 export for Scene3D — with the Elpian engine
 * (./lib.ts) that lays them out.
 */
export { installElpian, mountElpian, ElpianViewElement, type ElpianSession } from './dom/element.js';
export { WebPlatform, type WebPlatformOptions } from './dom/platform.js';
export { DomRenderer, registerNativeComponent, type NativeComponentFactory, type NativeComponentInstance } from './dom/renderer.js';
export { CanvasPainter, registerCanvasPainter } from './dom/canvas.js';
export { WebGodotBinding } from './dom/godot.js';
export { WebElpianVm, WebQuickJs, WebWasmEngine } from './dom/runtimes.js';
export { measureText } from './dom/text.js';
export * from './lib.js';
