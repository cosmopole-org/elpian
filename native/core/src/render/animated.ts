/**
 * Animated render objects.
 *
 * Implicit animations (Flutter `AnimatedContainer`, `AnimatedOpacity`,
 * `AnimatedPadding`, `AnimatedAlign`, `AnimatedPositioned`, `AnimatedScale`,
 * `AnimatedRotation`, `AnimatedSlide`, `AnimatedSize`,
 * `AnimatedDefaultTextStyle`, `AnimatedCrossFade`, `AnimatedSwitcher`, plus
 * CSS transitions) animate from the current value whenever a re-render
 * changes the target. Explicit animations (`FadeTransition`,
 * `SlideTransition`, `ScaleTransition`, `RotationTransition`,
 * `SizeTransition`, `TweenAnimationBuilder`, `StaggeredAnimation`, `Shimmer`,
 * `Pulse`, `AnimatedGradient`, CSS `@keyframes`) run their own controller from
 * the moment they mount.
 *
 * All of them tick on the owner's frame clock; only paint props change on
 * most frames (opacity / transform / colours), so the platform animates them
 * without relayout.
 */
import { lerpColor, type Color } from '../css/color.js';
import { identity, multiply, rotationZ, scaling, translation, lerpMatrix, aboutOrigin } from '../css/matrix.js';
import { CSSParser } from '../css/parser.js';
import {
  lerpAlignment,
  lerpInsets,
  lerpRadius,
  type Alignment,
  type BorderRadius,
  type EdgeInsets,
  type Gradient,
  type Keyframe,
  type Matrix4,
} from '../css/types.js';
import { AnimationController, ImplicitValue, lerpNumber, type Lerp } from '../animation/controller.js';
import { Curves, curveByName, interval, type Curve } from '../animation/curves.js';
import { deepEqual } from '../util/json.js';
import { RenderAlign, RenderConstrainedBox, RenderPadding } from './layout/basic.js';
import { RenderPositioned } from './layout/stack.js';
import { INF, RenderObject, RenderProxy, constrain, type Constraints } from './object.js';
import { RenderDecoratedBox, RenderDefaultTextStyle, RenderOpacity, RenderShaderMask, RenderTransform, decorationViewProps, type Decoration } from './paint/box.js';
import type { RenderOwner } from './owner.js';
import type { TextStyle } from './text-style.js';
import type { ViewKind, ViewProps } from './view.js';

function curveOf(props: Record<string, any>, fallback: Curve = Curves.linear): Curve {
  const c = props.curve;
  if (typeof c === 'function') return c;
  return curveByName(c, fallback);
}

const eq = (a: any, b: any) => deepEqual(a, b);

function lerpNullable(a: number | null, b: number | null, t: number): number | null {
  if (a == null || b == null) return t < 0.5 ? a : b;
  return a + (b - a) * t;
}

// ============================================================================
// Implicit
// ============================================================================

/** props: padding, percent, duration, curve */
export class RenderAnimatedPadding extends RenderPadding {
  private value!: ImplicitValue<EdgeInsets>;
  init(props: Record<string, any>): void {
    super.init(props);
    this.value = new ImplicitValue<EdgeInsets>(props.padding ?? { top: 0, right: 0, bottom: 0, left: 0 }, lerpInsets, eq, () => this.markNeedsLayout());
  }
  protected didUpdate(): void {
    this.value.set(this.props.padding ?? { top: 0, right: 0, bottom: 0, left: 0 }, this.props.duration, curveOf(this.props), this.owner);
  }
  resolvedPadding(c: Constraints | null): EdgeInsets {
    const saved = this.props.padding;
    this.props.padding = this.value.current;
    const out = super.resolvedPadding(c);
    this.props.padding = saved;
    return out;
  }
  protected onDetach(): void {
    this.value.dispose();
  }
}

/** props: alignment, widthFactor, heightFactor, duration, curve */
export class RenderAnimatedAlign extends RenderAlign {
  private value!: ImplicitValue<Alignment>;
  init(props: Record<string, any>): void {
    super.init(props);
    this.value = new ImplicitValue<Alignment>(props.alignment ?? { x: 0, y: 0 }, lerpAlignment, eq, () => this.markNeedsLayout());
  }
  protected didUpdate(): void {
    this.value.set(this.props.alignment ?? { x: 0, y: 0 }, this.props.duration, curveOf(this.props), this.owner);
  }
  protected performLayout(c: Constraints): void {
    const saved = this.props.alignment;
    this.props.alignment = this.value.current;
    super.performLayout(c);
    this.props.alignment = saved;
  }
  protected onDetach(): void {
    this.value.dispose();
  }
}

/** props: opacity, duration, curve */
export class RenderAnimatedOpacity extends RenderOpacity {
  private value!: ImplicitValue<number>;
  init(props: Record<string, any>): void {
    super.init(props);
    this.value = new ImplicitValue<number>(props.opacity ?? 1, lerpNumber, (a, b) => a === b, () => this.markNeedsPaint());
  }
  protected didUpdate(): void {
    this.value.set(this.props.opacity ?? 1, this.props.duration, curveOf(this.props), this.owner);
  }
  viewProps(): Omit<ViewProps, 'frame'> {
    const o = this.value.current;
    return { opacity: o >= 1 ? undefined : Math.max(0, o) };
  }
  protected onDetach(): void {
    this.value.dispose();
  }
}

