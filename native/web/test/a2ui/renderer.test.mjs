// The basic catalog examples through processor + lowering + reconcile +
// layout, the catalog table against catalog.json, functions, two-way binding,
// Tabs / Modal state, and the transport's chunk-split NDJSON decoding.
import test from 'node:test';
import assert from 'node:assert/strict';
import { a2uiDir, examples, lib, platform, readJson, renderOnSurface, walk } from './harness.mjs';

const {
  A2UIProcessor,
  A2UIUiState,
  A2UIConversation,
  BASIC_CATALOG,
  BASIC_FUNCTION_SPECS,
  BASIC_COMPONENTS,
  COMMON_PROPS,
  ICON_NAMES,
  lowerSurface,
  materialIconName,
  MATERIAL_ICON_CODEPOINTS,
  NdjsonDecoder,
  formatDatePattern,
  A2UIValidator,
} = lib;

function hooks(processor, log = []) {
  return {
    write: (sid, path, value) => {
      log.push(['write', path, value]);
      processor.setData(sid, path, value);
    },
    action: (sid, id, action, scope) => log.push(['action', processor.dispatchAction(sid, id, action, scope)]),
    invalidate: () => log.push(['invalidate']),
    error: (e) => log.push(['error', e.message]),
  };
}

test('the basic catalog table matches catalog.json', () => {
  const json = readJson(a2uiDir, 'spec', 'catalogs', 'basic', 'catalog.json');
  assert.equal(BASIC_CATALOG.id, json.catalogId);
  assert.deepEqual(Object.keys(BASIC_COMPONENTS).sort(), Object.keys(json.components).sort());
  for (const [name, schema] of Object.entries(json.components)) {
    const own = schema.allOf.find((a) => a.properties?.component);
    const props = Object.keys(own.properties).filter((p) => p !== 'component');
    const checkable = schema.allOf.some((a) => a.$ref?.endsWith('Checkable'));
    const ours = Object.keys(BASIC_COMPONENTS[name].props).filter((p) => p !== 'checks');
    assert.deepEqual(ours.sort(), props.sort(), name);
    assert.equal('checks' in BASIC_COMPONENTS[name].props, checkable, `${name} checks`);
    assert.deepEqual([...BASIC_COMPONENTS[name].required].sort(), own.required.filter((r) => r !== 'component').sort(), `${name} required`);
    for (const p of props) {
      if (own.properties[p].enum) assert.deepEqual([...BASIC_COMPONENTS[name].props[p].enum].sort(), [...own.properties[p].enum].sort(), `${name}.${p}`);
    }
  }
  assert.deepEqual(Object.keys(COMMON_PROPS).sort(), ['accessibility', 'component', 'id', 'weight']);
  assert.deepEqual(Object.keys(BASIC_FUNCTION_SPECS).sort(), Object.keys(json.functions).sort());
  for (const [name, schema] of Object.entries(json.functions)) {
    assert.deepEqual(Object.keys(BASIC_FUNCTION_SPECS[name].args).sort(), Object.keys(schema.properties.args.properties).sort(), name);
    assert.equal(BASIC_FUNCTION_SPECS[name].returnType, schema.properties.returnType.const, name);
  }
  assert.deepEqual([...ICON_NAMES].sort(), [...json.components.Icon.allOf[2].properties.name.oneOf[0].enum].sort());
});

test('every catalog icon maps to a Material icon', () => {
  for (const name of ICON_NAMES) assert.ok(MATERIAL_ICON_CODEPOINTS[materialIconName(name)] != null, `${name} → ${materialIconName(name)}`);
});

const all = examples();

test('there are 43 basic catalog examples', () => {
  assert.equal(all.length, 43);
});

