/**
 * Leaf render objects backed by native elements: images, native controls,
 * canvases, Godot surfaces, media players and embedded web content, plus the
 * transparent gesture region every event-bearing element is wrapped in.
 */
import type { Color } from '../../css/color.js';
import {
  INF,
  RenderObject,
  RenderProxy,
  biggest,
  constrain,
  smallest,
  tightFor,
  enforce,
  type Constraints,
  type Size,
} from '../object.js';
import { preserveAspect } from '../layout/basic.js';
import type { GestureKind, TextStyleSpec, ViewEvent, ViewKind, ViewProps } from '../view.js';

// ----------------------------------------------------------------------------
// Image
// ----------------------------------------------------------------------------

/** props: { src, fit, alignment, width, height, alt, repeat, tint, semanticsLabel, onEvent } */
export class RenderImage extends RenderObject {
  naturalSize(): Size | null {
    const src: string | null = this.props.src ?? null;
    if (!src || !this.owner) return null;
    return this.owner.imageSize(src);
  }

  protected performLayout(c: Constraints): void {
    const inner = enforce(tightFor({ minWidth: 0, maxWidth: INF, minHeight: 0, maxHeight: INF }, this.props.width, this.props.height), c);
    const natural = this.naturalSize();
    if (!natural) {
      this.size = smallest(inner);
      return;
    }
    this.size = preserveAspect(inner, natural);
  }

  protected computeMaxIntrinsicWidth(h: number): number {
    if (this.props.width != null) return this.props.width;
    const n = this.naturalSize();
    if (!n) return 0;
    return Number.isFinite(h) && n.height > 0 ? (h * n.width) / n.height : n.width;
  }
  protected computeMinIntrinsicWidth(h: number): number {
    return this.computeMaxIntrinsicWidth(h);
  }
  protected computeMaxIntrinsicHeight(w: number): number {
    if (this.props.height != null) return this.props.height;
    const n = this.naturalSize();
    if (!n) return 0;
    return Number.isFinite(w) && n.width > 0 ? (w * n.height) / n.width : n.height;
  }
  protected computeMinIntrinsicHeight(w: number): number {
    return this.computeMaxIntrinsicHeight(w);
  }

  viewKind(): ViewKind {
    return 'image';
  }
  viewProps(): Omit<ViewProps, 'frame'> {
    return {
      src: this.props.src ?? null,
      fit: this.props.fit ?? 'contain',
      alignment: this.props.alignment ?? null,
      alt: this.props.alt ?? null,
      tint: this.props.tint ?? null,
      semanticsLabel: this.props.semanticsLabel ?? this.props.alt ?? null,
      backgroundImage: this.props.repeat && this.props.repeat !== 'no-repeat' ? { src: this.props.src, fit: null, alignment: null, repeat: this.props.repeat } : null,
    };
  }
  handleViewEvent(event: ViewEvent): void {
    this.props.onEvent?.(event);
  }
}

// ----------------------------------------------------------------------------
// Native controls
// ----------------------------------------------------------------------------

/**
 * props: {
 *   kind: 'checkbox'|'radio'|'switch'|'slider'|'progress'|'textInput'|'select',
 *   view: Partial<ViewProps>  (value, checked, options, colors, textStyle …),
 *   width?, height?, lines?, lineHeight?, padding?: [t,r,b,l], onEvent
 * }
 */
export class RenderControl extends RenderObject {
  private kind(): ViewKind {
    return this.props.kind;
  }