interface TransformTarget {
  scale: number;
  turns: number;
  slideX: number;
  slideY: number;
  tx: number;
  ty: number;
  base: Matrix4;
}

const lerpTransformTarget: Lerp<TransformTarget> = (a, b, t) => ({
  scale: lerpNumber(a.scale, b.scale, t),
  turns: lerpNumber(a.turns, b.turns, t),
  slideX: lerpNumber(a.slideX, b.slideX, t),
  slideY: lerpNumber(a.slideY, b.slideY, t),
  tx: lerpNumber(a.tx, b.tx, t),
  ty: lerpNumber(a.ty, b.ty, t),
  base: lerpMatrix(a.base, b.base, t),
});

/**
 * AnimatedScale / AnimatedRotation / AnimatedSlide / CSS transform transitions.
 * props: { scale, turns, slide: [x, y] (fractions of size), translate: [x, y] px,
 *          transform: Matrix4, alignment, duration, curve }
 */
export class RenderAnimatedTransform extends RenderTransform {
  private value!: ImplicitValue<TransformTarget>;
  private targetOf(p: Record<string, any>): TransformTarget {
    return {
      scale: p.scale ?? 1,
      turns: p.turns ?? 0,
      slideX: p.slide?.[0] ?? 0,
      slideY: p.slide?.[1] ?? 0,
      tx: p.translate?.[0] ?? 0,
      ty: p.translate?.[1] ?? 0,
      base: p.transform ?? identity(),
    };
  }
  init(props: Record<string, any>): void {
    super.init(props);
    this.value = new ImplicitValue<TransformTarget>(this.targetOf(props), lerpTransformTarget, eq, () => this.markNeedsPaint());
  }
  protected didUpdate(): void {
    this.value.set(this.targetOf(this.props), this.props.duration, curveOf(this.props), this.owner);
  }
  effectiveMatrix(): Matrix4 {
    const v = this.value.current;
    let m = v.base;
    if (v.slideX || v.slideY || v.tx || v.ty) {
      m = multiply(translation(v.slideX * this.size.width + v.tx, v.slideY * this.size.height + v.ty), m);
    }
    if (v.turns) m = multiply(m, rotationZ(v.turns * Math.PI * 2));
    if (v.scale !== 1) m = multiply(m, scaling(v.scale, v.scale, 1));
    return m;
  }
  protected onDetach(): void {
    this.value.dispose();
  }
}

interface BoxTarget {
  width: number | null;
  height: number | null;
}

/** AnimatedContainer's size: props minWidth…maxHeight, width, height, duration, curve */
export class RenderAnimatedConstrained extends RenderConstrainedBox {
  private value!: ImplicitValue<BoxTarget>;
  init(props: Record<string, any>): void {
    super.init(props);
    this.value = new ImplicitValue<BoxTarget>(
      { width: props.width ?? null, height: props.height ?? null },
      (a, b, t) => ({ width: lerpNullable(a.width, b.width, t), height: lerpNullable(a.height, b.height, t) }),
      eq,
      () => this.markNeedsLayout(),
    );
  }
  protected didUpdate(): void {
    this.value.set({ width: this.props.width ?? null, height: this.props.height ?? null }, this.props.duration, curveOf(this.props), this.owner);
  }
  additional(): Constraints {
    const saved = { w: this.props.width, h: this.props.height };
    this.props.width = this.value.current.width;
    this.props.height = this.value.current.height;
    const out = super.additional();
    this.props.width = saved.w;
    this.props.height = saved.h;
    return out;
  }
  protected onDetach(): void {
    this.value.dispose();
  }
}

interface DecorationTarget {
  color: Color | null;
  radius: BorderRadius | null;
  borderColor: Color | null;
  borderWidth: number;
}

/** AnimatedContainer's decoration: colour, radius and uniform border animate. */
export class RenderAnimatedDecorated extends RenderDecoratedBox {
  private value!: ImplicitValue<DecorationTarget>;
  private targetOf(d: Decoration | undefined): DecorationTarget {
    return {
      color: d?.color ?? null,
      radius: d?.radius ?? null,
      borderColor: d?.border?.top.color ?? null,
      borderWidth: d?.border?.top.width ?? 0,
    };
  }
  init(props: Record<string, any>): void {
    super.init(props);
    this.value = new ImplicitValue<DecorationTarget>(
      this.targetOf(props.decoration),
      (a, b, t) => ({
        color: a.color == null || b.color == null ? (t < 0.5 ? a.color : b.color) : lerpColor(a.color, b.color, t),
        radius: a.radius && b.radius ? lerpRadius(a.radius, b.radius, t) : t < 0.5 ? a.radius : b.radius,
        borderColor: a.borderColor == null || b.borderColor == null ? (t < 0.5 ? a.borderColor : b.borderColor) : lerpColor(a.borderColor, b.borderColor, t),
        borderWidth: lerpNumber(a.borderWidth, b.borderWidth, t),
      }),
      eq,
      () => this.markNeedsPaint(),
    );
  }
  protected didUpdate(): void {
    this.value.set(this.targetOf(this.props.decoration), this.props.duration, curveOf(this.props), this.owner);
  }
  viewProps(): Omit<ViewProps, 'frame'> {
    const d: Decoration = { ...(this.props.decoration ?? {}) };
    const v = this.value.current;
    d.color = v.color;
    d.radius = v.radius;
    if (d.border && v.borderColor != null) {
      const side = (s: any) => ({ ...s, color: v.borderColor, width: s.style === 'none' ? s.width : v.borderWidth });
      d.border = { top: side(d.border.top), right: side(d.border.right), bottom: side(d.border.bottom), left: side(d.border.left) };
    }
    return decorationViewProps(d, this.size.width, this.size.height);
  }
  protected onDetach(): void {
    this.value.dispose();
  }
}

