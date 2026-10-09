/**
 * The A2UI message processor — pure state, no UI.
 *
 * It applies server-to-client messages to surfaces:
 *
 * - `createSurface` registers a surface with its catalog (unknown catalog ids
 *   are an error), theme and `sendDataModel` flag; creating an existing
 *   surface is an error;
 * - `updateComponents` upserts the flat adjacency list. Components arriving
 *   before `root` are buffered: a surface is renderable once `root` exists;
 * - `updateDataModel` writes (or, with no / null value, deletes) a JSON
 *   Pointer path of the surface's data model; path `/` replaces it;
 * - `deleteSurface` removes the surface.
 *
 * Inputs write back through [setData] (two-way binding), and interactions go
 * through [dispatchAction], which resolves an `action.event` into the
 * client-to-server `action` (name, surfaceId, sourceComponentId, ISO
 * timestamp, resolved context) and emits it, or runs an `action.functionCall`
 * locally. Listeners observe every change, action and error.
 */
import { BASIC_CATALOG, type A2UICatalog } from './catalog.js';
import { DataContext, resolveAction, type EvaluationHost } from './context.js';
import { cloneJson, DataModel } from './data-model.js';
import { A2UIError } from './errors.js';
import { messageKind, validateMessage } from './validator.js';

/** The protocol version this renderer speaks. */
export const A2UI_VERSION = 'v0.9.1';

export type ValidationMode = 'strict' | 'lenient' | 'off';

export interface A2UIProcessorOptions extends EvaluationHost {
  /** Catalogs this client supports (default: the basic catalog). */
  catalogs?: A2UICatalog[];
  /**
   * `strict` rejects a message with any schema issue; `lenient` (default)
   * reports issues but still applies what it can (unknown components render
   * as placeholders); `off` skips schema validation.
   */
  validation?: ValidationMode;
}

export interface A2UIComponent {
  id: string;
  component: string;
  [prop: string]: unknown;
}

/** The client-to-server `action` payload. */
export interface A2UIClientAction {
  name: string;
  surfaceId: string;
  sourceComponentId: string;
  timestamp: string;
  context: Record<string, unknown>;
  /** Carried through when the action defines one (conformance `userMessage`). */
  userMessage?: string;
}

export type A2UIProcessorEvent =
  | { type: 'surfaceCreated'; surfaceId: string }
  | { type: 'surfaceUpdated'; surfaceId: string; reason: 'components' | 'data' | 'local' }
  | { type: 'surfaceDeleted'; surfaceId: string }
  | { type: 'action'; action: A2UIClientAction }
  | { type: 'error'; error: A2UIError };

export type A2UIProcessorListener = (event: A2UIProcessorEvent) => void;

export class A2UISurfaceModel {
  readonly components = new Map<string, A2UIComponent>();
  readonly dataModel = new DataModel();
  /** Bumped on every change (components, data, local writes). */
  version = 0;

  constructor(
    readonly id: string,
    readonly catalog: A2UICatalog,
    /** The catalog id exactly as `createSurface` named it. */
    readonly catalogId: string,
    readonly theme: Record<string, unknown>,
    readonly sendDataModel: boolean,
    private readonly host: EvaluationHost,
  ) {}

  /** The `root` component, once it has arrived. */
  get root(): A2UIComponent | undefined {
    return this.components.get('root');
  }

  /** Whether the surface can render (components are buffered until `root` exists). */
  get isReady(): boolean {
    return this.components.has('root');
  }

  /** An evaluation context scoped to [scope]. */
  context(scope = '/'): DataContext {
    return new DataContext(this.dataModel, this.catalog, scope, this.host);
  }
}

const isObj = (v: unknown): v is Record<string, any> => v !== null && typeof v === 'object' && !Array.isArray(v);

export class A2UIProcessor {
  private readonly surfaceMap = new Map<string, A2UISurfaceModel>();
  private readonly listeners = new Set<A2UIProcessorListener>();
  readonly catalogs: A2UICatalog[];
  readonly validation: ValidationMode;

