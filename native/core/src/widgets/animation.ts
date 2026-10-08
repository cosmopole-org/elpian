/**
 * Animation widgets — ports of flutter/lib/src/widgets/elpian_animated_*.dart,
 * the explicit `*Transition` widgets, `TweenAnimationBuilder`,
 * `StaggeredAnimation`, `Shimmer`, `Pulse` and `AnimatedGradient`. Every
 * builder reads the same style fields and defaults as its Flutter
 * counterpart and lowers onto the animated render objects in
 * render/animated.ts, which tick on the owner's frame clock.
 */
import { M3 } from '../css/color.js';
import { radiusAll, type EdgeInsets } from '../css/types.js';
import { w, type W } from '../render/object.js';
import type { WidgetBuilder } from './context.js';
import { SHRINK, createTextStyle } from './style.js';

const ZERO: EdgeInsets = { top: 0, right: 0, bottom: 0, left: 0 };

function only(children: W[]): W | null {
  return children.length ? children[0] : null;
}

export const animationWidgets: Record<string, WidgetBuilder> = {
  // --------------------------------------------------------------------------
  // Implicit
  // --------------------------------------------------------------------------
  AnimatedContainer(node, children) {
    const s = node.style;
    const duration = s?.transitionDuration ?? 200;
    const curve = s?.transitionCurve ?? null;
    let current: W | null = only(children);
    // AnimatedContainer → Container composition with every layer animated.
    if (s?.padding || current) current = w('animatedPadding', { padding: s?.padding ?? ZERO, duration, curve }, current ?? SHRINK);
    current = w('animatedDecorated', { decoration: { color: s?.backgroundColor ?? null, radius: s?.borderRadius ?? null }, duration, curve }, current ?? null);
    current = w('animatedConstrained', { width: s?.width ?? null, height: s?.height ?? null, duration, curve }, current);
    if (s?.margin) current = w('animatedPadding', { padding: s.margin, duration, curve }, current);
    return current;
  },
  AnimatedOpacity(node, children) {
    // Flutter's builder passes no curve (linear).
    return w('animatedOpacity', { opacity: node.style?.opacity ?? 1, duration: node.style?.transitionDuration ?? 200 }, only(children));
  },
  AnimatedCrossFade(node, children) {
    const s = node.style;
    const curve = s?.transitionCurve ?? null;
    const first = children[0] ?? SHRINK;
    const second = children[1] ?? SHRINK;
    return w(
      'animatedCrossFade',
      { showFirst: node.props.showFirst !== false, duration: s?.transitionDuration ?? 300, curve },
      [w('opacity', { opacity: 1 }, first, 'first'), w('opacity', { opacity: 0 }, second, 'second')],
    );
  },
  AnimatedSwitcher(node, children) {
    return w(
      'animatedSwitcher',
      { duration: node.style?.transitionDuration ?? 300, transitionType: String(node.props.transitionType ?? 'fade'), curve: node.style?.transitionCurve ?? null },
      children.length ? [children[0]] : [],
    );
  },
  AnimatedAlign(node, children) {
    const s = node.style;
    return w(
      'animatedAlign',
      { alignment: s?.alignmentEnd ?? s?.alignment ?? { x: 0, y: 0 }, duration: s?.transitionDuration ?? 300, curve: s?.transitionCurve ?? null },
      only(children),
    );
  },
  AnimatedPadding(node, children) {
    const s = node.style;
    return w('animatedPadding', { padding: s?.padding ?? ZERO, duration: s?.transitionDuration ?? 300, curve: s?.transitionCurve ?? null }, only(children));
  },
  AnimatedPositioned(node, children) {
    const s = node.style;
    return w(
      'animatedPositioned',
      {
        top: s?.top ?? null,
        right: s?.right ?? null,
        bottom: s?.bottom ?? null,
        left: s?.left ?? null,
        width: s?.width ?? null,
        height: s?.height ?? null,
        duration: s?.transitionDuration ?? 300,
        curve: s?.transitionCurve ?? null,
      },
      only(children) ?? SHRINK,
    );
  },
  AnimatedScale(node, children) {
    const s = node.style;
    return w('animatedTransform', { scale: s?.scale ?? 1, alignment: { x: 0, y: 0 }, duration: s?.transitionDuration ?? 300, curve: s?.transitionCurve ?? null }, only(children));
  },
  AnimatedRotation(node, children) {
    const s = node.style;
    return w('animatedTransform', { turns: (s?.rotate ?? 0) / 360, alignment: { x: 0, y: 0 }, duration: s?.transitionDuration ?? 300, curve: s?.transitionCurve ?? null }, only(children));
  },
  AnimatedSlide(node, children) {
    const s = node.style;
    const o = s?.slideEnd ?? { dx: 0, dy: 0 };
    return w('animatedTransform', { slide: [o.dx, o.dy], alignment: { x: -1, y: -1 }, duration: s?.transitionDuration ?? 300, curve: s?.transitionCurve ?? null }, only(children));
  },
  AnimatedSize(node, children) {
    const s = node.style;
    return w('animatedSize', { duration: s?.transitionDuration ?? 300, curve: s?.transitionCurve ?? null, alignment: { x: 0, y: 0 } }, only(children));
  },
  AnimatedDefaultTextStyle(node, children) {
    const s = node.style;
    return w('animatedDefaultTextStyle', { style: createTextStyle(s) ?? {}, duration: s?.transitionDuration ?? 300, curve: s?.transitionCurve ?? null }, only(children) ?? SHRINK);
  },

  // --------------------------------------------------------------------------
  // Explicit
  // --------------------------------------------------------------------------
  FadeTransition(node, children) {
    const s = node.style;
    return transition('fade', node.style, s?.fadeBegin ?? 0, s?.fadeEnd ?? 1, only(children) ?? w('constrained', {}));
  },
  SlideTransition(node, children) {
    const s = node.style;
    const b = s?.slideBegin ?? { dx: -1, dy: 0 };
    const e = s?.slideEnd ?? { dx: 0, dy: 0 };
    return transition('slide', s, [b.dx, b.dy], [e.dx, e.dy], only(children) ?? w('constrained', {}));
  },
  ScaleTransition(node, children) {
    const s = node.style;
    return transition('scale', s, s?.scaleBegin ?? 0, s?.scaleEnd ?? 1, only(children) ?? w('constrained', {}));
  },
  RotationTransition(node, children) {
    const s = node.style;
    return transition('rotation', s, s?.rotationBegin ?? 0, s?.rotationEnd ?? 1, only(children) ?? w('constrained', {}));
  },
  SizeTransition(node, children) {
    const s = node.style;
    const t = transition('size', s, s?.animationFrom ?? 0, s?.animationTo ?? 1, only(children) ?? w('constrained', {}));
    t.p.axis = node.props.axis === 'horizontal' ? 'horizontal' : 'vertical';
    return t;
  },

  // --------------------------------------------------------------------------
  // Custom
  // --------------------------------------------------------------------------
  TweenAnimationBuilder(node, children) {
    const s = node.style;
    return w(
      'transition',
      {
        kind: 'tween',
        tweenType: String(node.props.tweenType ?? 'opacity'),
        begin: s?.animationFrom ?? 0,
        end: s?.animationTo ?? 1,
        duration: s?.animationDuration ?? s?.transitionDuration ?? 300,
        curve: s?.transitionCurve ?? null,
      },
      only(children) ?? w('constrained', {}),
    );
  },
  StaggeredAnimation(node, children) {
    const s = node.style;
    return w(
      'staggered',
      { duration: s?.animationDuration ?? 1000, staggerDelay: s?.staggerDelay ?? 100, curve: s?.transitionCurve ?? 'easeOut' },
      children.map((c, i) => w('staggerItem', {}, c, c.k ?? `stagger-${i}`)),
    );
  },
  Shimmer(node, children) {
    const s = node.style;
    const child =
      only(children) ??
      // Flutter's placeholder bar: a sized box with a rounded (transparent)
      // decoration; the mask paints the sweep onto it.
      w('constrained', { width: s?.width ?? 200, height: s?.height ?? 20 }, w('decorated', { decoration: { color: M3.surfaceContainerHighest, radius: s?.borderRadius ?? radiusAll(4) } }));
    return w(
      'shimmer',
      { duration: s?.animationDuration ?? 1500, baseColor: s?.shimmerBaseColor ?? 0xffe0e0e0, highlightColor: s?.shimmerHighlightColor ?? 0xfff5f5f5, blendMode: 'srcATop' },
      child,
    );
  },
  Pulse(node, children) {
    const s = node.style;
    return w(
      'transition',
      { kind: 'pulse', begin: s?.scaleBegin ?? 1, end: s?.scaleEnd ?? 1.05, duration: s?.animationDuration ?? 1000, curve: s?.transitionCurve ?? 'easeInOut' },
      only(children) ?? w('constrained', {}),
    );
  },
  AnimatedGradient(node, children) {
    const s = node.style;
    const gradient = w(
      'animatedGradient',
      {
        duration: s?.animationDuration ?? 2000,
        colors: s?.gradientColors ?? [0xff2196f3, 0xff9c27b0, 0xffe91e63, 0xff2196f3],
        decoration: { radius: s?.borderRadius ?? null },
      },
      only(children),
    );
    // Container(width, height, decoration): no child → expands like Container.
    if (s?.width != null || s?.height != null) return w('constrained', { width: s?.width ?? null, height: s?.height ?? null }, gradient);
    return children.length ? gradient : w('limited', { maxWidth: 0, maxHeight: 0 }, w('constrained', { minWidth: Number.POSITIVE_INFINITY, minHeight: Number.POSITIVE_INFINITY }, gradient));
  },
};

function transition(kind: string, s: any, begin: unknown, end: unknown, child: W): W {
  return w(
    'transition',
    {
      kind,
      begin,
      end,
      duration: s?.animationDuration ?? s?.transitionDuration ?? 300,
      curve: s?.transitionCurve ?? null,
      repeat: s?.animationRepeat ?? false,
      autoReverse: s?.animationAutoReverse ?? false,
    },
    child,
  );
}
