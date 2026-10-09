/**
 * Colour parsing, mirroring `CSSParser.parseColor` in the Flutter engine.
 *
 * Colours are 32-bit unsigned ARGB integers (Flutter's `Color.value` layout),
 * which every platform renderer can consume directly:
 *   Android `Color` ints, iOS via component extraction, web via [toCssColor].
 *
 * Fidelity notes (Flutter is the source of truth):
 *   * An 8-digit hex is `#AARRGGBB`, as in Flutter's `Color(0xAARRGGBB)` —
 *     NOT the CSS `#RRGGBBAA`. `#rgba` expands to `#rrggbbaa` and is then read
 *     the same way, exactly like the Flutter parser.
 *   * Names Flutter knows (`red`, `blue`, `grey`, `deep-orange` …) resolve to
 *     the Material primary swatches Flutter uses, not the CSS keywords. The
 *     remaining CSS named colours are accepted as a superset.
 */

export type Color = number;

export const TRANSPARENT: Color = 0x00000000;
export const BLACK: Color = 0xff000000;
export const WHITE: Color = 0xffffffff;

/** Flutter `Colors.*` values used by the widget defaults. */
export const Colors = {
  transparent: 0x00000000,
  black: 0xff000000,
  black87: 0xdd000000,
  black54: 0x8a000000,
  black45: 0x73000000,
  black38: 0x61000000,
  black26: 0x42000000,
  black12: 0x1f000000,
  white: 0xffffffff,
  white70: 0xb3ffffff,
  white60: 0x99ffffff,
  white54: 0x8affffff,
  white38: 0x62ffffff,
  white30: 0x4dffffff,
  white24: 0x3dffffff,
  white12: 0x1fffffff,
  white10: 0x1affffff,
  red: 0xfff44336,
  pink: 0xffe91e63,
  purple: 0xff9c27b0,
  deepPurple: 0xff673ab7,
  indigo: 0xff3f51b5,
  blue: 0xff2196f3,
  lightBlue: 0xff03a9f4,
  cyan: 0xff00bcd4,
  teal: 0xff009688,
  green: 0xff4caf50,
  lightGreen: 0xff8bc34a,
  lime: 0xffcddc39,
  yellow: 0xffffeb3b,
  amber: 0xffffc107,
  orange: 0xffff9800,
  deepOrange: 0xffff5722,
  brown: 0xff795548,
  grey: 0xff9e9e9e,
  grey100: 0xfff5f5f5,
  grey200: 0xffeeeeee,
  grey300: 0xffe0e0e0,
  grey400: 0xffbdbdbd,
  grey600: 0xff757575,
  blueGrey: 0xff607d8b,
} as const;

/** Material 3 baseline scheme (what an un-themed Flutter app renders with). */
export const M3 = {
  primary: 0xff6750a4,
  onPrimary: 0xffffffff,
  primaryContainer: 0xffeaddff,
  secondaryContainer: 0xffe8def8,
  onSecondaryContainer: 0xff1d192b,
  surface: 0xfffef7ff,
  surfaceContainerLow: 0xfff7f2fa,
  surfaceContainerHighest: 0xffe6e0e9,
  onSurface: 0xff1d1b20,
  onSurfaceVariant: 0xff49454f,
  outline: 0xff79747e,
  outlineVariant: 0xffcac4d0,
  error: 0xffb3261e,
  inverseSurface: 0xff322f35,
  onInverseSurface: 0xfff5eff7,
  shadow: 0xff000000,
} as const;