  constructor(readonly options: A2UIProcessorOptions = {}) {
    this.catalogs = options.catalogs ?? [BASIC_CATALOG];
    this.validation = options.validation ?? 'lenient';
  }

  /** Catalog ids this client supports (for `a2uiClientCapabilities`). */
  get supportedCatalogIds(): string[] {
    return this.catalogs.map((c) => c.id);
  }

  catalogFor(catalogId: string): A2UICatalog | null {
    return this.catalogs.find((c) => c.id === catalogId || (c.aliases ?? []).includes(catalogId)) ?? null;
  }

  on(listener: A2UIProcessorListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  private emit(event: A2UIProcessorEvent): void {
    for (const l of [...this.listeners]) {
      try {
        l(event);
      } catch (e) {
        console.warn('A2UI listener failed:', e);
      }
    }
  }

  private report(error: A2UIError): A2UIError {
    this.emit({ type: 'error', error });
    return error;
  }

  /** Surfaces in creation order. */
  get surfaces(): A2UISurfaceModel[] {
    return [...this.surfaceMap.values()];
  }

  surface(surfaceId: string): A2UISurfaceModel | undefined {
    return this.surfaceMap.get(surfaceId);
  }

  /** Apply several messages; returns every error. */
  processAll(messages: readonly unknown[]): A2UIError[] {
    const out: A2UIError[] = [];
    for (const m of messages) out.push(...this.process(m));
    return out;
  }

  /** Apply one server-to-client message; returns its errors (also emitted). */
  process(message: unknown): A2UIError[] {
    const kind = messageKind(message);
    if (!kind || !isObj(message)) {
      return [this.report(new A2UIError('ValidationError', 'Not an A2UI message: expected one of createSurface, updateComponents, updateDataModel, deleteSurface', { path: '/' }))];
    }
    const body = message[kind];
    const surfaceId = isObj(body) && typeof body.surfaceId === 'string' ? body.surfaceId : null;
    const errors: A2UIError[] = [];
    if (this.validation !== 'off') {
      const catalog = surfaceId ? this.surfaceMap.get(surfaceId)?.catalog : undefined;
      const issues = validateMessage(message, catalog ?? this.catalogs[0], { requireVersion: this.validation === 'strict' });
      for (const e of issues) errors.push(this.report(e));
      if (issues.length && this.validation === 'strict') return errors;
    }
    if (!surfaceId) {
      if (!errors.length) errors.push(this.report(new A2UIError('ValidationError', `${kind} requires a "surfaceId"`, { path: `/${kind}/surfaceId` })));
      return errors;
    }
    const fail = (message: string, path = `/${kind}`) => {
      errors.push(this.report(new A2UIError('ValidationError', message, { surfaceId, path })));
      return errors;
    };
    switch (kind) {
      case 'createSurface': {
        if (this.surfaceMap.has(surfaceId)) return fail(`Surface "${surfaceId}" already exists; delete it before creating it again`);
        const catalogId = typeof body.catalogId === 'string' ? body.catalogId : '';
        const catalog = this.catalogFor(catalogId);
        if (!catalog) return fail(`Unsupported catalog "${catalogId}" (supported: ${this.supportedCatalogIds.join(', ')})`, '/createSurface/catalogId');
        const surface = new A2UISurfaceModel(surfaceId, catalog, catalogId, isObj(body.theme) ? { ...body.theme } : {}, body.sendDataModel === true, this.options);
        this.surfaceMap.set(surfaceId, surface);
        this.emit({ type: 'surfaceCreated', surfaceId });
        return errors;
      }
      case 'updateComponents': {
        const surface = this.surfaceMap.get(surfaceId);
        if (!surface) return fail(`Surface "${surfaceId}" has not been created`);
        if (!Array.isArray(body.components)) return errors;
        for (const c of body.components) {
          if (!isObj(c) || typeof c.id !== 'string' || typeof c.component !== 'string') continue;
          surface.components.set(c.id, cloneJson(c) as A2UIComponent);
        }
        surface.version++;
        this.emit({ type: 'surfaceUpdated', surfaceId, reason: 'components' });
        return errors;
      }
      case 'updateDataModel': {
        const surface = this.surfaceMap.get(surfaceId);
        if (!surface) return fail(`Surface "${surfaceId}" has not been created`);
        const path = typeof body.path === 'string' ? body.path : '/';
        try {
          // An omitted or null value removes the key (list slots become null).
          if (body.value === undefined || body.value === null) surface.dataModel.delete(path);
          else surface.dataModel.set(path, body.value);
        } catch (e) {
          if (e instanceof A2UIError) {
            errors.push(this.report(new A2UIError(e.category === 'DataError' ? 'DataError' : 'ValidationError', e.message, { surfaceId, path: '/updateDataModel/path' })));
            return errors;
          }
          throw e;
        }
        surface.version++;
        this.emit({ type: 'surfaceUpdated', surfaceId, reason: 'data' });
        return errors;
      }
      case 'deleteSurface': {
        const surface = this.surfaceMap.get(surfaceId);
        if (!surface) return fail(`Surface "${surfaceId}" does not exist`);
        surface.dataModel.dispose();
        this.surfaceMap.delete(surfaceId);
        this.emit({ type: 'surfaceDeleted', surfaceId });
        return errors;
      }
    }
    return errors;
  }

  /** A local write through a two-way binding (an input changed). */
  setData(surfaceId: string, path: string, value: unknown): void {
    const surface = this.surfaceMap.get(surfaceId);
    if (!surface) return;
    try {
      surface.dataModel.set(path, value);
    } catch (e) {
      if (e instanceof A2UIError) {
        this.report(new A2UIError(e.category, e.message, { surfaceId, path }));
        return;
      }
      throw e;
    }
    surface.version++;
    this.emit({ type: 'surfaceUpdated', surfaceId, reason: 'local' });
  }

  /** The surface's current data model (a copy). */
  dataModel(surfaceId: string): unknown {
    return this.surfaceMap.get(surfaceId)?.dataModel.snapshot();
  }

  /**
   * The `a2uiClientDataModel` metadata: the models of the surfaces created
   * with `sendDataModel: true`, or null when there are none.
   */
  clientDataModel(): { version: string; surfaces: Record<string, unknown> } | null {
    const surfaces: Record<string, unknown> = {};
    let any = false;
    for (const s of this.surfaceMap.values()) {
      if (!s.sendDataModel) continue;
      surfaces[s.id] = s.dataModel.snapshot();
      any = true;
    }
    return any ? { version: A2UI_VERSION, surfaces } : null;
  }

  /**
   * The user interacted with [componentId]: resolve its [action] in [scope].
   * An `event` becomes an {@link A2UIClientAction}, emitted and returned; a
   * `functionCall` runs locally (returns null). Failures are reported and
   * return null.
   */
  dispatchAction(surfaceId: string, componentId: string, action: unknown, scope = '/', now: Date = new Date()): A2UIClientAction | null {
    const surface = this.surfaceMap.get(surfaceId);
    if (!surface) return null;
    try {
      const event = resolveAction(action, surface.context(scope));
      if (!event) {
        surface.version++;
        this.emit({ type: 'surfaceUpdated', surfaceId, reason: 'local' });
        return null;
      }
      const out: A2UIClientAction = { name: event.name, surfaceId, sourceComponentId: componentId, timestamp: now.toISOString(), context: event.context };
      if (event.userMessage !== undefined) out.userMessage = event.userMessage;
      this.emit({ type: 'action', action: out });
      return out;
    } catch (e) {
      const err = e instanceof A2UIError ? e : new A2UIError('ExpressionError', String(e instanceof Error ? e.message : e));
      this.report(new A2UIError(err.category, err.message, { surfaceId, path: null }));
      return null;
    }
  }

  /** Remove every surface. */
  reset(): void {
    for (const id of [...this.surfaceMap.keys()]) {
      this.surfaceMap.get(id)!.dataModel.dispose();
      this.surfaceMap.delete(id);
      this.emit({ type: 'surfaceDeleted', surfaceId: id });
    }
  }
}

/** The client-to-server message carrying [action]. */
export function clientActionMessage(action: A2UIClientAction): { version: string; action: A2UIClientAction } {
  return { version: A2UI_VERSION, action };
}
