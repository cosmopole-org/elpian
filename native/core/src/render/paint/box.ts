/**
 * Painting objects that own a plain `view`: DecoratedBox, Opacity, Transform,
 * ClipRRect/ClipOval, IgnorePointer, Visibility, filters and ShaderMask —
 * plus DefaultTextStyle, which paints nothing but provides the inherited text
 * style its descendants resolve against.
 */
import type { Color } from '../../css/color.js';
import { aboutOrigin, identity, isIdentity } from '../../css/matrix.js';
import type {
  Alignment,
  Border,
  BorderRadius,
  BoxFit,
  BoxShadow,
  Filter,
  Gradient,
  Matrix4,
} from '../../css/types.js';
import { RenderObject, RenderProxy, smallest, type Constraints } from '../object.js';
import type { TextStyle } from '../text-style.js';
import type { ViewKind, ViewProps } from '../view.js';

export interface Decoration {
  color?: Color | null;
  gradients?: Gradient[] | null;
  image?: { src: string; fit: BoxFit | null; alignment: Alignment | null; repeat: string | null; size?: { width: number | null; height: number | null } | null } | null;
  border?: Border | null;
  radius?: BorderRadius | null;
  /** Corner radii in percent of the box (CSS `border-radius: 50%`). */
  radiusPercent?: BorderRadius | null;
  shape?: 'rectangle' | 'circle' | null;
  shadows?: BoxShadow[] | null;
  outline?: { width: number; color: Color; style: string; offset: number } | null;
}

export function decorationIsEmpty(d: Decoration | null | undefined): boolean {
  if (!d) return true;
  return (
    d.color == null &&
    !(d.gradients && d.gradients.length) &&
    !d.image &&
    !d.border &&
    !d.radius &&
    !d.radiusPercent &&
    !(d.shadows && d.shadows.length) &&
    !d.outline &&
    d.shape !== 'circle'
  );
}

export function resolveRadius(d: Decoration, width: number, height: number): BorderRadius | null {
  const px = d.radius ?? null;
  const pct = d.radiusPercent ?? null;
  if (!pct) return clampRadius(px, width, height);
  const basis = Math.min(width, height);
  const r = (k: keyof BorderRadius) => (pct[k] ? (pct[k] / 100) * basis : 0) + (px ? px[k] : 0);
  return clampRadius({ topLeft: r('topLeft'), topRight: r('topRight'), bottomRight: r('bottomRight'), bottomLeft: r('bottomLeft') }, width, height);
}

/** Corners can never exceed half the shortest side (as Flutter/CSS scale them). */
function clampRadius(r: BorderRadius | null, width: number, height: number): BorderRadius | null {
  if (!r) return null;
  const max = Math.min(width, height) / 2;
  const c = (v: number) => Math.max(0, Math.min(v, max));
  const out = { topLeft: c(r.topLeft), topRight: c(r.topRight), bottomRight: c(r.bottomRight), bottomLeft: c(r.bottomLeft) };
  if (!out.topLeft && !out.topRight && !out.bottomRight && !out.bottomLeft) return null;
  return out;
}

export function decorationViewProps(d: Decoration, width: number, height: number): Omit<ViewProps, 'frame'> {
  return {
    background: d.color ?? null,
    gradients: d.gradients && d.gradients.length ? d.gradients : null,
    backgroundImage: d.image ?? null,
    border: d.border ?? null,
    radius: d.shape === 'circle' ? null : resolveRadius(d, width, height),
    oval: d.shape === 'circle' ? true : undefined,
    shadows: d.shadows && d.shadows.length ? d.shadows : null,
    outline: d.outline ?? null,
  };
}

/** props: { decoration: Decoration, clip?: boolean } */
export class RenderDecoratedBox extends RenderProxy {
  viewKind(): ViewKind {
    return 'view';
  }
  viewProps(): Omit<ViewProps, 'frame'> {
    const d: Decoration = this.props.decoration ?? {};
    return { ...decorationViewProps(d, this.size.width, this.size.height), clip: this.props.clip ? true : undefined };
  }
}

/** props: { opacity } */
export class RenderOpacity extends RenderProxy {
  viewKind(): ViewKind {
    return 'view';
  }
  viewProps(): Omit<ViewProps, 'frame'> {
    const o = this.props.opacity ?? 1;
    return { opacity: o >= 1 ? undefined : Math.max(0, o) };
  }
}

