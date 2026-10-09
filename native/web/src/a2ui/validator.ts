/**
 * Client-side validation of server-to-client messages.
 *
 * - [validateMessage] checks one message against the envelope schema and the
 *   catalog's component / function tables (types, enums, required and unknown
 *   properties, binding path syntax, function-call nesting, `formatString`
 *   templates, data nesting).
 * - [A2UIValidator] validates batches statefully and, in strict mode, also
 *   checks the component graph each batch leaves behind: a `root` exists,
 *   no duplicate ids in one message, no self references, dangling
 *   references or cycles, every component is reachable from `root`, and the
 *   tree is at most {@link MAX_NESTING} deep.
 *
 * Issues are {@link A2UIError}s of category `ValidationError` whose `path` is a
 * JSON Pointer into the message (the protocol's `VALIDATION_FAILED` shape).
 */
import { A2UIError, type A2UIIssueCode } from './errors.js';
import { childReferences, COMMON_PROPS, ICON_NAMES, type A2UICatalog, type PropKind } from './catalog.js';
import { parseTemplate } from './expressions.js';
import { isValidPointerSyntax } from './pointer.js';

export const SUPPORTED_VERSIONS: readonly string[] = ['v0.9', 'v0.9.1'];
export const MESSAGE_KINDS = ['createSurface', 'updateComponents', 'updateDataModel', 'deleteSurface'] as const;
export type MessageKind = (typeof MESSAGE_KINDS)[number];
/** Deepest component tree / data value accepted. */
export const MAX_NESTING = 50;
/** Deepest nesting of function calls inside one dynamic value. */
export const MAX_CALL_DEPTH = 5;

const isObj = (v: unknown): v is Record<string, any> => v !== null && typeof v === 'object' && !Array.isArray(v);

export interface ValidateOptions {
  /** Require the `version` field (the agent runtime fills it; lenient renderers may not insist). */
  requireVersion?: boolean;
}

class Issues {
  readonly list: A2UIError[] = [];
  constructor(readonly surfaceId: string | null) {}
  add(path: string, issue: A2UIIssueCode, message: string): void {
    this.list.push(new A2UIError('ValidationError', message, { surfaceId: this.surfaceId, path: path || '/', issue }));
  }
}

/** The message kind ([MESSAGE_KINDS]) of [msg], or null. */
export function messageKind(msg: unknown): MessageKind | null {
  if (!isObj(msg)) return null;
  for (const k of MESSAGE_KINDS) if (k in msg) return k;
  return null;
}

/** The surface a message addresses, when it names one. */
export function messageSurfaceId(msg: unknown): string | null {
  const kind = messageKind(msg);
  if (!kind || !isObj(msg)) return null;
  const body = msg[kind];
  return isObj(body) && typeof body.surfaceId === 'string' ? body.surfaceId : null;
}

