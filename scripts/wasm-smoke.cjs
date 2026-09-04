// Drive the real WASM VM in node.
//
// This exists because of a specific failure: `std::time::Instant::now()`
// *compiles* on wasm32-unknown-unknown and *traps* at run time. A clock read
// added to the per-turn path therefore killed the VM on its first turn in the
// browser — the module loaded, the VM was created, and `execute` trapped before
// anything rendered. The symptom was a blank white page, and every check the
// repository had at the time passed: it built, `cargo test` was green on the
// host, and the web export contained all the right files.
//
// Nothing short of *running* the wasm catches that. So this does.

const assert = require('node:assert');

const pkg = process.argv[2];
if (!pkg) {
  console.error('usage: node scripts/wasm-smoke.cjs <wasm-pkg-dir>');
  process.exit(2);
}
const vm = require(`${pkg}/elpian_wasm.js`);

function step(name, run) {
  try {
    run();
    console.log(`  ok: ${name}`);
  } catch (error) {
    console.error(`  FAIL: ${name}\n    ${String(error).split('\n')[0]}`);
    process.exitCode = 1;
    throw error;
  }
}

const renderAst = JSON.stringify({
  type: 'program',
  body: [
    {
      type: 'host_call',
      data: {
        name: 'render',
        args: [{ type: 'string', data: { value: '{"type":"text","text":"hi"}' } }],
      },
    },
  ],
});

// A function that makes a host call and *then* returns a value — the shape that
// exercises the resume path rather than only the first turn.
const resumeAst = JSON.stringify({
  type: 'program',
  body: [
    {
      type: 'functionDefinition',
      data: {
        name: 'ask',
        params: [],
        body: [
          { type: 'host_call', data: { name: 'log', args: [{ type: 'string', data: { value: 'x' } }] } },
          { type: 'returnOperation', data: { value: { type: 'string', data: { value: 'after-the-host-call' } } } },
        ],
      },
    },
  ],
});

try {
  step('init', () => vm.elpian_wasm_init());

  step('create a VM from AST', () => {
    assert.strictEqual(vm.elpian_wasm_create_vm_from_ast('smoke', renderAst), true);
  });

  // The turn that used to trap. Everything below depends on it.
  step('execute a turn', () => {
    const result = JSON.parse(vm.elpian_wasm_execute('smoke'));
    assert.strictEqual(result.hasHostCall, true, 'the guest should have asked to render');
    assert.ok(result.hostCallData.includes('render'), 'and the call should be `render`');
  });

  step('resume after a host call', () => {
    assert.strictEqual(vm.elpian_wasm_create_vm_from_ast('resume', resumeAst), true);
    vm.elpian_wasm_execute('resume');
    const first = JSON.parse(vm.elpian_wasm_execute_func('resume', 'ask', 1));
    assert.strictEqual(first.hasHostCall, true, 'the function calls the host');
    const done = JSON.parse(vm.elpian_wasm_continue_execution('resume', 'null'));
    assert.strictEqual(done.hasHostCall, false, 'and then finishes');
    // The value a resumed turn returns. This used to be a fixed "done", which
    // silently discarded every such function's result.
    assert.ok(
      done.resultValue.includes('after-the-host-call'),
      `a resumed turn must report what the function returned, got ${done.resultValue}`,
    );
  });

  step('governance calls work', () => {
    vm.elpian_wasm_set_capability('smoke', 'network', false);
    const allowed = JSON.parse(vm.elpian_wasm_capability_allows('smoke', 'net.fetch'));
    assert.strictEqual(allowed.allowed ?? allowed, false, 'the gate closed');
  });

  step('many turns in sequence', () => {
    // The per-turn bookkeeping runs on every one of these, so a fault in it
    // shows up here rather than only on the first call.
    for (let i = 0; i < 50; i += 1) {
      const result = JSON.parse(vm.elpian_wasm_execute('smoke'));
      assert.ok(result !== null);
    }
  });

  step('destroy', () => {
    assert.strictEqual(vm.elpian_wasm_destroy_vm('smoke'), true);
    assert.strictEqual(vm.elpian_wasm_vm_exists('smoke'), false);
  });

  console.log('\nwasm smoke: all checks passed');
} catch {
  console.error('\nwasm smoke: FAILED');
  process.exit(1);
}
