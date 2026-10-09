/**
 * Applies the core's view operations to the DOM.
 *
 * Every view is an absolutely positioned element at the frame the core laid
 * out. A view's decoration (background, gradients, image, border, radius,
 * shadows) lives on its own layer so the frame of the element stays the
 * border box Flutter lays children out in, and clipping applies to children
 * without clipping the view's own shadow — Flutter's Container + ClipRRect.
 * Leaf kinds map onto native browser elements: paragraphs, <img>, <input>,
 * <textarea>, <select>, <progress>, <canvas>, <video>, <audio>, <iframe>, the
 * Godot export's canvas, and host-registered native components.
 */
import { ROOT_VIEW_ID, toCssColor, type ViewEvent, type ViewKind, type ViewOp, type ViewProps } from '../lib.js';
import { CanvasPainter } from './canvas.js';
import { applyBorder, blendCss, boxShadowCss, css, filterCss, fontFamilyCss, gradientCss, px, radiusCss, round, spanStyle } from './css.js';
import { GestureRecognizer } from './gestures.js';
import { fillParagraph, paragraphStyle } from './text.js';

export interface NativeComponentInstance {
  element: HTMLElement;
  update?(props: Record<string, any>): void;
  dispose?(): void;
}
export type NativeComponentFactory = (props: Record<string, any>, emit: (type: string, value?: unknown) => void) => NativeComponentInstance;
const nativeComponents = new Map<string, NativeComponentFactory>();

/** Register a native island component (`ServerComponent` native islands, `native` views). */
export function registerNativeComponent(name: string, factory: NativeComponentFactory): void {
  nativeComponents.set(name, factory);
}

interface Rec {
  id: number;
  kind: ViewKind;
  el: HTMLElement;
  deco: HTMLElement | null;
  /** Where children are inserted (the element, a clip layer, or scroll content). */
  host: HTMLElement;
  props: ViewProps;
  children: number[];
  parent: number;
  gestures: GestureRecognizer | null;
  leaf: any;
  painter?: CanvasPainter;
  dispose?: () => void;
}

export interface RendererHooks {
  emit(event: ViewEvent): void;
  imageLoaded(src: string, width: number, height: number): void;
  godotSurface?(surfaceId: number): HTMLElement | null;
}

export class DomRenderer {
  private readonly views = new Map<number, Rec>();
  private shaderDefs: SVGSVGElement | null = null;
  private dpr = 1;

  constructor(
    readonly root: HTMLElement,
    private readonly hooks: RendererHooks,
  ) {
    if (getComputedStyle(root).position === 'static') root.style.position = 'relative';
    root.style.overflow = root.style.overflow || 'hidden';
    this.views.set(ROOT_VIEW_ID, { id: ROOT_VIEW_ID, kind: 'view', el: root, deco: null, host: root, props: { frame: [0, 0, 0, 0] }, children: [], parent: -1, gestures: null, leaf: null });
  }

