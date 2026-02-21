const quickJsMachines = new Map();
let quickJsModulePromise = null;

async function getQuickJsModule() {
  if (!quickJsModulePromise) {
    quickJsModulePromise = (async () => {
      const candidates = [
        // Preferred: bundled browser ESM build.
        'https://esm.sh/quickjs-emscripten@0.31.0?bundle&target=es2022&browser',
        // Fallback CDN ESM transform.
        'https://cdn.jsdelivr.net/npm/quickjs-emscripten@0.31.0/+esm',
      ];

      let lastError = null;
      for (const url of candidates) {
        try {
          const mod = await import(url);
          if (mod && typeof mod.getQuickJS === 'function') {
            return mod;
          }
          throw new Error(`Module loaded but getQuickJS is missing: ${url}`);
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
  const mod = await getQuickJsModule();
  const qjs = await mod.getQuickJS();
  const ctx = qjs.newContext();

  const askHost = ctx.newFunction('askHost', (...args) => {
    try {
      const apiName = args[0] ? ctx.dump(args[0]) : '';
      const payloadValue = args[1] ? ctx.dump(args[1]) : '';
      const payload = typeof payloadValue === 'string'
        ? payloadValue
        : JSON.stringify(payloadValue ?? null);
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
