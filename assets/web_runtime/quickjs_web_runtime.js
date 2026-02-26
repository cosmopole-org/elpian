const quickJsMachines = new Map();
let quickJsModulePromise = null;
let quickJsInstancePromise = null;

async function getQuickJsModule() {
  if (!quickJsModulePromise) {
    quickJsModulePromise = (async () => {
      const candidates = [
        // Browser-ready ESM entry.
        'https://esm.sh/quickjs-emscripten@0.31.0?bundle&target=es2022&browser',
      ];

      let lastError = null;
      for (const url of candidates) {
        try {
          const mod = await import(url);
          if (mod && typeof mod.newQuickJSWASMModule === 'function') {
            return mod;
          }
          throw new Error(`Module loaded but newQuickJSWASMModule is missing: ${url}`);
        } catch (error) {
          lastError = error;
          console.warn(`QuickJS module import failed from ${url}`, error);
        }
      }

      throw lastError ?? new Error('Unable to load quickjs-emscripten module from configured CDNs');
    })();
  }
  return quickJsModulePromise;
}

async function getWasmBinary() {
  const wasmCandidates = [
    'https://cdn.jsdelivr.net/npm/@jitl/quickjs-wasmfile-release-sync@0.31.0/dist/emscripten-module.wasm',
    'https://unpkg.com/@jitl/quickjs-wasmfile-release-sync@0.31.0/dist/emscripten-module.wasm',
  ];

  let lastError = null;
  for (const url of wasmCandidates) {
    try {
      const response = await fetch(url, { mode: 'cors' });
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }
      return await response.arrayBuffer();
    } catch (error) {
      lastError = error;
      console.warn(`QuickJS wasm fetch failed from ${url}`, error);
    }
  }

  throw lastError ?? new Error('Unable to fetch QuickJS wasm binary from configured CDNs');
}

async function getQuickJsInstance() {
  if (!quickJsInstancePromise) {
    quickJsInstancePromise = (async () => {
      const mod = await getQuickJsModule();
      const wasmBinary = await getWasmBinary();
      const variant = mod.newVariant(mod.RELEASE_SYNC, { wasmBinary });
      return mod.newQuickJSWASMModule(variant);
    })();
  }
  return quickJsInstancePromise;
}

function ensureHostBridge() {
  if (typeof globalThis.__elpianQuickJsHostCall !== 'function') {
    globalThis.__elpianQuickJsHostCall = (_machineId, _apiName, _payload) =>
      '{"type":"i16","data":{"value":0}}';
  }
}

function getMachine(machineId) {
  const machine = quickJsMachines.get(machineId);
  if (!machine) {
    throw new Error(`QuickJS machine not found: ${machineId}`);
  }
  return machine;
}

async function initMachine(machineId) {
  if (quickJsMachines.has(machineId)) return;

  ensureHostBridge();
  const qjs = await getQuickJsInstance();
  const ctx = qjs.newContext();

  const askHost = ctx.newFunction('askHost', (...args) => {
    try {
      const apiName = args[0] ? ctx.dump(args[0]) : '';
      const payloadArgs = args.slice(1).map((arg) => ctx.dump(arg));
      let payload = '';

      if (payloadArgs.length === 1) {
        const payloadValue = payloadArgs[0];
        payload = typeof payloadValue === 'string'
          ? payloadValue
          : JSON.stringify(payloadValue ?? null);
      } else if (payloadArgs.length > 1) {
        payload = JSON.stringify(payloadArgs);
      }

      const response = globalThis.__elpianQuickJsHostCall(machineId, String(apiName ?? ''), payload);
      return ctx.newString(typeof response === 'string' ? response : JSON.stringify(response));
    } catch (error) {
      return ctx.newString('{"type":"i16","data":{"value":0}}');
    }
  });

  ctx.setProp(ctx.global, 'askHost', askHost);
  askHost.dispose();

  quickJsMachines.set(machineId, { qjs, ctx });
}

function evalCode(machineId, code) {
  const { ctx } = getMachine(machineId);
  const result = ctx.evalCode(code);
  if (result.error) {
    const err = ctx.dump(result.error);
    result.error.dispose();
    throw new Error(`QuickJS eval error: ${String(err)}`);
  }

  const value = ctx.dump(result.value);
  result.value.dispose();
  return typeof value === 'string' ? value : JSON.stringify(value ?? '');
}

function callFunction(machineId, funcName) {
  return evalCode(machineId, `${funcName}();`);
}

function callFunctionWithInput(machineId, funcName, inputJson) {
  const escaped = JSON.stringify(inputJson);
  return evalCode(machineId, `${funcName}(JSON.parse(${escaped}));`);
}

function disposeMachine(machineId) {
  const machine = quickJsMachines.get(machineId);
  if (!machine) return;
  machine.ctx.dispose();
  quickJsMachines.delete(machineId);
}

globalThis.elpianQuickJs = {
  initMachine,
  evalCode,
  callFunction,
  callFunctionWithInput,
  disposeMachine,
};