  apply(ops: ViewOp[], dpr: number): void {
    this.dpr = dpr;
    for (const op of ops) {
      try {
        switch (op.op) {
          case 'create':
            this.create(op.id, op.kind, op.parent, op.index, op.props);
            break;
          case 'update':
            this.update(op.id, op.props);
            break;
          case 'move':
            this.move(op.id, op.parent, op.index);
            break;
          case 'remove':
            this.remove(op.id);
            break;
          case 'command':
            this.command(op.id, op.name, op.args);
            break;
        }
      } catch (e) {
        console.error('Elpian renderer: op failed', op, e);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Tree
  // ---------------------------------------------------------------------------

  private create(id: number, kind: ViewKind, parent: number, index: number, props: ViewProps): void {
    const el = document.createElement(kind === 'text' ? 'div' : 'div');
    el.style.position = 'absolute';
    el.style.boxSizing = 'border-box';
    el.style.margin = '0';
    const rec: Rec = { id, kind, el, deco: null, host: el, props: { frame: [0, 0, 0, 0] }, children: [], parent, gestures: null, leaf: null };
    this.views.set(id, rec);
    this.buildLeaf(rec);
    this.insert(rec, parent, index);
    this.update(id, props);
  }

  private insert(rec: Rec, parent: number, index: number): void {
    const p = this.views.get(parent) ?? this.views.get(ROOT_VIEW_ID)!;
    rec.parent = p.id;
    const list = p.children.filter((c) => c !== rec.id);
    const i = Math.max(0, Math.min(index, list.length));
    list.splice(i, 0, rec.id);
    p.children = list;
    const next = list[i + 1] != null ? this.views.get(list[i + 1])?.el ?? null : null;
    p.host.insertBefore(rec.el, next && next.parentNode === p.host ? next : null);
  }

  private move(id: number, parent: number, index: number): void {
    const rec = this.views.get(id);
    if (!rec) return;
    const old = this.views.get(rec.parent);
    if (old) old.children = old.children.filter((c) => c !== id);
    this.insert(rec, parent, index);
  }

  private remove(id: number): void {
    const rec = this.views.get(id);
    if (!rec) return;
    const parent = this.views.get(rec.parent);
    if (parent) parent.children = parent.children.filter((c) => c !== id);
    this.disposeTree(rec);
    rec.el.remove();
  }

  private disposeTree(rec: Rec): void {
    for (const c of rec.children) {
      const child = this.views.get(c);
      if (child) this.disposeTree(child);
    }
    rec.gestures?.dispose();
    rec.dispose?.();
    this.views.delete(rec.id);
  }

  clear(): void {
    const root = this.views.get(ROOT_VIEW_ID)!;
    for (const c of [...root.children]) this.remove(c);
    this.shaderDefs?.remove();
    this.shaderDefs = null;
  }

  // ---------------------------------------------------------------------------
  // Leaves
  // ---------------------------------------------------------------------------

  private emit(rec: Rec, e: Omit<ViewEvent, 'id'>): void {
    this.hooks.emit({ id: rec.id, ...e } as ViewEvent);
  }

  private buildLeaf(rec: Rec): void {
    const el = rec.el;
    switch (rec.kind) {
      case 'text': {
        const p = document.createElement('div');
        p.style.position = 'absolute';
        p.style.left = '0';
        p.style.top = '0';
        p.addEventListener('click', (e) => {
          const link = (e.target as HTMLElement).closest('[data-link]') as HTMLElement | null;
          if (link) {
            e.stopPropagation();
            this.emit(rec, { type: 'link', value: link.dataset.link });
          }
        });
        el.appendChild(p);
        rec.leaf = p;
        return;
      }
      case 'image': {
        const img = document.createElement('img');
        img.draggable = false;
        img.decoding = 'async';
        img.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;display:block';
        img.addEventListener('load', () => {
          this.hooks.imageLoaded(img.currentSrc || img.src, img.naturalWidth, img.naturalHeight);
          if (rec.props.src) this.hooks.imageLoaded(rec.props.src, img.naturalWidth, img.naturalHeight);
          this.emit(rec, { type: 'load', value: { width: img.naturalWidth, height: img.naturalHeight } });
        });
        img.addEventListener('error', () => {
          if (rec.props.src) this.hooks.imageLoaded(rec.props.src, 0, 0);
          this.emit(rec, { type: 'error' });
        });
        el.appendChild(img);
        rec.leaf = img;
        return;
      }
      case 'scroll': {
        el.style.overflow = 'auto';
        (el.style as any).webkitOverflowScrolling = 'touch';
        el.style.overscrollBehavior = 'contain';
        const content = document.createElement('div');
        content.style.cssText = 'position:relative;margin:0;padding:0';
        el.appendChild(content);
        rec.host = content;
        let raf = 0;
        el.addEventListener('scroll', () => {
          if (raf) return;
          raf = requestAnimationFrame(() => {
            raf = 0;
            this.emit(rec, { type: 'scroll', scrollX: el.scrollLeft, scrollY: el.scrollTop });
          });
        });
        return;
      }
      case 'textInput':
        return this.buildTextInput(rec);
      case 'checkbox':
      case 'radio':
      case 'switch':
        return this.buildToggle(rec);
      case 'slider': {
        const input = document.createElement('input');
        input.type = 'range';
        input.style.cssText = 'position:absolute;left:0;top:50%;transform:translateY(-50%);width:100%;margin:0;cursor:pointer';
        input.addEventListener('input', () => this.emit(rec, { type: 'input', value: Number(input.value) }));
        input.addEventListener('change', () => this.emit(rec, { type: 'change', value: Number(input.value) }));
        el.appendChild(input);
        rec.leaf = input;
        return;
      }
      case 'select': {
        const sel = document.createElement('select');
        sel.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;border:none;outline:none;background:transparent;cursor:pointer;appearance:auto';
        sel.addEventListener('change', () => this.emit(rec, { type: 'change', value: sel.value }));
        sel.addEventListener('focus', () => this.emit(rec, { type: 'focus' }));
        sel.addEventListener('blur', () => this.emit(rec, { type: 'blur' }));
        el.appendChild(sel);
        rec.leaf = sel;
        return;
      }
      case 'progress':
        rec.leaf = null; // built per variant in applyLeaf
        return;
      case 'canvas': {
        const canvas = document.createElement('canvas');
        canvas.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;display:block';
        el.appendChild(canvas);
        rec.leaf = canvas;
        rec.painter = new CanvasPainter(canvas, () => this.repaintCanvas(rec));
        for (const t of ['pointerdown', 'pointermove', 'pointerup'] as const) {
          canvas.addEventListener(t, (e) => {
            const r = canvas.getBoundingClientRect();
            this.emit(rec, { type: t, localX: e.clientX - r.left, localY: e.clientY - r.top, x: e.clientX - this.root.getBoundingClientRect().left, y: e.clientY - this.root.getBoundingClientRect().top, pointerId: e.pointerId, buttons: e.buttons });
          });
        }
        return;
      }
      case 'scene3d':
        // Taps come from the gesture recognizer (`gestures: ['tap']` when clickable).
        return;
      case 'video':
      case 'audio': {
        const media = document.createElement(rec.kind);
        media.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;display:block;background:' + (rec.kind === 'video' ? '#000' : 'transparent');
        media.setAttribute("playsinline", "");
        media.addEventListener('loadedmetadata', () =>
          this.emit(rec, { type: 'load', value: { width: (media as HTMLVideoElement).videoWidth ?? 0, height: (media as HTMLVideoElement).videoHeight ?? 0, duration: media.duration } }),
        );
        for (const t of ['play', 'pause', 'ended', 'error', 'volumechange', 'seeked'] as const) media.addEventListener(t, () => this.emit(rec, { type: t, value: { currentTime: media.currentTime, duration: media.duration, volume: media.volume, muted: media.muted } }));
        let last = 0;
        media.addEventListener('timeupdate', () => {
          const now = performance.now();
          if (now - last < 250) return;
          last = now;
          this.emit(rec, { type: 'timeupdate', value: { currentTime: media.currentTime, duration: media.duration } });
        });
        el.appendChild(media);
        rec.leaf = media;
        return;
      }
      case 'web': {
        const frame = document.createElement('iframe');
        frame.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;border:0;display:block';
        frame.setAttribute('referrerpolicy', 'no-referrer');
        frame.addEventListener('load', () => this.emit(rec, { type: 'load' }));
        el.appendChild(frame);
        rec.leaf = frame;
        return;
      }
      case 'native':
        rec.leaf = null; // created when the component name is known
        return;
      default:
        return;
    }
  }

  private buildTextInput(rec: Rec): void {
    const wrap = document.createElement('div');
    wrap.style.cssText = 'position:absolute;inset:0;box-sizing:border-box;display:flex;align-items:stretch';
    rec.el.appendChild(wrap);
    rec.leaf = { wrap, input: null as HTMLInputElement | HTMLTextAreaElement | null, list: null as HTMLDataListElement | null, multiline: null as boolean | null };
  }

  private ensureInput(rec: Rec, multiline: boolean): HTMLInputElement | HTMLTextAreaElement {
    const leaf = rec.leaf;
    if (leaf.input && leaf.multiline === multiline) return leaf.input;
    leaf.input?.remove();
    const input: HTMLInputElement | HTMLTextAreaElement = multiline ? document.createElement('textarea') : document.createElement('input');
    input.style.cssText = 'flex:1;min-width:0;border:none;outline:none;background:transparent;margin:0;padding:0;font:inherit;color:inherit;resize:none;box-sizing:border-box';
    input.addEventListener('input', () => this.emit(rec, { type: 'input', value: input.value }));
    input.addEventListener('change', () => this.emit(rec, { type: 'change', value: input.value }));
    input.addEventListener('focus', () => {
      leaf.focused = true;
      this.applyInputChrome(rec);
      this.emit(rec, { type: 'focus' });
    });
    input.addEventListener('blur', () => {
      leaf.focused = false;
      this.applyInputChrome(rec);
      this.emit(rec, { type: 'blur' });
    });
    input.addEventListener('keydown', (e) => {
      const ke = e as KeyboardEvent;
      this.emit(rec, { type: 'keydown', key: ke.key, keyCode: ke.keyCode, altKey: ke.altKey, ctrlKey: ke.ctrlKey, shiftKey: ke.shiftKey, metaKey: ke.metaKey });
      if (ke.key === 'Enter' && !multiline) this.emit(rec, { type: 'submit', value: input.value });
    });
    const pattern = rec.props.inputType === 'number' ? /[^0-9.\-eE+]/g : null;
    if (pattern) input.addEventListener('beforeinput', (e) => {
      const d = (e as InputEvent).data;
      if (d && pattern.test(d)) e.preventDefault();
      pattern.lastIndex = 0;
    });
    leaf.wrap.appendChild(input);
    leaf.input = input;
    leaf.multiline = multiline;
    return input;
  }

  private applyInputChrome(rec: Rec): void {
    const p = rec.props;
    const leaf = rec.leaf;
    const colors = p.colors ?? {};
    const radius = Number((colors as any).radius ?? 4);
    const focused = !!leaf.focused;
    const border = focused ? colors.focusedBorder ?? colors.border : colors.border;
    const width = focused ? Number((colors as any).focusedBorderWidth ?? 2) : 1;
    const w = leaf.wrap.style;
    w.background = colors.fill != null ? css(colors.fill) : 'transparent';
    const variant = p.variant ?? 'outline';
    if (variant === 'underline') {
      w.border = 'none';
      w.borderBottom = border != null ? `${width}px solid ${css(border)}` : 'none';
      w.borderRadius = `${radius}px ${radius}px 0 0`;
    } else if (variant === 'none') {
      w.border = 'none';
    } else {
      w.border = border != null ? `${width}px solid ${css(border)}` : 'none';
      w.borderRadius = `${radius}px`;
    }
    const cp = p.contentPadding ?? [12, 12, 12, 12];
    // Keep the text from shifting when the border thickens on focus.
    const inset = width - 1;
    w.padding = `${cp[0] - inset}px ${cp[1] - inset}px ${cp[2] - inset}px ${cp[3] - inset}px`;
    if (leaf.input) leaf.input.style.caretColor = colors.cursor != null ? css(colors.cursor) : '';
  }

  private buildToggle(rec: Rec): void {
    const input = document.createElement('input');
    input.type = rec.kind === 'radio' ? 'radio' : 'checkbox';
    if (rec.kind === 'switch') input.setAttribute('role', 'switch');
    input.style.cssText = 'position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);margin:0;cursor:pointer';
    input.addEventListener('change', () => {
      this.emit(rec, { type: 'change', value: rec.kind === 'radio' ? rec.props.value ?? true : input.checked });
    });
    if (rec.kind === 'switch') {
      // A Material 3 switch: 52×32 track with a 16/24/28 px thumb.
      input.style.opacity = '0';
      input.style.width = '100%';
      input.style.height = '100%';
      input.style.zIndex = '1';
      const track = document.createElement('div');
      track.style.cssText = 'position:absolute;left:50%;top:50%;width:52px;height:32px;margin:-16px 0 0 -26px;border-radius:16px;box-sizing:border-box;transition:background 150ms, border-color 150ms';
      const thumb = document.createElement('div');
      thumb.style.cssText = 'position:absolute;top:50%;border-radius:50%;transition:left 150ms, width 150ms, height 150ms, background 150ms';
      track.appendChild(thumb);
      rec.el.appendChild(track);
      rec.leaf = { input, track, thumb };
    } else {
      input.style.width = '18px';
      input.style.height = '18px';
      rec.leaf = { input };
    }
    rec.el.appendChild(input);
  }

  // ---------------------------------------------------------------------------
  // Props
  // ---------------------------------------------------------------------------

  private update(id: number, patch: Partial<ViewProps>): void {
    const rec = this.views.get(id);
    if (!rec) return;
    const prev = rec.props;
    const next: ViewProps = { ...prev, ...patch };
    rec.props = next;
    const el = rec.el;
    const s = el.style;
    const has = (k: keyof ViewProps) => Object.prototype.hasOwnProperty.call(patch, k);
    const frameChanged = has('frame');

    if (frameChanged) {
      const [x, y, w, h] = next.frame;
      s.left = px(x);
      s.top = px(y);
      s.width = px(w);
      s.height = px(h);
    }

    if (has('opacity')) s.opacity = next.opacity == null || next.opacity >= 1 ? '' : String(round(next.opacity));
    if (has('transform') || has('transformOrigin')) {
      const m = next.transform;
      s.transform = m ? `matrix3d(${m.map((v) => round(v)).join(',')})` : '';
      const o = next.transformOrigin;
      s.transformOrigin = o ? `${px(o[0])} ${px(o[1])}` : '0 0';
    }
    if (has('hidden')) s.visibility = next.hidden ? 'hidden' : '';
    if (has('pointerEvents')) s.pointerEvents = next.pointerEvents === 'none' ? 'none' : '';
    if (has('cursor')) s.cursor = next.cursor ?? '';
    if (has('zIndex')) s.zIndex = next.zIndex != null ? String(next.zIndex) : '';
    if (has('filter') || has('shaderMask') || frameChanged) this.applyFilter(rec);
    if (has('backdropFilter')) {
      const f = filterCss(next.backdropFilter);
      (s as any).backdropFilter = f;
      (s as any).webkitBackdropFilter = f;
    }
    if (has('blendMode')) s.mixBlendMode = blendCss(next.blendMode);
    if (has('semanticsLabel')) next.semanticsLabel ? el.setAttribute('aria-label', next.semanticsLabel) : el.removeAttribute('aria-label');
    if (has('role')) next.role ? el.setAttribute('role', next.role) : el.removeAttribute('role');

    const decoKeys: (keyof ViewProps)[] = ['background', 'gradients', 'backgroundImage', 'border', 'radius', 'oval', 'shadows', 'outline'];
    if (decoKeys.some(has) || (frameChanged && (next.gradients?.length || next.backgroundImage))) this.applyDecoration(rec);
    if (has('clip') || has('radius') || has('oval')) this.applyClip(rec);

    if (has('gestures') || has('ripple') || has('tooltip') || has('dragData') || has('dismissDirection') || has('focusable')) this.applyGestures(rec);

    this.applyLeaf(rec, patch, frameChanged);
  }

  private applyDecoration(rec: Rec): void {
    const p = rec.props;
    const needs = p.background != null || (p.gradients && p.gradients.length) || p.backgroundImage || p.border || (p.shadows && p.shadows.length) || p.outline;
    if (!needs) {
      if (rec.deco) {
        rec.deco.remove();
        rec.deco = null;
      }
      return;
    }
    if (!rec.deco) {
      const d = document.createElement('div');
      d.style.cssText = 'position:absolute;inset:0;box-sizing:border-box;pointer-events:none';
      rec.el.insertBefore(d, rec.el.firstChild);
      rec.deco = d;
    }
    const s = rec.deco.style;
    const [, , w, h] = p.frame;
    s.backgroundColor = p.background != null ? css(p.background) : '';
    const layers: string[] = [];
    const sizes: string[] = [];
    const positions: string[] = [];
    const repeats: string[] = [];
    // CSS paints the first layer on top; Flutter's list is bottom-first.
    for (const g of [...(p.gradients ?? [])].reverse()) {
      layers.push(gradientCss(g, w, h));
      sizes.push('100% 100%');
      positions.push('0 0');
      repeats.push('no-repeat');
    }
    const bi = p.backgroundImage;
    if (bi) {
      layers.push(`url(${JSON.stringify(bi.src)})`);
      sizes.push(bi.size && (bi.size.width != null || bi.size.height != null) ? `${bi.size.width != null ? px(bi.size.width) : 'auto'} ${bi.size.height != null ? px(bi.size.height) : 'auto'}` : fitToBackgroundSize(bi.fit));
      const a = bi.alignment ?? { x: 0, y: 0 };
      positions.push(`${round(((a.x + 1) / 2) * 100)}% ${round(((a.y + 1) / 2) * 100)}%`);
      repeats.push(bi.repeat ?? 'no-repeat');
    }
    s.backgroundImage = layers.join(', ');
    s.backgroundSize = sizes.join(', ');
    s.backgroundPosition = positions.join(', ');
    s.backgroundRepeat = repeats.join(', ');
    applyBorder(s, p.border);
    s.borderRadius = p.oval ? '50%' : radiusCss(p.radius);
    s.boxShadow = boxShadowCss(p.shadows);
    if (p.outline) {
      s.outline = `${px(p.outline.width)} ${p.outline.style} ${css(p.outline.color)}`;
      s.outlineOffset = px(p.outline.offset);
    } else s.outline = '';
  }

  private applyClip(rec: Rec): void {
    const p = rec.props;
    if (rec.kind === 'scroll') {
      rec.el.style.borderRadius = p.oval ? '50%' : radiusCss(p.radius);
      return;
    }
    if (!p.clip) {
      if (rec.host !== rec.el) {
        // Move children back onto the element.
        const clipLayer = rec.host;
        while (clipLayer.firstChild) rec.el.appendChild(clipLayer.firstChild);
        clipLayer.remove();
        rec.host = rec.el;
      }
      return;
    }
    if (rec.host === rec.el) {
      const layer = document.createElement('div');
      layer.style.cssText = 'position:absolute;inset:0;overflow:hidden';
      const keep = new Set<Node>([rec.deco as Node].filter(Boolean));
      for (const child of [...rec.el.childNodes]) if (!keep.has(child) && this.isChildView(rec, child)) layer.appendChild(child);
      rec.el.appendChild(layer);
      rec.host = layer;
    }
    rec.host.style.borderRadius = p.oval ? '50%' : radiusCss(p.radius);
  }

  private isChildView(rec: Rec, node: Node): boolean {
    return rec.children.some((c) => this.views.get(c)?.el === node);
  }

  private applyFilter(rec: Rec): void {
    const p = rec.props;
    const parts: string[] = [];
    const f = filterCss(p.filter);
    if (f) parts.push(f);
    if (p.shaderMask) parts.push(`url(#${this.shaderMaskFilter(rec)})`);
    rec.el.style.filter = parts.join(' ');
  }

  /**
   * ShaderMask(srcATop): the gradient replaces the colour of the content
   * while keeping its alpha — an SVG filter compositing a gradient image atop
   * the source graphic.
   */
  private shaderMaskFilter(rec: Rec): string {
    if (!this.shaderDefs) {
      const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
      svg.setAttribute('width', '0');
      svg.setAttribute('height', '0');
      svg.style.position = 'absolute';
      this.root.appendChild(svg);
      this.shaderDefs = svg;
    }
    const id = `elpian-mask-${rec.id}`;
    let filter = this.shaderDefs.querySelector(`#${id}`) as SVGFilterElement | null;
    if (!filter) {
      filter = document.createElementNS('http://www.w3.org/2000/svg', 'filter');
      filter.setAttribute('id', id);
      filter.setAttribute('x', '0');
      filter.setAttribute('y', '0');
      filter.setAttribute('width', '1');
      filter.setAttribute('height', '1');
      filter.setAttribute('color-interpolation-filters', 'sRGB');
      const img = document.createElementNS('http://www.w3.org/2000/svg', 'feImage');
      img.setAttribute('result', 'shader');
      img.setAttribute('preserveAspectRatio', 'none');
      const comp = document.createElementNS('http://www.w3.org/2000/svg', 'feComposite');
      comp.setAttribute('in', 'shader');
      comp.setAttribute('in2', 'SourceGraphic');
      comp.setAttribute('operator', 'atop');
      filter.append(img, comp);
      this.shaderDefs.appendChild(filter);
      const prev = rec.dispose;
      rec.dispose = () => {
        prev?.();
        filter?.remove();
      };
    }
    const [, , w, h] = rec.props.frame;
    const g = rec.props.shaderMask!;
    const svgImage = `<svg xmlns="http://www.w3.org/2000/svg" width="${round(w)}" height="${round(h)}"><foreignObject width="100%" height="100%"><div xmlns="http://www.w3.org/1999/xhtml" style="width:${round(w)}px;height:${round(h)}px;background:${gradientCss(g, w, h).replace(/"/g, "'")}"></div></foreignObject></svg>`;
    const fe = filter.querySelector('feImage')!;
    fe.setAttribute('href', `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svgImage)}`);
    fe.setAttribute('width', String(round(w)));
    fe.setAttribute('height', String(round(h)));
    return id;
  }

  private applyGestures(rec: Rec): void {
    const p = rec.props;
    const kinds = p.gestures ?? [];
    const wants = kinds.length > 0 || p.ripple != null || p.tooltip != null;
    if (!wants) {
      if (rec.gestures) {
        rec.gestures.dispose();
        rec.gestures = null;
      }
      return;
    }
    if (!rec.gestures) rec.gestures = new GestureRecognizer(rec.el, rec.id, { emit: (e) => this.hooks.emit(e), root: () => this.root });
    const g = rec.gestures;
    g.dismissDirection = p.dismissDirection ?? 'horizontal';
    g.dragData = p.dragData;
    g.tooltip = p.tooltip ?? null;
    g.ripple = p.ripple != null ? css(p.ripple) : null;
    g.configure(kinds);
    if (p.focusable && !rec.el.hasAttribute('tabindex')) rec.el.tabIndex = 0;
  }

  // ---------------------------------------------------------------------------
  // Leaf props
  // ---------------------------------------------------------------------------

  private applyLeaf(rec: Rec, patch: Partial<ViewProps>, frameChanged: boolean): void {
    const p = rec.props;
    const has = (k: keyof ViewProps) => Object.prototype.hasOwnProperty.call(patch, k);
    switch (rec.kind) {
      case 'text': {
        const para = rec.leaf as HTMLElement;
        if (has('text') && p.text) {
          para.setAttribute('style', paragraphStyle(p.text, p.frame[2]) + ';position:absolute;left:0;top:0');
          fillParagraph(para, p.text);
        } else if (frameChanged && p.text) {
          para.style.width = px(p.frame[2]);
        }
        return;
      }
      case 'image': {
        const img = rec.leaf as HTMLImageElement;
        if (has('src') && p.src && img.getAttribute('src') !== p.src) img.src = p.src;
        if (has('fit') || has('alignment') || frameChanged) {
          const fit = p.fit ?? 'contain';
          img.style.objectFit = fit === 'fill' ? 'fill' : fit === 'cover' ? 'cover' : fit === 'none' ? 'none' : fit === 'scaleDown' ? 'scale-down' : 'contain';
          if (fit === 'fitWidth' || fit === 'fitHeight') {
            // Scale to one axis and overflow the other (clipped by the view).
            img.style.objectFit = 'cover';
            const nw = img.naturalWidth || 1;
            const nh = img.naturalHeight || 1;
            const [, , w, h] = p.frame;
            const coverByWidth = w / nw >= h / nh;
            if ((fit === 'fitWidth') !== coverByWidth) img.style.objectFit = 'contain';
          }
          const a = p.alignment ?? { x: 0, y: 0 };
          img.style.objectPosition = `${round(((a.x + 1) / 2) * 100)}% ${round(((a.y + 1) / 2) * 100)}%`;
        }
        if (has('alt')) img.alt = p.alt ?? '';
        if (has('tint') || has('src')) {
          // Image.color with BlendMode.srcIn: paint the tint through the image's alpha.
          if (p.tint != null && p.src) {
            img.style.visibility = 'hidden';
            let mask = rec.el.querySelector(':scope > .elpian-tint') as HTMLElement | null;
            if (!mask) {
              mask = document.createElement('div');
              mask.className = 'elpian-tint';
              mask.style.cssText = 'position:absolute;inset:0;pointer-events:none';
              rec.el.appendChild(mask);
            }
            const url = `url(${JSON.stringify(p.src)})`;
            mask.style.background = css(p.tint);
            mask.style.maskImage = url;
            (mask.style as any).webkitMaskImage = url;
            mask.style.maskSize = 'contain';
            (mask.style as any).webkitMaskSize = 'contain';
            mask.style.maskRepeat = 'no-repeat';
            (mask.style as any).webkitMaskRepeat = 'no-repeat';
            mask.style.maskPosition = 'center';
            (mask.style as any).webkitMaskPosition = 'center';
          } else {
            img.style.visibility = '';
            rec.el.querySelector(':scope > .elpian-tint')?.remove();
          }
        }
        return;
      }
      case 'scroll': {
        const el = rec.el;
        const content = rec.host;
        if (has('contentSize') && p.contentSize) {
          content.style.width = px(p.contentSize[0]);
          content.style.height = px(p.contentSize[1]);
        }
        if (has('scrollAxis') || has('scrollEnabled')) {
          const enabled = p.scrollEnabled !== false;
          const axis = p.scrollAxis ?? 'vertical';
          el.style.overflowX = enabled && axis !== 'vertical' ? 'auto' : 'hidden';
          el.style.overflowY = enabled && axis !== 'horizontal' ? 'auto' : 'hidden';
        }
        if (has('showScrollbar')) el.style.scrollbarWidth = p.showScrollbar === false ? 'none' : '';
        if (p.scrollTo && has('scrollTo')) el.scrollTo({ left: p.scrollTo[0], top: p.scrollTo[1] });
        return;
      }
      case 'textInput': {
        const multiline = !!p.multiline;
        const input = this.ensureInput(rec, multiline);
        if (has('value') && input.value !== String(p.value ?? '')) input.value = String(p.value ?? '');
        if (has('placeholder')) input.placeholder = p.placeholder ?? '';
        if (!multiline && (has('inputType') || has('multiline'))) {
          const t = p.inputType ?? 'text';
          (input as HTMLInputElement).type = ['password', 'email', 'tel', 'url', 'search', 'number', 'date', 'time', 'datetime-local', 'month', 'week', 'color'].includes(t) ? (t === 'number' ? 'text' : t) : 'text';
          if (t === 'number') input.inputMode = 'decimal';
          else if (t === 'email') input.inputMode = 'email';
          else if (t === 'tel') input.inputMode = 'tel';
          else if (t === 'url') input.inputMode = 'url';
          else input.inputMode = '';
        }
        if (has('enabled')) input.disabled = p.enabled === false;
        if (has('readOnly')) input.readOnly = !!p.readOnly;
        if (has('maxLength')) p.maxLength != null ? (input.maxLength = p.maxLength) : input.removeAttribute('maxlength');
        if (multiline && (has('minLines') || has('maxLines'))) (input as HTMLTextAreaElement).rows = p.minLines ?? p.maxLines ?? 3;
        if (has('autofocus') && p.autofocus) requestAnimationFrame(() => input.focus());
        if (has('min')) p.min != null ? input.setAttribute('min', String(p.min)) : input.removeAttribute('min');
        if (has('max')) p.max != null ? input.setAttribute('max', String(p.max)) : input.removeAttribute('max');
        if (has('textStyle') && p.textStyle) {
          input.setAttribute('style', input.getAttribute('style')!.replace(/;?color:[^;]*|;?font[^;]*|;?letter-spacing:[^;]*|;?line-height:[^;]*/g, '') + ';' + spanStyle(p.textStyle).replace(/position:relative;top:[^;]*/, ''));
          input.style.background = 'transparent';
        }
        if (has('hintStyle') && p.hintStyle) {
          const id = `elpian-hint-${rec.id}`;
          input.id = id;
          let style = rec.el.querySelector('style') as HTMLStyleElement | null;
          if (!style) {
            style = document.createElement('style');
            rec.el.appendChild(style);
          }
          style.textContent = `#${id}::placeholder{color:${css(p.hintStyle.color)};opacity:1;font-size:${px(p.hintStyle.fontSize)};font-family:${fontFamilyCss(p.hintStyle.fontFamily)}}`;
        }
        if (has('suggestions')) {
          const leaf = rec.leaf;
          if (p.suggestions && p.suggestions.length) {
            if (!leaf.list) {
              leaf.list = document.createElement('datalist');
              leaf.list.id = `elpian-list-${rec.id}`;
              rec.el.appendChild(leaf.list);
            }
            leaf.list.textContent = '';
            for (const v of p.suggestions) {
              const o = document.createElement('option');
              o.value = v;
              leaf.list.appendChild(o);
            }
            input.setAttribute('list', leaf.list.id);
          } else {
            input.removeAttribute('list');
            leaf.list?.remove();
            leaf.list = null;
          }
        }
        if (has('colors') || has('variant') || has('contentPadding')) this.applyInputChrome(rec);
        if (multiline) input.style.alignSelf = 'stretch';
        return;
      }
      case 'checkbox':
      case 'radio':
      case 'switch': {
        const { input, track, thumb } = rec.leaf;
        if (has('checked')) input.checked = !!p.checked;
        if (has('enabled')) input.disabled = p.enabled === false;
        const colors = p.colors ?? {};
        if (rec.kind !== 'switch') {
          if (colors.fill != null) input.style.accentColor = css(colors.fill);
          input.style.opacity = p.enabled === false ? '0.38' : '';
          return;
        }
        // Material 3 switch colours.
        const on = !!p.checked;
        const active = colors.active ?? colors.fill ?? 0xff6750a4;
        const thumbOn = colors.thumb ?? 0xffffffff;
        const trackOff = colors.inactiveTrack ?? 0xffe6e0e9;
        const outline = colors.border ?? 0xff79747e;
        track.style.background = css(on ? active : trackOff);
        track.style.border = on ? '2px solid transparent' : `2px solid ${css(outline)}`;
        const size = on ? 24 : 16;
        thumb.style.width = thumb.style.height = `${size}px`;
        thumb.style.marginTop = `${-size / 2}px`;
        thumb.style.left = on ? `${52 - 4 - size - 2}px` : `${6}px`;
        thumb.style.background = css(on ? thumbOn : colors.inactiveThumb ?? outline);
        track.style.opacity = p.enabled === false ? '0.38' : '';
        return;
      }
      case 'slider': {
        const input = rec.leaf as HTMLInputElement;
        if (has('min')) input.min = String(p.min ?? 0);
        if (has('max')) input.max = String(p.max ?? 1);
        if (has('step')) input.step = p.step != null && p.step > 0 ? String(p.step) : 'any';
        if (has('value') && Number(input.value) !== Number(p.value)) input.value = String(p.value ?? 0);
        if (has('enabled')) input.disabled = p.enabled === false;
        if (has('colors') && p.colors?.active != null) input.style.accentColor = css(p.colors.active);
        return;
      }
      case 'select': {
        const sel = rec.leaf as HTMLSelectElement;
        if (has('options')) {
          sel.textContent = '';
          let group: HTMLOptGroupElement | null = null;
          if (p.placeholder && !(p.options ?? []).some((o) => o.value === p.value)) {
            const ph = document.createElement('option');
            ph.value = '';
            ph.textContent = p.placeholder;
            ph.disabled = true;
            ph.selected = true;
            sel.appendChild(ph);
          }
          for (const o of p.options ?? []) {
            const opt = document.createElement('option');
            opt.value = o.value;
            opt.textContent = o.label;
            opt.disabled = !!o.disabled;
            if (o.group) {
              if (!group || group.label !== o.group) {
                group = document.createElement('optgroup');
                group.label = o.group;
                sel.appendChild(group);
              }
              group.appendChild(opt);
            } else {
              group = null;
              sel.appendChild(opt);
            }
          }
        }
        if ((has('value') || has('options')) && p.value != null) sel.value = String(p.value);
        if (has('enabled')) sel.disabled = p.enabled === false;
        if (has('textStyle') && p.textStyle) {
          sel.style.color = css(p.textStyle.color);
          sel.style.fontSize = px(p.textStyle.fontSize);
          sel.style.fontFamily = fontFamilyCss(p.textStyle.fontFamily);
          sel.style.fontWeight = String(p.textStyle.fontWeight);
        }
        if (has('colors') && p.colors) {
          if (p.colors.menu != null) sel.style.backgroundColor = css(p.colors.menu);
          if (p.colors.text != null) sel.style.color = css(p.colors.text);
        }
        if (has('contentPadding') && p.contentPadding) sel.style.padding = p.contentPadding.map((v) => px(v)).join(' ');
        return;
      }
      case 'progress':
        return this.applyProgress(rec, has);
      case 'canvas': {
        const painter = rec.painter!;
        const [, , w, h] = p.frame;
        if (has('background')) (rec.leaf as HTMLCanvasElement).style.background = p.background != null ? css(p.background) : '';
        if (has('commands') && p.commands) {
          rec.leaf.__commands = p.commands.slice();
          painter.reset(w, h, this.dpr);
          painter.run(p.commands);
        } else if (frameChanged && rec.leaf.__commands) {
          painter.reset(w, h, this.dpr);
          painter.run(rec.leaf.__commands);
        }
        if (has('appendCommands') && p.appendCommands) {
          (rec.leaf.__commands ??= []).push(...p.appendCommands);
          painter.run(p.appendCommands);
        }
        return;
      }
      case 'scene3d': {
        if (has('surfaceId') && p.surfaceId != null) {
          const surface = this.hooks.godotSurface?.(p.surfaceId) ?? null;
          if (surface && surface.parentNode !== rec.el) {
            surface.style.position = 'absolute';
            surface.style.inset = '0';
            rec.el.insertBefore(surface, rec.el.firstChild);
          }
        }
        rec.el.style.cursor = p.clickable ? 'pointer' : '';
        return;
      }
      case 'video':
      case 'audio': {
        const m = rec.leaf as HTMLMediaElement;
        if (has('src') && p.src && m.getAttribute('src') !== p.src) m.src = p.src;
        if (has('autoplay')) m.autoplay = !!p.autoplay;
        if (has('loop')) m.loop = !!p.loop;
        if (has('muted')) m.muted = !!p.muted;
        if (has('controls')) m.controls = p.controls !== false;
        if (has('poster') && rec.kind === 'video') (m as HTMLVideoElement).poster = p.poster ?? '';
        if (has('fit') && rec.kind === 'video') m.style.objectFit = p.fit === 'cover' ? 'cover' : p.fit === 'fill' ? 'fill' : p.fit === 'none' ? 'none' : 'contain';
        if (has('tracks')) {
          for (const t of [...m.querySelectorAll('track')]) t.remove();
          for (const t of p.tracks ?? []) {
            const tr = document.createElement('track');
            tr.src = t.src;
            tr.kind = t.kind as TextTrackKind;
            if (t.srclang) tr.srclang = t.srclang;
            if (t.label) tr.label = t.label;
            tr.default = t.default;
            m.appendChild(tr);
          }
        }
        return;
      }
      case 'web': {
        const f = rec.leaf as HTMLIFrameElement;
        if (has('javascript')) {
          if (p.javascript === false) f.setAttribute('sandbox', 'allow-same-origin allow-popups allow-forms');
          else f.setAttribute('sandbox', 'allow-scripts allow-same-origin allow-popups allow-forms');
        }
        if (has('html') && p.html != null) f.srcdoc = p.html;
        else if (has('src') && p.src && f.getAttribute('src') !== p.src) f.src = p.src;
        return;
      }
      case 'native': {
        if (has('component') && p.component) {
          rec.leaf?.dispose?.();
          rec.leaf?.element?.remove();
          const factory = nativeComponents.get(p.component);
          if (!factory) {
            console.warn(`Elpian: no native component registered as "${p.component}"`);
            rec.leaf = null;
            return;
          }
          const inst = factory(p.componentProps ?? {}, (type, value) => this.emit(rec, { type, value }));
          inst.element.style.position = 'absolute';
          inst.element.style.inset = '0';
          rec.el.insertBefore(inst.element, rec.el.firstChild);
          rec.leaf = inst;
          rec.dispose = () => inst.dispose?.();
        } else if (has('componentProps') && rec.leaf) {
          rec.leaf.update?.(p.componentProps ?? {});
        }
        return;
      }
      default:
        return;
    }
  }

  private applyProgress(rec: Rec, has: (k: keyof ViewProps) => boolean): void {
    const p = rec.props;
    const circular = p.variant === 'circular';
    const colors = p.colors ?? {};
    const indicator = colors.indicator != null ? css(colors.indicator) : css(0xff6750a4);
    const track = colors.track != null ? css(colors.track) : 'transparent';
    const value: number | null = typeof p.value === 'number' ? Math.max(0, Math.min(1, p.value)) : null;
    if (!rec.leaf || rec.leaf.circular !== circular) {
      rec.el.textContent = '';
      if (circular) {
        const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
        svg.setAttribute('viewBox', '0 0 36 36');
        svg.style.cssText = 'position:absolute;inset:0;width:100%;height:100%;overflow:visible';
        const bg = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
        const fg = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
        for (const c of [bg, fg]) {
          c.setAttribute('cx', '18');
          c.setAttribute('cy', '18');
          c.setAttribute('fill', 'none');
        }
        fg.setAttribute('transform', 'rotate(-90 18 18)');
        svg.append(bg, fg);
        rec.el.appendChild(svg);
        rec.leaf = { circular, svg, bg, fg };
      } else {
        const bar = document.createElement('div');
        bar.style.cssText = 'position:absolute;inset:0;overflow:hidden';
        const fill = document.createElement('div');
        fill.style.cssText = 'position:absolute;top:0;bottom:0;left:0';
        bar.appendChild(fill);
        rec.el.appendChild(bar);
        rec.leaf = { circular, bar, fill };
      }
      rec.el.setAttribute('role', 'progressbar');
    }
    void has;
    if (value != null) rec.el.setAttribute('aria-valuenow', String(Math.round(value * 100)));
    else rec.el.removeAttribute('aria-valuenow');
    if (circular) {
      const { svg, bg, fg } = rec.leaf;
      const stroke = p.strokeWidth ?? 4;
      const size = Math.min(p.frame[2], p.frame[3]) || 36;
      const sw = (stroke / size) * 36;
      const r = 18 - sw / 2;
      const circ = 2 * Math.PI * r;
      for (const c of [bg, fg]) {
        c.setAttribute('r', String(round(r)));
        c.setAttribute('stroke-width', String(round(sw)));
      }
      bg.setAttribute('stroke', track);
      fg.setAttribute('stroke', indicator);
      fg.setAttribute('stroke-linecap', 'butt');
      if (value != null) {
        svg.style.animation = '';
        fg.style.animation = '';
        fg.setAttribute('stroke-dasharray', `${round(circ * value)} ${round(circ)}`);
      } else {
        ensureKeyframes();
        fg.setAttribute('stroke-dasharray', `${round(circ * 0.25)} ${round(circ)}`);
        svg.style.animation = 'elpian-spin 1.4s linear infinite';
        fg.style.animation = 'elpian-dash 1.4s ease-in-out infinite';
        fg.style.setProperty('--elpian-circ', String(round(circ)));
      }
    } else {
      const { bar, fill } = rec.leaf;
      bar.style.background = track;
      fill.style.background = indicator;
      bar.style.borderRadius = '0';
      if (value != null) {
        fill.style.animation = '';
        fill.style.left = '0';
        fill.style.width = `${round(value * 100)}%`;
      } else {
        ensureKeyframes();
        fill.style.width = '40%';
        fill.style.animation = 'elpian-indeterminate 1.8s cubic-bezier(0.4,0,0.2,1) infinite';
      }
    }
  }

  private repaintCanvas(rec: Rec): void {
    const cmds = rec.leaf?.__commands;
    if (!cmds || !rec.painter) return;
    const [, , w, h] = rec.props.frame;
    rec.painter.reset(w, h, this.dpr);
    rec.painter.run(cmds);
  }

  private command(id: number, name: string, args: any): void {
    const rec = this.views.get(id);
    if (!rec) return;
    switch (name) {
      case 'focus': {
        const input: HTMLElement | null = rec.leaf?.input ?? (rec.leaf instanceof HTMLElement ? rec.leaf : null);
        (input ?? rec.el).focus();
        return;
      }
      case 'blur':
        (rec.leaf?.input ?? rec.el).blur?.();
        return;
      case 'play':
        void (rec.leaf as HTMLMediaElement)?.play?.();
        return;
      case 'pause':
        (rec.leaf as HTMLMediaElement)?.pause?.();
        return;
      case 'seek':
        if (rec.leaf && typeof args === 'number') (rec.leaf as HTMLMediaElement).currentTime = args;
        return;
      case 'scrollTo':
        if (Array.isArray(args)) rec.el.scrollTo({ left: args[0], top: args[1], behavior: 'smooth' });
        return;
    }
  }

  /** Re-run every canvas (DPR change). */
  repaintAll(dpr: number): void {
    this.dpr = dpr;
    for (const rec of this.views.values()) if (rec.kind === 'canvas') this.repaintCanvas(rec);
  }
}

function fitToBackgroundSize(fit: string | null | undefined): string {
  switch (fit) {
    case 'cover':
      return 'cover';
    case 'contain':
      return 'contain';
    case 'fill':
      return '100% 100%';
    case 'fitWidth':
      return '100% auto';
    case 'fitHeight':
      return 'auto 100%';
    case 'scaleDown':
      return 'contain';
    default:
      return 'auto';
  }
}

let keyframesInstalled = false;
function ensureKeyframes(): void {
  if (keyframesInstalled) return;
  keyframesInstalled = true;
  const style = document.createElement('style');
  style.textContent = `
@keyframes elpian-spin { to { transform: rotate(360deg); } }
@keyframes elpian-dash {
  0% { stroke-dasharray: 1 200; stroke-dashoffset: 0; }
  50% { stroke-dasharray: 60 200; stroke-dashoffset: -10; }
  100% { stroke-dasharray: 60 200; stroke-dashoffset: -80; }
}
@keyframes elpian-indeterminate { 0% { left: -40%; } 100% { left: 100%; } }`;
  document.head.appendChild(style);
}

export { toCssColor };