interface PosTarget {
  top: number | null;
  right: number | null;
  bottom: number | null;
  left: number | null;
  width: number | null;
  height: number | null;
}

/** AnimatedPositioned. */
export class RenderAnimatedPositioned extends RenderPositioned {
  private value!: ImplicitValue<PosTarget>;
  private targetOf(p: Record<string, any>): PosTarget {
    return { top: p.top ?? null, right: p.right ?? null, bottom: p.bottom ?? null, left: p.left ?? null, width: p.width ?? null, height: p.height ?? null };
  }
  init(props: Record<string, any>): void {
    super.init(props);
    this.value = new ImplicitValue<PosTarget>(
      this.targetOf(props),
      (a, b, t) => ({
        top: lerpNullable(a.top, b.top, t),
        right: lerpNullable(a.right, b.right, t),
        bottom: lerpNullable(a.bottom, b.bottom, t),
        left: lerpNullable(a.left, b.left, t),
        width: lerpNullable(a.width, b.width, t),
        height: lerpNullable(a.height, b.height, t),
      }),
      eq,
      () => this.markNeedsLayout(),
    );
    Object.assign(this.props, this.value.current);
  }
  protected didUpdate(): void {
    const target = this.targetOf(this.props);
    this.value.set(target, this.props.duration, curveOf(this.props), this.owner);
    Object.assign(this.props, this.value.current);
  }
  protected performLayout(c: Constraints): void {
    Object.assign(this.props, this.value.current);
    super.performLayout(c);
  }
  markNeedsLayout(): void {
    if (this.value) Object.assign(this.props, this.value.current);
    super.markNeedsLayout();
  }
  protected onDetach(): void {
    this.value.dispose();
  }
}

const lerpTextStyle: Lerp<TextStyle> = (a, b, t) => {
  const out: TextStyle = { ...(t < 0.5 ? a : b) };
  if (a.color != null && b.color != null) out.color = lerpColor(a.color, b.color, t);
  for (const k of ['fontSize', 'letterSpacing', 'wordSpacing', 'height'] as const) {
    const x = a[k];
    const y = b[k];
    if (x != null && y != null) (out as any)[k] = x + (y - x) * t;
  }
  if (a.fontWeight != null && b.fontWeight != null) out.fontWeight = Math.round((a.fontWeight + (b.fontWeight - a.fontWeight) * t) / 100) * 100;
  return out;
};

/** AnimatedDefaultTextStyle: props style, duration, curve. */
export class RenderAnimatedDefaultTextStyle extends RenderDefaultTextStyle {
  private value!: ImplicitValue<TextStyle>;
  init(props: Record<string, any>): void {
    super.init(props);
    this.value = new ImplicitValue<TextStyle>(props.style ?? {}, lerpTextStyle, eq, () => this.markDescendantsDirty());
  }
  protected didUpdate(): void {
    this.value.set(this.props.style ?? {}, this.props.duration, curveOf(this.props), this.owner);
  }
  get textStyle(): TextStyle {
    return this.value.current;
  }
  private markDescendantsDirty(): void {
    this.visit((ro) => {
      if (ro.type === 'text') ro.markNeedsLayout();
    });
  }
  protected performLayout(c: Constraints): void {
    const saved = this.props.style;
    this.props.style = this.value.current;
    super.performLayout(c);
    this.props.style = saved;
  }
  protected onDetach(): void {
    this.value.dispose();
  }
}

/** AnimatedSize: animates its own size towards the child's. props duration, curve, alignment */
export class RenderAnimatedSize extends RenderObject {
  private controller: AnimationController | null = null;
  private fromSize = { width: 0, height: 0 };
  private toSize: { width: number; height: number } | null = null;
  private hasLaidOut = false;

