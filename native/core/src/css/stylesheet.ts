/**
 * Stylesheets and the cascade — a port of `CSSStylesheet`,
 * `GlobalStylesheetManager` and `JsonStylesheetParser`.
 *
 * Flutter resolves only bare `tag`, `.class` and `#id` selectors, in the order
 * tag → classes → id → @media → inline, with `!important` declarations
 * re-applied on top. That ordering is preserved exactly. The selector engine
 * is a superset: compound selectors (`button.primary#go`), selector lists
 * (`h1, h2`), and descendant / child combinators when the caller supplies the
 * element's ancestry. Custom properties (`--x`) declared on `:root` (or via a
 * JSON stylesheet's `variables`) are substituted into `var(--x, fallback)`.
 */
import { cssEnvironment } from './environment.js';
import { isImportant, splitTopLevel, stripImportant } from './parser.js';
import type { Keyframe } from './types.js';

export type StyleMap = Record<string, any>;

/** The facts about an element a selector can test. */
export interface ElementFacts {
  tagName: string;
  id?: string | null;
  classes?: string[] | null;
  attributes?: Record<string, any> | null;
}

interface CompoundSelector {
  tag: string | null;
  id: string | null;
  classes: string[];
  attrs: { name: string; value: string | null }[];
  universal: boolean;
  root: boolean;
}

interface ComplexSelector {
  /** Rightmost compound first; each step names the combinator to its left. */
  parts: { compound: CompoundSelector; combinator: ' ' | '>' | null }[];
  specificity: number;
}

export class CSSRule {
  readonly selectors: ComplexSelector[];
  constructor(
    readonly selector: string,
    readonly styles: StyleMap,
    readonly order: number,
  ) {
    this.selectors = parseSelectorList(selector);
  }

  toCSS(): string {
    const body = Object.entries(this.styles)
      .map(([k, v]) => `  ${k}: ${v};`)
      .join('\n');
    return `${this.selector} {\n${body}\n}\n`;
  }
}

let ruleCounter = 0;

export class CSSStylesheet {
  private rules: CSSRule[] = [];
  private keyframes = new Map<string, Keyframe[]>();
  /** Fast path: rules whose every selector is a single simple tag/class/id. */
  private simple = new Map<string, CSSRule[]>();

  addRule(selector: string, styles: StyleMap): void {
    const rule = new CSSRule(selector.trim(), styles, ruleCounter++);
    // Re-declaring an identical selector replaces it (Flutter's map semantics).
    this.removeRule(rule.selector);
    this.rules.push(rule);
    this.simple.clear();
  }

  removeRule(selector: string): void {
    const before = this.rules.length;
    this.rules = this.rules.filter((r) => r.selector !== selector);
    if (this.rules.length !== before) this.simple.clear();
  }

  get allRules(): readonly CSSRule[] {
    return this.rules;
  }

  getStyle(selector: string): StyleMap | undefined {
    return this.rules.find((r) => r.selector === selector)?.styles;
  }

  addKeyframeAnimation(name: string, frames: Keyframe[]): void {
    this.keyframes.set(name, frames);
  }

  getKeyframes(name: string): Keyframe[] | undefined {
    return this.keyframes.get(name);
  }

  get keyframeNames(): string[] {
    return [...this.keyframes.keys()];
  }

  /** Root custom properties (`:root { --x: … }`). */
  variables(): StyleMap {
    const out: StyleMap = {};
    for (const rule of this.rules) {
      if (rule.selectors.some((s) => s.parts.length === 1 && s.parts[0].compound.root)) {
        for (const [k, v] of Object.entries(rule.styles)) if (k.startsWith('--')) out[k] = v;
      }
    }
    return out;
  }

  /**
   * The raw cascaded map for an element: matched rules in specificity then
   * source order (tag < class < id, as in Flutter), then [inlineStyles].
   */
  getComputedStyleMap(element: ElementFacts, ancestors: ElementFacts[] = [], inlineStyles?: StyleMap | null): StyleMap {
    const merged: StyleMap = {};
    for (const rule of this.matching(element, ancestors)) Object.assign(merged, rule.styles);
    if (inlineStyles) Object.assign(merged, inlineStyles);
    return merged;
  }

  matching(element: ElementFacts, ancestors: ElementFacts[]): CSSRule[] {
    const matched: { rule: CSSRule; specificity: number }[] = [];
    for (const rule of this.rules) {
      let best = -1;
      for (const sel of rule.selectors) {
        if (sel.specificity > best && matchesComplex(sel, element, ancestors)) best = sel.specificity;
      }
      if (best >= 0) matched.push({ rule, specificity: best });
    }
    matched.sort((a, b) => a.specificity - b.specificity || a.rule.order - b.rule.order);
    return matched.map((m) => m.rule);
  }

