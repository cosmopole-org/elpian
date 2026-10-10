/**
 * The basic catalog's client-side functions, implemented as the basic catalog
 * implementation guide describes them: validation (`required`, `regex`,
 * `length`, `numeric`, `email`), formatting (`formatString`, `formatNumber`,
 * `formatCurrency`, `formatDate`, `pluralize`), logic (`and`, `or`, `not`)
 * and the `openUrl` side effect.
 *
 * A function receives its arguments already resolved (bindings read, nested
 * calls evaluated) and a {@link FunctionContext}; only `formatString` reaches
 * back into the context, to evaluate the expressions inside its template.
 */
import { expressionError } from './errors.js';
import { parseTemplate, type TemplatePart, type TemplateValue } from './expressions.js';

export interface FunctionContext {
  readonly locale: string;
  /** Resolve a data path (relative paths against the current scope). */
  read(path: string): unknown;
  /** Evaluate a function call with unresolved (expression) arguments. */
  call(name: string, args: Record<string, unknown>): unknown;
  /** Open a URL (already validated); absent when the host cannot. */
  openUrl?(url: string): void;
  /** The base for resolving relative URLs in `openUrl`. */
  readonly baseUrl?: string | null;
}

export type A2UIFunction = (args: Record<string, any>, ctx: FunctionContext) => unknown;

