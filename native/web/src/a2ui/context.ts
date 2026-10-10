/**
 * `DataContext` — evaluation of dynamic values within a data scope.
 *
 * A dynamic value is a literal, a data binding `{ "path": "…" }` or a function
 * call `{ "call": "…", "args": {…}, "returnType": "…" }`. Paths are absolute
 * (`/user/name`) or relative to the context's scope (the template item a
 * component was instantiated for, e.g. `/users/0`). Function arguments are
 * evaluated recursively — lists element by element — before the function runs.
 */
import { A2UIError, expressionError } from './errors.js';
import type { A2UICatalog } from './catalog.js';
import type { DataModel } from './data-model.js';
import type { FunctionContext } from './functions.js';
import { stringifyValue, toBool } from './functions.js';
import { resolvePath } from './pointer.js';

export interface EvaluationHost {
  /** BCP 47 locale for formatting (default `en-US`). */
  locale?: string;
  /** Base for relative URLs (`openUrl`). */
  baseUrl?: string | null;
  /** Perform `openUrl` (already validated to be http/https). */
  openUrl?(url: string): void;
  /** Observe a function call before it runs (tests, tracing). */
  onCall?(name: string, args: Record<string, unknown>): void;
}

const isPlainObject = (v: unknown): v is Record<string, any> => v !== null && typeof v === 'object' && !Array.isArray(v);

/** `{ "path": "…" }` and nothing else. */
export function isBinding(v: unknown): v is { path: string } {
  return isPlainObject(v) && typeof v.path === 'string' && Object.keys(v).every((k) => k === 'path');
}

/** `{ "call": "…", "args"?: {…}, "returnType"?: "…" }`. */
export function isFunctionCall(v: unknown): v is { call: string; args?: Record<string, unknown>; returnType?: string } {
  return isPlainObject(v) && typeof v.call === 'string' && Object.keys(v).every((k) => k === 'call' || k === 'args' || k === 'returnType');
}

export class DataContext {
  constructor(
    readonly model: DataModel,
    readonly catalog: A2UICatalog,
    /** The data scope relative paths resolve against (`/` at the root). */
    readonly scope: string = '/',
    readonly host: EvaluationHost = {},
  ) {}

  get locale(): string {
    return this.host.locale ?? 'en-US';
  }

  /** A context scoped to [scope] (an absolute pointer). */
  child(scope: string): DataContext {
    return new DataContext(this.model, this.catalog, scope, this.host);
  }

  resolvePath(path: string): string {
    return resolvePath(path, this.scope);
  }

  read(path: string): unknown {
    return this.model.get(this.resolvePath(path));
  }

  write(path: string, value: unknown): void {
    this.model.set(this.resolvePath(path), value);
  }

  /** The absolute path a binding writes to, or null when [value] is not a binding. */
  bindingPath(value: unknown): string | null {
    return isBinding(value) ? this.resolvePath(value.path) : null;
  }

  /** Evaluate a dynamic property value (literal lists stay literal). */
  evaluate(value: unknown): unknown {
    if (isBinding(value)) return this.read(value.path);
    if (isFunctionCall(value)) return this.call(value.call, value.args ?? {});
    return value;
  }

  /** Evaluate and coerce to a string (`''` for null/undefined). */
  string(value: unknown): string {
    return stringifyValue(this.evaluate(value));
  }

  /** Evaluate and coerce to a number (null when not numeric). */
  number(value: unknown): number | null {
    const v = this.evaluate(value);
    if (typeof v === 'number') return Number.isFinite(v) ? v : null;
    if (typeof v === 'string' && v.trim() !== '') {
      const n = Number(v);
      return Number.isFinite(n) ? n : null;
    }
    return null;
  }

  boolean(value: unknown): boolean {
    return toBool(this.evaluate(value));
  }