  protected performLayout(c: Constraints): void {
    const child = this.child;
    if (!child) {
      this.size = constrain(c, { width: 0, height: 0 });
      return;
    }
    child.layout(c);
    const target = { ...child.size };
    if (!this.hasLaidOut || !this.props.duration) {
      this.hasLaidOut = true;
      this.toSize = target;
      this.fromSize = target;
      this.size = constrain(c, target);
    } else if (this.toSize && (target.width !== this.toSize.width || target.height !== this.toSize.height)) {
      this.fromSize = { ...this.size };
      this.toSize = target;
      if (!this.controller) {
        this.controller = new AnimationController(this.props.duration);
        this.controller.addListener(() => this.markNeedsLayout());
      }
      this.controller.duration = this.props.duration;
      if (this.owner) this.controller.attach(this.owner);
      void this.controller.forward(0);
    }
    const t = this.controller?.isAnimating ? curveOf(this.props)(this.controller.value) : 1;
    const to = this.toSize ?? target;
    this.size = constrain(c, {
      width: this.fromSize.width + (to.width - this.fromSize.width) * t,
      height: this.fromSize.height + (to.height - this.fromSize.height) * t,
    });
    const a: Alignment = this.props.alignment ?? { x: 0, y: 0 };
    child.offset = { x: ((this.size.width - child.size.width) / 2) * (1 + a.x), y: ((this.size.height - child.size.height) / 2) * (1 + a.y) };
  }
  viewKind(): ViewKind {
    return 'view';
  }
  viewProps(): Omit<ViewProps, 'frame'> {
    return { clip: true };
  }
  protected onDetach(): void {
    this.controller?.detach();
    this.controller?.stop();
  }
}

/**
 * AnimatedCrossFade: props { showFirst, duration, curve } with exactly two
 * children (each an opacity holder created by lowering).
 */
export class RenderAnimatedCrossFade extends RenderObject {
  private controller: AnimationController | null = null;

  init(props: Record<string, any>): void {
    super.init(props);
  }

  protected onAttach(): void {
    if (!this.controller) {
      this.controller = new AnimationController(this.props.duration ?? 300, this.props.showFirst === false ? 1 : 0);
      this.controller.addListener(() => this.markNeedsLayout());
    }
    this.controller.attach(this.owner!);
  }

  protected didUpdate(old: Record<string, any>): void {
    if (!this.controller) return;
    this.controller.duration = this.props.duration ?? 300;
    if ((old.showFirst !== false) !== (this.props.showFirst !== false)) {
      if (this.props.showFirst === false) void this.controller.forward();
      else void this.controller.reverse();
    }
  }

  private get t(): number {
    const v = this.controller?.value ?? (this.props.showFirst === false ? 1 : 0);
    return curveOf(this.props)(v);
  }

  protected performLayout(c: Constraints): void {
    const [first, second] = this.children;
    const inner: Constraints = { minWidth: 0, maxWidth: c.maxWidth, minHeight: 0, maxHeight: c.maxHeight };
    first?.layout(inner);
    second?.layout(inner);
    const t = this.t;
    const a = first?.size ?? { width: 0, height: 0 };
    const b = second?.size ?? { width: 0, height: 0 };
    this.size = constrain(c, { width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t });
    if (first) {
      first.offset = { x: 0, y: 0 };
      first.props.opacity = 1 - t;
      first.markNeedsPaint();
    }
    if (second) {
      second.offset = { x: 0, y: 0 };
      second.props.opacity = t;
      second.markNeedsPaint();
    }
  }

  viewKind(): ViewKind {
    return 'view';
  }
  viewProps(): Omit<ViewProps, 'frame'> {
    return { clip: true };
  }

  paintsChild(child: RenderObject): boolean {
    const t = this.t;
    if (child === this.children[0]) return t < 1;
    return t > 0;
  }

  protected onDetach(): void {
    this.controller?.detach();
    this.controller?.stop();
  }
}

/**
 * AnimatedSwitcher: when the child's identity changes, the old child stays
 * mounted and transitions out while the new one transitions in.
 * props { duration, transitionType: 'fade'|'scale'|'rotation'|'slide', curve }
 */
export class RenderAnimatedSwitcher extends RenderObject {
  /** Children leaving, with their remaining progress controllers. */
  readonly outgoing = new Map<RenderObject, AnimationController>();
  readonly incoming = new Map<RenderObject, AnimationController>();
  private mounted = false;

  /** Called by the reconciler when the current child is replaced. */
  childReplaced(oldChild: RenderObject, newChild: RenderObject): void {
    this.childRemoved(oldChild);
    this.startIncoming(newChild);
  }

  /** Transition [oldChild] out, then detach it. */
  childRemoved(oldChild: RenderObject): void {
    const duration = this.props.duration ?? 300;
    if (!this.owner || duration <= 0) {
      oldChild.detach();
      this.children = this.children.filter((c) => c !== oldChild);
      return;
    }
    const out = new AnimationController(duration, 1);
    out.attach(this.owner);
    out.addListener(() => this.markNeedsLayout());
    this.outgoing.set(oldChild, out);
    // Keep the old child mounted (painted beneath the new one) while it leaves.
    if (!this.children.includes(oldChild)) this.children.unshift(oldChild);
    oldChild.parent = this;
    void out.reverse().then(() => {
      this.outgoing.delete(oldChild);
      oldChild.detach();
      this.children = this.children.filter((c) => c !== oldChild);
      this.markNeedsLayout();
    });
  }

