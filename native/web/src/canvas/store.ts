/**
 * Canvas command model and the per-mini-app context store — a port of
 * `CanvasCommand`, `CanvasAPIExecutor`'s command list and
 * `CanvasContextStore`.
 *
 * The core never rasterises: it normalises commands (colours to ARGB,
 * defaults filled in, fonts parsed) and hands the list to the platform
 * painter (Canvas2D on the web, android.graphics.Canvas, CoreGraphics), which
 * implements the full HTML-canvas-like semantics — including the commands
 * the Flutter executor leaves unhandled (drawImage, polygons, setTransform,
 * patterns, pixel data, arcTo with tangents).
 */
import { parseColor } from '../css/color.js';

export const CANVAS_COMMAND_TYPES = [
  'moveTo', 'lineTo', 'quadraticCurveTo', 'bezierCurveTo', 'arc', 'arcTo', 'ellipse', 'rect', 'roundRect',
  'circle', 'fillRect', 'strokeRect', 'clearRect', 'fillCircle', 'strokeCircle', 'fillPolygon', 'strokePolygon',
  'fillText', 'strokeText', 'drawImage', 'drawImageRect',
  'beginPath', 'closePath', 'fill', 'stroke', 'clip',
  'save', 'restore', 'translate', 'rotate', 'scale', 'transform', 'setTransform', 'resetTransform',
  'setFillStyle', 'setStrokeStyle', 'setLineWidth', 'setLineCap', 'setLineJoin', 'setMiterLimit', 'setLineDash',
  'setLineDashOffset', 'setShadowBlur', 'setShadowColor', 'setShadowOffsetX', 'setShadowOffsetY', 'setGlobalAlpha',
  'setGlobalCompositeOperation', 'setFont', 'setTextAlign', 'setTextBaseline',
  'createLinearGradient', 'createRadialGradient', 'addColorStop', 'createPattern',
  'putImageData', 'getImageData', 'createImageData', 'custom',
] as const;
export type CanvasCommandType = (typeof CANVAS_COMMAND_TYPES)[number];

export interface CanvasCommand {
  type: CanvasCommandType;
  params: Record<string, any>;
  id?: string | null;
}

const TYPES = new Set<string>(CANVAS_COMMAND_TYPES);

export function isCanvasCommandType(name: string): name is CanvasCommandType {
  return TYPES.has(name);
}

/** `CanvasCommand.fromJson` (unknown types become `custom`). */
export function commandFromJson(json: any): CanvasCommand {
  const t = typeof json?.type === 'string' && TYPES.has(json.type) ? (json.type as CanvasCommandType) : 'custom';
  const params = json?.params && typeof json.params === 'object' ? { ...json.params } : {};
  return { type: t, params, id: json?.id ?? null };
}

const COLOR_KEYS = ['color', 'shadowColor'];

/**
 * Normalise a command for the platform painter: colours to ARGB ints (the
 * Flutter parser's rules), gradient colour lists, numeric strings to numbers.
 */
export function normalizeCommand(cmd: CanvasCommand): { type: string; params: Record<string, any>; id?: string | null } {
  const p: Record<string, any> = {};
  for (const [k, v] of Object.entries(cmd.params)) {
    if (COLOR_KEYS.includes(k)) {
      p[k] = canvasColor(v);
    } else if (k === 'colors' && Array.isArray(v)) {
      p[k] = v.map(canvasColor);
    } else if (typeof v === 'string' && /^-?\d+(\.\d+)?$/.test(v.trim()) && !['text', 'font', 'id', 'gradientId', 'patternId', 'src', 'imageId', 'data'].includes(k)) {
      p[k] = parseFloat(v);
    } else {
      p[k] = v;
    }
  }
  return cmd.id ? { type: cmd.type, params: p, id: cmd.id } : { type: cmd.type, params: p };
}

/** Canvas colours: the canvas executor's own parser (hex, rgb/rgba, ints), falling back to CSS. */
export function canvasColor(value: any): number {
  if (typeof value === 'number') return value >>> 0;
  const parsed = parseColor(value);
  return parsed ?? 0xff000000;
}

/** A cached drawing context (`canvas.ctx.*`), rendered by `CachedCanvas`. */
export class CanvasContext {
  /** Every command ever added since the last clear. */
  commands: { type: string; params: Record<string, any>; id?: string | null }[] = [];
  /** Bumped on every change (Flutter's `version` notifier). */
  version = 0;
  /** Bumped when the command list is reset (clear / resize) — painters redraw from scratch. */
  generation = 0;
  private listeners = new Set<() => void>();

  constructor(
    readonly id: string,
    public width: number,
    public height: number,
  ) {}

  setSize(w: number, h: number): void {
    if (w === this.width && h === this.height) return;
    this.width = w;
    this.height = h;
    this.generation++;
    this.changed();
  }

  addCommand(cmd: CanvasCommand): void {
    this.commands.push(normalizeCommand(cmd));
    this.changed();
  }

  addCommands(cmds: CanvasCommand[]): void {
    for (const c of cmds) this.commands.push(normalizeCommand(c));
    this.changed();
  }

  clear(): void {
    this.commands = [];
    this.generation++;
    this.changed();
  }

  onChange(fn: () => void): () => void {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  private changed(): void {
    this.version++;
    for (const l of [...this.listeners]) l();
  }

  dispose(): void {
    this.listeners.clear();
    this.commands = [];
  }
}

export class CanvasContextStore {
  private contexts = new Map<string, CanvasContext>();
  private nextId = 1;

  create(opts: { id?: string | null; width?: number; height?: number } = {}): CanvasContext {
    const id = opts.id && opts.id !== '' ? opts.id : `ctx_${this.nextId++}`;
    const existing = this.contexts.get(id);
    if (existing) return existing;
    const ctx = new CanvasContext(id, opts.width ?? 0, opts.height ?? 0);
    this.contexts.set(id, ctx);
    return ctx;
  }

  get(id: string): CanvasContext | undefined {
    return this.contexts.get(id);
  }

  dispose(id: string): void {
    const ctx = this.contexts.get(id);
    this.contexts.delete(id);
    ctx?.dispose();
  }

  clearAll(): void {
    for (const ctx of this.contexts.values()) ctx.dispose();
    this.contexts.clear();
  }
}

/** The single, context-less command list of the `canvas.*` host APIs (`CanvasAPIExecutor`). */
export class CanvasExecutor {
  commands: CanvasCommand[] = [];
  addCommand(cmd: CanvasCommand): void {
    this.commands.push(cmd);
  }
  addCommands(cmds: CanvasCommand[]): void {
    this.commands.push(...cmds);
  }
  clear(): void {
    this.commands = [];
  }
}

/** Parse a CSS-ish canvas font (`bold italic 16px Arial`), as `_ParsedFont.parse` does. */
export function parseCanvasFont(font: string): { size: number; family: string; bold: boolean; italic: boolean } {
  let size = 10;
  let family = 'sans-serif';
  const parts = font.split(' ');
  for (let i = 0; i < parts.length; i++) {
    const part = parts[i];
    if (part.endsWith('px')) size = parseFloat(part) || 10;
    else if (!part.includes('bold') && !part.includes('italic') && part.trim() !== '' && !/^\d{3}$/.test(part)) {
      family = parts.slice(i).join(' ');
      break;
    }
  }
  return { size, family, bold: /bold|[6-9]00/.test(font), italic: font.includes('italic') };
}