for (const example of all) {
  test(`example ${example.file}: processes, lowers, lays out`, () => {
    const processor = new A2UIProcessor({ validation: 'strict' });
    const errors = processor.processAll(example.messages);
    assert.deepEqual(errors.map((e) => `${e.path}: ${e.message}`), [], 'processing errors');
    // The whole batch also passes strict topology validation.
    const v = new A2UIValidator(BASIC_CATALOG, { strict: true });
    // (Incremental examples replace placeholders, leaving them unreachable — allowed.)
    const topology = v.validateBatch(example.messages).map((e) => e.message);
    const orphans = new Set(topology.map((m) => /^Component '(.+)' is not reachable/.exec(m)?.[1]).filter(Boolean));
    assert.deepEqual(topology.filter((m) => !m.includes('is not reachable')), [], 'topology');
    assert.ok(processor.surfaces.length > 0);
    for (const surface of processor.surfaces) {
      assert.ok(surface.isReady, `${surface.id} has a root`);
      const log = [];
      const result = lowerSurface(surface, { hooks: hooks(processor, log), state: new A2UIUiState(), expandAll: true });
      assert.deepEqual(result.placeholders, [], 'placeholders');
      assert.deepEqual(log.filter((l) => l[0] === 'error'), [], 'evaluation errors');
      // Every component is lowered — except a template whose list is empty.
      const lowered = new Set(result.lowered.map((m) => m.split('@')[0]));
      for (const id of surface.components.keys()) {
        if (lowered.has(id) || orphans.has(id)) continue;
        const asTemplate = [...surface.components.values()].some((c) => c.children && !Array.isArray(c.children) && c.children.componentId === id);
        assert.ok(asTemplate, `${id} was not lowered`);
      }
      const { surface: s, ops } = renderOnSurface(result.node);
      assert.ok(ops.length > 0, 'committed view ops');
      assert.ok(s.owner.root.size.height > 0, 'laid out with height');
      const types = new Set();
      walk(result.node, (n) => types.add(n.type));
      for (const t of types) assert.ok(s.engine.services.registry.has(t), `lowered to unregistered widget ${t}`);
      assert.ok(!platform.logs.some((l) => l.includes('render error') || l.includes('Unknown widget')), platform.logs.join('\n'));
      s.dispose();
    }
  });
}

test('two-way binding, checks and actions on a form', () => {
  const p = new A2UIProcessor();
  p.processAll([
    { version: 'v0.9.1', createSurface: { surfaceId: 'f', catalogId: BASIC_CATALOG.id, theme: { primaryColor: '#00BFFF' } } },
    {
      version: 'v0.9.1',
      updateComponents: {
        surfaceId: 'f',
        components: [
          { id: 'root', component: 'Column', children: ['name', 'echo', 'go'] },
          { id: 'name', component: 'TextField', label: 'Name', value: { path: '/form/name' }, checks: [{ condition: { call: 'required', args: { value: { path: '/form/name' } } }, message: 'Required' }] },
          { id: 'echo', component: 'Text', text: { call: 'formatString', args: { value: 'Hi ${/form/name}' }, returnType: 'string' } },
          { id: 'go_label', component: 'Text', text: 'Go' },
          { id: 'go', component: 'Button', child: 'go_label', variant: 'primary', action: { event: { name: 'submit', context: { name: { path: '/form/name' } } } }, checks: [{ condition: { call: 'required', args: { value: { path: '/form/name' } } }, message: 'Required' }] },
        ],
      },
    },
  ]);
  const log = [];
  const state = new A2UIUiState();
  const lower = () => lowerSurface(p.surface('f'), { hooks: hooks(p, log), state }).node;
  const find = (node, pred) => {
    let hit = null;
    walk(node, (n) => {
      if (!hit && pred(n)) hit = n;
    });
    return hit;
  };
  let tree = lower();
  const button = find(tree, (n) => n.type === 'Button');
  assert.equal(button.props.disabled, true, 'disabled while the check fails');
  assert.equal(button.props.style.backgroundColor, '#00BFFF', 'theme primary color');
  const input = find(tree, (n) => n.type === 'TextField');
  input.events.input({ value: 'Ada' });
  assert.deepEqual(p.dataModel('f'), { form: { name: 'Ada' } });
  tree = lower();
  assert.equal(find(tree, (n) => n.type === 'TextField').props.value, 'Ada');
  assert.equal(find(tree, (n) => n.type === 'Text' && n.props.text.startsWith('Hi')).props.text, 'Hi Ada');
  const enabled = find(tree, (n) => n.type === 'Button');
  assert.equal(enabled.props.disabled, false);
  enabled.events.click({});
  const action = log.find((l) => l[0] === 'action')[1];
  assert.equal(action.name, 'submit');
  assert.equal(action.surfaceId, 'f');
  assert.equal(action.sourceComponentId, 'go');
  assert.deepEqual(action.context, { name: 'Ada' });
  // A server update re-renders the bound field.
  p.process({ version: 'v0.9.1', updateDataModel: { surfaceId: 'f', path: '/form/name', value: 'Grace' } });
  assert.equal(find(lower(), (n) => n.type === 'TextField').props.value, 'Grace');
});