  clear(): void {
    this.rules = [];
    this.keyframes.clear();
    this.simple.clear();
  }

  toCSS(): string {
    return this.rules.map((r) => r.toCSS()).join('\n');
  }

  /** Parse CSS text into this stylesheet; returns the `@media` blocks found. */
  parseCSS(cssText: string): { query: string; sheet: CSSStylesheet }[] {
    return parseCssText(cssText, this);
  }
}

export class MediaQuery {
  constructor(
    readonly query: string,
    readonly stylesheet: CSSStylesheet,
  ) {}

  matches(width: number, height: number): boolean {
    return mediaMatches(this.query, width, height);
  }
}

/** Flutter's media matcher, extended with `and`/`,`, `not`, aspect ratios and colour scheme. */
export function mediaMatches(query: string, width: number, height: number, darkMode = false): boolean {
  const alternatives = query.split(',').map((q) => q.trim()).filter((q) => q);
  if (alternatives.length === 0) return true;
  return alternatives.some((alt) => {
    let negate = false;
    let q = alt.toLowerCase();
    if (q.startsWith('not ')) {
      negate = true;
      q = q.substring(4);
    }
    q = q.replace(/^only\s+/, '');
    let ok = true;
    for (const m of q.matchAll(/(min|max)-(width|height):\s*([\d.]+)(px|em|rem)?/g)) {
      const isMin = m[1] === 'min';
      const isWidth = m[2] === 'width';
      let threshold = parseFloat(m[3]);
      if (m[4] === 'em' || m[4] === 'rem') threshold *= cssEnvironment().rootFontSize;
      const actual = isWidth ? width : height;
      if (isMin && actual < threshold) ok = false;
      if (!isMin && actual > threshold) ok = false;
    }
    const om = /orientation:\s*(portrait|landscape)/.exec(q);
    if (om && (om[1] === 'landscape') !== width >= height) ok = false;
    for (const m of q.matchAll(/(min|max)-aspect-ratio:\s*(\d+)\s*\/\s*(\d+)/g)) {
      const ratio = parseFloat(m[2]) / parseFloat(m[3]);
      const actual = height > 0 ? width / height : 0;
      if (m[1] === 'min' && actual < ratio) ok = false;
      if (m[1] === 'max' && actual > ratio) ok = false;
    }
    const scheme = /prefers-color-scheme:\s*(dark|light)/.exec(q);
    if (scheme && (scheme[1] === 'dark') !== darkMode) ok = false;
    if (/\bprint\b/.test(q) && !/\bscreen\b/.test(q)) ok = false;
    return negate ? !ok : ok;
  });
}

/**
 * The per-mini-app stylesheet manager (`GlobalStylesheetManager`): a global
 * sheet, `@media` sheets, keyframes, and the `!important` cascade.
 */
export class StylesheetManager {
  readonly global = new CSSStylesheet();
  private mediaQueries: MediaQuery[] = [];
  /** Bumped on every change so render caches can invalidate. */
  version = 0;
  darkMode = false;

  addMediaQuery(query: string, sheet: CSSStylesheet): void {
    this.mediaQueries = this.mediaQueries.filter((mq) => mq.query !== query);
    this.mediaQueries.push(new MediaQuery(query, sheet));
    this.version++;
  }

  touch(): void {
    this.version++;
  }

  keyframes(name: string): Keyframe[] | undefined {
    const own = this.global.getKeyframes(name);
    if (own) return own;
    for (const mq of this.mediaQueries) {
      const frames = mq.stylesheet.getKeyframes(name);
      if (frames) return frames;
    }
    return undefined;
  }

  get hasRules(): boolean {
    return this.global.allRules.length > 0 || this.mediaQueries.length > 0;
  }