  /** Evaluate to a list of strings (non-lists become `[]`, a lone string `[s]`). */
  stringList(value: unknown): string[] {
    const v = this.evaluate(value);
    if (Array.isArray(v)) return v.filter((x) => x != null).map((x) => stringifyValue(x));
    if (typeof v === 'string' && v !== '') return [v];
    return [];
  }

  /** Evaluate a function argument: bindings, calls, and lists of them. */
  argument(value: unknown): unknown {
    if (Array.isArray(value)) return value.map((v) => this.argument(v));
    return this.evaluate(value);
  }

  /** Call catalog function [name] with unevaluated [args]. */
  call(name: string, args: Record<string, unknown>): unknown {
    const impl = this.catalog.implementations[name];
    if (!impl) throw expressionError(`Unknown function "${name}"`);
    const resolved: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(isPlainObject(args) ? args : {})) resolved[k] = this.argument(v);
    this.host.onCall?.(name, resolved);
    return impl(resolved, this.functionContext());
  }

  private functionContext(): FunctionContext {
    return {
      locale: this.locale,
      baseUrl: this.host.baseUrl ?? null,
      read: (path) => this.read(path),
      call: (name, args) => this.call(name, args),
      openUrl: this.host.openUrl ? (url) => this.host.openUrl!(url) : undefined,
    };
  }

  /**
   * Evaluate without throwing: expression errors (unknown function, bad
   * template) yield [fallback] and are reported to [onError].
   */
  safe<T>(fn: () => T, fallback: T, onError?: (e: A2UIError) => void): T {
    try {
      return fn();
    } catch (e) {
      const err = e instanceof A2UIError ? e : expressionError(String(e instanceof Error ? e.message : e));
      onError?.(err);
      return fallback;
    }
  }
}

/** A failing check: its message. */
export interface CheckFailure {
  message: string;
}

/**
 * Run a component's `checks` and return the messages of those that fail. A
 * check is `{ condition, message }`; the protocol document's shorthand
 * `{ call, args, message }` is accepted too.
 */
export function evaluateChecks(checks: unknown, ctx: DataContext, onError?: (e: A2UIError) => void): string[] {
  if (!Array.isArray(checks)) return [];
  const failures: string[] = [];
  for (const check of checks) {
    if (!isPlainObject(check)) continue;
    const condition = 'condition' in check ? check.condition : typeof check.call === 'string' ? { call: check.call, args: check.args ?? {} } : true;
    const ok = ctx.safe(() => ctx.boolean(condition), false, onError);
    if (!ok) failures.push(typeof check.message === 'string' ? check.message : 'Invalid value');
  }
  return failures;
}

/** An `action.event` with its context resolved. */
export interface ResolvedEvent {
  name: string;
  context: Record<string, unknown>;
  userMessage?: string;
}

/**
 * Resolve an `Action`: `{ event: { name, context } }` (also the v0.9 shorthand
 * `{ name, context }`) becomes a {@link ResolvedEvent} with every context value
 * evaluated now; `{ functionCall }` runs locally and yields null.
 */
export function resolveAction(action: unknown, ctx: DataContext): ResolvedEvent | null {
  if (!isPlainObject(action)) throw expressionError('Action must be an object');
  if (isPlainObject(action.functionCall)) {
    const fc = action.functionCall;
    if (typeof fc.call !== 'string') throw expressionError('functionCall needs a "call" name');
    ctx.call(fc.call, isPlainObject(fc.args) ? fc.args : {});
    return null;
  }
  const event = isPlainObject(action.event) ? action.event : typeof action.name === 'string' ? action : null;
  if (!event || typeof event.name !== 'string') throw expressionError('Action needs an "event" with a "name"');
  const context: Record<string, unknown> = {};
  if (isPlainObject(event.context)) {
    for (const [k, v] of Object.entries(event.context)) {
      const value = ctx.evaluate(v);
      context[k] = value === undefined ? null : value;
    }
  }
  const out: ResolvedEvent = { name: event.name, context };
  if (typeof event.userMessage === 'string') out.userMessage = event.userMessage;
  return out;
}