/** Schema-level validation of one server-to-client message. */
export function validateMessage(msg: unknown, catalog: A2UICatalog, options: ValidateOptions = {}): A2UIError[] {
  const issues = new Issues(messageSurfaceId(msg));
  if (!isObj(msg)) {
    issues.add('/', 'type_mismatch', 'A message must be a JSON object');
    return issues.list;
  }
  if (msg.version === undefined) {
    if (options.requireVersion !== false) issues.add('/version', 'missing_field', 'The "version" field is required');
  } else if (typeof msg.version !== 'string' || !SUPPORTED_VERSIONS.includes(msg.version)) {
    issues.add('/version', 'invalid_value', `Unsupported version ${JSON.stringify(msg.version)} (expected v0.9 or v0.9.1)`);
  }
  const kinds = MESSAGE_KINDS.filter((k) => k in msg);
  if (kinds.length !== 1) {
    issues.add('/', kinds.length ? 'invalid_value' : 'missing_field', `A message must contain exactly one of ${MESSAGE_KINDS.join(', ')}`);
    return issues.list;
  }
  for (const k of Object.keys(msg)) if (k !== 'version' && k !== kinds[0]) issues.add(`/${k}`, 'unknown_field', `Unknown message field "${k}"`);
  const kind = kinds[0];
  const body = msg[kind];
  const base = `/${kind}`;
  if (!isObj(body)) {
    issues.add(base, 'type_mismatch', `"${kind}" must be an object`);
    return issues.list;
  }
  const allowed: Record<MessageKind, string[]> = {
    createSurface: ['surfaceId', 'catalogId', 'theme', 'sendDataModel'],
    updateComponents: ['surfaceId', 'components'],
    updateDataModel: ['surfaceId', 'path', 'value'],
    deleteSurface: ['surfaceId'],
  };
  for (const k of Object.keys(body)) if (!allowed[kind].includes(k)) issues.add(`${base}/${k}`, 'unknown_field', `Unknown field "${k}" in ${kind}`);
  requireString(issues, body, 'surfaceId', base);
  switch (kind) {
    case 'createSurface':
      requireString(issues, body, 'catalogId', base);
      if (body.theme !== undefined) validateTheme(issues, body.theme, `${base}/theme`);
      if (body.sendDataModel !== undefined && typeof body.sendDataModel !== 'boolean') issues.add(`${base}/sendDataModel`, 'type_mismatch', '"sendDataModel" must be a boolean');
      break;
    case 'updateComponents':
      if (!('components' in body)) issues.add(`${base}/components`, 'missing_field', '"components" is required');
      else if (!Array.isArray(body.components)) issues.add(`${base}/components`, 'type_mismatch', '"components" must be a list');
      else {
        if (body.components.length === 0) issues.add(`${base}/components`, 'invalid_value', '"components" must not be empty');
        body.components.forEach((c: unknown, i: number) => validateComponent(issues, c, catalog, `${base}/components/${i}`));
      }
      break;
    case 'updateDataModel':
      if (body.path !== undefined) {
        if (typeof body.path !== 'string') issues.add(`${base}/path`, 'type_mismatch', '"path" must be a string');
        else if (!isValidPointerSyntax(body.path)) issues.add(`${base}/path`, 'invalid_value', `Invalid path syntax: "${body.path}"`);
      }
      if (body.value !== undefined && depthOf(body.value) > MAX_NESTING) {
        issues.add(`${base}/value`, 'limit', `Global recursion limit exceeded: the value nests deeper than ${MAX_NESTING} levels`);
      }
      break;
    case 'deleteSurface':
      break;
  }
  return issues.list;
}

function requireString(issues: Issues, body: Record<string, any>, key: string, base: string): void {
  if (!(key in body)) issues.add(`${base}/${key}`, 'missing_field', `"${key}" is required`);
  else if (typeof body[key] !== 'string') issues.add(`${base}/${key}`, 'type_mismatch', `"${key}" must be a string`);
}