  private defaultSize(c: Constraints): Size {
    const kind = this.kind();
    const view = this.props.view ?? {};
    const fillW = (fallback: number) => (Number.isFinite(c.maxWidth) ? c.maxWidth : fallback);
    switch (kind) {
      case 'checkbox':
      case 'radio':
        return { width: 48, height: 48 };
      case 'switch':
        return { width: 60, height: 48 };
      case 'slider':
        return { width: fillW(200), height: 48 };
      case 'progress':
        return view.variant === 'circular'
          ? { width: 36, height: 36 }
          : { width: fillW(200), height: view.strokeWidth ?? 4 };
      case 'textInput': {
        const ts: TextStyleSpec | null = view.textStyle ?? null;
        const fontSize = ts?.fontSize ?? 16;
        const lineH = this.props.lineHeight ?? fontSize * (ts?.height ?? 1.5);
        const lines = Math.max(1, this.props.lines ?? 1);
        const pad: [number, number, number, number] = this.props.padding ?? [12, 0, 12, 0];
        return { width: fillW(280), height: Math.ceil(lines * lineH + pad[0] + pad[2]) };
      }
      case 'select': {
        const ts: TextStyleSpec | null = view.textStyle ?? null;
        const fontSize = ts?.fontSize ?? 14;
        const lineH = Math.max(24, fontSize * (ts?.height ?? 1.3));
        const pad: [number, number, number, number] = this.props.padding ?? [0, 0, 0, 0];
        return { width: fillW(200), height: Math.ceil(lineH + pad[0] + pad[2]) };
      }
      default:
        return { width: 48, height: 48 };
    }
  }

  protected performLayout(c: Constraints): void {
    let size = this.defaultSize(c);
    const measured = this.owner?.platform.measureControl?.({ kind: this.kind(), props: this.props.view ?? {} }, c.maxWidth);
    if (measured) size = measured;
    if (this.props.width != null) size = { ...size, width: this.props.width };
    if (this.props.height != null) size = { ...size, height: this.props.height };
    this.size = constrain(c, size);
  }

  protected computeMinIntrinsicWidth(): number {
    return this.props.width ?? this.defaultSize({ minWidth: 0, maxWidth: INF, minHeight: 0, maxHeight: INF }).width;
  }
  protected computeMaxIntrinsicWidth(): number {
    return this.computeMinIntrinsicWidth();
  }
  protected computeMinIntrinsicHeight(): number {
    return this.props.height ?? this.defaultSize({ minWidth: 0, maxWidth: INF, minHeight: 0, maxHeight: INF }).height;
  }
  protected computeMaxIntrinsicHeight(): number {
    return this.computeMinIntrinsicHeight();
  }

  baseline(): number | null {
    if (this.kind() === 'textInput' || this.kind() === 'select') {
      const ts: TextStyleSpec | null = this.props.view?.textStyle ?? null;
      const pad: [number, number, number, number] = this.props.padding ?? [12, 0, 12, 0];
      return pad[0] + (ts?.fontSize ?? 16) * 0.95;
    }
    return null;
  }

  viewKind(): ViewKind {
    return this.kind();
  }
  viewProps(): Omit<ViewProps, 'frame'> {
    return { ...(this.props.view ?? {}) };
  }
  handleViewEvent(event: ViewEvent): void {
    this.props.onEvent?.(event);
    // Controlled controls (Flutter Checkbox/Switch/Slider/Radio) show the
    // guest's value, not the user's gesture, until the guest re-renders: make
    // the next frame re-assert the configured value on the native control.
    if (this.props.controlled && this.viewId != null && this.owner) {
      this.owner.compositor.invalidateProps(this.viewId, ['checked', 'value']);
    }
  }
}

// ----------------------------------------------------------------------------
// Canvas
// ----------------------------------------------------------------------------

/**
 * props: {
 *   width?, height?, background?: Color,
 *   commands?: any[]            — inline command list (Canvas / canvas)
 *   context?: { id, version, generation, commands: any[] } — cached context
 * }
 */
export class RenderCanvas extends RenderObject {
  private sentGeneration = -1;
  private sentCount = 0;
  private sentInlineKey: string | null = null;

  protected performLayout(c: Constraints): void {
    const w: number | null = this.props.width ?? null;
    const h: number | null = this.props.height ?? null;
    const b = biggest(c);
    this.size = constrain(c, {
      width: w ?? (Number.isFinite(c.maxWidth) ? b.width : 0),
      height: h ?? (Number.isFinite(c.maxHeight) ? b.height : 0),
    });
  }

  viewKind(): ViewKind {
    return 'canvas';
  }

