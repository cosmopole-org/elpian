// Compile guest source inside the wasm module and run it, as a Node.js host
// (a server-side backend) does: Dart and JavaScript to bytecode, a function
// called with typed input, a host call made mid-function and resumed.
//
// Built with `--features compiler`; the browser artifact has no front-ends.

const assert = require('node:assert');

const pkg = process.argv[2];
if (!pkg) {
  console.error('usage: node scripts/wasm-compiler-smoke.cjs <wasm-pkg-dir>');
  process.exit(2);
}
const vm = require(`${pkg}/elpian_wasm.js`);
vm.elpian_wasm_init();

const sources = {
  dart: `Map greet(Map args) {
  var reply = askHost('host.echo', args['name']);
  return {'text': 'hello ' + args['name'], 'host': reply};
}`,
  js: `function greet(args) {
  var reply = askHost('host.echo', args.name);
  return { text: 'hello ' + args.name, host: reply };
}`,
};

const input = JSON.stringify({
  type: 'object',
  data: { value: { name: { type: 'string', data: { value: 'ada' } } } },
});

for (const [language, source] of Object.entries(sources)) {
  const bytecode = language === 'dart'
    ? vm.elpian_wasm_compile_dart(source)
    : vm.elpian_wasm_compile_js(source);
  assert.ok(bytecode.length > 0, `${language} compiles`);
  assert.strictEqual(vm.elpian_wasm_create_vm_from_bytecode(language, bytecode), true);
  vm.elpian_wasm_execute(language);
  let turn = JSON.parse(vm.elpian_wasm_execute_func_with_input(language, 'greet', input, 1));
  assert.strictEqual(turn.hasHostCall, true, `${language}: the guest asks the host`);
  assert.strictEqual(JSON.parse(turn.hostCallData).apiName, 'host.echo');
  turn = JSON.parse(vm.elpian_wasm_continue_execution(
    language, JSON.stringify({ type: 'string', data: { value: 'pong' } })));
  assert.strictEqual(turn.hasHostCall, false);
  assert.ok(turn.resultValue.includes('hello ada') && turn.resultValue.includes('pong'), turn.resultValue);
  console.log(`  ok: ${language} compiled, ran and resumed after a host call`);
}