function validateTheme(issues: Issues, theme: unknown, path: string): void {
  if (!isObj(theme)) {
    issues.add(path, 'type_mismatch', '"theme" must be an object');
    return;
  }
  if (theme.primaryColor !== undefined && (typeof theme.primaryColor !== 'string' || !/^#[0-9a-fA-F]{6}$/.test(theme.primaryColor))) {
    issues.add(`${path}/primaryColor`, 'invalid_value', '"primaryColor" must be a hex color like #00BFFF');
  }
  for (const k of ['iconUrl', 'agentDisplayName']) {
    if (theme[k] !== undefined && typeof theme[k] !== 'string') issues.add(`${path}/${k}`, 'type_mismatch', `"${k}" must be a string`);
  }
}

function depthOf(value: unknown): number {
  if (value === null || typeof value !== 'object') return 0;
  let max = 0;
  for (const v of Array.isArray(value) ? value : Object.values(value)) max = Math.max(max, depthOf(v));
  return max + 1;
}

/** Validate one component definition against [catalog]. */
function validateComponent(issues: Issues, c: unknown, catalog: A2UICatalog, base: string): void {
  if (!isObj(c)) {
    issues.add(base, 'type_mismatch', 'A component must be an object');
    return;
  }
  requireString(issues, c, 'id', base);
  if (!('component' in c)) {
    issues.add(`${base}/component`, 'missing_field', '"component" is required');
    return;
  }
  if (typeof c.component !== 'string') {
    issues.add(`${base}/component`, 'type_mismatch', '"component" must be a string');
    return;
  }
  const spec = catalog.components[c.component];
  if (!spec) {
    issues.add(`${base}/component`, 'invalid_value', `Unknown component type "${c.component}"`);
    return;
  }
  for (const [k, v] of Object.entries(c)) {
    if (k === 'id' || k === 'component') continue;
    const ps = spec.props[k] ?? COMMON_PROPS[k];
    if (!ps) {
      issues.add(`${base}/${k}`, 'unknown_field', `Unknown property "${k}" on ${c.component}`);
      continue;
    }
    checkKind(issues, v, ps.kind, `${base}/${k}`, catalog);
    if (ps.enum && typeof v === 'string' && !ps.enum.includes(v)) issues.add(`${base}/${k}`, 'invalid_value', `"${k}" must be one of ${ps.enum.join(', ')}`);
  }
  for (const r of spec.required) if (!(r in c)) issues.add(`${base}/${r}`, 'missing_field', `${c.component} requires "${r}"`);
}

function isBindingShape(v: unknown): v is { path: unknown } {
  return isObj(v) && 'path' in v && Object.keys(v).length === 1;
}

function checkBinding(issues: Issues, v: { path: unknown }, path: string): void {
  if (typeof v.path !== 'string') issues.add(`${path}/path`, 'type_mismatch', 'A binding "path" must be a string');
  else if (!isValidPointerSyntax(v.path)) issues.add(`${path}/path`, 'invalid_value', `Invalid path syntax: "${v.path}"`);
}

function checkKind(issues: Issues, v: unknown, kind: PropKind | 'any' | 'DynamicBooleanList', path: string, catalog: A2UICatalog): void {
  const dynamic = (literal: (x: unknown) => boolean, what: string) => {
    if (literal(v)) return;
    if (isBindingShape(v)) return checkBinding(issues, v, path);
    if (isObj(v) && 'call' in v) return checkCall(issues, v, path, catalog);
    issues.add(path, 'type_mismatch', `Expected ${what}, a {"path"} binding or a function call`);
  };
  switch (kind) {
    case 'any':
      if (isBindingShape(v)) checkBinding(issues, v, path);
      else if (isObj(v) && 'call' in v) checkCall(issues, v, path, catalog);
      return;
    case 'DynamicString':
      return dynamic((x) => typeof x === 'string', 'a string');
    case 'DynamicNumber':
      return dynamic((x) => typeof x === 'number', 'a number');
    case 'DynamicBoolean':
      return dynamic((x) => typeof x === 'boolean', 'a boolean');
    case 'DynamicStringList':
      return dynamic((x) => Array.isArray(x) && x.every((s) => typeof s === 'string'), 'a list of strings');
    case 'DynamicValue':
      return dynamic((x) => typeof x === 'string' || typeof x === 'number' || typeof x === 'boolean' || Array.isArray(x), 'a value');
    case 'DynamicBooleanList':
      if (!Array.isArray(v)) return issues.add(path, 'type_mismatch', 'Expected a list');
      if (v.length < 2) issues.add(path, 'invalid_value', 'Expected at least two values');
      v.forEach((x, i) => checkKind(issues, x, 'DynamicBoolean', `${path}/${i}`, catalog));
      return;
    case 'ComponentId':
      if (typeof v !== 'string') issues.add(path, 'type_mismatch', 'Expected a component id (string)');
      return;
    case 'ChildList':
      if (Array.isArray(v)) {
        v.forEach((x, i) => typeof x !== 'string' && issues.add(`${path}/${i}`, 'type_mismatch', 'Expected a component id (string)'));
      } else if (isObj(v)) {
        for (const k of Object.keys(v)) if (k !== 'componentId' && k !== 'path') issues.add(`${path}/${k}`, 'unknown_field', `Unknown template field "${k}"`);
        if (!('componentId' in v)) issues.add(`${path}/componentId`, 'missing_field', 'A child template requires "componentId"');
        else if (typeof v.componentId !== 'string') issues.add(`${path}/componentId`, 'type_mismatch', '"componentId" must be a string');
        if (!('path' in v)) issues.add(`${path}/path`, 'missing_field', 'A child template requires "path"');
        else checkBinding(issues, v as { path: unknown }, path);
      } else issues.add(path, 'invalid_value', 'Expected a list of component ids or a {componentId, path} template');
      return;
    case 'Action':
      if (isObj(v) && Object.keys(v).length === 1 && isObj(v.event)) {
        const e = v.event;
        if (typeof e.name !== 'string') issues.add(`${path}/event/name`, e.name === undefined ? 'missing_field' : 'type_mismatch', 'An event requires a "name" string');
        for (const k of Object.keys(e)) if (k !== 'name' && k !== 'context') issues.add(`${path}/event/${k}`, 'unknown_field', `Unknown event field "${k}"`);
        if (e.context !== undefined) {
          if (!isObj(e.context)) issues.add(`${path}/event/context`, 'type_mismatch', 'An event "context" must be an object');
          else for (const [k, x] of Object.entries(e.context)) checkKind(issues, x, 'any', `${path}/event/context/${k}`, catalog);
        }
      } else if (isObj(v) && Object.keys(v).length === 1 && isObj(v.functionCall)) {
        checkCall(issues, v.functionCall, `${path}/functionCall`, catalog);
      } else issues.add(path, 'invalid_value', 'An action must be {"event": {"name", "context"}} or {"functionCall": {...}}');
      return;
    case 'Checks':
      if (!Array.isArray(v)) return issues.add(path, 'type_mismatch', '"checks" must be a list');
      v.forEach((check, i) => {
        const p = `${path}/${i}`;
        if (!isObj(check)) return issues.add(p, 'type_mismatch', 'A check must be an object');
        if (typeof check.message !== 'string') issues.add(`${p}/message`, check.message === undefined ? 'missing_field' : 'type_mismatch', 'A check requires a "message" string');
        if ('condition' in check) checkKind(issues, check.condition, 'DynamicBoolean', `${p}/condition`, catalog);
        else if (typeof check.call === 'string') checkCall(issues, { call: check.call, args: check.args ?? {} }, p, catalog);
        else issues.add(`${p}/condition`, 'missing_field', 'A check requires a "condition"');
      });
      return;
    case 'Accessibility':
      if (!isObj(v)) return issues.add(path, 'type_mismatch', '"accessibility" must be an object');
      for (const k of ['label', 'description']) if (v[k] !== undefined) checkKind(issues, v[k], 'DynamicString', `${path}/${k}`, catalog);
      return;
    case 'IconName':
      if (typeof v === 'string') {
        if (!ICON_NAMES.includes(v)) issues.add(path, 'invalid_value', `Unknown icon name "${v}"`);
      } else if (isObj(v) && 'svgPath' in v) {
        if (typeof v.svgPath !== 'string' || Object.keys(v).length !== 1) issues.add(path, 'invalid_value', 'An icon must be {"svgPath": "…"}');
      } else if (isBindingShape(v)) checkBinding(issues, v, path);
      else issues.add(path, 'type_mismatch', 'Expected an icon name, {"svgPath"} or a binding');
      return;
    case 'TabList':
      if (!Array.isArray(v) || v.length === 0) return issues.add(path, 'invalid_value', '"tabs" must be a non-empty list');
      v.forEach((t, i) => {
        const p = `${path}/${i}`;
        if (!isObj(t)) return issues.add(p, 'type_mismatch', 'A tab must be an object');
        if (!('title' in t)) issues.add(`${p}/title`, 'missing_field', 'A tab requires "title"');
        else checkKind(issues, t.title, 'DynamicString', `${p}/title`, catalog);
        if (typeof t.child !== 'string') issues.add(`${p}/child`, t.child === undefined ? 'missing_field' : 'type_mismatch', 'A tab requires a "child" id');
        for (const k of Object.keys(t)) if (k !== 'title' && k !== 'child') issues.add(`${p}/${k}`, 'unknown_field', `Unknown tab field "${k}"`);
      });
      return;
    case 'OptionList':
      if (!Array.isArray(v)) return issues.add(path, 'type_mismatch', '"options" must be a list');
      v.forEach((o, i) => {
        const p = `${path}/${i}`;
        if (!isObj(o)) return issues.add(p, 'type_mismatch', 'An option must be an object');
        if (!('label' in o)) issues.add(`${p}/label`, 'missing_field', 'An option requires "label"');
        else checkKind(issues, o.label, 'DynamicString', `${p}/label`, catalog);
        if (typeof o.value !== 'string') issues.add(`${p}/value`, o.value === undefined ? 'missing_field' : 'type_mismatch', 'An option requires a "value" string');
      });
      return;
    case 'string':
      if (typeof v !== 'string') issues.add(path, 'type_mismatch', 'Expected a string');
      return;
    case 'number':
      if (typeof v !== 'number') issues.add(path, 'type_mismatch', 'Expected a number');
      return;
    case 'boolean':
      if (typeof v !== 'boolean') issues.add(path, 'type_mismatch', 'Expected a boolean');
      return;
  }
}

function callDepth(v: unknown): number {
  if (Array.isArray(v)) return Math.max(0, ...v.map(callDepth));
  if (!isObj(v)) return 0;
  const inner = Math.max(0, ...Object.values(isObj(v.args) ? v.args : {}).map(callDepth));
  return typeof v.call === 'string' ? inner + 1 : Math.max(0, ...Object.values(v).map(callDepth));
}

function checkCall(issues: Issues, v: Record<string, any>, path: string, catalog: A2UICatalog): void {
  if (callDepth(v) > MAX_CALL_DEPTH) {
    issues.add(path, 'limit', `functionCall depth exceeds the maximum of ${MAX_CALL_DEPTH}`);
    return;
  }
  if (typeof v.call !== 'string') return issues.add(`${path}/call`, 'type_mismatch', '"call" must be a function name');
  for (const k of Object.keys(v)) if (k !== 'call' && k !== 'args' && k !== 'returnType') issues.add(`${path}/${k}`, 'unknown_field', `Unknown function-call field "${k}"`);
  const spec = catalog.functions[v.call];
  if (!spec) return issues.add(`${path}/call`, 'invalid_value', `Unknown function "${v.call}"`);
  if (v.returnType !== undefined && !['string', 'number', 'boolean', 'array', 'object', 'any', 'void'].includes(v.returnType)) {
    issues.add(`${path}/returnType`, 'invalid_value', `Invalid returnType ${JSON.stringify(v.returnType)}`);
  }
  const args = v.args === undefined ? {} : v.args;
  if (!isObj(args)) return issues.add(`${path}/args`, 'type_mismatch', '"args" must be an object');
  for (const [k, x] of Object.entries(args)) {
    const kind = spec.args[k];
    if (!kind) {
      issues.add(`${path}/args/${k}`, 'unknown_field', `${v.call}() has no argument "${k}"`);
      continue;
    }
    checkKind(issues, x, kind, `${path}/args/${k}`, catalog);
  }
  for (const r of spec.required) if (!(r in args)) issues.add(`${path}/args/${r}`, 'missing_field', `${v.call}() requires "${r}"`);
  if (spec.anyOf && !spec.anyOf.some((group) => group.every((g) => g in args))) {
    issues.add(`${path}/args`, 'missing_field', `${v.call}() requires one of ${spec.anyOf.map((g) => g.join('+')).join(' or ')}`);
  }
  if (v.call === 'formatString' && typeof args.value === 'string') {
    try {
      parseTemplate(args.value);
    } catch (e) {
      issues.add(`${path}/args/value`, 'invalid_value', e instanceof Error ? e.message : String(e));
    }
  }
}

interface SurfaceShape {
  components: Map<string, Record<string, any>>;
}

/**
 * Stateful batch validation (the conformance `validate` action): each batch
 * is checked against the state the previous accepted batches left; a batch
 * with issues changes nothing.
 */
export class A2UIValidator {
  private surfaces = new Map<string, SurfaceShape>();

  constructor(
    readonly catalog: A2UICatalog,
    readonly options: { strict?: boolean; requireVersion?: boolean } = {},
  ) {}

  validateBatch(messages: unknown[]): A2UIError[] {
    const issues: A2UIError[] = [];
    messages.forEach((m, i) => {
      for (const e of validateMessage(m, this.catalog, { requireVersion: this.options.requireVersion })) {
        issues.push(new A2UIError('ValidationError', e.message, { ...e.details, path: `/${i}${e.path === '/' ? '' : e.path}` }));
      }
    });
    if (issues.length) return issues;
    const next = new Map<string, SurfaceShape>();
    for (const [id, s] of this.surfaces) next.set(id, { components: new Map(s.components) });
    const touched = new Set<string>();
    const strict = this.options.strict === true;
    messages.forEach((m, i) => {
      const kind = messageKind(m)!;
      const body = (m as any)[kind];
      const sid = String(body.surfaceId);
      const fail = (message: string, path = `/${i}/${kind}`) => issues.push(new A2UIError('ValidationError', message, { surfaceId: sid, path, issue: 'topology' }));
      if (kind === 'createSurface') {
        if (next.has(sid)) fail(`Surface "${sid}" already exists`);
        else next.set(sid, { components: new Map() });
      } else if (kind === 'deleteSurface') {
        next.delete(sid);
      } else if (kind === 'updateComponents') {
        const s = next.get(sid);
        if (!s) return fail(`Surface "${sid}" has not been created`);
        const seen = new Set<string>();
        body.components.forEach((c: Record<string, any>, j: number) => {
          if (strict && seen.has(c.id)) fail(`Duplicate component ID "${c.id}" in one updateComponents message`, `/${i}/updateComponents/components/${j}/id`);
          seen.add(c.id);
          s.components.set(c.id, c);
        });
        touched.add(sid);
      } else if (kind === 'updateDataModel') {
        if (!next.has(sid)) fail(`Surface "${sid}" has not been created`);
      }
    });
    if (strict) for (const sid of touched) issues.push(...this.topology(sid, next.get(sid)!));
    if (issues.length === 0) this.surfaces = next;
    return issues;
  }

  /** Graph checks for one surface's component map. */
  topology(surfaceId: string, surface: SurfaceShape): A2UIError[] {
    const out: A2UIError[] = [];
    const fail = (message: string, path = '/') => out.push(new A2UIError('ValidationError', message, { surfaceId, path, issue: 'topology' }));
    const comps = surface.components;
    if (comps.size === 0) return out;
    if (!comps.has('root')) {
      fail(`Missing root component: surface "${surfaceId}" has no component with id "root"`);
      return out;
    }
    for (const [id, c] of comps) {
      for (const ref of childReferences(c, this.catalog)) {
        if (ref.id === id) fail(`Self-reference detected: component "${id}" references itself (${ref.prop})`);
        else if (!comps.has(ref.id)) fail(`Dangling reference: component "${id}" references non-existent component '${ref.id}' (${ref.prop})`);
      }
    }
    if (out.length) return out;
    const reached = new Set<string>();
    const stack: string[] = [];
    let cycle: string[] | null = null;
    let tooDeep = false;
    const visit = (id: string) => {
      if (cycle || tooDeep) return;
      if (stack.includes(id)) {
        cycle = [...stack.slice(stack.indexOf(id)), id];
        return;
      }
      if (stack.length + 1 > MAX_NESTING) {
        tooDeep = true;
        return;
      }
      reached.add(id);
      stack.push(id);
      for (const ref of childReferences(comps.get(id)!, this.catalog)) if (comps.has(ref.id)) visit(ref.id);
      stack.pop();
    };
    visit('root');
    if (cycle) fail(`Circular reference detected. Circular component reference: ${(cycle as string[]).join(' -> ')}`);
    else if (tooDeep) fail(`Global recursion limit exceeded: the component tree is deeper than ${MAX_NESTING} levels`);
    else for (const id of comps.keys()) if (!reached.has(id)) fail(`Component '${id}' is not reachable from 'root'`);
    return out;
  }
}