  private startIncoming(child: RenderObject): void {
    if (!this.owner) return;
    const c = new AnimationController(this.props.duration ?? 300, 0);
    c.attach(this.owner);
    c.addListener(() => this.markNeedsLayout());
    this.incoming.set(child, c);
    void c.forward().then(() => this.incoming.delete(child));
  }

  protected onAttach(): void {
    this.mounted = true;
  }

  progressOf(child: RenderObject): number {
    const curve = curveOf(this.props);
    const out = this.outgoing.get(child);
    if (out) return curve(out.value);
    const inc = this.incoming.get(child);
    if (inc) return curve(inc.value);
    return 1;
  }

  protected performLayout(c: Constraints): void {
    let w = 0;
    let h = 0;
    for (const child of this.children) {
      child.layout({ minWidth: 0, maxWidth: c.maxWidth, minHeight: 0, maxHeight: c.maxHeight });
      w = Math.max(w, child.size.width);
      h = Math.max(h, child.size.height);
    }
    this.size = constrain(c, { width: w, height: h });
    for (const child of this.children) {
      child.offset = { x: (this.size.width - child.size.width) / 2, y: (this.size.height - child.size.height) / 2 };
      // Transition applied through the child's wrapper (a RenderSwitcherSlot).
      if (child instanceof RenderSwitcherSlot) {
        child.progress = this.progressOf(child);
        child.kind = this.props.transitionType ?? 'fade';
        child.markNeedsPaint();
      }
    }
  }

  protected onDetach(): void {
    for (const c of this.outgoing.values()) c.stop();
    for (const c of this.incoming.values()) c.stop();
    this.mounted = false;
  }

  get isMounted(): boolean {
    return this.mounted;
  }
}

/** One child slot of an AnimatedSwitcher; paints the transition. */
export class RenderSwitcherSlot extends RenderProxy {
  progress = 1;
  kind = 'fade';
  viewKind(): ViewKind {
    return 'view';
  }
  viewProps(): Omit<ViewProps, 'frame'> {
    const p = this.progress;
    const w = this.size.width;
    const h = this.size.height;
    switch (this.kind) {
      case 'scale':
        return { transform: scaling(p, p, 1), transformOrigin: [w / 2, h / 2] };
      case 'rotation':
        return { transform: rotationZ(p * Math.PI * 2), transformOrigin: [w / 2, h / 2] };
      case 'slide':
        return { transform: translation((1 - p) * w, 0), transformOrigin: [0, 0] };
      default:
        return { opacity: p >= 1 ? undefined : p };
    }
  }
}

// ============================================================================
// Explicit transitions
// ============================================================================

/**
 * One class for Fade/Slide/Scale/Rotation/Size transitions, Pulse and
 * TweenAnimationBuilder.
 *
 * props {
 *   kind: 'fade'|'slide'|'scale'|'rotation'|'size'|'pulse'|'tween',
 *   begin, end (numbers; slide uses [x, y] pairs), duration, curve,
 *   repeat, autoReverse, axis ('vertical'|'horizontal'), tweenType, alignment
 * }
 */
export class RenderTransition extends RenderObject {
  private controller: AnimationController | null = null;
  /** TweenAnimationBuilder: begin of the current run (animates to new ends). */
  private tweenFrom: number | null = null;

  protected onAttach(): void {
    if (!this.controller) {
      this.controller = new AnimationController(this.props.duration ?? 300);
      this.controller.addListener(() => (this.props.kind === 'size' ? this.markNeedsLayout() : this.markNeedsPaint()));
    }
    this.controller.attach(this.owner!);
    this.start();
  }

  private start(): void {
    const c = this.controller!;
    const kind = this.props.kind;
    if (kind === 'pulse') {
      c.repeatAnimation(true);
      return;
    }
    if (this.props.repeat) {
      c.repeatAnimation(!!this.props.autoReverse);
    } else if (this.props.autoReverse) {
      void c.forward(0).then(() => c.reverse());
    } else {
      void c.forward(0);
    }
  }

  protected didUpdate(old: Record<string, any>): void {
    if (!this.controller) return;
    this.controller.duration = this.props.duration ?? 300;
    if (this.props.kind === 'tween' && old.end !== this.props.end) {
      // TweenAnimationBuilder animates from the current value to the new end.
      this.tweenFrom = this.value();
      void this.controller.forward(0);
    }
  }

  /** Current animated value in the begin..end range. */
  value(): number {
    const raw = this.controller?.value ?? 0;
    const t = curveOf(this.props, this.props.kind === 'pulse' ? Curves.easeInOut : Curves.linear)(raw);
    const begin = this.tweenFrom ?? numberOr(this.props.begin, defaultBegin(this.props.kind));
    const end = numberOr(this.props.end, defaultEnd(this.props.kind));
    return begin + (end - begin) * t;
  }

  private slideValue(): [number, number] {
    const raw = this.controller?.value ?? 0;
    const t = curveOf(this.props)(raw);
    const b: [number, number] = this.props.begin ?? [-1, 0];
    const e: [number, number] = this.props.end ?? [0, 0];
    return [b[0] + (e[0] - b[0]) * t, b[1] + (e[1] - b[1]) * t];
  }