  getComputedStyleMap(
    element: ElementFacts,
    options: { ancestors?: ElementFacts[]; inlineStyles?: StyleMap | null; screenWidth?: number; screenHeight?: number } = {},
  ): StyleMap {
    const merged: StyleMap = {};
    const important: StyleMap = {};
    const mergeRaw = (raw: StyleMap | null | undefined) => {
      if (!raw) return;
      for (const [key, value] of Object.entries(raw)) {
        const stripped = stripImportant(value);
        merged[key] = stripped;
        if (isImportant(value)) important[key] = stripped;
      }
    };
    const ancestors = options.ancestors ?? [];
    mergeRaw(this.global.getComputedStyleMap(element, ancestors));
    if (this.mediaQueries.length > 0) {
      const env = cssEnvironment();
      const w = options.screenWidth ?? env.viewportWidth;
      const h = options.screenHeight ?? env.viewportHeight;
      for (const mq of this.mediaQueries) {
        if (mediaMatches(mq.query, w, h, this.darkMode)) mergeRaw(mq.stylesheet.getComputedStyleMap(element, ancestors));
      }
    }
    if (options.inlineStyles) mergeRaw(options.inlineStyles);
    Object.assign(merged, important);
    return this.substituteVariables(merged);
  }

  /** Replace `var(--name, fallback)` with root / element custom properties. */
  substituteVariables(map: StyleMap): StyleMap {
    let needs = false;
    for (const v of Object.values(map)) {
      if (typeof v === 'string' && v.includes('var(')) {
        needs = true;
        break;
      }
    }
    if (!needs) return map;
    const vars = { ...this.global.variables() };
    for (const [k, v] of Object.entries(map)) if (k.startsWith('--')) vars[k] = v;
    const out: StyleMap = {};
    for (const [k, v] of Object.entries(map)) out[k] = typeof v === 'string' ? resolveVars(v, vars, 0) : v;
    return out;
  }

  clear(): void {
    this.global.clear();
    this.mediaQueries = [];
    this.version++;
  }

  /** Load a JSON stylesheet (`{rules, mediaQueries, variables, keyframes}`) or CSS text. */
  load(json: StyleMap | string): void {
    if (typeof json === 'string') {
      const blocks = this.global.parseCSS(json);
      for (const block of blocks) this.addMediaQuery(block.query, block.sheet);
      this.version++;
      return;
    }
    const sheet = parseJsonStylesheet(json, (query, mq) => this.addMediaQuery(query, mq));
    for (const rule of sheet.allRules) this.global.addRule(rule.selector, rule.styles);
    for (const name of sheet.keyframeNames) this.global.addKeyframeAnimation(name, sheet.getKeyframes(name)!);
    if (typeof json.css === 'string') this.load(json.css);
    this.version++;
  }
}

function resolveVars(value: string, vars: StyleMap, depth: number): any {
  if (depth > 8 || !value.includes('var(')) return value;
  const replaced = value.replace(/var\(\s*(--[\w-]+)\s*(?:,\s*([^()]*(?:\([^()]*\)[^()]*)*))?\)/g, (_m, name: string, fallback?: string) => {
    const v = vars[name];
    if (v != null) return String(v);
    return fallback != null ? fallback.trim() : '';
  });
  return resolveVars(replaced, vars, depth + 1);
}

/** `JsonStylesheetParser.parseJsonStylesheet`. */
export function parseJsonStylesheet(json: StyleMap, onMedia: (query: string, sheet: CSSStylesheet) => void): CSSStylesheet {
  const sheet = new CSSStylesheet();
  const rules = json.rules;
  if (Array.isArray(rules)) {
    const mediaGroups = new Map<string, CSSStylesheet>();
    for (const rule of rules) {
      if (!rule || typeof rule !== 'object') continue;
      const media = rule.media;
      if (typeof media === 'string' && media.trim() !== '') {
        let group = mediaGroups.get(media);
        if (!group) mediaGroups.set(media, (group = new CSSStylesheet()));
        addJsonRule(rule, group);
      } else {
        addJsonRule(rule, sheet);
      }
    }
    for (const [query, group] of mediaGroups) onMedia(query, group);
  }
  const mediaQueries = json.mediaQueries;
  if (Array.isArray(mediaQueries)) {
    for (const mq of mediaQueries) {
      if (!mq || typeof mq.query !== 'string') continue;
      const group = new CSSStylesheet();
      if (Array.isArray(mq.rules)) for (const r of mq.rules) addJsonRule(r, group);
      onMedia(mq.query, group);
    }
  }
  const variables = json.variables;
  if (variables && typeof variables === 'object') {
    const vars: StyleMap = {};
    for (const [k, v] of Object.entries(variables)) vars[k.startsWith('--') ? k : `--${k}`] = v;
    sheet.addRule(':root', vars);
  }
  const keyframes = json.keyframes;
  if (Array.isArray(keyframes)) {
    for (const kf of keyframes) {
      if (!kf || typeof kf.name !== 'string' || !Array.isArray(kf.frames)) continue;
      const frames: Keyframe[] = [];
      for (const f of kf.frames) {
        if (f && typeof f.offset === 'number' && f.styles && typeof f.styles === 'object') {
          frames.push({ offset: f.offset, styles: f.styles });
        }
      }
      sheet.addKeyframeAnimation(kf.name, frames);
    }
  }
  return sheet;
}