const flutterNamed: Record<string, Color> = {
  transparent: Colors.transparent,
  black: Colors.black,
  white: Colors.white,
  red: Colors.red,
  green: Colors.green,
  blue: Colors.blue,
  yellow: Colors.yellow,
  orange: Colors.orange,
  purple: Colors.purple,
  pink: Colors.pink,
  grey: Colors.grey,
  gray: Colors.grey,
  brown: Colors.brown,
  cyan: Colors.cyan,
  indigo: Colors.indigo,
  lime: Colors.lime,
  teal: Colors.teal,
  amber: Colors.amber,
  deeporange: Colors.deepOrange,
  'deep-orange': Colors.deepOrange,
  deeppurple: Colors.deepPurple,
  'deep-purple': Colors.deepPurple,
  lightblue: Colors.lightBlue,
  'light-blue': Colors.lightBlue,
  lightgreen: Colors.lightGreen,
  'light-green': Colors.lightGreen,
  bluegrey: Colors.blueGrey,
  'blue-grey': Colors.blueGrey,
};

// The CSS keyword colours that Flutter's table does not define.
const cssNamed: Record<string, number> = {
  aliceblue: 0xf0f8ff, antiquewhite: 0xfaebd7, aqua: 0x00ffff, aquamarine: 0x7fffd4,
  azure: 0xf0ffff, beige: 0xf5f5dc, bisque: 0xffe4c4, blanchedalmond: 0xffebcd,
  blueviolet: 0x8a2be2, burlywood: 0xdeb887, cadetblue: 0x5f9ea0, chartreuse: 0x7fff00,
  chocolate: 0xd2691e, coral: 0xff7f50, cornflowerblue: 0x6495ed, cornsilk: 0xfff8dc,
  crimson: 0xdc143c, darkblue: 0x00008b, darkcyan: 0x008b8b, darkgoldenrod: 0xb8860b,
  darkgray: 0xa9a9a9, darkgrey: 0xa9a9a9, darkgreen: 0x006400, darkkhaki: 0xbdb76b,
  darkmagenta: 0x8b008b, darkolivegreen: 0x556b2f, darkorange: 0xff8c00, darkorchid: 0x9932cc,
  darkred: 0x8b0000, darksalmon: 0xe9967a, darkseagreen: 0x8fbc8f, darkslateblue: 0x483d8b,
  darkslategray: 0x2f4f4f, darkslategrey: 0x2f4f4f, darkturquoise: 0x00ced1, darkviolet: 0x9400d3,
  deeppink: 0xff1493, deepskyblue: 0x00bfff, dimgray: 0x696969, dimgrey: 0x696969,
  dodgerblue: 0x1e90ff, firebrick: 0xb22222, floralwhite: 0xfffaf0, forestgreen: 0x228b22,
  fuchsia: 0xff00ff, gainsboro: 0xdcdcdc, ghostwhite: 0xf8f8ff, gold: 0xffd700,
  goldenrod: 0xdaa520, greenyellow: 0xadff2f, honeydew: 0xf0fff0, hotpink: 0xff69b4,
  indianred: 0xcd5c5c, ivory: 0xfffff0, khaki: 0xf0e68c, lavender: 0xe6e6fa,
  lavenderblush: 0xfff0f5, lawngreen: 0x7cfc00, lemonchiffon: 0xfffacd, lightcoral: 0xf08080,
  lightcyan: 0xe0ffff, lightgoldenrodyellow: 0xfafad2, lightgray: 0xd3d3d3, lightgrey: 0xd3d3d3,
  lightpink: 0xffb6c1, lightsalmon: 0xffa07a, lightseagreen: 0x20b2aa, lightskyblue: 0x87cefa,
  lightslategray: 0x778899, lightslategrey: 0x778899, lightsteelblue: 0xb0c4de, lightyellow: 0xffffe0,
  limegreen: 0x32cd32, linen: 0xfaf0e6, magenta: 0xff00ff, maroon: 0x800000,
  mediumaquamarine: 0x66cdaa, mediumblue: 0x0000cd, mediumorchid: 0xba55d3, mediumpurple: 0x9370db,
  mediumseagreen: 0x3cb371, mediumslateblue: 0x7b68ee, mediumspringgreen: 0x00fa9a,
  mediumturquoise: 0x48d1cc, mediumvioletred: 0xc71585, midnightblue: 0x191970, mintcream: 0xf5fffa,
  mistyrose: 0xffe4e1, moccasin: 0xffe4b5, navajowhite: 0xffdead, navy: 0x000080,
  oldlace: 0xfdf5e6, olive: 0x808000, olivedrab: 0x6b8e23, orangered: 0xff4500,
  orchid: 0xda70d6, palegoldenrod: 0xeee8aa, palegreen: 0x98fb98, paleturquoise: 0xafeeee,
  palevioletred: 0xdb7093, papayawhip: 0xffefd5, peachpuff: 0xffdab9, peru: 0xcd853f,
  plum: 0xdda0dd, powderblue: 0xb0e0e6, rebeccapurple: 0x663399, rosybrown: 0xbc8f8f,
  royalblue: 0x4169e1, saddlebrown: 0x8b4513, salmon: 0xfa8072, sandybrown: 0xf4a460,
  seagreen: 0x2e8b57, seashell: 0xfff5ee, sienna: 0xa0522d, silver: 0xc0c0c0,
  skyblue: 0x87ceeb, slateblue: 0x6a5acd, slategray: 0x708090, slategrey: 0x708090,
  snow: 0xfffafa, springgreen: 0x00ff7f, steelblue: 0x4682b4, tan: 0xd2b48c,
  thistle: 0xd8bfd8, tomato: 0xff6347, turquoise: 0x40e0d0, violet: 0xee82ee,
  wheat: 0xf5deb3, whitesmoke: 0xf5f5f5, yellowgreen: 0x9acd32,
};