  viewProps(): Omit<ViewProps, 'frame'> {
    const out: Omit<ViewProps, 'frame'> = { background: (this.props.background as Color | null) ?? null };
    const ctx = this.props.context as { generation: number; commands: any[]; version: number } | undefined;
    if (ctx) {
      if (ctx.generation !== this.sentGeneration) {
        out.commands = ctx.commands.slice();
        this.sentGeneration = ctx.generation;
        this.sentCount = ctx.commands.length;
      } else if (ctx.commands.length > this.sentCount) {
        out.appendCommands = ctx.commands.slice(this.sentCount);
        this.sentCount = ctx.commands.length;
      }
      out.canvasVersion = ctx.version;
      return out;
    }
    const commands: any[] = this.props.commands ?? [];
    const key = this.props.commandsKey ?? JSON.stringify(commands);
    if (key !== this.sentInlineKey) {
      out.commands = commands;
      this.sentInlineKey = key;
    }
    return out;
  }

  /** Force the next frame to resend the full command list (e.g. after re-mount). */
  resetSent(): void {
    this.sentGeneration = -1;
    this.sentCount = 0;
    this.sentInlineKey = null;
  }

  handleViewEvent(event: ViewEvent): void {
    this.props.onEvent?.(event);
  }
}

// ----------------------------------------------------------------------------
// Scene3D (embedded Godot)
// ----------------------------------------------------------------------------

/** props: { surfaceId, width, height, clickable, live, placeholder?, onEvent } */
export class RenderScene3D extends RenderObject {
  protected performLayout(c: Constraints): void {
    const w: number | null = this.props.width ?? null;
    const h: number | null = this.props.height ?? null;
    const width = w ?? (Number.isFinite(c.maxWidth) ? c.maxWidth : 300);
    const height = h ?? (Number.isFinite(c.maxHeight) ? c.maxHeight : (width * 9) / 16);
    this.size = constrain(c, { width, height });
    for (const child of this.children) {
      child.layout({ minWidth: this.size.width, maxWidth: this.size.width, minHeight: this.size.height, maxHeight: this.size.height });
      child.offset = { x: 0, y: 0 };
    }
  }
  viewKind(): ViewKind {
    return 'scene3d';
  }
  /** The placeholder child paints only when no engine is live. */
  paintsChild(): boolean {
    return !this.props.live;
  }
  viewProps(): Omit<ViewProps, 'frame'> {
    return {
      surfaceId: this.props.surfaceId,
      clickable: !!this.props.clickable,
      gestures: this.props.clickable ? ['tap'] : null,
      clip: true,
    };
  }
  handleViewEvent(event: ViewEvent): void {
    this.props.onEvent?.(event);
  }
}

// ----------------------------------------------------------------------------
// Media (video / audio)
// ----------------------------------------------------------------------------

/** props: { kind: 'video'|'audio', src, autoplay, loop, muted, controls, poster, tracks, width, height, onEvent } */
export class RenderMedia extends RenderObject {
  private aspect: number | null = null;

  protected performLayout(c: Constraints): void {
    const kind = this.props.kind === 'audio' ? 'audio' : 'video';
    const w: number | null = this.props.width ?? null;
    const h: number | null = this.props.height ?? null;
    if (kind === 'audio') {
      this.size = constrain(c, { width: w ?? (Number.isFinite(c.maxWidth) ? c.maxWidth : 300), height: h ?? 54 });
      return;
    }
    const aspect = this.aspect ?? 16 / 9;
    const width = w ?? (Number.isFinite(c.maxWidth) ? c.maxWidth : 300);
    const height = h ?? width / aspect;
    this.size = constrain(c, { width, height });
  }
  viewKind(): ViewKind {
    return this.props.kind === 'audio' ? 'audio' : 'video';
  }
  viewProps(): Omit<ViewProps, 'frame'> {
    return {
      src: this.props.src ?? null,
      autoplay: !!this.props.autoplay,
      loop: !!this.props.loop,
      muted: !!this.props.muted,
      controls: this.props.controls !== false,
      poster: this.props.poster ?? null,
      tracks: this.props.tracks ?? null,
      fit: this.props.fit ?? 'contain',
    };
  }
  handleViewEvent(event: ViewEvent): void {
    if (event.type === 'load' && event.value && typeof event.value === 'object') {
      const vw = Number(event.value.width);
      const vh = Number(event.value.height);
      if (vw > 0 && vh > 0) {
        const next = vw / vh;
        if (this.aspect == null || Math.abs(this.aspect - next) > 0.001) {
          this.aspect = next;
          this.markNeedsLayout();
        }
      }
    }
    this.props.onEvent?.(event);
  }
}