function addJsonRule(rule: any, sheet: CSSStylesheet): void {
  if (!rule || typeof rule.selector !== 'string' || !rule.styles || typeof rule.styles !== 'object') return;
  sheet.addRule(rule.selector, rule.styles);
}

// ============================================================================
// CSS text
// ============================================================================

function parseDeclarations(body: string): StyleMap {
  const styles: StyleMap = {};
  for (const decl of splitTopLevel(body, ';')) {
    const idx = decl.indexOf(':');
    if (idx <= 0) continue;
    const key = decl.substring(0, idx).trim();
    let value: any = decl.substring(idx + 1).trim();
    if (key === '' || value === '') continue;
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    } else if (/^-?\d+(\.\d+)?(px)?$/.test(value)) {
      value = parseFloat(value);
    }
    styles[key] = value;
  }
  return styles;
}

function stripComments(css: string): string {
  return css.replace(/\/\*[\s\S]*?\*\//g, '');
}

/** Split CSS text into top-level blocks: `[prelude, body]`. */
function blocksOf(css: string): [string, string][] {
  const out: [string, string][] = [];
  let depth = 0;
  let preludeStart = 0;
  let bodyStart = -1;
  for (let i = 0; i < css.length; i++) {
    const ch = css[i];
    if (ch === '{') {
      if (depth === 0) bodyStart = i + 1;
      depth++;
    } else if (ch === '}') {
      depth--;
      if (depth === 0 && bodyStart >= 0) {
        out.push([css.substring(preludeStart, bodyStart - 1).trim(), css.substring(bodyStart, i)]);
        preludeStart = i + 1;
        bodyStart = -1;
      }
    } else if (ch === ';' && depth === 0) {
      // A top-level at-statement such as `@import …;` — skipped.
      preludeStart = i + 1;
    }
  }
  return out;
}

function parseCssText(css: string, sheet: CSSStylesheet): { query: string; sheet: CSSStylesheet }[] {
  const media: { query: string; sheet: CSSStylesheet }[] = [];
  for (const [prelude, body] of blocksOf(stripComments(css))) {
    if (prelude.startsWith('@media')) {
      const query = prelude.substring(6).trim();
      const inner = new CSSStylesheet();
      parseCssText(body, inner);
      media.push({ query, sheet: inner });
    } else if (prelude.startsWith('@keyframes') || prelude.startsWith('@-webkit-keyframes')) {
      const name = prelude.replace(/^@(-webkit-)?keyframes/, '').trim();
      const frames: Keyframe[] = [];
      for (const [sel, decls] of blocksOf(body)) {
        const styles = parseDeclarations(decls);
        for (const part of sel.split(',')) {
          const t = part.trim().toLowerCase();
          const offset = t === 'from' ? 0 : t === 'to' ? 1 : parseFloat(t) / 100;
          if (Number.isFinite(offset)) frames.push({ offset, styles });
        }
      }
      frames.sort((a, b) => a.offset - b.offset);
      sheet.addKeyframeAnimation(name, frames);
    } else if (prelude.startsWith('@supports') || prelude.startsWith('@layer')) {
      media.push(...parseCssText(body, sheet));
    } else if (!prelude.startsWith('@')) {
      sheet.addRule(prelude, parseDeclarations(body));
    }
  }
  return media;
}

/** `JsonStylesheetParser.cssToJson`. */
export function cssToJson(cssText: string): StyleMap {
  const sheet = new CSSStylesheet();
  const media = parseCssText(cssText, sheet);
  const rules: StyleMap[] = sheet.allRules.map((r) => ({ selector: r.selector, styles: r.styles }));
  for (const m of media) for (const r of m.sheet.allRules) rules.push({ selector: r.selector, styles: r.styles, media: m.query });
  return { rules };
}

// ============================================================================
// Selectors
// ============================================================================

function parseCompound(text: string): CompoundSelector | null {
  const c: CompoundSelector = { tag: null, id: null, classes: [], attrs: [], universal: false, root: false };
  let i = 0;
  const ident = () => {
    const m = /^-?[_a-zA-Z0-9 -￿-][_a-zA-Z0-9 -￿\\-]*/.exec(text.substring(i));
    if (!m) return null;
    i += m[0].length;
    return m[0];
  };
  if (text[0] === '*') {
    c.universal = true;
    i = 1;
  } else if (/[a-zA-Z]/.test(text[0] ?? '')) {
    c.tag = ident();
  }
  while (i < text.length) {
    const ch = text[i];
    if (ch === '.') {
      i++;
      const name = ident();
      if (!name) return null;
      c.classes.push(name);
    } else if (ch === '#') {
      i++;
      const name = ident();
      if (!name) return null;
      c.id = name;
    } else if (ch === '[') {
      const end = text.indexOf(']', i);
      if (end < 0) return null;
      const inner = text.substring(i + 1, end);
      const eq = inner.indexOf('=');
      if (eq < 0) c.attrs.push({ name: inner.trim(), value: null });
      else c.attrs.push({ name: inner.substring(0, eq).trim(), value: inner.substring(eq + 1).trim().replace(/^["']|["']$/g, '') });
      i = end + 1;
    } else if (ch === ':') {
      // Pseudo-classes: `:root` is honoured; interactive states (hover, focus…)
      // never match statically, which is what an un-hovered element shows.
      const m = /^::?([a-zA-Z-]+)(\([^)]*\))?/.exec(text.substring(i));
      if (!m) return null;
      i += m[0].length;
      if (m[1] === 'root') c.root = true;
      else if (!['first-child', 'last-child'].includes(m[1])) return null;
    } else {
      return null;
    }
  }
  return c;
}

function parseComplex(text: string): ComplexSelector | null {
  const tokens: string[] = [];
  const combinators: (' ' | '>')[] = [];
  const normalized = text.replace(/\s*>\s*/g, '>').replace(/\s+/g, ' ').trim();
  let current = '';
  for (const ch of normalized) {
    if (ch === ' ' || ch === '>') {
      if (current) tokens.push(current);
      current = '';
      combinators.push(ch);
    } else {
      current += ch;
    }
  }
  if (current) tokens.push(current);
  if (tokens.length === 0 || combinators.length !== tokens.length - 1) return null;
  const compounds = tokens.map(parseCompound);
  if (compounds.some((c) => c == null)) return null;
  const parts: ComplexSelector['parts'] = [];
  for (let k = compounds.length - 1; k >= 0; k--) {
    parts.push({ compound: compounds[k]!, combinator: k > 0 ? combinators[k - 1] : null });
  }
  let ids = 0, classes = 0, tags = 0;
  for (const c of compounds) {
    if (c!.id) ids++;
    classes += c!.classes.length + c!.attrs.length + (c!.root ? 1 : 0);
    if (c!.tag) tags++;
  }
  return { parts, specificity: ids * 10000 + classes * 100 + tags };
}

function parseSelectorList(selector: string): ComplexSelector[] {
  return splitTopLevel(selector, ',')
    .map((s) => s.trim())
    .filter((s) => s)
    .map(parseComplex)
    .filter((s): s is ComplexSelector => s != null);
}

function matchesCompound(c: CompoundSelector, el: ElementFacts): boolean {
  if (c.root) return el.tagName === ':root' || el.tagName === 'html';
  if (c.tag && c.tag !== el.tagName && c.tag.toLowerCase() !== el.tagName.toLowerCase()) return false;
  if (c.id && c.id !== el.id) return false;
  if (c.classes.length) {
    const own = el.classes ?? [];
    for (const cls of c.classes) if (!own.includes(cls)) return false;
  }
  for (const attr of c.attrs) {
    const v = el.attributes?.[attr.name];
    if (v === undefined) return false;
    if (attr.value != null && String(v) !== attr.value) return false;
  }
  return c.universal || c.tag != null || c.id != null || c.classes.length > 0 || c.attrs.length > 0;
}

function matchesComplex(sel: ComplexSelector, el: ElementFacts, ancestors: ElementFacts[]): boolean {
  const [first, ...rest] = sel.parts;
  if (!matchesCompound(first.compound, el)) return false;
  // ancestors are ordered nearest-first.
  let combinator = first.combinator;
  let index = 0;
  for (const part of rest) {
    if (combinator === '>') {
      const parent = ancestors[index];
      if (!parent || !matchesCompound(part.compound, parent)) return false;
      index++;
    } else {
      let found = false;
      while (index < ancestors.length) {
        const candidate = ancestors[index++];
        if (matchesCompound(part.compound, candidate)) {
          found = true;
          break;
        }
      }
      if (!found) return false;
    }
    combinator = part.combinator;
  }
  return true;
}
