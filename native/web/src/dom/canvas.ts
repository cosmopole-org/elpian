/**
 * Executes Elpian canvas commands on a Canvas2D context — every command type
 * of `CanvasCommandType`, with the semantics of Flutter's `CanvasAPIExecutor`
 * where it implements them (fill/stroke colours that ignore paint shaders on
 * text, globalAlpha applied per draw, shadows, clearRect) and the HTML canvas
 * semantics for the rest (arcTo, polygons, images, transforms, line dashes,
 * text alignment and baselines, colour stops, patterns, image data).
 *
 * The parameter vocabulary is documented in native/docs/canvas.md and shared
 * by the Android, iOS and Flutter painters.
 */
import { toCssColor } from '../lib.js';

type Params = Record<string, any>;
interface Cmd {
  type: string;
  params: Params;
}

interface Grad {
  kind: 'linear' | 'radial';
  colors: number[];
  stops: number[];
  x0: number;
  y0: number;
  x1: number;
  y1: number;
  r0: number;
  r1: number;
}

/** Host hooks for `custom` commands: name → painter. */
const customPainters = new Map<string, (ctx: CanvasRenderingContext2D, params: Params) => void>();
export function registerCanvasPainter(name: string, painter: (ctx: CanvasRenderingContext2D, params: Params) => void): void {
  customPainters.set(name, painter);
}

const imageCache = new Map<string, HTMLImageElement>();

function num(p: Params, k: string, d = 0): number {
  const v = p[k];
  if (typeof v === 'number' && Number.isFinite(v)) return v;
  if (typeof v === 'string') {
    const n = parseFloat(v);
    return Number.isFinite(n) ? n : d;
  }
  return d;
}

function color(v: unknown): string {
  if (typeof v === 'number') return toCssColor(v >>> 0);
  if (typeof v === 'string') return v;
  return '#000000';
}

/** Points as `[[x,y],…]`, `[{x,y},…]` or a flat `[x0,y0,x1,y1,…]`. */
export function pointsOf(v: unknown): [number, number][] {
  if (!Array.isArray(v)) return [];
  if (v.length && typeof v[0] === 'number') {
    const out: [number, number][] = [];
    for (let i = 0; i + 1 < v.length; i += 2) out.push([Number(v[i]), Number(v[i + 1])]);
    return out;
  }
  return v.map((p: any) => (Array.isArray(p) ? [Number(p[0]), Number(p[1])] : [Number(p?.x ?? 0), Number(p?.y ?? 0)]));
}

function parseFont(font: string): string {
  // Canvas fonts are CSS shorthands already; make sure a size is present.
  return /\d+(\.\d+)?(px|pt|em|rem|%)/.test(font) ? font : `${font} 10px sans-serif`.trim();
}

export class CanvasPainter {
  private readonly gradients = new Map<string, Grad>();
  private readonly patterns = new Map<string, { src: string; repetition: string }>();
  private readonly imageData = new Map<string, ImageData>();
  private path = new Path2D();
  /** The path's current point (Path2D does not expose it). */
  private cur: [number, number] = [0, 0];
  private fillStyle: string | CanvasGradient | CanvasPattern = '#000000';
  private strokeStyle: string | CanvasGradient | CanvasPattern = '#000000';
  private stack: { fill: string | CanvasGradient | CanvasPattern; stroke: string | CanvasGradient | CanvasPattern }[] = [];
  private pendingImages = 0;

  constructor(
    readonly canvas: HTMLCanvasElement,
    private readonly onImageReady: () => void,
  ) {}

  private get ctx(): CanvasRenderingContext2D {
    return this.canvas.getContext('2d')!;
  }