  protected performLayout(c: Constraints): void {
    const child = this.child;
    if (!child) {
      this.size = constrain(c, { width: 0, height: 0 });
      return;
    }
    if (this.props.kind === 'size') {
      const factor = Math.max(0, this.value());
      const horizontal = this.props.axis === 'horizontal';
      child.layout(horizontal ? { ...c, minWidth: 0, maxWidth: INF } : { ...c, minHeight: 0, maxHeight: INF });
      const size = horizontal ? { width: child.size.width * factor, height: child.size.height } : { width: child.size.width, height: child.size.height * factor };
      this.size = constrain(c, size);
      // SizeTransition aligns the child at the centre of the axis (axisAlignment 0).
      child.offset = horizontal ? { x: (this.size.width - child.size.width) / 2, y: 0 } : { x: 0, y: (this.size.height - child.size.height) / 2 };
      return;
    }
    child.layout(c);
    child.offset = { x: 0, y: 0 };
    this.size = { ...child.size };
  }

  viewKind(): ViewKind {
    return 'view';
  }

  viewProps(): Omit<ViewProps, 'frame'> {
    const w = this.size.width;
    const h = this.size.height;
    const center: [number, number] = [w / 2, h / 2];
    switch (this.props.kind) {
      case 'fade': {
        const o = Math.max(0, Math.min(1, this.value()));
        return { opacity: o >= 1 ? undefined : o };
      }
      case 'slide': {
        const [x, y] = this.slideValue();
        return { transform: translation(x * w, y * h), transformOrigin: [0, 0] };
      }
      case 'scale':
      case 'pulse': {
        const s = this.value();
        return { transform: scaling(s, s, 1), transformOrigin: center };
      }
      case 'rotation':
        return { transform: rotationZ(this.value() * Math.PI * 2), transformOrigin: center };
      case 'size':
        return { clip: true };
      case 'tween': {
        const v = this.value();
        switch (this.props.tweenType ?? 'opacity') {
          case 'scale':
            return { transform: scaling(v, v, 1), transformOrigin: center };
          case 'rotation':
            return { transform: rotationZ(v * Math.PI * 2), transformOrigin: center };
          case 'translateX':
            return { transform: translation(v, 0), transformOrigin: [0, 0] };
          case 'translateY':
            return { transform: translation(0, v), transformOrigin: [0, 0] };
          default: {
            const o = Math.max(0, Math.min(1, v));
            return { opacity: o >= 1 ? undefined : o };
          }
        }
      }
      default:
        return {};
    }
  }

  protected onDetach(): void {
    this.controller?.detach();
    this.controller?.stop();
  }
}

function numberOr(v: any, fallback: number): number {
  return typeof v === 'number' && Number.isFinite(v) ? v : fallback;
}
function defaultBegin(kind: string): number {
  return kind === 'pulse' ? 1 : 0;
}
function defaultEnd(kind: string): number {
  return kind === 'pulse' ? 1.05 : 1;
}

/**
 * StaggeredAnimation: a column whose children fade and rise in one after
 * another. props { duration (total), staggerDelay, curve }
 */
export class RenderStaggered extends RenderObject {
  private controller: AnimationController | null = null;

  protected onAttach(): void {
    if (!this.controller) {
      this.controller = new AnimationController(this.props.duration ?? 1000);
      this.controller.addListener(() => {
        for (const c of this.children) c.markNeedsPaint();
      });
    }
    this.controller.attach(this.owner!);
    void this.controller.forward(0);
  }

  itemProgress(index: number): number {
    const count = this.children.length;
    const total = this.props.duration ?? 1000;
    const delay = this.props.staggerDelay ?? 100;
    const totalDelay = delay * (count - 1);
    const start = Math.max(0, Math.min(1, (delay * index) / total));
    const end = Math.max(0, Math.min(1, (delay * index + (total - totalDelay)) / total));
    const curve = interval(start, end, curveOf(this.props, Curves.easeOut));
    return curve(this.controller?.value ?? 0);
  }

  protected performLayout(c: Constraints): void {
    let y = 0;
    let w = 0;
    for (const child of this.children) {
      child.layout({ minWidth: 0, maxWidth: c.maxWidth, minHeight: 0, maxHeight: INF });
      child.offset = { x: 0, y };
      y += child.size.height;
      w = Math.max(w, child.size.width);
    }
    this.size = constrain(c, { width: w, height: y });
  }

  protected onDetach(): void {
    this.controller?.detach();
    this.controller?.stop();
  }
}

/** One staggered child: fades in and slides up 20px. */
export class RenderStaggerItem extends RenderProxy {
  viewKind(): ViewKind {
    return 'view';
  }
  viewProps(): Omit<ViewProps, 'frame'> {
    const parent = this.parent;
    const index = parent ? parent.children.indexOf(this) : 0;
    const v = parent instanceof RenderStaggered ? parent.itemProgress(index) : 1;
    const o = Math.max(0, Math.min(1, v));
    return { opacity: o >= 1 ? undefined : o, transform: v >= 1 ? null : translation(0, 20 * (1 - v)), transformOrigin: [0, 0] };
  }
}