test('Tabs and Modal keep UI state', () => {
  const p = new A2UIProcessor();
  p.processAll(readJson(a2uiDir, 'spec', 'catalogs', 'basic', 'examples', '36_modal.json').messages);
  const s = p.surfaces[0];
  const state = new A2UIUiState();
  const log = [];
  const tree = lowerSurface(s, { hooks: hooks(p, log), state });
  assert.equal(tree.node.type, 'Column', 'no overlay while closed');
  let trigger = null;
  walk(tree.node, (n) => {
    if (!trigger && n.type === 'Button') trigger = n;
  });
  trigger.events.click({});
  const open = lowerSurface(s, { hooks: hooks(p, log), state });
  assert.equal(open.node.type, 'ConstrainedBox', 'the dialog overlays the surface');
  let barrier = null;
  walk(open.node, (n) => {
    if (n.key?.endsWith('/barrier')) barrier = n;
  });
  barrier.events.click({});
  assert.equal(lowerSurface(s, { hooks: hooks(p, log), state }).node.type, 'Column', 'closed by the barrier');
});

test('functions: formatting and validation', () => {
  const p = new A2UIProcessor({ locale: 'en-US' });
  p.process({ version: 'v0.9.1', createSurface: { surfaceId: 's', catalogId: BASIC_CATALOG.id } });
  const ctx = p.surface('s').context();
  const call = (name, args) => ctx.call(name, args);
  assert.equal(call('formatNumber', { value: 1234.5, decimals: 2 }), '1,234.50');
  assert.equal(call('formatNumber', { value: 1234.5, decimals: 0, grouping: false }), '1235');
  assert.equal(call('formatCurrency', { value: 49.99, currency: 'EUR' }), '€49.99');
  assert.equal(call('formatDate', { value: '2026-02-02T15:17:00Z', format: "EEEE, MMM d 'at' h:mm a" }), 'Monday, Feb 2 at 3:17 PM');
  assert.equal(formatDatePattern(new Date(2026, 0, 16), 'yyyy-MM-dd EEE MMMM yy'), '2026-01-16 Fri January 26');
  assert.equal(call('pluralize', { value: 1, one: 'item', other: 'items' }), 'item');
  assert.equal(call('pluralize', { value: 3, one: 'item', other: 'items' }), 'items');
  assert.equal(call('pluralize', { value: 0, zero: 'none', other: 'items' }), 'none');
  assert.equal(call('required', { value: [] }), false);
  assert.equal(call('email', { value: 'a@b.co' }), true);
  assert.equal(call('length', { value: 'abc', min: 4 }), false);
  assert.equal(call('numeric', { value: '5', min: 1, max: 10 }), true);
  assert.equal(call('regex', { value: '12345', pattern: '^[0-9]{5}$' }), true);
  assert.equal(call('and', { values: [true, { call: 'not', args: { value: false } }] }), true);
  assert.equal(call('or', { values: [false, false] }), false);
  assert.throws(() => call('openUrl', { url: 'javascript:alert(1)' }), /not allowed/);
  assert.throws(() => call('nope', {}), /Unknown function/);
});

test('NDJSON decoding survives arbitrary chunk splits', () => {
  const lines = [
    { type: 'conversation', conversationId: 'c1' },
    { version: 'v0.9.1', createSurface: { surfaceId: 's', catalogId: BASIC_CATALOG.id } },
    { type: 'text', text: 'héllo — ünïcode ✓' },
    { type: 'done', stopReason: 'end_turn' },
  ];
  const text = lines.map((l) => JSON.stringify(l)).join('\n') + '\n';
  for (const size of [1, 2, 3, 7, 13, text.length]) {
    const d = new NdjsonDecoder();
    const out = [];
    for (let i = 0; i < text.length; i += size) out.push(...d.push(text.substring(i, i + size)));
    out.push(...d.end());
    assert.deepEqual(out, lines, `chunk size ${size}`);
  }
  // A final line without a newline and a CRLF line.
  const d = new NdjsonDecoder();
  assert.deepEqual(d.push('{"a":1}\r\n{"b"'), [{ a: 1 }]);
  assert.deepEqual(d.push(':2}'), []);
  assert.deepEqual(d.end(), [{ b: 2 }]);
});