export function argb(a: number, r: number, g: number, b: number): Color {
  return (((a & 0xff) << 24) | ((r & 0xff) << 16) | ((g & 0xff) << 8) | (b & 0xff)) >>> 0;
}

export const alphaOf = (c: Color) => (c >>> 24) & 0xff;
export const redOf = (c: Color) => (c >>> 16) & 0xff;
export const greenOf = (c: Color) => (c >>> 8) & 0xff;
export const blueOf = (c: Color) => c & 0xff;

/** Replace the alpha channel with [opacity] (0..1) — `Color.withValues(alpha:)`. */
export function withOpacity(c: Color, opacity: number): Color {
  const a = Math.round(Math.max(0, Math.min(1, opacity)) * 255);
  return ((c & 0x00ffffff) | (a << 24)) >>> 0;
}

/** Multiply the existing alpha by [factor]. */
export function scaleAlpha(c: Color, factor: number): Color {
  return withOpacity(c, (alphaOf(c) / 255) * factor);
}

export function lerpColor(a: Color, b: Color, t: number): Color {
  const l = (x: number, y: number) => Math.round(x + (y - x) * t);
  return argb(l(alphaOf(a), alphaOf(b)), l(redOf(a), redOf(b)), l(greenOf(a), greenOf(b)), l(blueOf(a), blueOf(b)));
}

export function toCssColor(c: Color): string {
  const a = alphaOf(c);
  if (a === 255) {
    return '#' + (c & 0xffffff).toString(16).padStart(6, '0');
  }
  return `rgba(${redOf(c)},${greenOf(c)},${blueOf(c)},${+(a / 255).toFixed(4)})`;
}

function hslToRgb(h: number, s: number, l: number): [number, number, number] {
  // HSLColor.toColor in Flutter.
  const chroma = (1 - Math.abs(2 * l - 1)) * s;
  const hp = (((h % 360) + 360) % 360) / 60;
  const x = chroma * (1 - Math.abs((hp % 2) - 1));
  let r = 0, g = 0, b = 0;
  if (hp < 1) [r, g, b] = [chroma, x, 0];
  else if (hp < 2) [r, g, b] = [x, chroma, 0];
  else if (hp < 3) [r, g, b] = [0, chroma, x];
  else if (hp < 4) [r, g, b] = [0, x, chroma];
  else if (hp < 5) [r, g, b] = [x, 0, chroma];
  else [r, g, b] = [chroma, 0, x];
  const m = l - chroma / 2;
  return [Math.round((r + m) * 255), Math.round((g + m) * 255), Math.round((b + m) * 255)];
}

