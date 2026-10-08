/**
 * JSON helpers shared by every layer of the core.
 *
 * The VM boundary speaks JSON strings in both directions, and guest payloads are
 * notoriously loose: a payload may be a JSON document, a bare string, a quoted
 * string, or a positional argument list. These helpers normalise that once so
 * the host APIs can read their arguments the same way the Flutter
 * `HostHandler` does.
 */

export type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
export type JsonMap = Record<string, any>;

export function isMap(value: unknown): value is JsonMap {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

/** Parse a VM payload: JSON when it is JSON, a bare string otherwise. */
export function parseVmPayload(payload: string): any {
  if (payload === '' || payload == null) return null;
  try {
    return JSON.parse(payload);
  } catch {
    if (payload.length >= 2 && payload.startsWith('"') && payload.endsWith('"')) {
      return payload.substring(1, payload.length - 1);
    }
    return payload;
  }
}

/** The first positional argument when the payload is an argument list. */
export function unwrapHostArgs(parsed: any): any {
  if (Array.isArray(parsed)) return parsed.length === 0 ? null : parsed[0];
  return parsed;
}

/** Positional arguments, always as a list. */
export function asHostArgs(parsed: any): any[] {
  return Array.isArray(parsed) ? parsed : [parsed];
}

/** The payload's first argument coerced to a map (empty when it is not one). */
export function normalizedArgs(payload: string): JsonMap {
  const unwrapped = unwrapHostArgs(parseVmPayload(payload));
  return isMap(unwrapped) ? unwrapped : {};
}

/** A JSON map from a value that may itself be a JSON-encoded string. */
export function coerceJsonMap(value: unknown): JsonMap | null {
  if (isMap(value)) return value;
  if (typeof value !== 'string') return null;
  try {
    const decoded = JSON.parse(value);
    return isMap(decoded) ? decoded : null;
  } catch {
    return null;
  }
}

export function toNumber(value: unknown): number | null {
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  if (typeof value === 'string') {
    const n = parseFloat(value);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

export function toInt(value: unknown): number | null {
  const n = toNumber(value);
  return n == null ? null : Math.trunc(n);
}

export function toStr(value: unknown): string | null {
  if (value == null) return null;
  return typeof value === 'string' ? value : String(value);
}

/** Structural equality for JSON-shaped values. */
export function deepEqual(a: any, b: any): boolean {
  if (a === b) return true;
  if (typeof a !== typeof b || a == null || b == null) return false;
  if (Array.isArray(a)) {
    if (!Array.isArray(b) || a.length !== b.length) return false;
    for (let i = 0; i < a.length; i++) if (!deepEqual(a[i], b[i])) return false;
    return true;
  }
  if (typeof a === 'object') {
    if (Array.isArray(b)) return false;
    const ka = Object.keys(a);
    const kb = Object.keys(b);
    if (ka.length !== kb.length) return false;
    for (const k of ka) if (!deepEqual(a[k], b[k])) return false;
    return true;
  }
  return false;
}

/** Deep-merge [patch] into a copy of [base] (maps merge, everything else replaces). */
export function deepMerge(base: JsonMap, patch: JsonMap): JsonMap {
  const result: JsonMap = { ...base };
  for (const key of Object.keys(patch)) {
    const pv = patch[key];
    const bv = result[key];
    result[key] = isMap(pv) && isMap(bv) ? deepMerge(bv, pv) : pv;
  }
  return result;
}

/** Stable string form of a JSON value — used as a cache key. */
export function stableKey(value: any): string {
  if (value === undefined) return 'u';
  if (value === null || typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) return '[' + value.map(stableKey).join(',') + ']';
  const keys = Object.keys(value).sort();
  return '{' + keys.map((k) => JSON.stringify(k) + ':' + stableKey(value[k])).join(',') + '}';
}

export function clamp(v: number, lo: number, hi: number): number {
  return v < lo ? lo : v > hi ? hi : v;
}
