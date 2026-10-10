/**
 * JSON Pointers (RFC 6901) as A2UI uses them: absolute paths (`/user/name`),
 * relative paths resolved against a data scope (`name` inside a template
 * item at `/users/0`), `.`/`..` segments, and tolerant normalisation of empty
 * segments (`//a///b//` is `/a/b`).
 */
import { dataError, A2UIError } from './errors.js';

/** Segments that would reach a JavaScript prototype; refused on read and write. */
const FORBIDDEN = new Set(['__proto__', 'constructor', 'prototype']);

/** True when [path] only uses valid `~0` / `~1` escapes. */
export function isValidPointerSyntax(path: string): boolean {
  return !/~(?![01])/.test(path);
}

/** Decode one reference token (`~1` → `/`, then `~0` → `~`). */
export function decodeSegment(token: string): string {
  return token.replace(/~1/g, '/').replace(/~0/g, '~');
}

/** Encode one key as a reference token. */
export function encodeSegment(key: string): string {
  return key.replace(/~/g, '~0').replace(/\//g, '~1');
}

/**
 * The decoded segments of an absolute pointer. Empty segments are dropped, so
 * `''`, `'/'` and `'///'` all address the root.
 */
export function parsePointer(path: string): string[] {
  if (!isValidPointerSyntax(path)) {
    throw new A2UIError('ValidationError', `Invalid path syntax: "${path}" uses an escape other than ~0 or ~1`, { path });
  }
  const segments = path.split('/').filter((s) => s !== '').map(decodeSegment);
  for (const s of segments) if (FORBIDDEN.has(s)) throw dataError(`Forbidden path segment "${s}" in "${path}"`);
  return segments;
}

/** The canonical pointer for [segments] (`/` for the root). */
export function formatPointer(segments: readonly string[]): string {
  return segments.length === 0 ? '/' : '/' + segments.map(encodeSegment).join('/');
}

/** Normalise a pointer to its canonical spelling. */
export function normalizePointer(path: string): string {
  return formatPointer(parsePointer(path));
}

/**
 * Resolve [path] against the data scope [contextPath] (`/` when absent):
 * absolute paths ignore the scope; `''` and `.` mean the scope itself; `..`
 * walks up one level.
 */
export function resolvePath(path: string, contextPath?: string | null): string {
  if (path.startsWith('/')) return path;
  const base = (contextPath ?? '/').split('/').filter((s) => s !== '');
  for (const raw of path.split('/')) {
    if (raw === '' || raw === '.') continue;
    if (raw === '..') base.pop();
    else base.push(raw);
  }
  return base.length === 0 ? '/' : '/' + base.join('/');
}

/** Array index segments: `0` or a digit run without a leading zero. */
export function isIndexSegment(segment: string): boolean {
  return /^(0|[1-9][0-9]*)$/.test(segment);
}

/** Whether [ancestor] is [path] or a prefix of it, segment-wise. */
export function isPrefixOf(ancestor: readonly string[], path: readonly string[]): boolean {
  if (ancestor.length > path.length) return false;
  for (let i = 0; i < ancestor.length; i++) if (ancestor[i] !== path[i]) return false;
  return true;
}