// ----------------------------------------------------------------------------
// Web content (iframe / embed / object)
// ----------------------------------------------------------------------------

/** props: { src, html, width, height, javascript, onEvent } */
export class RenderWeb extends RenderObject {
  protected performLayout(c: Constraints): void {
    const w: number | null = this.props.width ?? null;
    const h: number | null = this.props.height ?? null;
    this.size = constrain(c, {
      width: w ?? (Number.isFinite(c.maxWidth) ? c.maxWidth : 300),
      height: h ?? (Number.isFinite(c.maxHeight) ? c.maxHeight : 150),
    });
  }
  viewKind(): ViewKind {
    return 'web';
  }
  viewProps(): Omit<ViewProps, 'frame'> {
    return { src: this.props.src ?? null, html: this.props.html ?? null, javascript: this.props.javascript !== false, clip: true };
  }
  handleViewEvent(event: ViewEvent): void {
    this.props.onEvent?.(event);
  }
}

/**
 * A host-registered native component (an island). props { component,
 * componentProps, width?, height?, onEvent }. Fills bounded constraints, else
 * the platform's measured size, else its explicit size; Elpian children are
 * laid over it (server-rendered content the native component wraps).
 */
export class RenderNative extends RenderObject {
  protected performLayout(c: Constraints): void {
    const measured = this.owner?.platform.measureControl?.({ kind: 'native', props: { component: this.props.component, componentProps: this.props.componentProps ?? {} } }, c.maxWidth) ?? null;
    const w = this.props.width ?? measured?.width ?? (Number.isFinite(c.maxWidth) ? c.maxWidth : 0);
    const h = this.props.height ?? measured?.height ?? (Number.isFinite(c.maxHeight) ? c.maxHeight : 0);
    this.size = constrain(c, { width: w, height: h });
    for (const child of this.children) {
      child.layout({ minWidth: 0, maxWidth: this.size.width, minHeight: 0, maxHeight: this.size.height });
      child.offset = { x: 0, y: 0 };
    }
  }
  viewKind(): ViewKind {
    return 'native';
  }
  viewProps(): Omit<ViewProps, 'frame'> {
    return { component: this.props.component ?? null, componentProps: this.props.componentProps ?? {} };
  }
  handleViewEvent(event: ViewEvent): void {
    this.props.onEvent?.(event);
  }
}

// ----------------------------------------------------------------------------
// Gesture region
// ----------------------------------------------------------------------------

/**
 * props: {
 *   gestures: GestureKind[], ripple?, cursor?, tooltip?, focusable?, semanticsLabel?,
 *   role?, dragData?, dismissDirection?, onEvent(ViewEvent)
 * }
 * Sizes to its child (HitTestBehavior.opaque) and owns a transparent view.
 */
export class RenderGesture extends RenderProxy {
  /** A Dismissible that was swiped away collapses to nothing. */
  dismissed = false;
  collapse = 1;

  protected performLayout(c: Constraints): void {
    super.performLayout(c);
    if (this.dismissed) {
      this.size = { width: this.size.width, height: this.size.height * this.collapse };
    }
  }

  viewKind(): ViewKind {
    return 'view';
  }
  viewProps(): Omit<ViewProps, 'frame'> {
    const gestures: GestureKind[] = this.props.gestures ?? [];
    return {
      gestures: gestures.length ? gestures : null,
      ripple: this.props.ripple ?? null,
      cursor: this.props.cursor ?? null,
      tooltip: this.props.tooltip ?? null,
      focusable: this.props.focusable ? true : undefined,
      semanticsLabel: this.props.semanticsLabel ?? null,
      role: this.props.role ?? null,
      dragData: this.props.dragData,
      dismissDirection: this.props.dismissDirection ?? null,
      hidden: this.dismissed && this.collapse <= 0 ? true : undefined,
      clip: this.dismissed ? true : undefined,
    };
  }
  handleViewEvent(event: ViewEvent): void {
    this.props.onEvent?.(event, this);
  }
}
