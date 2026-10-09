/**
 * Easing curves — an exact port of Flutter's `Curves` (cubic bisection with
 * the same 0.001 error bound, Robert Penner's bounce, Flutter's elastic
 * curves) plus CSS `cubic-bezier()` and `steps()`.
 */

export type Curve = (t: number) => number;

const CUBIC_ERROR_BOUND = 0.001;

function evaluateCubic(a: number, b: number, m: number): number {
  return 3 * a * (1 - m) * (1 - m) * m + 3 * b * (1 - m) * m * m + m * m * m;
}

export function cubic(a: number, b: number, c: number, d: number): Curve {
  return (t: number) => {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    let start = 0;
    let end = 1;
    for (let i = 0; i < 64; i++) {
      const mid = (start + end) / 2;
      const estimate = evaluateCubic(a, c, mid);
      if (Math.abs(t - estimate) < CUBIC_ERROR_BOUND) return evaluateCubic(b, d, mid);
      if (estimate < t) start = mid;
      else end = mid;
    }
    return evaluateCubic(b, d, (start + end) / 2);
  };
}

function bounce(t: number): number {
  if (t < 1 / 2.75) return 7.5625 * t * t;
  if (t < 2 / 2.75) {
    t -= 1.5 / 2.75;
    return 7.5625 * t * t + 0.75;
  }
  if (t < 2.5 / 2.75) {
    t -= 2.25 / 2.75;
    return 7.5625 * t * t + 0.9375;
  }
  t -= 2.625 / 2.75;
  return 7.5625 * t * t + 0.984375;
}

export function elasticIn(period = 0.4): Curve {
  return (t) => {
    if (t <= 0 || t >= 1) return t <= 0 ? 0 : 1;
    const s = period / 4;
    t = t - 1;
    return -Math.pow(2, 10 * t) * Math.sin(((t - s) * (Math.PI * 2)) / period);
  };
}

export function elasticOut(period = 0.4): Curve {
  return (t) => {
    if (t <= 0 || t >= 1) return t <= 0 ? 0 : 1;
    const s = period / 4;
    return Math.pow(2, -10 * t) * Math.sin(((t - s) * (Math.PI * 2)) / period) + 1;
  };
}

export function elasticInOut(period = 0.4): Curve {
  return (t) => {
    if (t <= 0 || t >= 1) return t <= 0 ? 0 : 1;
    const s = period / 4;
    t = 2 * t - 1;
    if (t < 0) return -0.5 * Math.pow(2, 10 * t) * Math.sin(((t - s) * (Math.PI * 2)) / period);
    return Math.pow(2, -10 * t) * Math.sin(((t - s) * (Math.PI * 2)) / period) * 0.5 + 1;
  };
}

export function interval(begin: number, end: number, curve: Curve = Curves.linear): Curve {
  return (t) => {
    if (end <= begin) return t >= end ? 1 : 0;
    const local = Math.max(0, Math.min(1, (t - begin) / (end - begin)));
    if (local === 0 || local === 1) return local;
    return curve(local);
  };
}

export function steps(count: number, position: 'start' | 'end' | 'both' | 'none' = 'end'): Curve {
  const n = Math.max(1, count);
  return (t) => {
    if (t >= 1) return 1;
    let step = Math.floor(t * n);
    if (position === 'start' || position === 'both') step += 1;
    const jumps = position === 'both' ? n + 1 : position === 'none' ? n - 1 : n;
    return Math.max(0, Math.min(1, step / Math.max(1, jumps)));
  };
}

