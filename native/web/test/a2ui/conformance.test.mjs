// The vendored A2UI conformance suites (a2ui/conformance/json, converted from
// the YAML by a2ui/scripts/conformance-to-json.mjs) run against the renderer.
//
// Cases written for protocol v1.0 (inline `createSurface.dataModel/components`,
// `@call` / `@path`, `title`, `checked`, `selectedIndex`, `Container`) are
// translated to their v0.9.1 equivalents first (see `fromV1`). Skipped, with
// the reason printed: node_resolution (its `test_data/node/*` fixtures are not
// vendored, and it asserts web_core's reactive-node identity/emission model),
// cases with inline custom catalogs (this renderer ships the basic catalog).
import test from 'node:test';
import assert from 'node:assert/strict';
import { conformance, lib } from './harness.mjs';

const {
  DataModel,
  A2UIError,
  resolvePath,
  parseTemplate,
  A2UIProcessor,
  A2UIValidator,
  BASIC_CATALOG,
  BASIC_CATALOG_ID,
  validateMessage,
  describeAccessibility,
} = lib;

const summary = { passed: 0, skipped: [] };
const skip = (name, reason) => summary.skipped.push(`${name}: ${reason}`);

test.after(() => {
  console.log(`A2UI conformance: ${summary.passed} cases passed, ${summary.skipped.length} skipped`);
  for (const s of summary.skipped) console.log(`  skipped ${s}`);
});

function expectError(fn, expected) {
  let error = null;
  try {
    fn();
  } catch (e) {
    error = e;
  }
  assert.ok(error, `expected ${expected.category} error`);
  assert.ok(error instanceof A2UIError, `not an A2UIError: ${error}`);
  if (expected.category) assert.equal(error.category, expected.category);
  if (expected.message) assert.ok(error.message.includes(expected.message), `"${error.message}" should contain "${expected.message}"`);
}

// ---------------------------------------------------------------------------
// v1.0 → v0.9.1 translation
// ---------------------------------------------------------------------------

function renameKeys(v) {
  if (Array.isArray(v)) return v.map(renameKeys);
  if (v && typeof v === 'object') {
    const out = {};
    for (const [k, x] of Object.entries(v)) out[k === '@call' ? 'call' : k === '@path' ? 'path' : k] = renameKeys(x);
    return out;
  }
  return v;
}