/** Stringify an interpolated value the way the protocol prescribes. */
export function stringifyValue(value: unknown): string {
  if (value === null || value === undefined) return '';
  if (typeof value === 'string') return value;
  if (typeof value === 'number' || typeof value === 'boolean') return String(value);
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

export function toBool(value: unknown): boolean {
  return value === true || value === 'true';
}

function toNum(value: unknown): number | null {
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (typeof value === 'string' && value.trim() !== '') {
    const n = Number(value);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** Evaluate one parsed template value against [ctx]. */
export function evaluateTemplateValue(value: TemplateValue | TemplatePart, ctx: FunctionContext): unknown {
  if (value === null || typeof value !== 'object') return value;
  if ('path' in value) return ctx.read(value.path);
  return ctx.call(value.call, value.args);
}

function numberFormat(locale: string, options: Intl.NumberFormatOptions): Intl.NumberFormat {
  try {
    return new Intl.NumberFormat(locale, options);
  } catch {
    return new Intl.NumberFormat('en-US', options);
  }
}

function fractionOptions(args: Record<string, any>): Intl.NumberFormatOptions {
  const out: Intl.NumberFormatOptions = { useGrouping: args.grouping !== false };
  const decimals = toNum(args.decimals);
  if (decimals != null) {
    const d = Math.max(0, Math.min(20, Math.trunc(decimals)));
    out.minimumFractionDigits = d;
    out.maximumFractionDigits = d;
  }
  return out;
}

export const BASIC_FUNCTIONS: Record<string, A2UIFunction> = {
  required: ({ value }) => !(value === null || value === undefined || value === '' || (Array.isArray(value) && value.length === 0)),

  regex: ({ value, pattern }) => {
    if (typeof pattern !== 'string') throw expressionError('regex: "pattern" must be a string');
    let re: RegExp;
    try {
      re = new RegExp(pattern);
    } catch (e) {
      throw expressionError(`regex: invalid pattern "${pattern}"`);
    }
    return re.test(stringifyValue(value));
  },

  length: ({ value, min, max }) => {
    const n = stringifyValue(value).length;
    if (toNum(min) != null && n < (toNum(min) as number)) return false;
    if (toNum(max) != null && n > (toNum(max) as number)) return false;
    return true;
  },

  numeric: ({ value, min, max }) => {
    const n = toNum(value);
    if (n == null) return false;
    if (toNum(min) != null && n < (toNum(min) as number)) return false;
    if (toNum(max) != null && n > (toNum(max) as number)) return false;
    return true;
  },

  email: ({ value }) => typeof value === 'string' && EMAIL.test(value),

  formatString: ({ value }, ctx) => {
    if (value === null || value === undefined) return '';
    const parts = parseTemplate(stringifyValue(value));
    return parts.map((p) => stringifyValue(evaluateTemplateValue(p, ctx))).join('');
  },

  formatNumber: (args, ctx) => {
    const n = toNum(args.value);
    if (n == null) return '';
    return numberFormat(ctx.locale, fractionOptions(args)).format(n);
  },

  formatCurrency: (args, ctx) => {
    const n = toNum(args.value);
    if (n == null) return '';
    const currency = typeof args.currency === 'string' && /^[A-Za-z]{3}$/.test(args.currency) ? args.currency.toUpperCase() : 'USD';
    return numberFormat(ctx.locale, { style: 'currency', currency, ...fractionOptions(args) }).format(n);
  },

  formatDate: ({ value, format }, ctx) => {
    const date = parseDate(value);
    if (!date) return '';
    return formatDatePattern(date, typeof format === 'string' && format ? format : 'yyyy-MM-dd', ctx.locale);
  },

  pluralize: (args, ctx) => {
    const n = toNum(args.value);
    if (n == null) return stringifyValue(args.other);
    let category: string = 'other';
    try {
      category = new Intl.PluralRules(ctx.locale).select(n);
    } catch {
      category = n === 1 ? 'one' : 'other';
    }
    // English (and most locales) report 0 as "other"; an explicit zero form wins.
    if (n === 0 && args.zero !== undefined) category = 'zero';
    const chosen = args[category] !== undefined ? args[category] : args.other;
    return stringifyValue(chosen);
  },

  openUrl: ({ url }, ctx) => {
    const resolved = validateOpenUrl(url, ctx.baseUrl ?? null);
    ctx.openUrl?.(resolved);
    return undefined;
  },

  and: ({ values }) => {
    if (!Array.isArray(values)) throw expressionError('and: "values" must be a list');
    for (const v of values) if (!toBool(v)) return false;
    return true;
  },

  or: ({ values }) => {
    if (!Array.isArray(values)) throw expressionError('or: "values" must be a list');
    for (const v of values) if (toBool(v)) return true;
    return false;
  },

  not: ({ value }) => !toBool(value),
};

/**
 * `openUrl`'s mandatory checks: resolve relative URLs against [base], then
 * allow only `http:` and `https:` (no `javascript:`, `data:`, …).
 */
export function validateOpenUrl(url: unknown, base: string | null): string {
  if (typeof url !== 'string' || url.trim() === '') throw expressionError('openUrl: "url" must be a non-empty string');
  const raw = url.trim();
  let resolved = raw;
  const scheme = /^([a-zA-Z][a-zA-Z0-9+.-]*):/.exec(raw);
  if (!scheme) {
    if (!base) throw expressionError(`openUrl: cannot resolve relative URL "${raw}"`);
    try {
      resolved = new URL(raw, base).toString();
    } catch {
      throw expressionError(`openUrl: invalid URL "${raw}"`);
    }
  }
  const protocol = (/^([a-zA-Z][a-zA-Z0-9+.-]*):/.exec(resolved)?.[1] ?? '').toLowerCase();
  if (protocol !== 'http' && protocol !== 'https') throw expressionError(`openUrl: the "${protocol}:" scheme is not allowed (http and https only)`);
  return resolved;
}

// ----------------------------------------------------------------------------
// Dates
// ----------------------------------------------------------------------------

/**
 * Parse an A2UI date value: an ISO 8601 date-time (`2026-02-02T15:17:00Z`),
 * a date (`2026-02-02`, local midnight), a time (`14:30`, today), or epoch
 * milliseconds.
 */
export function parseDate(value: unknown): Date | null {
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
  if (typeof value === 'number') return Number.isFinite(value) ? new Date(value) : null;
  if (typeof value !== 'string' || value.trim() === '') return null;
  const s = value.trim();
  let m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s);
  if (m) return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]));
  m = /^(\d{1,2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?$/.exec(s);
  if (m) {
    const d = new Date();
    d.setHours(Number(m[1]), Number(m[2]), Number(m[3] ?? 0), 0);
    return d;
  }
  // A date-time without an offset is local time (as `Date` reads it); with one, absolute.
  const d = new Date(s);
  return Number.isNaN(d.getTime()) ? null : d;
}

function pad(n: number, width: number): string {
  return String(n).padStart(width, '0');
}

function names(locale: string, options: Intl.DateTimeFormatOptions, date: Date): string {
  try {
    return new Intl.DateTimeFormat(locale, options).format(date);
  } catch {
    return new Intl.DateTimeFormat('en-US', options).format(date);
  }
}

/** Format [date] with a Unicode TR35 pattern (`yyyy-MM-dd`, `EEEE, MMM d 'at' h:mm a`, …). */
export function formatDatePattern(date: Date, pattern: string, locale = 'en-US'): string {
  let out = '';
  let i = 0;
  while (i < pattern.length) {
    const ch = pattern[i];
    if (ch === "'") {
      // Quoted literal; '' is a single quote.
      if (pattern[i + 1] === "'") {
        out += "'";
        i += 2;
        continue;
      }
      let j = i + 1;
      while (j < pattern.length) {
        if (pattern[j] === "'" && pattern[j + 1] === "'") {
          out += "'";
          j += 2;
          continue;
        }
        if (pattern[j] === "'") break;
        out += pattern[j++];
      }
      i = j + 1;
      continue;
    }
    if (!/[A-Za-z]/.test(ch)) {
      out += ch;
      i++;
      continue;
    }
    let n = 1;
    while (pattern[i + n] === ch) n++;
    i += n;
    out += field(date, ch, n, locale);
  }
  return out;
}

function field(d: Date, ch: string, n: number, locale: string): string {
  switch (ch) {
    case 'y':
    case 'Y':
    case 'u':
      return n === 2 ? pad(d.getFullYear() % 100, 2) : pad(d.getFullYear(), n);
    case 'M':
    case 'L':
      if (n >= 4) return names(locale, { month: 'long' }, d);
      if (n === 3) return names(locale, { month: 'short' }, d);
      return pad(d.getMonth() + 1, n);
    case 'd':
      return pad(d.getDate(), n);
    case 'D': {
      const start = new Date(d.getFullYear(), 0, 1);
      return pad(Math.floor((d.getTime() - start.getTime()) / 86400000) + 1, n);
    }
    case 'E':
    case 'e':
    case 'c':
      if (n === 5) return names(locale, { weekday: 'narrow' }, d);
      if (n >= 4) return names(locale, { weekday: 'long' }, d);
      return names(locale, { weekday: 'short' }, d);
    case 'a':
      return d.getHours() < 12 ? 'AM' : 'PM';
    case 'h':
      return pad(d.getHours() % 12 === 0 ? 12 : d.getHours() % 12, n);
    case 'K':
      return pad(d.getHours() % 12, n);
    case 'H':
      return pad(d.getHours(), n);
    case 'k':
      return pad(d.getHours() === 0 ? 24 : d.getHours(), n);
    case 'm':
      return pad(d.getMinutes(), n);
    case 's':
      return pad(d.getSeconds(), n);
    case 'S':
      return pad(d.getMilliseconds(), 3).substring(0, n);
    case 'z':
    case 'Z':
    case 'x':
    case 'X': {
      const offset = -d.getTimezoneOffset();
      if (offset === 0 && (ch === 'X' || ch === 'x')) return 'Z';
      const sign = offset >= 0 ? '+' : '-';
      const abs = Math.abs(offset);
      return `${sign}${pad(Math.floor(abs / 60), 2)}:${pad(abs % 60, 2)}`;
    }
    default:
      return ch.repeat(n);
  }
}