export const Curves = {
  linear: ((t: number) => t) as Curve,
  decelerate: ((t: number) => {
    t = 1 - t;
    return 1 - t * t;
  }) as Curve,
  fastLinearToSlowEaseIn: cubic(0.18, 1.0, 0.04, 1.0),
  ease: cubic(0.25, 0.1, 0.25, 1.0),
  easeIn: cubic(0.42, 0.0, 1.0, 1.0),
  easeInToLinear: cubic(0.67, 0.03, 0.65, 0.09),
  easeInSine: cubic(0.47, 0.0, 0.745, 0.715),
  easeInQuad: cubic(0.55, 0.085, 0.68, 0.53),
  easeInCubic: cubic(0.55, 0.055, 0.675, 0.19),
  easeInQuart: cubic(0.895, 0.03, 0.685, 0.22),
  easeInQuint: cubic(0.755, 0.05, 0.855, 0.06),
  easeInExpo: cubic(0.95, 0.05, 0.795, 0.035),
  easeInCirc: cubic(0.6, 0.04, 0.98, 0.335),
  easeInBack: cubic(0.6, -0.28, 0.735, 0.045),
  easeOut: cubic(0.0, 0.0, 0.58, 1.0),
  linearToEaseOut: cubic(0.35, 0.91, 0.33, 0.97),
  easeOutSine: cubic(0.39, 0.575, 0.565, 1.0),
  easeOutQuad: cubic(0.25, 0.46, 0.45, 0.94),
  easeOutCubic: cubic(0.215, 0.61, 0.355, 1.0),
  easeOutQuart: cubic(0.165, 0.84, 0.44, 1.0),
  easeOutQuint: cubic(0.23, 1.0, 0.32, 1.0),
  easeOutExpo: cubic(0.19, 1.0, 0.22, 1.0),
  easeOutCirc: cubic(0.075, 0.82, 0.165, 1.0),
  easeOutBack: cubic(0.175, 0.885, 0.32, 1.275),
  easeInOut: cubic(0.42, 0.0, 0.58, 1.0),
  easeInOutSine: cubic(0.445, 0.05, 0.55, 0.95),
  easeInOutQuad: cubic(0.455, 0.03, 0.515, 0.955),
  easeInOutCubic: cubic(0.645, 0.045, 0.355, 1.0),
  easeInOutQuart: cubic(0.77, 0.0, 0.175, 1.0),
  easeInOutQuint: cubic(0.86, 0.0, 0.07, 1.0),
  easeInOutExpo: cubic(1.0, 0.0, 0.0, 1.0),
  easeInOutCirc: cubic(0.785, 0.135, 0.15, 0.86),
  easeInOutBack: cubic(0.68, -0.55, 0.265, 1.55),
  fastOutSlowIn: cubic(0.4, 0.0, 0.2, 1.0),
  slowMiddle: cubic(0.15, 0.85, 0.85, 0.15),
  bounceIn: ((t: number) => 1 - bounce(1 - t)) as Curve,
  bounceOut: ((t: number) => bounce(t)) as Curve,
  bounceInOut: ((t: number) => (t < 0.5 ? (1 - bounce(1 - t * 2)) * 0.5 : bounce(t * 2 - 1) * 0.5 + 0.5)) as Curve,
  elasticIn: elasticIn(0.4),
  elasticOut: elasticOut(0.4),
  elasticInOut: elasticInOut(0.4),
};

/** Normalised name (lowercase, no separators) → curve; mirrors `CSSParser._curveMap`. */
const byName: Record<string, Curve> = {
  linear: Curves.linear,
  ease: Curves.ease,
  easein: Curves.easeIn,
  easeout: Curves.easeOut,
  easeinout: Curves.easeInOut,
  bounce: Curves.bounceIn,
  bouncein: Curves.bounceIn,
  bounceout: Curves.bounceOut,
  bounceinout: Curves.bounceInOut,
  elastic: Curves.elasticIn,
  elasticin: Curves.elasticIn,
  elasticout: Curves.elasticOut,
  elasticinout: Curves.elasticInOut,
  decelerate: Curves.decelerate,
  fastoutslowin: Curves.fastOutSlowIn,
  slowmiddle: Curves.slowMiddle,
  fastlineartosloweasein: Curves.fastLinearToSlowEaseIn,
  easeintolinear: Curves.easeInToLinear,
  lineartoeaseout: Curves.linearToEaseOut,
  easeinsine: Curves.easeInSine,
  easeinquad: Curves.easeInQuad,
  easeincubic: Curves.easeInCubic,
  easeinquart: Curves.easeInQuart,
  easeinquint: Curves.easeInQuint,
  easeinexpo: Curves.easeInExpo,
  easeincirc: Curves.easeInCirc,
  easeinback: Curves.easeInBack,
  easeoutsine: Curves.easeOutSine,
  easeoutquad: Curves.easeOutQuad,
  easeoutcubic: Curves.easeOutCubic,
  easeoutquart: Curves.easeOutQuart,
  easeoutquint: Curves.easeOutQuint,
  easeoutexpo: Curves.easeOutExpo,
  easeoutcirc: Curves.easeOutCirc,
  easeoutback: Curves.easeOutBack,
  easeinoutsine: Curves.easeInOutSine,
  easeinoutquad: Curves.easeInOutQuad,
  easeinoutcubic: Curves.easeInOutCubic,
  easeinoutquart: Curves.easeInOutQuart,
  easeinoutquint: Curves.easeInOutQuint,
  easeinoutexpo: Curves.easeInOutExpo,
  easeinoutcirc: Curves.easeInOutCirc,
  easeinoutback: Curves.easeInOutBack,
  stepstart: steps(1, 'start'),
  stepend: steps(1, 'end'),
};

/** Resolve a curve name (`ease-in-out`, `easeInOut`, `cubic-bezier(…)`, `steps(4, end)`). */
export function curveByName(name: string | null | undefined, fallback: Curve = Curves.linear): Curve {
  if (!name) return fallback;
  const raw = name.trim().toLowerCase();
  const bez = /^cubic-bezier\(\s*([-\d.]+)\s*,\s*([-\d.]+)\s*,\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\)$/.exec(raw);
  if (bez) return cubic(parseFloat(bez[1]), parseFloat(bez[2]), parseFloat(bez[3]), parseFloat(bez[4]));
  const st = /^steps\(\s*(\d+)\s*(?:,\s*([a-z-]+))?\s*\)$/.exec(raw);
  if (st) {
    const pos = st[2] ?? 'end';
    const position = pos === 'start' || pos === 'jump-start' ? 'start' : pos === 'jump-both' ? 'both' : pos === 'jump-none' ? 'none' : 'end';
    return steps(Number.parseInt(st[1], 10), position);
  }
  return byName[raw.replace(/[-_\s]/g, '')] ?? fallback;
}