function fromV1(messages) {
  const out = [];
  for (const raw of messages) {
    const m = renameKeys(raw);
    if (m.createSurface) {
      const { dataModel, components, ...cs } = m.createSurface;
      if (cs.catalogId === 'basic') cs.catalogId = BASIC_CATALOG_ID;
      out.push({ version: 'v0.9.1', createSurface: cs });
      if (dataModel !== undefined) out.push({ version: 'v0.9.1', updateDataModel: { surfaceId: cs.surfaceId, path: '/', value: dataModel } });
      if (components) out.push({ version: 'v0.9.1', updateComponents: { surfaceId: cs.surfaceId, components } });
    } else {
      const { version, ...rest } = m;
      out.push({ version: 'v0.9.1', ...rest });
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// data_model
// ---------------------------------------------------------------------------

test('conformance: data_model', () => {
  for (const c of conformance('data_model')) {
    const model = new DataModel(c.initial ?? {});
    const notified = [];
    for (const path of c.watch ?? []) model.watch(path, () => notified.push(path));
    for (const step of c.steps) {
      notified.length = 0;
      const where = `${c.name} ${JSON.stringify(step)}`;
      if (step.expect_error) {
        expectError(() => (step.op === 'get' ? model.get(step.path) : step.op === 'delete' ? model.delete(step.path) : model.set(step.path, step.value)), step.expect_error);
        continue;
      }
      switch (step.op) {
        case 'get': {
          const v = model.get(step.path);
          if ('expect' in step) assert.deepEqual(v, step.expect, where);
          // Absent: no value, or a null padding slot (languages without `undefined` cannot tell them apart).
          if (step.expect_absent) assert.ok(v === undefined || v === null, where);
          if (step.expect_type === 'list') assert.ok(Array.isArray(v), where);
          if (step.expect_type === 'object') assert.ok(v && typeof v === 'object' && !Array.isArray(v), where);
          break;
        }
        case 'set':
          model.set(step.path, step.value);
          break;
        case 'delete':
          model.delete(step.path);
          break;
        case 'dispose':
          model.dispose();
          break;
        default:
          assert.fail(`unknown op ${step.op}`);
      }
      if (step.expect_notified) assert.deepEqual([...notified].sort(), [...step.expect_notified].sort(), where);
      for (const [p, v] of Object.entries(step.expect_values ?? {})) assert.deepEqual(model.get(p), v, where);
    }
    summary.passed++;
  }
});

// ---------------------------------------------------------------------------
// data_context
// ---------------------------------------------------------------------------

test('conformance: data_context', () => {
  for (const c of conformance('data_context')) {
    assert.equal(c.action, 'resolve_path');
    assert.equal(resolvePath(c.args.path, c.args.contextPath), c.expect, c.name);
    summary.passed++;
  }
});

// ---------------------------------------------------------------------------
// expressions
// ---------------------------------------------------------------------------

function rootText(messages) {
  const p = new A2UIProcessor({ validation: 'strict' });
  const errors = p.processAll(messages);
  assert.deepEqual(errors.map((e) => e.message), []);
  const s = p.surfaces[0];
  const root = s.components.get('root');
  return { processor: p, surface: s, text: s.context().string(root.text) };
}

test('conformance: expressions', () => {
  for (const c of conformance('expressions')) {
    if (c.action === 'parse_expression_template') {
      if (c.expect_error) expectError(() => parseTemplate(c.input), c.expect_error);
      else assert.deepEqual(parseTemplate(c.input), c.expect, c.name);
    } else if (c.action === 'validate') {
      const messages = fromV1(c.steps.flatMap((s) => s.payload));
      const expected = c.steps.find((s) => s.expectError)?.expectError;
      if (expected) {
        const issues = messages.flatMap((m) => validateMessage(m, BASIC_CATALOG));
        assert.ok(issues.some((e) => e.category === expected.category && e.message.includes(expected.message)), `${c.name}: ${issues.map((e) => e.message)}`);
      } else {
        assert.equal(rootText(messages).text, c.expect.surfaces.main.components.root.text, c.name);
      }
    } else assert.fail(`unexpected action ${c.action}`);
    summary.passed++;
  }
});

// ---------------------------------------------------------------------------
// data_deletion
// ---------------------------------------------------------------------------

test('conformance: data_deletion', () => {
  for (const c of conformance('data_deletion')) {
    const p = new A2UIProcessor({ validation: 'strict' });
    const errors = p.processAll(fromV1(c.steps.flatMap((s) => s.payload)));
    assert.deepEqual(errors.map((e) => e.message), [], c.name);
    for (const [sid, exp] of Object.entries(c.expect.surfaces)) assert.deepEqual(p.dataModel(sid), exp.dataModel, c.name);
    summary.passed++;
  }
});

// ---------------------------------------------------------------------------
// actions
// ---------------------------------------------------------------------------

test('conformance: actions', () => {
  for (const c of conformance('actions')) {
    const p = new A2UIProcessor();
    const sid = c.surfaceId ?? 'main';
    p.process({ version: 'v0.9.1', createSurface: { surfaceId: sid, catalogId: BASIC_CATALOG_ID } });
    if (c.dataModel) p.process({ version: 'v0.9.1', updateDataModel: { surfaceId: sid, path: '/', value: c.dataModel } });
    const emitted = [];
    p.on((e) => e.type === 'action' && emitted.push(e.action));
    const action = p.dispatchAction(sid, 'btn', c.actionPayload, c.scope ?? '/');
    assert.ok(action, c.name);
    assert.equal(emitted.length, 1);
    assert.equal(action.surfaceId, sid);
    assert.equal(action.sourceComponentId, 'btn');
    assert.ok(!Number.isNaN(Date.parse(action.timestamp)));
    const exp = c.expectDispatched;
    assert.equal(action.name, exp.name, c.name);
    assert.deepEqual(action.context, exp.context ?? {}, c.name);
    if (exp.userMessage) assert.equal(action.userMessage, exp.userMessage);
    summary.passed++;
  }
});

// ---------------------------------------------------------------------------
// accessibility
// ---------------------------------------------------------------------------

/** The v1.0 `surface` shorthand → v0.9.1 components. */
function a11yComponents(surface) {
  const comps = [];
  const conv = (id, c) => {
    const out = { id, ...renameKeys(c) };
    delete out.components;
    if (out.component === 'Container') {
      out.component = 'Column';
      out.children = out.child ? [out.child] : [];
      delete out.child;
    }
    if (out.component === 'Button' && typeof out.title === 'string') {
      comps.push({ id: `${id}__label`, component: 'Text', text: out.title });
      out.child = `${id}__label`;
      out.action = { event: { name: 'press' } };
      delete out.title;
    }
    if (out.component === 'CheckBox' && 'checked' in out) {
      out.value = out.checked;
      delete out.checked;
    }
    if (out.component === 'ChoicePicker' && 'selectedIndex' in out) {
      out.value = [out.options[out.selectedIndex].value];
      delete out.selectedIndex;
    }
    comps.push(out);
  };
  conv(surface.id, surface);
  for (const [id, c] of Object.entries(surface.components ?? {})) conv(id, c);
  return comps;
}

test('conformance: accessibility', () => {
  for (const c of conformance('accessibility')) {
    const p = new A2UIProcessor({ validation: 'off' });
    p.process({ version: 'v0.9.1', createSurface: { surfaceId: 's', catalogId: BASIC_CATALOG_ID } });
    p.process({ version: 'v0.9.1', updateComponents: { surfaceId: 's', components: a11yComponents(c.surface) } });
    const s = p.surface('s');
    for (const [id, exp] of Object.entries(c.assertions.accessibilityTree)) {
      const node = describeAccessibility(s, s.components.get(id));
      for (const [k, v] of Object.entries(exp)) {
        if (v && typeof v === 'object' && 'path' in v) assert.equal(node.bindings?.[k], v.path, `${c.name} ${id}.${k}`);
        else assert.deepEqual(node[k], v, `${c.name} ${id}.${k}`);
      }
    }
    summary.passed++;
  }
});

// ---------------------------------------------------------------------------
// validator_v0_9 and composition_constraints
// ---------------------------------------------------------------------------

function dotted(path) {
  // `/0/createSurface/surfaceId` → `messages.0.createSurface.surfaceId`
  return 'messages' + path.split('/').filter(Boolean).map((s) => `.${s}`).join('');
}

function checkExpected(issues, expected, where) {
  assert.ok(issues.length > 0, `${where}: expected an error`);
  if (typeof expected === 'string') {
    assert.ok(issues.some((e) => e.message.includes(expected)), `${where}: ${issues.map((e) => e.message).join(' | ')} should mention "${expected}"`);
    return;
  }
  if (expected.category) assert.ok(issues.every((e) => e.category === expected.category), where);
  if (expected.message) assert.ok(issues.some((e) => e.message.includes(expected.message)), `${where}: ${issues.map((e) => e.message).join(' | ')}`);
  for (const d of expected.details ?? []) {
    assert.ok(
      issues.some((e) => dotted(e.path) === d.path && e.details.issue === d.code),
      `${where}: no issue at ${d.path} (${d.code}); got ${issues.map((e) => `${dotted(e.path)} ${e.details.issue}`).join(', ')}`,
    );
  }
}

test('conformance: validator_v0_9', () => {
  for (const c of conformance('validator_v0_9')) {
    if (c.catalog) {
      skip(c.name, 'inline custom catalog (only the basic catalog is built in)');
      continue;
    }
    const v = new A2UIValidator(BASIC_CATALOG, { strict: c.strictMode === true, requireVersion: true });
    c.steps.forEach((step, i) => {
      const issues = v.validateBatch(step.messages);
      if (step.expectError) checkExpected(issues, step.expectError, `${c.name} step ${i}`);
      else assert.deepEqual(issues.map((e) => e.message), [], `${c.name} step ${i}`);
    });
    if (c.expectError) assert.fail(`${c.name}: case-level expectError not handled`);
    summary.passed++;
  }
});

test('conformance: composition_constraints', () => {
  for (const c of conformance('composition_constraints')) {
    if (c.catalog?.catalogSchema) {
      skip(c.name, 'v1.0 allowedParents/allowedChildren on an inline custom catalog');
      continue;
    }
    const p = new A2UIProcessor({ validation: 'strict' });
    const errors = p.processAll(fromV1(c.steps.flatMap((s) => s.payload)));
    assert.deepEqual(errors.map((e) => e.message), [], c.name);
    const v = new A2UIValidator(BASIC_CATALOG, { strict: true });
    assert.deepEqual(v.validateBatch(fromV1(c.steps.flatMap((s) => s.payload))).map((e) => e.message), [], c.name);
    for (const [sid, exp] of Object.entries(c.expect.surfaces)) {
      for (const [id, comp] of Object.entries(exp.components)) assert.deepEqual({ ...p.surface(sid).components.get(id), id: undefined }, { ...comp, id: undefined });
    }
    summary.passed++;
  }
});

test('conformance: node_resolution', () => {
  for (const c of conformance('node_resolution')) skip(c.name, 'fixtures (test_data/node/*.yaml) are not vendored; asserts web_core reactive-node identity');
});