/** Shimmer: a sweeping highlight gradient masked onto the child (srcATop). */
export class RenderShimmer extends RenderShaderMask {
  private controller: AnimationController | null = null;
  protected onAttach(): void {
    if (!this.controller) {
      this.controller = new AnimationController(this.props.duration ?? 1500);
      this.controller.addListener(() => this.markNeedsPaint());
    }
    this.controller.attach(this.owner!);
    this.controller.repeatAnimation(false);
  }
  viewProps(): Omit<ViewProps, 'frame'> {
    const v = -1 + 3 * (this.controller?.value ?? 0); // Tween(-1, 2)
    const base: Color = this.props.baseColor ?? 0xffe0e0e0;
    const highlight: Color = this.props.highlightColor ?? 0xfff5f5f5;
    const clamp = (x: number) => Math.max(0, Math.min(1, x));
    const gradient: Gradient = {
      kind: 'linear',
      colors: [base, highlight, base],
      stops: [clamp(v - 0.3), clamp(v), clamp(v + 0.3)],
      begin: { x: -1, y: 0 },
      end: { x: 1, y: 0 },
    };
    return { shaderMask: gradient };
  }
  protected onDetach(): void {
    this.controller?.detach();
    this.controller?.stop();
  }
}

/** AnimatedGradient: a decorated box whose gradient stops rotate continuously. */
export class RenderAnimatedGradient extends RenderDecoratedBox {
  private controller: AnimationController | null = null;
  protected onAttach(): void {
    if (!this.controller) {
      this.controller = new AnimationController(this.props.duration ?? 2000);
      this.controller.addListener(() => this.markNeedsPaint());
    }
    this.controller.attach(this.owner!);
    this.controller.repeatAnimation(false);
  }
  viewProps(): Omit<ViewProps, 'frame'> {
    const colors: Color[] = this.props.colors ?? [0xff2196f3, 0xff9c27b0, 0xffe91e63, 0xff2196f3];
    const shift = this.controller?.value ?? 0;
    const stops = colors.map((_, i) => ((colors.length > 1 ? i / (colors.length - 1) : 0) + shift) % 1).sort((a, b) => a - b);
    const d: Decoration = {
      ...(this.props.decoration ?? {}),
      gradients: [{ kind: 'linear', colors, stops, begin: { x: -1, y: -1 }, end: { x: 1, y: 1 } }],
    };
    return decorationViewProps(d, this.size.width, this.size.height);
  }
  protected onDetach(): void {
    this.controller?.detach();
    this.controller?.stop();
  }
}

// ============================================================================
// CSS @keyframes
// ============================================================================

interface ParsedFrame {
  offset: number;
  opacity?: number;
  transform?: Matrix4;
  background?: Color;
}

/**
 * CSS keyframe animation on an element: animates opacity, transform and
 * background colour between the stylesheet's `@keyframes` frames.
 * props { frames: Keyframe[], duration, delay, iterations (-1 = infinite),
 *         direction, fillMode, timing, playState }
 */
export class RenderKeyframes extends RenderProxy {
  private controller: AnimationController | null = null;
  private frames: ParsedFrame[] = [];
  private iteration = 0;
  private delayTimer: number | null = null;

  init(props: Record<string, any>): void {
    super.init(props);
    this.frames = parseFrames(props.frames ?? []);
  }

  protected didUpdate(old: Record<string, any>): void {
    if (!deepEqual(old.frames, this.props.frames)) this.frames = parseFrames(this.props.frames ?? []);
    if (old.playState !== this.props.playState && this.controller) {
      if (this.props.playState === 'paused') this.controller.stop();
      else this.run();
    }
  }

  protected onAttach(): void {
    if (!this.controller) {
      this.controller = new AnimationController(this.props.duration ?? 1000);
      this.controller.addListener(() => this.markNeedsPaint());
      this.controller.addStatusListener((s) => {
        if (s === 'completed' || s === 'dismissed') this.onIterationEnd();
      });
    }
    this.controller.attach(this.owner!);
    const delay = this.props.delay ?? 0;
    if (delay > 0 && this.owner) {
      this.delayTimer = this.owner.platform.setTimeout(() => {
        this.delayTimer = null;
        this.run();
      }, delay);
    } else this.run();
  }

  private direction(iteration: number): 'forward' | 'reverse' {
    switch (this.props.direction) {
      case 'reverse':
        return 'reverse';
      case 'alternate':
        return iteration % 2 === 0 ? 'forward' : 'reverse';
      case 'alternate-reverse':
        return iteration % 2 === 0 ? 'reverse' : 'forward';
      default:
        return 'forward';
    }
  }

  private run(): void {
    if (!this.controller || this.props.playState === 'paused') return;
    this.controller.duration = Math.max(1, this.props.duration ?? 1000);
    if (this.direction(this.iteration) === 'forward') void this.controller.forward(0);
    else void this.controller.reverse(1);
  }

  private onIterationEnd(): void {
    this.iteration++;
    const total = this.props.iterations ?? 1;
    if (total === -1 || this.iteration < total) this.run();
    else this.markNeedsPaint();
  }