  /** Reset the bitmap to [w]×[h] logical px at [dpr] and the state to defaults. */
  reset(w: number, h: number, dpr: number): void {
    const cw = Math.max(1, Math.round(w * dpr));
    const ch = Math.max(1, Math.round(h * dpr));
    if (this.canvas.width !== cw) this.canvas.width = cw;
    if (this.canvas.height !== ch) this.canvas.height = ch;
    const ctx = this.ctx;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, cw, ch);
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    this.dpr = dpr;
    // Flutter's CanvasState defaults.
    ctx.globalAlpha = 1;
    ctx.globalCompositeOperation = 'source-over';
    ctx.lineWidth = 1;
    ctx.lineCap = 'butt';
    ctx.lineJoin = 'miter';
    ctx.miterLimit = 10;
    ctx.setLineDash([]);
    ctx.lineDashOffset = 0;
    ctx.shadowBlur = 0;
    ctx.shadowColor = 'rgba(0,0,0,0)';
    ctx.shadowOffsetX = 0;
    ctx.shadowOffsetY = 0;
    ctx.font = '10px sans-serif';
    ctx.textAlign = 'start';
    ctx.textBaseline = 'alphabetic';
    this.fillStyle = '#000000';
    this.strokeStyle = '#000000';
    this.stack = [];
    this.path = new Path2D();
    this.gradients.clear();
    this.patterns.clear();
  }

  private dpr = 1;

  run(commands: Cmd[]): void {
    const ctx = this.ctx;
    for (const c of commands) {
      try {
        this.exec(ctx, c.type, c.params ?? {});
      } catch (e) {
        console.warn(`Elpian canvas: ${c.type} failed`, e);
      }
    }
  }

  private exec(ctx: CanvasRenderingContext2D, type: string, p: Params): void {
    switch (type) {
      // ---- path building ----
      case 'beginPath':
        this.path = new Path2D();
        this.cur = [0, 0];
        return;
      case 'closePath':
        this.path.closePath();
        return;
      case 'moveTo':
        this.path.moveTo(num(p, 'x'), num(p, 'y'));
        this.cur = [num(p, 'x'), num(p, 'y')];
        return;
      case 'lineTo':
        this.path.lineTo(num(p, 'x'), num(p, 'y'));
        this.cur = [num(p, 'x'), num(p, 'y')];
        return;
      case 'quadraticCurveTo':
        this.path.quadraticCurveTo(num(p, 'cpx'), num(p, 'cpy'), num(p, 'x'), num(p, 'y'));
        this.cur = [num(p, 'x'), num(p, 'y')];
        return;
      case 'bezierCurveTo':
        this.path.bezierCurveTo(num(p, 'cp1x'), num(p, 'cp1y'), num(p, 'cp2x'), num(p, 'cp2y'), num(p, 'x'), num(p, 'y'));
        this.cur = [num(p, 'x'), num(p, 'y')];
        return;
      case 'arc':
        this.path.arc(num(p, 'x'), num(p, 'y'), Math.max(0, num(p, 'radius')), num(p, 'startAngle'), num(p, 'endAngle'), p.counterclockwise === true);
        this.cur = [num(p, 'x') + Math.cos(num(p, 'endAngle')) * num(p, 'radius'), num(p, 'y') + Math.sin(num(p, 'endAngle')) * num(p, 'radius')];
        return;
      case 'arcTo':
        // HTML arcTo(x1, y1, x2, y2, r); the Flutter-only shape {x, y, radius}
        // (an arc to a point) is honoured too.
        if (p.x1 != null || p.x2 != null) {
          this.path.arcTo(num(p, 'x1'), num(p, 'y1'), num(p, 'x2'), num(p, 'y2'), Math.max(0, num(p, 'radius')));
          this.cur = [num(p, 'x1'), num(p, 'y1')];
        } else this.arcToPoint(num(p, 'x'), num(p, 'y'), num(p, 'radius'), p.clockwise !== false, p.largeArc === true);
        return;
      case 'ellipse':
        this.path.ellipse(num(p, 'x'), num(p, 'y'), Math.abs(num(p, 'radiusX')), Math.abs(num(p, 'radiusY')), num(p, 'rotation'), num(p, 'startAngle', 0), num(p, 'endAngle', Math.PI * 2), p.counterclockwise === true);
        return;
      case 'rect':
        this.path.rect(num(p, 'x'), num(p, 'y'), num(p, 'width'), num(p, 'height'));
        this.cur = [num(p, 'x'), num(p, 'y')];
        return;
      case 'roundRect': {
        const r = Array.isArray(p.radii) ? p.radii.map(Number) : num(p, 'radius');
        if (typeof (this.path as any).roundRect === 'function') (this.path as any).roundRect(num(p, 'x'), num(p, 'y'), num(p, 'width'), num(p, 'height'), r);
        else this.roundRectPath(num(p, 'x'), num(p, 'y'), num(p, 'width'), num(p, 'height'), typeof r === 'number' ? r : r[0] ?? 0);
        return;
      }
      case 'circle':
        this.path.moveTo(num(p, 'x') + num(p, 'radius'), num(p, 'y'));
        this.path.arc(num(p, 'x'), num(p, 'y'), Math.max(0, num(p, 'radius')), 0, Math.PI * 2);
        return;

      // ---- painting the path ----
      case 'fill':
        ctx.fillStyle = this.fillStyle;
        ctx.fill(this.path, p.fillRule === 'evenodd' ? 'evenodd' : 'nonzero');
        return;
      case 'stroke':
        ctx.strokeStyle = this.strokeStyle;
        ctx.stroke(this.path);
        return;
      case 'clip':
        ctx.clip(this.path, p.fillRule === 'evenodd' ? 'evenodd' : 'nonzero');
        return;

      // ---- shapes ----
      case 'fillRect':
        ctx.fillStyle = this.fillStyle;
        ctx.fillRect(num(p, 'x'), num(p, 'y'), num(p, 'width'), num(p, 'height'));
        return;
      case 'strokeRect':
        ctx.strokeStyle = this.strokeStyle;
        ctx.strokeRect(num(p, 'x'), num(p, 'y'), num(p, 'width'), num(p, 'height'));
        return;
      case 'clearRect':
        ctx.clearRect(num(p, 'x'), num(p, 'y'), num(p, 'width'), num(p, 'height'));
        return;
      case 'fillCircle':
      case 'strokeCircle': {
        const c = new Path2D();
        c.arc(num(p, 'x'), num(p, 'y'), Math.max(0, num(p, 'radius')), 0, Math.PI * 2);
        if (type === 'fillCircle') {
          ctx.fillStyle = this.fillStyle;
          ctx.fill(c);
        } else {
          ctx.strokeStyle = this.strokeStyle;
          ctx.stroke(c);
        }
        return;
      }
      case 'fillPolygon':
      case 'strokePolygon': {
        const pts = pointsOf(p.points);
        if (pts.length < 2) return;
        const poly = new Path2D();
        poly.moveTo(pts[0][0], pts[0][1]);
        for (let i = 1; i < pts.length; i++) poly.lineTo(pts[i][0], pts[i][1]);
        if (p.closed !== false) poly.closePath();
        if (type === 'fillPolygon') {
          ctx.fillStyle = this.fillStyle;
          ctx.fill(poly);
        } else {
          ctx.strokeStyle = this.strokeStyle;
          ctx.stroke(poly);
        }
        return;
      }

      // ---- text ----
      case 'fillText':
      case 'strokeText': {
        const text = String(p.text ?? '');
        const maxWidth = p.maxWidth != null ? num(p, 'maxWidth') : undefined;
        if (type === 'fillText') {
          ctx.fillStyle = this.fillStyle;
          maxWidth != null ? ctx.fillText(text, num(p, 'x'), num(p, 'y'), maxWidth) : ctx.fillText(text, num(p, 'x'), num(p, 'y'));
        } else {
          ctx.strokeStyle = this.strokeStyle;
          maxWidth != null ? ctx.strokeText(text, num(p, 'x'), num(p, 'y'), maxWidth) : ctx.strokeText(text, num(p, 'x'), num(p, 'y'));
        }
        return;
      }

      // ---- images ----
      case 'drawImage':
      case 'drawImageRect': {
        const img = this.image(String(p.src ?? p.imageId ?? ''));
        if (!img) return;
        if (type === 'drawImageRect' || p.sx != null) {
          ctx.drawImage(img, num(p, 'sx'), num(p, 'sy'), num(p, 'sw', img.naturalWidth), num(p, 'sh', img.naturalHeight), num(p, 'dx', num(p, 'x')), num(p, 'dy', num(p, 'y')), num(p, 'dw', num(p, 'width', img.naturalWidth)), num(p, 'dh', num(p, 'height', img.naturalHeight)));
        } else if (p.width != null || p.height != null) {
          ctx.drawImage(img, num(p, 'x'), num(p, 'y'), num(p, 'width', img.naturalWidth), num(p, 'height', img.naturalHeight));
        } else {
          ctx.drawImage(img, num(p, 'x'), num(p, 'y'));
        }
        return;
      }

      // ---- state and transforms ----
      case 'save':
        this.stack.push({ fill: this.fillStyle, stroke: this.strokeStyle });
        ctx.save();
        return;
      case 'restore': {
        const s = this.stack.pop();
        if (s) {
          this.fillStyle = s.fill;
          this.strokeStyle = s.stroke;
        }
        ctx.restore();
        return;
      }
      case 'translate':
        ctx.translate(num(p, 'x'), num(p, 'y'));
        return;
      case 'rotate':
        ctx.rotate(num(p, 'angle'));
        return;
      case 'scale':
        ctx.scale(num(p, 'x', 1), num(p, 'y', num(p, 'x', 1)));
        return;
      case 'transform':
        ctx.transform(num(p, 'a', 1), num(p, 'b'), num(p, 'c'), num(p, 'd', 1), num(p, 'e'), num(p, 'f'));
        return;
      case 'setTransform':
        // Relative to the device-pixel base, like an HTML canvas of CSS size.
        ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
        ctx.transform(num(p, 'a', 1), num(p, 'b'), num(p, 'c'), num(p, 'd', 1), num(p, 'e'), num(p, 'f'));
        return;
      case 'resetTransform':
        ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
        return;

      // ---- styles ----
      case 'setFillStyle':
        this.fillStyle = this.style(p) ?? this.fillStyle;
        return;
      case 'setStrokeStyle':
        this.strokeStyle = this.style(p) ?? this.strokeStyle;
        return;
      case 'setLineWidth':
        ctx.lineWidth = num(p, 'width', 1);
        return;
      case 'setLineCap':
        ctx.lineCap = p.cap === 'round' || p.cap === 'square' ? p.cap : 'butt';
        return;
      case 'setLineJoin':
        ctx.lineJoin = p.join === 'round' || p.join === 'bevel' ? p.join : 'miter';
        return;
      case 'setMiterLimit':
        ctx.miterLimit = num(p, 'limit', 10);
        return;
      case 'setLineDash':
        ctx.setLineDash(Array.isArray(p.segments) ? p.segments.map(Number) : []);
        return;
      case 'setLineDashOffset':
        ctx.lineDashOffset = num(p, 'offset');
        return;
      case 'setShadowBlur':
        ctx.shadowBlur = num(p, 'blur');
        return;
      case 'setShadowColor':
        ctx.shadowColor = color(p.color);
        return;
      case 'setShadowOffsetX':
        ctx.shadowOffsetX = num(p, 'offset', num(p, 'x'));
        return;
      case 'setShadowOffsetY':
        ctx.shadowOffsetY = num(p, 'offset', num(p, 'y'));
        return;
      case 'setGlobalAlpha':
        ctx.globalAlpha = Math.max(0, Math.min(1, num(p, 'alpha', 1)));
        return;
      case 'setGlobalCompositeOperation':
        ctx.globalCompositeOperation = (p.operation as GlobalCompositeOperation) ?? 'source-over';
        return;
      case 'setFont':
        ctx.font = parseFont(String(p.font ?? '10px sans-serif'));
        return;
      case 'setTextAlign':
        ctx.textAlign = (['left', 'right', 'center', 'start', 'end'].includes(p.align) ? p.align : 'start') as CanvasTextAlign;
        return;
      case 'setTextBaseline':
        ctx.textBaseline = (['top', 'hanging', 'middle', 'alphabetic', 'ideographic', 'bottom'].includes(p.baseline) ? p.baseline : 'alphabetic') as CanvasTextBaseline;
        return;

      // ---- gradients and patterns ----
      case 'createLinearGradient':
        this.gradients.set(String(p.id), {
          kind: 'linear',
          colors: (p.colors ?? []).map((c: any) => Number(c)),
          stops: stopsOf(p),
          x0: num(p, 'x0'),
          y0: num(p, 'y0'),
          x1: num(p, 'x1'),
          y1: num(p, 'y1'),
          r0: 0,
          r1: 0,
        });
        return;
      case 'createRadialGradient':
        // Flutter shape {x, y, r} (one circle) or HTML {x0, y0, r0, x1, y1, r1}.
        this.gradients.set(String(p.id), {
          kind: 'radial',
          colors: (p.colors ?? []).map((c: any) => Number(c)),
          stops: stopsOf(p),
          x0: num(p, 'x0', num(p, 'x')),
          y0: num(p, 'y0', num(p, 'y')),
          r0: num(p, 'r0'),
          x1: num(p, 'x1', num(p, 'x')),
          y1: num(p, 'y1', num(p, 'y')),
          r1: num(p, 'r1', num(p, 'r')),
        });
        return;
      case 'addColorStop': {
        const g = this.gradients.get(String(p.gradientId ?? p.id));
        if (!g) return;
        const offset = Math.max(0, Math.min(1, num(p, 'offset')));
        const c = typeof p.color === 'number' ? p.color : 0xff000000;
        // Keep stops sorted, as CanvasGradient does.
        let i = g.stops.findIndex((s) => s > offset);
        if (i < 0) i = g.stops.length;
        g.stops.splice(i, 0, offset);
        g.colors.splice(i, 0, c);
        return;
      }
      case 'createPattern':
        this.patterns.set(String(p.id), { src: String(p.src ?? p.imageId ?? ''), repetition: String(p.repetition ?? 'repeat') });
        return;

      // ---- pixels ----
      case 'createImageData': {
        const w = Math.max(1, Math.round(num(p, 'width', 1)));
        const h = Math.max(1, Math.round(num(p, 'height', 1)));
        this.imageData.set(String(p.id), ctx.createImageData(w, h));
        return;
      }
      case 'getImageData': {
        const d = this.dpr;
        this.imageData.set(String(p.id), ctx.getImageData(num(p, 'x') * d, num(p, 'y') * d, Math.max(1, num(p, 'width', 1) * d), Math.max(1, num(p, 'height', 1) * d)));
        return;
      }
      case 'putImageData': {
        let data: ImageData | undefined = p.id != null ? this.imageData.get(String(p.id)) : undefined;
        const pixels = pixelsOf(p.data);
        if (pixels) {
          const w = Math.max(1, Math.round(num(p, 'width', data?.width ?? 1)));
          const h = Math.max(1, Math.round(num(p, 'height', data?.height ?? Math.ceil(pixels.length / 4 / w))));
          data = new ImageData(w, h);
          data.data.set(pixels.subarray(0, w * h * 4));
          if (p.id != null) this.imageData.set(String(p.id), data);
        }
        if (!data) return;
        const d = this.dpr;
        ctx.putImageData(data, num(p, 'x') * d, num(p, 'y') * d);
        return;
      }

      case 'custom': {
        const painter = customPainters.get(String(p.name ?? ''));
        if (painter) {
          ctx.save();
          painter(ctx, p);
          ctx.restore();
        }
        return;
      }
      default:
        return;
    }
  }

  private style(p: Params): string | CanvasGradient | CanvasPattern | null {
    if (p.color != null) return color(p.color);
    if (p.gradientId != null) {
      const g = this.gradients.get(String(p.gradientId));
      if (!g) return null;
      const ctx = this.ctx;
      const grad = g.kind === 'linear' ? ctx.createLinearGradient(g.x0, g.y0, g.x1, g.y1) : ctx.createRadialGradient(g.x0, g.y0, g.r0, g.x1, g.y1, Math.max(0, g.r1));
      g.colors.forEach((c, i) => grad.addColorStop(Math.max(0, Math.min(1, g.stops[i] ?? 0)), toCssColor(c >>> 0)));
      return grad;
    }
    if (p.patternId != null) {
      const pat = this.patterns.get(String(p.patternId));
      const img = pat ? this.image(pat.src) : null;
      return img ? this.ctx.createPattern(img, (pat!.repetition as any) || 'repeat') : null;
    }
    return null;
  }

  /** A decoded image, or null while it loads (the painter re-runs on load). */
  private image(src: string): HTMLImageElement | null {
    if (!src) return null;
    let img = imageCache.get(src);
    if (!img) {
      img = new Image();
      img.crossOrigin = 'anonymous';
      img.decoding = 'async';
      img.src = src;
      imageCache.set(src, img);
    }
    if (img.complete && img.naturalWidth > 0) return img;
    this.pendingImages++;
    img.addEventListener(
      'load',
      () => {
        this.pendingImages--;
        this.onImageReady();
      },
      { once: true },
    );
    return null;
  }

  /**
   * Flutter `Path.arcToPoint`: a circular arc of [radius] from the current
   * point to (x, y) — clockwise by default, the shorter arc unless [largeArc].
   * A radius too small for the chord grows to half the chord (SVG rules).
   */
  private arcToPoint(x: number, y: number, radius: number, clockwise: boolean, largeArc: boolean): void {
    const [x0, y0] = this.cur;
    const dx = x - x0;
    const dy = y - y0;
    const d = Math.hypot(dx, dy);
    if (d === 0) return;
    if (radius <= 0) {
      this.path.lineTo(x, y);
      this.cur = [x, y];
      return;
    }
    const r = Math.max(radius, d / 2);
    const h = Math.sqrt(Math.max(0, r * r - (d / 2) * (d / 2)));
    // Centre on the side that gives the requested sweep (y grows downwards).
    const sign = clockwise !== largeArc ? 1 : -1;
    const cx = (x0 + x) / 2 - (sign * h * dy) / d;
    const cy = (y0 + y) / 2 + (sign * h * dx) / d;
    const a0 = Math.atan2(y0 - cy, x0 - cx);
    const a1 = Math.atan2(y - cy, x - cx);
    this.path.arc(cx, cy, r, a0, a1, !clockwise);
    this.cur = [x, y];
  }

  private roundRectPath(x: number, y: number, w: number, h: number, r: number): void {
    const rr = Math.max(0, Math.min(r, Math.abs(w) / 2, Math.abs(h) / 2));
    this.path.moveTo(x + rr, y);
    this.path.arcTo(x + w, y, x + w, y + h, rr);
    this.path.arcTo(x + w, y + h, x, y + h, rr);
    this.path.arcTo(x, y + h, x, y, rr);
    this.path.arcTo(x, y, x + w, y, rr);
    this.path.closePath();
  }
}

function stopsOf(p: Params): number[] {
  const colors: unknown[] = Array.isArray(p.colors) ? p.colors : [];
  if (Array.isArray(p.stops) && p.stops.length === colors.length) return p.stops.map(Number);
  return colors.map((_, i) => (colors.length > 1 ? i / (colors.length - 1) : 0));
}

/** RGBA bytes from an array of numbers or a base64 string. */
function pixelsOf(data: unknown): Uint8ClampedArray | null {
  if (Array.isArray(data)) return Uint8ClampedArray.from(data.map(Number));
  if (typeof data === 'string' && data) {
    const bin = atob(data);
    const out = new Uint8ClampedArray(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  return null;
}
