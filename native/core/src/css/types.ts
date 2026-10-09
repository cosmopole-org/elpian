/**
 * Value types of the resolved style model. These mirror the Flutter painting
 * primitives (`EdgeInsets`, `Alignment`, `BorderSide`, `BoxShadow`, gradients,
 * `Matrix4`) so the lowering code can be written against the same vocabulary
 * as the Flutter widgets it ports.
 */
import type { Color } from './color.js';

export interface EdgeInsets {
  top: number;
  right: number;
  bottom: number;
  left: number;
}

export const EdgeInsetsZero: EdgeInsets = Object.freeze({ top: 0, right: 0, bottom: 0, left: 0 });

export function insetsAll(v: number): EdgeInsets {
  return { top: v, right: v, bottom: v, left: v };
}
export function insetsSymmetric(vertical: number, horizontal: number): EdgeInsets {
  return { top: vertical, right: horizontal, bottom: vertical, left: horizontal };
}
export function insetsOnly(o: Partial<EdgeInsets>): EdgeInsets {
  return { top: o.top ?? 0, right: o.right ?? 0, bottom: o.bottom ?? 0, left: o.left ?? 0 };
}
export const horizontalOf = (e: EdgeInsets) => e.left + e.right;
export const verticalOf = (e: EdgeInsets) => e.top + e.bottom;
export function addInsets(a: EdgeInsets, b: EdgeInsets): EdgeInsets {
  return { top: a.top + b.top, right: a.right + b.right, bottom: a.bottom + b.bottom, left: a.left + b.left };
}
export function lerpInsets(a: EdgeInsets, b: EdgeInsets, t: number): EdgeInsets {
  const l = (x: number, y: number) => x + (y - x) * t;
  return { top: l(a.top, b.top), right: l(a.right, b.right), bottom: l(a.bottom, b.bottom), left: l(a.left, b.left) };
}

/** Flutter `Alignment`: x and y in -1..1, (0,0) is the centre. */
export interface Alignment {
  x: number;
  y: number;
}

export const Align = {
  topLeft: { x: -1, y: -1 },
  topCenter: { x: 0, y: -1 },
  topRight: { x: 1, y: -1 },
  centerLeft: { x: -1, y: 0 },
  center: { x: 0, y: 0 },
  centerRight: { x: 1, y: 0 },
  bottomLeft: { x: -1, y: 1 },
  bottomCenter: { x: 0, y: 1 },
  bottomRight: { x: 1, y: 1 },
} as const satisfies Record<string, Alignment>;

export function lerpAlignment(a: Alignment, b: Alignment, t: number): Alignment {
  return { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t };
}

export interface Offset {
  dx: number;
  dy: number;
}

export type BorderStyleName = 'solid' | 'dashed' | 'dotted' | 'double' | 'none';

export interface BorderSide {
  width: number;
  color: Color;
  style: BorderStyleName;
}

export const BorderSideNone: BorderSide = Object.freeze({ width: 0, color: 0xff000000, style: 'none' });

export interface Border {
  top: BorderSide;
  right: BorderSide;
  bottom: BorderSide;
  left: BorderSide;
}

export function borderAll(side: BorderSide): Border {
  return { top: side, right: side, bottom: side, left: side };
}

export function borderInsets(b: Border | null | undefined): EdgeInsets {
  if (!b) return EdgeInsetsZero;
  const w = (s: BorderSide) => (s.style === 'none' ? 0 : s.width);
  return { top: w(b.top), right: w(b.right), bottom: w(b.bottom), left: w(b.left) };
}

/** Per-corner circular radii, Flutter `BorderRadius` (elliptical radii as x/y pairs). */
export interface BorderRadius {
  topLeft: number;
  topRight: number;
  bottomRight: number;
  bottomLeft: number;
}

export function radiusAll(r: number): BorderRadius {
  return { topLeft: r, topRight: r, bottomRight: r, bottomLeft: r };
}
export function lerpRadius(a: BorderRadius, b: BorderRadius, t: number): BorderRadius {
  const l = (x: number, y: number) => x + (y - x) * t;
  return {
    topLeft: l(a.topLeft, b.topLeft),
    topRight: l(a.topRight, b.topRight),
    bottomRight: l(a.bottomRight, b.bottomRight),
    bottomLeft: l(a.bottomLeft, b.bottomLeft),
  };
}

export interface BoxShadow {
  color: Color;
  dx: number;
  dy: number;
  blur: number;
  spread: number;
  inset?: boolean;
}

export interface TextShadow {
  color: Color;
  dx: number;
  dy: number;
  blur: number;
}

/**
 * Gradients in Flutter's vocabulary. Linear gradients run from [begin] to
 * [end] (alignments within the painted box); radial ones are centred on
 * [center] with [radius] as a fraction of the shortest side (Flutter's
 * `RadialGradient.radius`, default 0.5); sweep gradients turn around
 * [center] from [startAngle] to [endAngle] (radians).
 */
export interface Gradient {
  kind: 'linear' | 'radial' | 'sweep';
  colors: Color[];
  stops?: number[] | null;
  begin?: Alignment;
  end?: Alignment;
  center?: Alignment;
  radius?: number;
  startAngle?: number;
  endAngle?: number;
  /** CSS `repeating-*` / Flutter `TileMode.repeated`. */
  repeat?: boolean;
}

/** A 4x4 matrix in Flutter's column-major `Matrix4.storage` order. */
export type Matrix4 = number[];

export const IDENTITY: Matrix4 = Object.freeze([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]) as unknown as Matrix4;

export type Overflow = 'visible' | 'hidden' | 'clip' | 'scroll';

export type FontWeight = 100 | 200 | 300 | 400 | 500 | 600 | 700 | 800 | 900;

export type TextAlign = 'left' | 'right' | 'center' | 'justify' | 'start' | 'end';

export interface TextDecoration {
  underline: boolean;
  overline: boolean;
  lineThrough: boolean;
}

export type BoxFit = 'fill' | 'contain' | 'cover' | 'fitWidth' | 'fitHeight' | 'none' | 'scaleDown';

export type TextOverflow = 'clip' | 'ellipsis' | 'fade' | 'visible';

export interface Filter {
  blur?: number;
  brightness?: number;
  contrast?: number;
  grayscale?: number;
  hueRotate?: number;
  invert?: number;
  saturate?: number;
  sepia?: number;
  opacity?: number;
  dropShadow?: TextShadow;
}

export interface Keyframe {
  offset: number;
  styles: Record<string, unknown>;
}

/** A percentage of the parent's size, kept symbolic until layout (CSS `%`). */
export interface Percent {
  pct: number;
}

export type Length = number | Percent;

export function isPercent(v: unknown): v is Percent {
  return typeof v === 'object' && v !== null && 'pct' in (v as object);
}

export function resolveLength(v: Length | null | undefined, basis: number): number | null {
  if (v == null) return null;
  if (typeof v === 'number') return v;
  return Number.isFinite(basis) ? (v.pct / 100) * basis : null;
}