  private finished(): boolean {
    const total = this.props.iterations ?? 1;
    return total !== -1 && this.iteration >= total;
  }

  viewKind(): ViewKind {
    return 'view';
  }

  viewProps(): Omit<ViewProps, 'frame'> {
    if (this.frames.length === 0) return {};
    const fill = this.props.fillMode ?? 'none';
    if (this.finished() && fill !== 'forwards' && fill !== 'both') return {};
    const t = curveByName(this.props.timing, Curves.ease)(this.controller?.value ?? 0);
    const sampled = sampleFrames(this.frames, t);
    const out: Omit<ViewProps, 'frame'> = {};
    if (sampled.opacity != null) out.opacity = sampled.opacity;
    if (sampled.transform) {
      out.transform = sampled.transform;
      out.transformOrigin = [this.size.width / 2, this.size.height / 2];
    }
    if (sampled.background != null) out.background = sampled.background;
    return out;
  }

  protected onDetach(): void {
    if (this.delayTimer != null && this.owner) this.owner.platform.clearTimeout(this.delayTimer);
    this.controller?.detach();
    this.controller?.stop();
  }
}

function parseFrames(frames: Keyframe[]): ParsedFrame[] {
  return frames
    .map((f) => {
      const s = CSSParser.parse(f.styles as Record<string, any>);
      const out: ParsedFrame = { offset: f.offset };
      if (s.opacity != null) out.opacity = s.opacity;
      let m: Matrix4 | null = s.transform ?? null;
      if (s.translate) m = multiply(m ?? identity(), translation(s.translate.dx, s.translate.dy));
      if (s.rotate != null) m = multiply(m ?? identity(), rotationZ((s.rotate * Math.PI) / 180));
      if (s.scale != null) m = multiply(m ?? identity(), scaling(s.scale, s.scale, 1));
      if (m) out.transform = m;
      if (s.backgroundColor != null) out.background = s.backgroundColor;
      return out;
    })
    .sort((a, b) => a.offset - b.offset);
}

function sampleFrames(frames: ParsedFrame[], t: number): { opacity?: number; transform?: Matrix4; background?: Color } {
  const pick = <K extends 'opacity' | 'transform' | 'background'>(key: K): ParsedFrame[K] | undefined => {
    const withKey = frames.filter((f) => f[key] !== undefined);
    if (withKey.length === 0) return undefined;
    if (t <= withKey[0].offset) return withKey[0][key];
    for (let i = 0; i < withKey.length - 1; i++) {
      const a = withKey[i];
      const b = withKey[i + 1];
      if (t >= a.offset && t <= b.offset) {
        const local = b.offset > a.offset ? (t - a.offset) / (b.offset - a.offset) : 1;
        if (key === 'opacity') return ((a.opacity as number) + ((b.opacity as number) - (a.opacity as number)) * local) as ParsedFrame[K];
        if (key === 'transform') return lerpMatrix(a.transform!, b.transform!, local) as ParsedFrame[K];
        return lerpColor(a.background!, b.background!, local) as ParsedFrame[K];
      }
    }
    return withKey[withKey.length - 1][key];
  };
  return { opacity: pick('opacity'), transform: pick('transform'), background: pick('background') };
}

// ============================================================================
// Hero
// ============================================================================

/**
 * Hero: when a hero with the same tag appears at a new place on screen (a
 * re-render moved it, or a new screen replaced the old one), it flies from
 * its previous global rect to the new one (fastOutSlowIn, 300 ms).
 */
export class RenderHero extends RenderProxy {
  private controller: AnimationController | null = null;
  private fromRect: { x: number; y: number; width: number; height: number } | null = null;

  /** Called by the owner's hero registry after layout of a frame. */
  flyFrom(rect: { x: number; y: number; width: number; height: number }, owner: RenderOwner): void {
    this.fromRect = rect;
    if (!this.controller) {
      this.controller = new AnimationController(300);
      this.controller.addListener(() => this.markNeedsPaint());
    }
    this.controller.attach(owner);
    void this.controller.forward(0).then(() => {
      this.fromRect = null;
      this.markNeedsPaint();
    });
  }

  viewKind(): ViewKind {
    return 'view';
  }

  viewProps(): Omit<ViewProps, 'frame'> {
    const from = this.fromRect;
    if (!from || !this.owner || !this.controller) return { transform: null };
    const here = this.owner.compositor.globalFrame(this);
    const t = Curves.fastOutSlowIn(this.controller.value);
    const sx = this.size.width > 0 ? from.width / this.size.width : 1;
    const sy = this.size.height > 0 ? from.height / this.size.height : 1;
    const scaleX = sx + (1 - sx) * t;
    const scaleY = sy + (1 - sy) * t;
    const dx = (from.x - here.x) * (1 - t);
    const dy = (from.y - here.y) * (1 - t);
    return { transform: multiply(translation(dx, dy), scaling(scaleX, scaleY, 1)), transformOrigin: [0, 0] };
  }

  protected onDetach(): void {
    this.controller?.detach();
    this.controller?.stop();
  }
}

export { aboutOrigin };