test('a conversation streams a turn from a fake agent', async () => {
  const body = [
    '{"type":"conversation","conversationId":"conv-1"}\n{"version":"v0.9.1","createSurface":{"surfaceId":"s","catalogId":"' + BASIC_CATALOG.id + '","sendDataModel":true}}\n',
    '{"version":"v0.9.1","updateComponents":{"surfaceId":"s","components":[{"id":"root","component":"Text","text":{"path":"/greeting"}}]}}\n{"version":"v0.9',
    '.1","updateDataModel":{"surfaceId":"s","path":"/greeting","value":"Hello"}}\n{"type":"text","text":"Here you go"}\n{"type":"done","stopReason":"end_turn"}\n',
  ];
  platform.requests.length = 0;
  platform.streamScript = () => ({ chunks: body });
  const conv = new A2UIConversation({ endpoint: { baseUrl: 'http://agent.test/', appId: 'shop', agent: 'assistant' } });
  const events = [];
  conv.on((e) => events.push(e.type));
  const turn = conv.send('hi');
  assert.equal(await turn.conversationId, 'conv-1');
  const done = await turn.done;
  assert.deepEqual(done, { conversationId: 'conv-1', stopReason: 'end_turn' });
  assert.equal(platform.requests[0].url, 'http://agent.test/apps/shop/agent/assistant');
  const first = JSON.parse(platform.requests[0].body);
  assert.deepEqual(first, { message: 'hi', capabilities: { supportedCatalogIds: [BASIC_CATALOG.id] } });
  assert.equal(conv.dataModel('s').greeting, 'Hello');
  assert.deepEqual(conv.transcript, [
    { role: 'user', text: 'hi' },
    { role: 'agent', text: 'Here you go' },
  ]);
  assert.ok(events.includes('done') && events.includes('text') && events.includes('conversation'));
  // The next turn carries the conversation id and the sendDataModel surface.
  platform.streamScript = () => ({ chunks: ['{"type":"done","stopReason":"end_turn"}'] });
  await conv.sendAction({ name: 'x', surfaceId: 's', sourceComponentId: 'root', timestamp: new Date().toISOString(), context: {} }).done;
  const second = JSON.parse(platform.requests[1].body);
  assert.equal(second.conversationId, 'conv-1');
  assert.equal(second.action.name, 'x');
  assert.deepEqual(second.dataModel, { version: 'v0.9.1', surfaces: { s: { greeting: 'Hello' } } });
  // A transport failure ends the turn with an error.
  platform.streamScript = () => ({ chunks: [], error: 'HTTP status 500' });
  const failed = await conv.send('again').done;
  assert.equal(failed.stopReason, 'error');
});

test('A2UISurface widget: static messages, events and the agent host APIs', async () => {
  const messages = readJson(a2uiDir, 'spec', 'catalogs', 'basic', 'examples', '00_interactive-button.json').messages;
  const got = [];
  const { surface } = renderOnSurface({ type: 'A2UISurface', key: 'w', props: { messages }, events: { a2uiAction: (e) => got.push(e.value) } });
  const reg = lib.a2uiRegistry(surface.engine.services);
  const conv = reg.get('static:w');
  assert.ok(conv && conv.processor.surfaces.length === 1);
  const s = conv.processor.surfaces[0];
  const button = [...s.components.values()].find((c) => c.component === 'Button');
  conv.processor.dispatchAction(s.id, button.id, button.action);
  assert.equal(got.length, 1);
  assert.equal(got[0].sourceComponentId, button.id);
  // Host APIs share the registry.
  const handler = new lib.HostHandler(surface.engine.services);
  const model = JSON.parse(await handler.handleHostCall('a2ui.dataModel', JSON.stringify({ conversation: 'static:w', surfaceId: s.id })));
  assert.ok(model.type === 'object' || model.type === 'null');
  reg.defaults = { baseUrl: 'http://agent.test', appId: 'shop' };
  platform.streamScript = () => ({ chunks: ['{"type":"conversation","conversationId":"c9"}\n{"type":"done","stopReason":"end_turn"}\n'] });
  const sent = JSON.parse(await handler.handleHostCall('agent.send', JSON.stringify({ agent: 'assistant', message: 'hello' })));
  assert.deepEqual(sent.data.value, { conversationId: 'c9', conversation: 'agent:assistant' });
  assert.equal(platform.requests.at(-1).url, 'http://agent.test/apps/shop/agent/assistant');
  surface.dispose();
});

test('reconciler: removing a keyed middle child keeps the bottom run intact', () => {
  // Regression: the bottom run was reconciled against the old middle's objects
  // (the A2UI chat row collapsed to 0x0 when the busy indicator went away).
  const surface = new lib.ElpianSurface('reconcile');
  const view = (busy) => ({
    type: 'Column',
    children: [
      { type: 'Text', key: 'a', props: { text: 'a' } },
      ...(busy ? [{ type: 'LinearProgressIndicator', key: 'busy' }] : []),
      { type: 'Text', key: 'b', props: { text: 'b' } },
      { type: 'Row', key: 'chat', children: [{ type: 'Expanded', children: [{ type: 'TextField', key: 'in', props: { hint: 'x' } }] }] },
    ],
  });
  for (const busy of [false, true, false]) {
    surface.setContent(view(busy));
    surface.renderNow();
    surface.owner.flush(0);
  }
  let input = null;
  surface.owner.root.visit((ro) => {
    if (ro.type === 'control' && ro.props.kind === 'textInput') input = ro;
  });
  assert.ok(input.size.width > 0 && input.size.height > 0, JSON.stringify(input.size));
  surface.dispose();
});