/**
 * props: { transform: Matrix4, alignment?: Alignment, origin?: [x, y] (px) }
 * The matrix is applied about the alignment point (Flutter `Transform` with
 * `alignment`), expressed to the platform as a transform + origin.
 */
export class RenderTransform extends RenderProxy {
  viewKind(): ViewKind {
    return 'view';
  }
  effectiveMatrix(): Matrix4 {
    return (this.props.transform as Matrix4 | null) ?? identity();
  }
  origin(): [number, number] {
    if (this.props.origin) return this.props.origin;
    const a: Alignment = this.props.alignment ?? { x: 0, y: 0 };
    return [(this.size.width / 2) * (1 + a.x), (this.size.height / 2) * (1 + a.y)];
  }
  viewProps(): Omit<ViewProps, 'frame'> {
    const m = this.effectiveMatrix();
    if (isIdentity(m)) return { transform: null };
    return { transform: m, transformOrigin: this.origin() };
  }
  /** The full matrix in this view's coordinate space (used for hit testing). */
  matrixInSpace(): Matrix4 {
    const [ox, oy] = this.origin();
    return aboutOrigin(this.effectiveMatrix(), ox, oy);
  }
}

/** props: { radius?: BorderRadius, oval?: boolean, enabled?: boolean } */
export class RenderClip extends RenderProxy {
  viewKind(): ViewKind {
    return 'view';
  }
  viewProps(): Omit<ViewProps, 'frame'> {
    if (this.props.enabled === false) return {};
    const r: BorderRadius | null = this.props.radius ?? null;
    return {
      clip: true,
      radius: r ? resolveRadius({ radius: r }, this.size.width, this.size.height) : null,
      oval: this.props.oval ? true : undefined,
    };
  }
}

/** props: { ignoring: boolean } */
export class RenderIgnorePointer extends RenderProxy {
  viewKind(): ViewKind {
    return 'view';
  }
  viewProps(): Omit<ViewProps, 'frame'> {
    return { pointerEvents: this.props.ignoring === false ? 'auto' : 'none' };
  }
}

/**
 * props: { mode: 'gone' | 'hidden' | 'visible' }
 * `gone` (Flutter `Visibility(visible: false)`) takes no space and paints
 * nothing; `hidden` (CSS `visibility: hidden`) keeps its space.
 */
export class RenderVisibility extends RenderObject {
  protected performLayout(c: Constraints): void {
    const child = this.child;
    if (this.props.mode === 'gone') {
      child?.layout(c);
      this.size = smallest(c);
      return;
    }
    if (child) {
      child.layout(c);
      child.offset = { x: 0, y: 0 };
      this.size = { ...child.size };
    } else this.size = smallest(c);
  }
  paintsChild(): boolean {
    return this.props.mode !== 'gone';
  }
  viewKind(): ViewKind | null {
    return this.props.mode === 'hidden' ? 'view' : null;
  }
  viewProps(): Omit<ViewProps, 'frame'> {
    return { hidden: true };
  }
}

/** props: { filter?: Filter, backdrop?: Filter, blendMode?: string, zIndex?: number } */
export class RenderFilter extends RenderProxy {
  viewKind(): ViewKind {
    return 'view';
  }
  viewProps(): Omit<ViewProps, 'frame'> {
    const f: Filter | null = this.props.filter ?? null;
    const b: Filter | null = this.props.backdrop ?? null;
    return { filter: f, backdropFilter: b, blendMode: this.props.blendMode ?? null };
  }
}

/** props: { gradient: Gradient } — ShaderMask(srcATop) as Shimmer uses it. */
export class RenderShaderMask extends RenderProxy {
  viewKind(): ViewKind {
    return 'view';
  }
  viewProps(): Omit<ViewProps, 'frame'> {
    return { shaderMask: this.props.gradient ?? null };
  }
}

/**
 * props: { style: TextStyle, textAlign?, maxLines?, overflow?, softWrap? }
 * Provides the inherited text style (Flutter `DefaultTextStyle`).
 */
export class RenderDefaultTextStyle extends RenderProxy {
  get textStyle(): TextStyle {
    return this.props.style ?? {};
  }
}