function channel(token: string, scale: number): number {
  const t = token.trim();
  if (t.endsWith('%')) return (parseFloat(t) / 100) * scale;
  return parseFloat(t);
}

function alphaChannel(token: string | undefined): number {
  if (token == null || token.trim() === '') return 1;
  const t = token.trim();
  if (t.endsWith('%')) return parseFloat(t) / 100;
  return parseFloat(t);
}

const cache = new Map<string, Color | null>();

export function parseColor(value: unknown): Color | null {
  if (value == null) return null;
  if (typeof value === 'number') return value >>> 0;
  if (typeof value !== 'string') return null;
  const cached = cache.get(value);
  if (cached !== undefined) return cached;
  const parsed = parseColorString(value.trim());
  if (cache.size > 2048) cache.clear();
  cache.set(value, parsed);
  return parsed;
}

function parseColorString(raw: string): Color | null {
  if (raw === '') return null;
  const lower = raw.toLowerCase();

  if (lower.startsWith('#')) {
    let hex = lower.substring(1);
    if (hex.length === 3 || hex.length === 4) {
      hex = hex.split('').map((c) => c + c).join('');
    }
    if (!/^[0-9a-f]+$/.test(hex)) return null;
    if (hex.length === 6) return (0xff000000 | parseInt(hex, 16)) >>> 0;
    if (hex.length === 8) return parseInt(hex, 16) >>> 0; // AARRGGBB, as Flutter
    return null;
  }

  if (lower.startsWith('0x')) {
    const n = parseInt(lower.substring(2), 16);
    if (Number.isFinite(n)) return (lower.length <= 8 ? 0xff000000 | n : n) >>> 0;
    return null;
  }

  const fn = /^(rgba?|hsla?)\(\s*([^)]*)\)$/.exec(lower);
  if (fn) {
    const body = fn[2];
    let parts: string[];
    let alphaPart: string | undefined;
    if (body.includes(',')) {
      parts = body.split(',').map((p) => p.trim());
      if (parts.length === 4) alphaPart = parts.pop();
    } else {
      const [main, a] = body.split('/');
      parts = main.trim().split(/\s+/);
      alphaPart = a;
      if (parts.length === 4 && alphaPart == null) alphaPart = parts.pop();
    }
    if (parts.length < 3) return null;
    const alpha = Math.max(0, Math.min(1, alphaChannel(alphaPart)));
    if (fn[1].startsWith('rgb')) {
      const r = channel(parts[0], 255), g = channel(parts[1], 255), b = channel(parts[2], 255);
      if ([r, g, b, alpha].some((n) => Number.isNaN(n))) return null;
      // Flutter truncates alpha: (a * 255).toInt()
      return argb(Math.trunc(alpha * 255), Math.round(r), Math.round(g), Math.round(b));
    }
    let h = parseFloat(parts[0]);
    if (parts[0].endsWith('turn')) h *= 360;
    else if (parts[0].endsWith('rad')) h = (h * 180) / Math.PI;
    const s = parseFloat(parts[1]) / 100;
    const l = parseFloat(parts[2]) / 100;
    if ([h, s, l, alpha].some((n) => Number.isNaN(n))) return null;
    const [r, g, b] = hslToRgb(h, s, l);
    return argb(Math.round(alpha * 255), r, g, b);
  }

  const named = flutterNamed[lower];
  if (named !== undefined) return named >>> 0;
  const css = cssNamed[lower];
  if (css !== undefined) return (0xff000000 | css) >>> 0;
  if (lower === 'currentcolor') return null;
  return null;
}
