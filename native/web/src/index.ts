/**
 * @elpian/web — host Elpian mini apps in web pages and web frameworks with
 * native browser elements: DOM views, Canvas2D, <video>, <iframe>, form
 * controls, and the Godot HTML5 export for Scene3D.
 */
export { installElpian, mountElpian, ElpianViewElement, type ElpianSession } from './element.js';
export { WebPlatform, type WebPlatformOptions } from './platform.js';
export { DomRenderer, registerNativeComponent, type NativeComponentFactory, type NativeComponentInstance } from './renderer.js';
export { CanvasPainter, registerCanvasPainter } from './canvas.js';
export { WebGodotBinding } from './godot.js';
export { WebElpianVm, WebQuickJs, WebWasmEngine } from './runtimes.js';
export { measureText } from './text.js';
export * from '@elpian/native-core';
