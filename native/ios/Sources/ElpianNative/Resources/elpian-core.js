"use strict";
(() => {
  var __defProp = Object.defineProperty;
  var __defProps = Object.defineProperties;
  var __getOwnPropDescs = Object.getOwnPropertyDescriptors;
  var __getOwnPropSymbols = Object.getOwnPropertySymbols;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __propIsEnum = Object.prototype.propertyIsEnumerable;
  var __defNormalProp = (obj2, key, value) => key in obj2 ? __defProp(obj2, key, { enumerable: true, configurable: true, writable: true, value }) : obj2[key] = value;
  var __spreadValues = (a, b) => {
    for (var prop in b || (b = {}))
      if (__hasOwnProp.call(b, prop))
        __defNormalProp(a, prop, b[prop]);
    if (__getOwnPropSymbols)
      for (var prop of __getOwnPropSymbols(b)) {
        if (__propIsEnum.call(b, prop))
          __defNormalProp(a, prop, b[prop]);
      }
    return a;
  };
  var __spreadProps = (a, b) => __defProps(a, __getOwnPropDescs(b));

  // core/src/platform/platform.ts
  var current = null;
  function setPlatform(platform2) {
    current = platform2;
  }
  function platform() {
    if (!current) throw new Error("Elpian core: no platform installed (call setPlatform first)");
    return current;
  }
  function hasPlatform() {
    return current != null;
  }

  // core/src/util/bytes.ts
  function utf8Encode(text2) {
    const out = [];
    for (let i = 0; i < text2.length; i++) {
      let c = text2.charCodeAt(i);
      if (c >= 55296 && c <= 56319 && i + 1 < text2.length) {
        const d = text2.charCodeAt(i + 1);
        if (d >= 56320 && d <= 57343) {
          c = 65536 + (c - 55296 << 10) + (d - 56320);
          i++;
        } else c = 65533;
      } else if (c >= 55296 && c <= 57343) c = 65533;
      if (c < 128) out.push(c);
      else if (c < 2048) out.push(192 | c >> 6, 128 | c & 63);
      else if (c < 65536) out.push(224 | c >> 12, 128 | c >> 6 & 63, 128 | c & 63);
      else out.push(240 | c >> 18, 128 | c >> 12 & 63, 128 | c >> 6 & 63, 128 | c & 63);
    }
    return Uint8Array.from(out);
  }
  function utf8Decode(bytes) {
    let out = "";
    let i = 0;
    const n = bytes.length;
    const push = (cp) => {
      if (cp >= 65536) {
        cp -= 65536;
        out += String.fromCharCode(55296 + (cp >> 10), 56320 + (cp & 1023));
      } else out += String.fromCharCode(cp);
    };
    while (i < n) {
      const b = bytes[i];
      if (b < 128) {
        push(b);
        i++;
        continue;
      }
      let need = 0;
      let cp = 0;
      let min = 0;
      if (b >= 194 && b <= 223) {
        need = 1;
        cp = b & 31;
        min = 128;
      } else if (b >= 224 && b <= 239) {
        need = 2;
        cp = b & 15;
        min = 2048;
      } else if (b >= 240 && b <= 244) {
        need = 3;
        cp = b & 7;
        min = 65536;
      } else {
        push(65533);
        i++;
        continue;
      }
      let j = 1;
      for (; j <= need; j++) {
        const c = bytes[i + j];
        if (c === void 0 || (c & 192) !== 128) break;
        cp = cp << 6 | c & 63;
      }
      if (j <= need || cp < min || cp > 1114111 || cp >= 55296 && cp <= 57343) {
        push(65533);
        i += Math.max(1, j);
        continue;
      }
      push(cp);
      i += need + 1;
    }
    return out;
  }
  var B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  var B64_INDEX = {};
  for (let i = 0; i < B64.length; i++) B64_INDEX[B64[i]] = i;
  B64_INDEX["-"] = 62;
  B64_INDEX["_"] = 63;
  function base64Encode(bytes) {
    let out = "";
    let i = 0;
    for (; i + 2 < bytes.length; i += 3) {
      const v = bytes[i] << 16 | bytes[i + 1] << 8 | bytes[i + 2];
      out += B64[v >> 18] + B64[v >> 12 & 63] + B64[v >> 6 & 63] + B64[v & 63];
    }
    const rest = bytes.length - i;
    if (rest === 1) {
      const v = bytes[i] << 16;
      out += B64[v >> 18] + B64[v >> 12 & 63] + "==";
    } else if (rest === 2) {
      const v = bytes[i] << 16 | bytes[i + 1] << 8;
      out += B64[v >> 18] + B64[v >> 12 & 63] + B64[v >> 6 & 63] + "=";
    }
    return out;
  }
  function base64Decode(text2) {
    const clean = text2.replace(/[\s=]/g, "");
    const out = new Uint8Array(Math.floor(clean.length * 3 / 4));
    let o = 0;
    let acc = 0;
    let bits = 0;
    for (let i = 0; i < clean.length; i++) {
      const v = B64_INDEX[clean[i]];
      if (v === void 0) throw new Error(`invalid base64 character "${clean[i]}"`);
      acc = acc << 6 | v;
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        out[o++] = acc >> bits & 255;
      }
    }
    return out.subarray(0, o);
  }

  // core/src/bridge/native-host.ts
  var ELPIAN_BRIDGE_VERSION = 1;
  var pending = {
    timers: /* @__PURE__ */ new Map(),
    frames: [],
    fetches: /* @__PURE__ */ new Map(),
    streams: /* @__PURE__ */ new Map(),
    assets: /* @__PURE__ */ new Map(),
    godotReplies: /* @__PURE__ */ new Map(),
    godotStats: /* @__PURE__ */ new Map(),
    sandboxes: /* @__PURE__ */ new Map(),
    wasmImports: /* @__PURE__ */ new Map(),
    godotSignal: null,
    imageListeners: /* @__PURE__ */ new Set()
  };
  var nextId = 1;
  var id = () => nextId++;
  function parseOr(json, fallback) {
    if (!json) return fallback;
    try {
      return JSON.parse(json);
    } catch (e) {
      return fallback;
    }
  }
  function nativeHostPlatform(host2) {
    const imageSizes = /* @__PURE__ */ new Map();
    pending.imageListeners.add((src, w2, h) => {
      if (w2 > 0 && h > 0) imageSizes.set(src, { width: w2, height: h });
    });
    const godot = {
      get isLive() {
        return host2.godotIsLive();
      },
      post: (opsJson) => host2.godotPost(opsJson),
      send: (opsJson) => new Promise((resolve) => {
        const rid = id();
        pending.godotReplies.set(rid, resolve);
        host2.godotSend(rid, opsJson);
      }),
      mountSurface: (s, h) => host2.godotMount(s, h),
      releaseSurface: (s) => host2.godotRelease(s),
      setSignalHandler: (handler) => {
        pending.godotSignal = handler;
      },
      stats: () => new Promise((resolve) => {
        const rid = id();
        pending.godotStats.set(rid, (json) => resolve(parseOr(json, null)));
        host2.godotStats(rid);
      })
    };
    const vm = (method, args) => parseOr(host2.vmCall(method, JSON.stringify(args)), null);
    const elpianVm = {
      isAvailable: () => host2.vmAvailable(),
      lastError: () => host2.vmLastError() || null,
      init: () => void vm("init", []),
      createFromAst: (m, ast) => vm("createFromAst", [m, ast]) === true,
      createFromCode: (m, code) => vm("createFromCode", [m, code]) === true,
      createFromBytecode: (m, b64) => vm("createFromBytecode", [m, b64]) === true,
      validateAst: (ast) => vm("validateAst", [ast]) === true,
      execute: (m) => {
        var _a;
        return String((_a = vm("execute", [m])) != null ? _a : "");
      },
      executeFunc: (m, fn, cb) => {
        var _a;
        return String((_a = vm("executeFunc", [m, fn, cb])) != null ? _a : "");
      },
      executeFuncWithInput: (m, fn, input, cb) => {
        var _a;
        return String((_a = vm("executeFuncWithInput", [m, fn, input, cb])) != null ? _a : "");
      },
      continueExecution: (m, input) => {
        var _a;
        return String((_a = vm("continueExecution", [m, input])) != null ? _a : "");
      },
      deliverHostMessage: (m, msg, cb) => {
        var _a;
        return String((_a = vm("deliverHostMessage", [m, msg, cb])) != null ? _a : "");
      },
      destroy: (m) => vm("destroy", [m]) === true,
      exists: (m) => vm("exists", [m]) === true,
      governance: (symbol, args) => {
        const r = vm("governance", [symbol, ...args]);
        return typeof r === "string" ? r : null;
      }
    };
    const jsSandbox = {
      create(machineId) {
        const handle = id();
        host2.sandboxCreate(handle, machineId);
        const sandbox = {
          setHostCallHandler(handler) {
            pending.sandboxes.set(handle, handler);
          },
          evaluate(code) {
            var _a, _b;
            const r = parseOr(host2.sandboxEval(handle, code), { ok: false, error: "malformed sandbox reply" });
            if (!r.ok) throw new Error((_a = r.error) != null ? _a : "evaluation failed");
            return (_b = r.value) != null ? _b : "";
          },
          dispose() {
            pending.sandboxes.delete(handle);
            host2.sandboxDispose(handle);
          }
        };
        return sandbox;
      }
    };
    const wasm = {
      instantiate(bytes, onImport) {
        const handle = id();
        pending.wasmImports.set(handle, onImport);
        const err = host2.wasmInstantiate(handle, base64Encode(bytes));
        if (err) {
          pending.wasmImports.delete(handle);
          throw new Error(err);
        }
        const inst = {
          hasExport: (name) => host2.wasmHasExport(handle, name),
          call: (name, args) => parseOr(host2.wasmCall(handle, name, JSON.stringify(args)), []),
          memoryLength: (mem) => host2.wasmMemoryLength(handle, mem),
          memoryRead: (mem, ptr, len) => base64Decode(host2.wasmMemoryRead(handle, mem, ptr, len)),
          memoryWrite: (mem, ptr, b) => host2.wasmMemoryWrite(handle, mem, ptr, base64Encode(b)),
          dispose: () => {
            pending.wasmImports.delete(handle);
            host2.wasmDispose(handle);
          }
        };
        return inst;
      }
    };
    const platform2 = {
      name: host2.platformName(),
      now: () => host2.now(),
      setTimeout(callback, ms) {
        const h = id();
        pending.timers.set(h, callback);
        host2.scheduleTimer(h, Math.max(0, ms));
        return h;
      },
      clearTimeout(h) {
        if (pending.timers.delete(h)) host2.cancelTimer(h);
      },
      requestFrame(callback) {
        pending.frames.push(callback);
        if (pending.frames.length === 1) host2.requestFrame();
        return pending.frames.length;
      },
      cancelFrame() {
      },
      commit: (surface, ops) => host2.commit(surface, JSON.stringify(ops)),
      measureText: (spec, maxWidth) => parseOr(host2.measureText(JSON.stringify(spec), finite(maxWidth)), { width: 0, height: 0, baseline: 0, lineCount: 0, didExceedMaxLines: false }),
      measureControl: (spec, maxWidth) => parseOr(host2.measureControl(JSON.stringify(spec), finite(maxWidth)), null),
      imageSize: (src) => {
        var _a;
        return (_a = imageSizes.get(src)) != null ? _a : parseOr(host2.imageSize(src), null);
      },
      preloadImage: (src) => host2.preloadImage(src),
      viewport: (surface) => parseOr(host2.viewport(surface), DEFAULT_VIEWPORT),
      log: (level, message) => host2.log(level, message),
      openUrl: (url) => host2.openUrl(url),
      fetch: (request) => new Promise((resolve, reject) => {
        const rid = id();
        pending.fetches.set(rid, { resolve, reject });
        host2.fetch(rid, JSON.stringify(request));
      }),
      fetchStream(request, handlers) {
        const rid = id();
        pending.streams.set(rid, handlers);
        host2.fetchStream(rid, JSON.stringify(request));
        return () => {
          if (pending.streams.delete(rid)) host2.cancelFetch(rid);
        };
      },
      storageGet: (key) => host2.storageGet(key),
      storageSet: (key, value) => host2.storageSet(key, value),
      loadAsset: (path, encoding) => new Promise((resolve, reject) => {
        const rid = id();
        pending.assets.set(rid, { resolve, reject });
        host2.loadAsset(rid, path, encoding);
      }),
      godot,
      elpianVm: host2.vmAvailable() ? elpianVm : void 0,
      jsSandbox: host2.sandboxAvailable() ? jsSandbox : void 0,
      wasm: host2.wasmAvailable() ? wasm : void 0
    };
    return platform2;
  }
  function finite(n) {
    return Number.isFinite(n) ? n : -1;
  }
  var DEFAULT_VIEWPORT = {
    width: 360,
    height: 640,
    devicePixelRatio: 1,
    safeArea: { top: 0, right: 0, bottom: 0, left: 0 },
    locale: "en-US",
    platform: "unknown",
    isWeb: false,
    darkMode: false,
    textScale: 1
  };

  // core/src/render/object.ts
  var INF = Number.POSITIVE_INFINITY;
  function tight(width, height) {
    return { minWidth: width, maxWidth: width, minHeight: height, maxHeight: height };
  }
  function loose(c) {
    return { minWidth: 0, maxWidth: c.maxWidth, minHeight: 0, maxHeight: c.maxHeight };
  }
  function tightFor(c, width, height) {
    return {
      minWidth: width != null ? clampN(width, c.minWidth, c.maxWidth) : c.minWidth,
      maxWidth: width != null ? clampN(width, c.minWidth, c.maxWidth) : c.maxWidth,
      minHeight: height != null ? clampN(height, c.minHeight, c.maxHeight) : c.minHeight,
      maxHeight: height != null ? clampN(height, c.minHeight, c.maxHeight) : c.maxHeight
    };
  }
  function enforce(inner, outer) {
    return {
      minWidth: clampN(inner.minWidth, outer.minWidth, outer.maxWidth),
      maxWidth: clampN(inner.maxWidth, outer.minWidth, outer.maxWidth),
      minHeight: clampN(inner.minHeight, outer.minHeight, outer.maxHeight),
      maxHeight: clampN(inner.maxHeight, outer.minHeight, outer.maxHeight)
    };
  }
  function deflate(c, h, v) {
    const minW = Math.max(0, c.minWidth - h);
    const minH = Math.max(0, c.minHeight - v);
    return {
      minWidth: minW,
      maxWidth: Math.max(minW, c.maxWidth - h),
      minHeight: minH,
      maxHeight: Math.max(minH, c.maxHeight - v)
    };
  }
  function constrain(c, s) {
    return { width: clampN(s.width, c.minWidth, c.maxWidth), height: clampN(s.height, c.minHeight, c.maxHeight) };
  }
  function biggest(c) {
    return {
      width: Number.isFinite(c.maxWidth) ? c.maxWidth : c.minWidth,
      height: Number.isFinite(c.maxHeight) ? c.maxHeight : c.minHeight
    };
  }
  function smallest(c) {
    return { width: c.minWidth, height: c.minHeight };
  }
  function clampN(v, lo, hi) {
    if (v < lo) return lo;
    if (v > hi) return hi;
    return v;
  }
  function constraintsEqual(a, b) {
    return !!a && a.minWidth === b.minWidth && a.maxWidth === b.maxWidth && a.minHeight === b.minHeight && a.maxHeight === b.maxHeight;
  }
  function w(t, p = {}, c, k) {
    const children = c == null ? void 0 : Array.isArray(c) ? c : [c];
    return { t, p, c: children, k: k != null ? k : null };
  }
  var RenderObject = class {
    constructor() {
      this.type = "";
      this.key = null;
      this.props = {};
      this.parent = null;
      this.children = [];
      this.owner = null;
      this.size = { width: 0, height: 0 };
      /** Offset of this object's top-left inside its parent's coordinate space. */
      this.offset = { x: 0, y: 0 };
      this.needsLayout = true;
      this.lastConstraints = null;
      /** Cache of intrinsic queries, cleared on layout invalidation. */
      this.intrinsicCache = /* @__PURE__ */ new Map();
      /** The native view this object owns, when it paints. */
      this.viewId = null;
    }
    // ---------------------------------------------------------------------------
    // Lifecycle (driven by the reconciler)
    // ---------------------------------------------------------------------------
    /** First configuration. */
    init(props) {
      this.props = props;
    }
    /** A new configuration for an existing object. Default: relayout. */
    update(props) {
      const old = this.props;
      this.props = props;
      this.didUpdate(old);
      this.markNeedsLayout();
    }
    /** Hook for subclasses to react to a configuration change (start animations …). */
    didUpdate(_old) {
    }
    attach(owner) {
      this.owner = owner;
      this.onAttach();
    }
    detach() {
      this.onDetach();
      for (const c of this.children) c.detach();
      this.owner = null;
    }
    onAttach() {
    }
    onDetach() {
    }
    markNeedsLayout() {
      var _a;
      let node = this;
      while (node && !node.needsLayout) {
        node.needsLayout = true;
        node.intrinsicCache.clear();
        node = node.parent;
      }
      if (node) node.intrinsicCache.clear();
      (_a = this.owner) == null ? void 0 : _a.requestVisualUpdate();
    }
    /** Paint-only change: re-emit this view's props without relayout. */
    markNeedsPaint() {
      var _a;
      (_a = this.owner) == null ? void 0 : _a.markPaintDirty(this);
    }
    // ---------------------------------------------------------------------------
    // Layout
    // ---------------------------------------------------------------------------
    layout(c) {
      if (!this.needsLayout && constraintsEqual(this.lastConstraints, c)) return;
      this.lastConstraints = c;
      this.performLayout(c);
      if (!Number.isFinite(this.size.width)) this.size.width = Number.isFinite(c.minWidth) ? c.minWidth : 0;
      if (!Number.isFinite(this.size.height)) this.size.height = Number.isFinite(c.minHeight) ? c.minHeight : 0;
      this.needsLayout = false;
      this.intrinsicCache.clear();
    }
    get constraints() {
      return this.lastConstraints;
    }
    get child() {
      var _a;
      return (_a = this.children[0]) != null ? _a : null;
    }
    // Intrinsics (Flutter getMin/MaxIntrinsicWidth/Height).
    minIntrinsicWidth(height) {
      return this.cachedIntrinsic("minW", height, () => this.computeMinIntrinsicWidth(height));
    }
    maxIntrinsicWidth(height) {
      return this.cachedIntrinsic("maxW", height, () => this.computeMaxIntrinsicWidth(height));
    }
    minIntrinsicHeight(width) {
      return this.cachedIntrinsic("minH", width, () => this.computeMinIntrinsicHeight(width));
    }
    maxIntrinsicHeight(width) {
      return this.cachedIntrinsic("maxH", width, () => this.computeMaxIntrinsicHeight(width));
    }
    cachedIntrinsic(kind, extent, compute) {
      const key = kind + ":" + extent;
      const hit = this.intrinsicCache.get(key);
      if (hit !== void 0) return hit;
      const v = compute();
      this.intrinsicCache.set(key, v);
      return v;
    }
    computeMinIntrinsicWidth(height) {
      var _a, _b;
      return (_b = (_a = this.child) == null ? void 0 : _a.minIntrinsicWidth(height)) != null ? _b : 0;
    }
    computeMaxIntrinsicWidth(height) {
      var _a, _b;
      return (_b = (_a = this.child) == null ? void 0 : _a.maxIntrinsicWidth(height)) != null ? _b : 0;
    }
    computeMinIntrinsicHeight(width) {
      var _a, _b;
      return (_b = (_a = this.child) == null ? void 0 : _a.minIntrinsicHeight(width)) != null ? _b : 0;
    }
    computeMaxIntrinsicHeight(width) {
      var _a, _b;
      return (_b = (_a = this.child) == null ? void 0 : _a.maxIntrinsicHeight(width)) != null ? _b : 0;
    }
    /** Distance from the top to the first alphabetic baseline, if any. */
    baseline() {
      const c = this.child;
      if (!c) return null;
      const b = c.baseline();
      return b == null ? null : b + c.offset.y;
    }
    // ---------------------------------------------------------------------------
    // Painting
    // ---------------------------------------------------------------------------
    /** The native view kind when this object owns a view, otherwise null. */
    viewKind() {
      return null;
    }
    /** This object's view props (frame excluded — the compositor fills it). */
    viewProps() {
      return {};
    }
    /**
     * Offset added to children inside this object's own view (a scroll view's
     * children live in content space, so it reports none).
     */
    childOriginInView() {
      return { x: 0, y: 0 };
    }
    /** Whether [child] is painted (IndexedStack / Offstage hide some children). */
    paintsChild(_child) {
      return true;
    }
    /** Called by the compositor when the platform reports an event on this view. */
    handleViewEvent(_event) {
    }
    /** Visit descendants. */
    visit(fn) {
      fn(this);
      for (const c of this.children) c.visit(fn);
    }
    toString() {
      return `${this.type}${this.key ? `#${this.key}` : ""}(${this.size.width.toFixed(1)}x${this.size.height.toFixed(1)})`;
    }
  };
  var RenderProxy = class extends RenderObject {
    performLayout(c) {
      const child = this.child;
      if (child) {
        child.layout(c);
        child.offset = { x: 0, y: 0 };
        this.size = __spreadValues({}, child.size);
      } else {
        this.size = smallest(c);
      }
    }
  };

  // core/src/util/json.ts
  function isMap(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
  }
  function parseVmPayload(payload) {
    if (payload === "" || payload == null) return null;
    try {
      return JSON.parse(payload);
    } catch (e) {
      if (payload.length >= 2 && payload.startsWith('"') && payload.endsWith('"')) {
        return payload.substring(1, payload.length - 1);
      }
      return payload;
    }
  }
  function unwrapHostArgs(parsed) {
    if (Array.isArray(parsed)) return parsed.length === 0 ? null : parsed[0];
    return parsed;
  }
  function asHostArgs(parsed) {
    return Array.isArray(parsed) ? parsed : [parsed];
  }
  function normalizedArgs(payload) {
    const unwrapped = unwrapHostArgs(parseVmPayload(payload));
    return isMap(unwrapped) ? unwrapped : {};
  }
  function coerceJsonMap(value) {
    if (isMap(value)) return value;
    if (typeof value !== "string") return null;
    try {
      const decoded = JSON.parse(value);
      return isMap(decoded) ? decoded : null;
    } catch (e) {
      return null;
    }
  }
  function toNumber(value) {
    if (typeof value === "number") return Number.isFinite(value) ? value : null;
    if (typeof value === "string") {
      const n = parseFloat(value);
      return Number.isFinite(n) ? n : null;
    }
    return null;
  }
  function deepEqual(a, b) {
    if (a === b) return true;
    if (typeof a !== typeof b || a == null || b == null) return false;
    if (Array.isArray(a)) {
      if (!Array.isArray(b) || a.length !== b.length) return false;
      for (let i = 0; i < a.length; i++) if (!deepEqual(a[i], b[i])) return false;
      return true;
    }
    if (typeof a === "object") {
      if (Array.isArray(b)) return false;
      const ka = Object.keys(a);
      const kb = Object.keys(b);
      if (ka.length !== kb.length) return false;
      for (const k of ka) if (!deepEqual(a[k], b[k])) return false;
      return true;
    }
    return false;
  }
  function deepMerge(base, patch) {
    const result = __spreadValues({}, base);
    for (const key of Object.keys(patch)) {
      const pv = patch[key];
      const bv = result[key];
      result[key] = isMap(pv) && isMap(bv) ? deepMerge(bv, pv) : pv;
    }
    return result;
  }
  function stableKey(value) {
    if (value === void 0) return "u";
    if (value === null || typeof value !== "object") return JSON.stringify(value);
    if (Array.isArray(value)) return "[" + value.map(stableKey).join(",") + "]";
    const keys = Object.keys(value).sort();
    return "{" + keys.map((k) => JSON.stringify(k) + ":" + stableKey(value[k])).join(",") + "}";
  }

  // core/src/css/environment.ts
  var env = {
    viewportWidth: 1280,
    viewportHeight: 800,
    safeArea: { top: 0, right: 0, bottom: 0, left: 0 },
    rootFontSize: 16,
    devicePixelRatio: 1
  };
  var generation = 0;
  function cssEnvironment() {
    return env;
  }
  function cssEnvironmentGeneration() {
    return generation;
  }
  function updateCssEnvironment(next) {
    let changed = false;
    for (const key of Object.keys(next)) {
      const value = next[key];
      if (value === void 0) continue;
      if (key === "safeArea") {
        const s = value;
        const c = env.safeArea;
        if (s.top !== c.top || s.right !== c.right || s.bottom !== c.bottom || s.left !== c.left) {
          env.safeArea = __spreadValues({}, s);
          changed = true;
        }
      } else if (env[key] !== value) {
        env[key] = value;
        changed = true;
      }
    }
    if (changed) generation++;
    return changed;
  }

  // core/src/css/color.ts
  var Colors = {
    transparent: 0,
    black: 4278190080,
    black87: 3707764736,
    black54: 2315255808,
    black45: 1929379840,
    black38: 1627389952,
    black26: 1107296256,
    black12: 520093696,
    white: 4294967295,
    white70: 3019898879,
    white60: 2583691263,
    white54: 2332033023,
    white38: 1660944383,
    white30: 1308622847,
    white24: 1040187391,
    white12: 536870911,
    white10: 452984831,
    red: 4294198070,
    pink: 4293467747,
    purple: 4288423856,
    deepPurple: 4284955319,
    indigo: 4282339765,
    blue: 4280391411,
    lightBlue: 4278430196,
    cyan: 4278238420,
    teal: 4278228616,
    green: 4283215696,
    lightGreen: 4287349578,
    lime: 4291681337,
    yellow: 4294961979,
    amber: 4294951175,
    orange: 4294940672,
    deepOrange: 4294924066,
    brown: 4286141768,
    grey: 4288585374,
    grey100: 4294309365,
    grey200: 4293848814,
    grey300: 4292927712,
    grey400: 4290624957,
    grey600: 4285887861,
    blueGrey: 4284513675
  };
  var M3 = {
    primary: 4284960932,
    onPrimary: 4294967295,
    primaryContainer: 4293582335,
    secondaryContainer: 4293451512,
    onSecondaryContainer: 4280097067,
    surface: 4294899711,
    surfaceContainerLow: 4294439674,
    surfaceContainerHighest: 4293320937,
    onSurface: 4280097568,
    onSurfaceVariant: 4282991951,
    outline: 4286149758,
    outlineVariant: 4291478736,
    error: 4289930782,
    inverseSurface: 4281478965,
    onInverseSurface: 4294307831,
    shadow: 4278190080
  };
  var flutterNamed = {
    transparent: Colors.transparent,
    black: Colors.black,
    white: Colors.white,
    red: Colors.red,
    green: Colors.green,
    blue: Colors.blue,
    yellow: Colors.yellow,
    orange: Colors.orange,
    purple: Colors.purple,
    pink: Colors.pink,
    grey: Colors.grey,
    gray: Colors.grey,
    brown: Colors.brown,
    cyan: Colors.cyan,
    indigo: Colors.indigo,
    lime: Colors.lime,
    teal: Colors.teal,
    amber: Colors.amber,
    deeporange: Colors.deepOrange,
    "deep-orange": Colors.deepOrange,
    deeppurple: Colors.deepPurple,
    "deep-purple": Colors.deepPurple,
    lightblue: Colors.lightBlue,
    "light-blue": Colors.lightBlue,
    lightgreen: Colors.lightGreen,
    "light-green": Colors.lightGreen,
    bluegrey: Colors.blueGrey,
    "blue-grey": Colors.blueGrey
  };
  var cssNamed = {
    aliceblue: 15792383,
    antiquewhite: 16444375,
    aqua: 65535,
    aquamarine: 8388564,
    azure: 15794175,
    beige: 16119260,
    bisque: 16770244,
    blanchedalmond: 16772045,
    blueviolet: 9055202,
    burlywood: 14596231,
    cadetblue: 6266528,
    chartreuse: 8388352,
    chocolate: 13789470,
    coral: 16744272,
    cornflowerblue: 6591981,
    cornsilk: 16775388,
    crimson: 14423100,
    darkblue: 139,
    darkcyan: 35723,
    darkgoldenrod: 12092939,
    darkgray: 11119017,
    darkgrey: 11119017,
    darkgreen: 25600,
    darkkhaki: 12433259,
    darkmagenta: 9109643,
    darkolivegreen: 5597999,
    darkorange: 16747520,
    darkorchid: 10040012,
    darkred: 9109504,
    darksalmon: 15308410,
    darkseagreen: 9419919,
    darkslateblue: 4734347,
    darkslategray: 3100495,
    darkslategrey: 3100495,
    darkturquoise: 52945,
    darkviolet: 9699539,
    deeppink: 16716947,
    deepskyblue: 49151,
    dimgray: 6908265,
    dimgrey: 6908265,
    dodgerblue: 2003199,
    firebrick: 11674146,
    floralwhite: 16775920,
    forestgreen: 2263842,
    fuchsia: 16711935,
    gainsboro: 14474460,
    ghostwhite: 16316671,
    gold: 16766720,
    goldenrod: 14329120,
    greenyellow: 11403055,
    honeydew: 15794160,
    hotpink: 16738740,
    indianred: 13458524,
    ivory: 16777200,
    khaki: 15787660,
    lavender: 15132410,
    lavenderblush: 16773365,
    lawngreen: 8190976,
    lemonchiffon: 16775885,
    lightcoral: 15761536,
    lightcyan: 14745599,
    lightgoldenrodyellow: 16448210,
    lightgray: 13882323,
    lightgrey: 13882323,
    lightpink: 16758465,
    lightsalmon: 16752762,
    lightseagreen: 2142890,
    lightskyblue: 8900346,
    lightslategray: 7833753,
    lightslategrey: 7833753,
    lightsteelblue: 11584734,
    lightyellow: 16777184,
    limegreen: 3329330,
    linen: 16445670,
    magenta: 16711935,
    maroon: 8388608,
    mediumaquamarine: 6737322,
    mediumblue: 205,
    mediumorchid: 12211667,
    mediumpurple: 9662683,
    mediumseagreen: 3978097,
    mediumslateblue: 8087790,
    mediumspringgreen: 64154,
    mediumturquoise: 4772300,
    mediumvioletred: 13047173,
    midnightblue: 1644912,
    mintcream: 16121850,
    mistyrose: 16770273,
    moccasin: 16770229,
    navajowhite: 16768685,
    navy: 128,
    oldlace: 16643558,
    olive: 8421376,
    olivedrab: 7048739,
    orangered: 16729344,
    orchid: 14315734,
    palegoldenrod: 15657130,
    palegreen: 10025880,
    paleturquoise: 11529966,
    palevioletred: 14381203,
    papayawhip: 16773077,
    peachpuff: 16767673,
    peru: 13468991,
    plum: 14524637,
    powderblue: 11591910,
    rebeccapurple: 6697881,
    rosybrown: 12357519,
    royalblue: 4286945,
    saddlebrown: 9127187,
    salmon: 16416882,
    sandybrown: 16032864,
    seagreen: 3050327,
    seashell: 16774638,
    sienna: 10506797,
    silver: 12632256,
    skyblue: 8900331,
    slateblue: 6970061,
    slategray: 7372944,
    slategrey: 7372944,
    snow: 16775930,
    springgreen: 65407,
    steelblue: 4620980,
    tan: 13808780,
    thistle: 14204888,
    tomato: 16737095,
    turquoise: 4251856,
    violet: 15631086,
    wheat: 16113331,
    whitesmoke: 16119285,
    yellowgreen: 10145074
  };
  function argb(a, r, g, b) {
    return ((a & 255) << 24 | (r & 255) << 16 | (g & 255) << 8 | b & 255) >>> 0;
  }
  var alphaOf = (c) => c >>> 24 & 255;
  var redOf = (c) => c >>> 16 & 255;
  var greenOf = (c) => c >>> 8 & 255;
  var blueOf = (c) => c & 255;
  function withOpacity(c, opacity) {
    const a = Math.round(Math.max(0, Math.min(1, opacity)) * 255);
    return (c & 16777215 | a << 24) >>> 0;
  }
  function scaleAlpha(c, factor) {
    return withOpacity(c, alphaOf(c) / 255 * factor);
  }
  function lerpColor(a, b, t) {
    const l = (x, y) => Math.round(x + (y - x) * t);
    return argb(l(alphaOf(a), alphaOf(b)), l(redOf(a), redOf(b)), l(greenOf(a), greenOf(b)), l(blueOf(a), blueOf(b)));
  }
  function hslToRgb(h, s, l) {
    const chroma = (1 - Math.abs(2 * l - 1)) * s;
    const hp = (h % 360 + 360) % 360 / 60;
    const x = chroma * (1 - Math.abs(hp % 2 - 1));
    let r = 0, g = 0, b = 0;
    if (hp < 1) [r, g, b] = [chroma, x, 0];
    else if (hp < 2) [r, g, b] = [x, chroma, 0];
    else if (hp < 3) [r, g, b] = [0, chroma, x];
    else if (hp < 4) [r, g, b] = [0, x, chroma];
    else if (hp < 5) [r, g, b] = [x, 0, chroma];
    else [r, g, b] = [chroma, 0, x];
    const m = l - chroma / 2;
    return [Math.round((r + m) * 255), Math.round((g + m) * 255), Math.round((b + m) * 255)];
  }
  function channel(token, scale) {
    const t = token.trim();
    if (t.endsWith("%")) return parseFloat(t) / 100 * scale;
    return parseFloat(t);
  }
  function alphaChannel(token) {
    if (token == null || token.trim() === "") return 1;
    const t = token.trim();
    if (t.endsWith("%")) return parseFloat(t) / 100;
    return parseFloat(t);
  }
  var cache = /* @__PURE__ */ new Map();
  function parseColor(value) {
    if (value == null) return null;
    if (typeof value === "number") return value >>> 0;
    if (typeof value !== "string") return null;
    const cached = cache.get(value);
    if (cached !== void 0) return cached;
    const parsed = parseColorString(value.trim());
    if (cache.size > 2048) cache.clear();
    cache.set(value, parsed);
    return parsed;
  }
  function parseColorString(raw) {
    if (raw === "") return null;
    const lower = raw.toLowerCase();
    if (lower.startsWith("#")) {
      let hex = lower.substring(1);
      if (hex.length === 3 || hex.length === 4) {
        hex = hex.split("").map((c) => c + c).join("");
      }
      if (!/^[0-9a-f]+$/.test(hex)) return null;
      if (hex.length === 6) return (4278190080 | parseInt(hex, 16)) >>> 0;
      if (hex.length === 8) return parseInt(hex, 16) >>> 0;
      return null;
    }
    if (lower.startsWith("0x")) {
      const n = parseInt(lower.substring(2), 16);
      if (Number.isFinite(n)) return (lower.length <= 8 ? 4278190080 | n : n) >>> 0;
      return null;
    }
    const fn = /^(rgba?|hsla?)\(\s*([^)]*)\)$/.exec(lower);
    if (fn) {
      const body = fn[2];
      let parts;
      let alphaPart;
      if (body.includes(",")) {
        parts = body.split(",").map((p) => p.trim());
        if (parts.length === 4) alphaPart = parts.pop();
      } else {
        const [main, a] = body.split("/");
        parts = main.trim().split(/\s+/);
        alphaPart = a;
        if (parts.length === 4 && alphaPart == null) alphaPart = parts.pop();
      }
      if (parts.length < 3) return null;
      const alpha = Math.max(0, Math.min(1, alphaChannel(alphaPart)));
      if (fn[1].startsWith("rgb")) {
        const r2 = channel(parts[0], 255), g2 = channel(parts[1], 255), b2 = channel(parts[2], 255);
        if ([r2, g2, b2, alpha].some((n) => Number.isNaN(n))) return null;
        return argb(Math.trunc(alpha * 255), Math.round(r2), Math.round(g2), Math.round(b2));
      }
      let h = parseFloat(parts[0]);
      if (parts[0].endsWith("turn")) h *= 360;
      else if (parts[0].endsWith("rad")) h = h * 180 / Math.PI;
      const s = parseFloat(parts[1]) / 100;
      const l = parseFloat(parts[2]) / 100;
      if ([h, s, l, alpha].some((n) => Number.isNaN(n))) return null;
      const [r, g, b] = hslToRgb(h, s, l);
      return argb(Math.round(alpha * 255), r, g, b);
    }
    const named = flutterNamed[lower];
    if (named !== void 0) return named >>> 0;
    const css = cssNamed[lower];
    if (css !== void 0) return (4278190080 | css) >>> 0;
    if (lower === "currentcolor") return null;
    return null;
  }

  // core/src/canvas/store.ts
  var CANVAS_COMMAND_TYPES = [
    "moveTo",
    "lineTo",
    "quadraticCurveTo",
    "bezierCurveTo",
    "arc",
    "arcTo",
    "ellipse",
    "rect",
    "roundRect",
    "circle",
    "fillRect",
    "strokeRect",
    "clearRect",
    "fillCircle",
    "strokeCircle",
    "fillPolygon",
    "strokePolygon",
    "fillText",
    "strokeText",
    "drawImage",
    "drawImageRect",
    "beginPath",
    "closePath",
    "fill",
    "stroke",
    "clip",
    "save",
    "restore",
    "translate",
    "rotate",
    "scale",
    "transform",
    "setTransform",
    "resetTransform",
    "setFillStyle",
    "setStrokeStyle",
    "setLineWidth",
    "setLineCap",
    "setLineJoin",
    "setMiterLimit",
    "setLineDash",
    "setLineDashOffset",
    "setShadowBlur",
    "setShadowColor",
    "setShadowOffsetX",
    "setShadowOffsetY",
    "setGlobalAlpha",
    "setGlobalCompositeOperation",
    "setFont",
    "setTextAlign",
    "setTextBaseline",
    "createLinearGradient",
    "createRadialGradient",
    "addColorStop",
    "createPattern",
    "putImageData",
    "getImageData",
    "createImageData",
    "custom"
  ];
  var TYPES = new Set(CANVAS_COMMAND_TYPES);
  function isCanvasCommandType(name) {
    return TYPES.has(name);
  }
  function commandFromJson(json) {
    var _a;
    const t = typeof (json == null ? void 0 : json.type) === "string" && TYPES.has(json.type) ? json.type : "custom";
    const params = (json == null ? void 0 : json.params) && typeof json.params === "object" ? __spreadValues({}, json.params) : {};
    return { type: t, params, id: (_a = json == null ? void 0 : json.id) != null ? _a : null };
  }
  var COLOR_KEYS = ["color", "shadowColor"];
  function normalizeCommand(cmd) {
    const p = {};
    for (const [k, v] of Object.entries(cmd.params)) {
      if (COLOR_KEYS.includes(k)) {
        p[k] = canvasColor(v);
      } else if (k === "colors" && Array.isArray(v)) {
        p[k] = v.map(canvasColor);
      } else if (typeof v === "string" && /^-?\d+(\.\d+)?$/.test(v.trim()) && !["text", "font", "id", "gradientId", "patternId", "src", "imageId", "data"].includes(k)) {
        p[k] = parseFloat(v);
      } else {
        p[k] = v;
      }
    }
    return cmd.id ? { type: cmd.type, params: p, id: cmd.id } : { type: cmd.type, params: p };
  }
  function canvasColor(value) {
    if (typeof value === "number") return value >>> 0;
    const parsed = parseColor(value);
    return parsed != null ? parsed : 4278190080;
  }
  var CanvasContext = class {
    constructor(id2, width, height) {
      this.id = id2;
      this.width = width;
      this.height = height;
      /** Every command ever added since the last clear. */
      this.commands = [];
      /** Bumped on every change (Flutter's `version` notifier). */
      this.version = 0;
      /** Bumped when the command list is reset (clear / resize) — painters redraw from scratch. */
      this.generation = 0;
      this.listeners = /* @__PURE__ */ new Set();
    }
    setSize(w2, h) {
      if (w2 === this.width && h === this.height) return;
      this.width = w2;
      this.height = h;
      this.generation++;
      this.changed();
    }
    addCommand(cmd) {
      this.commands.push(normalizeCommand(cmd));
      this.changed();
    }
    addCommands(cmds) {
      for (const c of cmds) this.commands.push(normalizeCommand(c));
      this.changed();
    }
    clear() {
      this.commands = [];
      this.generation++;
      this.changed();
    }
    onChange(fn) {
      this.listeners.add(fn);
      return () => this.listeners.delete(fn);
    }
    changed() {
      this.version++;
      for (const l of [...this.listeners]) l();
    }
    dispose() {
      this.listeners.clear();
      this.commands = [];
    }
  };
  var CanvasContextStore = class {
    constructor() {
      this.contexts = /* @__PURE__ */ new Map();
      this.nextId = 1;
    }
    create(opts = {}) {
      var _a, _b;
      const id2 = opts.id && opts.id !== "" ? opts.id : `ctx_${this.nextId++}`;
      const existing = this.contexts.get(id2);
      if (existing) return existing;
      const ctx = new CanvasContext(id2, (_a = opts.width) != null ? _a : 0, (_b = opts.height) != null ? _b : 0);
      this.contexts.set(id2, ctx);
      return ctx;
    }
    get(id2) {
      return this.contexts.get(id2);
    }
    dispose(id2) {
      const ctx = this.contexts.get(id2);
      this.contexts.delete(id2);
      ctx == null ? void 0 : ctx.dispose();
    }
    clearAll() {
      for (const ctx of this.contexts.values()) ctx.dispose();
      this.contexts.clear();
    }
  };
  var CanvasExecutor = class {
    constructor() {
      this.commands = [];
    }
    addCommand(cmd) {
      this.commands.push(cmd);
    }
    addCommands(cmds) {
      this.commands.push(...cmds);
    }
    clear() {
      this.commands = [];
    }
  };

  // core/src/css/types.ts
  var EdgeInsetsZero = Object.freeze({ top: 0, right: 0, bottom: 0, left: 0 });
  function insetsAll(v) {
    return { top: v, right: v, bottom: v, left: v };
  }
  function insetsSymmetric(vertical, horizontal) {
    return { top: vertical, right: horizontal, bottom: vertical, left: horizontal };
  }
  function insetsOnly(o) {
    var _a, _b, _c, _d;
    return { top: (_a = o.top) != null ? _a : 0, right: (_b = o.right) != null ? _b : 0, bottom: (_c = o.bottom) != null ? _c : 0, left: (_d = o.left) != null ? _d : 0 };
  }
  function lerpInsets(a, b, t) {
    const l = (x, y) => x + (y - x) * t;
    return { top: l(a.top, b.top), right: l(a.right, b.right), bottom: l(a.bottom, b.bottom), left: l(a.left, b.left) };
  }
  var Align = {
    topLeft: { x: -1, y: -1 },
    topCenter: { x: 0, y: -1 },
    topRight: { x: 1, y: -1 },
    centerLeft: { x: -1, y: 0 },
    center: { x: 0, y: 0 },
    centerRight: { x: 1, y: 0 },
    bottomLeft: { x: -1, y: 1 },
    bottomCenter: { x: 0, y: 1 },
    bottomRight: { x: 1, y: 1 }
  };
  function lerpAlignment(a, b, t) {
    return { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t };
  }
  var BorderSideNone = Object.freeze({ width: 0, color: 4278190080, style: "none" });
  function borderAll(side2) {
    return { top: side2, right: side2, bottom: side2, left: side2 };
  }
  function borderInsets(b) {
    if (!b) return EdgeInsetsZero;
    const w2 = (s) => s.style === "none" ? 0 : s.width;
    return { top: w2(b.top), right: w2(b.right), bottom: w2(b.bottom), left: w2(b.left) };
  }
  function radiusAll(r) {
    return { topLeft: r, topRight: r, bottomRight: r, bottomLeft: r };
  }
  function lerpRadius(a, b, t) {
    const l = (x, y) => x + (y - x) * t;
    return {
      topLeft: l(a.topLeft, b.topLeft),
      topRight: l(a.topRight, b.topRight),
      bottomRight: l(a.bottomRight, b.bottomRight),
      bottomLeft: l(a.bottomLeft, b.bottomLeft)
    };
  }
  var IDENTITY = Object.freeze([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]);

  // core/src/css/matrix.ts
  function identity() {
    return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
  }
  function isIdentity(m) {
    if (!m) return true;
    const id2 = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
    for (let i = 0; i < 16; i++) if (Math.abs(m[i] - id2[i]) > 1e-12) return false;
    return true;
  }
  function multiply(a, b) {
    const out = new Array(16);
    for (let c = 0; c < 4; c++) {
      for (let r = 0; r < 4; r++) {
        let sum = 0;
        for (let k = 0; k < 4; k++) sum += a[k * 4 + r] * b[c * 4 + k];
        out[c * 4 + r] = sum;
      }
    }
    return out;
  }
  function translation(x, y, z = 0) {
    return [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, z, 1];
  }
  function scaling(x, y, z = 1) {
    return [x, 0, 0, 0, 0, y, 0, 0, 0, 0, z, 0, 0, 0, 0, 1];
  }
  function rotationZ(radians) {
    const c = Math.cos(radians);
    const s = Math.sin(radians);
    return [c, s, 0, 0, -s, c, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
  }
  function skew(ax, ay) {
    return [1, Math.tan(ay), 0, 0, Math.tan(ax), 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
  }
  function fromCssMatrix(v) {
    if (v.length === 6) {
      const [a, b, c, d, e, f] = v;
      return [a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, e, f, 0, 1];
    }
    if (v.length === 16) return v.slice();
    return null;
  }
  function aboutOrigin(m, ox, oy) {
    return multiply(multiply(translation(ox, oy), m), translation(-ox, -oy));
  }
  function lerpMatrix(a, b, t) {
    return a.map((v, i) => v + (b[i] - v) * t);
  }

  // core/src/css/parser.ts
  var MAX_CACHE = 512;
  var cache2 = /* @__PURE__ */ new Map();
  function pick(m, camel) {
    const v = m[camel];
    if (v !== void 0 && v !== null) return v;
    const kebab = camel.replace(/[A-Z]/g, (c) => "-" + c.toLowerCase());
    return kebab === camel ? void 0 : m[kebab];
  }
  function str(v) {
    if (v == null) return null;
    return typeof v === "string" ? v : String(v);
  }
  var VIEWPORT_KEYS = [
    "width",
    "height",
    "minWidth",
    "min-width",
    "maxWidth",
    "max-width",
    "minHeight",
    "min-height",
    "maxHeight",
    "max-height",
    "top",
    "right",
    "bottom",
    "left",
    "padding",
    "margin",
    "gap"
  ];
  function hasViewportUnits(m) {
    for (const key of VIEWPORT_KEYS) {
      const v = m[key];
      if (typeof v === "string" && /%|vw|vh|vmin|vmax|calc\(|env\(/.test(v)) return true;
    }
    return false;
  }
  var CSSParser = {
    parse(styleMap) {
      const viewportDependent = hasViewportUnits(styleMap);
      const key = (viewportDependent ? "g" + cssEnvironmentGeneration() + ":" : "") + stableKey(styleMap);
      const hit = cache2.get(key);
      if (hit) {
        cache2.delete(key);
        cache2.set(key, hit);
        return hit;
      }
      const style = parseUncached(styleMap);
      if (cache2.size >= MAX_CACHE) cache2.delete(cache2.keys().next().value);
      cache2.set(key, style);
      return style;
    },
    clearCache() {
      cache2.clear();
    },
    get cacheSize() {
      return cache2.size;
    },
    parseColor,
    parseDouble,
    parseDimension,
    parseAlignment,
    parseOffset,
    parseDuration,
    parseEdgeInsets,
    parseGradient,
    parseBoxShadow,
    parseTransform,
    stripImportant,
    isImportant
  };
  function stripImportant(value) {
    if (typeof value === "string") {
      const re = /\s*!\s*important\s*$/i;
      if (re.test(value)) return value.replace(re, "").trim();
    }
    return value;
  }
  function isImportant(value) {
    return typeof value === "string" && /!\s*important\s*$/i.test(value);
  }
  function parseUncached(m) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j, _k, _l, _m, _n, _o, _p, _q, _r, _s, _t, _u, _v, _w, _x, _y, _z, _A;
    const s = {};
    const fontSize = parseFontSize(pick(m, "fontSize"));
    s.width = parseDimension(m.width, true);
    s.height = parseDimension(m.height, false);
    s.widthFactor = percentFactor(m.width);
    s.heightFactor = percentFactor(m.height);
    s.aspectRatio = parseAspectRatio(pick(m, "aspectRatio"));
    s.minWidth = parseDimension(pick(m, "minWidth"), true);
    s.maxWidth = parseDimension(pick(m, "maxWidth"), true);
    s.minHeight = parseDimension(pick(m, "minHeight"), false);
    s.maxHeight = parseDimension(pick(m, "maxHeight"), false);
    if (s.maxWidth == null && /^\s*none\s*$/i.test((_a = str(pick(m, "maxWidth"))) != null ? _a : "")) s.maxWidth = null;
    const pad = parseEdgeInsetsFor(m, "padding", fontSize);
    s.padding = pad.insets;
    s.paddingPercent = pad.percent;
    const mar = parseEdgeInsetsFor(m, "margin", fontSize);
    s.margin = mar.insets;
    s.marginPercent = mar.percent;
    s.marginAuto = mar.auto;
    s.alignment = parseAlignment(m.alignment);
    s.position = str(m.position);
    s.top = parseDimension(m.top, false);
    s.right = parseDimension(m.right, true);
    s.bottom = parseDimension(m.bottom, false);
    s.left = parseDimension(m.left, true);
    s.zIndex = parseDouble(pick(m, "zIndex"));
    s.display = (_c = (_b = str(m.display)) == null ? void 0 : _b.trim()) != null ? _c : null;
    s.flexDirection = str(pick(m, "flexDirection"));
    s.justifyContent = str(pick(m, "justifyContent"));
    s.alignItems = str(pick(m, "alignItems"));
    s.alignContent = str(pick(m, "alignContent"));
    s.alignSelf = str(pick(m, "alignSelf"));
    parseFlexShorthand(m, s);
    s.flexWrap = str(pick(m, "flexWrap"));
    const flow = str(pick(m, "flexFlow"));
    if (flow) {
      for (const token of flow.split(/\s+/)) {
        if (token.startsWith("row") || token.startsWith("column")) (_d = s.flexDirection) != null ? _d : s.flexDirection = token;
        else if (token.startsWith("wrap") || token === "nowrap") (_e = s.flexWrap) != null ? _e : s.flexWrap = token;
      }
    }
    s.order = parseInt2(m.order);
    const gap = str(m.gap);
    if (gap && gap.trim().includes(" ")) {
      const [rg, cg] = gap.trim().split(/\s+/);
      s.rowGap = parseDouble(rg, fontSize);
      s.columnGap = parseDouble(cg, fontSize);
      s.gap = s.columnGap;
    } else {
      s.gap = parseDouble(m.gap, fontSize);
      s.rowGap = parseDouble(pick(m, "rowGap"), fontSize);
      s.columnGap = parseDouble(pick(m, "columnGap"), fontSize);
    }
    s.overflow = parseOverflow(m.overflow);
    s.overflowX = parseOverflow(pick(m, "overflowX"));
    s.overflowY = parseOverflow(pick(m, "overflowY"));
    s.boxSizing = str(pick(m, "boxSizing"));
    s.gridTemplateColumns = str(pick(m, "gridTemplateColumns"));
    s.gridTemplateRows = str(pick(m, "gridTemplateRows"));
    s.gridTemplateAreas = str(pick(m, "gridTemplateAreas"));
    s.gridAutoColumns = str(pick(m, "gridAutoColumns"));
    s.gridAutoRows = str(pick(m, "gridAutoRows"));
    s.gridAutoFlow = str(pick(m, "gridAutoFlow"));
    s.gridColumnGap = parseDouble(
      (_g = (_f = pick(m, "gridColumnGap")) != null ? _f : pick(m, "columnGap")) != null ? _g : s.columnGap != null ? s.columnGap : void 0,
      fontSize
    );
    s.gridRowGap = parseDouble((_i = (_h = pick(m, "gridRowGap")) != null ? _h : pick(m, "rowGap")) != null ? _i : s.rowGap != null ? s.rowGap : void 0, fontSize);
    s.gridGap = parseDouble(pick(m, "gridGap"), fontSize);
    s.gridColumn = str(pick(m, "gridColumn"));
    s.gridRow = str(pick(m, "gridRow"));
    s.gridArea = str(pick(m, "gridArea"));
    s.justifyItems = str(pick(m, "justifyItems"));
    s.justifySelf = str(pick(m, "justifySelf"));
    const background = m.background;
    const bgLayers = typeof background === "string" ? parseBackgroundShorthand(background) : null;
    s.backgroundColor = (_k = (_j = parseColor(pick(m, "backgroundColor"))) != null ? _j : bgLayers == null ? void 0 : bgLayers.color) != null ? _k : null;
    const bgImage = str(pick(m, "backgroundImage"));
    s.backgroundImage = bgImage && !isGradientValue(bgImage) ? extractUrl(bgImage) : (_l = bgLayers == null ? void 0 : bgLayers.image) != null ? _l : null;
    s.backgroundSize = parseBoxFit(pick(m, "backgroundSize"));
    s.backgroundSizePx = parseBackgroundSizePx(pick(m, "backgroundSize"));
    s.backgroundPosition = parseAlignment(pick(m, "backgroundPosition"));
    s.backgroundRepeat = str(pick(m, "backgroundRepeat"));
    const gradients = [];
    const explicit = parseGradient(m.gradient);
    if (explicit) gradients.push(explicit);
    if (bgImage && isGradientValue(bgImage)) gradients.push(...parseGradientLayers(bgImage));
    if (bgLayers) gradients.push(...bgLayers.gradients);
    s.gradient = (_m = gradients[0]) != null ? _m : null;
    s.gradientLayers = gradients.length > 1 ? gradients.slice(1) : null;
    s.gradientColors = parseColorList(pick(m, "gradientColors"));
    s.gradientStops = parseNumberList(pick(m, "gradientStops"));
    s.borderColor = parseColor(pick(m, "borderColor"));
    s.borderWidth = parseDouble(pick(m, "borderWidth"), fontSize);
    s.borderStyle = str(pick(m, "borderStyle"));
    s.border = parseBorder(m, s, fontSize);
    const radius = parseBorderRadius(m, fontSize);
    s.borderRadius = radius.px;
    s.borderRadiusPercent = radius.percent;
    s.outlineColor = parseColor(pick(m, "outlineColor"));
    s.outlineWidth = parseDouble(pick(m, "outlineWidth"), fontSize);
    s.outlineStyle = str(pick(m, "outlineStyle"));
    s.outlineOffset = parseDouble(pick(m, "outlineOffset"), fontSize);
    const outline = str(m.outline);
    if (outline) {
      const side2 = parseBorderSideString(outline, fontSize);
      if (side2) {
        (_n = s.outlineColor) != null ? _n : s.outlineColor = side2.color;
        (_o = s.outlineWidth) != null ? _o : s.outlineWidth = side2.width;
        (_p = s.outlineStyle) != null ? _p : s.outlineStyle = side2.style;
      }
    }
    s.color = parseColor(m.color);
    s.fontSize = fontSize;
    s.fontWeight = parseFontWeight(pick(m, "fontWeight"));
    s.fontStyle = parseFontStyle(pick(m, "fontStyle"));
    s.fontFamily = str(pick(m, "fontFamily"));
    parseFontShorthand(m.font, s);
    s.letterSpacing = parseDouble(pick(m, "letterSpacing"), fontSize != null ? fontSize : 16);
    s.wordSpacing = parseDouble(pick(m, "wordSpacing"), fontSize != null ? fontSize : 16);
    parseLineHeight(pick(m, "lineHeight"), s);
    s.textAlign = parseTextAlign(pick(m, "textAlign"));
    const deco = parseTextDecoration((_q = pick(m, "textDecoration")) != null ? _q : pick(m, "textDecorationLine"));
    s.textDecoration = deco.decoration;
    s.textDecorationColor = (_r = parseColor(pick(m, "textDecorationColor"))) != null ? _r : deco.color;
    s.textDecorationStyle = (_s = str(pick(m, "textDecorationStyle"))) != null ? _s : deco.style;
    s.textDecorationThickness = parseDouble(pick(m, "textDecorationThickness"));
    s.textOverflow = parseTextOverflow(pick(m, "textOverflow"));
    s.textTransform = str(pick(m, "textTransform"));
    s.whiteSpace = str(pick(m, "whiteSpace"));
    const collapse = str(pick(m, "borderCollapse"));
    s.borderCollapse = collapse === "collapse" || collapse === "separate" ? collapse : null;
    s.borderSpacing = CSSParser.parseDouble(pick(m, "borderSpacing"));
    s.verticalAlign = str(pick(m, "verticalAlign"));
    s.writingMode = str(pick(m, "writingMode"));
    s.wordBreak = str(pick(m, "wordBreak"));
    s.lineClamp = parseInt2((_u = (_t = pick(m, "lineClamp")) != null ? _t : pick(m, "WebkitLineClamp")) != null ? _u : m["-webkit-line-clamp"]);
    s.boxShadow = parseBoxShadow(pick(m, "boxShadow"));
    s.textShadow = parseTextShadow(pick(m, "textShadow"));
    s.transform = parseTransform(m.transform);
    s.rotate = parseAngleDegrees(m.rotate);
    const scaleRaw = m.scale;
    if (typeof scaleRaw === "string" && scaleRaw.trim().includes(" ")) {
      const [sx, sy] = scaleRaw.trim().split(/\s+/).map((t) => parseFloat(t));
      s.scaleX = Number.isFinite(sx) ? sx : null;
      s.scaleY = Number.isFinite(sy) ? sy : null;
    } else {
      s.scale = parseDouble(scaleRaw);
    }
    (_v = s.scaleX) != null ? _v : s.scaleX = parseDouble(pick(m, "scaleX"));
    (_w = s.scaleY) != null ? _w : s.scaleY = parseDouble(pick(m, "scaleY"));
    s.translate = (_x = parseOffset(m.translate)) != null ? _x : parseTranslateString(m.translate);
    s.transformOrigin = (_y = parseAlignment(pick(m, "transformOrigin"))) != null ? _y : parseOriginString(pick(m, "transformOrigin"));
    s.opacity = parseDouble(m.opacity);
    s.visible = typeof m.visible === "boolean" ? m.visible : null;
    s.visibility = str(m.visibility);
    s.filter = parseFilter(m.filter);
    s.backdropFilter = parseFilter(pick(m, "backdropFilter"));
    s.mixBlendMode = str(pick(m, "mixBlendMode"));
    s.cursor = str(m.cursor);
    s.pointerEvents = str(pick(m, "pointerEvents"));
    s.userSelect = str(pick(m, "userSelect"));
    s.touchAction = str(pick(m, "touchAction"));
    s.objectFit = parseBoxFit(pick(m, "objectFit"));
    s.objectPosition = parseAlignment(pick(m, "objectPosition"));
    s.clipBehavior = str(pick(m, "clipBehavior"));
    const shape = (_z = str(m.shape)) == null ? void 0 : _z.toLowerCase();
    s.shape = shape === "circle" ? "circle" : shape === "rectangle" ? "rectangle" : null;
    s.transitionDuration = parseDuration(pick(m, "transitionDuration"));
    s.transitionCurve = normalizeCurve((_A = pick(m, "transitionCurve")) != null ? _A : pick(m, "transitionTimingFunction"));
    s.transitionProperty = str(pick(m, "transitionProperty"));
    s.transitionDelay = parseDuration(pick(m, "transitionDelay"));
    const transition2 = str(m.transition);
    if (transition2) parseTransitionShorthand(transition2, s);
    s.animationName = str(pick(m, "animationName"));
    s.animationDuration = parseDuration(pick(m, "animationDuration"));
    s.animationTimingFunction = str(pick(m, "animationTimingFunction"));
    s.animationDelay = parseDuration(pick(m, "animationDelay"));
    s.animationIterationCount = parseInt2(pick(m, "animationIterationCount"));
    s.animationDirection = str(pick(m, "animationDirection"));
    s.animationFillMode = str(pick(m, "animationFillMode"));
    s.animationPlayState = str(pick(m, "animationPlayState"));
    const animation = str(m.animation);
    if (animation) parseAnimationShorthand(animation, s);
    s.animateOnBuild = asBool(pick(m, "animateOnBuild"));
    s.staggerDelay = parseDuration(pick(m, "staggerDelay"));
    s.staggerChildren = parseInt2(pick(m, "staggerChildren"));
    s.animationFrom = parseDouble(pick(m, "animationFrom"));
    s.animationTo = parseDouble(pick(m, "animationTo"));
    s.slideBegin = parseOffset(pick(m, "slideBegin"));
    s.slideEnd = parseOffset(pick(m, "slideEnd"));
    s.scaleBegin = parseDouble(pick(m, "scaleBegin"));
    s.scaleEnd = parseDouble(pick(m, "scaleEnd"));
    s.rotationBegin = parseDouble(pick(m, "rotationBegin"));
    s.rotationEnd = parseDouble(pick(m, "rotationEnd"));
    s.fadeBegin = parseDouble(pick(m, "fadeBegin"));
    s.fadeEnd = parseDouble(pick(m, "fadeEnd"));
    s.colorBegin = parseColor(pick(m, "colorBegin"));
    s.colorEnd = parseColor(pick(m, "colorEnd"));
    s.paddingBegin = parseEdgeInsets(pick(m, "paddingBegin"));
    s.paddingEnd = parseEdgeInsets(pick(m, "paddingEnd"));
    s.alignmentBegin = parseAlignment(pick(m, "alignmentBegin"));
    s.alignmentEnd = parseAlignment(pick(m, "alignmentEnd"));
    s.shimmerBaseColor = parseColor(pick(m, "shimmerBaseColor"));
    s.shimmerHighlightColor = parseColor(pick(m, "shimmerHighlightColor"));
    s.animationAutoReverse = asBool(pick(m, "animationAutoReverse"));
    s.animationRepeat = asBool(pick(m, "animationRepeat"));
    s.keyframes = parseKeyframes(m.keyframes);
    for (const key of Object.keys(s)) {
      if (s[key] == null) delete s[key];
    }
    return s;
  }
  function asBool(v) {
    if (typeof v === "boolean") return v;
    if (v === "true") return true;
    if (v === "false") return false;
    return null;
  }
  function parseDouble(value, emBase) {
    if (value == null) return null;
    if (typeof value === "number") return Number.isFinite(value) ? value : null;
    if (typeof value === "boolean") return null;
    const raw = String(stripImportant(value)).trim();
    if (raw === "") return null;
    const lower = raw.toLowerCase();
    if (lower.endsWith("rem")) {
      const n2 = parseFloat(lower);
      return Number.isFinite(n2) ? n2 * cssEnvironment().rootFontSize : null;
    }
    if (lower.endsWith("em") && !lower.endsWith("rem")) {
      const n2 = parseFloat(lower);
      return Number.isFinite(n2) ? n2 * (emBase != null ? emBase : cssEnvironment().rootFontSize) : null;
    }
    if (/^-?[\d.]+(vw|vh|vmin|vmax)$/.test(lower)) return resolveLength(lower, true);
    const n = parseFloat(raw.replace(/[^0-9.\-eE+]/g, ""));
    if (!Number.isFinite(n)) {
      const fallback = Number.parseFloat(raw.replace(/[^0-9.\-]/g, ""));
      return Number.isFinite(fallback) ? fallback : null;
    }
    return n;
  }
  function parseInt2(value) {
    if (value == null) return null;
    if (typeof value === "number") return Math.trunc(value);
    if (typeof value === "string") {
      const t = value.trim().toLowerCase();
      if (t === "infinite") return -1;
      const n = Number.parseInt(t, 10);
      return Number.isFinite(n) ? n : null;
    }
    return null;
  }
  function parseFontSize(value) {
    if (value == null) return null;
    if (typeof value === "string") {
      const t = value.trim().toLowerCase();
      const keywords = {
        "xx-small": 9,
        "x-small": 10,
        small: 13,
        medium: 16,
        large: 18,
        "x-large": 24,
        "xx-large": 32,
        "xxx-large": 48
      };
      if (t in keywords) return keywords[t];
      if (t.endsWith("%")) {
        const n = parseFloat(t);
        return Number.isFinite(n) ? n / 100 * cssEnvironment().rootFontSize : null;
      }
    }
    return parseDouble(value);
  }
  function percentFactor(value) {
    if (typeof value !== "string") return null;
    const raw = String(stripImportant(value)).trim();
    if (!raw.endsWith("%")) return null;
    const n = parseFloat(raw.substring(0, raw.length - 1));
    return Number.isFinite(n) ? n / 100 : null;
  }
  function parseDimension(value, isWidth) {
    if (value == null) return null;
    if (typeof value === "number") return Number.isFinite(value) ? value : null;
    if (typeof value !== "string") return null;
    const raw = String(stripImportant(value)).trim();
    if (raw === "" || raw === "auto" || raw === "none" || raw === "fit-content" || raw === "max-content" || raw === "min-content") {
      return null;
    }
    if (raw.includes("calc(")) return evalCalc(raw, isWidth);
    if (/^(min|max|clamp)\(/.test(raw)) return evalMathFn(raw, isWidth);
    return resolveLength(raw, isWidth);
  }
  function resolveLength(raw, isWidth) {
    const t = raw.trim().toLowerCase();
    if (t === "") return null;
    if (t.startsWith("env(")) return resolveEnv(t, isWidth);
    if (t.startsWith("var(")) return null;
    if (t.includes("*") || t.includes("/") || t.includes("(")) return null;
    const n = parseFloat(t.replace(/[^0-9.\-eE+]/g, ""));
    if (!Number.isFinite(n)) return null;
    const env2 = cssEnvironment();
    const w2 = env2.viewportWidth;
    const h = env2.viewportHeight;
    if (t.endsWith("vmin")) return n / 100 * Math.min(w2, h);
    if (t.endsWith("vmax")) return n / 100 * Math.max(w2, h);
    if (t.endsWith("vw")) return n / 100 * w2;
    if (t.endsWith("vh") || t.endsWith("dvh") || t.endsWith("svh") || t.endsWith("lvh")) return n / 100 * h;
    if (t.endsWith("%")) return n / 100 * (isWidth ? w2 : h);
    if (t.endsWith("rem")) return n * env2.rootFontSize;
    if (t.endsWith("em")) return n * env2.rootFontSize;
    if (t.endsWith("pt")) return n * 4 / 3;
    return n;
  }
  function evalCalc(raw, isWidth) {
    var _a;
    const m = /^calc\(([\s\S]*)\)$/.exec(raw.trim());
    const body = (_a = m == null ? void 0 : m[1]) == null ? void 0 : _a.trim();
    if (!body) return null;
    return evalSum(body, isWidth);
  }
  function evalSum(body, isWidth) {
    let sum = 0;
    let sign = 1;
    let start = 0;
    let depth = 0;
    for (let i = 0; i < body.length; i++) {
      const c = body[i];
      if (c === "(") depth++;
      else if (c === ")") depth--;
      else if (depth === 0 && (c === "+" || c === "-") && i > 0 && body[i - 1] === " " && body[i + 1] === " ") {
        const v = evalProduct(body.substring(start, i).trim(), isWidth);
        if (v == null) return null;
        sum += sign * v;
        sign = c === "+" ? 1 : -1;
        start = i + 1;
      }
    }
    const last = evalProduct(body.substring(start).trim(), isWidth);
    if (last == null) return null;
    return sum + sign * last;
  }
  function evalProduct(term, isWidth) {
    const mul = /^(.+?)\s*([*/])\s*(.+)$/.exec(term);
    if (mul && !term.startsWith("env(") && !term.startsWith("calc(")) {
      const left = evalAtom(mul[1].trim(), isWidth);
      const right = evalAtom(mul[3].trim(), isWidth);
      if (left == null || right == null) return null;
      return mul[2] === "*" ? left * right : right === 0 ? null : left / right;
    }
    return evalAtom(term, isWidth);
  }
  function evalAtom(atom, isWidth) {
    const t = atom.trim();
    if (t.startsWith("(") && t.endsWith(")")) return evalSum(t.substring(1, t.length - 1).trim(), isWidth);
    if (t.startsWith("calc(")) return evalCalc(t, isWidth);
    if (/^(min|max|clamp)\(/.test(t)) return evalMathFn(t, isWidth);
    return resolveLength(t, isWidth);
  }
  function evalMathFn(raw, isWidth) {
    const m = /^(min|max|clamp)\(([\s\S]*)\)$/.exec(raw.trim());
    if (!m) return null;
    const args = splitTopLevel(m[2], ",").map((a) => evalSum(a.trim(), isWidth));
    if (args.some((a) => a == null)) return null;
    const nums = args;
    if (m[1] === "min") return Math.min(...nums);
    if (m[1] === "max") return Math.max(...nums);
    if (nums.length !== 3) return null;
    return Math.min(Math.max(nums[1], nums[0]), nums[2]);
  }
  function resolveEnv(raw, isWidth) {
    var _a;
    const m = /^env\(\s*([a-z-]+)\s*(?:,\s*([^)]+))?\)$/.exec(raw.trim());
    if (!m) return null;
    const insets = cssEnvironment().safeArea;
    switch (m[1]) {
      case "safe-area-inset-top":
        return insets.top;
      case "safe-area-inset-right":
        return insets.right;
      case "safe-area-inset-bottom":
        return insets.bottom;
      case "safe-area-inset-left":
        return insets.left;
    }
    return m[2] != null ? (_a = resolveLength(m[2].trim(), isWidth)) != null ? _a : 0 : 0;
  }
  function parseAspectRatio(value) {
    if (typeof value === "number") return value > 0 ? value : null;
    if (typeof value !== "string") return null;
    const raw = value.trim().toLowerCase();
    if (raw === "" || raw === "auto") return null;
    const parts = raw.split("/");
    if (parts.length === 2) {
      const w2 = parseFloat(parts[0]);
      const h = parseFloat(parts[1]);
      return Number.isFinite(w2) && Number.isFinite(h) && h !== 0 ? w2 / h : null;
    }
    const v = parseFloat(raw);
    return Number.isFinite(v) && v > 0 ? v : null;
  }
  function parseFlexShorthand(m, s) {
    var _a, _b, _c, _d, _e, _f;
    const flex = m.flex;
    s.flexGrow = parseDouble(pick(m, "flexGrow"));
    s.flexShrink = parseDouble(pick(m, "flexShrink"));
    s.flexBasis = str(pick(m, "flexBasis"));
    if (flex == null) return;
    if (typeof flex === "number") {
      s.flex = flex;
      return;
    }
    const t = String(flex).trim().toLowerCase();
    if (t === "none") {
      (_a = s.flexShrink) != null ? _a : s.flexShrink = 0;
      return;
    }
    if (t === "auto") {
      s.flex = 1;
      (_b = s.flexBasis) != null ? _b : s.flexBasis = "auto";
      return;
    }
    const parts = t.split(/\s+/);
    const grow = parseFloat(parts[0]);
    if (Number.isFinite(grow)) {
      s.flex = grow;
      if (parts.length > 1) {
        const shrink = parseFloat(parts[1]);
        if (Number.isFinite(shrink)) (_c = s.flexShrink) != null ? _c : s.flexShrink = shrink;
        else (_d = s.flexBasis) != null ? _d : s.flexBasis = parts[1];
      }
      if (parts.length > 2) (_e = s.flexBasis) != null ? _e : s.flexBasis = parts[2];
    } else {
      (_f = s.flexBasis) != null ? _f : s.flexBasis = parts[0];
    }
  }
  function expandFour(parts) {
    if (parts.length === 1) return [parts[0], parts[0], parts[0], parts[0]];
    if (parts.length === 2) return [parts[0], parts[1], parts[0], parts[1]];
    if (parts.length === 3) return [parts[0], parts[1], parts[2], parts[1]];
    return [parts[0], parts[1], parts[2], parts[3]];
  }
  function parseEdgeInsets(value, emBase) {
    var _a, _b, _c, _d;
    if (value == null) return null;
    if (typeof value === "object" && !Array.isArray(value)) {
      return {
        top: (_a = parseDouble(value.top, emBase)) != null ? _a : 0,
        right: (_b = parseDouble(value.right, emBase)) != null ? _b : 0,
        bottom: (_c = parseDouble(value.bottom, emBase)) != null ? _c : 0,
        left: (_d = parseDouble(value.left, emBase)) != null ? _d : 0
      };
    }
    if (Array.isArray(value)) {
      const nums = value.map((v) => {
        var _a2;
        return (_a2 = parseDouble(v, emBase)) != null ? _a2 : 0;
      });
      if (nums.length === 0) return null;
      const [t, r, b, l] = expandFour(nums);
      return { top: t, right: r, bottom: b, left: l };
    }
    if (typeof value === "number" || typeof value === "string") {
      const parts = String(stripImportant(value)).trim().split(/\s+/).filter((p) => p !== "");
      if (parts.length === 0 || parts.length > 4) return null;
      const nums = parts.map((p) => {
        var _a2;
        return p === "auto" ? 0 : (_a2 = parseLengthToken(p, emBase)) != null ? _a2 : 0;
      });
      const [t, r, b, l] = expandFour(nums);
      return { top: t, right: r, bottom: b, left: l };
    }
    return null;
  }
  function parseLengthToken(token, emBase) {
    const t = token.trim().toLowerCase();
    if (t.endsWith("%")) return null;
    if (/vw$|vh$|vmin$|vmax$|^calc\(|^env\(/.test(t)) return parseDimension(t, true);
    return parseDouble(t, emBase);
  }
  function parseEdgeInsetsFor(m, base, emBase) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j, _k;
    const percent = {};
    const auto = { top: false, right: false, bottom: false, left: false };
    let any = false;
    const values = { top: null, right: null, bottom: null, left: null };
    const shorthandRaw = m[base];
    if (shorthandRaw != null) {
      if (typeof shorthandRaw === "object") {
        const e = parseEdgeInsets(shorthandRaw, emBase);
        if (e) {
          Object.assign(values, e);
          any = true;
        }
      } else {
        const parts = String(stripImportant(shorthandRaw)).trim().split(/\s+/).filter((p) => p !== "");
        if (parts.length > 0 && parts.length <= 4) {
          const four = expandFour(parts);
          ["top", "right", "bottom", "left"].forEach((side2, i) => applyInsetToken(four[i], side2, values, percent, auto, emBase));
          any = true;
        }
      }
    }
    const cap = base.charAt(0).toUpperCase() + base.substring(1);
    for (const side2 of ["top", "right", "bottom", "left"]) {
      const sideCap = side2.charAt(0).toUpperCase() + side2.substring(1);
      const raw = (_a = m[`${base}${sideCap}`]) != null ? _a : m[`${base}-${side2}`];
      if (raw != null) {
        applyInsetToken(String(stripImportant(raw)), side2, values, percent, auto, emBase);
        any = true;
      }
    }
    const x = (_c = (_b = m[`${base}X`]) != null ? _b : m[`${base}Inline`]) != null ? _c : m[`${base}-inline`];
    const y = (_e = (_d = m[`${base}Y`]) != null ? _d : m[`${base}Block`]) != null ? _e : m[`${base}-block`];
    if (x != null) {
      const parts = String(x).trim().split(/\s+/);
      applyInsetToken(parts[0], "left", values, percent, auto, emBase, true);
      applyInsetToken((_f = parts[1]) != null ? _f : parts[0], "right", values, percent, auto, emBase, true);
      any = true;
    }
    if (y != null) {
      const parts = String(y).trim().split(/\s+/);
      applyInsetToken(parts[0], "top", values, percent, auto, emBase, true);
      applyInsetToken((_g = parts[1]) != null ? _g : parts[0], "bottom", values, percent, auto, emBase, true);
      any = true;
    }
    if (!any) return { insets: null, percent: null, auto: null };
    return {
      insets: { top: (_h = values.top) != null ? _h : 0, right: (_i = values.right) != null ? _i : 0, bottom: (_j = values.bottom) != null ? _j : 0, left: (_k = values.left) != null ? _k : 0 },
      percent: Object.keys(percent).length ? percent : null,
      auto: auto.top || auto.right || auto.bottom || auto.left ? auto : null
    };
  }
  function applyInsetToken(token, side2, values, percent, auto, emBase, onlyIfUnset = false) {
    var _a;
    if (onlyIfUnset && values[side2] != null) return;
    const t = String(token).trim().toLowerCase();
    if (t === "auto") {
      auto[side2] = true;
      values[side2] = 0;
      delete percent[side2];
      return;
    }
    auto[side2] = false;
    if (t.endsWith("%")) {
      const n = parseFloat(t);
      if (Number.isFinite(n)) {
        percent[side2] = { pct: n };
        values[side2] = 0;
      }
      return;
    }
    delete percent[side2];
    values[side2] = (_a = parseLengthToken(t, emBase)) != null ? _a : 0;
  }
  var alignmentMap = {
    center: Align.center,
    topleft: Align.topLeft,
    "top-left": Align.topLeft,
    topcenter: Align.topCenter,
    "top-center": Align.topCenter,
    topright: Align.topRight,
    "top-right": Align.topRight,
    centerleft: Align.centerLeft,
    "center-left": Align.centerLeft,
    centerright: Align.centerRight,
    "center-right": Align.centerRight,
    bottomleft: Align.bottomLeft,
    "bottom-left": Align.bottomLeft,
    bottomcenter: Align.bottomCenter,
    "bottom-center": Align.bottomCenter,
    bottomright: Align.bottomRight,
    "bottom-right": Align.bottomRight
  };
  function parseAlignment(value) {
    var _a, _b;
    if (value == null) return null;
    if (typeof value === "string") {
      const key = value.trim().toLowerCase();
      const direct = alignmentMap[key];
      if (direct) return direct;
      return parsePositionKeywords(key);
    }
    if (typeof value === "object") {
      return { x: (_a = parseDouble(value.x)) != null ? _a : 0, y: (_b = parseDouble(value.y)) != null ? _b : 0 };
    }
    return null;
  }
  function parsePositionKeywords(key) {
    const tokens = key.split(/\s+/).filter((t) => t !== "");
    if (tokens.length === 0 || tokens.length > 2) return null;
    let x = null;
    let y = null;
    const unresolved = [];
    for (const t of tokens) {
      if (t === "left") x = -1;
      else if (t === "right") x = 1;
      else if (t === "top") y = -1;
      else if (t === "bottom") y = 1;
      else if (t.endsWith("%")) {
        const n = parseFloat(t);
        if (!Number.isFinite(n)) return null;
        const v = n / 50 - 1;
        if (x == null) x = v;
        else y = v;
      } else if (t === "center") unresolved.push(t);
      else return null;
    }
    for (const _ of unresolved) {
      if (x == null) x = 0;
      else if (y == null) y = 0;
    }
    if (x == null && y == null) return null;
    return { x: x != null ? x : 0, y: y != null ? y : 0 };
  }
  function parseOriginString(value) {
    if (typeof value !== "string") return null;
    return parsePositionKeywords(value.trim().toLowerCase());
  }
  function parseOffset(value) {
    var _a, _b, _c, _d, _e, _f;
    if (value == null) return null;
    if (Array.isArray(value) && value.length === 2) {
      return { dx: (_a = parseDouble(value[0])) != null ? _a : 0, dy: (_b = parseDouble(value[1])) != null ? _b : 0 };
    }
    if (typeof value === "object" && !Array.isArray(value)) {
      return { dx: (_d = parseDouble((_c = value.x) != null ? _c : value.dx)) != null ? _d : 0, dy: (_f = parseDouble((_e = value.y) != null ? _e : value.dy)) != null ? _f : 0 };
    }
    return null;
  }
  function parseTranslateString(value) {
    var _a;
    if (typeof value !== "string") return null;
    const parts = value.trim().split(/\s+/);
    const dx = parseDouble(parts[0]);
    if (dx == null) return null;
    return { dx, dy: (_a = parseDouble(parts[1])) != null ? _a : 0 };
  }
  var fontWeightMap = {
    thin: 100,
    hairline: 100,
    extralight: 200,
    "extra-light": 200,
    ultralight: 200,
    light: 300,
    normal: 400,
    regular: 400,
    medium: 500,
    semibold: 600,
    "semi-bold": 600,
    demibold: 600,
    bold: 700,
    extrabold: 800,
    "extra-bold": 800,
    black: 900,
    heavy: 900,
    bolder: 700,
    lighter: 300
  };
  function parseFontWeight(value) {
    if (value == null) return null;
    if (typeof value === "number") {
      const idx = Math.min(9, Math.max(1, Math.trunc(value / 100)));
      return idx * 100;
    }
    const t = String(value).trim().toLowerCase();
    if (fontWeightMap[t]) return fontWeightMap[t];
    const n = Number.parseInt(t.startsWith("w") ? t.substring(1) : t, 10);
    if (Number.isFinite(n)) {
      const idx = Math.min(9, Math.max(1, Math.trunc(n / 100)));
      return idx * 100;
    }
    return null;
  }
  function parseFontStyle(value) {
    if (typeof value !== "string") return null;
    const t = value.trim().toLowerCase();
    if (t === "italic" || t === "oblique") return "italic";
    if (t === "normal") return "normal";
    return null;
  }
  function parseFontShorthand(value, s) {
    var _a, _b, _c, _d;
    if (typeof value !== "string") return;
    const m = /^\s*((?:(?:italic|oblique|normal|bold|bolder|lighter|small-caps|\d{3})\s+)*)([\d.]+(?:px|em|rem|pt|%)?)(?:\s*\/\s*([\d.]+(?:px|em|rem|%)?))?\s+(.+)$/i.exec(
      value
    );
    if (!m) return;
    for (const token of m[1].trim().split(/\s+/).filter((t) => t)) {
      const lower = token.toLowerCase();
      if (lower === "italic" || lower === "oblique") (_a = s.fontStyle) != null ? _a : s.fontStyle = "italic";
      else {
        const w2 = parseFontWeight(lower);
        if (w2 && lower !== "normal") (_b = s.fontWeight) != null ? _b : s.fontWeight = w2;
      }
    }
    (_c = s.fontSize) != null ? _c : s.fontSize = parseFontSize(m[2]);
    if (m[3]) parseLineHeight(m[3], s);
    (_d = s.fontFamily) != null ? _d : s.fontFamily = m[4].trim();
  }
  function parseLineHeight(value, s) {
    if (value == null) return;
    if (typeof value === "number") {
      s.lineHeight = value;
      return;
    }
    const t = String(stripImportant(value)).trim().toLowerCase();
    if (t === "normal") return;
    if (/^[\d.]+$/.test(t)) {
      s.lineHeight = parseFloat(t);
      return;
    }
    if (t.endsWith("%")) {
      s.lineHeight = parseFloat(t) / 100;
      return;
    }
    if (t.endsWith("em") && !t.endsWith("rem")) {
      s.lineHeight = parseFloat(t);
      return;
    }
    const px = parseDouble(t);
    if (px != null) s.lineHeightPx = px;
  }
  var textAlignMap = {
    left: "left",
    right: "right",
    center: "center",
    justify: "justify",
    start: "start",
    end: "end"
  };
  function parseTextAlign(value) {
    var _a;
    if (typeof value !== "string") return null;
    return (_a = textAlignMap[value.trim().toLowerCase()]) != null ? _a : null;
  }
  function parseTextDecoration(value) {
    var _a;
    if (typeof value !== "string") return { decoration: null, color: null, style: null };
    const deco = { underline: false, overline: false, lineThrough: false };
    let color = null;
    let style = null;
    let known = false;
    for (const token of splitTopLevel(value.trim().toLowerCase(), " ").filter((t) => t)) {
      if (token === "underline") deco.underline = true, known = true;
      else if (token === "overline") deco.overline = true, known = true;
      else if (token === "line-through" || token === "linethrough") deco.lineThrough = true, known = true;
      else if (token === "none") known = true;
      else if (["solid", "double", "dotted", "dashed", "wavy"].includes(token)) style = token;
      else color = (_a = parseColor(token)) != null ? _a : color;
    }
    return { decoration: known ? deco : null, color, style };
  }
  var textOverflowMap = { ellipsis: "ellipsis", clip: "clip", fade: "fade", visible: "visible" };
  function parseTextOverflow(value) {
    var _a;
    if (typeof value !== "string") return null;
    return (_a = textOverflowMap[value.trim().toLowerCase()]) != null ? _a : null;
  }
  var overflowMap = { visible: "visible", hidden: "hidden", clip: "clip", auto: "scroll", scroll: "scroll", overlay: "scroll" };
  function parseOverflow(value) {
    var _a;
    if (typeof value !== "string") return null;
    const token = value.trim().toLowerCase().split(/\s+/)[0];
    return (_a = overflowMap[token]) != null ? _a : null;
  }
  var boxFitMap = {
    fill: "fill",
    contain: "contain",
    cover: "cover",
    fitwidth: "fitWidth",
    "fit-width": "fitWidth",
    fitheight: "fitHeight",
    "fit-height": "fitHeight",
    none: "none",
    scaledown: "scaleDown",
    "scale-down": "scaleDown",
    "100% 100%": "fill"
  };
  function parseBoxFit(value) {
    var _a;
    if (typeof value !== "string") return null;
    return (_a = boxFitMap[value.trim().toLowerCase()]) != null ? _a : null;
  }
  function parseBackgroundSizePx(value) {
    if (typeof value !== "string") return null;
    const t = value.trim().toLowerCase();
    if (boxFitMap[t]) return null;
    const parts = t.split(/\s+/);
    const w2 = parts[0] === "auto" ? null : parseDouble(parts[0]);
    const h = parts.length > 1 ? parts[1] === "auto" ? null : parseDouble(parts[1]) : null;
    if (w2 == null && h == null) return null;
    return { width: w2, height: h };
  }
  var borderStyles = ["solid", "dashed", "dotted", "double", "none"];
  function parseBorderSideMap(value, emBase) {
    var _a, _b, _c;
    if (value == null || typeof value !== "object") return null;
    const style = String((_a = value.style) != null ? _a : "solid").toLowerCase();
    return {
      color: (_b = parseColor(value.color)) != null ? _b : 4278190080,
      width: (_c = parseDouble(value.width, emBase)) != null ? _c : 1,
      style: borderStyles.includes(style) ? style : "solid"
    };
  }
  function parseBorderSideString(value, emBase) {
    var _a;
    const t = String(stripImportant(value)).trim();
    if (t === "") return null;
    if (/^(none|0|hidden)$/i.test(t)) return { width: 0, color: 4278190080, style: "none" };
    let width = null;
    let style = null;
    let color = null;
    for (const token of splitTopLevel(t, " ").filter((p) => p)) {
      const lower = token.toLowerCase();
      if (borderStyles.includes(lower) || lower === "groove" || lower === "ridge" || lower === "inset" || lower === "outset") {
        style = borderStyles.includes(lower) ? lower : "solid";
      } else if (lower === "thin") width = 1;
      else if (lower === "medium") width = 3;
      else if (lower === "thick") width = 5;
      else if (/^-?[\d.]/.test(lower)) width = parseDouble(lower, emBase);
      else color = (_a = parseColor(token)) != null ? _a : color;
    }
    return { width: width != null ? width : 3, style: style != null ? style : "none", color: color != null ? color : 4278190080 };
  }
  function parseBorderSideAny(value, emBase) {
    if (value == null) return null;
    if (typeof value === "object") return parseBorderSideMap(value, emBase);
    return parseBorderSideString(String(value), emBase);
  }
  function parseBorder(m, s, emBase) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j, _k, _l;
    const none2 = { width: 0, color: 4278190080, style: "none" };
    let top = null, right = null, bottom = null, left = null;
    let any = false;
    const all = m.border;
    if (all != null) {
      if (typeof all === "object" && !Array.isArray(all)) {
        if ("top" in all || "right" in all || "bottom" in all || "left" in all) {
          top = (_a = parseBorderSideMap(all.top, emBase)) != null ? _a : none2;
          right = (_b = parseBorderSideMap(all.right, emBase)) != null ? _b : none2;
          bottom = (_c = parseBorderSideMap(all.bottom, emBase)) != null ? _c : none2;
          left = (_d = parseBorderSideMap(all.left, emBase)) != null ? _d : none2;
        } else {
          const side2 = parseBorderSideMap(all, emBase);
          top = right = bottom = left = side2;
        }
        any = true;
      } else {
        const side2 = parseBorderSideString(String(all), emBase);
        if (side2) {
          top = right = bottom = left = side2;
          any = true;
        }
      }
    }
    for (const sideName of ["top", "right", "bottom", "left"]) {
      const cap = sideName.charAt(0).toUpperCase() + sideName.substring(1);
      const raw = (_e = m[`border${cap}`]) != null ? _e : m[`border-${sideName}`];
      let side2 = raw != null ? parseBorderSideAny(raw, emBase) : null;
      const width = parseDouble((_f = m[`border${cap}Width`]) != null ? _f : m[`border-${sideName}-width`], emBase);
      const color = parseColor((_g = m[`border${cap}Color`]) != null ? _g : m[`border-${sideName}-color`]);
      const styleRaw2 = (_h = m[`border${cap}Style`]) != null ? _h : m[`border-${sideName}-style`];
      if (width != null || color != null || styleRaw2 != null) {
        const base = side2 != null ? side2 : sideName === "top" ? top : sideName === "right" ? right : sideName === "bottom" ? bottom : left;
        side2 = {
          width: (_i = width != null ? width : base == null ? void 0 : base.width) != null ? _i : 1,
          color: (_k = (_j = color != null ? color : base == null ? void 0 : base.color) != null ? _j : s.borderColor) != null ? _k : 4278190080,
          style: styleRaw2 ? String(styleRaw2).toLowerCase() : (_l = base == null ? void 0 : base.style) != null ? _l : "solid"
        };
      }
      if (side2) {
        any = true;
        if (sideName === "top") top = side2;
        else if (sideName === "right") right = side2;
        else if (sideName === "bottom") bottom = side2;
        else left = side2;
      }
    }
    const widthRaw = pick(m, "borderWidth");
    const colorRaw = pick(m, "borderColor");
    const styleRaw = pick(m, "borderStyle");
    const multi = (v) => typeof v === "string" && splitTopLevel(v.trim(), " ").filter((p) => p).length > 1;
    if (any && (widthRaw != null || colorRaw != null || styleRaw != null)) {
      const widths = widthRaw != null ? expandFour(splitTopLevel(String(widthRaw).trim(), " ").filter((p) => p).map((w2) => {
        var _a2;
        return (_a2 = parseDouble(w2, emBase)) != null ? _a2 : 0;
      })) : null;
      const colors = colorRaw != null ? expandFour(splitTopLevel(String(colorRaw).trim(), " ").filter((p) => p).map((c) => {
        var _a2;
        return (_a2 = parseColor(c)) != null ? _a2 : 4278190080;
      })) : null;
      const styles = styleRaw != null ? expandFour(String(styleRaw).trim().split(/\s+/).map((x) => x.toLowerCase())) : null;
      const sides = [top, right, bottom, left].map(
        (side2, i) => {
          var _a2, _b2, _c2;
          return side2 ? {
            width: (_a2 = widths == null ? void 0 : widths[i]) != null ? _a2 : side2.width,
            color: (_b2 = colors == null ? void 0 : colors[i]) != null ? _b2 : side2.color,
            style: (_c2 = styles == null ? void 0 : styles[i]) != null ? _c2 : side2.style
          } : side2;
        }
      );
      [top, right, bottom, left] = sides;
    } else if (!any && (multi(widthRaw) || multi(colorRaw) || multi(styleRaw)) && (widthRaw != null || styleRaw != null)) {
      const widths = expandFour(splitTopLevel(String(widthRaw != null ? widthRaw : "1").trim(), " ").filter((p) => p).map((w2) => {
        var _a2;
        return (_a2 = parseDouble(w2, emBase)) != null ? _a2 : 0;
      }));
      const colors = expandFour(splitTopLevel(String(colorRaw != null ? colorRaw : "#000").trim(), " ").filter((p) => p).map((c) => {
        var _a2;
        return (_a2 = parseColor(c)) != null ? _a2 : 4278190080;
      }));
      const styles = expandFour(String(styleRaw != null ? styleRaw : "solid").trim().split(/\s+/).map((x) => x.toLowerCase()));
      [top, right, bottom, left] = [0, 1, 2, 3].map((i) => ({ width: widths[i], color: colors[i], style: styles[i] }));
      any = true;
    }
    if (!any) return null;
    return { top: top != null ? top : none2, right: right != null ? right : none2, bottom: bottom != null ? bottom : none2, left: left != null ? left : none2 };
  }
  function parseBorderRadius(m, emBase) {
    var _a;
    const px = { topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0 };
    const pct = { topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0 };
    let anyPx = false;
    let anyPct = false;
    const corners = ["topLeft", "topRight", "bottomRight", "bottomLeft"];
    const assign = (corner, token) => {
      if (token == null) return;
      if (typeof token === "string" && token.trim().endsWith("%")) {
        const n2 = parseFloat(token);
        if (Number.isFinite(n2)) {
          pct[corner] = n2;
          px[corner] = 0;
          anyPct = true;
        }
        return;
      }
      const n = parseDouble(token, emBase);
      if (n != null) {
        px[corner] = n;
        pct[corner] = 0;
        anyPx = true;
      }
    };
    const all = pick(m, "borderRadius");
    if (all != null) {
      if (typeof all === "object" && !Array.isArray(all)) {
        for (const c of corners) assign(c, (_a = all[c]) != null ? _a : all[c.replace(/[A-Z]/g, (x) => "-" + x.toLowerCase())]);
      } else if (typeof all === "number") {
        for (const c of corners) assign(c, all);
      } else {
        const horizontal = String(stripImportant(all)).split("/")[0].trim().split(/\s+/).filter((p) => p);
        if (horizontal.length) {
          const four = expandFour(horizontal);
          corners.forEach((c, i) => assign(c, four[i]));
        }
      }
    }
    const longhand = {
      topLeft: "borderTopLeftRadius",
      topRight: "borderTopRightRadius",
      bottomRight: "borderBottomRightRadius",
      bottomLeft: "borderBottomLeftRadius"
    };
    for (const c of corners) assign(c, pick(m, longhand[c]));
    return { px: anyPx ? px : null, percent: anyPct ? pct : null };
  }
  function parseBoxShadow(value) {
    if (value == null) return null;
    if (Array.isArray(value)) {
      return value.map((shadow) => {
        var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j, _k;
        if (shadow && typeof shadow === "object") {
          const offset = (_e = parseOffset(shadow.offset)) != null ? _e : { dx: (_b = parseDouble((_a = shadow.dx) != null ? _a : shadow.x)) != null ? _b : 0, dy: (_d = parseDouble((_c = shadow.dy) != null ? _c : shadow.y)) != null ? _d : 0 };
          return {
            color: (_f = parseColor(shadow.color)) != null ? _f : 1107296256,
            dx: offset.dx,
            dy: offset.dy,
            blur: (_h = parseDouble((_g = shadow.blurRadius) != null ? _g : shadow.blur)) != null ? _h : 0,
            spread: (_j = parseDouble((_i = shadow.spreadRadius) != null ? _i : shadow.spread)) != null ? _j : 0,
            inset: shadow.inset === true
          };
        }
        if (typeof shadow === "string") return (_k = parseShadowString(shadow)) != null ? _k : zeroShadow();
        return zeroShadow();
      });
    }
    if (typeof value === "object") return parseBoxShadow([value]);
    if (typeof value === "string") {
      const t = value.trim();
      if (t === "" || t === "none") return null;
      const out = splitTopLevel(t, ",").map((s) => parseShadowString(s)).filter((s) => s != null);
      return out.length ? out : null;
    }
    return null;
  }
  function zeroShadow() {
    return { color: 4278190080, dx: 0, dy: 0, blur: 0, spread: 0 };
  }
  function parseShadowString(raw) {
    var _a, _b, _c, _d;
    const tokens = splitTopLevel(raw.trim(), " ").filter((p) => p);
    const lengths = [];
    let color = null;
    let inset = false;
    for (const token of tokens) {
      if (token.toLowerCase() === "inset") inset = true;
      else if (/^-?[\d.]/.test(token)) lengths.push((_a = parseDouble(token)) != null ? _a : 0);
      else color = (_b = parseColor(token)) != null ? _b : color;
    }
    if (lengths.length < 2) return null;
    return {
      dx: lengths[0],
      dy: lengths[1],
      blur: (_c = lengths[2]) != null ? _c : 0,
      spread: (_d = lengths[3]) != null ? _d : 0,
      color: color != null ? color : 4278190080,
      inset
    };
  }
  function parseTextShadow(value) {
    var _a;
    if (value == null) return null;
    if (typeof value === "string" || typeof value === "object" && !Array.isArray(value)) {
      const boxes = parseBoxShadow(value);
      return (_a = boxes == null ? void 0 : boxes.map((b) => ({ color: b.color, dx: b.dx, dy: b.dy, blur: b.blur }))) != null ? _a : null;
    }
    if (Array.isArray(value)) {
      return value.map((shadow) => {
        var _a2, _b, _c, _d;
        if (shadow && typeof shadow === "object") {
          const offset = (_a2 = parseOffset(shadow.offset)) != null ? _a2 : { dx: 0, dy: 0 };
          return {
            color: (_b = parseColor(shadow.color)) != null ? _b : 1107296256,
            dx: offset.dx,
            dy: offset.dy,
            blur: (_d = parseDouble((_c = shadow.blurRadius) != null ? _c : shadow.blur)) != null ? _d : 0
          };
        }
        const parsed = typeof shadow === "string" ? parseShadowString(shadow) : null;
        return parsed ? { color: parsed.color, dx: parsed.dx, dy: parsed.dy, blur: parsed.blur } : { color: 4278190080, dx: 0, dy: 0, blur: 0 };
      });
    }
    return null;
  }
  function parseAngleDegrees(value) {
    if (value == null) return null;
    if (typeof value === "number") return value;
    const t = String(value).trim().toLowerCase();
    const n = parseFloat(t);
    if (!Number.isFinite(n)) return null;
    if (t.endsWith("rad")) return n * 180 / Math.PI;
    if (t.endsWith("turn")) return n * 360;
    if (t.endsWith("grad")) return n * 0.9;
    return n;
  }
  function angleRadians(token) {
    var _a;
    return ((_a = parseAngleDegrees(token)) != null ? _a : 0) * Math.PI / 180;
  }
  function parseTransform(value) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j, _k, _l, _m, _n, _o;
    if (value == null) return null;
    if (Array.isArray(value) && value.length === 16) return value.map((e) => Number(e));
    if (typeof value !== "string") return null;
    const t = value.trim();
    if (t === "" || t === "none") return null;
    const re = /([a-zA-Z0-9]+)\(([^)]*)\)/g;
    let matrix = identity();
    let match;
    let any = false;
    while ((match = re.exec(t)) !== null) {
      const fn = match[1].toLowerCase();
      const args = match[2].split(/[\s,]+/).filter((a) => a !== "");
      let step = null;
      switch (fn) {
        case "translate":
          step = translation((_a = parseDouble(args[0])) != null ? _a : 0, (_b = parseDouble(args[1])) != null ? _b : 0, 0);
          break;
        case "translatex":
          step = translation((_c = parseDouble(args[0])) != null ? _c : 0, 0, 0);
          break;
        case "translatey":
          step = translation(0, (_d = parseDouble(args[0])) != null ? _d : 0, 0);
          break;
        case "translate3d":
          step = translation((_e = parseDouble(args[0])) != null ? _e : 0, (_f = parseDouble(args[1])) != null ? _f : 0, (_g = parseDouble(args[2])) != null ? _g : 0);
          break;
        case "rotate":
        case "rotatez":
          step = rotationZ(angleRadians((_h = args[0]) != null ? _h : "0"));
          break;
        case "scale": {
          const sx = parseFloat((_i = args[0]) != null ? _i : "1");
          const sy = args.length > 1 ? parseFloat(args[1]) : sx;
          step = scaling(sx, sy, 1);
          break;
        }
        case "scalex":
          step = scaling(parseFloat((_j = args[0]) != null ? _j : "1"), 1, 1);
          break;
        case "scaley":
          step = scaling(1, parseFloat((_k = args[0]) != null ? _k : "1"), 1);
          break;
        case "skew":
          step = skew(angleRadians((_l = args[0]) != null ? _l : "0"), angleRadians((_m = args[1]) != null ? _m : "0"));
          break;
        case "skewx":
          step = skew(angleRadians((_n = args[0]) != null ? _n : "0"), 0);
          break;
        case "skewy":
          step = skew(0, angleRadians((_o = args[0]) != null ? _o : "0"));
          break;
        case "matrix":
        case "matrix3d":
          step = fromCssMatrix(args.map((a) => parseFloat(a)));
          break;
        default:
          step = null;
      }
      if (step) {
        matrix = multiply(matrix, step);
        any = true;
      }
    }
    return any ? matrix : null;
  }
  function isGradientValue(value) {
    return typeof value === "string" && value.includes("gradient(");
  }
  function extractUrl(value) {
    const m = /url\(\s*(['"]?)(.*?)\1\s*\)/.exec(value);
    if (m) return m[2];
    const t = value.trim();
    return t === "" || t === "none" ? null : t;
  }
  function splitTopLevel(input, separator) {
    const out = [];
    let depth = 0;
    let quote = null;
    let start = 0;
    for (let i = 0; i < input.length; i++) {
      const ch = input[i];
      if (quote) {
        if (ch === quote) quote = null;
        continue;
      }
      if (ch === '"' || ch === "'") quote = ch;
      else if (ch === "(") depth++;
      else if (ch === ")") depth = Math.max(0, depth - 1);
      else if (depth === 0 && (separator === " " ? /\s/.test(ch) : ch === separator)) {
        out.push(input.substring(start, i));
        start = i + 1;
      }
    }
    out.push(input.substring(start));
    return separator === " " ? out.filter((s) => s.trim() !== "") : out;
  }
  function angleForSideKeyword(side2) {
    switch (side2.replace(/\s+/g, " ").trim()) {
      case "top":
        return 0;
      case "top right":
      case "right top":
        return 45;
      case "right":
        return 90;
      case "bottom right":
      case "right bottom":
        return 135;
      case "bottom":
        return 180;
      case "bottom left":
      case "left bottom":
        return 225;
      case "left":
        return 270;
      case "top left":
      case "left top":
        return 315;
      default:
        return 180;
    }
  }
  function beginEndForAngle(deg) {
    const a = (deg % 360 + 360) % 360 * (Math.PI / 180);
    const dx = Math.sin(a);
    const dy = -Math.cos(a);
    const scale = 1 / Math.max(Math.abs(dx), Math.abs(dy));
    const ex = dx * scale;
    const ey = dy * scale;
    const round2 = (v) => Math.abs(v) < 1e-9 ? 0 : v;
    return [
      { x: round2(-ex), y: round2(-ey) },
      { x: round2(ex), y: round2(ey) }
    ];
  }
  function parseCssGradientString(raw) {
    var _a, _b;
    const s = raw.trim();
    const lower = s.toLowerCase();
    const kind = lower.includes("radial-gradient") ? "radial" : lower.includes("conic-gradient") ? "sweep" : "linear";
    const repeat = lower.startsWith("repeating-");
    const open = s.indexOf("(");
    const close = s.lastIndexOf(")");
    if (open < 0 || close <= open) return null;
    const parts = splitTopLevel(s.substring(open + 1, close), ",");
    if (parts.length === 0) return null;
    let angleDeg = null;
    let center2;
    let startAngle = 0;
    let colorParts = parts;
    const first2 = parts[0].trim().toLowerCase();
    if (kind === "linear") {
      if (/^-?[\d.]+(deg|rad|turn|grad)$/.test(first2)) {
        angleDeg = parseAngleDegrees(first2);
        colorParts = parts.slice(1);
      } else if (first2.startsWith("to ")) {
        angleDeg = angleForSideKeyword(first2.substring(3));
        colorParts = parts.slice(1);
      }
    } else if (kind === "radial") {
      if (!looksLikeColorStop(first2)) {
        const at = first2.indexOf("at ");
        if (at >= 0) center2 = (_a = parsePositionKeywords(first2.substring(at + 3).trim())) != null ? _a : void 0;
        colorParts = parts.slice(1);
      }
    } else {
      if (!looksLikeColorStop(first2)) {
        const from = /from\s+(-?[\d.]+\w*)/.exec(first2);
        if (from) startAngle = angleRadians(from[1]);
        const at = first2.indexOf("at ");
        if (at >= 0) center2 = (_b = parsePositionKeywords(first2.substring(at + 3).trim())) != null ? _b : void 0;
        colorParts = parts.slice(1);
      }
    }
    const colors = [];
    const stops = [];
    for (const part of colorParts) {
      const t = part.trim();
      if (t === "") continue;
      const tokens = splitTopLevel(t, " ");
      const color = parseColor(tokens[0]);
      if (color == null) continue;
      const positions = tokens.slice(1).map((p) => parseStopPosition(p));
      if (positions.length === 0) {
        colors.push(color);
        stops.push(null);
      } else {
        for (const pos of positions) {
          colors.push(color);
          stops.push(pos);
        }
      }
    }
    if (colors.length === 0) return null;
    if (colors.length === 1) {
      colors.push(colors[0]);
      stops.push(null);
    }
    const resolvedStops = resolveStops(stops);
    if (kind === "radial") {
      return { kind, colors, stops: resolvedStops, center: center2 != null ? center2 : Align.center, radius: 0.5, repeat };
    }
    if (kind === "sweep") {
      return {
        kind,
        colors,
        stops: resolvedStops,
        center: center2 != null ? center2 : Align.center,
        startAngle: startAngle - Math.PI / 2,
        endAngle: startAngle - Math.PI / 2 + Math.PI * 2,
        repeat
      };
    }
    const [begin, end] = beginEndForAngle(angleDeg != null ? angleDeg : 180);
    return { kind, colors, stops: resolvedStops, begin, end, repeat };
  }
  function looksLikeColorStop(token) {
    return parseColor(splitTopLevel(token, " ")[0]) != null;
  }
  function parseStopPosition(token) {
    var _a;
    const t = token.trim();
    if (t.endsWith("%")) {
      const n = parseFloat(t);
      return Number.isFinite(n) ? Math.max(0, Math.min(1, n / 100)) : null;
    }
    if (/deg$|turn$/.test(t)) return ((_a = parseAngleDegrees(t)) != null ? _a : 0) / 360;
    return null;
  }
  function resolveStops(stops) {
    if (stops.every((s) => s == null)) return null;
    const out = stops.slice();
    if (out[0] == null) out[0] = 0;
    if (out[out.length - 1] == null) out[out.length - 1] = 1;
    let i = 0;
    while (i < out.length) {
      if (out[i] != null) {
        i++;
        continue;
      }
      const startIdx = i - 1;
      let endIdx = i;
      while (out[endIdx] == null) endIdx++;
      const a = out[startIdx];
      const b = out[endIdx];
      const span = endIdx - startIdx;
      for (let k = startIdx + 1; k < endIdx; k++) out[k] = a + (b - a) * (k - startIdx) / span;
      i = endIdx;
    }
    for (let k = 1; k < out.length; k++) if (out[k] < out[k - 1]) out[k] = out[k - 1];
    return out;
  }
  function parseGradientLayers(value) {
    return splitTopLevel(value, ",").map((layer) => layer.trim()).filter((layer) => isGradientValue(layer)).map((layer) => parseCssGradientString(layer)).filter((g) => g != null);
  }
  function parseGradient(value) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _i;
    if (value == null) return null;
    if (typeof value === "string") {
      const layers = parseGradientLayers(value);
      return (_a = layers[0]) != null ? _a : null;
    }
    if (typeof value === "object" && !Array.isArray(value)) {
      const type = String((_b = value.type) != null ? _b : "linear").toLowerCase();
      const colors = Array.isArray(value.colors) ? value.colors.map((c) => {
        var _a2;
        return (_a2 = parseColor(c)) != null ? _a2 : 0;
      }) : null;
      if (!colors || colors.length === 0) return null;
      const stops = parseNumberList(value.stops);
      if (type === "linear") {
        return {
          kind: "linear",
          colors,
          stops,
          begin: (_c = parseAlignment(value.begin)) != null ? _c : Align.topCenter,
          end: (_d = parseAlignment(value.end)) != null ? _d : Align.bottomCenter
        };
      }
      if (type === "radial") {
        return { kind: "radial", colors, stops, center: (_e = parseAlignment(value.center)) != null ? _e : Align.center, radius: (_f = parseDouble(value.radius)) != null ? _f : 0.5 };
      }
      if (type === "sweep") {
        return {
          kind: "sweep",
          colors,
          stops,
          center: (_g = parseAlignment(value.center)) != null ? _g : Align.center,
          startAngle: (_h = parseDouble(value.startAngle)) != null ? _h : 0,
          endAngle: (_i = parseDouble(value.endAngle)) != null ? _i : Math.PI * 2
        };
      }
    }
    return null;
  }
  function parseBackgroundShorthand(value) {
    const layers = splitTopLevel(value.trim(), ",");
    const gradients = [];
    let color = null;
    let image = null;
    for (const layer of layers) {
      const t = layer.trim();
      if (isGradientValue(t)) {
        const g = parseCssGradientString(t.substring(t.search(/(repeating-)?(linear|radial|conic)-gradient\(/)));
        if (g) gradients.push(g);
        continue;
      }
      if (t.includes("url(")) {
        image = extractUrl(t);
      }
      for (const token of splitTopLevel(t, " ")) {
        const c = parseColor(token);
        if (c != null) color = c;
      }
    }
    return { color, gradients, image };
  }
  function parseColorList(value) {
    if (!Array.isArray(value)) return null;
    const out = value.map((c) => parseColor(c)).filter((c) => c != null);
    return out.length ? out : null;
  }
  function parseNumberList(value) {
    if (!Array.isArray(value)) return null;
    const out = value.map((c) => parseDouble(c)).filter((c) => c != null);
    return out.length ? out : null;
  }
  function parseFilter(value) {
    var _a, _b;
    if (typeof value !== "string") return null;
    const t = value.trim();
    if (t === "" || t === "none") return null;
    const f = {};
    const re = /([a-z-]+)\(([^()]*(?:\([^()]*\)[^()]*)*)\)/gi;
    let m;
    const amount = (arg, def) => {
      const a = arg.trim();
      if (a === "") return def;
      if (a.endsWith("%")) return parseFloat(a) / 100;
      return parseFloat(a);
    };
    while ((m = re.exec(t)) !== null) {
      const name = m[1].toLowerCase();
      const arg = m[2];
      switch (name) {
        case "blur":
          f.blur = (_a = parseDouble(arg)) != null ? _a : 0;
          break;
        case "brightness":
          f.brightness = amount(arg, 1);
          break;
        case "contrast":
          f.contrast = amount(arg, 1);
          break;
        case "grayscale":
          f.grayscale = amount(arg, 1);
          break;
        case "hue-rotate":
          f.hueRotate = (_b = parseAngleDegrees(arg)) != null ? _b : 0;
          break;
        case "invert":
          f.invert = amount(arg, 1);
          break;
        case "saturate":
          f.saturate = amount(arg, 1);
          break;
        case "sepia":
          f.sepia = amount(arg, 1);
          break;
        case "opacity":
          f.opacity = amount(arg, 1);
          break;
        case "drop-shadow": {
          const s = parseShadowString(arg);
          if (s) f.dropShadow = { color: s.color, dx: s.dx, dy: s.dy, blur: s.blur };
          break;
        }
      }
    }
    return Object.keys(f).length ? f : null;
  }
  function parseDuration(value) {
    if (value == null) return null;
    if (typeof value === "number") return Math.trunc(value);
    if (typeof value !== "string") return null;
    const t = value.trim().toLowerCase();
    if (t.endsWith("ms")) {
      const n2 = parseFloat(t);
      return Number.isFinite(n2) ? Math.trunc(n2) : null;
    }
    if (t.endsWith("s")) {
      const n2 = parseFloat(t);
      return Number.isFinite(n2) ? Math.trunc(n2 * 1e3) : null;
    }
    const n = Number.parseInt(t.replace(/[^0-9]/g, ""), 10);
    return Number.isFinite(n) ? n : null;
  }
  function normalizeCurve(value) {
    if (typeof value !== "string") return null;
    const t = value.trim();
    if (t === "") return null;
    if (t.startsWith("cubic-bezier(") || t.startsWith("steps(")) return t.toLowerCase();
    return t.toLowerCase().replace(/[-_\s]/g, "");
  }
  function parseTransitionShorthand(value, s) {
    var _a, _b, _c, _d, _e;
    const first2 = splitTopLevel(value, ",")[0];
    const tokens = splitTopLevel(first2, " ");
    const times = [];
    for (const token of tokens) {
      if (/^[\d.]+m?s$/.test(token)) times.push((_a = parseDuration(token)) != null ? _a : 0);
      else if (/^(ease|linear|step|cubic-bezier|steps)/.test(token)) (_b = s.transitionCurve) != null ? _b : s.transitionCurve = normalizeCurve(token);
      else (_c = s.transitionProperty) != null ? _c : s.transitionProperty = token;
    }
    if (times.length > 0) (_d = s.transitionDuration) != null ? _d : s.transitionDuration = times[0];
    if (times.length > 1) (_e = s.transitionDelay) != null ? _e : s.transitionDelay = times[1];
  }
  function parseAnimationShorthand(value, s) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j;
    const first2 = splitTopLevel(value, ",")[0];
    const tokens = splitTopLevel(first2, " ");
    const times = [];
    for (const token of tokens) {
      const lower = token.toLowerCase();
      if (/^[\d.]+m?s$/.test(lower)) times.push((_a = parseDuration(lower)) != null ? _a : 0);
      else if (/^(ease|linear|step|cubic-bezier|steps)/.test(lower)) (_b = s.animationTimingFunction) != null ? _b : s.animationTimingFunction = lower;
      else if (lower === "infinite") (_c = s.animationIterationCount) != null ? _c : s.animationIterationCount = -1;
      else if (/^\d+$/.test(lower)) (_d = s.animationIterationCount) != null ? _d : s.animationIterationCount = Number.parseInt(lower, 10);
      else if (["normal", "reverse", "alternate", "alternate-reverse"].includes(lower)) (_e = s.animationDirection) != null ? _e : s.animationDirection = lower;
      else if (["forwards", "backwards", "both"].includes(lower)) (_f = s.animationFillMode) != null ? _f : s.animationFillMode = lower;
      else if (["running", "paused"].includes(lower)) (_g = s.animationPlayState) != null ? _g : s.animationPlayState = lower;
      else if (lower !== "none") (_h = s.animationName) != null ? _h : s.animationName = token;
    }
    if (times.length > 0) (_i = s.animationDuration) != null ? _i : s.animationDuration = times[0];
    if (times.length > 1) (_j = s.animationDelay) != null ? _j : s.animationDelay = times[1];
  }
  function parseKeyframes(value) {
    if (!Array.isArray(value)) return null;
    const out = [];
    for (const frame of value) {
      if (frame && typeof frame === "object" && !Array.isArray(frame)) {
        const offset = parseDouble(frame.offset);
        const styles = frame.styles;
        if (offset != null && styles && typeof styles === "object") out.push({ offset, styles });
        else out.push({ offset: offset != null ? offset : 0, styles: frame });
      }
    }
    return out.length ? out : null;
  }

  // core/src/css/stylesheet.ts
  var CSSRule = class {
    constructor(selector, styles, order) {
      this.selector = selector;
      this.styles = styles;
      this.order = order;
      this.selectors = parseSelectorList(selector);
    }
    toCSS() {
      const body = Object.entries(this.styles).map(([k, v]) => `  ${k}: ${v};`).join("\n");
      return `${this.selector} {
${body}
}
`;
    }
  };
  var ruleCounter = 0;
  var CSSStylesheet = class {
    constructor() {
      this.rules = [];
      this.keyframes = /* @__PURE__ */ new Map();
      /** Fast path: rules whose every selector is a single simple tag/class/id. */
      this.simple = /* @__PURE__ */ new Map();
    }
    addRule(selector, styles) {
      const rule = new CSSRule(selector.trim(), styles, ruleCounter++);
      this.removeRule(rule.selector);
      this.rules.push(rule);
      this.simple.clear();
    }
    removeRule(selector) {
      const before = this.rules.length;
      this.rules = this.rules.filter((r) => r.selector !== selector);
      if (this.rules.length !== before) this.simple.clear();
    }
    get allRules() {
      return this.rules;
    }
    getStyle(selector) {
      var _a;
      return (_a = this.rules.find((r) => r.selector === selector)) == null ? void 0 : _a.styles;
    }
    addKeyframeAnimation(name, frames) {
      this.keyframes.set(name, frames);
    }
    getKeyframes(name) {
      return this.keyframes.get(name);
    }
    get keyframeNames() {
      return [...this.keyframes.keys()];
    }
    /** Root custom properties (`:root { --x: … }`). */
    variables() {
      const out = {};
      for (const rule of this.rules) {
        if (rule.selectors.some((s) => s.parts.length === 1 && s.parts[0].compound.root)) {
          for (const [k, v] of Object.entries(rule.styles)) if (k.startsWith("--")) out[k] = v;
        }
      }
      return out;
    }
    /**
     * The raw cascaded map for an element: matched rules in specificity then
     * source order (tag < class < id, as in Flutter), then [inlineStyles].
     */
    getComputedStyleMap(element, ancestors = [], inlineStyles) {
      const merged = {};
      for (const rule of this.matching(element, ancestors)) Object.assign(merged, rule.styles);
      if (inlineStyles) Object.assign(merged, inlineStyles);
      return merged;
    }
    matching(element, ancestors) {
      const matched = [];
      for (const rule of this.rules) {
        let best = -1;
        for (const sel of rule.selectors) {
          if (sel.specificity > best && matchesComplex(sel, element, ancestors)) best = sel.specificity;
        }
        if (best >= 0) matched.push({ rule, specificity: best });
      }
      matched.sort((a, b) => a.specificity - b.specificity || a.rule.order - b.rule.order);
      return matched.map((m) => m.rule);
    }
    clear() {
      this.rules = [];
      this.keyframes.clear();
      this.simple.clear();
    }
    toCSS() {
      return this.rules.map((r) => r.toCSS()).join("\n");
    }
    /** Parse CSS text into this stylesheet; returns the `@media` blocks found. */
    parseCSS(cssText) {
      return parseCssText(cssText, this);
    }
  };
  var MediaQuery = class {
    constructor(query, stylesheet) {
      this.query = query;
      this.stylesheet = stylesheet;
    }
    matches(width, height) {
      return mediaMatches(this.query, width, height);
    }
  };
  function mediaMatches(query, width, height, darkMode = false) {
    const alternatives = query.split(",").map((q) => q.trim()).filter((q) => q);
    if (alternatives.length === 0) return true;
    return alternatives.some((alt) => {
      let negate = false;
      let q = alt.toLowerCase();
      if (q.startsWith("not ")) {
        negate = true;
        q = q.substring(4);
      }
      q = q.replace(/^only\s+/, "");
      let ok = true;
      for (const m of q.matchAll(/(min|max)-(width|height):\s*([\d.]+)(px|em|rem)?/g)) {
        const isMin = m[1] === "min";
        const isWidth = m[2] === "width";
        let threshold = parseFloat(m[3]);
        if (m[4] === "em" || m[4] === "rem") threshold *= cssEnvironment().rootFontSize;
        const actual = isWidth ? width : height;
        if (isMin && actual < threshold) ok = false;
        if (!isMin && actual > threshold) ok = false;
      }
      const om = /orientation:\s*(portrait|landscape)/.exec(q);
      if (om && om[1] === "landscape" !== width >= height) ok = false;
      for (const m of q.matchAll(/(min|max)-aspect-ratio:\s*(\d+)\s*\/\s*(\d+)/g)) {
        const ratio = parseFloat(m[2]) / parseFloat(m[3]);
        const actual = height > 0 ? width / height : 0;
        if (m[1] === "min" && actual < ratio) ok = false;
        if (m[1] === "max" && actual > ratio) ok = false;
      }
      const scheme = /prefers-color-scheme:\s*(dark|light)/.exec(q);
      if (scheme && scheme[1] === "dark" !== darkMode) ok = false;
      if (/\bprint\b/.test(q) && !/\bscreen\b/.test(q)) ok = false;
      return negate ? !ok : ok;
    });
  }
  var StylesheetManager = class {
    constructor() {
      this.global = new CSSStylesheet();
      this.mediaQueries = [];
      /** Bumped on every change so render caches can invalidate. */
      this.version = 0;
      this.darkMode = false;
    }
    addMediaQuery(query, sheet) {
      this.mediaQueries = this.mediaQueries.filter((mq) => mq.query !== query);
      this.mediaQueries.push(new MediaQuery(query, sheet));
      this.version++;
    }
    touch() {
      this.version++;
    }
    keyframes(name) {
      const own = this.global.getKeyframes(name);
      if (own) return own;
      for (const mq of this.mediaQueries) {
        const frames = mq.stylesheet.getKeyframes(name);
        if (frames) return frames;
      }
      return void 0;
    }
    get hasRules() {
      return this.global.allRules.length > 0 || this.mediaQueries.length > 0;
    }
    getComputedStyleMap(element, options = {}) {
      var _a, _b, _c;
      const merged = {};
      const important = {};
      const mergeRaw = (raw) => {
        if (!raw) return;
        for (const [key, value] of Object.entries(raw)) {
          const stripped = stripImportant(value);
          merged[key] = stripped;
          if (isImportant(value)) important[key] = stripped;
        }
      };
      const ancestors = (_a = options.ancestors) != null ? _a : [];
      mergeRaw(this.global.getComputedStyleMap(element, ancestors));
      if (this.mediaQueries.length > 0) {
        const env2 = cssEnvironment();
        const w2 = (_b = options.screenWidth) != null ? _b : env2.viewportWidth;
        const h = (_c = options.screenHeight) != null ? _c : env2.viewportHeight;
        for (const mq of this.mediaQueries) {
          if (mediaMatches(mq.query, w2, h, this.darkMode)) mergeRaw(mq.stylesheet.getComputedStyleMap(element, ancestors));
        }
      }
      if (options.inlineStyles) mergeRaw(options.inlineStyles);
      Object.assign(merged, important);
      return this.substituteVariables(merged);
    }
    /** Replace `var(--name, fallback)` with root / element custom properties. */
    substituteVariables(map) {
      let needs = false;
      for (const v of Object.values(map)) {
        if (typeof v === "string" && v.includes("var(")) {
          needs = true;
          break;
        }
      }
      if (!needs) return map;
      const vars = __spreadValues({}, this.global.variables());
      for (const [k, v] of Object.entries(map)) if (k.startsWith("--")) vars[k] = v;
      const out = {};
      for (const [k, v] of Object.entries(map)) out[k] = typeof v === "string" ? resolveVars(v, vars, 0) : v;
      return out;
    }
    clear() {
      this.global.clear();
      this.mediaQueries = [];
      this.version++;
    }
    /** Load a JSON stylesheet (`{rules, mediaQueries, variables, keyframes}`) or CSS text. */
    load(json) {
      if (typeof json === "string") {
        const blocks = this.global.parseCSS(json);
        for (const block of blocks) this.addMediaQuery(block.query, block.sheet);
        this.version++;
        return;
      }
      const sheet = parseJsonStylesheet(json, (query, mq) => this.addMediaQuery(query, mq));
      for (const rule of sheet.allRules) this.global.addRule(rule.selector, rule.styles);
      for (const name of sheet.keyframeNames) this.global.addKeyframeAnimation(name, sheet.getKeyframes(name));
      if (typeof json.css === "string") this.load(json.css);
      this.version++;
    }
  };
  function resolveVars(value, vars, depth) {
    if (depth > 8 || !value.includes("var(")) return value;
    const replaced = value.replace(/var\(\s*(--[\w-]+)\s*(?:,\s*([^()]*(?:\([^()]*\)[^()]*)*))?\)/g, (_m, name, fallback) => {
      const v = vars[name];
      if (v != null) return String(v);
      return fallback != null ? fallback.trim() : "";
    });
    return resolveVars(replaced, vars, depth + 1);
  }
  function parseJsonStylesheet(json, onMedia) {
    const sheet = new CSSStylesheet();
    const rules = json.rules;
    if (Array.isArray(rules)) {
      const mediaGroups = /* @__PURE__ */ new Map();
      for (const rule of rules) {
        if (!rule || typeof rule !== "object") continue;
        const media = rule.media;
        if (typeof media === "string" && media.trim() !== "") {
          let group = mediaGroups.get(media);
          if (!group) mediaGroups.set(media, group = new CSSStylesheet());
          addJsonRule(rule, group);
        } else {
          addJsonRule(rule, sheet);
        }
      }
      for (const [query, group] of mediaGroups) onMedia(query, group);
    }
    const mediaQueries = json.mediaQueries;
    if (Array.isArray(mediaQueries)) {
      for (const mq of mediaQueries) {
        if (!mq || typeof mq.query !== "string") continue;
        const group = new CSSStylesheet();
        if (Array.isArray(mq.rules)) for (const r of mq.rules) addJsonRule(r, group);
        onMedia(mq.query, group);
      }
    }
    const variables = json.variables;
    if (variables && typeof variables === "object") {
      const vars = {};
      for (const [k, v] of Object.entries(variables)) vars[k.startsWith("--") ? k : `--${k}`] = v;
      sheet.addRule(":root", vars);
    }
    const keyframes = json.keyframes;
    if (Array.isArray(keyframes)) {
      for (const kf of keyframes) {
        if (!kf || typeof kf.name !== "string" || !Array.isArray(kf.frames)) continue;
        const frames = [];
        for (const f of kf.frames) {
          if (f && typeof f.offset === "number" && f.styles && typeof f.styles === "object") {
            frames.push({ offset: f.offset, styles: f.styles });
          }
        }
        sheet.addKeyframeAnimation(kf.name, frames);
      }
    }
    return sheet;
  }
  function addJsonRule(rule, sheet) {
    if (!rule || typeof rule.selector !== "string" || !rule.styles || typeof rule.styles !== "object") return;
    sheet.addRule(rule.selector, rule.styles);
  }
  function parseDeclarations(body) {
    const styles = {};
    for (const decl of splitTopLevel(body, ";")) {
      const idx = decl.indexOf(":");
      if (idx <= 0) continue;
      const key = decl.substring(0, idx).trim();
      let value = decl.substring(idx + 1).trim();
      if (key === "" || value === "") continue;
      if (value.startsWith('"') && value.endsWith('"') || value.startsWith("'") && value.endsWith("'")) {
        value = value.substring(1, value.length - 1);
      } else if (/^-?\d+(\.\d+)?(px)?$/.test(value)) {
        value = parseFloat(value);
      }
      styles[key] = value;
    }
    return styles;
  }
  function stripComments(css) {
    return css.replace(/\/\*[\s\S]*?\*\//g, "");
  }
  function blocksOf(css) {
    const out = [];
    let depth = 0;
    let preludeStart = 0;
    let bodyStart = -1;
    for (let i = 0; i < css.length; i++) {
      const ch = css[i];
      if (ch === "{") {
        if (depth === 0) bodyStart = i + 1;
        depth++;
      } else if (ch === "}") {
        depth--;
        if (depth === 0 && bodyStart >= 0) {
          out.push([css.substring(preludeStart, bodyStart - 1).trim(), css.substring(bodyStart, i)]);
          preludeStart = i + 1;
          bodyStart = -1;
        }
      } else if (ch === ";" && depth === 0) {
        preludeStart = i + 1;
      }
    }
    return out;
  }
  function parseCssText(css, sheet) {
    const media = [];
    for (const [prelude, body] of blocksOf(stripComments(css))) {
      if (prelude.startsWith("@media")) {
        const query = prelude.substring(6).trim();
        const inner = new CSSStylesheet();
        parseCssText(body, inner);
        media.push({ query, sheet: inner });
      } else if (prelude.startsWith("@keyframes") || prelude.startsWith("@-webkit-keyframes")) {
        const name = prelude.replace(/^@(-webkit-)?keyframes/, "").trim();
        const frames = [];
        for (const [sel, decls] of blocksOf(body)) {
          const styles = parseDeclarations(decls);
          for (const part of sel.split(",")) {
            const t = part.trim().toLowerCase();
            const offset = t === "from" ? 0 : t === "to" ? 1 : parseFloat(t) / 100;
            if (Number.isFinite(offset)) frames.push({ offset, styles });
          }
        }
        frames.sort((a, b) => a.offset - b.offset);
        sheet.addKeyframeAnimation(name, frames);
      } else if (prelude.startsWith("@supports") || prelude.startsWith("@layer")) {
        media.push(...parseCssText(body, sheet));
      } else if (!prelude.startsWith("@")) {
        sheet.addRule(prelude, parseDeclarations(body));
      }
    }
    return media;
  }
  function parseCompound(text2) {
    var _a;
    const c = { tag: null, id: null, classes: [], attrs: [], universal: false, root: false };
    let i = 0;
    const ident = () => {
      const m = /^-?[_a-zA-Z0-9 -￿-][_a-zA-Z0-9 -￿\\-]*/.exec(text2.substring(i));
      if (!m) return null;
      i += m[0].length;
      return m[0];
    };
    if (text2[0] === "*") {
      c.universal = true;
      i = 1;
    } else if (/[a-zA-Z]/.test((_a = text2[0]) != null ? _a : "")) {
      c.tag = ident();
    }
    while (i < text2.length) {
      const ch = text2[i];
      if (ch === ".") {
        i++;
        const name = ident();
        if (!name) return null;
        c.classes.push(name);
      } else if (ch === "#") {
        i++;
        const name = ident();
        if (!name) return null;
        c.id = name;
      } else if (ch === "[") {
        const end = text2.indexOf("]", i);
        if (end < 0) return null;
        const inner = text2.substring(i + 1, end);
        const eq2 = inner.indexOf("=");
        if (eq2 < 0) c.attrs.push({ name: inner.trim(), value: null });
        else c.attrs.push({ name: inner.substring(0, eq2).trim(), value: inner.substring(eq2 + 1).trim().replace(/^["']|["']$/g, "") });
        i = end + 1;
      } else if (ch === ":") {
        const m = /^::?([a-zA-Z-]+)(\([^)]*\))?/.exec(text2.substring(i));
        if (!m) return null;
        i += m[0].length;
        if (m[1] === "root") c.root = true;
        else if (!["first-child", "last-child"].includes(m[1])) return null;
      } else {
        return null;
      }
    }
    return c;
  }
  function parseComplex(text2) {
    const tokens = [];
    const combinators = [];
    const normalized2 = text2.replace(/\s*>\s*/g, ">").replace(/\s+/g, " ").trim();
    let current2 = "";
    for (const ch of normalized2) {
      if (ch === " " || ch === ">") {
        if (current2) tokens.push(current2);
        current2 = "";
        combinators.push(ch);
      } else {
        current2 += ch;
      }
    }
    if (current2) tokens.push(current2);
    if (tokens.length === 0 || combinators.length !== tokens.length - 1) return null;
    const compounds = tokens.map(parseCompound);
    if (compounds.some((c) => c == null)) return null;
    const parts = [];
    for (let k = compounds.length - 1; k >= 0; k--) {
      parts.push({ compound: compounds[k], combinator: k > 0 ? combinators[k - 1] : null });
    }
    let ids = 0, classes = 0, tags = 0;
    for (const c of compounds) {
      if (c.id) ids++;
      classes += c.classes.length + c.attrs.length + (c.root ? 1 : 0);
      if (c.tag) tags++;
    }
    return { parts, specificity: ids * 1e4 + classes * 100 + tags };
  }
  function parseSelectorList(selector) {
    return splitTopLevel(selector, ",").map((s) => s.trim()).filter((s) => s).map(parseComplex).filter((s) => s != null);
  }
  function matchesCompound(c, el) {
    var _a, _b;
    if (c.root) return el.tagName === ":root" || el.tagName === "html";
    if (c.tag && c.tag !== el.tagName && c.tag.toLowerCase() !== el.tagName.toLowerCase()) return false;
    if (c.id && c.id !== el.id) return false;
    if (c.classes.length) {
      const own = (_a = el.classes) != null ? _a : [];
      for (const cls of c.classes) if (!own.includes(cls)) return false;
    }
    for (const attr of c.attrs) {
      const v = (_b = el.attributes) == null ? void 0 : _b[attr.name];
      if (v === void 0) return false;
      if (attr.value != null && String(v) !== attr.value) return false;
    }
    return c.universal || c.tag != null || c.id != null || c.classes.length > 0 || c.attrs.length > 0;
  }
  function matchesComplex(sel, el, ancestors) {
    const [first2, ...rest] = sel.parts;
    if (!matchesCompound(first2.compound, el)) return false;
    let combinator = first2.combinator;
    let index = 0;
    for (const part of rest) {
      if (combinator === ">") {
        const parent = ancestors[index];
        if (!parent || !matchesCompound(part.compound, parent)) return false;
        index++;
      } else {
        let found = false;
        while (index < ancestors.length) {
          const candidate = ancestors[index++];
          if (matchesCompound(part.compound, candidate)) {
            found = true;
            break;
          }
        }
        if (!found) return false;
      }
      combinator = part.combinator;
    }
    return true;
  }

  // core/src/events/events.ts
  function eventKind(e) {
    if (e.key !== void 0) return "keyboard";
    if (e.velocity !== void 0 || e.focalPoint !== void 0 || e.scale !== void 0) return "gesture";
    if (e.position !== void 0) return "pointer";
    if ("value" in e) return "input";
    return "base";
  }
  function makeEvent(type, eventType, target, extra = {}) {
    return __spreadValues({
      type,
      eventType,
      target,
      currentTarget: target,
      timestamp: Date.now(),
      phase: "none",
      data: {}
    }, extra);
  }
  var EventTarget = class {
    constructor() {
      this.listeners = /* @__PURE__ */ new Map();
    }
    addEventListener(type, listener, options = {}) {
      var _a;
      const list2 = (_a = this.listeners.get(type)) != null ? _a : [];
      list2.push({ listener, capture: !!options.capture, once: !!options.once });
      this.listeners.set(type, list2);
    }
    removeEventListener(type, listener) {
      const list2 = this.listeners.get(type);
      if (!list2) return;
      const next = list2.filter((c) => c.listener !== listener);
      if (next.length) this.listeners.set(type, next);
      else this.listeners.delete(type);
    }
    removeAllEventListeners(type) {
      if (type) this.listeners.delete(type);
      else this.listeners.clear();
    }
    dispatchEvent(event) {
      const list2 = this.listeners.get(event.type);
      if (!list2 || list2.length === 0) return !event.defaultPrevented;
      const remove = [];
      for (const config of [...list2]) {
        if (config.capture && event.phase !== "capturing") continue;
        if (!config.capture && event.phase === "capturing") continue;
        try {
          config.listener(event);
        } catch (e) {
          console.warn("Error in event listener:", e);
        }
        if (config.once) remove.push(config);
        if (event.immediatePropagationStopped) break;
      }
      if (remove.length) this.listeners.set(event.type, list2.filter((c) => !remove.includes(c)));
      return !event.defaultPrevented;
    }
    hasEventListener(type) {
      var _a, _b;
      return ((_b = (_a = this.listeners.get(type)) == null ? void 0 : _a.length) != null ? _b : 0) > 0;
    }
    getListenerCount(type) {
      var _a, _b;
      if (type) return (_b = (_a = this.listeners.get(type)) == null ? void 0 : _a.length) != null ? _b : 0;
      let n = 0;
      for (const l of this.listeners.values()) n += l.length;
      return n;
    }
  };
  var EventBus = class extends EventTarget {
    broadcast(event) {
      this.dispatchEvent(event);
    }
    subscribe(type, listener) {
      this.addEventListener(type, listener);
    }
    unsubscribe(type, listener) {
      this.removeEventListener(type, listener);
    }
  };
  var EventDispatcher = class {
    constructor() {
      this.nodes = /* @__PURE__ */ new Map();
      this.parents = /* @__PURE__ */ new Map();
      this.bus = new EventBus();
      this.globalEventHandler = null;
      /** Host-side listeners attached to a node (`(event) => void` values in `events`). */
      this.nativeHandlers = /* @__PURE__ */ new Map();
    }
    registerNode(id2, node, parentId) {
      this.nodes.set(id2, node);
      this.parents.set(id2, parentId);
    }
    unregisterNode(id2) {
      this.nodes.delete(id2);
      this.parents.delete(id2);
    }
    getNode(id2) {
      return this.nodes.get(id2);
    }
    addNodeHandler(id2, type, listener) {
      let m = this.nativeHandlers.get(id2);
      if (!m) this.nativeHandlers.set(id2, m = /* @__PURE__ */ new Map());
      m.set(type, listener);
    }
    chain(elementId) {
      const out = [];
      const seen = /* @__PURE__ */ new Set();
      let current2 = elementId;
      while (current2 != null && !seen.has(current2)) {
        seen.add(current2);
        out.push(current2);
        current2 = this.parents.get(current2);
      }
      return out;
    }
    dispatchEvent(event, elementId) {
      var _a, _b, _c, _d, _e;
      const chain = this.chain(elementId);
      if (chain.length === 0) {
        (_a = this.globalEventHandler) == null ? void 0 : _a.call(this, event);
        return;
      }
      for (let i = chain.length - 1; i > 0; i--) {
        const node = this.nodes.get(chain[i]);
        if (!node) continue;
        const capturing = __spreadProps(__spreadValues({}, event), { currentTarget: chain[i], phase: "capturing" });
        this.dispatchToNode(chain[i], node, capturing);
        if (capturing.propagationStopped) {
          (_b = this.globalEventHandler) == null ? void 0 : _b.call(this, capturing);
          return;
        }
      }
      const targetNode = this.nodes.get(elementId);
      if (targetNode) {
        const atTarget = __spreadProps(__spreadValues({}, event), { currentTarget: elementId, phase: "atTarget" });
        this.dispatchToNode(elementId, targetNode, atTarget);
        if (atTarget.propagationStopped) {
          (_c = this.globalEventHandler) == null ? void 0 : _c.call(this, atTarget);
          return;
        }
        event = atTarget;
      }
      for (let i = 1; i < chain.length; i++) {
        const node = this.nodes.get(chain[i]);
        if (!node) continue;
        const bubbling = __spreadProps(__spreadValues({}, event), { currentTarget: chain[i], phase: "bubbling" });
        this.dispatchToNode(chain[i], node, bubbling);
        if (bubbling.propagationStopped) {
          (_d = this.globalEventHandler) == null ? void 0 : _d.call(this, bubbling);
          return;
        }
      }
      this.bus.broadcast(event);
      (_e = this.globalEventHandler) == null ? void 0 : _e.call(this, event);
    }
    /** Every node on the path that declares a handler for [event.type], nearest first. */
    handlersAlongPath(event, elementId) {
      var _a, _b;
      const out = [];
      for (const id2 of this.chain(elementId)) {
        const handler = (_b = (_a = this.nodes.get(id2)) == null ? void 0 : _a.events) == null ? void 0 : _b[event.type];
        if (handler != null) out.push({ nodeId: id2, handler });
      }
      return out;
    }
    dispatchToNode(id2, node, event) {
      var _a, _b;
      const native = (_a = this.nativeHandlers.get(id2)) == null ? void 0 : _a.get(event.type);
      if (native) {
        try {
          native(event);
        } catch (e) {
          console.warn("Error executing event handler:", e);
        }
      }
      const handler = (_b = node.events) == null ? void 0 : _b[event.type];
      if (typeof handler === "function") {
        try {
          handler(event);
        } catch (e) {
          console.warn("Error executing event handler:", e);
        }
      }
    }
    onGlobalEvent(listener) {
      this.globalEventHandler = listener;
    }
    onEventType(type, listener) {
      this.bus.addEventListener(type, listener);
    }
    // Convenience dispatchers (mirroring the Dart API).
    dispatchClick(id2, position) {
      this.dispatchEvent(makeEvent("click", "click", id2, position ? { position, localPosition: position } : {}), id2);
    }
    dispatchChange(id2, value) {
      this.dispatchEvent(makeEvent("change", "change", id2, { value }), id2);
    }
    dispatchInput(id2, value) {
      this.dispatchEvent(makeEvent("input", "input", id2, { value }), id2);
    }
    dispatchSubmit(id2, data = {}) {
      this.dispatchEvent(makeEvent("submit", "submit", id2, { data }), id2);
    }
    dispatchFocus(id2) {
      this.dispatchEvent(makeEvent("focus", "focus", id2), id2);
    }
    dispatchBlur(id2) {
      this.dispatchEvent(makeEvent("blur", "blur", id2), id2);
    }
    clear() {
      this.nodes.clear();
      this.parents.clear();
      this.nativeHandlers.clear();
    }
    getStats() {
      return { nodes: this.nodes.size, parents: this.parents.size };
    }
  };
  function eventToJson(event) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j, _k, _l, _m, _n, _o, _p, _q, _r, _s, _t, _u, _v, _w, _x;
    const base = {
      type: event.type,
      eventType: event.eventType,
      target: event.target,
      currentTarget: event.currentTarget,
      timestamp: new Date(event.timestamp).toISOString(),
      phase: event.phase,
      data: event.data
    };
    switch (eventKind(event)) {
      case "pointer":
        Object.assign(base, {
          position: { x: event.position.x, y: event.position.y },
          localPosition: { x: (_b = (_a = event.localPosition) == null ? void 0 : _a.x) != null ? _b : event.position.x, y: (_d = (_c = event.localPosition) == null ? void 0 : _c.y) != null ? _d : event.position.y },
          delta: { x: (_f = (_e = event.delta) == null ? void 0 : _e.x) != null ? _f : 0, y: (_h = (_g = event.delta) == null ? void 0 : _g.y) != null ? _h : 0 },
          buttons: (_i = event.buttons) != null ? _i : 0,
          pressure: (_j = event.pressure) != null ? _j : 1,
          distance: (_k = event.distance) != null ? _k : 0,
          pointerId: (_l = event.pointerId) != null ? _l : 0
        });
        break;
      case "keyboard":
        Object.assign(base, {
          key: event.key,
          keyCode: (_m = event.keyCode) != null ? _m : 0,
          altKey: !!event.altKey,
          ctrlKey: !!event.ctrlKey,
          shiftKey: !!event.shiftKey,
          metaKey: !!event.metaKey
        });
        break;
      case "input":
        Object.assign(base, { value: event.value, inputType: (_n = event.inputType) != null ? _n : null });
        break;
      case "gesture":
        Object.assign(base, {
          velocity: { x: (_p = (_o = event.velocity) == null ? void 0 : _o.x) != null ? _p : 0, y: (_r = (_q = event.velocity) == null ? void 0 : _q.y) != null ? _r : 0 },
          scale: (_s = event.scale) != null ? _s : 1,
          rotation: (_t = event.rotation) != null ? _t : 0,
          focalPoint: { x: (_v = (_u = event.focalPoint) == null ? void 0 : _u.x) != null ? _v : 0, y: (_x = (_w = event.focalPoint) == null ? void 0 : _w.y) != null ? _x : 0 }
        });
        break;
    }
    return base;
  }

  // core/src/godot/values.ts
  var OpKey = {
    create: "new",
    def: "def",
    self: "self",
    tree: "tree",
    singleton: "singleton",
    load: "load",
    free: "free",
    ref: "ref",
    get: "get",
    set: "set",
    getIndexed: "geti",
    setIndexed: "seti",
    value: "value",
    props: "props",
    method: "method",
    args: "args",
    static_: "static",
    connect: "connect",
    disconnect: "disconnect",
    cb: "cb",
    flags: "flags",
    constant: "const",
    expr: "expr",
    names: "names",
    values: "values",
    classes: "classes",
    classInfo: "classinfo",
    audit: "audit",
    mount: "mount",
    surface: "surface"
  };
  var GodotRef = class {
    constructor(id2) {
      this.id = id2;
    }
    toWire() {
      return { ref: this.id };
    }
    static isRef(v) {
      return !!v && typeof v === "object" && Object.keys(v).length === 1 && Number.isInteger(v.ref);
    }
  };
  var GodotCallbackRef = class {
    constructor(id2) {
      this.id = id2;
    }
    toWire() {
      return { cb: this.id };
    }
  };
  var _HandleAllocator = class _HandleAllocator {
    constructor(start = _HandleAllocator.selfHandle + 1) {
      this.next = start;
    }
    allocate() {
      return this.next++;
    }
    get issued() {
      return this.next - _HandleAllocator.selfHandle - 1;
    }
  };
  _HandleAllocator.selfHandle = 1;
  var HandleAllocator = _HandleAllocator;
  function isWireError(v) {
    return !!v && typeof v === "object" && "__dart_error__" in v;
  }
  function wireErrorMessage(v) {
    return isWireError(v) ? String(v.__dart_error__) : null;
  }
  var GodotOpException = class extends Error {
    constructor(message, op) {
      super(op ? `GodotOpException: ${message} (op: ${JSON.stringify(op)})` : `GodotOpException: ${message}`);
      this.op = op;
    }
  };
  var GodotValue = class {
  };
  function tagged(tag, data) {
    return { [tag]: data };
  }
  var Vector2 = class extends GodotValue {
    constructor(x, y) {
      super();
      this.x = x;
      this.y = y;
    }
    toWire() {
      return tagged("vec2", [this.x, this.y]);
    }
  };
  var Vector2i = class extends GodotValue {
    constructor(x, y) {
      super();
      this.x = x;
      this.y = y;
    }
    toWire() {
      return tagged("vec2i", [this.x, this.y]);
    }
  };
  var Vector3 = class _Vector3 extends GodotValue {
    constructor(x, y, z) {
      super();
      this.x = x;
      this.y = y;
      this.z = z;
    }
    static all(v) {
      return new _Vector3(v, v, v);
    }
    plus(o) {
      return new _Vector3(this.x + o.x, this.y + o.y, this.z + o.z);
    }
    minus(o) {
      return new _Vector3(this.x - o.x, this.y - o.y, this.z - o.z);
    }
    times(s) {
      return new _Vector3(this.x * s, this.y * s, this.z * s);
    }
    toWire() {
      return tagged("vec3", [this.x, this.y, this.z]);
    }
  };
  var Vector3i = class extends GodotValue {
    constructor(x, y, z) {
      super();
      this.x = x;
      this.y = y;
      this.z = z;
    }
    toWire() {
      return tagged("vec3i", [this.x, this.y, this.z]);
    }
  };
  var Vector4 = class extends GodotValue {
    constructor(x, y, z, w2) {
      super();
      this.x = x;
      this.y = y;
      this.z = z;
      this.w = w2;
    }
    toWire() {
      return tagged("vec4", [this.x, this.y, this.z, this.w]);
    }
  };
  var Vector4i = class extends GodotValue {
    constructor(x, y, z, w2) {
      super();
      this.x = x;
      this.y = y;
      this.z = z;
      this.w = w2;
    }
    toWire() {
      return tagged("vec4i", [this.x, this.y, this.z, this.w]);
    }
  };
  var GodotColor = class _GodotColor extends GodotValue {
    constructor(r, g, b, a = 1) {
      super();
      this.r = r;
      this.g = g;
      this.b = b;
      this.a = a;
    }
    static hex(rgb, a = 1) {
      return new _GodotColor((rgb >> 16 & 255) / 255, (rgb >> 8 & 255) / 255, (rgb & 255) / 255, a);
    }
    toWire() {
      return tagged("color", [this.r, this.g, this.b, this.a]);
    }
  };
  var Rect2 = class extends GodotValue {
    constructor(x, y, w2, h) {
      super();
      this.x = x;
      this.y = y;
      this.w = w2;
      this.h = h;
    }
    toWire() {
      return tagged("rect2", [this.x, this.y, this.w, this.h]);
    }
  };
  var Rect2i = class extends GodotValue {
    constructor(x, y, w2, h) {
      super();
      this.x = x;
      this.y = y;
      this.w = w2;
      this.h = h;
    }
    toWire() {
      return tagged("rect2i", [this.x, this.y, this.w, this.h]);
    }
  };
  var Plane = class extends GodotValue {
    constructor(nx, ny, nz, d) {
      super();
      this.nx = nx;
      this.ny = ny;
      this.nz = nz;
      this.d = d;
    }
    toWire() {
      return tagged("plane", [this.nx, this.ny, this.nz, this.d]);
    }
  };
  var Quaternion = class extends GodotValue {
    constructor(x, y, z, w2) {
      super();
      this.x = x;
      this.y = y;
      this.z = z;
      this.w = w2;
    }
    toWire() {
      return tagged("quat", [this.x, this.y, this.z, this.w]);
    }
  };
  var AABB = class extends GodotValue {
    constructor(px, py, pz, sx, sy, sz) {
      super();
      this.px = px;
      this.py = py;
      this.pz = pz;
      this.sx = sx;
      this.sy = sy;
      this.sz = sz;
    }
    toWire() {
      return tagged("aabb", [this.px, this.py, this.pz, this.sx, this.sy, this.sz]);
    }
  };
  var Basis = class extends GodotValue {
    constructor(rows) {
      super();
      this.rows = rows;
    }
    toWire() {
      return tagged("basis", this.rows);
    }
  };
  var Transform2D = class extends GodotValue {
    constructor(m) {
      super();
      this.m = m;
    }
    toWire() {
      return tagged("xform2d", this.m);
    }
  };
  var Transform3D = class extends GodotValue {
    constructor(m) {
      super();
      this.m = m;
    }
    toWire() {
      return tagged("xform3d", this.m);
    }
  };
  var Projection = class extends GodotValue {
    constructor(m) {
      super();
      this.m = m;
    }
    toWire() {
      return tagged("proj", this.m);
    }
  };
  var StringName = class extends GodotValue {
    constructor(value) {
      super();
      this.value = value;
    }
    toWire() {
      return tagged("sname", this.value);
    }
  };
  var NodePath = class extends GodotValue {
    constructor(value) {
      super();
      this.value = value;
    }
    toWire() {
      return tagged("npath", this.value);
    }
  };
  var GRid = class extends GodotValue {
    constructor(id2) {
      super();
      this.id = id2;
    }
    toWire() {
      return tagged("rid", this.id);
    }
  };
  var GSignal = class extends GodotValue {
    constructor(sourceHandle, name) {
      super();
      this.sourceHandle = sourceHandle;
      this.name = name;
    }
    toWire() {
      return tagged("sig", [new GodotRef(this.sourceHandle).toWire(), this.name]);
    }
  };
  var GCallable = class extends GodotValue {
    constructor(callbackId) {
      super();
      this.callbackId = callbackId;
    }
    toWire() {
      return tagged("callable", this.callbackId);
    }
  };
  var GInt = class extends GodotValue {
    constructor(value) {
      super();
      this.value = value;
    }
    toWire() {
      return tagged("int", Math.trunc(this.value));
    }
  };
  var GFloat = class extends GodotValue {
    constructor(value) {
      super();
      this.value = value;
    }
    toWire() {
      return tagged("float", this.value);
    }
  };
  var GDict = class extends GodotValue {
    constructor(entries) {
      super();
      this.entries = entries;
    }
    toWire() {
      return tagged("dictv", this.entries.map(([k, v]) => [marshal(k), marshal(v)]));
    }
  };
  var Packed = class _Packed extends GodotValue {
    constructor(tag, data) {
      super();
      this.tag = tag;
      this.data = data;
    }
    static bytesBase64(b64) {
      return new _Packed("u8", b64);
    }
    static i32(v) {
      return new _Packed("i32", v);
    }
    static i64(v) {
      return new _Packed("i64", v);
    }
    static f32(v) {
      return new _Packed("f32", v);
    }
    static f64(v) {
      return new _Packed("f64", v);
    }
    static strings(v) {
      return new _Packed("strs", v);
    }
    static vector2s(flat) {
      return new _Packed("pv2", flat);
    }
    static vector3s(flat) {
      return new _Packed("pv3", flat);
    }
    static vector4s(flat) {
      return new _Packed("pv4", flat);
    }
    static colors(flat) {
      return new _Packed("pcol", flat);
    }
    toWire() {
      return tagged(this.tag, this.data);
    }
  };
  function isHandle(v) {
    return !!v && typeof v === "object" && v.ref instanceof GodotRef;
  }
  function marshal(v) {
    if (v == null || typeof v === "boolean" || typeof v === "string" || typeof v === "number") return v;
    if (v instanceof GodotValue) return v.toWire();
    if (v instanceof GodotRef) return v.toWire();
    if (v instanceof GodotCallbackRef) return v.toWire();
    if (isHandle(v)) return v.ref.toWire();
    if (Array.isArray(v)) return v.map(marshal);
    if (typeof v === "object") {
      const out = {};
      for (const [k, val] of Object.entries(v)) out[k] = marshal(val);
      return { dict: out };
    }
    return v;
  }
  function marshalArgs(args) {
    return args ? args.map(marshal) : [];
  }
  function unmarshal(v) {
    if (Array.isArray(v)) return v.map(unmarshal);
    if (!v || typeof v !== "object") return v;
    const map = v;
    if ("__dart_error__" in map) return v;
    const keys = Object.keys(map);
    if (keys.length !== 1) return v;
    const key = keys[0];
    const data = map[key];
    const nums = () => data.map((e) => Number(e));
    const ints = () => data.map((e) => Math.trunc(Number(e)));
    switch (key) {
      case "ref":
        return new GodotRef(data);
      case "vec2": {
        const n = nums();
        return new Vector2(n[0], n[1]);
      }
      case "vec2i": {
        const n = ints();
        return new Vector2i(n[0], n[1]);
      }
      case "vec3": {
        const n = nums();
        return new Vector3(n[0], n[1], n[2]);
      }
      case "vec3i": {
        const n = ints();
        return new Vector3i(n[0], n[1], n[2]);
      }
      case "vec4": {
        const n = nums();
        return new Vector4(n[0], n[1], n[2], n[3]);
      }
      case "vec4i": {
        const n = ints();
        return new Vector4i(n[0], n[1], n[2], n[3]);
      }
      case "color": {
        const n = nums();
        return new GodotColor(n[0], n[1], n[2], n[3]);
      }
      case "rect2": {
        const n = nums();
        return new Rect2(n[0], n[1], n[2], n[3]);
      }
      case "rect2i": {
        const n = ints();
        return new Rect2i(n[0], n[1], n[2], n[3]);
      }
      case "plane": {
        const n = nums();
        return new Plane(n[0], n[1], n[2], n[3]);
      }
      case "quat": {
        const n = nums();
        return new Quaternion(n[0], n[1], n[2], n[3]);
      }
      case "aabb": {
        const n = nums();
        return new AABB(n[0], n[1], n[2], n[3], n[4], n[5]);
      }
      case "basis":
        return new Basis(data.map((row3) => row3.map((e) => Number(e))));
      case "xform2d":
        return new Transform2D(nums());
      case "xform3d":
        return new Transform3D(nums());
      case "proj":
        return new Projection(nums());
      case "sname":
        return new StringName(String(data));
      case "npath":
        return new NodePath(String(data));
      case "rid":
        return new GRid(Number(data));
      case "int":
        return Math.trunc(Number(data));
      case "float":
        return Number(data);
      case "callable":
        return new GCallable(Number(data));
      case "dict": {
        const out = {};
        for (const [k, val] of Object.entries(data)) out[k] = unmarshal(val);
        return out;
      }
      case "dictv":
        return new GDict(data.map((pair) => [unmarshal(pair[0]), unmarshal(pair[1])]));
      case "u8":
      case "i32":
      case "i64":
      case "f32":
      case "f64":
      case "strs":
      case "pv2":
      case "pv3":
      case "pv4":
      case "pcol":
        return new Packed(key, data);
      default:
        return v;
    }
  }

  // core/src/godot/controller.ts
  var MockGodotBinding = class {
    constructor() {
      this.ops = [];
      this.surfaces = /* @__PURE__ */ new Map();
      this.nextHostHandle = 1e6;
      this.onSignal = null;
    }
    get isLive() {
      return false;
    }
    record(op) {
      this.ops.push(op);
      const produces = OpKey.create in op || op[OpKey.self] === true || op[OpKey.tree] === true || OpKey.singleton in op || OpKey.load in op;
      if (produces) {
        const def = op[OpKey.def];
        return typeof def === "number" && def !== 0 ? def : this.nextHostHandle++;
      }
      return null;
    }
    async send(batch) {
      return batch.map((op) => this.record(op));
    }
    post(batch) {
      for (const op of batch) this.record(op);
    }
    async mountSurface(surfaceId, mountHandle) {
      this.surfaces.set(surfaceId, mountHandle);
    }
    async releaseSurface(surfaceId) {
      this.surfaces.delete(surfaceId);
    }
    fireSignal(callbackId, args) {
      var _a;
      (_a = this.onSignal) == null ? void 0 : _a.call(this, callbackId, args);
    }
    clear() {
      this.ops.length = 0;
    }
    async stats() {
      return { pushed: this.ops.length, polls: 0, drained: this.ops.length };
    }
    dispose() {
    }
  };
  var nextSurfaceId = 1;
  function scheduleMicrotask(fn) {
    const q = globalThis.queueMicrotask;
    if (typeof q === "function") q(fn);
    else void Promise.resolve().then(fn);
  }
  var GodotController = class {
    constructor(binding2, surfaceId) {
      this.binding = binding2;
      this.handles = new HandleAllocator();
      this.callbacks = /* @__PURE__ */ new Map();
      this.pending = [];
      this.nextCallbackId = 1;
      this.explicitBatch = false;
      this.flushScheduled = false;
      this.disposed = false;
      this.mounted = false;
      this.listeners = /* @__PURE__ */ new Set();
      this.surfaceId = surfaceId != null ? surfaceId : nextSurfaceId++;
      binding2.onSignal = (id2, args) => this.dispatchSignal(id2, args);
      this.root = new GodotObject(this, HandleAllocator.selfHandle);
      this.g3 = new Godot3D(this);
    }
    get isLive() {
      return this.binding.isLive;
    }
    get pendingOps() {
      return this.pending.length;
    }
    addListener(fn) {
      this.listeners.add(fn);
    }
    removeListener(fn) {
      this.listeners.delete(fn);
    }
    // ---- op submission ------------------------------------------------------
    enqueue(op) {
      if (this.disposed) return;
      this.pending.push(op);
      if (!this.explicitBatch) this.scheduleFlush();
    }
    async request(op) {
      var _a;
      if (this.disposed) return null;
      const batch = [...this.pending, op];
      this.pending = [];
      const replies = await this.binding.send(batch);
      if (replies.length < batch.length) return null;
      const reply = replies[batch.length - 1];
      if (isWireError(reply)) throw new GodotOpException((_a = wireErrorMessage(reply)) != null ? _a : "engine error", op);
      return unmarshal(reply);
    }
    beginBatch() {
      this.explicitBatch = true;
    }
    endBatch() {
      this.explicitBatch = false;
      this.flush();
    }
    flush() {
      if (this.pending.length === 0 || this.disposed) return;
      const batch = this.pending;
      this.pending = [];
      this.binding.post(batch);
    }
    scheduleFlush() {
      if (this.flushScheduled) return;
      this.flushScheduled = true;
      scheduleMicrotask(() => {
        this.flushScheduled = false;
        this.flush();
      });
    }
    // ---- object creation (the GD facade) -----------------------------------
    create(className) {
      const handle = this.handles.allocate();
      this.enqueue({ [OpKey.create]: className, [OpKey.def]: handle });
      return new GodotObject(this, handle);
    }
    createWith(className, properties) {
      const node = this.create(className);
      node.setAll(properties);
      return node;
    }
    singleton(name) {
      const handle = this.handles.allocate();
      this.enqueue({ [OpKey.singleton]: name, [OpKey.def]: handle });
      return new GodotObject(this, handle);
    }
    tree() {
      const handle = this.handles.allocate();
      this.enqueue({ [OpKey.tree]: true, [OpKey.def]: handle });
      return new GodotObject(this, handle);
    }
    load(path) {
      const handle = this.handles.allocate();
      this.enqueue({ [OpKey.load]: path, [OpKey.def]: handle });
      return new GodotObject(this, handle);
    }
    mount(node) {
      this.root.addChild(node);
    }
    constant(name) {
      return this.request({ [OpKey.constant]: name });
    }
    evaluate(expression, names = [], values = []) {
      return this.request({ [OpKey.expr]: expression, [OpKey.names]: names, [OpKey.values]: marshalArgs(values) });
    }
    async classes() {
      const reply = await this.request({ [OpKey.classes]: true });
      return Array.isArray(reply) ? reply.map(String) : [];
    }
    async classInfo(className) {
      const reply = await this.request({ [OpKey.classInfo]: className });
      return reply && typeof reply === "object" ? reply : {};
    }
    audit() {
      return this.request({ [OpKey.audit]: true });
    }
    stats() {
      return this.binding.stats();
    }
    renderingServer() {
      return this.singleton("RenderingServer");
    }
    physicsServer3D() {
      return this.singleton("PhysicsServer3D");
    }
    physicsServer2D() {
      return this.singleton("PhysicsServer2D");
    }
    audioServer() {
      return this.singleton("AudioServer");
    }
    displayServer() {
      return this.singleton("DisplayServer");
    }
    input() {
      return this.singleton("Input");
    }
    engine() {
      return this.singleton("Engine");
    }
    os() {
      return this.singleton("OS");
    }
    time() {
      return this.singleton("Time");
    }
    projectSettings() {
      return this.singleton("ProjectSettings");
    }
    resourceLoader() {
      return this.singleton("ResourceLoader");
    }
    // ---- callbacks ----------------------------------------------------------
    registerCallback(callback) {
      const id2 = this.nextCallbackId++;
      this.callbacks.set(id2, callback);
      return id2;
    }
    unregisterCallback(id2) {
      this.callbacks.delete(id2);
    }
    callable(callback) {
      return new GCallable(this.registerCallback(callback));
    }
    dispatchSignal(id2, args) {
      const callback = this.callbacks.get(id2);
      if (!callback) return;
      callback(args.map(unmarshal));
    }
    releaseHandle(handle) {
      this.enqueue({ [OpKey.free]: handle, weak: true });
    }
    // ---- surface lifecycle ---------------------------------------------------
    async attachSurface() {
      if (this.mounted || this.disposed) return;
      this.mounted = true;
      this.flush();
      await this.binding.mountSurface(this.surfaceId, this.root.handle);
      for (const l of [...this.listeners]) l();
    }
    async detachSurface() {
      if (!this.mounted) return;
      this.mounted = false;
      await this.binding.releaseSurface(this.surfaceId);
    }
    get isAttached() {
      return this.mounted;
    }
    dispose() {
      if (this.disposed) return;
      this.disposed = true;
      this.pending = [];
      this.callbacks.clear();
      void this.detachSurface();
      this.binding.onSignal = null;
      this.listeners.clear();
    }
  };
  var GodotObject = class {
    constructor(controller, handle) {
      this.controller = controller;
      this.handle = handle;
    }
    get ref() {
      return new GodotRef(this.handle);
    }
    call(method, args) {
      return this.controller.request({ [OpKey.ref]: this.handle, [OpKey.method]: method, [OpKey.args]: marshalArgs(args) });
    }
    callVoid(method, args) {
      this.controller.enqueue({ [OpKey.ref]: this.handle, [OpKey.method]: method, [OpKey.args]: marshalArgs(args) });
    }
    get(property) {
      return this.controller.request({ [OpKey.ref]: this.handle, [OpKey.get]: property });
    }
    set(property, value) {
      this.controller.enqueue({ [OpKey.ref]: this.handle, [OpKey.set]: property, [OpKey.value]: marshal(value) });
    }
    setAll(properties) {
      const keys = Object.keys(properties);
      if (keys.length === 0) return;
      const props = {};
      for (const k of keys) props[k] = marshal(properties[k]);
      this.controller.enqueue({ [OpKey.ref]: this.handle, [OpKey.props]: props });
    }
    getIndexed(path) {
      return this.controller.request({ [OpKey.ref]: this.handle, [OpKey.getIndexed]: path });
    }
    setIndexed(path, value) {
      this.controller.enqueue({ [OpKey.ref]: this.handle, [OpKey.setIndexed]: path, [OpKey.value]: marshal(value) });
    }
    connect(signal, callback, flags = 0) {
      const id2 = this.controller.registerCallback(callback);
      const op = { [OpKey.ref]: this.handle, [OpKey.connect]: signal, [OpKey.cb]: id2 };
      if (flags !== 0) op[OpKey.flags] = flags;
      this.controller.enqueue(op);
      return id2;
    }
    disconnect(signal, callbackId) {
      this.controller.enqueue({ [OpKey.ref]: this.handle, [OpKey.disconnect]: signal, [OpKey.cb]: callbackId });
      this.controller.unregisterCallback(callbackId);
    }
    signal(name) {
      return new GSignal(this.handle, name);
    }
    emitSignal(name, args = []) {
      this.callVoid("emit_signal", [name, ...args]);
    }
    addChild(child) {
      this.callVoid("add_child", [child]);
    }
    removeChild(child) {
      this.callVoid("remove_child", [child]);
    }
    addChildren(children) {
      for (const c of children) this.addChild(c);
    }
    queueFree() {
      this.callVoid("queue_free");
    }
    freeNow() {
      this.controller.enqueue({ [OpKey.free]: this.handle });
    }
    release() {
      this.controller.releaseHandle(this.handle);
    }
  };
  var Godot3D = class _Godot3D {
    constructor(c) {
      this.c = c;
    }
    node(opts = {}) {
      const n = this.c.create("Node3D");
      this.setTransform(n, opts);
      return n;
    }
    material(opts = {}) {
      var _a;
      const m = this.c.create("StandardMaterial3D");
      m.set("albedo_color", (_a = opts.color) != null ? _a : new GodotColor(0.8, 0.82, 0.9, 1));
      if (opts.metallic != null) m.set("metallic", new GFloat(opts.metallic));
      if (opts.roughness != null) m.set("roughness", new GFloat(opts.roughness));
      if (opts.emission) {
        m.set("emission_enabled", true);
        m.set("emission", opts.emission);
        if (opts.emissionEnergy != null) m.set("emission_energy_multiplier", new GFloat(opts.emissionEnergy));
      }
      if (opts.transparency) m.set("transparency", new GInt(1));
      return m;
    }
    primitive(shape, options = {}) {
      const n = (key, fallback) => typeof options[key] === "number" ? options[key] : fallback;
      switch (shape) {
        case "sphere": {
          const mesh = this.c.create("SphereMesh");
          const r = n("radius", 0.5);
          mesh.set("radius", new GFloat(r));
          mesh.set("height", new GFloat(n("height", r * 2)));
          return mesh;
        }
        case "cylinder": {
          const mesh = this.c.create("CylinderMesh");
          const r = n("radius", 0.5);
          mesh.set("top_radius", new GFloat(n("topRadius", r)));
          mesh.set("bottom_radius", new GFloat(n("bottomRadius", r)));
          mesh.set("height", new GFloat(n("height", 1)));
          return mesh;
        }
        case "capsule": {
          const mesh = this.c.create("CapsuleMesh");
          mesh.set("radius", new GFloat(n("radius", 0.4)));
          mesh.set("height", new GFloat(n("height", 1.4)));
          return mesh;
        }
        case "plane": {
          const mesh = this.c.create("PlaneMesh");
          mesh.set("size", new Vector2(n("width", 2), n("depth", 2)));
          return mesh;
        }
        case "prism": {
          const mesh = this.c.create("PrismMesh");
          mesh.set("size", _Godot3D.vec3(options.size, 1, 1, 1));
          return mesh;
        }
        case "torus": {
          const mesh = this.c.create("TorusMesh");
          mesh.set("inner_radius", new GFloat(n("innerRadius", 0.3)));
          mesh.set("outer_radius", new GFloat(n("outerRadius", 0.6)));
          return mesh;
        }
        default: {
          const mesh = this.c.create("BoxMesh");
          mesh.set("size", _Godot3D.vec3(options.size, 1, 1, 1));
          return mesh;
        }
      }
    }
    mesh(shape, options = {}, material) {
      var _a, _b, _c, _d, _e;
      const mi = this.c.create("MeshInstance3D");
      const prim = this.primitive(shape, options);
      prim.set(
        "material",
        material != null ? material : this.material({
          color: (_a = options.color) != null ? _a : null,
          metallic: (_b = options.metallic) != null ? _b : null,
          roughness: (_c = options.roughness) != null ? _c : null,
          emission: (_d = options.emission) != null ? _d : null,
          emissionEnergy: (_e = options.emissionEnergy) != null ? _e : null,
          transparency: options.transparency === true
        })
      );
      mi.set("mesh", prim);
      this.setTransform(mi, { position: options.position, rotation: options.rotation, scale: options.scale, visible: options.visible });
      return mi;
    }
    camera(opts = {}) {
      const cam = this.c.create("Camera3D");
      if (opts.fov != null) cam.set("fov", new GFloat(opts.fov));
      if (opts.current !== false) cam.set("current", true);
      this.setTransform(cam, { position: opts.position, rotation: opts.rotation });
      return cam;
    }
    dirLight(opts = {}) {
      var _a, _b;
      const l = this.c.create("DirectionalLight3D");
      l.set("light_color", (_a = opts.color) != null ? _a : new GodotColor(1, 0.98, 0.92, 1));
      l.set("light_energy", new GFloat((_b = opts.energy) != null ? _b : 1));
      if (opts.shadow) l.set("shadow_enabled", true);
      this.setTransform(l, { position: opts.position, rotation: opts.rotation });
      return l;
    }
    omniLight(opts = {}) {
      var _a, _b;
      const l = this.c.create("OmniLight3D");
      l.set("light_color", (_a = opts.color) != null ? _a : new GodotColor(1, 1, 1, 1));
      l.set("light_energy", new GFloat((_b = opts.energy) != null ? _b : 1));
      if (opts.range != null) l.set("omni_range", new GFloat(opts.range));
      this.setTransform(l, { position: opts.position });
      return l;
    }
    spotLight(opts = {}) {
      var _a, _b;
      const l = this.c.create("SpotLight3D");
      l.set("light_color", (_a = opts.color) != null ? _a : new GodotColor(1, 1, 1, 1));
      l.set("light_energy", new GFloat((_b = opts.energy) != null ? _b : 1));
      if (opts.range != null) l.set("spot_range", new GFloat(opts.range));
      if (opts.angle != null) l.set("spot_angle", new GFloat(opts.angle));
      this.setTransform(l, { position: opts.position, rotation: opts.rotation });
      return l;
    }
    environment(opts = {}) {
      var _a, _b, _c;
      const we = this.c.create("WorldEnvironment");
      const env2 = this.c.create("Environment");
      env2.set("background_mode", new GInt(1));
      env2.set("background_color", (_a = opts.bg) != null ? _a : new GodotColor(0.05, 0.06, 0.09, 1));
      env2.set("ambient_light_source", new GInt(3));
      env2.set("ambient_light_color", (_b = opts.ambient) != null ? _b : new GodotColor(0.5, 0.55, 0.7, 1));
      env2.set("ambient_light_energy", new GFloat((_c = opts.ambientEnergy) != null ? _c : 0.6));
      we.set("environment", env2);
      return we;
    }
    async instanceScene(path) {
      const packed = this.c.load(path);
      const instance = await packed.call("instantiate");
      return instance instanceof GodotRef ? new GodotObject(this.c, instance.id) : null;
    }
    setTransform(node, opts) {
      if (opts.position != null) node.set("position", _Godot3D.vec3(opts.position, 0, 0, 0));
      if (opts.rotation != null) node.set("rotation_degrees", _Godot3D.vec3(opts.rotation, 0, 0, 0));
      if (opts.scale != null) node.set("scale", _Godot3D.vec3(opts.scale, 1, 1, 1));
      if (opts.visible != null) node.set("visible", opts.visible);
    }
    static vec3(v, dx, dy, dz) {
      if (v instanceof Vector3) return v;
      if (typeof v === "number") return new Vector3(v, v, v);
      if (Array.isArray(v) && v.length >= 3) return new Vector3(Number(v[0]), Number(v[1]), Number(v[2]));
      return new Vector3(dx, dy, dz);
    }
  };

  // core/src/godot/scene.ts
  var GodotScene = class {
    constructor(controller, nodesById, roots) {
      this.controller = controller;
      this.nodesById = nodesById;
      this.roots = roots;
    }
    byId(id2) {
      return this.nodesById.get(id2);
    }
    require(id2) {
      const node = this.nodesById.get(id2);
      if (!node) throw new Error(`no node with id "${id2}" in the scene`);
      return node;
    }
  };
  function parseGodotColor(value) {
    if (value == null) return null;
    if (value instanceof GodotColor) return value;
    if (Array.isArray(value) && value.length >= 3) {
      const at = (i, f) => typeof value[i] === "number" ? value[i] : f;
      return new GodotColor(at(0, 0), at(1, 0), at(2, 0), at(3, 1));
    }
    if (typeof value === "string" && value.startsWith("#")) {
      let hex = value.substring(1);
      if (hex.length === 3) hex = hex.split("").map((c) => c + c).join("");
      if (hex.length !== 6 && hex.length !== 8) return null;
      const rgb = parseInt(hex.substring(0, 6), 16);
      if (!Number.isFinite(rgb)) return null;
      let alpha = 1;
      if (hex.length === 8) {
        const a = parseInt(hex.substring(6, 8), 16);
        if (Number.isFinite(a)) alpha = a / 255;
      }
      return GodotColor.hex(rgb, alpha);
    }
    return null;
  }
  function looksLikeColor(v) {
    return v.startsWith("#") && (v.length === 7 || v.length === 9 || v.length === 4);
  }
  var SceneDsl = class {
    constructor(controller) {
      this.controller = controller;
    }
    build(json) {
      const byId = /* @__PURE__ */ new Map();
      const roots = [];
      const c = this.controller;
      c.beginBatch();
      try {
        const env2 = json.environment;
        if (env2 && typeof env2 === "object") {
          const node = this.environment(env2);
          c.mount(node);
          roots.push(node);
        }
        const camera = json.camera;
        if (camera && typeof camera === "object") {
          const node = this.camera(camera);
          c.mount(node);
          roots.push(node);
          this.register(byId, camera, node);
        }
        const lights = json.lights;
        if (Array.isArray(lights)) {
          for (const light of lights) {
            if (!light || typeof light !== "object") continue;
            const node = this.light(light);
            c.mount(node);
            roots.push(node);
            this.register(byId, light, node);
          }
        }
        const nodes = json.nodes;
        if (Array.isArray(nodes)) {
          for (const entry of nodes) {
            if (!entry || typeof entry !== "object") continue;
            const node = this.node(entry, byId);
            if (!node) continue;
            c.mount(node);
            roots.push(node);
          }
        }
      } finally {
        c.endBatch();
      }
      return new GodotScene(c, byId, roots);
    }
    register(byId, spec, node) {
      const id2 = spec.id;
      if (typeof id2 === "string" && id2 !== "") byId.set(id2, node);
    }
    environment(spec) {
      return this.controller.g3.environment({
        bg: parseGodotColor(spec.bg),
        ambient: parseGodotColor(spec.ambient),
        ambientEnergy: typeof spec.ambientEnergy === "number" ? spec.ambientEnergy : 0.6
      });
    }
    camera(spec) {
      return this.controller.g3.camera({
        fov: typeof spec.fov === "number" ? spec.fov : null,
        current: spec.current !== false,
        position: spec.position,
        rotation: spec.rotation
      });
    }
    light(spec) {
      const g3 = this.controller.g3;
      const num3 = (v, f) => typeof v === "number" ? v : f;
      switch (spec.type) {
        case "omni":
        case "point":
          return g3.omniLight({ color: parseGodotColor(spec.color), energy: num3(spec.energy, 1), range: typeof spec.range === "number" ? spec.range : null, position: spec.position });
        case "spot":
          return g3.spotLight({
            color: parseGodotColor(spec.color),
            energy: num3(spec.energy, 1),
            range: typeof spec.range === "number" ? spec.range : null,
            angle: typeof spec.angle === "number" ? spec.angle : null,
            position: spec.position,
            rotation: spec.rotation
          });
        default:
          return g3.dirLight({ color: parseGodotColor(spec.color), energy: num3(spec.energy, 1), shadow: spec.shadow === true, position: spec.position, rotation: spec.rotation });
      }
    }
    node(spec, byId) {
      var _a;
      const type = typeof spec.type === "string" ? spec.type : "node";
      const c = this.controller;
      let node;
      switch (type) {
        case "mesh": {
          const options = __spreadValues({}, spec);
          if (spec.color != null) options.color = parseGodotColor(spec.color);
          if (spec.emission != null) options.emission = parseGodotColor(spec.emission);
          node = c.g3.mesh(typeof spec.shape === "string" ? spec.shape : "box", options);
          break;
        }
        case "node":
        case "group":
          node = c.g3.node({ position: spec.position, rotation: spec.rotation, scale: spec.scale, visible: typeof spec.visible === "boolean" ? spec.visible : null });
          break;
        case "camera":
          node = this.camera(spec);
          break;
        case "light":
          node = this.light(spec);
          break;
        default:
          node = c.create(type);
          c.g3.setTransform(node, { position: spec.position, rotation: spec.rotation, scale: spec.scale, visible: typeof spec.visible === "boolean" ? spec.visible : null });
      }
      const props = spec.props;
      if (props && typeof props === "object") {
        const coerced = {};
        for (const [k, v] of Object.entries(props)) {
          coerced[k] = typeof v === "string" && looksLikeColor(v) ? (_a = parseGodotColor(v)) != null ? _a : v : v;
        }
        node.setAll(coerced);
      }
      this.register(byId, spec, node);
      const children = spec.children;
      if (Array.isArray(children)) {
        for (const child of children) {
          if (!child || typeof child !== "object") continue;
          const built = this.node(child, byId);
          if (built) node.addChild(built);
        }
      }
      return node;
    }
  };
  var GodotSceneController = class {
    constructor(binding2) {
      this.current = null;
      this.disposed = false;
      this.listeners = /* @__PURE__ */ new Set();
      this.godot = new GodotController(binding2);
    }
    get scene() {
      return this.current;
    }
    get isLive() {
      return this.godot.isLive;
    }
    node(id2) {
      var _a;
      return (_a = this.current) == null ? void 0 : _a.byId(id2);
    }
    adopt(scene) {
      this.current = scene;
      if (!this.disposed) for (const l of [...this.listeners]) l();
    }
    replaceScene(json) {
      var _a, _b;
      for (const root of (_b = (_a = this.current) == null ? void 0 : _a.roots) != null ? _b : []) root.queueFree();
      const built = new SceneDsl(this.godot).build(json);
      this.adopt(built);
      return built;
    }
    addListener(fn) {
      this.listeners.add(fn);
    }
    dispose() {
      if (this.disposed) return;
      this.disposed = true;
      this.godot.dispose();
      this.listeners.clear();
    }
  };

  // core/src/host/dom.ts
  var ElpianElement = class {
    constructor(tagName, id2, classes, dom) {
      this.tagName = tagName;
      this.id = id2;
      this.classes = classes;
      this.dom = dom;
      this.parent = null;
      this.kids = [];
      this.attrs = {};
      this.styles = {};
      this.listeners = /* @__PURE__ */ new Map();
      this.textContent = null;
    }
    get innerHTML() {
      return this.textContent;
    }
    set innerHTML(v) {
      this.textContent = v;
    }
    getAttribute(name) {
      return this.attrs[name];
    }
    setAttribute(name, value) {
      this.attrs[name] = value;
    }
    removeAttribute(name) {
      delete this.attrs[name];
    }
    hasAttribute(name) {
      return Object.prototype.hasOwnProperty.call(this.attrs, name);
    }
    get attributes() {
      return __spreadValues({}, this.attrs);
    }
    setStyle(property, value) {
      this.styles[property] = value;
    }
    getStyle(property) {
      return this.styles[property];
    }
    setStyleObject(styles) {
      Object.assign(this.styles, styles);
    }
    get style() {
      return __spreadValues({}, this.styles);
    }
    addClass(className) {
      if (!this.classes.includes(className)) {
        this.classes.push(className);
        this.dom.indexClass(className, this);
      }
    }
    removeClass(className) {
      const i = this.classes.indexOf(className);
      if (i >= 0) this.classes.splice(i, 1);
      this.dom.unindexClass(className, this);
    }
    hasClass(className) {
      return this.classes.includes(className);
    }
    toggleClass(className) {
      if (this.hasClass(className)) this.removeClass(className);
      else this.addClass(className);
    }
    appendChild(child) {
      var _a;
      (_a = child.parent) == null ? void 0 : _a.removeChild(child);
      child.parent = this;
      this.kids.push(child);
    }
    insertBefore(newChild, reference) {
      var _a;
      (_a = newChild.parent) == null ? void 0 : _a.removeChild(newChild);
      newChild.parent = this;
      if (!reference) {
        this.kids.push(newChild);
        return;
      }
      const index = this.kids.indexOf(reference);
      if (index >= 0) this.kids.splice(index, 0, newChild);
      else this.kids.push(newChild);
    }
    removeChild(child) {
      const i = this.kids.indexOf(child);
      if (i >= 0) {
        this.kids.splice(i, 1);
        child.parent = null;
      }
    }
    replaceChild(newChild, oldChild) {
      var _a;
      if (!this.kids.includes(oldChild)) return;
      (_a = newChild.parent) == null ? void 0 : _a.removeChild(newChild);
      const index = this.kids.indexOf(oldChild);
      newChild.parent = this;
      oldChild.parent = null;
      this.kids[index] = newChild;
    }
    get children() {
      return [...this.kids];
    }
    get firstChild() {
      var _a;
      return (_a = this.kids[0]) != null ? _a : null;
    }
    get lastChild() {
      var _a;
      return (_a = this.kids[this.kids.length - 1]) != null ? _a : null;
    }
    get nextSibling() {
      if (!this.parent) return null;
      const s = this.parent.kids;
      const i = s.indexOf(this);
      return i >= 0 && i < s.length - 1 ? s[i + 1] : null;
    }
    get previousSibling() {
      if (!this.parent) return null;
      const s = this.parent.kids;
      const i = s.indexOf(this);
      return i > 0 ? s[i - 1] : null;
    }
    addEventListener(event, callback) {
      this.listeners.set(event, callback);
    }
    removeEventListener(event) {
      this.listeners.delete(event);
    }
    dispatchEvent(event, data) {
      var _a;
      (_a = this.listeners.get(event)) == null ? void 0 : _a(data);
    }
    clone(deep = false) {
      const copy = this.dom.createElement(this.tagName, { classes: [...this.classes] });
      copy.attrs = __spreadValues({}, this.attrs);
      copy.styles = __spreadValues({}, this.styles);
      copy.textContent = this.textContent;
      if (deep) for (const k of this.kids) copy.appendChild(k.clone(true));
      return copy;
    }
    /** The element as Elpian JSON (`toElpianNode().toJson()`). */
    toJson() {
      const props = __spreadValues({}, this.attrs);
      if (this.textContent != null) props.text = this.textContent;
      if (this.classes.length) props.className = this.classes.join(" ");
      if (Object.keys(this.styles).length) props.style = __spreadValues({}, this.styles);
      const out = { type: this.tagName, props, children: this.kids.map((k) => k.toJson()) };
      if (this.id != null) out.key = this.id;
      return out;
    }
    encode() {
      return {
        id: this.id,
        tagName: this.tagName,
        classes: [...this.classes],
        attributes: __spreadValues({}, this.attrs),
        style: __spreadValues({}, this.styles),
        textContent: this.textContent,
        children: this.kids.map((c) => c.id)
      };
    }
    toString() {
      return `<${this.tagName}${this.id ? ` id="${this.id}"` : ""}${this.classes.length ? ` class="${this.classes.join(" ")}"` : ""}>`;
    }
  };
  var ElpianDOM = class {
    constructor() {
      this.byId = /* @__PURE__ */ new Map();
      this.all = [];
      this.byClass = /* @__PURE__ */ new Map();
      this.byTag = /* @__PURE__ */ new Map();
    }
    getElementById(id2) {
      var _a;
      return (_a = this.byId.get(id2)) != null ? _a : null;
    }
    getElementsByClassName(className) {
      var _a;
      return [...(_a = this.byClass.get(className)) != null ? _a : []];
    }
    getElementsByTagName(tagName) {
      var _a;
      return [...(_a = this.byTag.get(tagName)) != null ? _a : []];
    }
    querySelector(selector) {
      var _a;
      return (_a = this.querySelectorAll(selector)[0]) != null ? _a : null;
    }
    querySelectorAll(selector) {
      const s = selector.trim();
      if (s.startsWith("#")) {
        const e = this.getElementById(s.substring(1));
        return e ? [e] : [];
      }
      if (s.startsWith(".")) return this.getElementsByClassName(s.substring(1));
      const m = /^([a-zA-Z][\w-]*)?((?:\.[\w-]+)*)$/.exec(s);
      if (m && m[2]) {
        const classes = m[2].split(".").filter((c) => c);
        return this.all.filter((e) => (!m[1] || e.tagName === m[1]) && classes.every((c) => e.classes.includes(c)));
      }
      return this.getElementsByTagName(s);
    }
    createElement(tagName, opts = {}) {
      var _a, _b, _c;
      const el = new ElpianElement(tagName, (_a = opts.id) != null ? _a : null, [...(_b = opts.classes) != null ? _b : []], this);
      if (el.id != null) this.byId.set(el.id, el);
      this.all.push(el);
      const tags = (_c = this.byTag.get(tagName)) != null ? _c : [];
      tags.push(el);
      this.byTag.set(tagName, tags);
      for (const c of el.classes) this.indexClass(c, el);
      return el;
    }
    /** Build elements from Elpian JSON (`ElpianElement.fromElpianNode`). */
    fromJson(json) {
      var _a, _b, _c, _d;
      const props = (_a = json.props) != null ? _a : {};
      const cn = props.className;
      const classes = typeof cn === "string" ? cn.split(/\s+/).filter((c) => c) : Array.isArray(cn) ? cn.map(String) : [];
      const el = this.createElement(String((_b = json.type) != null ? _b : "div"), { id: (_c = json.key) != null ? _c : null, classes });
      for (const [k, v] of Object.entries(props)) if (k !== "className" && k !== "style") el.setAttribute(k, v);
      if (props.style && typeof props.style === "object") el.setStyleObject(props.style);
      if (props.text != null) el.textContent = String(props.text);
      for (const child of (_d = json.children) != null ? _d : []) el.appendChild(this.fromJson(child));
      return el;
    }
    indexClass(className, el) {
      var _a;
      const list2 = (_a = this.byClass.get(className)) != null ? _a : [];
      if (!list2.includes(el)) list2.push(el);
      this.byClass.set(className, list2);
    }
    unindexClass(className, el) {
      const list2 = this.byClass.get(className);
      if (!list2) return;
      const i = list2.indexOf(el);
      if (i >= 0) list2.splice(i, 1);
    }
    removeElement(el) {
      var _a;
      if (el.id != null) this.byId.delete(el.id);
      this.all = this.all.filter((e) => e !== el);
      const tags = this.byTag.get(el.tagName);
      if (tags) this.byTag.set(el.tagName, tags.filter((e) => e !== el));
      for (const c of el.classes) this.unindexClass(c, el);
      (_a = el.parent) == null ? void 0 : _a.removeChild(el);
    }
    clear() {
      this.byId.clear();
      this.all = [];
      this.byClass.clear();
      this.byTag.clear();
    }
    get allElements() {
      return [...this.all];
    }
  };

  // core/src/model/node.ts
  function nodeFromJson(json) {
    var _a;
    const props = isMap(json.props) ? __spreadValues({}, json.props) : {};
    if (json.style != null && props.style == null) props.style = json.style;
    for (const k of ["className", "class", "text", "id"]) {
      if (json[k] != null && props[k] == null) props[k] = json[k];
    }
    if (props.class != null && props.className == null) props.className = props.class;
    const rawChildren = Array.isArray(json.children) ? json.children : [];
    const children = [];
    for (const child of rawChildren) {
      if (isMap(child)) children.push(nodeFromJson(child));
      else if (typeof child === "string" || typeof child === "number") {
        children.push({ type: "#text", props: { text: String(child) }, children: [], key: null, events: null, style: null });
      }
    }
    return {
      type: String((_a = json.type) != null ? _a : "div"),
      props,
      children,
      key: json.key != null ? String(json.key) : null,
      events: isMap(json.events) ? json.events : null,
      style: null
    };
  }
  function classesOf(node) {
    const cn = node.props.className;
    if (typeof cn === "string") return cn.split(/\s+/).filter((c) => c !== "");
    if (Array.isArray(cn)) return cn.map((c) => String(c));
    return null;
  }
  function textOf(node) {
    var _a;
    const t = (_a = node.props.text) != null ? _a : node.props.data;
    return t == null ? "" : String(t);
  }

  // core/src/render/text-style.ts
  function mergeTextStyle(base, over) {
    if (!base) return __spreadValues({}, over != null ? over : {});
    if (!over) return __spreadValues({}, base);
    const out = __spreadValues({}, base);
    for (const [k, v] of Object.entries(over)) {
      if (v !== void 0 && v !== null) out[k] = v;
    }
    if (over.height != null) out.heightPx = null;
    if (over.heightPx != null) out.height = null;
    return out;
  }
  var DEFAULT_TEXT_STYLE = {
    color: M3.onSurface,
    fontSize: 14,
    fontWeight: 400,
    italic: false,
    fontFamily: null,
    letterSpacing: 0.25,
    wordSpacing: 0,
    height: 20 / 14,
    decoration: 0
  };
  var LABEL_LARGE = { fontSize: 14, fontWeight: 500, letterSpacing: 0.1, height: 20 / 14 };
  var TITLE_LARGE = { fontSize: 22, fontWeight: 400, letterSpacing: 0, height: 28 / 22 };
  var BODY_LARGE = { fontSize: 16, fontWeight: 400, letterSpacing: 0.5, height: 24 / 16 };
  var LABEL_SMALL = { fontSize: 11, fontWeight: 500, letterSpacing: 0.5, height: 16 / 11 };
  var SERIF = /* @__PURE__ */ new Set([
    "serif",
    "georgia",
    "times",
    "times new roman",
    "cambria",
    "garamond",
    "cinzel",
    "playfair display",
    "merriweather",
    "crimson",
    "crimson pro",
    "pt serif",
    "noto serif",
    "liberation serif",
    "roboto serif"
  ]);
  var MONO = /* @__PURE__ */ new Set([
    "monospace",
    "courier",
    "courier new",
    "consolas",
    "menlo",
    "monaco",
    "roboto mono",
    "sf mono",
    "source code pro",
    "fira code",
    "jetbrains mono",
    "liberation mono",
    "ui-monospace"
  ]);
  var SANS = /* @__PURE__ */ new Set([
    "sans-serif",
    "arial",
    "helvetica",
    "helvetica neue",
    "roboto",
    "inter",
    "segoe ui",
    "verdana",
    "tahoma",
    "noto sans",
    "liberation sans",
    "ubuntu"
  ]);
  function resolveFontFamily(family) {
    if (!family) return null;
    if (family === "icons") return "icons";
    for (const raw of family.split(",")) {
      const name = raw.trim().replace(/^['"]|['"]$/g, "").toLowerCase();
      if (name === "") continue;
      if (SERIF.has(name) || name.includes("serif") && !name.includes("sans")) return "serif";
      if (MONO.has(name) || name.includes("mono")) return "monospace";
      if (SANS.has(name) || name.includes("sans") || name === "system-ui" || name.startsWith("-apple") || name === "ui-sans-serif") {
        return null;
      }
      if (name === "material icons" || name === "materialicons") return "icons";
      return raw.trim().replace(/^['"]|['"]$/g, "");
    }
    return null;
  }
  var DECO_UNDERLINE = 1;
  var DECO_OVERLINE = 2;
  var DECO_LINE_THROUGH = 4;
  var Decoration = { underline: DECO_UNDERLINE, overline: DECO_OVERLINE, lineThrough: DECO_LINE_THROUGH };
  function textStyleFromCss(style) {
    var _a;
    if (!style) return null;
    const t = {};
    if (style.color != null) t.color = style.color;
    if (style.fontSize != null) t.fontSize = style.fontSize;
    if (style.fontWeight != null) t.fontWeight = style.fontWeight;
    if (style.fontStyle != null) t.italic = style.fontStyle === "italic";
    if (style.fontFamily != null) t.fontFamily = (_a = resolveFontFamily(style.fontFamily)) != null ? _a : "";
    if (style.letterSpacing != null) t.letterSpacing = style.letterSpacing;
    if (style.wordSpacing != null) t.wordSpacing = style.wordSpacing;
    if (style.lineHeight != null) t.height = style.lineHeight;
    if (style.lineHeightPx != null) t.heightPx = style.lineHeightPx;
    if (style.textDecoration != null) {
      const d = style.textDecoration;
      t.decoration = (d.underline ? DECO_UNDERLINE : 0) | (d.overline ? DECO_OVERLINE : 0) | (d.lineThrough ? DECO_LINE_THROUGH : 0);
    }
    if (style.textDecorationColor != null) t.decorationColor = style.textDecorationColor;
    if (style.textDecorationStyle != null) t.decorationStyle = style.textDecorationStyle;
    if (style.textDecorationThickness != null) t.decorationThickness = style.textDecorationThickness;
    if (style.textShadow != null) t.shadows = style.textShadow;
    if (style.textTransform != null) t.textTransform = style.textTransform;
    return t;
  }
  function toSpec(style, textScale = 1) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j, _k, _l, _m, _n;
    const merged = mergeTextStyle(DEFAULT_TEXT_STYLE, style);
    const fontSize = ((_a = merged.fontSize) != null ? _a : 14) * textScale;
    let height = (_b = merged.height) != null ? _b : null;
    if (merged.heightPx != null && fontSize > 0) height = merged.heightPx * textScale / fontSize;
    return {
      color: (_c = merged.color) != null ? _c : M3.onSurface,
      fontSize,
      fontWeight: (_d = merged.fontWeight) != null ? _d : 400,
      italic: !!merged.italic,
      fontFamily: merged.fontFamily === "" ? null : (_e = merged.fontFamily) != null ? _e : null,
      letterSpacing: (_f = merged.letterSpacing) != null ? _f : 0,
      wordSpacing: (_g = merged.wordSpacing) != null ? _g : 0,
      height,
      decoration: (_h = merged.decoration) != null ? _h : 0,
      decorationColor: (_i = merged.decorationColor) != null ? _i : null,
      decorationStyle: (_j = merged.decorationStyle) != null ? _j : null,
      decorationThickness: (_k = merged.decorationThickness) != null ? _k : null,
      shadows: (_l = merged.shadows) != null ? _l : null,
      background: (_m = merged.background) != null ? _m : null,
      baselineShift: (_n = merged.baselineShift) != null ? _n : 0
    };
  }
  function applyTextTransform(text2, transform) {
    switch (transform) {
      case "uppercase":
        return text2.toUpperCase();
      case "lowercase":
        return text2.toLowerCase();
      case "capitalize":
        return text2.replace(new RegExp(`(^|\\s|[-(\\["'])(\\p{L})`, "gu"), (_m, pre, ch) => pre + ch.toUpperCase());
      default:
        return text2;
    }
  }

  // core/src/widgets/style.ts
  var SHRINK = w("constrained", { width: 0, height: 0 });
  function sizedBox(width, height, child) {
    return w("constrained", { width, height }, child != null ? child : null);
  }
  function padding(insets, child, percent) {
    return w("padding", { padding: insets, percent: percent != null ? percent : null }, child);
  }
  function align(alignment, child, factors) {
    var _a, _b;
    return w("align", { alignment, widthFactor: (_a = factors == null ? void 0 : factors.widthFactor) != null ? _a : null, heightFactor: (_b = factors == null ? void 0 : factors.heightFactor) != null ? _b : null }, child);
  }
  function center(child) {
    return align({ x: 0, y: 0 }, child);
  }
  function column(children, opts = {}) {
    return w("flex", __spreadValues({ direction: "column", mainAxisAlignment: "start", crossAxisAlignment: "center", mainAxisSize: "max" }, opts), children);
  }
  function row(children, opts = {}) {
    return w("flex", __spreadValues({ direction: "row", mainAxisAlignment: "start", crossAxisAlignment: "center", mainAxisSize: "max" }, opts), children);
  }
  function expanded(child, flex = 1) {
    return w("flexible", { flex, fit: "tight" }, child);
  }
  function text(value, style, opts = {}) {
    return w("text", __spreadValues({ text: value, style: style != null ? style : null }, opts));
  }
  function decorated(decoration, child) {
    return w("decorated", { decoration }, child);
  }
  var ELEVATION_SHADOWS = {
    0: [],
    1: [
      { dx: 0, dy: 2, blur: 1, spread: -1, color: 855638016 },
      { dx: 0, dy: 1, blur: 1, spread: 0, color: 603979776 },
      { dx: 0, dy: 1, blur: 3, spread: 0, color: 520093696 }
    ],
    2: [
      { dx: 0, dy: 3, blur: 1, spread: -2, color: 855638016 },
      { dx: 0, dy: 2, blur: 2, spread: 0, color: 603979776 },
      { dx: 0, dy: 1, blur: 5, spread: 0, color: 520093696 }
    ],
    3: [
      { dx: 0, dy: 3, blur: 3, spread: -2, color: 855638016 },
      { dx: 0, dy: 3, blur: 4, spread: 0, color: 603979776 },
      { dx: 0, dy: 1, blur: 8, spread: 0, color: 520093696 }
    ],
    4: [
      { dx: 0, dy: 2, blur: 4, spread: -1, color: 855638016 },
      { dx: 0, dy: 4, blur: 5, spread: 0, color: 603979776 },
      { dx: 0, dy: 1, blur: 10, spread: 0, color: 520093696 }
    ],
    6: [
      { dx: 0, dy: 3, blur: 5, spread: -1, color: 855638016 },
      { dx: 0, dy: 6, blur: 10, spread: 0, color: 603979776 },
      { dx: 0, dy: 1, blur: 18, spread: 0, color: 520093696 }
    ],
    8: [
      { dx: 0, dy: 5, blur: 5, spread: -3, color: 855638016 },
      { dx: 0, dy: 8, blur: 10, spread: 1, color: 603979776 },
      { dx: 0, dy: 3, blur: 14, spread: 2, color: 520093696 }
    ],
    12: [
      { dx: 0, dy: 7, blur: 8, spread: -4, color: 855638016 },
      { dx: 0, dy: 12, blur: 17, spread: 2, color: 603979776 },
      { dx: 0, dy: 5, blur: 22, spread: 4, color: 520093696 }
    ],
    16: [
      { dx: 0, dy: 8, blur: 10, spread: -5, color: 855638016 },
      { dx: 0, dy: 16, blur: 24, spread: 2, color: 603979776 },
      { dx: 0, dy: 6, blur: 30, spread: 5, color: 520093696 }
    ],
    24: [
      { dx: 0, dy: 11, blur: 15, spread: -7, color: 855638016 },
      { dx: 0, dy: 24, blur: 38, spread: 3, color: 603979776 },
      { dx: 0, dy: 9, blur: 46, spread: 8, color: 520093696 }
    ]
  };
  function elevationShadows(elevation) {
    if (elevation <= 0) return [];
    const keys = Object.keys(ELEVATION_SHADOWS).map(Number);
    let best = keys[0];
    for (const k of keys) if (Math.abs(k - elevation) < Math.abs(best - elevation)) best = k;
    return ELEVATION_SHADOWS[best];
  }
  function decorationFromStyle(style, ctx) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j, _k, _l, _m, _n, _o;
    const gradients = [];
    if (style.gradientLayers) gradients.push(...[...style.gradientLayers].reverse());
    if (style.gradient) gradients.push(style.gradient);
    let border = (_a = style.border) != null ? _a : null;
    if (!border && style.borderWidth != null && (style.borderColor != null || style.borderStyle && style.borderStyle !== "none")) {
      border = borderAll({
        width: style.borderWidth,
        color: (_c = (_b = style.borderColor) != null ? _b : style.color) != null ? _c : 4278190080,
        style: style.borderStyle && style.borderStyle !== "solid" ? style.borderStyle : "solid"
      });
    }
    const image = style.backgroundImage ? {
      src: ctx ? ctx.engine.resolveUrl(style.backgroundImage) : style.backgroundImage,
      fit: (_d = style.backgroundSize) != null ? _d : null,
      alignment: (_e = style.backgroundPosition) != null ? _e : null,
      repeat: (_f = style.backgroundRepeat) != null ? _f : null,
      size: (_g = style.backgroundSizePx) != null ? _g : null
    } : null;
    return {
      color: (_h = style.backgroundColor) != null ? _h : null,
      gradients: gradients.length ? gradients : null,
      image,
      border,
      radius: (_i = style.borderRadius) != null ? _i : null,
      radiusPercent: (_j = style.borderRadiusPercent) != null ? _j : null,
      shape: (_k = style.shape) != null ? _k : null,
      shadows: style.boxShadow && style.boxShadow.length ? style.boxShadow : null,
      outline: style.outlineWidth != null && style.outlineWidth > 0 && style.outlineStyle !== "none" ? { width: style.outlineWidth, color: (_m = (_l = style.outlineColor) != null ? _l : style.color) != null ? _m : 4278190080, style: (_n = style.outlineStyle) != null ? _n : "solid", offset: (_o = style.outlineOffset) != null ? _o : 0 } : null
    };
  }
  function needsContainer(style) {
    return style.padding != null || style.paddingPercent != null || style.backgroundColor != null || style.gradient != null || style.border != null || style.borderRadius != null || style.borderRadiusPercent != null || style.boxShadow != null || style.borderColor != null || style.backgroundImage != null || style.shape === "circle" || style.outlineWidth != null && style.outlineWidth > 0;
  }
  function clips(o) {
    return o === "hidden" || o === "clip";
  }
  function flexSingleChildAlignment(style) {
    const isColumn = style.flexDirection === "column" || style.flexDirection === "column-reverse";
    const factor = (v) => {
      switch ((v != null ? v : "").toLowerCase()) {
        case "center":
          return 0;
        case "flex-end":
        case "end":
          return 1;
        default:
          return -1;
      }
    };
    const main = factor(style.justifyContent);
    const cross = factor(style.alignItems);
    return isColumn ? { x: cross, y: main } : { x: main, y: cross };
  }
  function styleTransform(style) {
    var _a, _b, _c;
    if (style.transform == null && style.rotate == null && style.scale == null && style.translate == null && style.scaleX == null && style.scaleY == null) {
      return null;
    }
    let m = (_a = style.transform) != null ? _a : identity();
    if (style.rotate != null) m = rotationZ(style.rotate * Math.PI / 180);
    if (style.scale != null) m = scaling(style.scale, style.scale, 1);
    if (style.scaleX != null || style.scaleY != null) m = multiply(m, scaling((_b = style.scaleX) != null ? _b : 1, (_c = style.scaleY) != null ? _c : 1, 1));
    if (style.translate) m = multiply(translation(style.translate.dx, style.translate.dy), m);
    return m;
  }
  function applyStyle(child, style, opts = {}, ctx) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j, _k, _l, _m, _n, _o, _p, _q, _r, _s, _t, _u, _v, _w, _x, _y, _z, _A, _B, _C, _D, _E, _F, _G, _H;
    if (!style) return child;
    const applyFlex = (_a = opts.applyFlex) != null ? _a : true;
    const animated = style.transitionDuration != null && style.transitionDuration > 0;
    const dur = (_b = style.transitionDuration) != null ? _b : 0;
    const curve = (_c = style.transitionCurve) != null ? _c : null;
    let result = child;
    if (!opts.layoutHandled && (style.display === "flex" || style.display === "inline-flex") && style.width != null && style.height != null) {
      const a = flexSingleChildAlignment(style);
      if (a.x !== -1 || a.y !== -1) result = align(a, result);
    }
    if (style.opacity != null && (style.opacity < 1 || animated)) {
      result = animated ? w("animatedOpacity", { opacity: style.opacity, duration: dur, curve }, result) : w("opacity", { opacity: style.opacity }, result);
    }
    const matrix = styleTransform(style);
    if (matrix) {
      result = animated ? w("animatedTransform", { transform: matrix, alignment: (_d = style.transformOrigin) != null ? _d : { x: 0, y: 0 }, duration: dur, curve }, result) : w("transform", { transform: matrix, alignment: (_e = style.transformOrigin) != null ? _e : { x: 0, y: 0 } }, result);
    }
    if (style.filter || style.backdropFilter || style.mixBlendMode) {
      result = w("filter", { filter: (_f = style.filter) != null ? _f : null, backdrop: (_g = style.backdropFilter) != null ? _g : null, blendMode: (_h = style.mixBlendMode) != null ? _h : null }, result);
    }
    if (style.visible === false) result = w("visibility", { mode: "gone" }, result);
    else if (style.visibility === "hidden" || style.visibility === "collapse") result = w("visibility", { mode: "hidden" }, result);
    if (style.alignment) {
      result = animated ? w("animatedAlign", { alignment: style.alignment, duration: dur, curve }, result) : align(style.alignment, result);
    }
    const overflowX = (_j = (_i = style.overflowX) != null ? _i : style.overflow) != null ? _j : null;
    const overflowY = (_l = (_k = style.overflowY) != null ? _k : style.overflow) != null ? _l : null;
    const boundedW = style.width != null || style.maxWidth != null || style.widthFactor != null;
    const boundedH = style.height != null || style.maxHeight != null || style.heightFactor != null;
    const scrollY = overflowY === "scroll" && boundedH;
    const scrollX = overflowX === "scroll" && boundedW;
    if (scrollY || scrollX) {
      result = w("scroll", { axis: scrollY && scrollX ? "both" : scrollY ? "vertical" : "horizontal" }, result);
    } else if (clips(overflowX) || clips(overflowY) || overflowX === "scroll" || overflowY === "scroll") {
      result = w(
        "clip",
        { radius: (_m = style.borderRadius) != null ? _m : null, oval: style.shape === "circle" },
        result
      );
    }
    if (style.aspectRatio != null && !(style.width != null && style.height != null)) {
      result = w("aspectRatio", { aspectRatio: style.aspectRatio }, result);
    }
    const wf = (_n = style.widthFactor) != null ? _n : null;
    const hf = (_o = style.heightFactor) != null ? _o : null;
    const fixedWidth = wf == null ? (_p = style.width) != null ? _p : null : null;
    const fixedHeight = hf == null ? (_q = style.height) != null ? _q : null : null;
    if (fixedWidth != null || fixedHeight != null || style.minWidth != null || style.maxWidth != null || style.minHeight != null || style.maxHeight != null) {
      const sized = { width: fixedWidth, height: fixedHeight };
      const inner = fixedWidth != null || fixedHeight != null ? animated ? w("animatedConstrained", __spreadProps(__spreadValues({}, sized), { duration: dur, curve }), result) : w("constrained", sized, result) : result;
      result = w(
        "constrained",
        { minWidth: (_r = style.minWidth) != null ? _r : 0, maxWidth: (_s = style.maxWidth) != null ? _s : null, minHeight: (_t = style.minHeight) != null ? _t : 0, maxHeight: (_u = style.maxHeight) != null ? _u : null },
        inner
      );
    }
    if (needsContainer(style)) {
      const decoration = decorationFromStyle(style, ctx);
      const insets = borderInsets(decoration.border);
      const pad = (_v = style.padding) != null ? _v : { top: 0, right: 0, bottom: 0, left: 0 };
      const effective = { top: pad.top + insets.top, right: pad.right + insets.right, bottom: pad.bottom + insets.bottom, left: pad.left + insets.left };
      if (effective.top || effective.right || effective.bottom || effective.left || style.paddingPercent) {
        result = animated ? w("animatedPadding", { padding: effective, percent: (_w = style.paddingPercent) != null ? _w : null, duration: dur, curve }, result) : padding(effective, result, style.paddingPercent);
      }
      const hasPaint = decoration.color != null || decoration.gradients || decoration.image || decoration.border || decoration.shadows || decoration.outline || decoration.radius || decoration.radiusPercent || decoration.shape === "circle";
      if (hasPaint) {
        result = animated ? w("animatedDecorated", { decoration, duration: dur, curve }, result) : decorated(decoration, result);
      }
    }
    if (style.animationName && ctx) {
      const frames = (_x = style.keyframes) != null ? _x : ctx.engine.services.stylesheets.keyframes(style.animationName);
      if (frames && frames.length) {
        result = w(
          "keyframes",
          {
            frames,
            duration: (_y = style.animationDuration) != null ? _y : 1e3,
            delay: (_z = style.animationDelay) != null ? _z : 0,
            iterations: (_A = style.animationIterationCount) != null ? _A : 1,
            direction: (_B = style.animationDirection) != null ? _B : "normal",
            fillMode: (_C = style.animationFillMode) != null ? _C : "none",
            timing: (_D = style.animationTimingFunction) != null ? _D : "ease",
            playState: (_E = style.animationPlayState) != null ? _E : "running"
          },
          result
        );
      }
    }
    if (style.margin || style.marginPercent) {
      const m = (_F = style.margin) != null ? _F : { top: 0, right: 0, bottom: 0, left: 0 };
      if (m.top || m.right || m.bottom || m.left || style.marginPercent) result = padding(m, result, style.marginPercent);
    }
    if (style.marginAuto && (style.marginAuto.left || style.marginAuto.right)) {
      const ax = style.marginAuto.left && style.marginAuto.right ? 0 : style.marginAuto.left ? 1 : -1;
      result = w("align", { alignment: { x: ax, y: -1 }, heightFactor: 1 }, result);
    }
    if (wf != null || hf != null) {
      result = w(
        "fractional",
        { widthFactor: wf, heightFactor: hf, alignment: { x: -1, y: 0 }, fallbackWidth: wf != null ? (_G = style.width) != null ? _G : null : null, fallbackHeight: hf != null ? (_H = style.height) != null ? _H : null : null },
        result
      );
    }
    if (style.pointerEvents === "none") result = w("ignorePointer", { ignoring: true }, result);
    if (applyFlex) result = wrapFlex(result, style);
    return result;
  }
  function wrapFlex(child, style) {
    var _a, _b, _c, _d;
    if (!style) return child;
    const grow = (_b = (_a = style.flex) != null ? _a : style.flexGrow) != null ? _b : null;
    const basis = parseBasis(style.flexBasis);
    if (grow != null && grow > 0) {
      return w("flexible", { flex: grow, fit: "tight", shrink: (_c = style.flexShrink) != null ? _c : 1, alignSelf: alignSelfOf(style), basis }, child);
    }
    if (style.flexShrink != null || style.alignSelf != null || basis != null) {
      return w("flexible", { flex: 0, fit: "loose", shrink: (_d = style.flexShrink) != null ? _d : 1, alignSelf: alignSelfOf(style), basis }, child);
    }
    return child;
  }
  function parseBasis(basis) {
    if (!basis || basis === "auto" || basis === "content") return null;
    const n = parseFloat(basis);
    if (!Number.isFinite(n) || basis.trim().endsWith("%")) return null;
    return n;
  }
  function alignSelfOf(style) {
    var _a;
    switch (((_a = style.alignSelf) != null ? _a : "").toLowerCase()) {
      case "center":
        return "center";
      case "flex-end":
      case "end":
        return "end";
      case "flex-start":
      case "start":
        return "start";
      case "stretch":
        return "stretch";
      case "baseline":
        return "baseline";
      default:
        return null;
    }
  }
  function createTextStyle(style) {
    return textStyleFromCss(style);
  }
  function textOptionsFromStyle(style) {
    var _a;
    if (!style) return {};
    const out = {};
    if (style.textAlign) out.align = style.textAlign;
    if (style.textOverflow) out.overflow = style.textOverflow;
    if (style.whiteSpace === "nowrap" || style.whiteSpace === "pre") {
      out.softWrap = false;
      if (style.whiteSpace === "nowrap") out.maxLines = 1;
    }
    if (style.lineClamp != null && style.lineClamp > 0) {
      out.maxLines = style.lineClamp;
      out.overflow = (_a = out.overflow) != null ? _a : "ellipsis";
    }
    return out;
  }
  function container(opts) {
    var _a, _b, _c, _d, _e, _f, _g;
    let current2 = (_a = opts.child) != null ? _a : null;
    const tightW = opts.width != null;
    const tightH = opts.height != null;
    if (!current2 && !(tightW && tightH)) {
      current2 = w("limited", { maxWidth: 0, maxHeight: 0 }, w("constrained", { minWidth: Number.POSITIVE_INFINITY, minHeight: Number.POSITIVE_INFINITY }));
    }
    if (opts.alignment) current2 = align(opts.alignment, current2);
    const borderPad = borderInsets((_b = opts.decoration) == null ? void 0 : _b.border);
    const p = (_c = opts.padding) != null ? _c : { top: 0, right: 0, bottom: 0, left: 0 };
    const eff = { top: p.top + borderPad.top, right: p.right + borderPad.right, bottom: p.bottom + borderPad.bottom, left: p.left + borderPad.left };
    if (eff.top || eff.right || eff.bottom || eff.left) current2 = padding(eff, current2);
    if (opts.decoration) current2 = decorated(opts.decoration, current2);
    if (opts.width != null || opts.height != null || opts.minWidth != null || opts.minHeight != null) {
      current2 = w("constrained", { width: (_d = opts.width) != null ? _d : null, height: (_e = opts.height) != null ? _e : null, minWidth: (_f = opts.minWidth) != null ? _f : 0, minHeight: (_g = opts.minHeight) != null ? _g : 0 }, current2);
    }
    if (opts.margin) current2 = padding(opts.margin, current2);
    return current2;
  }

  // core/src/widgets/animation.ts
  var ZERO = { top: 0, right: 0, bottom: 0, left: 0 };
  function only(children) {
    return children.length ? children[0] : null;
  }
  var animationWidgets = {
    // --------------------------------------------------------------------------
    // Implicit
    // --------------------------------------------------------------------------
    AnimatedContainer(node, children) {
      var _a, _b, _c, _d, _e, _f, _g;
      const s = node.style;
      const duration = (_a = s == null ? void 0 : s.transitionDuration) != null ? _a : 200;
      const curve = (_b = s == null ? void 0 : s.transitionCurve) != null ? _b : null;
      let current2 = only(children);
      if ((s == null ? void 0 : s.padding) || current2) current2 = w("animatedPadding", { padding: (_c = s == null ? void 0 : s.padding) != null ? _c : ZERO, duration, curve }, current2 != null ? current2 : SHRINK);
      current2 = w("animatedDecorated", { decoration: { color: (_d = s == null ? void 0 : s.backgroundColor) != null ? _d : null, radius: (_e = s == null ? void 0 : s.borderRadius) != null ? _e : null }, duration, curve }, current2 != null ? current2 : null);
      current2 = w("animatedConstrained", { width: (_f = s == null ? void 0 : s.width) != null ? _f : null, height: (_g = s == null ? void 0 : s.height) != null ? _g : null, duration, curve }, current2);
      if (s == null ? void 0 : s.margin) current2 = w("animatedPadding", { padding: s.margin, duration, curve }, current2);
      return current2;
    },
    AnimatedOpacity(node, children) {
      var _a, _b, _c, _d;
      return w("animatedOpacity", { opacity: (_b = (_a = node.style) == null ? void 0 : _a.opacity) != null ? _b : 1, duration: (_d = (_c = node.style) == null ? void 0 : _c.transitionDuration) != null ? _d : 200 }, only(children));
    },
    AnimatedCrossFade(node, children) {
      var _a, _b, _c, _d;
      const s = node.style;
      const curve = (_a = s == null ? void 0 : s.transitionCurve) != null ? _a : null;
      const first2 = (_b = children[0]) != null ? _b : SHRINK;
      const second = (_c = children[1]) != null ? _c : SHRINK;
      return w(
        "animatedCrossFade",
        { showFirst: node.props.showFirst !== false, duration: (_d = s == null ? void 0 : s.transitionDuration) != null ? _d : 300, curve },
        [w("opacity", { opacity: 1 }, first2, "first"), w("opacity", { opacity: 0 }, second, "second")]
      );
    },
    AnimatedSwitcher(node, children) {
      var _a, _b, _c, _d, _e;
      return w(
        "animatedSwitcher",
        { duration: (_b = (_a = node.style) == null ? void 0 : _a.transitionDuration) != null ? _b : 300, transitionType: String((_c = node.props.transitionType) != null ? _c : "fade"), curve: (_e = (_d = node.style) == null ? void 0 : _d.transitionCurve) != null ? _e : null },
        children.length ? [children[0]] : []
      );
    },
    AnimatedAlign(node, children) {
      var _a, _b, _c, _d;
      const s = node.style;
      return w(
        "animatedAlign",
        { alignment: (_b = (_a = s == null ? void 0 : s.alignmentEnd) != null ? _a : s == null ? void 0 : s.alignment) != null ? _b : { x: 0, y: 0 }, duration: (_c = s == null ? void 0 : s.transitionDuration) != null ? _c : 300, curve: (_d = s == null ? void 0 : s.transitionCurve) != null ? _d : null },
        only(children)
      );
    },
    AnimatedPadding(node, children) {
      var _a, _b, _c;
      const s = node.style;
      return w("animatedPadding", { padding: (_a = s == null ? void 0 : s.padding) != null ? _a : ZERO, duration: (_b = s == null ? void 0 : s.transitionDuration) != null ? _b : 300, curve: (_c = s == null ? void 0 : s.transitionCurve) != null ? _c : null }, only(children));
    },
    AnimatedPositioned(node, children) {
      var _a, _b, _c, _d, _e, _f, _g, _h, _i;
      const s = node.style;
      return w(
        "animatedPositioned",
        {
          top: (_a = s == null ? void 0 : s.top) != null ? _a : null,
          right: (_b = s == null ? void 0 : s.right) != null ? _b : null,
          bottom: (_c = s == null ? void 0 : s.bottom) != null ? _c : null,
          left: (_d = s == null ? void 0 : s.left) != null ? _d : null,
          width: (_e = s == null ? void 0 : s.width) != null ? _e : null,
          height: (_f = s == null ? void 0 : s.height) != null ? _f : null,
          duration: (_g = s == null ? void 0 : s.transitionDuration) != null ? _g : 300,
          curve: (_h = s == null ? void 0 : s.transitionCurve) != null ? _h : null
        },
        (_i = only(children)) != null ? _i : SHRINK
      );
    },
    AnimatedScale(node, children) {
      var _a, _b, _c;
      const s = node.style;
      return w("animatedTransform", { scale: (_a = s == null ? void 0 : s.scale) != null ? _a : 1, alignment: { x: 0, y: 0 }, duration: (_b = s == null ? void 0 : s.transitionDuration) != null ? _b : 300, curve: (_c = s == null ? void 0 : s.transitionCurve) != null ? _c : null }, only(children));
    },
    AnimatedRotation(node, children) {
      var _a, _b, _c;
      const s = node.style;
      return w("animatedTransform", { turns: ((_a = s == null ? void 0 : s.rotate) != null ? _a : 0) / 360, alignment: { x: 0, y: 0 }, duration: (_b = s == null ? void 0 : s.transitionDuration) != null ? _b : 300, curve: (_c = s == null ? void 0 : s.transitionCurve) != null ? _c : null }, only(children));
    },
    AnimatedSlide(node, children) {
      var _a, _b, _c;
      const s = node.style;
      const o = (_a = s == null ? void 0 : s.slideEnd) != null ? _a : { dx: 0, dy: 0 };
      return w("animatedTransform", { slide: [o.dx, o.dy], alignment: { x: -1, y: -1 }, duration: (_b = s == null ? void 0 : s.transitionDuration) != null ? _b : 300, curve: (_c = s == null ? void 0 : s.transitionCurve) != null ? _c : null }, only(children));
    },
    AnimatedSize(node, children) {
      var _a, _b;
      const s = node.style;
      return w("animatedSize", { duration: (_a = s == null ? void 0 : s.transitionDuration) != null ? _a : 300, curve: (_b = s == null ? void 0 : s.transitionCurve) != null ? _b : null, alignment: { x: 0, y: 0 } }, only(children));
    },
    AnimatedDefaultTextStyle(node, children) {
      var _a, _b, _c, _d;
      const s = node.style;
      return w("animatedDefaultTextStyle", { style: (_a = createTextStyle(s)) != null ? _a : {}, duration: (_b = s == null ? void 0 : s.transitionDuration) != null ? _b : 300, curve: (_c = s == null ? void 0 : s.transitionCurve) != null ? _c : null }, (_d = only(children)) != null ? _d : SHRINK);
    },
    // --------------------------------------------------------------------------
    // Explicit
    // --------------------------------------------------------------------------
    FadeTransition(node, children) {
      var _a, _b, _c;
      const s = node.style;
      return transition("fade", node.style, (_a = s == null ? void 0 : s.fadeBegin) != null ? _a : 0, (_b = s == null ? void 0 : s.fadeEnd) != null ? _b : 1, (_c = only(children)) != null ? _c : w("constrained", {}));
    },
    SlideTransition(node, children) {
      var _a, _b, _c;
      const s = node.style;
      const b = (_a = s == null ? void 0 : s.slideBegin) != null ? _a : { dx: -1, dy: 0 };
      const e = (_b = s == null ? void 0 : s.slideEnd) != null ? _b : { dx: 0, dy: 0 };
      return transition("slide", s, [b.dx, b.dy], [e.dx, e.dy], (_c = only(children)) != null ? _c : w("constrained", {}));
    },
    ScaleTransition(node, children) {
      var _a, _b, _c;
      const s = node.style;
      return transition("scale", s, (_a = s == null ? void 0 : s.scaleBegin) != null ? _a : 0, (_b = s == null ? void 0 : s.scaleEnd) != null ? _b : 1, (_c = only(children)) != null ? _c : w("constrained", {}));
    },
    RotationTransition(node, children) {
      var _a, _b, _c;
      const s = node.style;
      return transition("rotation", s, (_a = s == null ? void 0 : s.rotationBegin) != null ? _a : 0, (_b = s == null ? void 0 : s.rotationEnd) != null ? _b : 1, (_c = only(children)) != null ? _c : w("constrained", {}));
    },
    SizeTransition(node, children) {
      var _a, _b, _c;
      const s = node.style;
      const t = transition("size", s, (_a = s == null ? void 0 : s.animationFrom) != null ? _a : 0, (_b = s == null ? void 0 : s.animationTo) != null ? _b : 1, (_c = only(children)) != null ? _c : w("constrained", {}));
      t.p.axis = node.props.axis === "horizontal" ? "horizontal" : "vertical";
      return t;
    },
    // --------------------------------------------------------------------------
    // Custom
    // --------------------------------------------------------------------------
    TweenAnimationBuilder(node, children) {
      var _a, _b, _c, _d, _e, _f, _g;
      const s = node.style;
      return w(
        "transition",
        {
          kind: "tween",
          tweenType: String((_a = node.props.tweenType) != null ? _a : "opacity"),
          begin: (_b = s == null ? void 0 : s.animationFrom) != null ? _b : 0,
          end: (_c = s == null ? void 0 : s.animationTo) != null ? _c : 1,
          duration: (_e = (_d = s == null ? void 0 : s.animationDuration) != null ? _d : s == null ? void 0 : s.transitionDuration) != null ? _e : 300,
          curve: (_f = s == null ? void 0 : s.transitionCurve) != null ? _f : null
        },
        (_g = only(children)) != null ? _g : w("constrained", {})
      );
    },
    StaggeredAnimation(node, children) {
      var _a, _b, _c;
      const s = node.style;
      return w(
        "staggered",
        { duration: (_a = s == null ? void 0 : s.animationDuration) != null ? _a : 1e3, staggerDelay: (_b = s == null ? void 0 : s.staggerDelay) != null ? _b : 100, curve: (_c = s == null ? void 0 : s.transitionCurve) != null ? _c : "easeOut" },
        children.map((c, i) => {
          var _a2;
          return w("staggerItem", {}, c, (_a2 = c.k) != null ? _a2 : `stagger-${i}`);
        })
      );
    },
    Shimmer(node, children) {
      var _a, _b, _c, _d, _e, _f, _g;
      const s = node.style;
      const child = (_d = only(children)) != null ? _d : (
        // Flutter's placeholder bar: a sized box with a rounded (transparent)
        // decoration; the mask paints the sweep onto it.
        w("constrained", { width: (_a = s == null ? void 0 : s.width) != null ? _a : 200, height: (_b = s == null ? void 0 : s.height) != null ? _b : 20 }, w("decorated", { decoration: { color: M3.surfaceContainerHighest, radius: (_c = s == null ? void 0 : s.borderRadius) != null ? _c : radiusAll(4) } }))
      );
      return w(
        "shimmer",
        { duration: (_e = s == null ? void 0 : s.animationDuration) != null ? _e : 1500, baseColor: (_f = s == null ? void 0 : s.shimmerBaseColor) != null ? _f : 4292927712, highlightColor: (_g = s == null ? void 0 : s.shimmerHighlightColor) != null ? _g : 4294309365, blendMode: "srcATop" },
        child
      );
    },
    Pulse(node, children) {
      var _a, _b, _c, _d, _e;
      const s = node.style;
      return w(
        "transition",
        { kind: "pulse", begin: (_a = s == null ? void 0 : s.scaleBegin) != null ? _a : 1, end: (_b = s == null ? void 0 : s.scaleEnd) != null ? _b : 1.05, duration: (_c = s == null ? void 0 : s.animationDuration) != null ? _c : 1e3, curve: (_d = s == null ? void 0 : s.transitionCurve) != null ? _d : "easeInOut" },
        (_e = only(children)) != null ? _e : w("constrained", {})
      );
    },
    AnimatedGradient(node, children) {
      var _a, _b, _c, _d, _e;
      const s = node.style;
      const gradient = w(
        "animatedGradient",
        {
          duration: (_a = s == null ? void 0 : s.animationDuration) != null ? _a : 2e3,
          colors: (_b = s == null ? void 0 : s.gradientColors) != null ? _b : [4280391411, 4288423856, 4293467747, 4280391411],
          decoration: { radius: (_c = s == null ? void 0 : s.borderRadius) != null ? _c : null }
        },
        only(children)
      );
      if ((s == null ? void 0 : s.width) != null || (s == null ? void 0 : s.height) != null) return w("constrained", { width: (_d = s == null ? void 0 : s.width) != null ? _d : null, height: (_e = s == null ? void 0 : s.height) != null ? _e : null }, gradient);
      return children.length ? gradient : w("limited", { maxWidth: 0, maxHeight: 0 }, w("constrained", { minWidth: Number.POSITIVE_INFINITY, minHeight: Number.POSITIVE_INFINITY }, gradient));
    }
  };
  function transition(kind, s, begin, end, child) {
    var _a, _b, _c, _d, _e;
    return w(
      "transition",
      {
        kind,
        begin,
        end,
        duration: (_b = (_a = s == null ? void 0 : s.animationDuration) != null ? _a : s == null ? void 0 : s.transitionDuration) != null ? _b : 300,
        curve: (_c = s == null ? void 0 : s.transitionCurve) != null ? _c : null,
        repeat: (_d = s == null ? void 0 : s.animationRepeat) != null ? _d : false,
        autoReverse: (_e = s == null ? void 0 : s.animationAutoReverse) != null ? _e : false
      },
      child
    );
  }

  // core/src/widgets/icons.ts
  var MATERIAL_ICON_CODEPOINTS = {
    // Flutter `Icons.copy` is the content_copy glyph.
    copy: 57677,
    "10k": 59729,
    "10mp": 59730,
    "11mp": 59731,
    "123": 60301,
    "12mp": 59732,
    "13mp": 59733,
    "14mp": 59734,
    "15mp": 59735,
    "16mp": 59736,
    "17mp": 59737,
    "18_up_rating": 63741,
    "18mp": 59738,
    "19mp": 59739,
    "1k": 59740,
    "1k_plus": 59741,
    "1x_mobiledata": 61389,
    "20mp": 59742,
    "21mp": 59743,
    "22mp": 59744,
    "23mp": 59745,
    "24mp": 59746,
    "2k": 59747,
    "2k_plus": 59748,
    "2mp": 59749,
    "30fps": 61390,
    "30fps_select": 61391,
    "360": 58743,
    "3d_rotation": 59469,
    "3g_mobiledata": 61392,
    "3k": 59750,
    "3k_plus": 59751,
    "3mp": 59752,
    "3p": 61393,
    "4g_mobiledata": 61394,
    "4g_plus_mobiledata": 61395,
    "4k": 57458,
    "4k_plus": 59753,
    "4mp": 59754,
    "5g": 61240,
    "5k": 59755,
    "5k_plus": 59756,
    "5mp": 59757,
    "60fps": 61396,
    "60fps_select": 61397,
    "6_ft_apart": 61982,
    "6k": 59758,
    "6k_plus": 59759,
    "6mp": 59760,
    "7k": 59761,
    "7k_plus": 59762,
    "7mp": 59763,
    "8k": 59764,
    "8k_plus": 59765,
    "8mp": 59766,
    "9k": 59767,
    "9k_plus": 59768,
    "9mp": 59769,
    abc: 60308,
    ac_unit: 60219,
    access_alarm: 57744,
    access_alarms: 57745,
    access_time: 57746,
    access_time_filled: 61398,
    accessibility: 59470,
    accessibility_new: 59692,
    accessible: 59668,
    accessible_forward: 59700,
    account_balance: 59471,
    account_balance_wallet: 59472,
    account_box: 59473,
    account_circle: 59475,
    account_tree: 59770,
    ad_units: 61241,
    adb: 58894,
    add: 57669,
    add_a_photo: 58425,
    add_alarm: 57747,
    add_alert: 57347,
    add_box: 57670,
    add_business: 59177,
    add_call: 57576,
    add_card: 60294,
    add_chart: 59771,
    add_circle: 57671,
    add_circle_outline: 57672,
    add_comment: 57958,
    add_home: 63723,
    add_home_work: 63725,
    add_ic_call: 59772,
    add_link: 57720,
    add_location: 58727,
    add_location_alt: 61242,
    add_moderator: 59773,
    add_photo_alternate: 58430,
    add_reaction: 57811,
    add_road: 61243,
    add_shopping_cart: 59476,
    add_task: 62010,
    add_to_drive: 58972,
    add_to_home_screen: 57854,
    add_to_photos: 58269,
    add_to_queue: 57436,
    addchart: 61244,
    adf_scanner: 60122,
    adjust: 58270,
    admin_panel_settings: 61245,
    adobe: 60054,
    ads_click: 59234,
    agriculture: 60025,
    air: 61400,
    airline_seat_flat: 58928,
    airline_seat_flat_angled: 58929,
    airline_seat_individual_suite: 58930,
    airline_seat_legroom_extra: 58931,
    airline_seat_legroom_normal: 58932,
    airline_seat_legroom_reduced: 58933,
    airline_seat_recline_extra: 58934,
    airline_seat_recline_normal: 58935,
    airline_stops: 59344,
    airlines: 59338,
    airplane_ticket: 61401,
    airplanemode_active: 57749,
    airplanemode_inactive: 57748,
    airplanemode_off: 57748,
    airplanemode_on: 57749,
    airplay: 57429,
    airport_shuttle: 60220,
    alarm: 59477,
    alarm_add: 59478,
    alarm_off: 59479,
    alarm_on: 59480,
    album: 57369,
    align_horizontal_center: 57359,
    align_horizontal_left: 57357,
    align_horizontal_right: 57360,
    align_vertical_bottom: 57365,
    align_vertical_center: 57361,
    align_vertical_top: 57356,
    all_inbox: 59775,
    all_inclusive: 60221,
    all_out: 59659,
    alt_route: 61828,
    alternate_email: 57574,
    amp_stories: 59923,
    analytics: 61246,
    anchor: 61901,
    android: 59481,
    animation: 59164,
    announcement: 59482,
    aod: 61402,
    apartment: 59968,
    api: 61879,
    app_blocking: 61247,
    app_registration: 61248,
    app_settings_alt: 61249,
    app_shortcut: 60132,
    apple: 60032,
    approval: 59778,
    apps: 58819,
    apps_outage: 59340,
    architecture: 59963,
    archive: 57673,
    area_chart: 59248,
    arrow_back: 58820,
    arrow_back_ios: 58848,
    arrow_back_ios_new: 58090,
    arrow_circle_down: 61825,
    arrow_circle_left: 60071,
    arrow_circle_right: 60074,
    arrow_circle_up: 61826,
    arrow_downward: 58843,
    arrow_drop_down: 58821,
    arrow_drop_down_circle: 58822,
    arrow_drop_up: 58823,
    arrow_forward: 58824,
    arrow_forward_ios: 58849,
    arrow_left: 58846,
    arrow_outward: 63694,
    arrow_right: 58847,
    arrow_right_alt: 59713,
    arrow_upward: 58840,
    art_track: 57440,
    article: 61250,
    aspect_ratio: 59483,
    assessment: 59484,
    assignment: 59485,
    assignment_add: 63560,
    assignment_ind: 59486,
    assignment_late: 59487,
    assignment_return: 59488,
    assignment_returned: 59489,
    assignment_turned_in: 59490,
    assist_walker: 63701,
    assistant: 58271,
    assistant_direction: 59784,
    assistant_navigation: 59785,
    assistant_photo: 58272,
    assured_workload: 60271,
    atm: 58739,
    attach_email: 59998,
    attach_file: 57894,
    attach_money: 57895,
    attachment: 58044,
    attractions: 59986,
    attribution: 61403,
    audio_file: 60290,
    audiotrack: 58273,
    auto_awesome: 58975,
    auto_awesome_mosaic: 58976,
    auto_awesome_motion: 58977,
    auto_delete: 59980,
    auto_fix_high: 58979,
    auto_fix_normal: 58980,
    auto_fix_off: 58981,
    auto_graph: 58619,
    auto_mode: 60448,
    auto_stories: 58982,
    autofps_select: 61404,
    autorenew: 59491,
    av_timer: 57371,
    baby_changing_station: 61851,
    back_hand: 59236,
    backpack: 61852,
    backspace: 57674,
    backup: 59492,
    backup_table: 61251,
    badge: 60007,
    bakery_dining: 59987,
    balance: 60150,
    balcony: 58767,
    ballot: 57714,
    bar_chart: 57963,
    barcode_reader: 63580,
    batch_prediction: 61685,
    bathroom: 61405,
    bathtub: 59969,
    battery_0_bar: 60380,
    battery_1_bar: 60377,
    battery_2_bar: 60384,
    battery_3_bar: 60381,
    battery_4_bar: 60386,
    battery_5_bar: 60372,
    battery_6_bar: 60370,
    battery_alert: 57756,
    battery_charging_full: 57763,
    battery_full: 57764,
    battery_saver: 61406,
    battery_std: 57765,
    battery_unknown: 57766,
    beach_access: 60222,
    bed: 61407,
    bedroom_baby: 61408,
    bedroom_child: 61409,
    bedroom_parent: 61410,
    bedtime: 61252,
    bedtime_off: 60278,
    beenhere: 58669,
    bento: 61940,
    bike_scooter: 61253,
    biotech: 59962,
    blender: 61411,
    blind: 63702,
    blinds: 57990,
    blinds_closed: 60447,
    block: 57675,
    block_flipped: 61254,
    bloodtype: 61412,
    bluetooth: 57767,
    bluetooth_audio: 58895,
    bluetooth_connected: 57768,
    bluetooth_disabled: 57769,
    bluetooth_drive: 61413,
    bluetooth_searching: 57770,
    blur_circular: 58274,
    blur_linear: 58275,
    blur_off: 58276,
    blur_on: 58277,
    bolt: 59915,
    book: 59493,
    book_online: 61975,
    bookmark: 59494,
    bookmark_add: 58776,
    bookmark_added: 58777,
    bookmark_border: 59495,
    bookmark_outline: 59495,
    bookmark_remove: 58778,
    bookmarks: 59787,
    border_all: 57896,
    border_bottom: 57897,
    border_clear: 57898,
    border_color: 57899,
    border_horizontal: 57900,
    border_inner: 57901,
    border_left: 57902,
    border_outer: 57903,
    border_right: 57904,
    border_style: 57905,
    border_top: 57906,
    border_vertical: 57907,
    boy: 60263,
    branding_watermark: 57451,
    breakfast_dining: 59988,
    brightness_1: 58278,
    brightness_2: 58279,
    brightness_3: 58280,
    brightness_4: 58281,
    brightness_5: 58282,
    brightness_6: 58283,
    brightness_7: 58284,
    brightness_auto: 57771,
    brightness_high: 57772,
    brightness_low: 57773,
    brightness_medium: 57774,
    broadcast_on_home: 63736,
    broadcast_on_personal: 63737,
    broken_image: 58285,
    browse_gallery: 60369,
    browser_not_supported: 61255,
    browser_updated: 59343,
    brunch_dining: 60019,
    brush: 58286,
    bubble_chart: 59101,
    bug_report: 59496,
    build: 59497,
    build_circle: 61256,
    bungalow: 58769,
    burst_mode: 58428,
    bus_alert: 59791,
    business: 57519,
    business_center: 60223,
    cabin: 58761,
    cable: 61414,
    cached: 59498,
    cake: 59369,
    calculate: 59999,
    calendar_month: 60364,
    calendar_today: 59701,
    calendar_view_day: 59702,
    calendar_view_month: 61415,
    calendar_view_week: 61416,
    call: 57520,
    call_end: 57521,
    call_made: 57522,
    call_merge: 57523,
    call_missed: 57524,
    call_missed_outgoing: 57572,
    call_received: 57525,
    call_split: 57526,
    call_to_action: 57452,
    camera: 58287,
    camera_alt: 58288,
    camera_enhance: 59644,
    camera_front: 58289,
    camera_indoor: 61417,
    camera_outdoor: 61418,
    camera_rear: 58290,
    camera_roll: 58291,
    cameraswitch: 61419,
    campaign: 61257,
    cancel: 58825,
    cancel_presentation: 57577,
    cancel_schedule_send: 59961,
    candlestick_chart: 60116,
    car_crash: 60402,
    car_rental: 59989,
    car_repair: 59990,
    card_giftcard: 59638,
    card_membership: 59639,
    card_travel: 59640,
    carpenter: 61944,
    cases: 59794,
    casino: 60224,
    cast: 58119,
    cast_connected: 58120,
    cast_for_education: 61420,
    castle: 60081,
    catching_pokemon: 58632,
    category: 58740,
    celebration: 60005,
    cell_tower: 60346,
    cell_wifi: 57580,
    center_focus_strong: 58292,
    center_focus_weak: 58293,
    chair: 61421,
    chair_alt: 61422,
    chalet: 58757,
    change_circle: 58087,
    change_history: 59499,
    charging_station: 61853,
    chat: 57527,
    chat_bubble: 57546,
    chat_bubble_outline: 57547,
    check: 58826,
    check_box: 59444,
    check_box_outline_blank: 59445,
    check_circle: 59500,
    check_circle_outline: 59693,
    checklist: 59057,
    checklist_rtl: 59059,
    checkroom: 61854,
    chevron_left: 58827,
    chevron_right: 58828,
    child_care: 60225,
    child_friendly: 60226,
    chrome_reader_mode: 59501,
    church: 60078,
    circle: 61258,
    circle_notifications: 59796,
    class: 59502,
    clean_hands: 61983,
    cleaning_services: 61695,
    clear: 57676,
    clear_all: 57528,
    close: 58829,
    close_fullscreen: 61903,
    closed_caption: 57372,
    closed_caption_disabled: 61916,
    closed_caption_off: 59798,
    cloud: 58045,
    cloud_circle: 58046,
    cloud_done: 58047,
    cloud_download: 58048,
    cloud_off: 58049,
    cloud_queue: 58050,
    cloud_sync: 60250,
    cloud_upload: 58051,
    cloudy_snowing: 59408,
    co2: 59312,
    co_present: 60144,
    code: 59503,
    code_off: 58611,
    coffee: 61423,
    coffee_maker: 61424,
    collections: 58294,
    collections_bookmark: 58417,
    color_lens: 58295,
    colorize: 58296,
    comment: 57529,
    comment_bank: 59982,
    comments_disabled: 59298,
    commit: 60149,
    commute: 59712,
    compare: 58297,
    compare_arrows: 59669,
    compass_calibration: 58748,
    compost: 59233,
    compress: 59725,
    computer: 58122,
    confirmation_num: 58936,
    confirmation_number: 58936,
    connect_without_contact: 61987,
    connected_tv: 59800,
    connecting_airports: 59337,
    construction: 59964,
    contact_emergency: 63697,
    contact_mail: 57552,
    contact_page: 61998,
    contact_phone: 57551,
    contact_support: 59724,
    contactless: 60017,
    contacts: 57530,
    content_copy: 57677,
    content_cut: 57678,
    content_paste: 57679,
    content_paste_go: 60046,
    content_paste_off: 58616,
    content_paste_search: 60059,
    contrast: 60215,
    control_camera: 57460,
    control_point: 58298,
    control_point_duplicate: 58299,
    conveyor_belt: 63591,
    cookie: 60076,
    copy_all: 58092,
    copyright: 59660,
    coronavirus: 61985,
    corporate_fare: 61904,
    cottage: 58759,
    countertops: 61943,
    create: 57680,
    create_new_folder: 58060,
    credit_card: 59504,
    credit_card_off: 58612,
    credit_score: 61425,
    crib: 58760,
    crisis_alert: 60393,
    crop: 58302,
    crop_16_9: 58300,
    crop_3_2: 58301,
    crop_5_4: 58303,
    crop_7_5: 58304,
    crop_din: 58305,
    crop_free: 58306,
    crop_landscape: 58307,
    crop_original: 58308,
    crop_portrait: 58309,
    crop_rotate: 58423,
    crop_square: 58310,
    cruelty_free: 59289,
    css: 60307,
    currency_bitcoin: 60357,
    currency_exchange: 60272,
    currency_franc: 60154,
    currency_lira: 60143,
    currency_pound: 60145,
    currency_ruble: 60140,
    currency_rupee: 60151,
    currency_yen: 60155,
    currency_yuan: 60153,
    curtains: 60446,
    curtains_closed: 60445,
    cyclone: 60373,
    dangerous: 59802,
    dark_mode: 58652,
    dashboard: 59505,
    dashboard_customize: 59803,
    data_array: 60113,
    data_exploration: 59247,
    data_object: 60115,
    data_saver_off: 61426,
    data_saver_on: 61427,
    data_thresholding: 60319,
    data_usage: 57775,
    dataset: 63726,
    dataset_linked: 63727,
    date_range: 59670,
    deblur: 60279,
    deck: 59970,
    dehaze: 58311,
    delete: 59506,
    delete_forever: 59691,
    delete_outline: 59694,
    delete_sweep: 57708,
    delivery_dining: 60018,
    density_large: 60329,
    density_medium: 60318,
    density_small: 60328,
    departure_board: 58742,
    description: 59507,
    deselect: 60342,
    design_services: 61706,
    desk: 63732,
    desktop_access_disabled: 59805,
    desktop_mac: 58123,
    desktop_windows: 58124,
    details: 58312,
    developer_board: 58125,
    developer_board_off: 58623,
    developer_mode: 57776,
    device_hub: 58165,
    device_thermostat: 57855,
    device_unknown: 58169,
    devices: 57777,
    devices_fold: 60382,
    devices_other: 58167,
    dew_point: 63609,
    dialer_sip: 57531,
    dialpad: 57532,
    diamond: 60117,
    difference: 60285,
    dining: 61428,
    dinner_dining: 59991,
    directions: 58670,
    directions_bike: 58671,
    directions_boat: 58674,
    directions_boat_filled: 61429,
    directions_bus: 58672,
    directions_bus_filled: 61430,
    directions_car: 58673,
    directions_car_filled: 61431,
    directions_ferry: 58674,
    directions_off: 61711,
    directions_railway: 58676,
    directions_railway_filled: 61432,
    directions_run: 58726,
    directions_subway: 58675,
    directions_subway_filled: 61433,
    directions_train: 58676,
    directions_transit: 58677,
    directions_transit_filled: 61434,
    directions_walk: 58678,
    dirty_lens: 61259,
    disabled_by_default: 62e3,
    disabled_visible: 59246,
    disc_full: 58896,
    discord: 60012,
    discount: 60361,
    display_settings: 60311,
    diversity_1: 63703,
    diversity_2: 63704,
    diversity_3: 63705,
    dnd_forwardslash: 58897,
    dns: 59509,
    do_disturb: 61580,
    do_disturb_alt: 61581,
    do_disturb_off: 61582,
    do_disturb_on: 61583,
    do_not_disturb: 58898,
    do_not_disturb_alt: 58897,
    do_not_disturb_off: 58947,
    do_not_disturb_on: 58948,
    do_not_disturb_on_total_silence: 61435,
    do_not_step: 61855,
    do_not_touch: 61872,
    dock: 58126,
    document_scanner: 58874,
    domain: 59374,
    domain_add: 60258,
    domain_disabled: 57583,
    domain_verification: 61260,
    done: 59510,
    done_all: 59511,
    done_outline: 59695,
    donut_large: 59671,
    donut_small: 59672,
    door_back: 61436,
    door_front: 61437,
    door_sliding: 61438,
    doorbell: 61439,
    double_arrow: 59984,
    downhill_skiing: 58633,
    download: 61584,
    download_done: 61585,
    download_for_offline: 61440,
    downloading: 61441,
    drafts: 57681,
    drag_handle: 57949,
    drag_indicator: 59717,
    draw: 59206,
    drive_eta: 58899,
    drive_file_move: 58997,
    drive_file_move_outline: 59809,
    drive_file_move_rtl: 59245,
    drive_file_rename_outline: 59810,
    drive_folder_upload: 59811,
    dry: 61875,
    dry_cleaning: 59992,
    duo: 59813,
    dvr: 57778,
    dynamic_feed: 59924,
    dynamic_form: 61887,
    e_mobiledata: 61442,
    earbuds: 61443,
    earbuds_battery: 61444,
    east: 61919,
    eco: 59957,
    edgesensor_high: 61445,
    edgesensor_low: 61446,
    edit: 58313,
    edit_attributes: 58744,
    edit_calendar: 59202,
    edit_document: 63628,
    edit_location: 58728,
    edit_location_alt: 57797,
    edit_note: 59205,
    edit_notifications: 58661,
    edit_off: 59728,
    edit_road: 61261,
    edit_square: 63629,
    egg: 60108,
    egg_alt: 60104,
    eject: 59643,
    elderly: 61978,
    elderly_woman: 60265,
    electric_bike: 60187,
    electric_bolt: 60444,
    electric_car: 60188,
    electric_meter: 60443,
    electric_moped: 60189,
    electric_rickshaw: 60190,
    electric_scooter: 60191,
    electrical_services: 61698,
    elevator: 61856,
    email: 57534,
    emergency: 57835,
    emergency_recording: 60404,
    emergency_share: 60406,
    emoji_emotions: 59938,
    emoji_events: 59939,
    emoji_flags: 59930,
    emoji_food_beverage: 59931,
    emoji_nature: 59932,
    emoji_objects: 59940,
    emoji_people: 59933,
    emoji_symbols: 59934,
    emoji_transportation: 59935,
    energy_savings_leaf: 60442,
    engineering: 59965,
    enhance_photo_translate: 59644,
    enhanced_encryption: 58943,
    equalizer: 57373,
    error: 57344,
    error_outline: 57345,
    escalator: 61857,
    escalator_warning: 61868,
    euro: 59925,
    euro_symbol: 59686,
    ev_station: 58733,
    event: 59512,
    event_available: 58900,
    event_busy: 58901,
    event_note: 58902,
    event_repeat: 60283,
    event_seat: 59651,
    exit_to_app: 59513,
    expand: 59727,
    expand_circle_down: 59341,
    expand_less: 58830,
    expand_more: 58831,
    explicit: 57374,
    explore: 59514,
    explore_off: 59816,
    exposure: 58314,
    exposure_minus_1: 58315,
    exposure_minus_2: 58316,
    exposure_neg_1: 58315,
    exposure_neg_2: 58316,
    exposure_plus_1: 58317,
    exposure_plus_2: 58318,
    exposure_zero: 58319,
    extension: 59515,
    extension_off: 58613,
    face: 59516,
    face_2: 63706,
    face_3: 63707,
    face_4: 63708,
    face_5: 63709,
    face_6: 63710,
    face_retouching_natural: 61262,
    face_retouching_off: 61447,
    facebook: 62004,
    fact_check: 61637,
    factory: 60348,
    family_restroom: 61858,
    fast_forward: 57375,
    fast_rewind: 57376,
    fastfood: 58746,
    favorite: 59517,
    favorite_border: 59518,
    favorite_outline: 59518,
    fax: 60120,
    featured_play_list: 57453,
    featured_video: 57454,
    feed: 61449,
    feedback: 59519,
    female: 58768,
    fence: 61942,
    festival: 60008,
    fiber_dvr: 57437,
    fiber_manual_record: 57441,
    fiber_new: 57438,
    fiber_pin: 57450,
    fiber_smart_record: 57442,
    file_copy: 57715,
    file_download: 58052,
    file_download_done: 59818,
    file_download_off: 58622,
    file_open: 60147,
    file_present: 59918,
    file_upload: 58054,
    file_upload_off: 63622,
    filter: 58323,
    filter_1: 58320,
    filter_2: 58321,
    filter_3: 58322,
    filter_4: 58324,
    filter_5: 58325,
    filter_6: 58326,
    filter_7: 58327,
    filter_8: 58328,
    filter_9: 58329,
    filter_9_plus: 58330,
    filter_alt: 61263,
    filter_alt_off: 60210,
    filter_b_and_w: 58331,
    filter_center_focus: 58332,
    filter_drama: 58333,
    filter_frames: 58334,
    filter_hdr: 58335,
    filter_list: 57682,
    filter_list_alt: 59726,
    filter_list_off: 60247,
    filter_none: 58336,
    filter_tilt_shift: 58338,
    filter_vintage: 58339,
    find_in_page: 59520,
    find_replace: 59521,
    fingerprint: 59661,
    fire_extinguisher: 61912,
    fire_hydrant: 61859,
    fire_hydrant_alt: 63729,
    fire_truck: 63730,
    fireplace: 59971,
    first_page: 58844,
    fit_screen: 59920,
    fitbit: 59435,
    fitness_center: 60227,
    flag: 57683,
    flag_circle: 60152,
    flaky: 61264,
    flare: 58340,
    flash_auto: 58341,
    flash_off: 58342,
    flash_on: 58343,
    flashlight_off: 61450,
    flashlight_on: 61451,
    flatware: 61452,
    flight: 58681,
    flight_class: 59339,
    flight_land: 59652,
    flight_takeoff: 59653,
    flip: 58344,
    flip_camera_android: 59959,
    flip_camera_ios: 59960,
    flip_to_back: 59522,
    flip_to_front: 59523,
    flood: 60390,
    flourescent: 60465,
    fluorescent: 60465,
    flutter_dash: 57355,
    fmd_bad: 61454,
    fmd_good: 61455,
    foggy: 59416,
    folder: 58055,
    folder_copy: 60349,
    folder_delete: 60212,
    folder_off: 60291,
    folder_open: 58056,
    folder_shared: 58057,
    folder_special: 58903,
    folder_zip: 60204,
    follow_the_signs: 61986,
    font_download: 57703,
    font_download_off: 58617,
    food_bank: 61938,
    forest: 60057,
    fork_left: 60320,
    fork_right: 60332,
    forklift: 63592,
    format_align_center: 57908,
    format_align_justify: 57909,
    format_align_left: 57910,
    format_align_right: 57911,
    format_bold: 57912,
    format_clear: 57913,
    format_color_fill: 57914,
    format_color_reset: 57915,
    format_color_text: 57916,
    format_indent_decrease: 57917,
    format_indent_increase: 57918,
    format_italic: 57919,
    format_line_spacing: 57920,
    format_list_bulleted: 57921,
    format_list_bulleted_add: 63561,
    format_list_numbered: 57922,
    format_list_numbered_rtl: 57959,
    format_overline: 60261,
    format_paint: 57923,
    format_quote: 57924,
    format_shapes: 57950,
    format_size: 57925,
    format_strikethrough: 57926,
    format_textdirection_l_to_r: 57927,
    format_textdirection_r_to_l: 57928,
    format_underline: 57929,
    format_underlined: 57929,
    fort: 60077,
    forum: 57535,
    forward: 57684,
    forward_10: 57430,
    forward_30: 57431,
    forward_5: 57432,
    forward_to_inbox: 61831,
    foundation: 61952,
    free_breakfast: 60228,
    free_cancellation: 59208,
    front_hand: 59241,
    front_loader: 63593,
    fullscreen: 58832,
    fullscreen_exit: 58833,
    functions: 57930,
    g_mobiledata: 61456,
    g_translate: 59687,
    gamepad: 58127,
    games: 57377,
    garage: 61457,
    gas_meter: 60441,
    gavel: 59662,
    generating_tokens: 59209,
    gesture: 57685,
    get_app: 59524,
    gif: 59656,
    gif_box: 59299,
    girl: 60264,
    gite: 58763,
    goat: 1114109,
    golf_course: 60229,
    gpp_bad: 61458,
    gpp_good: 61459,
    gpp_maybe: 61460,
    gps_fixed: 57779,
    gps_not_fixed: 57780,
    gps_off: 57781,
    grade: 59525,
    gradient: 58345,
    grading: 59983,
    grain: 58346,
    graphic_eq: 57784,
    grass: 61957,
    grid_3x3: 61461,
    grid_4x4: 61462,
    grid_goldenratio: 61463,
    grid_off: 58347,
    grid_on: 58348,
    grid_view: 59824,
    group: 59375,
    group_add: 59376,
    group_off: 59207,
    group_remove: 59309,
    group_work: 59526,
    groups: 62003,
    groups_2: 63711,
    groups_3: 63712,
    h_mobiledata: 61464,
    h_plus_mobiledata: 61465,
    hail: 59825,
    handshake: 60363,
    handyman: 61707,
    hardware: 59993,
    hd: 57426,
    hdr_auto: 61466,
    hdr_auto_select: 61467,
    hdr_enhanced_select: 61265,
    hdr_off: 58349,
    hdr_off_select: 61468,
    hdr_on: 58350,
    hdr_on_select: 61469,
    hdr_plus: 61470,
    hdr_strong: 58353,
    hdr_weak: 58354,
    headphones: 61471,
    headphones_battery: 61472,
    headset: 58128,
    headset_mic: 58129,
    headset_off: 58170,
    healing: 58355,
    health_and_safety: 57813,
    hearing: 57379,
    hearing_disabled: 61700,
    heart_broken: 60098,
    heat_pump: 60440,
    height: 59926,
    help: 59527,
    help_center: 61888,
    help_outline: 59645,
    hevc: 61473,
    hexagon: 60217,
    hide_image: 61474,
    hide_source: 61475,
    high_quality: 57380,
    highlight: 57951,
    highlight_alt: 61266,
    highlight_off: 59528,
    highlight_remove: 59528,
    hiking: 58634,
    history: 59529,
    history_edu: 59966,
    history_toggle_off: 61821,
    hive: 60070,
    hls: 60298,
    hls_off: 60300,
    holiday_village: 58762,
    home: 59530,
    home_filled: 59826,
    home_max: 61476,
    home_mini: 61477,
    home_repair_service: 61696,
    home_work: 59913,
    horizontal_distribute: 57364,
    horizontal_rule: 61704,
    horizontal_split: 59719,
    hot_tub: 60230,
    hotel: 58682,
    hotel_class: 59203,
    hourglass_bottom: 59996,
    hourglass_disabled: 61267,
    hourglass_empty: 59531,
    hourglass_full: 59532,
    hourglass_top: 59995,
    house: 59972,
    house_siding: 61954,
    houseboat: 58756,
    how_to_reg: 57716,
    how_to_vote: 57717,
    html: 60286,
    http: 59650,
    https: 59533,
    hub: 59892,
    hvac: 61710,
    ice_skating: 58635,
    icecream: 60009,
    image: 58356,
    image_aspect_ratio: 58357,
    image_not_supported: 61718,
    image_search: 58431,
    imagesearch_roller: 59828,
    import_contacts: 57568,
    import_export: 57539,
    important_devices: 59666,
    inbox: 57686,
    incomplete_circle: 59291,
    indeterminate_check_box: 59657,
    info: 59534,
    info_outline: 59535,
    input: 59536,
    insert_chart: 57931,
    insert_chart_outlined: 57962,
    insert_comment: 57932,
    insert_drive_file: 57933,
    insert_emoticon: 57934,
    insert_invitation: 57935,
    insert_link: 57936,
    insert_page_break: 60106,
    insert_photo: 57937,
    insights: 61586,
    install_desktop: 60273,
    install_mobile: 60274,
    integration_instructions: 61268,
    interests: 59336,
    interpreter_mode: 59451,
    inventory: 57721,
    inventory_2: 57761,
    invert_colors: 59537,
    invert_colors_off: 57540,
    invert_colors_on: 59537,
    ios_share: 59064,
    iron: 58755,
    iso: 58358,
    javascript: 60284,
    join_full: 60139,
    join_inner: 60148,
    join_left: 60146,
    join_right: 60138,
    kayaking: 58636,
    kebab_dining: 59458,
    key: 59196,
    key_off: 60292,
    keyboard: 58130,
    keyboard_alt: 61480,
    keyboard_arrow_down: 58131,
    keyboard_arrow_left: 58132,
    keyboard_arrow_right: 58133,
    keyboard_arrow_up: 58134,
    keyboard_backspace: 58135,
    keyboard_capslock: 58136,
    keyboard_command: 60128,
    keyboard_command_key: 60135,
    keyboard_control: 58835,
    keyboard_control_key: 60134,
    keyboard_double_arrow_down: 60112,
    keyboard_double_arrow_left: 60099,
    keyboard_double_arrow_right: 60105,
    keyboard_double_arrow_up: 60111,
    keyboard_hide: 58138,
    keyboard_option: 60127,
    keyboard_option_key: 60136,
    keyboard_return: 58139,
    keyboard_tab: 58140,
    keyboard_voice: 58141,
    king_bed: 59973,
    kitchen: 60231,
    kitesurfing: 58637,
    label: 59538,
    label_important: 59703,
    label_important_outline: 59720,
    label_off: 59830,
    label_outline: 59539,
    lan: 60207,
    landscape: 58359,
    landslide: 60375,
    language: 59540,
    laptop: 58142,
    laptop_chromebook: 58143,
    laptop_mac: 58144,
    laptop_windows: 58145,
    last_page: 58845,
    launch: 59541,
    layers: 58683,
    layers_clear: 58684,
    leaderboard: 61964,
    leak_add: 58360,
    leak_remove: 58361,
    leave_bags_at_home: 61979,
    legend_toggle: 61723,
    lens: 58362,
    lens_blur: 61481,
    library_add: 57390,
    library_add_check: 59831,
    library_books: 57391,
    library_music: 57392,
    light: 61482,
    light_mode: 58648,
    lightbulb: 57584,
    lightbulb_circle: 60414,
    lightbulb_outline: 59663,
    line_axis: 60058,
    line_style: 59673,
    line_weight: 59674,
    linear_scale: 57952,
    link: 57687,
    link_off: 57711,
    linked_camera: 58424,
    liquor: 6e4,
    list: 59542,
    list_alt: 57582,
    live_help: 57542,
    live_tv: 58937,
    living: 61483,
    local_activity: 58687,
    local_airport: 58685,
    local_atm: 58686,
    local_attraction: 58687,
    local_bar: 58688,
    local_cafe: 58689,
    local_car_wash: 58690,
    local_convenience_store: 58691,
    local_dining: 58710,
    local_drink: 58692,
    local_fire_department: 61269,
    local_florist: 58693,
    local_gas_station: 58694,
    local_grocery_store: 58695,
    local_hospital: 58696,
    local_hotel: 58697,
    local_laundry_service: 58698,
    local_library: 58699,
    local_mall: 58700,
    local_movies: 58701,
    local_offer: 58702,
    local_parking: 58703,
    local_pharmacy: 58704,
    local_phone: 58705,
    local_pizza: 58706,
    local_play: 58707,
    local_police: 61270,
    local_post_office: 58708,
    local_print_shop: 58709,
    local_printshop: 58709,
    local_restaurant: 58710,
    local_see: 58711,
    local_shipping: 58712,
    local_taxi: 58713,
    location_city: 59377,
    location_disabled: 57782,
    location_history: 58714,
    location_off: 57543,
    location_on: 57544,
    location_pin: 61915,
    location_searching: 57783,
    lock: 59543,
    lock_clock: 61271,
    lock_open: 59544,
    lock_outline: 59545,
    lock_person: 63731,
    lock_reset: 60126,
    login: 60023,
    logo_dev: 60118,
    logout: 59834,
    looks: 58364,
    looks_3: 58363,
    looks_4: 58365,
    looks_5: 58366,
    looks_6: 58367,
    looks_one: 58368,
    looks_two: 58369,
    loop: 57384,
    loupe: 58370,
    low_priority: 57709,
    loyalty: 59546,
    lte_mobiledata: 61484,
    lte_plus_mobiledata: 61485,
    luggage: 62005,
    lunch_dining: 60001,
    lyrics: 60427,
    macro_off: 63698,
    mail: 57688,
    mail_lock: 60426,
    mail_outline: 57569,
    male: 58766,
    man: 58603,
    man_2: 63713,
    man_3: 63714,
    man_4: 63715,
    manage_accounts: 61486,
    manage_history: 60391,
    manage_search: 61487,
    map: 58715,
    maps_home_work: 61488,
    maps_ugc: 61272,
    margin: 59835,
    mark_as_unread: 59836,
    mark_chat_read: 61835,
    mark_chat_unread: 61833,
    mark_email_read: 61836,
    mark_email_unread: 61834,
    mark_unread_chat_alt: 60317,
    markunread: 57689,
    markunread_mailbox: 59547,
    masks: 61976,
    maximize: 59696,
    media_bluetooth_off: 61489,
    media_bluetooth_on: 61490,
    mediation: 61351,
    medical_information: 60397,
    medical_services: 61705,
    medication: 61491,
    medication_liquid: 60039,
    meeting_room: 60239,
    memory: 58146,
    menu: 58834,
    menu_book: 59929,
    menu_open: 59837,
    merge: 60312,
    merge_type: 57938,
    message: 57545,
    messenger: 57546,
    messenger_outline: 57547,
    mic: 57385,
    mic_external_off: 61273,
    mic_external_on: 61274,
    mic_none: 57386,
    mic_off: 57387,
    microwave: 61956,
    military_tech: 59967,
    minimize: 59697,
    minor_crash: 60401,
    miscellaneous_services: 61708,
    missed_video_call: 57459,
    mms: 58904,
    mobile_friendly: 57856,
    mobile_off: 57857,
    mobile_screen_share: 57575,
    mobiledata_off: 61492,
    mode: 61591,
    mode_comment: 57939,
    mode_edit: 57940,
    mode_edit_outline: 61493,
    mode_fan_off: 60439,
    mode_night: 61494,
    mode_of_travel: 59342,
    mode_standby: 61495,
    model_training: 61647,
    monetization_on: 57955,
    money: 58749,
    money_off: 57948,
    money_off_csred: 61496,
    monitor: 61275,
    monitor_heart: 60066,
    monitor_weight: 61497,
    monochrome_photos: 58371,
    mood: 59378,
    mood_bad: 59379,
    moped: 60200,
    more: 58905,
    more_horiz: 58835,
    more_time: 59997,
    more_vert: 58836,
    mosque: 60082,
    motion_photos_auto: 61498,
    motion_photos_off: 59840,
    motion_photos_on: 59841,
    motion_photos_pause: 61991,
    motion_photos_paused: 59842,
    motorcycle: 59675,
    mouse: 58147,
    move_down: 60257,
    move_to_inbox: 57704,
    move_up: 60260,
    movie: 57388,
    movie_creation: 58372,
    movie_edit: 63552,
    movie_filter: 58426,
    moving: 58625,
    mp: 59843,
    multiline_chart: 59103,
    multiple_stop: 61881,
    multitrack_audio: 57784,
    museum: 59958,
    music_note: 58373,
    music_off: 58432,
    music_video: 57443,
    my_library_add: 57390,
    my_library_books: 57391,
    my_library_music: 57392,
    my_location: 58716,
    nat: 61276,
    nature: 58374,
    nature_people: 58375,
    navigate_before: 58376,
    navigate_next: 58377,
    navigation: 58717,
    near_me: 58729,
    near_me_disabled: 61935,
    nearby_error: 61499,
    nearby_off: 61500,
    nest_cam_wired_stand: 60438,
    network_cell: 57785,
    network_check: 58944,
    network_locked: 58906,
    network_ping: 60362,
    network_wifi: 57786,
    network_wifi_1_bar: 60388,
    network_wifi_2_bar: 60374,
    network_wifi_3_bar: 60385,
    new_label: 58889,
    new_releases: 57393,
    newspaper: 60289,
    next_plan: 61277,
    next_week: 57706,
    nfc: 57787,
    night_shelter: 61937,
    nightlife: 60002,
    nightlight: 61501,
    nightlight_round: 61278,
    nights_stay: 59974,
    no_accounts: 61502,
    no_adult_content: 63742,
    no_backpack: 62007,
    no_cell: 61860,
    no_crash: 60400,
    no_drinks: 61861,
    no_encryption: 58945,
    no_encryption_gmailerrorred: 61503,
    no_flash: 61862,
    no_food: 61863,
    no_luggage: 62011,
    no_meals: 61910,
    no_meals_ouline: 61993,
    no_meeting_room: 60238,
    no_photography: 61864,
    no_sim: 57548,
    no_stroller: 61871,
    no_transfer: 61909,
    noise_aware: 60396,
    noise_control_off: 60403,
    nordic_walking: 58638,
    north: 61920,
    north_east: 61921,
    north_west: 61922,
    not_accessible: 61694,
    not_interested: 57395,
    not_listed_location: 58741,
    not_started: 61649,
    note: 57455,
    note_add: 59548,
    note_alt: 61504,
    notes: 57964,
    notification_add: 58265,
    notification_important: 57348,
    notifications: 59380,
    notifications_active: 59383,
    notifications_none: 59381,
    notifications_off: 59382,
    notifications_on: 59383,
    notifications_paused: 59384,
    now_wallpaper: 57788,
    now_widgets: 57789,
    numbers: 60103,
    offline_bolt: 59698,
    offline_pin: 59658,
    offline_share: 59845,
    oil_barrel: 60437,
    on_device_training: 60413,
    ondemand_video: 58938,
    online_prediction: 61675,
    opacity: 59676,
    open_in_browser: 59549,
    open_in_full: 61902,
    open_in_new: 59550,
    open_in_new_off: 58614,
    open_with: 59551,
    other_houses: 58764,
    outbond: 61992,
    outbound: 57802,
    outbox: 61279,
    outdoor_grill: 59975,
    outgoing_mail: 61650,
    outlet: 61908,
    outlined_flag: 57710,
    output: 60350,
    padding: 59848,
    pages: 59385,
    pageview: 59552,
    paid: 61505,
    palette: 58378,
    pallet: 63594,
    pan_tool: 59685,
    pan_tool_alt: 60345,
    panorama: 58379,
    panorama_fish_eye: 58380,
    panorama_fisheye: 58380,
    panorama_horizontal: 58381,
    panorama_horizontal_select: 61280,
    panorama_photosphere: 59849,
    panorama_photosphere_select: 59850,
    panorama_vertical: 58382,
    panorama_vertical_select: 61281,
    panorama_wide_angle: 58383,
    panorama_wide_angle_select: 61282,
    paragliding: 58639,
    park: 60003,
    party_mode: 59386,
    password: 61506,
    pattern: 61507,
    pause: 57396,
    pause_circle: 57762,
    pause_circle_filled: 57397,
    pause_circle_outline: 57398,
    pause_presentation: 57578,
    payment: 59553,
    payments: 61283,
    paypal: 60045,
    pedal_bike: 60201,
    pending: 61284,
    pending_actions: 61883,
    pentagon: 60240,
    people: 59387,
    people_alt: 59937,
    people_outline: 59388,
    percent: 60248,
    perm_camera_mic: 59554,
    perm_contact_cal: 59555,
    perm_contact_calendar: 59555,
    perm_data_setting: 59556,
    perm_device_info: 59557,
    perm_device_information: 59557,
    perm_identity: 59558,
    perm_media: 59559,
    perm_phone_msg: 59560,
    perm_scan_wifi: 59561,
    person: 59389,
    person_2: 63716,
    person_3: 63717,
    person_4: 63718,
    person_add: 59390,
    person_add_alt: 59981,
    person_add_alt_1: 61285,
    person_add_disabled: 59851,
    person_off: 58640,
    person_outline: 59391,
    person_pin: 58714,
    person_pin_circle: 58730,
    person_remove: 61286,
    person_remove_alt_1: 61287,
    person_search: 61702,
    personal_injury: 59098,
    personal_video: 58939,
    pest_control: 61690,
    pest_control_rodent: 61693,
    pets: 59677,
    phishing: 60119,
    phone: 57549,
    phone_android: 58148,
    phone_bluetooth_speaker: 58907,
    phone_callback: 58953,
    phone_disabled: 59852,
    phone_enabled: 59853,
    phone_forwarded: 58908,
    phone_in_talk: 58909,
    phone_iphone: 58149,
    phone_locked: 58910,
    phone_missed: 58911,
    phone_paused: 58912,
    phonelink: 58150,
    phonelink_erase: 57563,
    phonelink_lock: 57564,
    phonelink_off: 58151,
    phonelink_ring: 57565,
    phonelink_setup: 57566,
    photo: 58384,
    photo_album: 58385,
    photo_camera: 58386,
    photo_camera_back: 61288,
    photo_camera_front: 61289,
    photo_filter: 58427,
    photo_library: 58387,
    photo_size_select_actual: 58418,
    photo_size_select_large: 58419,
    photo_size_select_small: 58420,
    php: 60303,
    piano: 58657,
    piano_off: 58656,
    picture_as_pdf: 58389,
    picture_in_picture: 59562,
    picture_in_picture_alt: 59665,
    pie_chart: 59076,
    pie_chart_outline: 61508,
    pie_chart_outlined: 59077,
    pin: 61509,
    pin_drop: 58718,
    pin_end: 59239,
    pin_invoke: 59235,
    pinch: 60216,
    pivot_table_chart: 59854,
    pix: 60067,
    place: 58719,
    plagiarism: 59994,
    play_arrow: 57399,
    play_circle: 57796,
    play_circle_fill: 57400,
    play_circle_filled: 57400,
    play_circle_outline: 57401,
    play_disabled: 61290,
    play_for_work: 59654,
    play_lesson: 61511,
    playlist_add: 57403,
    playlist_add_check: 57445,
    playlist_add_check_circle: 59366,
    playlist_add_circle: 59365,
    playlist_play: 57439,
    playlist_remove: 60288,
    plumbing: 61703,
    plus_one: 59392,
    podcasts: 61512,
    point_of_sale: 61822,
    policy: 59927,
    poll: 59393,
    polyline: 60347,
    polymer: 59563,
    pool: 60232,
    portable_wifi_off: 57550,
    portrait: 58390,
    post_add: 59936,
    power: 58940,
    power_input: 58166,
    power_off: 58950,
    power_settings_new: 59564,
    precision_manufacturing: 61513,
    pregnant_woman: 59678,
    present_to_all: 57567,
    preview: 61893,
    price_change: 61514,
    price_check: 61515,
    print: 59565,
    print_disabled: 59855,
    priority_high: 58949,
    privacy_tip: 61660,
    private_connectivity: 59204,
    production_quantity_limits: 57809,
    propane: 60436,
    propane_tank: 60435,
    psychology: 59978,
    psychology_alt: 63722,
    public: 59403,
    public_off: 61898,
    publish: 57941,
    published_with_changes: 62002,
    punch_clock: 60072,
    push_pin: 61709,
    qr_code: 61291,
    qr_code_2: 57354,
    qr_code_scanner: 61958,
    query_builder: 59566,
    query_stats: 58620,
    question_answer: 59567,
    question_mark: 60299,
    queue: 57404,
    queue_music: 57405,
    queue_play_next: 57446,
    quick_contacts_dialer: 57551,
    quick_contacts_mail: 57552,
    quickreply: 61292,
    quiz: 61516,
    quora: 60056,
    r_mobiledata: 61517,
    radar: 61518,
    radio: 57406,
    radio_button_checked: 59447,
    radio_button_off: 59446,
    radio_button_on: 59447,
    radio_button_unchecked: 59446,
    railway_alert: 59857,
    ramen_dining: 60004,
    ramp_left: 60316,
    ramp_right: 60310,
    rate_review: 58720,
    raw_off: 61519,
    raw_on: 61520,
    read_more: 61293,
    real_estate_agent: 59194,
    rebase_edit: 63558,
    receipt: 59568,
    receipt_long: 61294,
    recent_actors: 57407,
    recommend: 59858,
    record_voice_over: 59679,
    rectangle: 60244,
    recycling: 59232,
    reddit: 60064,
    redeem: 59569,
    redo: 57690,
    reduce_capacity: 61980,
    refresh: 58837,
    remember_me: 61521,
    remove: 57691,
    remove_circle: 57692,
    remove_circle_outline: 57693,
    remove_done: 59859,
    remove_from_queue: 57447,
    remove_moderator: 59860,
    remove_red_eye: 58391,
    remove_road: 60412,
    remove_shopping_cart: 59688,
    reorder: 59646,
    repartition: 63720,
    repeat: 57408,
    repeat_on: 59862,
    repeat_one: 57409,
    repeat_one_on: 59863,
    replay: 57410,
    replay_10: 57433,
    replay_30: 57434,
    replay_5: 57435,
    replay_circle_filled: 59864,
    reply: 57694,
    reply_all: 57695,
    report: 57696,
    report_gmailerrorred: 61522,
    report_off: 57712,
    report_problem: 59570,
    request_page: 61996,
    request_quote: 61878,
    reset_tv: 59865,
    restart_alt: 61523,
    restaurant: 58732,
    restaurant_menu: 58721,
    restore: 59571,
    restore_from_trash: 59704,
    restore_page: 59689,
    reviews: 61524,
    rice_bowl: 61941,
    ring_volume: 57553,
    rocket: 60325,
    rocket_launch: 60315,
    roller_shades: 60434,
    roller_shades_closed: 60433,
    roller_skating: 60365,
    roofing: 61953,
    room: 59572,
    room_preferences: 61880,
    room_service: 60233,
    rotate_90_degrees_ccw: 58392,
    rotate_90_degrees_cw: 60075,
    rotate_left: 58393,
    rotate_right: 58394,
    roundabout_left: 60313,
    roundabout_right: 60323,
    rounded_corner: 59680,
    route: 60109,
    router: 58152,
    rowing: 59681,
    rss_feed: 57573,
    rsvp: 61525,
    rtt: 59821,
    rule: 61890,
    rule_folder: 61897,
    run_circle: 61295,
    running_with_errors: 58653,
    rv_hookup: 58946,
    safety_check: 60399,
    safety_divider: 57804,
    sailing: 58626,
    sanitizer: 61981,
    satellite: 58722,
    satellite_alt: 60218,
    save: 57697,
    save_alt: 57713,
    save_as: 60256,
    saved_search: 59921,
    savings: 58091,
    scale: 60255,
    scanner: 58153,
    scatter_plot: 57960,
    schedule: 59573,
    schedule_send: 59914,
    schema: 58621,
    school: 59404,
    science: 59979,
    score: 57961,
    scoreboard: 60368,
    screen_lock_landscape: 57790,
    screen_lock_portrait: 57791,
    screen_lock_rotation: 57792,
    screen_rotation: 57793,
    screen_rotation_alt: 60398,
    screen_search_desktop: 61296,
    screen_share: 57570,
    screenshot: 61526,
    screenshot_monitor: 60424,
    scuba_diving: 60366,
    sd: 59869,
    sd_card: 58915,
    sd_card_alert: 61527,
    sd_storage: 57794,
    search: 59574,
    search_off: 60022,
    security: 58154,
    security_update: 61528,
    security_update_good: 61529,
    security_update_warning: 61530,
    segment: 59723,
    select_all: 57698,
    self_improvement: 60024,
    sell: 61531,
    send: 57699,
    send_and_archive: 59916,
    send_time_extension: 60123,
    send_to_mobile: 61532,
    sensor_door: 61877,
    sensor_occupied: 60432,
    sensor_window: 61876,
    sensors: 58654,
    sensors_off: 58655,
    sentiment_dissatisfied: 59409,
    sentiment_neutral: 59410,
    sentiment_satisfied: 59411,
    sentiment_satisfied_alt: 57581,
    sentiment_very_dissatisfied: 59412,
    sentiment_very_satisfied: 59413,
    set_meal: 61930,
    settings: 59576,
    settings_accessibility: 61533,
    settings_applications: 59577,
    settings_backup_restore: 59578,
    settings_bluetooth: 59579,
    settings_brightness: 59581,
    settings_cell: 59580,
    settings_display: 59581,
    settings_ethernet: 59582,
    settings_input_antenna: 59583,
    settings_input_component: 59584,
    settings_input_composite: 59585,
    settings_input_hdmi: 59586,
    settings_input_svideo: 59587,
    settings_overscan: 59588,
    settings_phone: 59589,
    settings_power: 59590,
    settings_remote: 59591,
    settings_suggest: 61534,
    settings_system_daydream: 57795,
    settings_voice: 59592,
    severe_cold: 60371,
    shape_line: 63699,
    share: 59405,
    share_arrival_time: 58660,
    share_location: 61535,
    shelves: 63598,
    shield: 59872,
    shield_moon: 60073,
    shop: 59593,
    shop_2: 57758,
    shop_two: 59594,
    shopify: 60061,
    shopping_bag: 61900,
    shopping_basket: 59595,
    shopping_cart: 59596,
    shopping_cart_checkout: 60296,
    short_text: 57953,
    shortcut: 61536,
    show_chart: 59105,
    shower: 61537,
    shuffle: 57411,
    shuffle_on: 59873,
    shutter_speed: 58429,
    sick: 61984,
    sign_language: 60389,
    signal_cellular_0_bar: 61608,
    signal_cellular_4_bar: 57800,
    signal_cellular_alt: 57858,
    signal_cellular_alt_1_bar: 60383,
    signal_cellular_alt_2_bar: 60387,
    signal_cellular_connected_no_internet_0_bar: 61612,
    signal_cellular_connected_no_internet_4_bar: 57805,
    signal_cellular_no_sim: 57806,
    signal_cellular_nodata: 61538,
    signal_cellular_null: 57807,
    signal_cellular_off: 57808,
    signal_wifi_0_bar: 61616,
    signal_wifi_4_bar: 57816,
    signal_wifi_4_bar_lock: 57817,
    signal_wifi_bad: 61539,
    signal_wifi_connected_no_internet_4: 61540,
    signal_wifi_off: 57818,
    signal_wifi_statusbar_4_bar: 61541,
    signal_wifi_statusbar_connected_no_internet_4: 61542,
    signal_wifi_statusbar_null: 61543,
    signpost: 60305,
    sim_card: 58155,
    sim_card_alert: 58916,
    sim_card_download: 61544,
    single_bed: 59976,
    sip: 61545,
    skateboarding: 58641,
    skip_next: 57412,
    skip_previous: 57413,
    sledding: 58642,
    slideshow: 58395,
    slow_motion_video: 57448,
    smart_button: 61889,
    smart_display: 61546,
    smart_screen: 61547,
    smart_toy: 61548,
    smartphone: 58156,
    smoke_free: 60234,
    smoking_rooms: 60235,
    sms: 58917,
    sms_failed: 58918,
    snapchat: 60014,
    snippet_folder: 61895,
    snooze: 57414,
    snowboarding: 58643,
    snowing: 59407,
    snowmobile: 58627,
    snowshoeing: 58644,
    soap: 61874,
    social_distance: 57803,
    solar_power: 60431,
    sort: 57700,
    sort_by_alpha: 57427,
    sos: 60407,
    soup_kitchen: 59347,
    source: 61892,
    south: 61923,
    south_america: 59364,
    south_east: 61924,
    south_west: 61925,
    spa: 60236,
    space_bar: 57942,
    space_dashboard: 58987,
    spatial_audio: 60395,
    spatial_audio_off: 60392,
    spatial_tracking: 60394,
    speaker: 58157,
    speaker_group: 58158,
    speaker_notes: 59597,
    speaker_notes_off: 59690,
    speaker_phone: 57554,
    speed: 59876,
    spellcheck: 59598,
    splitscreen: 61549,
    spoke: 59815,
    sports: 59952,
    sports_bar: 61939,
    sports_baseball: 59985,
    sports_basketball: 59942,
    sports_cricket: 59943,
    sports_esports: 59944,
    sports_football: 59945,
    sports_golf: 59946,
    sports_gymnastics: 60356,
    sports_handball: 59955,
    sports_hockey: 59947,
    sports_kabaddi: 59956,
    sports_martial_arts: 60137,
    sports_mma: 59948,
    sports_motorsports: 59949,
    sports_rugby: 59950,
    sports_score: 61550,
    sports_soccer: 59951,
    sports_tennis: 59954,
    sports_volleyball: 59953,
    square: 60214,
    square_foot: 59977,
    ssid_chart: 60262,
    stacked_bar_chart: 59878,
    stacked_line_chart: 61995,
    stadium: 60304,
    stairs: 61865,
    star: 59448,
    star_border: 59450,
    star_border_purple500: 61593,
    star_half: 59449,
    star_outline: 61551,
    star_purple500: 61594,
    star_rate: 61676,
    stars: 59600,
    start: 57481,
    stay_current_landscape: 57555,
    stay_current_portrait: 57556,
    stay_primary_landscape: 57557,
    stay_primary_portrait: 57558,
    sticky_note_2: 61948,
    stop: 57415,
    stop_circle: 61297,
    stop_screen_share: 57571,
    storage: 57819,
    store: 59601,
    store_mall_directory: 58723,
    storefront: 59922,
    storm: 61552,
    straight: 60309,
    straighten: 58396,
    stream: 59881,
    streetview: 58734,
    strikethrough_s: 57943,
    stroller: 61870,
    style: 58397,
    subdirectory_arrow_left: 58841,
    subdirectory_arrow_right: 58842,
    subject: 59602,
    subscript: 61713,
    subscriptions: 57444,
    subtitles: 57416,
    subtitles_off: 61298,
    subway: 58735,
    summarize: 61553,
    sunny: 59418,
    sunny_snowing: 59417,
    superscript: 61714,
    supervised_user_circle: 59705,
    supervisor_account: 59603,
    support: 61299,
    support_agent: 61666,
    surfing: 58645,
    surround_sound: 57417,
    swap_calls: 57559,
    swap_horiz: 59604,
    swap_horizontal_circle: 59699,
    swap_vert: 59605,
    swap_vert_circle: 59606,
    swap_vertical_circle: 59606,
    swipe: 59884,
    swipe_down: 60243,
    swipe_down_alt: 60208,
    swipe_left: 60249,
    swipe_left_alt: 60211,
    swipe_right: 60242,
    swipe_right_alt: 60246,
    swipe_up: 60206,
    swipe_up_alt: 60213,
    swipe_vertical: 60241,
    switch_access_shortcut: 59361,
    switch_access_shortcut_add: 59362,
    switch_account: 59885,
    switch_camera: 58398,
    switch_left: 61905,
    switch_right: 61906,
    switch_video: 58399,
    synagogue: 60080,
    sync: 58919,
    sync_alt: 59928,
    sync_disabled: 58920,
    sync_lock: 60142,
    sync_problem: 58921,
    system_security_update: 61554,
    system_security_update_good: 61555,
    system_security_update_warning: 61556,
    system_update: 58922,
    system_update_alt: 59607,
    system_update_tv: 59607,
    tab: 59608,
    tab_unselected: 59609,
    table_bar: 60114,
    table_chart: 57957,
    table_restaurant: 60102,
    table_rows: 61697,
    table_view: 61886,
    tablet: 58159,
    tablet_android: 58160,
    tablet_mac: 58161,
    tag: 59887,
    tag_faces: 58400,
    takeout_dining: 60020,
    tap_and_play: 58923,
    tapas: 61929,
    task: 61557,
    task_alt: 58086,
    taxi_alert: 61300,
    telegram: 60011,
    temple_buddhist: 60083,
    temple_hindu: 60079,
    terminal: 60302,
    terrain: 58724,
    text_decrease: 60125,
    text_fields: 57954,
    text_format: 57701,
    text_increase: 60130,
    text_rotate_up: 59706,
    text_rotate_vertical: 59707,
    text_rotation_angledown: 59708,
    text_rotation_angleup: 59709,
    text_rotation_down: 59710,
    text_rotation_none: 59711,
    text_snippet: 61894,
    textsms: 57560,
    texture: 58401,
    theater_comedy: 60006,
    theaters: 59610,
    thermostat: 61558,
    thermostat_auto: 61559,
    thumb_down: 59611,
    thumb_down_alt: 59414,
    thumb_down_off_alt: 59890,
    thumb_up: 59612,
    thumb_up_alt: 59415,
    thumb_up_off_alt: 59891,
    thumbs_up_down: 59613,
    thunderstorm: 60379,
    tiktok: 60030,
    time_to_leave: 58924,
    timelapse: 58402,
    timeline: 59682,
    timer: 58405,
    timer_10: 58403,
    timer_10_select: 61562,
    timer_3: 58404,
    timer_3_select: 61563,
    timer_off: 58406,
    tips_and_updates: 59290,
    tire_repair: 60360,
    title: 57956,
    toc: 59614,
    today: 59615,
    toggle_off: 59893,
    toggle_on: 59894,
    token: 59941,
    toll: 59616,
    tonality: 58407,
    topic: 61896,
    tornado: 57753,
    touch_app: 59667,
    tour: 61301,
    toys: 58162,
    track_changes: 59617,
    traffic: 58725,
    train: 58736,
    tram: 58737,
    transcribe: 63724,
    transfer_within_a_station: 58738,
    transform: 58408,
    transgender: 58765,
    transit_enterexit: 58745,
    translate: 59618,
    travel_explore: 58075,
    trending_down: 59619,
    trending_flat: 59620,
    trending_neutral: 59620,
    trending_up: 59621,
    trip_origin: 58747,
    trolley: 63595,
    troubleshoot: 57810,
    try: 61564,
    tsunami: 60376,
    tty: 61866,
    tune: 58409,
    tungsten: 61565,
    turn_left: 60326,
    turn_right: 60331,
    turn_sharp_left: 60327,
    turn_sharp_right: 60330,
    turn_slight_left: 60324,
    turn_slight_right: 60314,
    turned_in: 59622,
    turned_in_not: 59623,
    tv: 58163,
    tv_off: 58951,
    two_wheeler: 59897,
    type_specimen: 63728,
    u_turn_left: 60321,
    u_turn_right: 60322,
    umbrella: 61869,
    unarchive: 57705,
    undo: 57702,
    unfold_less: 58838,
    unfold_less_double: 63695,
    unfold_more: 58839,
    unfold_more_double: 63696,
    unpublished: 62006,
    unsubscribe: 57579,
    upcoming: 61566,
    update: 59683,
    update_disabled: 57461,
    upgrade: 61691,
    upload: 61595,
    upload_file: 59900,
    usb: 57824,
    usb_off: 58618,
    vaccines: 57656,
    vape_free: 60358,
    vaping_rooms: 60367,
    verified: 61302,
    verified_user: 59624,
    vertical_align_bottom: 57944,
    vertical_align_center: 57945,
    vertical_align_top: 57946,
    vertical_distribute: 57462,
    vertical_shades: 60430,
    vertical_shades_closed: 60429,
    vertical_split: 59721,
    vibration: 58925,
    video_call: 57456,
    video_camera_back: 61567,
    video_camera_front: 61568,
    video_chat: 63648,
    video_collection: 57418,
    video_file: 60295,
    video_label: 57457,
    video_library: 57418,
    video_settings: 60021,
    video_stable: 61569,
    videocam: 57419,
    videocam_off: 57420,
    videogame_asset: 58168,
    videogame_asset_off: 58624,
    view_agenda: 59625,
    view_array: 59626,
    view_carousel: 59627,
    view_column: 59628,
    view_comfortable: 58410,
    view_comfy: 58410,
    view_comfy_alt: 60275,
    view_compact: 58411,
    view_compact_alt: 60276,
    view_cozy: 60277,
    view_day: 59629,
    view_headline: 59630,
    view_in_ar: 59902,
    view_kanban: 60287,
    view_list: 59631,
    view_module: 59632,
    view_quilt: 59633,
    view_sidebar: 61716,
    view_stream: 59634,
    view_timeline: 60293,
    view_week: 59635,
    vignette: 58421,
    villa: 58758,
    visibility: 59636,
    visibility_off: 59637,
    voice_chat: 58926,
    voice_over_off: 59722,
    voicemail: 57561,
    volcano: 60378,
    volume_down: 57421,
    volume_down_alt: 59292,
    volume_mute: 57422,
    volume_off: 57423,
    volume_up: 57424,
    volunteer_activism: 60016,
    vpn_key: 57562,
    vpn_key_off: 60282,
    vpn_lock: 58927,
    vrpano: 61570,
    wallet: 63743,
    wallet_giftcard: 59638,
    wallet_membership: 59639,
    wallet_travel: 59640,
    wallpaper: 57788,
    warehouse: 60344,
    warning: 57346,
    warning_amber: 61571,
    wash: 61873,
    watch: 58164,
    watch_later: 59684,
    watch_off: 60131,
    water: 61572,
    water_damage: 61955,
    water_drop: 59288,
    waterfall_chart: 59904,
    waves: 57718,
    waving_hand: 59238,
    wb_auto: 58412,
    wb_cloudy: 58413,
    wb_incandescent: 58414,
    wb_iridescent: 58422,
    wb_shade: 59905,
    wb_sunny: 58416,
    wb_twighlight: 59906,
    wb_twilight: 57798,
    wc: 58941,
    web: 57425,
    web_asset: 57449,
    web_asset_off: 58615,
    web_stories: 58773,
    webhook: 60306,
    wechat: 60033,
    weekend: 57707,
    west: 61926,
    whatshot: 59406,
    wheelchair_pickup: 61867,
    where_to_vote: 57719,
    widgets: 57789,
    width_full: 63733,
    width_normal: 63734,
    width_wide: 63735,
    wifi: 58942,
    wifi_1_bar: 58570,
    wifi_2_bar: 58585,
    wifi_calling: 61303,
    wifi_calling_3: 61573,
    wifi_channel: 60266,
    wifi_find: 60209,
    wifi_lock: 57825,
    wifi_off: 58952,
    wifi_password: 60267,
    wifi_protected_setup: 61692,
    wifi_tethering: 57826,
    wifi_tethering_error: 60121,
    wifi_tethering_error_rounded: 61574,
    wifi_tethering_off: 61575,
    wind_power: 60428,
    window: 61576,
    wine_bar: 61928,
    woman: 57662,
    woman_2: 63719,
    woo_commerce: 60013,
    wordpress: 60063,
    work: 59641,
    work_history: 60425,
    work_off: 59714,
    work_outline: 59715,
    workspace_premium: 59311,
    workspaces: 57760,
    workspaces_filled: 59917,
    workspaces_outline: 59919,
    wrap_text: 57947,
    wrong_location: 61304,
    wysiwyg: 61891,
    yard: 61577,
    youtube_searched_for: 59642,
    zoom_in: 59647,
    zoom_in_map: 60205,
    zoom_out: 59648,
    zoom_out_map: 58731
  };
  function iconCodepoint(name) {
    var _a, _b;
    const key = (name != null ? name : "star").toLowerCase().trim();
    return (_b = (_a = MATERIAL_ICON_CODEPOINTS[key]) != null ? _a : MATERIAL_ICON_CODEPOINTS[key.replace(/-/g, "_")]) != null ? _b : MATERIAL_ICON_CODEPOINTS.star;
  }

  // core/src/widgets/flutter.ts
  function first(children) {
    var _a;
    return (_a = children[0]) != null ? _a : null;
  }
  function num(v) {
    return toNumber(v);
  }
  function dispatchEvent(ctx, type, extra = {}) {
    var _a, _b;
    const { engine, elementId } = ctx;
    if (type === "change") engine.services.events.dispatchChange(elementId, extra.value);
    else if (type === "input") engine.services.events.dispatchInput(elementId, extra.value);
    else if (type === "submit") engine.services.events.dispatchSubmit(elementId, (_a = extra.data) != null ? _a : {});
    else if (type === "click") engine.services.events.dispatchClick(elementId, extra.position);
    else {
      const typeName = (_b = { tap: "tap", focus: "focus", blur: "blur", keydown: "keyDown", keyup: "keyUp", dismissed: "custom", drop: "drop" }[type]) != null ? _b : "custom";
      engine.services.events.dispatchEvent(makeEvent(type, typeName, elementId, extra), elementId);
    }
  }
  function materialButton(opts) {
    var _a, _b, _c, _d, _e, _f, _g, _h;
    const s = (_a = opts.style) != null ? _a : {};
    const enabled = opts.onPressed != null;
    const variant = (_b = opts.variant) != null ? _b : "elevated";
    const hasBg = s.backgroundColor != null || s.gradient != null;
    let bg = (_c = s.backgroundColor) != null ? _c : variant === "elevated" ? M3.surfaceContainerLow : variant === "filled" ? M3.primary : null;
    let fg = (_d = s.color) != null ? _d : variant === "filled" || hasBg ? Colors.white : M3.primary;
    if (!enabled) {
      bg = bg != null ? withOpacity(M3.onSurface, 0.12) : null;
      fg = withOpacity(M3.onSurface, 0.38);
    }
    const elevation = s.boxShadow && s.boxShadow.length ? s.boxShadow[0].blur / 2 : variant === "elevated" && enabled ? 1 : 0;
    const decoration = {
      color: bg,
      gradients: s.gradient ? [s.gradient] : null,
      radius: (_e = s.borderRadius) != null ? _e : null,
      radiusPercent: s.borderRadius ? null : radiusAll(50),
      shadows: s.boxShadow && s.boxShadow.length ? s.boxShadow : elevationShadows(elevation),
      border: variant === "outlined" ? { top: side(M3.outline), right: side(M3.outline), bottom: side(M3.outline), left: side(M3.outline) } : (_f = s.border) != null ? _f : null
    };
    const pad = (_g = s.padding) != null ? _g : insetsSymmetric(0, 24);
    let content = w("defaultTextStyle", { style: __spreadProps(__spreadValues({}, LABEL_LARGE), { color: fg }) }, align({ x: 0, y: 0 }, opts.child, { widthFactor: 1, heightFactor: 1 }));
    content = padding(pad, content);
    content = w("constrained", { minWidth: 64, minHeight: 40 }, content);
    content = w("decorated", { decoration }, content);
    content = w(
      "gesture",
      {
        gestures: enabled ? ["tap"] : [],
        ripple: enabled ? scaleAlpha(fg, 0.12) : null,
        cursor: enabled ? "pointer" : "default",
        role: "button",
        semanticsLabel: (_h = opts.semanticsLabel) != null ? _h : null,
        onEvent: (e) => {
          var _a2;
          if (e.type === "tap") (_a2 = opts.onPressed) == null ? void 0 : _a2.call(opts);
        }
      },
      content
    );
    return padding({ top: 4, right: 0, bottom: 4, left: 0 }, content);
  }
  function side(color) {
    return { width: 1, color, style: "solid" };
  }
  function buttonOuter(result, style) {
    var _a, _b, _c;
    if (!style) return result;
    if (style.margin) result = padding(style.margin, result);
    if (style.opacity != null && style.opacity < 1) result = w("opacity", { opacity: style.opacity }, result);
    if (style.width != null || style.height != null) result = sizedBox((_a = style.width) != null ? _a : null, (_b = style.height) != null ? _b : null, result);
    if (style.flex != null || style.flexGrow != null) result = w("flexible", { flex: (_c = style.flex) != null ? _c : style.flexGrow, fit: "tight" }, result);
    return result;
  }
  function buttonPressed(ctx) {
    return () => {
      dispatchEvent(ctx, "click");
      dispatchEvent(ctx, "tap");
    };
  }
  function iconGlyph(name, size, color) {
    const glyph = String.fromCodePoint(iconCodepoint(name));
    return sizedBox(
      size,
      size,
      center(text(glyph, { fontFamily: "icons", fontSize: size, color: color != null ? color : M3.onSurfaceVariant, height: 1, letterSpacing: 0, wordSpacing: 0, decoration: 0 }, { softWrap: false }))
    );
  }
  function icon(name, size = 24, color = null) {
    return iconGlyph(name, size, color);
  }
  function parseAlignmentProp(v, fallback) {
    var _a;
    return (_a = CSSParser.parseAlignment(v)) != null ? _a : fallback;
  }
  var flutterWidgets = {
    Container(node, children, ctx) {
      let child = null;
      if (children.length === 1) child = children[0];
      else if (children.length > 1) child = column(children, { crossAxisAlignment: "start", mainAxisSize: "min" });
      const p = node.props;
      const decoration = p.decoration && typeof p.decoration === "object" ? decorationFromStyle(CSSParser.parse(p.decoration), ctx) : null;
      let result = container({
        child,
        width: num(p.width),
        height: num(p.height),
        padding: CSSParser.parseEdgeInsets(p.padding),
        margin: CSSParser.parseEdgeInsets(p.margin),
        alignment: CSSParser.parseAlignment(p.alignment),
        decoration
      });
      return applyStyle(result, node.style, {}, ctx);
    },
    Text(node, _children, ctx) {
      const value = textOf(node);
      const style = createTextStyle(node.style);
      const opts = __spreadValues({}, textOptionsFromStyle(node.style));
      if (typeof node.props.textAlign === "string") opts.align = node.props.textAlign;
      if (num(node.props.maxLines) != null) opts.maxLines = num(node.props.maxLines);
      if (typeof node.props.overflow === "string") opts.overflow = node.props.overflow;
      if (typeof node.props.softWrap === "boolean") opts.softWrap = node.props.softWrap;
      if (node.props.selectable === true) opts.selectable = true;
      return applyStyle(text(value, style, opts), node.style, {}, ctx);
    },
    Button(node, children, ctx) {
      var _a, _b, _c;
      const label = String((_a = node.props.text) != null ? _a : "Button");
      const s = node.style;
      const fg = (_b = s == null ? void 0 : s.color) != null ? _b : (s == null ? void 0 : s.backgroundColor) != null ? Colors.white : M3.primary;
      const child = (_c = first(children)) != null ? _c : text(label, { color: fg });
      const enabled = node.props.disabled !== true && node.props.enabled !== false;
      return buttonOuter(materialButton({ child, style: s, onPressed: enabled ? buttonPressed(ctx) : null, semanticsLabel: label }), s);
    },
    Image(node, _children, ctx) {
      var _a, _b, _c, _d, _e, _f;
      const raw = String((_a = node.props.src) != null ? _a : "");
      const fit = typeof node.props.fit === "string" ? node.props.fit : "contain";
      const src = ctx.engine.resolveUrl(raw);
      const result = w("image", {
        src,
        fit,
        width: (_c = (_b = node.style) == null ? void 0 : _b.width) != null ? _c : num(node.props.width),
        height: (_e = (_d = node.style) == null ? void 0 : _d.height) != null ? _e : num(node.props.height),
        alt: (_f = node.props.alt) != null ? _f : null,
        onEvent: (e) => {
          if (e.type === "load" || e.type === "error") dispatchEvent(ctx, e.type, { value: e.value });
        }
      });
      return applyStyle(result, node.style, {}, ctx);
    },
    Column(node, children, ctx) {
      return applyStyle(flexOrWrap("column", node.style, children), node.style, {}, ctx);
    },
    Row(node, children, ctx) {
      return applyStyle(flexOrWrap("row", node.style, children), node.style, {}, ctx);
    },
    Stack(node, children, ctx) {
      var _a, _b;
      const alignment = (_b = (_a = node.style) == null ? void 0 : _a.alignment) != null ? _b : { x: 0, y: 0 };
      return applyStyle(w("stack", { alignment, fit: "loose" }, children), node.style, {}, ctx);
    },
    Positioned(node, children) {
      var _a, _b, _c, _d, _e, _f, _g, _h;
      const s = (_a = node.style) != null ? _a : {};
      return w(
        "positioned",
        { top: (_b = s.top) != null ? _b : null, right: (_c = s.right) != null ? _c : null, bottom: (_d = s.bottom) != null ? _d : null, left: (_e = s.left) != null ? _e : null, width: (_f = s.width) != null ? _f : null, height: (_g = s.height) != null ? _g : null },
        (_h = first(children)) != null ? _h : container({})
      );
    },
    Expanded(node, children) {
      var _a, _b;
      return w("flexible", { flex: (_a = num(node.props.flex)) != null ? _a : 1, fit: "tight" }, (_b = first(children)) != null ? _b : container({}));
    },
    Flexible(node, children) {
      var _a, _b;
      return w("flexible", { flex: (_a = num(node.props.flex)) != null ? _a : 1, fit: node.props.fit === "tight" ? "tight" : "loose" }, (_b = first(children)) != null ? _b : container({}));
    },
    Center(node, children, ctx) {
      var _a;
      return applyStyle(center((_a = first(children)) != null ? _a : container({})), node.style, {}, ctx);
    },
    Padding(node, children) {
      var _a, _b, _c, _d;
      return padding((_b = (_a = node.style) == null ? void 0 : _a.padding) != null ? _b : insetsAll(8), (_c = first(children)) != null ? _c : container({}), (_d = node.style) == null ? void 0 : _d.paddingPercent);
    },
    Align(node, children) {
      var _a, _b, _c;
      return align((_b = (_a = node.style) == null ? void 0 : _a.alignment) != null ? _b : { x: 0, y: 0 }, (_c = first(children)) != null ? _c : container({}));
    },
    SizedBox(node, children) {
      var _a, _b, _c, _d;
      return sizedBox((_b = (_a = node.style) == null ? void 0 : _a.width) != null ? _b : num(node.props.width), (_d = (_c = node.style) == null ? void 0 : _c.height) != null ? _d : num(node.props.height), first(children));
    },
    ListView(node, children, ctx) {
      const scrollable = node.props.scrollable !== false;
      const list2 = w("flex", { direction: "column", crossAxisAlignment: "stretch", mainAxisSize: "min" }, children);
      const result = w("scroll", { axis: node.props.scrollDirection === "horizontal" ? "horizontal" : "vertical", enabled: scrollable }, list2);
      return applyStyle(result, node.style, {}, ctx);
    },
    GridView(node, children, ctx) {
      var _a, _b, _c, _d;
      const count = Math.max(1, (_a = num(node.props.crossAxisCount)) != null ? _a : 2);
      const spacing = (_b = num(node.props.crossAxisSpacing)) != null ? _b : 0;
      const mainSpacing = (_c = num(node.props.mainAxisSpacing)) != null ? _c : 0;
      const ratio = (_d = num(node.props.childAspectRatio)) != null ? _d : 1;
      const grid = w(
        "grid",
        { columns: `repeat(${count}, 1fr)`, columnGap: spacing, rowGap: mainSpacing, alignItems: "stretch" },
        children.map((c) => w("aspectRatio", { aspectRatio: ratio }, c))
      );
      return applyStyle(w("scroll", { axis: "vertical", enabled: node.props.scrollable !== false }, grid), node.style, {}, ctx);
    },
    TextField(node, _children, ctx) {
      var _a, _b, _c, _d, _e, _f;
      const state = ctx.engine.stateFor(ctx.elementId, () => {
        var _a2;
        return { value: String((_a2 = node.props.value) != null ? _a2 : "") };
      });
      const s = node.style;
      const textStyle = __spreadValues(__spreadValues({}, BODY_LARGE), (_a = createTextStyle(s)) != null ? _a : {});
      const lines = Math.max(1, (_b = num(node.props.maxLines)) != null ? _b : 1);
      const result = w("control", {
        kind: "textInput",
        lines: node.props.multiline ? Math.max(lines, 3) : lines,
        padding: [12, 0, 12, 0],
        view: {
          value: state.value,
          placeholder: String((_d = (_c = node.props.hint) != null ? _c : node.props.placeholder) != null ? _d : ""),
          inputType: node.props.obscureText ? "password" : (_e = node.props.keyboardType) != null ? _e : "text",
          multiline: lines > 1 || !!node.props.multiline,
          maxLines: lines,
          maxLength: num(node.props.maxLength),
          enabled: node.props.enabled !== false,
          readOnly: node.props.readOnly === true,
          autofocus: node.props.autofocus === true,
          variant: "underline",
          textStyle: toSpec(textStyle),
          hintStyle: toSpec(__spreadProps(__spreadValues({}, textStyle), { color: M3.onSurfaceVariant })),
          contentPadding: [12, 0, 12, 0],
          colors: { text: (_f = textStyle.color) != null ? _f : M3.onSurface, hint: M3.onSurfaceVariant, border: M3.onSurfaceVariant, focusedBorder: M3.primary, cursor: M3.primary, fill: null }
        },
        onEvent: (e) => {
          var _a2;
          if (e.type === "input" || e.type === "change") {
            state.value = String((_a2 = e.value) != null ? _a2 : "");
            dispatchEvent(ctx, "input", { value: state.value });
          } else if (e.type === "submit") dispatchEvent(ctx, "submit");
          else if (e.type === "focus" || e.type === "blur") dispatchEvent(ctx, e.type);
        }
      });
      return applyStyle(result, s, {}, ctx);
    },
    Checkbox(node, _children, ctx) {
      var _a, _b;
      const value = node.props.value === true;
      return w("control", {
        kind: "checkbox",
        view: { checked: value, enabled: node.props.enabled !== false, colors: { fill: (_b = (_a = node.style) == null ? void 0 : _a.color) != null ? _b : M3.primary, check: M3.onPrimary, border: M3.onSurfaceVariant } },
        controlled: true,
        onEvent: (e) => {
          if (e.type === "change") dispatchEvent(ctx, "change", { value: !!e.value });
        }
      });
    },
    Radio(node, _children, ctx) {
      var _a, _b;
      const value = node.props.value;
      const group = node.props.groupValue;
      return w("control", {
        kind: "radio",
        view: { checked: value === group && value !== void 0, value: value != null ? value : null, colors: { fill: (_b = (_a = node.style) == null ? void 0 : _a.color) != null ? _b : M3.primary, border: M3.onSurfaceVariant } },
        controlled: true,
        onEvent: (e) => {
          if (e.type === "change") dispatchEvent(ctx, "change", { value });
        }
      });
    },
    Switch(node, _children, ctx) {
      var _a, _b;
      const value = node.props.value === true;
      return w("control", {
        kind: "switch",
        view: {
          checked: value,
          enabled: node.props.enabled !== false,
          colors: { trackOn: (_b = (_a = node.style) == null ? void 0 : _a.color) != null ? _b : M3.primary, thumbOn: M3.onPrimary, trackOff: M3.surfaceContainerHighest, thumbOff: M3.outline, outline: M3.outline }
        },
        controlled: true,
        onEvent: (e) => {
          if (e.type === "change") dispatchEvent(ctx, "change", { value: !!e.value });
        }
      });
    },
    Slider(node, _children, ctx) {
      var _a, _b, _c, _d, _e, _f, _g;
      const min = (_a = num(node.props.min)) != null ? _a : 0;
      const max = (_b = num(node.props.max)) != null ? _b : 1;
      const value = Math.max(min, Math.min(max, (_c = num(node.props.value)) != null ? _c : 0.5));
      const divisions = num(node.props.divisions);
      return w("control", {
        kind: "slider",
        view: {
          value,
          min,
          max,
          step: divisions && divisions > 0 ? (max - min) / divisions : null,
          enabled: node.props.enabled !== false,
          colors: { active: (_e = (_d = node.style) == null ? void 0 : _d.color) != null ? _e : M3.primary, inactive: M3.secondaryContainer, thumb: (_g = (_f = node.style) == null ? void 0 : _f.color) != null ? _g : M3.primary }
        },
        controlled: true,
        onEvent: (e) => {
          if (e.type === "change" || e.type === "input") dispatchEvent(ctx, "change", { value: Number(e.value) });
        }
      });
    },
    Icon(node, _children, ctx) {
      var _a, _b, _c, _d, _e, _f;
      const name = String((_a = node.props.icon) != null ? _a : "star");
      const size = (_d = (_c = (_b = node.style) == null ? void 0 : _b.fontSize) != null ? _c : num(node.props.size)) != null ? _d : 24;
      return applyStyle(icon(name, size, (_f = (_e = node.style) == null ? void 0 : _e.color) != null ? _f : null), node.style, {}, ctx);
    },
    Card(node, children, ctx) {
      var _a, _b, _c, _d, _e;
      const s = (_a = node.style) != null ? _a : {};
      let child = children.length === 0 ? SHRINK : children.length === 1 ? children[0] : column(children);
      const elevation = s.boxShadow && s.boxShadow.length ? s.boxShadow[0].blur / 2 : (_b = num(node.props.elevation)) != null ? _b : 1;
      if (s.padding) child = padding(s.padding, child);
      const border = s.borderColor != null ? { width: (_c = s.borderWidth) != null ? _c : 1, color: s.borderColor, style: "solid" } : null;
      const radius = (_d = s.borderRadius) != null ? _d : radiusAll(12);
      let result = w("clip", { radius }, child);
      result = decorated(
        {
          color: (_e = s.backgroundColor) != null ? _e : M3.surfaceContainerLow,
          radius,
          shadows: elevationShadows(elevation),
          border: border ? { top: border, right: border, bottom: border, left: border } : null
        },
        result
      );
      result = padding(insetsAll(4), result);
      const external = {
        width: s.width,
        height: s.height,
        minWidth: s.minWidth,
        maxWidth: s.maxWidth,
        minHeight: s.minHeight,
        maxHeight: s.maxHeight,
        margin: s.margin,
        opacity: s.opacity,
        flex: s.flex,
        transform: s.transform,
        rotate: s.rotate,
        scale: s.scale,
        alignment: s.alignment,
        visible: s.visible
      };
      for (const k of Object.keys(external)) if (external[k] == null) delete external[k];
      return applyStyle(result, external, {}, ctx);
    },
    Scaffold(node, children, ctx) {
      var _a, _b;
      let appBar = null;
      let fab = null;
      let bottom = null;
      const body = [];
      node.children.forEach((child, i) => {
        const slot = child.props.slot;
        if (child.type === "AppBar" || slot === "appBar") appBar = children[i];
        else if (slot === "floatingActionButton" || child.type === "FloatingActionButton") fab = children[i];
        else if (slot === "bottomNavigationBar" || slot === "bottomBar") bottom = children[i];
        else body.push(children[i]);
      });
      const bodyW = body.length ? body[body.length - 1] : SHRINK;
      const columnChildren = [];
      if (appBar) columnChildren.push(appBar);
      columnChildren.push(expanded(w("align", { alignment: { x: -1, y: -1 } }, bodyW)));
      if (bottom) columnChildren.push(bottom);
      let result = w("flex", { direction: "column", crossAxisAlignment: "stretch", mainAxisSize: "max" }, columnChildren);
      if (fab) {
        result = w("stack", { alignment: { x: -1, y: -1 }, fit: "expand" }, [result, w("positioned", { right: 16, bottom: 16 + (bottom ? 80 : 0) }, fab)]);
      }
      result = decorated({ color: (_b = (_a = node.style) == null ? void 0 : _a.backgroundColor) != null ? _b : M3.surface }, w("defaultTextStyle", { style: {} }, result));
      return result;
    },
    AppBar(node, children, ctx) {
      var _a, _b, _c, _d, _e;
      const title = String((_a = node.props.title) != null ? _a : "");
      const s = (_b = node.style) != null ? _b : {};
      const fg = (_c = s.color) != null ? _c : M3.onSurface;
      const row1 = [];
      const leading = node.children.findIndex((c) => c.props.slot === "leading");
      if (leading >= 0) row1.push(padding({ top: 0, right: 0, bottom: 0, left: 4 }, sizedBox(48, 48, center(children[leading]))));
      row1.push(expanded(padding({ top: 0, right: 16, bottom: 0, left: 16 }, text(title, __spreadProps(__spreadValues({}, TITLE_LARGE), { color: fg }), { maxLines: 1, overflow: "ellipsis", softWrap: false }))));
      node.children.forEach((c, i) => {
        if (i !== leading && c.props.slot !== "title") row1.push(children[i]);
      });
      let bar = sizedBox(null, (_d = s.height) != null ? _d : 64, w("flex", { direction: "row", crossAxisAlignment: "center", mainAxisSize: "max" }, row1));
      if (node.props.primary !== false) bar = w("safeArea", { top: true }, bar);
      return decorated({ color: (_e = s.backgroundColor) != null ? _e : M3.surface, shadows: num(node.props.elevation) ? elevationShadows(num(node.props.elevation)) : null }, w("defaultTextStyle", { style: { color: fg } }, bar));
    },
    Wrap(node, children, ctx) {
      var _a, _b;
      const s = node.style;
      const result = w("wrap", { direction: "horizontal", spacing: (_a = s == null ? void 0 : s.gap) != null ? _a : 8, runSpacing: (_b = s == null ? void 0 : s.rowGap) != null ? _b : 8, alignment: "start" }, children);
      return applyStyle(result, s, {}, ctx);
    },
    InkWell(node, children, ctx) {
      var _a, _b, _c;
      const child = (_a = first(children)) != null ? _a : container({});
      const result = w("gesture", { gestures: ["tap"], ripple: scaleAlpha((_c = (_b = node.style) == null ? void 0 : _b.color) != null ? _c : M3.onSurface, 0.12), cursor: "pointer", onEvent: () => {
      } }, child);
      return applyStyle(result, node.style, {}, ctx);
    },
    GestureDetector(_node, children) {
      var _a;
      return w("proxy", {}, (_a = first(children)) != null ? _a : container({}));
    },
    Opacity(node, children) {
      var _a, _b, _c, _d;
      const opacity = (_c = (_b = (_a = node.style) == null ? void 0 : _a.opacity) != null ? _b : num(node.props.opacity)) != null ? _c : 1;
      return w("opacity", { opacity }, (_d = first(children)) != null ? _d : container({}));
    },
    Transform(node, children) {
      var _a, _b, _c, _d, _e;
      let m = (_b = (_a = node.style) == null ? void 0 : _a.transform) != null ? _b : identity();
      if (((_c = node.style) == null ? void 0 : _c.rotate) != null) m = rotationZ(node.style.rotate * Math.PI / 180);
      if (((_d = node.style) == null ? void 0 : _d.scale) != null) m = scaling(node.style.scale, node.style.scale, 1);
      return w("transform", { transform: m, alignment: { x: 0, y: 0 } }, (_e = first(children)) != null ? _e : container({}));
    },
    ClipRRect(node, children) {
      var _a, _b, _c;
      return w("clip", { radius: (_b = (_a = node.style) == null ? void 0 : _a.borderRadius) != null ? _b : radiusAll(8) }, (_c = first(children)) != null ? _c : container({}));
    },
    ConstrainedBox(node, children) {
      var _a, _b, _c, _d, _e, _f;
      const s = (_a = node.style) != null ? _a : {};
      return w("constrained", { minWidth: (_b = s.minWidth) != null ? _b : 0, maxWidth: (_c = s.maxWidth) != null ? _c : null, minHeight: (_d = s.minHeight) != null ? _d : 0, maxHeight: (_e = s.maxHeight) != null ? _e : null }, (_f = first(children)) != null ? _f : container({}));
    },
    AspectRatio(node, children) {
      var _a, _b, _c, _d;
      return w("aspectRatio", { aspectRatio: (_c = (_b = num(node.props.aspectRatio)) != null ? _b : (_a = node.style) == null ? void 0 : _a.aspectRatio) != null ? _c : 1 }, (_d = first(children)) != null ? _d : container({}));
    },
    FractionallySizedBox(node, children) {
      var _a, _b;
      return w(
        "fractional",
        { widthFactor: num(node.props.widthFactor), heightFactor: num(node.props.heightFactor), alignment: (_b = (_a = node.style) == null ? void 0 : _a.alignment) != null ? _b : { x: 0, y: 0 } },
        first(children)
      );
    },
    FittedBox(node, children) {
      var _a, _b, _c;
      const fit = typeof node.props.fit === "string" ? node.props.fit : "contain";
      return w("fitted", { fit, alignment: (_b = (_a = node.style) == null ? void 0 : _a.alignment) != null ? _b : { x: 0, y: 0 } }, w("fittedContent", {}, (_c = first(children)) != null ? _c : container({})));
    },
    LimitedBox(node, children) {
      var _a, _b, _c, _d, _e;
      return w("limited", { maxWidth: (_b = (_a = node.style) == null ? void 0 : _a.maxWidth) != null ? _b : null, maxHeight: (_d = (_c = node.style) == null ? void 0 : _c.maxHeight) != null ? _d : null }, (_e = first(children)) != null ? _e : container({}));
    },
    OverflowBox(node, children) {
      var _a, _b, _c, _d, _e, _f, _g;
      const s = (_a = node.style) != null ? _a : {};
      return w(
        "overflowBox",
        { alignment: (_b = s.alignment) != null ? _b : { x: 0, y: 0 }, minWidth: (_c = s.minWidth) != null ? _c : null, maxWidth: (_d = s.maxWidth) != null ? _d : null, minHeight: (_e = s.minHeight) != null ? _e : null, maxHeight: (_f = s.maxHeight) != null ? _f : null },
        (_g = first(children)) != null ? _g : container({})
      );
    },
    Baseline(node, children) {
      var _a, _b;
      return w("baseline", { baseline: (_a = num(node.props.baseline)) != null ? _a : 0 }, (_b = first(children)) != null ? _b : container({}));
    },
    Spacer(node) {
      var _a;
      return w("flexible", { flex: (_a = num(node.props.flex)) != null ? _a : 1, fit: "tight" }, SHRINK);
    },
    Divider(node) {
      var _a, _b, _c, _d, _e, _f, _g;
      const s = (_a = node.style) != null ? _a : {};
      const thickness = (_b = s.borderWidth) != null ? _b : 1;
      const height = (_c = s.height) != null ? _c : 16;
      const indent = (_d = num(node.props.indent)) != null ? _d : 0;
      const endIndent = (_e = num(node.props.endIndent)) != null ? _e : 0;
      return sizedBox(
        null,
        height,
        center(padding({ top: 0, right: endIndent, bottom: 0, left: indent }, container({ height: thickness, decoration: { color: (_g = (_f = s.borderColor) != null ? _f : s.color) != null ? _g : M3.outlineVariant } })))
      );
    },
    VerticalDivider(node) {
      var _a, _b, _c, _d, _e;
      const s = (_a = node.style) != null ? _a : {};
      const thickness = (_b = s.borderWidth) != null ? _b : 1;
      const width = (_c = s.width) != null ? _c : 16;
      return sizedBox(width, null, center(container({ width: thickness, decoration: { color: (_e = (_d = s.borderColor) != null ? _d : s.color) != null ? _e : M3.outlineVariant } })));
    },
    CircularProgressIndicator(node) {
      var _a, _b, _c, _d, _e, _f;
      const value = num(node.props.value);
      return w("control", {
        kind: "progress",
        view: {
          variant: "circular",
          value,
          strokeWidth: (_b = (_a = node.style) == null ? void 0 : _a.borderWidth) != null ? _b : 4,
          colors: { indicator: (_d = (_c = node.style) == null ? void 0 : _c.color) != null ? _d : M3.primary, track: (_f = (_e = node.style) == null ? void 0 : _e.backgroundColor) != null ? _f : null }
        }
      });
    },
    LinearProgressIndicator(node) {
      var _a, _b, _c, _d, _e;
      const value = num(node.props.value);
      return w("control", {
        kind: "progress",
        view: {
          variant: "linear",
          value,
          strokeWidth: (_a = num(node.props.minHeight)) != null ? _a : 4,
          colors: { indicator: (_c = (_b = node.style) == null ? void 0 : _b.color) != null ? _c : M3.primary, track: (_e = (_d = node.style) == null ? void 0 : _d.backgroundColor) != null ? _e : M3.secondaryContainer }
        }
      });
    },
    Tooltip(node, children) {
      var _a, _b;
      return w("gesture", { gestures: ["longpress", "hover"], tooltip: String((_a = node.props.message) != null ? _a : ""), onEvent: () => {
      } }, (_b = first(children)) != null ? _b : container({}));
    },
    Badge(node, children) {
      var _a, _b, _c, _d, _e;
      const label = node.props.label != null ? String(node.props.label) : "";
      const child = (_a = first(children)) != null ? _a : container({});
      const s = (_b = node.style) != null ? _b : {};
      const pill = label === "" ? container({ width: 6, height: 6, decoration: { color: (_c = s.backgroundColor) != null ? _c : M3.error, shape: "circle" } }) : container({
        minWidth: 16,
        height: 16,
        padding: insetsSymmetric(0, 4),
        alignment: { x: 0, y: 0 },
        decoration: { color: (_d = s.backgroundColor) != null ? _d : M3.error, radius: radiusAll(8) },
        child: text(label, { fontSize: 11, fontWeight: 500, letterSpacing: 0.5, height: 16 / 11, color: (_e = s.color) != null ? _e : Colors.white }, { softWrap: false })
      });
      return w("stack", { alignment: { x: -1, y: -1 }, fit: "loose" }, [child, w("positioned", { top: label === "" ? 0 : -4, right: label === "" ? 0 : -4 }, pill)]);
    },
    Chip(node, children) {
      var _a, _b, _c, _d, _e;
      const label = String((_a = node.props.label) != null ? _a : "");
      const s = (_b = node.style) != null ? _b : {};
      const content = [];
      const avatar = node.children.findIndex((c) => c.props.slot === "avatar");
      if (avatar >= 0) content.push(padding({ top: 0, right: 8, bottom: 0, left: 0 }, sizedBox(18, 18, children[avatar])));
      content.push(text(label, __spreadProps(__spreadValues({}, LABEL_LARGE), { color: (_c = s.color) != null ? _c : M3.onSurfaceVariant }), { softWrap: false }));
      return padding(
        insetsSymmetric(8, 0),
        container({
          minHeight: 32,
          padding: insetsSymmetric(6, 16),
          alignment: null,
          decoration: { color: (_d = s.backgroundColor) != null ? _d : null, radius: (_e = s.borderRadius) != null ? _e : radiusAll(8), border: { top: side(M3.outlineVariant), right: side(M3.outlineVariant), bottom: side(M3.outlineVariant), left: side(M3.outlineVariant) } },
          child: w("flex", { direction: "row", crossAxisAlignment: "center", mainAxisSize: "min" }, content)
        })
      );
    },
    Dismissible(node, children, ctx) {
      var _a, _b;
      const state = ctx.engine.stateFor(ctx.elementId, () => ({ dismissed: false }));
      const child = (_a = first(children)) != null ? _a : container({});
      if (state.dismissed) return SHRINK;
      return w("gesture", {
        gestures: ["dismiss"],
        dismissDirection: String((_b = node.props.direction) != null ? _b : "horizontal"),
        onEvent: (e) => {
          var _a2, _b2, _c, _d, _e;
          if (e.type === "dismissed") {
            state.dismissed = true;
            dispatchEvent(ctx, "dismissed", { data: { direction: (_a2 = e.direction) != null ? _a2 : null } });
            if ((_b2 = node.events) == null ? void 0 : _b2.dismiss) dispatchEvent(ctx, "dismiss", { data: { direction: (_c = e.direction) != null ? _c : null } });
            (_e = (_d = ctx.engine.host).invalidate) == null ? void 0 : _e.call(_d);
          }
        }
      }, child);
    },
    Draggable(node, children, ctx) {
      var _a, _b;
      const child = (_a = first(children)) != null ? _a : container({});
      return w("gesture", {
        gestures: ["draggable"],
        dragData: (_b = node.props.data) != null ? _b : null,
        onEvent: (e) => {
          var _a2, _b2, _c;
          if (e.type === "dragstart") dispatchEvent(ctx, "dragstart", { data: { data: (_a2 = node.props.data) != null ? _a2 : null } });
          else if (e.type === "dragupdate") ctx.engine.dragOver(ctx.elementId, e, (_b2 = node.props.data) != null ? _b2 : null);
          else if (e.type === "dragend" || e.type === "drop") ctx.engine.dropAt(ctx.elementId, e, (_c = node.props.data) != null ? _c : null);
        }
      }, child);
    },
    DragTarget(node, children, ctx) {
      var _a;
      const child = (_a = first(children)) != null ? _a : container({});
      return w("gesture", { gestures: [], dragTargetId: ctx.elementId, onEvent: () => {
      } }, child, `dt:${ctx.elementId}`);
    },
    Hero(node, children) {
      var _a, _b;
      return w("hero", { tag: (_a = node.props.tag) != null ? _a : "hero" }, (_b = first(children)) != null ? _b : container({}));
    },
    IndexedStack(node, children) {
      var _a;
      return w("indexedStack", { index: (_a = num(node.props.index)) != null ? _a : 0, alignment: parseAlignmentProp(node.props.alignment, { x: -1, y: -1 }) }, children);
    },
    RotatedBox(node, children) {
      var _a, _b;
      return w("rotatedBox", { quarterTurns: (_a = num(node.props.quarterTurns)) != null ? _a : 0 }, (_b = first(children)) != null ? _b : container({}));
    },
    DecoratedBox(node, children, ctx) {
      var _a, _b;
      const s = (_a = node.style) != null ? _a : {};
      const d = decorationFromStyle(s, ctx);
      return decorated(d, (_b = first(children)) != null ? _b : container({}));
    },
    Scope(_node, children) {
      if (children.length === 0) return SHRINK;
      if (children.length === 1) return children[0];
      return column(children);
    },
    Canvas(node, _children, ctx) {
      var _a, _b, _c, _d, _e, _f, _g, _h, _i;
      const raw = Array.isArray(node.props.commands) ? node.props.commands : [];
      const commands = raw.filter((c) => c && typeof c === "object").map((c) => normalizeCommand(commandFromJson(c)));
      const bg = (_c = (_b = CSSParser.parseColor(node.props.backgroundColor)) != null ? _b : (_a = node.style) == null ? void 0 : _a.backgroundColor) != null ? _c : null;
      return w("canvas", {
        width: (_f = (_e = num(node.props.width)) != null ? _e : (_d = node.style) == null ? void 0 : _d.width) != null ? _f : null,
        height: (_i = (_h = num(node.props.height)) != null ? _h : (_g = node.style) == null ? void 0 : _g.height) != null ? _i : null,
        background: bg,
        commands,
        onEvent: (e) => ctx.engine.handleGesture(ctx.elementId, node, e)
      });
    },
    CachedCanvas(node, _children, ctx) {
      var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j, _k, _l;
      const id2 = String((_b = (_a = node.props.contextId) != null ? _a : node.props.id) != null ? _b : "");
      if (!id2) return SHRINK;
      const store = ctx.engine.services.canvasContexts;
      const c = (_c = store.get(ctx.engine.services.scopeId(id2))) != null ? _c : store.get(id2);
      const width = (_f = (_e = num(node.props.width)) != null ? _e : (_d = node.style) == null ? void 0 : _d.width) != null ? _f : null;
      const height = (_i = (_h = num(node.props.height)) != null ? _h : (_g = node.style) == null ? void 0 : _g.height) != null ? _i : null;
      if (!c) return SHRINK;
      if (width != null && height != null) c.setSize(width, height);
      const bg = (_l = (_k = CSSParser.parseColor(node.props.backgroundColor)) != null ? _k : (_j = node.style) == null ? void 0 : _j.backgroundColor) != null ? _l : null;
      return w("canvas", {
        width: width != null ? width : c.width,
        height: height != null ? height : c.height,
        background: bg,
        context: { id: c.id, version: c.version, generation: c.generation, commands: c.commands }
      });
    },
    Scene3D(node, children, ctx) {
      return scene3d(node, children, ctx);
    },
    scene3d(node, children, ctx) {
      return scene3d(node, children, ctx);
    },
    MathExpression(node, _children, ctx) {
      return mathExpression(node, ctx);
    },
    Math(node, _children, ctx) {
      return mathExpression(node, ctx);
    }
  };
  function flexOrWrap(direction, style, children) {
    var _a;
    const gap = (_a = style == null ? void 0 : style.gap) != null ? _a : 0;
    const wraps = (style == null ? void 0 : style.flexWrap) === "wrap" || (style == null ? void 0 : style.flexWrap) === "wrap-reverse";
    const main = style == null ? void 0 : style.justifyContent;
    const cross = style == null ? void 0 : style.alignItems;
    const mainMap = (v) => {
      switch ((v != null ? v : "").toLowerCase()) {
        case "center":
          return "center";
        case "flex-end":
        case "end":
          return "end";
        case "space-between":
          return "spaceBetween";
        case "space-around":
          return "spaceAround";
        case "space-evenly":
          return "spaceEvenly";
        default:
          return "start";
      }
    };
    const crossMap = (v) => {
      switch ((v != null ? v : "").toLowerCase()) {
        case "center":
          return "center";
        case "flex-end":
        case "end":
          return "end";
        case "stretch":
          return "stretch";
        case "baseline":
          return "baseline";
        default:
          return "start";
      }
    };
    if (wraps) {
      return w("wrap", {
        direction: direction === "row" ? "horizontal" : "vertical",
        spacing: gap,
        runSpacing: gap,
        alignment: mainMap(main),
        crossAxisAlignment: crossMap(cross) === "stretch" || crossMap(cross) === "baseline" ? "start" : crossMap(cross),
        verticalDirection: (style == null ? void 0 : style.flexWrap) === "wrap-reverse" ? "up" : "down"
      }, children);
    }
    return w("flex", { direction, mainAxisAlignment: mainMap(main), crossAxisAlignment: crossMap(cross), mainAxisSize: "max", gap }, children);
  }
  function scene3d(node, children, ctx) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _i;
    const p = node.props;
    const raw = (_b = (_a = p.initialScene) != null ? _a : p.scene) != null ? _b : p.world;
    const json = raw && typeof raw === "object" && !Array.isArray(raw) ? raw : Array.isArray(raw) ? { nodes: raw } : null;
    const controller = ctx.engine.sceneFor(ctx.elementId, json);
    const placeholder = (_c = first(children)) != null ? _c : scenePlaceholder();
    const clickable = p.clickable === true;
    return w(
      "scene3d",
      {
        surfaceId: controller.godot.surfaceId,
        live: controller.isLive,
        width: (_f = (_e = num(p.width)) != null ? _e : (_d = node.style) == null ? void 0 : _d.width) != null ? _f : null,
        height: (_i = (_h = num(p.height)) != null ? _h : (_g = node.style) == null ? void 0 : _g.height) != null ? _i : null,
        clickable,
        onEvent: (e) => {
          var _a2, _b2;
          if (e.type === "tap" && clickable) (_b2 = (_a2 = ctx.engine.host).sceneTap) == null ? void 0 : _b2.call(_a2, __spreadValues({}, p));
        }
      },
      placeholder
    );
  }
  function scenePlaceholder() {
    return decorated(
      { gradients: [{ kind: "linear", colors: [4279243805, 4279902771], begin: { x: -1, y: -1 }, end: { x: 1, y: 1 } }] },
      center(
        column(
          [icon("view_in_ar", 36, Colors.white24), sizedBox(null, 8), text("3D unavailable on this platform", { color: Colors.white38, fontSize: 12 })],
          { mainAxisSize: "min", crossAxisAlignment: "center" }
        )
      )
    );
  }
  var MATH_SYMBOLS = [
    ["alpha", "\u03B1"],
    ["beta", "\u03B2"],
    ["gamma", "\u03B3"],
    ["delta", "\u03B4"],
    ["theta", "\u03B8"],
    ["lambda", "\u03BB"],
    ["mu", "\u03BC"],
    ["pi", "\u03C0"],
    ["sigma", "\u03C3"],
    ["phi", "\u03C6"],
    ["omega", "\u03C9"],
    ["sum", "\u2211"],
    ["prod", "\u220F"],
    ["int", "\u222B"],
    ["infty", "\u221E"],
    ["sqrt", "\u221A"],
    ["neq", "\u2260"],
    ["leq", "\u2264"],
    ["geq", "\u2265"],
    ["approx", "\u2248"],
    ["times", "\xD7"],
    ["cdot", "\xB7"],
    ["pm", "\xB1"],
    ["to", "\u2192"],
    ["leftarrow", "\u2190"],
    ["Rightarrow", "\u21D2"],
    ["forall", "\u2200"],
    ["exists", "\u2203"],
    ["in", "\u2208"],
    ["notin", "\u2209"],
    ["subset", "\u2282"],
    ["subseteq", "\u2286"],
    ["cup", "\u222A"],
    ["cap", "\u2229"]
  ].map(([name, sym]) => [new RegExp("\\\\" + name, "g"), sym]);
  var SUPER = { "0": "\u2070", "1": "\xB9", "2": "\xB2", "3": "\xB3", "4": "\u2074", "5": "\u2075", "6": "\u2076", "7": "\u2077", "8": "\u2078", "9": "\u2079", "+": "\u207A", "-": "\u207B", "=": "\u207C", "(": "\u207D", ")": "\u207E", n: "\u207F", i: "\u2071" };
  var SUB = { "0": "\u2080", "1": "\u2081", "2": "\u2082", "3": "\u2083", "4": "\u2084", "5": "\u2085", "6": "\u2086", "7": "\u2087", "8": "\u2088", "9": "\u2089", "+": "\u208A", "-": "\u208B", "=": "\u208C", "(": "\u208D", ")": "\u208E" };
  var BLOCKED = ["write", "input", "include", "openout", "read", "catcode", "usepackage", "newcommand", "renewcommand", "def", "csname", "every", "special"];
  function sanitizeMath(input) {
    let expression = input.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, " ").trim();
    if (expression.length > 4096) expression = expression.substring(0, 4096);
    let sanitized = false;
    for (const cmd of BLOCKED) {
      const re = new RegExp("\\\\" + cmd, "gi");
      if (re.test(expression)) sanitized = true;
      expression = expression.replace(new RegExp("\\\\" + cmd, "gi"), "\\text{blocked}");
    }
    return { value: expression, sanitized };
  }
  function renderMathToUnicode(expression) {
    let out = expression;
    const frac = /\\frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}/;
    for (let i = 0; i < 24 && frac.test(out); i++) out = out.replace(new RegExp(frac.source, "g"), (_m, a, b) => `(${a})/(${b})`);
    for (const [re, sym] of MATH_SYMBOLS) out = out.replace(re, sym);
    const mapScript = (value, map) => [...value].map((c) => {
      var _a;
      return (_a = map[c]) != null ? _a : c;
    }).join("");
    out = out.replace(/\^\{([^{}]+)\}|\^([A-Za-z0-9+\-=()])/g, (_m, a, b) => {
      var _a;
      return mapScript((_a = a != null ? a : b) != null ? _a : "", SUPER);
    });
    out = out.replace(/_\{([^{}]+)\}|_([A-Za-z0-9+\-=()])/g, (_m, a, b) => {
      var _a;
      return mapScript((_a = a != null ? a : b) != null ? _a : "", SUB);
    });
    out = out.replace(/\\left|\\right/g, "").replace(/\\text\{([^{}]*)\}/g, "$1").replace(/[{}]/g, "");
    return out.trim();
  }
  function mathExpression(node, ctx) {
    var _a, _b, _c, _d, _e;
    const raw = String((_d = (_c = (_b = (_a = node.props.expression) != null ? _a : node.props.latex) != null ? _b : node.props.text) != null ? _c : node.props.data) != null ? _d : "");
    const sanitized = sanitizeMath(raw);
    const rendered = renderMathToUnicode(sanitized.value);
    const style = node.style ? (_e = createTextStyle(node.style)) != null ? _e : {} : { fontSize: 18 };
    let result;
    if (rendered.trim() === "") {
      result = text("Math expression is required", style);
    } else {
      const parts = [w("scroll", { axis: "horizontal" }, text(rendered, style, { selectable: true, softWrap: false }))];
      if (sanitized.sanitized) {
        parts.push(padding({ top: 4, right: 0, bottom: 0, left: 0 }, text("Unsafe commands were sanitized from the expression.", { fontSize: 11, color: Colors.orange })));
      }
      result = column(parts, { crossAxisAlignment: "start", mainAxisSize: "min" });
    }
    return applyStyle(result, node.style, {}, ctx);
  }

  // core/src/render/layout/imagemap.ts
  function areaBounds(area, w2, h) {
    const c = area.coords;
    switch (area.shape) {
      case "rect":
        return { x: Math.min(c[0], c[2]), y: Math.min(c[1], c[3]), width: Math.abs(c[2] - c[0]), height: Math.abs(c[3] - c[1]) };
      case "circle":
        return { x: c[0] - c[2], y: c[1] - c[2], width: c[2] * 2, height: c[2] * 2 };
      case "poly": {
        const xs = c.filter((_, i) => i % 2 === 0);
        const ys = c.filter((_, i) => i % 2 === 1);
        const x = Math.min(...xs);
        const y = Math.min(...ys);
        return { x, y, width: Math.max(...xs) - x, height: Math.max(...ys) - y };
      }
      default:
        return { x: 0, y: 0, width: w2, height: h };
    }
  }
  function areaContains(area, px, py) {
    const c = area.coords;
    switch (area.shape) {
      case "rect":
        return px >= Math.min(c[0], c[2]) && px <= Math.max(c[0], c[2]) && py >= Math.min(c[1], c[3]) && py <= Math.max(c[1], c[3]);
      case "circle":
        return (px - c[0]) ** 2 + (py - c[1]) ** 2 <= c[2] ** 2;
      case "poly": {
        let inside = false;
        const n = Math.floor(c.length / 2);
        for (let i = 0, j = n - 1; i < n; j = i++) {
          const xi = c[2 * i], yi = c[2 * i + 1], xj = c[2 * j], yj = c[2 * j + 1];
          if (yi > py !== yj > py && px < (xj - xi) * (py - yi) / (yj - yi) + xi) inside = !inside;
        }
        return inside;
      }
      default:
        return true;
    }
  }
  var RenderImageMap = class extends RenderObject {
    constructor() {
      super(...arguments);
      this.scale = { x: 1, y: 1 };
    }
    performLayout(c) {
      var _a, _b, _c;
      const [image, ...areas] = this.children;
      if (!image) {
        this.size = constrain(c, { width: 0, height: 0 });
        return;
      }
      image.layout(c);
      image.offset = { x: 0, y: 0 };
      this.size = __spreadValues({}, image.size);
      const natural = (_b = (_a = this.owner) == null ? void 0 : _a.imageSize(this.props.src)) != null ? _b : null;
      this.scale = natural && natural.width > 0 && natural.height > 0 ? { x: this.size.width / natural.width, y: this.size.height / natural.height } : { x: 1, y: 1 };
      const specs = (_c = this.props.areas) != null ? _c : [];
      areas.forEach((area, i) => {
        var _a2, _b2;
        const spec = specs[i];
        if (!spec) {
          area.layout({ minWidth: 0, maxWidth: 0, minHeight: 0, maxHeight: 0 });
          return;
        }
        const b = areaBounds(spec, (_a2 = natural == null ? void 0 : natural.width) != null ? _a2 : this.size.width, (_b2 = natural == null ? void 0 : natural.height) != null ? _b2 : this.size.height);
        const w2 = b.width * this.scale.x;
        const h = b.height * this.scale.y;
        area.layout({ minWidth: w2, maxWidth: w2, minHeight: h, maxHeight: h });
        area.offset = { x: b.x * this.scale.x, y: b.y * this.scale.y };
      });
    }
  };

  // core/src/widgets/html.ts
  var num2 = toNumber;
  var INLINE_DEFAULTS = {
    span: {},
    strong: { fontWeight: 700 },
    b: { fontWeight: 700 },
    em: { italic: true },
    i: { italic: true },
    cite: { italic: true },
    var: { italic: true },
    dfn: { italic: true },
    u: { decoration: Decoration.underline },
    ins: { decoration: Decoration.underline },
    s: { decoration: Decoration.lineThrough },
    del: { decoration: Decoration.lineThrough },
    strike: { decoration: Decoration.lineThrough },
    code: { fontFamily: "monospace", background: 4294309365 },
    kbd: { fontFamily: "monospace", background: 4293848814 },
    samp: { fontFamily: "monospace" },
    tt: { fontFamily: "monospace" },
    mark: { background: 4294967040 },
    small: { fontSize: 12 },
    sub: { fontSize: 10, baselineShift: 3 },
    sup: { fontSize: 10, baselineShift: -6 },
    abbr: { decoration: Decoration.underline },
    a: { color: Colors.blue, decoration: Decoration.underline },
    q: {},
    time: {},
    data: {},
    label: { fontWeight: 500 }
  };
  var INLINE_TAGS = /* @__PURE__ */ new Set([...Object.keys(INLINE_DEFAULTS), "br", "#text"]);
  function inlineSpans(node, inherited, ctx, depth = 0) {
    var _a, _b, _c;
    if (depth > 12) return null;
    if (node.type === "#text") return [{ text: String((_a = node.props.text) != null ? _a : ""), style: inherited }];
    if (node.type === "br") return [{ text: "\n", style: inherited }];
    if (!INLINE_TAGS.has(node.type)) return null;
    const s = node.style;
    if (s && (s.display === "block" || s.display === "flex" || s.display === "grid" || s.position === "absolute" || s.position === "fixed")) return null;
    if (s && (s.width != null || s.height != null || s.border || s.borderRadius || s.boxShadow || s.transform)) return null;
    if ((s == null ? void 0 : s.display) === "none") return [];
    const events = node.events ? Object.keys(node.events) : [];
    const isLink = node.type === "a" && events.every((e) => e === "click" || e === "tap");
    if (events.length && !isLink) return null;
    const own = mergeTextStyle(mergeTextStyle(inherited, (_b = INLINE_DEFAULTS[node.type]) != null ? _b : {}), createTextStyle(s));
    if ((s == null ? void 0 : s.backgroundColor) != null) own.background = s.backgroundColor;
    const link = node.type === "a" ? String((_c = node.props.href) != null ? _c : "#") : null;
    const out = [];
    const t = textOf(node);
    if (t) out.push({ text: node.type === "q" ? `\u201C${t}\u201D` : t, style: own, link });
    for (const child of node.children) {
      const childSpans = inlineSpans(child, own, ctx, depth + 1);
      if (!childSpans) return null;
      for (const span of childSpans) out.push(link && !span.link ? __spreadProps(__spreadValues({}, span), { link }) : span);
    }
    return out;
  }
  function richText(node, style, ctx, opts = {}) {
    if (node.children.length === 0) return null;
    const spans = [];
    const t = textOf(node);
    if (t) spans.push({ text: t, style: {} });
    for (const child of node.children) {
      const childSpans = inlineSpans(child, {}, ctx);
      if (!childSpans) return null;
      spans.push(...childSpans);
    }
    return w("text", __spreadProps(__spreadValues({
      spans,
      style
    }, opts), {
      onLink: (href) => openLink(ctx, href, null)
    }));
  }
  function openLink(ctx, href, node) {
    var _a, _b, _c;
    if (((_a = node == null ? void 0 : node.events) == null ? void 0 : _a.click) || ((_b = node == null ? void 0 : node.events) == null ? void 0 : _b.tap)) {
      dispatchEvent(ctx, "click");
    }
    if (!href || href === "#") return;
    const host2 = ctx.engine.host;
    if (/^(https?:|mailto:|tel:|sms:|geo:)/i.test(href) || !host2.navigate) {
      (_c = host2.openUrl) == null ? void 0 : _c.call(host2, href);
    } else {
      host2.navigate(href, false);
    }
  }
  function childStyle(node) {
    let n = node;
    while (n.type === "Scope" && n.children.length === 1) n = n.children[0];
    return n.style;
  }
  function stretchChild(child) {
    if (child.t === "flexible" && child.c && child.c[0]) {
      return __spreadProps(__spreadValues({}, child), { c: [w("fill", { width: true }, child.c[0])] });
    }
    return w("fill", { width: true }, child);
  }
  function unflex(child) {
    return child.t === "flexible" && child.c && child.c[0] ? child.c[0] : child;
  }
  function buildColumn(node, children, gap, mainAxisAlignment, mainAxisSize, flowNodes) {
    var _a, _b, _c;
    const alignItems = (_a = node.style) == null ? void 0 : _a.alignItems;
    const canStretch = alignItems == null && flowNodes.length === children.length;
    if (!canStretch) {
      return w("flex", { direction: "column", mainAxisAlignment, crossAxisAlignment: crossOf(alignItems), mainAxisSize, gap, reverse: ((_b = node.style) == null ? void 0 : _b.flexDirection) === "column-reverse" }, children);
    }
    const laid = children.map((child, i) => {
      var _a2, _b2;
      return ((_a2 = childStyle(flowNodes[i])) == null ? void 0 : _a2.width) == null && ((_b2 = childStyle(flowNodes[i])) == null ? void 0 : _b2.widthFactor) == null ? stretchChild(child) : child;
    });
    return w("flex", { direction: "column", mainAxisAlignment, crossAxisAlignment: "start", mainAxisSize, gap, reverse: ((_c = node.style) == null ? void 0 : _c.flexDirection) === "column-reverse" }, laid);
  }
  function mainOf(v) {
    switch ((v != null ? v : "").toLowerCase()) {
      case "center":
        return "center";
      case "flex-end":
      case "end":
      case "right":
        return "end";
      case "space-between":
        return "spaceBetween";
      case "space-around":
        return "spaceAround";
      case "space-evenly":
        return "spaceEvenly";
      default:
        return "start";
    }
  }
  function crossOf(v) {
    switch ((v != null ? v : "").toLowerCase()) {
      case "center":
        return "center";
      case "flex-end":
      case "end":
        return "end";
      case "stretch":
        return "stretch";
      case "baseline":
        return "baseline";
      default:
        return "start";
    }
  }
  function wrapCrossOf(v) {
    const c = crossOf(v);
    return c === "center" || c === "end" ? c : "start";
  }
  function buildFlow(node, children, flowNodes) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j;
    const s = node.style;
    const display = s == null ? void 0 : s.display;
    if (display === "grid" || display === "inline-grid") return buildGrid(node, children, flowNodes);
    const gap = (_b = (_a = s == null ? void 0 : s.gap) != null ? _a : s == null ? void 0 : s.columnGap) != null ? _b : 0;
    if (display === "flex" || display === "inline-flex") {
      const dir = (_c = s == null ? void 0 : s.flexDirection) != null ? _c : "row";
      const isRow = dir === "row" || dir === "row-reverse";
      const wraps = (s == null ? void 0 : s.flexWrap) === "wrap" || (s == null ? void 0 : s.flexWrap) === "wrap-reverse";
      if (wraps) {
        return w(
          "wrap",
          {
            direction: isRow ? "horizontal" : "vertical",
            spacing: isRow ? (_d = s == null ? void 0 : s.columnGap) != null ? _d : gap : (_e = s == null ? void 0 : s.rowGap) != null ? _e : gap,
            runSpacing: isRow ? (_f = s == null ? void 0 : s.rowGap) != null ? _f : gap : (_g = s == null ? void 0 : s.columnGap) != null ? _g : gap,
            alignment: mainOf(s == null ? void 0 : s.justifyContent),
            runAlignment: mainOf(s == null ? void 0 : s.alignContent),
            crossAxisAlignment: wrapCrossOf(s == null ? void 0 : s.alignItems),
            verticalDirection: (s == null ? void 0 : s.flexWrap) === "wrap-reverse" ? "up" : "down",
            reverse: dir.endsWith("reverse")
          },
          children
        );
      }
      if (isRow) {
        const flex = w(
          "flex",
          {
            direction: "row",
            mainAxisAlignment: mainOf(s == null ? void 0 : s.justifyContent),
            crossAxisAlignment: crossOf(s == null ? void 0 : s.alignItems),
            mainAxisSize: "max",
            gap: (_h = s == null ? void 0 : s.columnGap) != null ? _h : gap,
            reverse: dir === "row-reverse",
            shrink: true
          },
          children
        );
        const hasFlex = flowNodes.some((c) => {
          var _a2, _b2, _c2;
          return ((_c2 = (_a2 = childStyle(c)) == null ? void 0 : _a2.flex) != null ? _c2 : (_b2 = childStyle(c)) == null ? void 0 : _b2.flexGrow) != null;
        });
        return hasFlex ? w("intrinsicWidth", { onlyWhenUnbounded: true }, [flex]) : flex;
      }
      return buildColumn(node, children, (_i = s == null ? void 0 : s.rowGap) != null ? _i : gap, mainOf(s == null ? void 0 : s.justifyContent), "max", flowNodes);
    }
    if (children.length === 1) return unflex(children[0]);
    return buildColumn(node, children, (_j = s == null ? void 0 : s.rowGap) != null ? _j : gap, "start", "min", flowNodes);
  }
  function buildGrid(node, children, flowNodes) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j, _k;
    const s = (_a = node.style) != null ? _a : {};
    const base = (_c = (_b = s.gridGap) != null ? _b : s.gap) != null ? _c : 0;
    const items = children.map((child, i) => {
      var _a2, _b2, _c2;
      const cs = childStyle(flowNodes[i]);
      const area = cs == null ? void 0 : cs.gridArea;
      return w(
        "gridItem",
        {
          column: (_a2 = cs == null ? void 0 : cs.gridColumn) != null ? _a2 : area && area.includes("/") ? area.split("/")[1] : null,
          row: (_b2 = cs == null ? void 0 : cs.gridRow) != null ? _b2 : area && area.includes("/") ? area.split("/")[0] : null,
          alignSelf: (_c2 = cs == null ? void 0 : cs.alignSelf) != null ? _c2 : null
        },
        unflex(child)
      );
    });
    return w(
      "grid",
      {
        columns: (_d = s.gridTemplateColumns) != null ? _d : null,
        rows: (_e = s.gridTemplateRows) != null ? _e : null,
        autoRows: (_f = s.gridAutoRows) != null ? _f : null,
        columnGap: (_h = (_g = s.gridColumnGap) != null ? _g : s.columnGap) != null ? _h : base,
        rowGap: (_j = (_i = s.gridRowGap) != null ? _i : s.rowGap) != null ? _j : base,
        alignItems: (_k = s.alignItems) != null ? _k : null
      },
      items
    );
  }
  function buildPositioned(node, children) {
    var _a, _b, _c, _d, _e, _f;
    const nodes = node.children;
    if (nodes.length !== children.length) return null;
    const styles = nodes.map(childStyle);
    if (!styles.some((st) => (st == null ? void 0 : st.position) === "absolute" || (st == null ? void 0 : st.position) === "fixed")) return null;
    const flow = [];
    const flowNodes = [];
    const positioned = [];
    styles.forEach((st, i) => {
      if ((st == null ? void 0 : st.position) === "absolute" || (st == null ? void 0 : st.position) === "fixed") positioned.push(i);
      else {
        flow.push(children[i]);
        flowNodes.push(nodes[i]);
      }
    });
    positioned.sort((a, b) => {
      var _a2, _b2, _c2, _d2;
      return ((_b2 = (_a2 = styles[a]) == null ? void 0 : _a2.zIndex) != null ? _b2 : 0) - ((_d2 = (_c2 = styles[b]) == null ? void 0 : _c2.zIndex) != null ? _d2 : 0) || a - b;
    });
    const stackChildren = [];
    if (flow.length) stackChildren.push(w("fill", { width: true }, buildFlow(node, flow, flowNodes)));
    for (const i of positioned) {
      const st = styles[i];
      const lr = st.left != null && st.right != null;
      const tb = st.top != null && st.bottom != null;
      stackChildren.push(
        w(
          "positioned",
          { top: (_a = st.top) != null ? _a : null, left: (_b = st.left) != null ? _b : null, right: (_c = st.right) != null ? _c : null, bottom: (_d = st.bottom) != null ? _d : null, width: lr ? null : (_e = st.width) != null ? _e : null, height: tb ? null : (_f = st.height) != null ? _f : null },
          unflex(children[i])
        )
      );
    }
    return w("stack", { alignment: { x: -1, y: -1 }, fit: "loose", clip: true }, stackChildren);
  }
  function htmlDiv(node, children, ctx, opts = {}) {
    if (children.length === 0) {
      let empty = SHRINK;
      if (opts.fullWidth) empty = w("fill", { width: true }, empty);
      return applyStyle(empty, node.style, { layoutHandled: true }, ctx);
    }
    const positioned = buildPositioned(node, children);
    let body = positioned != null ? positioned : buildFlow(node, children, node.children);
    if (opts.fullWidth) body = w("fill", { width: true }, body);
    return applyStyle(body, node.style, { layoutHandled: true }, ctx);
  }
  function withDefaults(style, defaults) {
    const out = __spreadValues({}, defaults);
    for (const [k, v] of Object.entries(style != null ? style : {})) if (v != null) out[k] = v;
    return out;
  }
  function textElement(node, ctx, defaults, baseText = {}) {
    const style = withDefaults(node.style, defaults);
    const ts = mergeTextStyle(baseText, createTextStyle(style));
    const opts = textOptionsFromStyle(style);
    const rich = richText(node, ts, ctx, opts);
    if (rich) return applyStyle(rich, style, {}, ctx);
    return applyStyle(text(textOf(node), ts, opts), style, {}, ctx);
  }
  function textWithChildren(node, children, ctx, defaults, layout) {
    var _a;
    const style = withDefaults(node.style, defaults);
    const ts = (_a = createTextStyle(style)) != null ? _a : {};
    const opts = textOptionsFromStyle(style);
    if (children.length === 0) return applyStyle(text(textOf(node), ts, opts), style, {}, ctx);
    const rich = richText(node, ts, ctx, opts);
    if (rich) return applyStyle(rich, style, {}, ctx);
    const parts = [];
    const t = textOf(node);
    if (t) parts.push(text(t, ts, opts));
    parts.push(...children);
    const body = layout === "column" ? column(parts, { crossAxisAlignment: "start", mainAxisSize: "min" }) : w("wrap", { direction: "horizontal", crossAxisAlignment: "center" }, parts);
    return applyStyle(w("defaultTextStyle", { style: ts }, body), style, { layoutHandled: true }, ctx);
  }
  function heading(size, marginV) {
    return (node, children, ctx) => textWithChildren(node, children, ctx, { fontSize: size, fontWeight: 700, margin: insetsSymmetric(marginV, 0) }, "column");
  }
  var monoStyle = (bg, pad, extra = {}) => __spreadValues({ fontFamily: "monospace", backgroundColor: bg, padding: pad }, extra);
  function replaceDefaults(node, ctx, defaults, inline) {
    var _a, _b;
    const style = (_a = node.style) != null ? _a : defaults;
    const ts = mergeTextStyle(node.style ? (_b = INLINE_DEFAULTS[node.type]) != null ? _b : {} : inline, createTextStyle(style));
    const rich = richText(node, ts, ctx);
    return applyStyle(rich != null ? rich : text(textOf(node), ts, textOptionsFromStyle(style)), style, {}, ctx);
  }
  var DARK = {
    text: 4294438620,
    fill: 4278851110,
    border: 4280038480,
    focus: 4292260714,
    hint: 4285234834
  };
  function datalistOptions(ctx, listId) {
    if (!listId) return null;
    const list2 = ctx.engine.datalists.get(listId);
    return list2 && list2.length ? [...list2] : null;
  }
  function htmlInput(node, children, ctx) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j, _k, _l, _m, _n, _o, _p, _q, _r, _s, _t;
    const type = String((_a = node.props.type) != null ? _a : "text").toLowerCase();
    const name = node.props.name != null ? String(node.props.name) : null;
    const disabled = node.props.disabled === true || node.props.disabled === "disabled";
    if (type === "hidden") {
      ctx.engine.registerFormField(ctx.formId, name, () => {
        var _a2;
        return (_a2 = node.props.value) != null ? _a2 : "";
      });
      return SHRINK;
    }
    if (type === "checkbox") {
      const state2 = ctx.engine.stateFor(ctx.elementId, () => ({ checked: node.props.checked === true || node.props.checked === "checked" }));
      ctx.engine.registerFormField(ctx.formId, name, () => {
        var _a2;
        return state2.checked ? (_a2 = node.props.value) != null ? _a2 : "on" : null;
      });
      const result2 = w("control", {
        kind: "checkbox",
        focusId: node.props.id != null ? String(node.props.id) : null,
        view: { checked: state2.checked, enabled: !disabled, colors: { fill: (_c = (_b = node.style) == null ? void 0 : _b.color) != null ? _c : M3.primary, check: M3.onPrimary, border: M3.onSurfaceVariant } },
        onEvent: (e) => {
          if (e.type === "change") {
            state2.checked = !!e.value;
            dispatchEvent(ctx, "change", { value: state2.checked });
          }
        }
      });
      return applyStyle(result2, node.style, {}, ctx);
    }
    if (type === "radio") {
      const value = node.props.value;
      const group = node.props.groupValue;
      const checked = group !== void 0 ? value === group : node.props.checked === true || node.props.checked === "checked";
      ctx.engine.registerFormField(ctx.formId, name, () => checked ? value : void 0);
      const result2 = w("control", {
        kind: "radio",
        focusId: node.props.id != null ? String(node.props.id) : null,
        view: { checked, value: value != null ? value : null, enabled: !disabled, colors: { fill: (_e = (_d = node.style) == null ? void 0 : _d.color) != null ? _e : M3.primary, border: M3.onSurfaceVariant } },
        controlled: true,
        onEvent: (e) => {
          if (e.type === "change") dispatchEvent(ctx, "change", { value });
        }
      });
      return applyStyle(result2, node.style, {}, ctx);
    }
    if (type === "range") {
      const min = (_f = num2(node.props.min)) != null ? _f : 0;
      const max = (_g = num2(node.props.max)) != null ? _g : 100;
      const state2 = ctx.engine.stateFor(ctx.elementId, () => {
        var _a2;
        return { value: Math.max(min, Math.min(max, (_a2 = num2(node.props.value)) != null ? _a2 : (min + max) / 2)) };
      });
      ctx.engine.registerFormField(ctx.formId, name, () => state2.value);
      const step = (_h = num2(node.props.step)) != null ? _h : 1;
      const result2 = w("control", {
        kind: "slider",
        focusId: node.props.id != null ? String(node.props.id) : null,
        view: { value: state2.value, min, max, step, enabled: !disabled, colors: { active: DARK.focus, inactive: DARK.border, thumb: DARK.focus } },
        onEvent: (e) => {
          if (e.type === "input" || e.type === "change") {
            state2.value = Number(e.value);
            dispatchEvent(ctx, e.type === "input" ? "input" : "change", { value: state2.value });
          }
        }
      });
      return applyStyle(result2, node.style, {}, ctx);
    }
    if (type === "submit" || type === "button" || type === "reset") {
      const label = String((_j = (_i = node.props.value) != null ? _i : node.props.text) != null ? _j : type === "submit" ? "Submit" : type === "reset" ? "Reset" : "Button");
      return htmlButtonLike(node, [text(label, { color: (_m = (_k = node.style) == null ? void 0 : _k.color) != null ? _m : ((_l = node.style) == null ? void 0 : _l.backgroundColor) != null ? Colors.white : M3.primary })], ctx, type);
    }
    const state = ctx.engine.stateFor(ctx.elementId, () => ({ value: node.props.value != null ? String(node.props.value) : "" }));
    ctx.engine.registerFormField(ctx.formId, name, () => type === "number" ? state.value === "" ? null : Number(state.value) : state.value);
    const s = node.style;
    const textColor = (_n = s == null ? void 0 : s.color) != null ? _n : DARK.text;
    const fontSize = (_o = s == null ? void 0 : s.fontSize) != null ? _o : 13;
    const ts = { color: textColor, fontSize, height: 1.3, letterSpacing: 0 };
    const result = w("control", {
      kind: "textInput",
      focusId: node.props.id != null ? String(node.props.id) : null,
      lines: 1,
      padding: [10, 10, 10, 10],
      lineHeight: fontSize * 1.3,
      view: {
        value: state.value,
        placeholder: String((_p = node.props.placeholder) != null ? _p : ""),
        inputType: type,
        multiline: false,
        maxLength: num2((_q = node.props.maxLength) != null ? _q : node.props.maxlength),
        enabled: !disabled,
        readOnly: node.props.readOnly === true || node.props.readonly != null,
        autofocus: node.props.autofocus === true || node.props.autofocus === "autofocus",
        min: (_r = num2(node.props.min)) != null ? _r : void 0,
        max: (_s = num2(node.props.max)) != null ? _s : void 0,
        suggestions: datalistOptions(ctx, node.props.list != null ? String(node.props.list) : null),
        variant: "outline",
        textStyle: toSpec(ts),
        hintStyle: toSpec(__spreadProps(__spreadValues({}, ts), { color: DARK.hint })),
        contentPadding: [10, 10, 10, 10],
        colors: { text: textColor, hint: DARK.hint, fill: (_t = s == null ? void 0 : s.backgroundColor) != null ? _t : DARK.fill, border: DARK.border, focusedBorder: DARK.focus, cursor: DARK.focus, radius: 8 }
      },
      onEvent: (e) => {
        var _a2, _b2;
        if (e.type === "input" || e.type === "change") {
          state.value = String((_a2 = e.value) != null ? _a2 : "");
          dispatchEvent(ctx, "input", { value: state.value });
        } else if (e.type === "submit") {
          dispatchEvent(ctx, "submit");
          if (ctx.formId) ctx.engine.submitForm(ctx.formId);
        } else if (e.type === "focus" || e.type === "blur") {
          dispatchEvent(ctx, e.type);
          if (e.type === "blur" && ((_b2 = node.events) == null ? void 0 : _b2.change)) dispatchEvent(ctx, "change", { value: state.value });
        }
      }
    });
    return applyStyle(result, s, {}, ctx);
  }
  function htmlTextarea(node, _children, ctx) {
    var _a, _b, _c, _d, _e;
    const state = ctx.engine.stateFor(ctx.elementId, () => {
      var _a2, _b2;
      return { value: String((_b2 = (_a2 = node.props.value) != null ? _a2 : node.props.text) != null ? _b2 : "") };
    });
    ctx.engine.registerFormField(ctx.formId, node.props.name != null ? String(node.props.name) : null, () => state.value);
    const lines = Math.max(1, (_a = num2(node.props.rows)) != null ? _a : 5);
    const ts = { fontSize: 16, height: 1.5, letterSpacing: 0.5, color: (_c = (_b = node.style) == null ? void 0 : _b.color) != null ? _c : M3.onSurface };
    const result = w("control", {
      kind: "textInput",
      focusId: node.props.id != null ? String(node.props.id) : null,
      lines,
      padding: [16, 12, 16, 12],
      lineHeight: 24,
      view: {
        value: state.value,
        placeholder: String((_d = node.props.placeholder) != null ? _d : ""),
        inputType: "multiline",
        multiline: true,
        maxLines: lines,
        minLines: lines,
        enabled: node.props.disabled == null,
        readOnly: node.props.readOnly === true || node.props.readonly != null,
        variant: "outline",
        textStyle: toSpec(ts),
        hintStyle: toSpec(__spreadProps(__spreadValues({}, ts), { color: M3.onSurfaceVariant })),
        contentPadding: [16, 12, 16, 12],
        colors: { text: (_e = ts.color) != null ? _e : M3.onSurface, hint: M3.onSurfaceVariant, border: M3.outline, focusedBorder: M3.primary, cursor: M3.primary, fill: null, radius: 4 }
      },
      onEvent: (e) => {
        var _a2;
        if (e.type === "input" || e.type === "change") {
          state.value = String((_a2 = e.value) != null ? _a2 : "");
          dispatchEvent(ctx, "input", { value: state.value });
        } else if (e.type === "submit") dispatchEvent(ctx, "submit");
        else if (e.type === "focus" || e.type === "blur") dispatchEvent(ctx, e.type);
      }
    });
    return applyStyle(result, node.style, {}, ctx);
  }
  function selectOptions(node) {
    var _a, _b, _c, _d;
    const out = [];
    const raw = node.props.options;
    if (Array.isArray(raw)) {
      for (const o of raw) {
        if (o && typeof o === "object") {
          const v = String((_b = (_a = o.value) != null ? _a : o.label) != null ? _b : "");
          out.push({ value: v, label: String((_c = o.label) != null ? _c : v), group: (_d = o.group) != null ? _d : null, disabled: o.disabled === true });
        } else if (o != null) out.push({ value: String(o), label: String(o) });
      }
    }
    if (out.length === 0) {
      const visit = (n, group) => {
        var _a2, _b2, _c2, _d2, _e;
        for (const c of n.children) {
          if (c.type === "option") {
            const v = String((_b2 = (_a2 = c.props.value) != null ? _a2 : c.props.text) != null ? _b2 : "");
            out.push({ value: v, label: String((_d2 = (_c2 = c.props.text) != null ? _c2 : c.props.label) != null ? _d2 : v), group, disabled: c.props.disabled != null && c.props.disabled !== false });
          } else if (c.type === "optgroup") visit(c, String((_e = c.props.label) != null ? _e : ""));
        }
      };
      visit(node, null);
    }
    return out;
  }
  function htmlSelect(node, _children, ctx) {
    var _a, _b, _c, _d, _e;
    const options = selectOptions(node);
    const selectedChild = node.children.find((c) => c.type === "option" && (c.props.selected === true || c.props.selected === "selected"));
    const state = ctx.engine.stateFor(ctx.elementId, () => {
      var _a2, _b2;
      return {
        value: node.props.value != null ? String(node.props.value) : selectedChild ? String((_b2 = (_a2 = selectedChild.props.value) != null ? _a2 : selectedChild.props.text) != null ? _b2 : "") : null,
        lastProp: node.props.value != null ? String(node.props.value) : null
      };
    });
    const incoming = node.props.value != null ? String(node.props.value) : null;
    if (incoming != null && incoming !== state.lastProp) {
      state.value = incoming;
      state.lastProp = incoming;
    }
    const value = options.some((o) => o.value === state.value) ? state.value : (_b = (_a = options[0]) == null ? void 0 : _a.value) != null ? _b : null;
    ctx.engine.registerFormField(ctx.formId, node.props.name != null ? String(node.props.name) : null, () => value);
    const s = node.style;
    const ts = { color: (_c = s == null ? void 0 : s.color) != null ? _c : DARK.text, fontSize: (_d = s == null ? void 0 : s.fontSize) != null ? _d : 13, height: 1.3 };
    let result = w("control", {
      kind: "select",
      focusId: node.props.id != null ? String(node.props.id) : null,
      padding: [0, 10, 0, 10],
      view: {
        value,
        options,
        enabled: node.props.disabled == null,
        textStyle: toSpec(ts),
        colors: { text: (_e = ts.color) != null ? _e : DARK.text, fill: DARK.fill, icon: DARK.focus, menu: DARK.fill }
      },
      onEvent: (e) => {
        var _a2, _b2;
        if (e.type === "change" && e.value != null) {
          state.value = String(e.value);
          dispatchEvent(ctx, "change", { value: state.value });
          (_b2 = (_a2 = ctx.engine.host).invalidate) == null ? void 0 : _b2.call(_a2);
        }
      }
    });
    result = container({
      child: result,
      padding: insetsSymmetric(0, 10),
      decoration: { color: DARK.fill, radius: radiusAll(8), border: borderAll({ width: 1, color: DARK.border, style: "solid" }) }
    });
    return applyStyle(result, s, {}, ctx);
  }
  function htmlButtonLike(node, children, ctx, type) {
    var _a, _b, _c, _d;
    const s = node.style;
    const label = String((_a = node.props.text) != null ? _a : "Button");
    const fg = (_b = s == null ? void 0 : s.color) != null ? _b : (s == null ? void 0 : s.backgroundColor) != null ? Colors.white : M3.primary;
    const child = (_c = children[0]) != null ? _c : text(label, { color: fg });
    const kind = type != null ? type : String((_d = node.props.type) != null ? _d : ctx.formId ? "submit" : "button").toLowerCase();
    const disabled = node.props.disabled === true || node.props.disabled === "disabled";
    const press = buttonPressed(ctx);
    const onPressed = disabled ? null : () => {
      press();
      if (kind === "submit" && ctx.formId) ctx.engine.submitForm(ctx.formId);
      if (kind === "reset" && ctx.formId) dispatchEvent(ctx, "reset");
    };
    return buttonOuter(materialButton({ child, style: s, onPressed, semanticsLabel: label }), s);
  }
  function mediaSource(node, ctx) {
    const direct = node.props.src;
    if (direct) return ctx.engine.resolveUrl(String(direct));
    for (const c of node.children) if (c.type === "source" && c.props.src) return ctx.engine.resolveUrl(String(c.props.src));
    return "";
  }
  function mediaElement(kind) {
    return (node, _children, ctx) => {
      var _a, _b, _c, _d, _e, _f, _g, _h;
      const src = mediaSource(node, ctx);
      const tracks = node.children.filter((c) => c.type === "track" && c.props.src).map((c) => {
        var _a2;
        return {
          src: ctx.engine.resolveUrl(String(c.props.src)),
          kind: String((_a2 = c.props.kind) != null ? _a2 : "subtitles"),
          srclang: c.props.srclang != null ? String(c.props.srclang) : null,
          label: c.props.label != null ? String(c.props.label) : null,
          default: c.props.default === true || c.props.default === "default"
        };
      });
      if (!src) {
        const msg = kind === "video" ? "video src is required" : "audio src is required";
        return applyStyle(
          kind === "video" ? decorated({ color: Colors.black }, center(text(msg, { color: Colors.white70 }))) : row([padding(insetsAll(16), icon("audiotrack", 24)), text(msg)], { mainAxisSize: "min" }),
          node.style,
          {},
          ctx
        );
      }
      const result = w("media", {
        kind,
        src,
        autoplay: node.props.autoplay === true || node.props.autoplay === "autoplay",
        loop: node.props.loop === true || node.props.loop === "loop",
        muted: node.props.muted === true || node.props.muted === "muted",
        controls: node.props.controls !== false,
        poster: node.props.poster ? ctx.engine.resolveUrl(String(node.props.poster)) : null,
        tracks: tracks.length ? tracks : null,
        width: kind === "video" ? (_b = (_a = node.style) == null ? void 0 : _a.width) != null ? _b : num2(node.props.width) : (_d = (_c = node.style) == null ? void 0 : _c.width) != null ? _d : null,
        height: kind === "video" ? (_f = (_e = node.style) == null ? void 0 : _e.height) != null ? _f : num2(node.props.height) : null,
        fit: (_h = (_g = node.style) == null ? void 0 : _g.objectFit) != null ? _h : "contain",
        onEvent: (e) => {
          if (["play", "pause", "ended", "timeupdate", "load", "error", "volumechange", "seeked"].includes(e.type)) {
            dispatchEvent(ctx, e.type === "load" ? "loadedmetadata" : e.type, { value: e.value });
            if (e.type === "load") dispatchEvent(ctx, "load", { value: e.value });
          }
        }
      });
      return applyStyle(result, node.style, {}, ctx);
    };
  }
  function looksLike(kind, type, src) {
    const s = src.toLowerCase().split("?")[0];
    if (kind === "image") return type.startsWith("image/") || /\.(png|jpe?g|gif|webp|svg|bmp|avif)$/.test(s);
    if (kind === "video") return type.startsWith("video/") || /\.(mp4|webm|mov|m3u8|mkv|ogv)$/.test(s);
    return type.startsWith("audio/") || /\.(mp3|wav|ogg|aac|m4a|flac|opus)$/.test(s);
  }
  function webContent(node, ctx, src, label) {
    var _a, _b, _c, _d;
    if (!src && !node.props.srcdoc) {
      return applyStyle(center(text(`${label} source is required`)), node.style, {}, ctx);
    }
    const result = w("web", {
      src: src ? ctx.engine.resolveUrl(src) : null,
      html: node.props.srcdoc ? String(node.props.srcdoc) : null,
      width: (_b = (_a = node.style) == null ? void 0 : _a.width) != null ? _b : num2(node.props.width),
      height: (_d = (_c = node.style) == null ? void 0 : _c.height) != null ? _d : num2(node.props.height),
      onEvent: (e) => {
        if (e.type === "load" || e.type === "error") dispatchEvent(ctx, e.type, { value: e.value });
      }
    });
    return applyStyle(result, node.style, {}, ctx);
  }
  function embedTyped(node, children, ctx, src) {
    var _a;
    const type = String((_a = node.props.type) != null ? _a : "").toLowerCase();
    const withSrc = __spreadProps(__spreadValues({}, node), { props: __spreadProps(__spreadValues({}, node.props), { src }) });
    if (looksLike("image", type, src)) return htmlImg(withSrc, children, ctx);
    if (looksLike("video", type, src)) return mediaElement("video")(withSrc, children, ctx);
    if (looksLike("audio", type, src)) return mediaElement("audio")(withSrc, children, ctx);
    return webContent(withSrc, ctx, src, node.type);
  }
  function htmlImg(node, _children, ctx) {
    var _a, _b, _c, _d, _e;
    const rawSrc = String((_a = node.props.src) != null ? _a : "");
    const src = ctx.engine.resolveUrl(chooseSrcset(node, rawSrc));
    const s = node.style;
    const img = w("image", {
      src,
      fit: (_b = s == null ? void 0 : s.objectFit) != null ? _b : (s == null ? void 0 : s.width) != null && (s == null ? void 0 : s.height) != null ? "fill" : "contain",
      alignment: (_c = s == null ? void 0 : s.objectPosition) != null ? _c : null,
      width: (_d = s == null ? void 0 : s.width) != null ? _d : num2(node.props.width),
      height: (_e = s == null ? void 0 : s.height) != null ? _e : num2(node.props.height),
      alt: node.props.alt != null ? String(node.props.alt) : null,
      onEvent: (e) => {
        if (e.type === "load" || e.type === "error") dispatchEvent(ctx, e.type, { value: e.value });
      }
    });
    let result = img;
    const usemap = typeof node.props.usemap === "string" ? node.props.usemap.replace(/^#/, "") : null;
    const areas = usemap ? ctx.engine.imageMaps.get(usemap) : null;
    if (areas && areas.length) {
      const specs = [];
      const regions = [];
      areas.forEach((area, i) => {
        var _a2, _b2, _c2, _d2, _e2, _f;
        const shape = String((_a2 = area.props.shape) != null ? _a2 : "rect").toLowerCase();
        const coords = String((_b2 = area.props.coords) != null ? _b2 : "").split(",").map((c) => parseFloat(c)).filter((n) => Number.isFinite(n));
        const spec = { shape: shape === "circ" || shape === "circle" ? "circle" : shape === "poly" || shape === "polygon" ? "poly" : shape === "default" ? "default" : "rect", coords };
        specs.push(spec);
        const href = area.props.href != null ? String(area.props.href) : null;
        const areaId = (_c2 = area.key) != null ? _c2 : `${ctx.elementId}/area${i}`;
        regions.push(
          w("gesture", {
            gestures: ["tap"],
            cursor: "pointer",
            tooltip: (_e2 = (_d2 = area.props.title) != null ? _d2 : area.props.alt) != null ? _e2 : null,
            semanticsLabel: (_f = area.props.alt) != null ? _f : null,
            onEvent: (e, ro) => {
              var _a3, _b3, _c3, _d3, _e3, _f2, _g, _h, _i, _j;
              if (e.type !== "tap") return;
              const map = ro == null ? void 0 : ro.parent;
              const sx = (_b3 = (_a3 = map == null ? void 0 : map.scale) == null ? void 0 : _a3.x) != null ? _b3 : 1;
              const sy = (_d3 = (_c3 = map == null ? void 0 : map.scale) == null ? void 0 : _c3.y) != null ? _d3 : 1;
              const px = (((_e3 = e.localX) != null ? _e3 : 0) + ((_g = (_f2 = ro == null ? void 0 : ro.offset) == null ? void 0 : _f2.x) != null ? _g : 0)) / sx;
              const py = (((_h = e.localY) != null ? _h : 0) + ((_j = (_i = ro == null ? void 0 : ro.offset) == null ? void 0 : _i.y) != null ? _j : 0)) / sy;
              if (!areaContains(spec, px, py)) return;
              if (area.events) {
                ctx.engine.services.events.registerNode(areaId, area, ctx.elementId);
                ctx.engine.handleGesture(areaId, area, __spreadProps(__spreadValues({}, e), { type: "tap" }));
              }
              if (href) openLink(ctx, href, null);
            }
          })
        );
      });
      result = w("imageMap", { src, areas: specs }, [img, ...regions]);
    }
    return applyStyle(result, s, {}, ctx);
  }
  function chooseSrcset(node, fallback) {
    var _a, _b, _c;
    const srcset = (_a = node.props.srcset) != null ? _a : node.props.srcSet;
    if (typeof srcset !== "string" || srcset.trim() === "") return fallback;
    const env2 = cssEnvironment();
    const target = env2.viewportWidth * env2.devicePixelRatio;
    const candidates = srcset.split(",").map((part) => part.trim().split(/\s+/)).filter((p) => p[0]).map(([url, desc]) => {
      const d = desc != null ? desc : "1x";
      return { url, w: d.endsWith("w") ? parseFloat(d) : null, x: d.endsWith("x") ? parseFloat(d) : null };
    });
    const byWidth = candidates.filter((c) => c.w != null).sort((a, b) => a.w - b.w);
    if (byWidth.length) return ((_b = byWidth.find((c) => c.w >= target)) != null ? _b : byWidth[byWidth.length - 1]).url;
    const byDensity = candidates.filter((c) => c.x != null).sort((a, b) => a.x - b.x);
    if (byDensity.length) return ((_c = byDensity.find((c) => c.x >= env2.devicePixelRatio)) != null ? _c : byDensity[byDensity.length - 1]).url;
    return fallback;
  }
  function tableCell(node, children, ctx, header) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _i;
    const t = textOf(node);
    const base = header ? { fontWeight: 700 } : {};
    let child;
    if (children.length === 1) child = children[0];
    else if (children.length > 1) {
      child = (_a = richText(node, mergeTextStyle(base, createTextStyle(node.style)), ctx)) != null ? _a : column(children, { crossAxisAlignment: "start", mainAxisSize: "min" });
    } else child = text(t, mergeTextStyle(base, createTextStyle(node.style)), textOptionsFromStyle(node.style));
    if (header && ((_b = node.style) == null ? void 0 : _b.textAlign) == null) child = center(child);
    const style = withDefaults(node.style, { padding: insetsAll(8) });
    const boxed = applyStyle(child, style, {}, ctx);
    const va = String((_e = (_d = (_c = node.style) == null ? void 0 : _c.verticalAlign) != null ? _d : node.props.valign) != null ? _e : "middle");
    return w("tableCell", { colSpan: (_g = num2((_f = node.props.colspan) != null ? _f : node.props.colSpan)) != null ? _g : 1, rowSpan: (_i = num2((_h = node.props.rowspan) != null ? _h : node.props.rowSpan)) != null ? _i : 1, verticalAlign: va === "top" ? "top" : va === "bottom" ? "bottom" : "middle", width: num2(node.props.width) }, boxed);
  }
  function tableRow(node, children) {
    var _a, _b, _c;
    const cells = children.map((c) => c.t === "tableCell" ? c : w("tableCell", {}, c));
    return w("tableRow", { decorated: ((_a = node.style) == null ? void 0 : _a.backgroundColor) != null, background: (_c = (_b = node.style) == null ? void 0 : _b.backgroundColor) != null ? _c : null }, cells);
  }
  function htmlTable(node, children, ctx) {
    var _a, _b, _c, _d, _e, _f;
    const rows = [];
    let caption = null;
    node.children.forEach((child, i) => {
      var _a2;
      const wc = children[i];
      if (child.type === "caption") caption = wc;
      else if (["thead", "tbody", "tfoot"].includes(child.type)) {
        for (const r of (_a2 = wc.c) != null ? _a2 : []) rows.push(r);
      } else if (child.type === "tr") rows.push(wc);
      else if (child.type === "colgroup" || child.type === "col") {
      } else rows.push(w("tableRow", {}, [w("tableCell", {}, wc)]));
    });
    const collapse = ((_a = node.style) == null ? void 0 : _a.borderCollapse) === "collapse";
    const table = w(
      "table",
      {
        collapse,
        borderSpacing: collapse ? 0 : (_d = (_c = (_b = node.style) == null ? void 0 : _b.borderSpacing) != null ? _c : num2(node.props.cellspacing)) != null ? _d : 2,
        caption: "top",
        fullWidth: ((_e = node.style) == null ? void 0 : _e.width) != null || ((_f = node.style) == null ? void 0 : _f.widthFactor) != null
      },
      caption ? [caption, ...rows] : rows
    );
    const bordered = node.props.border != null && node.props.border !== "0";
    const result = bordered ? decorated({ border: borderAll({ width: 1, color: Colors.black, style: "solid" }) }, table) : table;
    return applyStyle(result, node.style, {}, ctx);
  }
  function listItem(node, children, ctx, marker) {
    const ts = createTextStyle(node.style);
    const rich = richText(node, ts != null ? ts : {}, ctx);
    const content = rich != null ? rich : children.length === 1 ? children[0] : children.length > 1 ? column(children, { crossAxisAlignment: "start", mainAxisSize: "min" }) : text(textOf(node), ts);
    const result = w("flex", { direction: "row", crossAxisAlignment: "start", mainAxisSize: "max" }, [text(marker, ts), expanded(content)]);
    return applyStyle(result, node.style, {}, ctx);
  }
  function detailsElement(node, children, ctx) {
    const state = ctx.engine.stateFor(ctx.elementId, () => ({ open: node.props.open === true || node.props.open === "open" }));
    const summaryIndex = node.children.findIndex((c) => c.type === "summary");
    const summary = summaryIndex >= 0 ? children[summaryIndex] : text("Details", { fontWeight: 600 });
    const body = children.filter((_, i) => i !== summaryIndex);
    const header = w(
      "gesture",
      {
        gestures: ["tap"],
        ripple: scaleAlpha(M3.onSurface, 0.08),
        cursor: "pointer",
        role: "button",
        onEvent: (e) => {
          var _a, _b;
          if (e.type !== "tap") return;
          state.open = !state.open;
          dispatchEvent(ctx, "toggle", { data: { open: state.open } });
          (_b = (_a = ctx.engine.host).invalidate) == null ? void 0 : _b.call(_a);
        }
      },
      padding(insetsSymmetric(8, 0), row([expanded(summary), w("animatedTransform", { turns: state.open ? 0.5 : 0, duration: 200, curve: "easeInOut", alignment: { x: 0, y: 0 } }, icon("expand_more", 24))], { mainAxisSize: "max" }))
    );
    const content = w("animatedSize", { duration: 200, curve: "easeInOut", alignment: { x: -1, y: -1 } }, state.open ? column(body, { crossAxisAlignment: "start", mainAxisSize: "min" }) : SHRINK);
    return applyStyle(column([header, content], { crossAxisAlignment: "stretch", mainAxisSize: "min" }), node.style, {}, ctx);
  }
  function dialogElement(node, children, ctx) {
    var _a, _b, _c, _d;
    if (node.props.open === false || node.props.open === "false") return SHRINK;
    const content = padding(insetsAll(24), column(children, { crossAxisAlignment: "start", mainAxisSize: "min" }));
    const card = decorated(
      { color: (_b = (_a = node.style) == null ? void 0 : _a.backgroundColor) != null ? _b : 4293715696, radius: (_d = (_c = node.style) == null ? void 0 : _c.borderRadius) != null ? _d : radiusAll(28), shadows: [{ dx: 0, dy: 3, blur: 5, spread: -1, color: 855638016 }, { dx: 0, dy: 6, blur: 10, spread: 0, color: 603979776 }, { dx: 0, dy: 1, blur: 18, spread: 0, color: 520093696 }] },
      w("constrained", { minWidth: 280, maxWidth: 560 }, content)
    );
    const inset = padding({ top: 24, right: 40, bottom: 24, left: 40 }, card);
    return applyStyle(center(inset), withDefaults(node.style, {}), {}, ctx);
  }
  function progressElement(node, meter) {
    var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j, _k, _l;
    const value = num2(node.props.value);
    const min = (_a = num2(node.props.min)) != null ? _a : 0;
    const max = (_b = num2(node.props.max)) != null ? _b : 1;
    let fraction;
    if (meter) fraction = ((value != null ? value : 0.5) - min) / (max - min || 1);
    else fraction = value != null ? value / (max || 1) : null;
    let indicator = (_d = (_c = node.style) == null ? void 0 : _c.color) != null ? _d : meter ? Colors.green : M3.primary;
    if (meter) {
      const low = num2(node.props.low);
      const high = num2(node.props.high);
      const v = value != null ? value : 0.5;
      if (low != null && v < low || high != null && v > high) indicator = (_f = (_e = node.style) == null ? void 0 : _e.color) != null ? _f : Colors.amber;
    }
    return w("control", {
      kind: "progress",
      focusId: node.props.id != null ? String(node.props.id) : null,
      width: (_h = (_g = node.style) == null ? void 0 : _g.width) != null ? _h : null,
      view: {
        variant: "linear",
        value: fraction == null ? null : Math.max(0, Math.min(1, fraction)),
        strokeWidth: (_j = (_i = node.style) == null ? void 0 : _i.height) != null ? _j : 4,
        colors: { indicator, track: (_l = (_k = node.style) == null ? void 0 : _k.backgroundColor) != null ? _l : 4293848814 }
      }
    });
  }
  function pictureElement(node, children, ctx) {
    var _a, _b, _c, _d;
    const env2 = cssEnvironment();
    const source = node.children.find(
      (c) => c.type === "source" && (c.props.srcset || c.props.srcSet || c.props.src) && (!c.props.media || mediaMatches(String(c.props.media), env2.viewportWidth, env2.viewportHeight))
    );
    const imgIndex = node.children.findIndex((c) => c.type === "img");
    if (imgIndex >= 0) {
      const img = node.children[imgIndex];
      if (source) {
        const srcset = String((_b = (_a = source.props.srcset) != null ? _a : source.props.srcSet) != null ? _b : source.props.src);
        const first2 = srcset.split(",")[0].trim().split(/\s+/)[0];
        const swapped = __spreadProps(__spreadValues({}, img), { props: __spreadProps(__spreadValues({}, img.props), { src: first2, srcset: srcset.includes(",") ? srcset : img.props.srcset }) });
        return applyStyle(htmlImg(swapped, [], __spreadProps(__spreadValues({}, ctx), { elementId: `${ctx.elementId}/img` })), node.style, {}, ctx);
      }
      return applyStyle(children[imgIndex], node.style, {}, ctx);
    }
    const fallback = (_d = (_c = children.find((c) => c.t !== "constrained")) != null ? _c : children[0]) != null ? _d : SHRINK;
    return applyStyle(fallback, node.style, {}, ctx);
  }
  var hidden = () => SHRINK;
  var htmlWidgets = {
    div: (node, children, ctx) => htmlDiv(node, children, ctx),
    section: (node, children, ctx) => htmlDiv(node, children, ctx),
    article: (node, children, ctx) => htmlDiv(node, children, ctx),
    aside: (node, children, ctx) => htmlDiv(node, children, ctx),
    main: (node, children, ctx) => htmlDiv(node, children, ctx),
    header: (node, children, ctx) => htmlDiv(node, children, ctx, { fullWidth: true }),
    footer: (node, children, ctx) => htmlDiv(node, children, ctx, { fullWidth: true }),
    body: (node, children, ctx) => htmlDiv(node, children, ctx, { fullWidth: true }),
    html: (node, children, ctx) => htmlDiv(node, children, ctx, { fullWidth: true }),
    span(node, children, ctx) {
      var _a, _b;
      const s = node.style;
      const ts = (_a = createTextStyle(s)) != null ? _a : {};
      const opts = { overflow: (_b = s == null ? void 0 : s.textOverflow) != null ? _b : void 0 };
      if ((s == null ? void 0 : s.whiteSpace) === "nowrap") {
        opts.maxLines = 1;
        opts.softWrap = false;
      }
      if (children.length === 0) return applyStyle(text(textOf(node), ts, opts), s, {}, ctx);
      const rich = richText(node, ts, ctx, opts);
      if (rich) return applyStyle(rich, s, {}, ctx);
      const parts = [];
      const t = textOf(node);
      if (t) parts.push(text(t, ts, opts));
      parts.push(...children);
      return applyStyle(w("wrap", { direction: "horizontal", crossAxisAlignment: "center" }, parts), s, { layoutHandled: true }, ctx);
    },
    p: (node, children, ctx) => textWithChildren(node, children, ctx, { margin: insetsSymmetric(8, 0) }, "wrap"),
    h1: heading(32, 16),
    h2: heading(28, 14),
    h3: heading(24, 12),
    h4: heading(20, 10),
    h5: heading(16, 8),
    h6: heading(14, 6),
    a(node, children, ctx) {
      var _a, _b, _c;
      const href = String((_a = node.props.href) != null ? _a : "#");
      const style = withDefaults(node.style, { color: Colors.blue, textDecoration: { underline: true, overline: false, lineThrough: false } });
      const ts = (_b = createTextStyle(style)) != null ? _b : {};
      let content;
      const rich = richText(node, ts, ctx);
      if (rich) content = rich;
      else if (children.length) {
        const parts = [];
        const t = textOf(node);
        if (t) parts.push(text(t, ts));
        parts.push(...children);
        content = w("wrap", { direction: "horizontal", crossAxisAlignment: "center" }, parts);
      } else content = text(textOf(node), ts);
      const link = w(
        "gesture",
        {
          gestures: ["tap"],
          cursor: "pointer",
          role: "link",
          semanticsLabel: (_c = node.props.title) != null ? _c : null,
          onEvent: (e) => {
            var _a2, _b2, _c2;
            if (e.type === "tap") {
              const target = String((_a2 = node.props.target) != null ? _a2 : "");
              if (target === "_blank" && /^https?:/i.test(href)) (_c2 = (_b2 = ctx.engine.host).openUrl) == null ? void 0 : _c2.call(_b2, href);
              else openLink(ctx, href, node);
            }
          }
        },
        content
      );
      return applyStyle(link, style, {}, ctx);
    },
    button: (node, children, ctx) => htmlButtonLike(node, children, ctx),
    input: htmlInput,
    textarea: htmlTextarea,
    select: htmlSelect,
    option: (node) => {
      var _a, _b;
      return text(String((_b = (_a = node.props.text) != null ? _a : node.props.label) != null ? _b : ""));
    },
    optgroup(node, children, ctx) {
      var _a;
      const label = String((_a = node.props.label) != null ? _a : "");
      return applyStyle(column([text(label, { fontWeight: 700 }), ...children], { crossAxisAlignment: "start", mainAxisSize: "max" }), node.style, {}, ctx);
    },
    datalist: hidden,
    label(node, children, ctx) {
      var _a, _b;
      const ts = __spreadValues({ fontWeight: 500 }, (_a = createTextStyle(node.style)) != null ? _a : {});
      const rich = richText(node, ts, ctx);
      let result = rich != null ? rich : children.length ? row([text(textOf(node), ts), ...children], { mainAxisSize: "min" }) : text(textOf(node), ts);
      const forId = (_b = node.props.for) != null ? _b : node.props.htmlFor;
      if (forId) {
        result = w("gesture", { gestures: ["tap"], cursor: "pointer", onEvent: () => ctx.engine.focusElement(String(forId)) }, result);
      }
      return applyStyle(result, node.style, {}, ctx);
    },
    form(node, children, ctx) {
      return applyStyle(column(children, { crossAxisAlignment: "start", mainAxisSize: "max" }), node.style, {}, ctx);
    },
    fieldset(node, children, ctx) {
      const box = container({
        padding: insetsAll(16),
        decoration: { border: borderAll({ width: 1, color: Colors.grey, style: "solid" }), radius: radiusAll(4) },
        child: column(children, { crossAxisAlignment: "start", mainAxisSize: "max" })
      });
      return applyStyle(box, node.style, {}, ctx);
    },
    legend(node, _children, ctx) {
      return applyStyle(text(textOf(node), { fontWeight: 700 }), node.style, {}, ctx);
    },
    output(node, _children, ctx) {
      const box = container({
        padding: insetsAll(8),
        decoration: { border: borderAll({ width: 1, color: Colors.grey, style: "solid" }), radius: radiusAll(4) },
        child: text(textOf(node), createTextStyle(node.style))
      });
      return applyStyle(box, node.style, {}, ctx);
    },
    img: htmlImg,
    picture: pictureElement,
    source: hidden,
    track: hidden,
    param: hidden,
    map: hidden,
    area: hidden,
    video: mediaElement("video"),
    audio: mediaElement("audio"),
    iframe: (node, _children, ctx) => {
      var _a;
      return webContent(node, ctx, String((_a = node.props.src) != null ? _a : ""), "iframe");
    },
    embed: (node, children, ctx) => {
      var _a;
      return embedTyped(node, children, ctx, String((_a = node.props.src) != null ? _a : ""));
    },
    object(node, children, ctx) {
      var _a, _b;
      const data = String((_a = node.props.data) != null ? _a : "");
      const params = node.children.filter((c) => c.type === "param" && c.props.name);
      let src = data;
      if (params.length && data && !looksLike("image", String((_b = node.props.type) != null ? _b : ""), data)) {
        const q = params.map((p) => {
          var _a2;
          return `${encodeURIComponent(String(p.props.name))}=${encodeURIComponent(String((_a2 = p.props.value) != null ? _a2 : ""))}`;
        }).join("&");
        src = data + (data.includes("?") ? "&" : "?") + q;
      }
      return embedTyped(node, children, ctx, src);
    },
    canvas(node, children, ctx) {
      var _a, _b, _c, _d, _e, _f, _g, _h, _i;
      const raw = Array.isArray(node.props.commands) ? node.props.commands : [];
      const commands = raw.filter((c) => c && typeof c === "object").map((c) => normalizeCommand(commandFromJson(c)));
      const contextId = node.props.contextId;
      if (contextId) return applyStyle(flutterWidgets.CachedCanvas(node, children, ctx), node.style, {}, ctx);
      const result = w("canvas", {
        width: (_c = (_b = num2(node.props.width)) != null ? _b : (_a = node.style) == null ? void 0 : _a.width) != null ? _c : null,
        height: (_f = (_e = num2(node.props.height)) != null ? _e : (_d = node.style) == null ? void 0 : _d.height) != null ? _f : null,
        background: (_i = (_h = CSSParser.parseColor(node.props.backgroundColor)) != null ? _h : (_g = node.style) == null ? void 0 : _g.backgroundColor) != null ? _i : null,
        commands,
        onEvent: (e) => ctx.engine.handleGesture(ctx.elementId, node, e)
      });
      return applyStyle(result, node.style, {}, ctx);
    },
    ul(node, children, ctx) {
      const items = children.map((c, i) => node.children[i].type === "li" ? c : listItemWrap(c, "\u2022 "));
      return applyStyle(column(items, { crossAxisAlignment: "start", mainAxisSize: "max" }), node.style, {}, ctx);
    },
    ol(node, children, ctx) {
      var _a;
      const start = (_a = num2(node.props.start)) != null ? _a : 1;
      const items = children.map((c, i) => {
        var _a2;
        const li = node.children[i];
        const marker = `${start + i}. `;
        if (li.type === "li") return listItem(li, (_a2 = c.c) != null ? _a2 : [], __spreadProps(__spreadValues({}, ctx), { elementId: `${ctx.elementId}/${i}` }), marker);
        return listItemWrap(c, marker);
      });
      return applyStyle(column(items, { crossAxisAlignment: "start", mainAxisSize: "max" }), node.style, {}, ctx);
    },
    li: (node, children, ctx) => listItem(node, children, ctx, "\u2022 "),
    table: htmlTable,
    thead: (_node, children) => w("proxy", {}, children),
    tbody: (_node, children) => w("proxy", {}, children),
    tfoot: (_node, children) => w("proxy", {}, children),
    caption: (node, children, ctx) => textWithChildren(node, children, ctx, { textAlign: "center", padding: insetsSymmetric(4, 0) }, "column"),
    colgroup: hidden,
    col: hidden,
    tr: (node, children) => tableRow(node, children),
    td: (node, children, ctx) => tableCell(node, children, ctx, false),
    th: (node, children, ctx) => tableCell(node, children, ctx, true),
    strong: (node, _c, ctx) => textElement(node, ctx, { fontWeight: 700 }),
    b: (node, _c, ctx) => textElement(node, ctx, { fontWeight: 700 }),
    em: (node, _c, ctx) => textElement(node, ctx, { fontStyle: "italic" }),
    i: (node, _c, ctx) => textElement(node, ctx, { fontStyle: "italic" }),
    u: (node, _c, ctx) => textElement(node, ctx, { textDecoration: { underline: true, overline: false, lineThrough: false } }),
    s: (node, _c, ctx) => textElement(node, ctx, { textDecoration: { underline: false, overline: false, lineThrough: true } }),
    q: (node, _c, ctx) => applyStyle(text(`\u201C${textOf(node)}\u201D`, createTextStyle(node.style)), node.style, {}, ctx),
    code: (node, _c, ctx) => replaceDefaults(node, ctx, monoStyle(4294309365, insetsSymmetric(2, 4)), INLINE_DEFAULTS.code),
    pre(node, _children, ctx) {
      var _a, _b;
      const style = (_a = node.style) != null ? _a : monoStyle(4294309365, insetsAll(8));
      const ts = (_b = createTextStyle(style)) != null ? _b : {};
      const body = w("scroll", { axis: "horizontal" }, text(textOf(node), __spreadValues({ fontFamily: "monospace" }, ts), { softWrap: false }));
      return applyStyle(body, style, {}, ctx);
    },
    kbd: (node, _c, ctx) => replaceDefaults(node, ctx, monoStyle(4293848814, insetsAll(4), { borderRadius: radiusAll(3) }), INLINE_DEFAULTS.kbd),
    samp: (node, _c, ctx) => replaceDefaults(node, ctx, { fontFamily: "monospace" }, INLINE_DEFAULTS.samp),
    var: (node, _c, ctx) => replaceDefaults(node, ctx, { fontStyle: "italic" }, INLINE_DEFAULTS.var),
    cite: (node, _c, ctx) => replaceDefaults(node, ctx, { fontStyle: "italic" }, INLINE_DEFAULTS.cite),
    mark: (node, _c, ctx) => replaceDefaults(node, ctx, { backgroundColor: 4294967040, padding: insetsSymmetric(2, 4) }, INLINE_DEFAULTS.mark),
    del: (node, _c, ctx) => replaceDefaults(node, ctx, { textDecoration: { underline: false, overline: false, lineThrough: true } }, INLINE_DEFAULTS.del),
    ins: (node, _c, ctx) => replaceDefaults(node, ctx, { textDecoration: { underline: true, overline: false, lineThrough: false } }, INLINE_DEFAULTS.ins),
    small: (node, _c, ctx) => replaceDefaults(node, ctx, { fontSize: 12 }, INLINE_DEFAULTS.small),
    sub(node, _c, ctx) {
      var _a;
      const style = (_a = node.style) != null ? _a : { fontSize: 10 };
      const ts = mergeTextStyle({ baselineShift: 3 }, createTextStyle(style));
      return w("padding", { padding: { top: 4, right: 0, bottom: 0, left: 0 } }, text(textOf(node), ts));
    },
    sup(node, _c, ctx) {
      var _a;
      const style = (_a = node.style) != null ? _a : { fontSize: 10 };
      const ts = mergeTextStyle({ baselineShift: -6 }, createTextStyle(style));
      return w("padding", { padding: { top: 0, right: 0, bottom: 4, left: 0 } }, text(textOf(node), ts));
    },
    abbr(node, _c, ctx) {
      var _a, _b;
      const result = w("gesture", { gestures: ["longpress", "hover"], tooltip: String((_a = node.props.title) != null ? _a : ""), onEvent: () => {
      } }, text(textOf(node), __spreadValues({ decoration: Decoration.underline }, (_b = createTextStyle(node.style)) != null ? _b : {})));
      return applyStyle(result, node.style, {}, ctx);
    },
    time: (node, _c, ctx) => applyStyle(text(textOf(node), createTextStyle(node.style)), node.style, {}, ctx),
    data: (node, _c, ctx) => applyStyle(text(textOf(node), createTextStyle(node.style)), node.style, {}, ctx),
    blockquote(node, children, ctx) {
      var _a;
      const child = children.length === 1 ? children[0] : children.length > 1 ? column(children, { crossAxisAlignment: "start", mainAxisSize: "min" }) : text(textOf(node), createTextStyle(node.style));
      const box = container({ padding: insetsAll(16), decoration: { border: { top: none(), right: none(), bottom: none(), left: { width: 4, color: Colors.grey, style: "solid" } } }, child });
      const style = (_a = node.style) != null ? _a : { padding: insetsAll(16), margin: insetsSymmetric(8, 0), borderColor: Colors.grey, borderWidth: 4 };
      return applyStyle(box, __spreadProps(__spreadValues({}, style), { padding: void 0, border: void 0, borderColor: void 0, borderWidth: void 0 }), {}, ctx);
    },
    hr(node, _c, ctx) {
      return applyStyle(flutterWidgets.Divider(__spreadProps(__spreadValues({}, node), { style: null }), [], ctx), node.style, {}, ctx);
    },
    br: () => sizedBox(null, 16),
    figure(node, children, ctx) {
      return applyStyle(column(children, { crossAxisAlignment: "start", mainAxisSize: "min" }), node.style, {}, ctx);
    },
    figcaption: (node, _c, ctx) => replaceDefaults(node, ctx, { fontStyle: "italic", color: Colors.grey, fontSize: 14 }, { italic: true, color: Colors.grey, fontSize: 14 }),
    details: detailsElement,
    summary: (node, children, ctx) => textWithChildren(node, children, ctx, { fontWeight: 700 }, "wrap"),
    dialog: dialogElement,
    progress: (node) => progressElement(node, false),
    meter: (node) => progressElement(node, true),
    nav(node, children, ctx) {
      var _a, _b;
      const s = node.style;
      const result = w(
        "flex",
        { direction: "row", mainAxisAlignment: mainOf((_a = s == null ? void 0 : s.justifyContent) != null ? _a : "space-around"), crossAxisAlignment: crossOf(s == null ? void 0 : s.alignItems), mainAxisSize: "max", gap: (_b = s == null ? void 0 : s.gap) != null ? _b : 0, shrink: true },
        children
      );
      return applyStyle(result, s, { layoutHandled: true }, ctx);
    }
  };
  function none() {
    return { width: 0, color: Colors.black, style: "none" };
  }
  function listItemWrap(child, marker) {
    return w("flex", { direction: "row", crossAxisAlignment: "start", mainAxisSize: "max" }, [text(marker), expanded(child)]);
  }

  // core/src/render/layout/flex.ts
  var RenderFlexible = class extends RenderObject {
    performLayout(c) {
      const child = this.child;
      if (child) {
        child.layout(c);
        child.offset = { x: 0, y: 0 };
        this.size = __spreadValues({}, child.size);
      } else {
        this.size = constrain(c, { width: 0, height: 0 });
      }
    }
  };
  function flexInfo(child) {
    var _a;
    if (child instanceof RenderFlexible) {
      const p = child.props;
      return {
        flex: typeof p.flex === "number" && p.flex > 0 ? p.flex : 0,
        fit: p.fit === "loose" ? "loose" : "tight",
        shrink: typeof p.shrink === "number" ? p.shrink : 1,
        alignSelf: (_a = p.alignSelf) != null ? _a : null,
        basis: typeof p.basis === "number" ? p.basis : null
      };
    }
    return { flex: 0, fit: "tight", shrink: 1, alignSelf: null, basis: null };
  }
  function mainAxisAlignmentFromCss(value) {
    switch ((value != null ? value : "").toLowerCase()) {
      case "center":
        return "center";
      case "flex-end":
      case "end":
      case "right":
        return "end";
      case "space-between":
        return "spaceBetween";
      case "space-around":
        return "spaceAround";
      case "space-evenly":
        return "spaceEvenly";
      default:
        return "start";
    }
  }
  function crossAxisAlignmentFromCss(value) {
    switch ((value != null ? value : "").toLowerCase()) {
      case "center":
        return "center";
      case "flex-end":
      case "end":
        return "end";
      case "stretch":
        return "stretch";
      case "baseline":
      case "first baseline":
        return "baseline";
      default:
        return "start";
    }
  }
  var RenderFlex = class extends RenderObject {
    constructor() {
      super(...arguments);
      this.overflow = 0;
    }
    get horizontal() {
      return this.props.direction !== "column";
    }
    main(s) {
      return this.horizontal ? s.width : s.height;
    }
    cross(s) {
      return this.horizontal ? s.height : s.width;
    }
    /** Constraints for a child with the given main extent bounds. */
    childConstraints(minMain, maxMain, c, align2) {
      const stretch = align2 === "stretch";
      if (this.horizontal) {
        const maxCross2 = c.maxHeight;
        return {
          minWidth: minMain,
          maxWidth: maxMain,
          minHeight: stretch && Number.isFinite(maxCross2) ? maxCross2 : 0,
          maxHeight: maxCross2
        };
      }
      const maxCross = c.maxWidth;
      return {
        minWidth: stretch && Number.isFinite(maxCross) ? maxCross : 0,
        maxWidth: maxCross,
        minHeight: minMain,
        maxHeight: maxMain
      };
    }
    performLayout(c) {
      var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j;
      const horizontal = this.horizontal;
      const gap = (_a = this.props.gap) != null ? _a : 0;
      const crossAlign = (_b = this.props.crossAxisAlignment) != null ? _b : "start";
      const maxMain = horizontal ? c.maxWidth : c.maxHeight;
      const canFlex = Number.isFinite(maxMain);
      const children = this.children;
      const infos = children.map(flexInfo);
      const gaps = Math.max(0, children.length - 1) * gap;
      let totalFlex = 0;
      let allocated = 0;
      const isFlex = infos.map((info) => canFlex && info.flex > 0);
      for (let i = 0; i < children.length; i++) {
        const child = children[i];
        const info = infos[i];
        if (isFlex[i]) {
          totalFlex += info.flex;
          continue;
        }
        const align2 = (_c = info.alignSelf) != null ? _c : crossAlign;
        if (info.basis != null) {
          child.layout(this.childConstraints(info.basis, info.basis, c, align2));
        } else {
          child.layout(this.childConstraints(0, INF, c, align2));
        }
        allocated += this.main(child.size);
      }
      if (this.props.shrink && canFlex && allocated + gaps > maxMain + 0.01) {
        this.shrinkChildren(c, infos, isFlex, maxMain - gaps);
        allocated = 0;
        for (let i = 0; i < children.length; i++) if (!isFlex[i]) allocated += this.main(children[i].size);
      }
      const freeSpace = Math.max(0, (canFlex ? maxMain : 0) - allocated - gaps);
      if (totalFlex > 0) {
        const perFlex = freeSpace / totalFlex;
        let lastFlexIndex = -1;
        for (let i = 0; i < children.length; i++) if (isFlex[i]) lastFlexIndex = i;
        let used = 0;
        for (let i = 0; i < children.length; i++) {
          if (!isFlex[i]) continue;
          const info = infos[i];
          const maxChild = i === lastFlexIndex ? Math.max(0, freeSpace - used) : perFlex * info.flex;
          const minChild = info.fit === "tight" ? maxChild : 0;
          const align2 = (_d = info.alignSelf) != null ? _d : crossAlign;
          children[i].layout(this.childConstraints(minChild, maxChild, c, align2));
          const extent = this.main(children[i].size);
          used += extent;
          allocated += extent;
        }
      }
      const mainSizeMax = ((_e = this.props.mainAxisSize) != null ? _e : "max") === "max";
      const allocatedWithGaps = allocated + gaps;
      const idealMain = mainSizeMax && canFlex ? maxMain : allocatedWithGaps;
      let crossSize = 0;
      let maxBaseline = 0;
      let maxBelowBaseline = 0;
      const baselines = [];
      for (let i = 0; i < children.length; i++) {
        const child = children[i];
        const align2 = (_f = infos[i].alignSelf) != null ? _f : crossAlign;
        if (align2 === "baseline" && horizontal) {
          const b = (_g = child.baseline()) != null ? _g : child.size.height;
          baselines.push(b);
          maxBaseline = Math.max(maxBaseline, b);
          maxBelowBaseline = Math.max(maxBelowBaseline, child.size.height - b);
        } else {
          baselines.push(null);
          crossSize = Math.max(crossSize, this.cross(child.size));
        }
      }
      crossSize = Math.max(crossSize, maxBaseline + maxBelowBaseline);
      if (crossAlign === "stretch") {
        const maxCross = horizontal ? c.maxHeight : c.maxWidth;
        if (Number.isFinite(maxCross)) crossSize = Math.max(crossSize, maxCross);
      }
      const size = constrain(
        c,
        horizontal ? { width: idealMain, height: crossSize } : { width: crossSize, height: idealMain }
      );
      this.size = size;
      const actualMain = this.main(size);
      const actualCross = this.cross(size);
      this.overflow = Math.max(0, allocatedWithGaps - actualMain);
      const remaining = Math.max(0, actualMain - allocatedWithGaps);
      const n = children.length;
      let leading = 0;
      let between = 0;
      switch ((_h = this.props.mainAxisAlignment) != null ? _h : "start") {
        case "end":
          leading = remaining;
          break;
        case "center":
          leading = remaining / 2;
          break;
        case "spaceBetween":
          between = n > 1 ? remaining / (n - 1) : 0;
          break;
        case "spaceAround":
          between = n > 0 ? remaining / n : 0;
          leading = between / 2;
          break;
        case "spaceEvenly":
          between = n > 0 ? remaining / (n + 1) : 0;
          leading = between;
          break;
      }
      const flip = this.props.reverse === true || !horizontal && this.props.verticalDirection === "up";
      let pos = leading;
      for (let k = 0; k < n; k++) {
        const i = flip ? n - 1 - k : k;
        const child = children[i];
        const align2 = (_i = infos[i].alignSelf) != null ? _i : crossAlign;
        const childCross = this.cross(child.size);
        let crossPos = 0;
        switch (align2) {
          case "end":
            crossPos = actualCross - childCross;
            break;
          case "center":
            crossPos = (actualCross - childCross) / 2;
            break;
          case "baseline":
            crossPos = horizontal ? maxBaseline - ((_j = baselines[i]) != null ? _j : 0) : 0;
            break;
          default:
            crossPos = 0;
        }
        if (!horizontal && this.props.verticalDirection === "up" && align2 !== "baseline") {
        }
        child.offset = horizontal ? { x: pos, y: crossPos } : { x: crossPos, y: pos };
        pos += this.main(child.size) + gap + between;
      }
    }
    /** CSS flex-shrink: reduce inflexible children so they fit [available]. */
    shrinkChildren(c, infos, isFlex, available) {
      var _a, _b;
      const crossAlign = (_a = this.props.crossAxisAlignment) != null ? _a : "start";
      const children = this.children;
      const base = children.map((ch) => this.main(ch.size));
      const minContent = children.map(
        (ch, i) => isFlex[i] ? 0 : this.horizontal ? ch.minIntrinsicWidth(INF) : ch.minIntrinsicHeight(c.maxWidth)
      );
      const frozen = children.map((_, i) => isFlex[i] || infos[i].shrink <= 0);
      const target = base.slice();
      for (let iter = 0; iter < 8; iter++) {
        let used = 0;
        let weighted = 0;
        for (let i = 0; i < children.length; i++) {
          if (isFlex[i]) continue;
          used += target[i];
          if (!frozen[i]) weighted += infos[i].shrink * base[i];
        }
        const over = used - available;
        if (over <= 0.01 || weighted <= 0) break;
        let clamped = false;
        for (let i = 0; i < children.length; i++) {
          if (frozen[i]) continue;
          const share = over * infos[i].shrink * base[i] / weighted;
          const next = target[i] - share;
          if (next < minContent[i]) {
            target[i] = minContent[i];
            frozen[i] = true;
            clamped = true;
          } else {
            target[i] = next;
          }
        }
        if (!clamped) break;
      }
      for (let i = 0; i < children.length; i++) {
        if (isFlex[i] || Math.abs(target[i] - base[i]) < 0.01) continue;
        const align2 = (_b = infos[i].alignSelf) != null ? _b : crossAlign;
        const extent = Math.max(0, target[i]);
        children[i].layout(this.childConstraints(extent, extent, c, align2));
      }
    }
    get overflowExtent() {
      return this.overflow;
    }
    baseline() {
      for (const child of this.children) {
        const b = child.baseline();
        if (b != null) return b + child.offset.y;
      }
      return null;
    }
    computeMinIntrinsicWidth(height) {
      return this.intrinsicMain("min", true, height);
    }
    computeMaxIntrinsicWidth(height) {
      return this.intrinsicMain("max", true, height);
    }
    computeMinIntrinsicHeight(width) {
      return this.intrinsicMain("min", false, width);
    }
    computeMaxIntrinsicHeight(width) {
      return this.intrinsicMain("max", false, width);
    }
    intrinsicMain(kind, widthAxis, extent) {
      var _a;
      const gap = (_a = this.props.gap) != null ? _a : 0;
      const gaps = Math.max(0, this.children.length - 1) * gap;
      const get = (ch) => widthAxis ? kind === "min" ? ch.minIntrinsicWidth(extent) : ch.maxIntrinsicWidth(extent) : kind === "min" ? ch.minIntrinsicHeight(extent) : ch.maxIntrinsicHeight(extent);
      if (this.horizontal === widthAxis) {
        let inflexible = 0;
        let maxPerFlex = 0;
        let totalFlex = 0;
        for (const ch of this.children) {
          const info = flexInfo(ch);
          const v = get(ch);
          if (info.flex > 0) {
            totalFlex += info.flex;
            maxPerFlex = Math.max(maxPerFlex, v / info.flex);
          } else inflexible += v;
        }
        return inflexible + maxPerFlex * totalFlex + gaps;
      }
      let m = 0;
      for (const ch of this.children) m = Math.max(m, get(ch));
      return m;
    }
  };

  // core/src/widgets/nextjs.ts
  var GOLD = 4292260714;
  var FIELD_FILL = 4278851110;
  var FIELD_BORDER = 4280038480;
  var TEXT = 4294438620;
  var HINT = 4285432724;
  var INK = 4278587946;
  var ERROR = 4290791727;
  function linkChildStyle(child) {
    if (child.style) return child.style;
    const inline = child.props.style;
    if (inline && typeof inline === "object" && !Array.isArray(inline)) return CSSParser.parse(inline);
    return null;
  }
  function withGaps(children, gap, horizontal) {
    if (gap <= 0 || children.length <= 1) return children;
    const out = [];
    children.forEach((c, i) => {
      out.push(c);
      if (i < children.length - 1) out.push(sizedBox(horizontal ? gap : 0, horizontal ? 0 : gap));
    });
    return out;
  }
  function linkFlow(node, flow) {
    var _a;
    const s = node.style;
    const isColumn = (s == null ? void 0 : s.flexDirection) === "column" || (s == null ? void 0 : s.flexDirection) === "column-reverse";
    const children = withGaps(flow, (_a = s == null ? void 0 : s.gap) != null ? _a : 0, !isColumn);
    const opts = {
      mainAxisSize: "min",
      mainAxisAlignment: mainAxisAlignmentFromCss(s == null ? void 0 : s.justifyContent),
      crossAxisAlignment: (s == null ? void 0 : s.alignItems) == null ? "center" : crossAxisAlignmentFromCss(s == null ? void 0 : s.alignItems)
    };
    return isColumn ? column(children, opts) : row(children, opts);
  }
  function layoutLinkChildren(node, children) {
    const aligned = node.children.length === children.length;
    const flow = [];
    const overlays = [];
    children.forEach((child, i) => {
      var _a, _b, _c, _d;
      const cs = aligned ? linkChildStyle(node.children[i]) : null;
      if (cs && (cs.position === "absolute" || cs.position === "fixed")) {
        overlays.push(w("positioned", { top: (_a = cs.top) != null ? _a : null, left: (_b = cs.left) != null ? _b : null, right: (_c = cs.right) != null ? _c : null, bottom: (_d = cs.bottom) != null ? _d : null }, child));
      } else flow.push(child);
    });
    const base = flow.length === 0 ? SHRINK : flow.length === 1 ? flow[0] : linkFlow(node, flow);
    if (!overlays.length) return base;
    return w("stack", { fit: "loose", clip: false }, [base, ...overlays]);
  }
  var nextjsLink = (node, children, ctx) => {
    var _a, _b, _c, _d, _e, _f;
    const href = node.props.href != null ? String(node.props.href) : null;
    const replace2 = node.props.replace === true;
    const label = node.props.text != null ? String(node.props.text) : href != null ? href : "Navigate";
    const s = node.style;
    const ariaLabel = node.props.ariaLabel != null ? String(node.props.ariaLabel) : null;
    const isButtonLike = s != null && (s.backgroundColor != null || s.gradient != null || s.border != null || s.borderColor != null || s.padding != null);
    const content = children.length ? layoutLinkChildren(node, children) : text(
      label,
      {
        color: (_a = s == null ? void 0 : s.color) != null ? _a : GOLD,
        fontSize: (_b = s == null ? void 0 : s.fontSize) != null ? _b : void 0,
        fontWeight: (_c = s == null ? void 0 : s.fontWeight) != null ? _c : isButtonLike ? 700 : void 0,
        letterSpacing: (_d = s == null ? void 0 : s.letterSpacing) != null ? _d : void 0
      },
      { textAlign: (_e = s == null ? void 0 : s.textAlign) != null ? _e : isButtonLike ? "center" : "start" }
    );
    const styled = applyStyle(content, s, { applyFlex: false }, ctx);
    let tappable = w(
      "gesture",
      {
        gestures: href != null ? ["tap"] : [],
        opaque: true,
        cursor: href != null ? "pointer" : "default",
        role: ariaLabel ? "button" : "link",
        semanticsLabel: ariaLabel,
        onEvent: (e) => {
          var _a2, _b2;
          if (e.type === "tap" && href != null) (_b2 = (_a2 = ctx.engine.host).navigate) == null ? void 0 : _b2.call(_a2, href, replace2);
        }
      },
      styled
    );
    const flex = (_f = s == null ? void 0 : s.flex) != null ? _f : s == null ? void 0 : s.flexGrow;
    if (flex != null) tappable = w("flexible", { flex, fit: "tight" }, sizedBox(Number.POSITIVE_INFINITY, null, tappable));
    return tappable;
  };
  function optionsOf(f) {
    var _a, _b, _c, _d;
    const out = [];
    if (Array.isArray(f.options)) {
      for (const o of f.options) {
        if (o && typeof o === "object") {
          const v = String((_b = (_a = o.value) != null ? _a : o.label) != null ? _b : "");
          out.push({ value: v, label: String((_c = o.label) != null ? _c : v) });
        } else if (o != null) out.push({ value: String(o), label: String(o) });
      }
    }
    if (!out.length) {
      for (const part of String((_d = f.placeholder) != null ? _d : "").split(",")) {
        const v = part.trim();
        if (v) out.push({ value: v, label: v });
      }
    }
    return out;
  }
  function numProp(f, key, fallback) {
    var _a;
    return (_a = toNumber(f[key])) != null ? _a : fallback;
  }
  function fmtRange(v) {
    return v === Math.round(v) ? String(Math.round(v)) : String(v);
  }
  function fieldBox(child, pad = insetsSymmetric(4, 8)) {
    return container({ child, padding: pad, decoration: { color: FIELD_FILL, radius: radiusAll(10), border: borderAll({ width: 1, color: FIELD_BORDER, style: "solid" }) } });
  }
  var nextjsForm = (node, _children, ctx) => {
    var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j, _k, _l, _m, _n;
    const action = String((_a = node.props.action) != null ? _a : "");
    const submitLabel = String((_b = node.props.submitLabel) != null ? _b : "Submit");
    const fields = Array.isArray(node.props.fields) ? node.props.fields.filter((f) => f && typeof f === "object") : [];
    const state = ctx.engine.stateFor(ctx.elementId, () => {
      var _a2, _b2, _c2, _d2;
      const values = {};
      for (const f of fields) {
        const name = String((_a2 = f.name) != null ? _a2 : "");
        if (!name) continue;
        const type = String((_b2 = f.type) != null ? _b2 : "");
        const value = f.value != null ? String(f.value) : "";
        if (type === "select") {
          const options = optionsOf(f);
          values[name] = options.some((o) => o.value === value) ? value : (_d2 = (_c2 = options[0]) == null ? void 0 : _c2.value) != null ? _d2 : value;
        } else if (type === "checkbox") {
          values[name] = value === "true" || value === "on" ? "true" : "false";
        } else if (type === "range") {
          const min = numProp(f, "min", 0);
          const max = numProp(f, "max", 100);
          const parsed = toNumber(value);
          values[name] = fmtRange(max > min ? Math.min(max, Math.max(min, parsed != null ? parsed : min)) : min);
        } else values[name] = value;
      }
      return { values, busy: false, error: null };
    });
    const update = (patch) => {
      var _a2, _b2;
      Object.assign(state, patch);
      (_b2 = (_a2 = ctx.engine.host).invalidate) == null ? void 0 : _b2.call(_a2);
    };
    const submit = async () => {
      const handler = ctx.engine.host.submitForm;
      if (!handler || state.busy) return;
      update({ busy: true, error: null });
      let error = null;
      try {
        error = await handler(action, __spreadValues({}, state.values));
      } catch (e) {
        error = `Request failed: ${e}`;
      }
      update({ busy: false, error });
    };
    const labelOf = (label) => padding(insetsOnly({ bottom: 4 }), text(label, { color: HINT, fontSize: 11, fontWeight: 600 }));
    const items = [];
    for (const f of fields) {
      const name = String((_c = f.name) != null ? _c : "");
      if (!name) continue;
      const type = String((_d = f.type) != null ? _d : "");
      if (type === "hidden") continue;
      const label = f.label != null ? String(f.label) : null;
      let control;
      if (type === "select") {
        const options = optionsOf(f);
        const current2 = options.some((o) => o.value === state.values[name]) ? state.values[name] : (_f = (_e = options[0]) == null ? void 0 : _e.value) != null ? _f : null;
        const ts = { color: TEXT, fontSize: 14 };
        control = container({
          padding: insetsSymmetric(4, 10),
          decoration: { color: FIELD_FILL, radius: radiusAll(10), border: borderAll({ width: 1, color: FIELD_BORDER, style: "solid" }) },
          child: w("control", {
            kind: "select",
            view: {
              value: current2,
              options: options.map((o) => ({ value: o.value, label: o.label, group: null, disabled: false })),
              placeholder: String((_g = f.placeholder) != null ? _g : name),
              enabled: !state.busy,
              textStyle: toSpec(ts),
              hintStyle: toSpec(__spreadProps(__spreadValues({}, ts), { color: HINT })),
              colors: { text: TEXT, fill: FIELD_FILL, icon: GOLD, menu: FIELD_FILL, hint: HINT }
            },
            onEvent: (e) => {
              var _a2, _b2;
              if (e.type === "change") update({ values: __spreadProps(__spreadValues({}, state.values), { [name]: String((_b2 = (_a2 = e.value) != null ? _a2 : current2) != null ? _b2 : "") }) });
            }
          })
        });
      } else if (type === "checkbox") {
        const checked = state.values[name] === "true";
        const toggle = (v) => update({ values: __spreadProps(__spreadValues({}, state.values), { [name]: v ? "true" : "false" }) });
        control = w(
          "gesture",
          {
            gestures: state.busy ? [] : ["tap"],
            ripple: scaleAlpha(GOLD, 0.12),
            rippleRadius: 10,
            cursor: state.busy ? "default" : "pointer",
            onEvent: (e) => {
              if (e.type === "tap") toggle(!checked);
            }
          },
          fieldBox(
            row(
              [
                w("control", {
                  kind: "checkbox",
                  view: { checked, enabled: !state.busy, colors: { fill: GOLD, check: INK, border: HINT } },
                  controlled: true,
                  onEvent: (e) => {
                    if (e.type === "change") toggle(e.value === true);
                  }
                }),
                w("flexible", { flex: 1, fit: "loose" }, text(String((_i = (_h = f.placeholder) != null ? _h : label) != null ? _i : name), { color: TEXT, fontSize: 13 }))
              ],
              { mainAxisSize: "min" }
            )
          )
        );
      } else if (type === "range") {
        const min = numProp(f, "min", 0);
        const max = numProp(f, "max", 100);
        const step = numProp(f, "step", 1);
        const hasRoom = max > min;
        const current2 = hasRoom ? Math.min(max, Math.max(min, (_j = toNumber(state.values[name])) != null ? _j : min)) : min;
        const slider = hasRoom ? w("control", {
          kind: "slider",
          view: {
            value: current2,
            min,
            max,
            step: step > 0 ? step : null,
            enabled: !state.busy,
            trackHeight: 3,
            colors: { active: GOLD, inactive: FIELD_BORDER, thumb: GOLD, overlay: withOpacity(GOLD, 0.15) }
          },
          controlled: true,
          onEvent: (e) => {
            if (e.type === "change" || e.type === "input") update({ values: __spreadProps(__spreadValues({}, state.values), { [name]: fmtRange(Number(e.value)) }) });
          }
        }) : padding(insetsSymmetric(8, 0), text(String((_k = f.placeholder) != null ? _k : "No range available"), { color: HINT, fontSize: 13 }));
        control = fieldBox(
          row([expanded(slider), sizedBox(6, null), text((_l = state.values[name]) != null ? _l : fmtRange(current2), { color: GOLD, fontSize: 13, fontWeight: 700 })]),
          insetsSymmetric(6, 10)
        );
      } else {
        const multiline = type === "textarea";
        const ts = { color: TEXT, fontSize: 14, height: 1.3 };
        control = w("control", {
          kind: "textInput",
          lines: multiline ? 3 : 1,
          maxLines: multiline ? 4 : 1,
          padding: [12, 12, 12, 12],
          lineHeight: 14 * 1.3,
          view: {
            value: (_m = state.values[name]) != null ? _m : "",
            placeholder: String((_n = f.placeholder) != null ? _n : name),
            inputType: type === "password" ? "password" : type === "number" ? "number" : "text",
            allowedPattern: type === "number" ? "[0-9.\\-]" : void 0,
            multiline,
            enabled: true,
            variant: "outline",
            textStyle: toSpec(ts),
            hintStyle: toSpec(__spreadProps(__spreadValues({}, ts), { color: HINT })),
            contentPadding: [12, 12, 12, 12],
            colors: { text: TEXT, hint: HINT, fill: FIELD_FILL, border: FIELD_BORDER, focusedBorder: GOLD, focusedBorderWidth: 1.5, cursor: GOLD, radius: 10 }
          },
          onEvent: (e) => {
            var _a2;
            if (e.type === "input" || e.type === "change") state.values = __spreadProps(__spreadValues({}, state.values), { [name]: String((_a2 = e.value) != null ? _a2 : "") });
            else if (e.type === "submit" && !multiline && !state.busy) void submit();
          }
        });
      }
      items.push(padding(insetsOnly({ bottom: 12 }), column([...label ? [labelOf(label)] : [], control], { crossAxisAlignment: "start", mainAxisSize: "min" })));
    }
    if (state.error) items.push(padding(insetsOnly({ bottom: 8 }), text(state.error, { color: ERROR, fontSize: 13 })));
    const buttonChild = state.busy ? sizedBox(16, 16, w("control", { kind: "progress", view: { variant: "circular", value: null, strokeWidth: 2, colors: { indicator: INK, track: null } } })) : text(submitLabel, { fontWeight: 700, letterSpacing: 0.3, color: INK, fontSize: 14 });
    const button = w(
      "gesture",
      {
        gestures: state.busy ? [] : ["tap"],
        ripple: scaleAlpha(INK, 0.12),
        cursor: state.busy ? "default" : "pointer",
        role: "button",
        semanticsLabel: submitLabel,
        onEvent: (e) => {
          if (e.type === "tap") void submit();
        }
      },
      container({
        padding: insetsSymmetric(14, 16),
        alignment: { x: 0, y: 0 },
        decoration: { color: state.busy ? withOpacity(GOLD, 0.5) : GOLD, radius: radiusAll(10), shadows: [] },
        child: buttonChild
      })
    );
    items.push(sizedBox(Number.POSITIVE_INFINITY, null, w("constrained", { minHeight: 40 }, button)));
    return column(items, { mainAxisSize: "min" });
  };
  var nextjsWidgets = {
    NextjsLink: nextjsLink,
    "next-link": nextjsLink,
    NextjsForm: nextjsForm,
    "nextjs-form": nextjsForm
  };

  // core/src/widgets/registry.ts
  function registerDefaultWidgets(engine) {
    engine.registerWidgets(flutterWidgets);
    engine.registerWidgets(animationWidgets);
    engine.registerWidgets(htmlWidgets);
    engine.registerWidgets(nextjsWidgets);
  }

  // core/src/engine/engine.ts
  var ElpianServices = class {
    constructor(appId = "default") {
      this.appId = appId;
      this.events = new EventDispatcher();
      this.stylesheets = new StylesheetManager();
      this.canvasContexts = new CanvasContextStore();
      this.canvas = new CanvasExecutor();
      this.dom = new ElpianDOM();
      this.registry = /* @__PURE__ */ new Map();
    }
    /** Namespace a guest-chosen id so mini apps never collide (`appId::id`). */
    scopeId(id2) {
      return `${this.appId}::${id2}`;
    }
    dispose() {
      this.events.clear();
      this.events.bus.removeAllEventListeners();
      this.stylesheets.clear();
      this.canvasContexts.clearAll();
      this.canvas.clear();
      this.dom.clear();
    }
  };
  var EVENT_GESTURES = {
    click: "tap",
    tap: "tap",
    doubletap: "doubletap",
    dblclick: "doubletap",
    longpress: "longpress",
    contextmenu: "longpress",
    tapdown: "tapdown",
    tapup: "tapup",
    tapcancel: "tapcancel",
    drag: "pan",
    dragstart: "pan",
    dragend: "pan",
    swipeleft: "swipe",
    swiperight: "swipe",
    swipeup: "swipe",
    swipedown: "swipe",
    pointerdown: "pointer",
    pointerup: "pointer",
    pointermove: "pointer",
    pointercancel: "pointer",
    pointerenter: "hover",
    pointerexit: "hover",
    pointerhover: "hover",
    mouseenter: "hover",
    mouseleave: "hover",
    keydown: "key",
    keyup: "key",
    keypress: "key",
    focus: "focus",
    blur: "focus",
    scalestart: "scale",
    scaleupdate: "scale",
    scaleend: "scale",
    pinchstart: "scale",
    pinchupdate: "scale",
    pinchend: "scale",
    rotatestart: "scale",
    rotateupdate: "scale",
    rotateend: "scale",
    scroll: "scroll"
  };
  var EVENT_TYPE_NAMES = {
    click: "click",
    tap: "tap",
    doubletap: "doubleClick",
    longpress: "longPress",
    tapdown: "tapDown",
    tapup: "tapUp",
    tapcancel: "tapCancel",
    pointerdown: "pointerDown",
    pointerup: "pointerUp",
    pointermove: "pointerMove",
    pointerenter: "pointerEnter",
    pointerexit: "pointerExit",
    pointerhover: "pointerHover",
    pointercancel: "pointerCancel",
    dragstart: "dragStart",
    drag: "drag",
    dragend: "dragEnd",
    dragenter: "dragEnter",
    dragleave: "dragLeave",
    dragover: "dragOver",
    drop: "drop",
    focus: "focus",
    blur: "blur",
    input: "input",
    change: "change",
    submit: "submit",
    keydown: "keyDown",
    keyup: "keyUp",
    keypress: "keyPress",
    scroll: "scroll",
    swipeleft: "swipeLeft",
    swiperight: "swipeRight",
    swipeup: "swipeUp",
    swipedown: "swipeDown",
    scalestart: "scaleStart",
    scaleupdate: "scaleUpdate",
    scaleend: "scaleEnd",
    pinchstart: "pinchStart",
    pinchupdate: "pinchUpdate",
    pinchend: "pinchEnd",
    rotatestart: "rotateStart",
    rotateupdate: "rotateUpdate",
    rotateend: "rotateEnd",
    load: "load",
    select: "select",
    reset: "reset",
    resize: "resize"
  };
  function eventTypeFor(name) {
    var _a;
    return (_a = EVENT_TYPE_NAMES[name]) != null ? _a : "custom";
  }
  var ElpianEngine = class {
    constructor(services, host2 = {}) {
      /** Per-element state that survives re-renders (details open, select value …). */
      this.state = /* @__PURE__ */ new Map();
      this.seen = /* @__PURE__ */ new Set();
      this.scenes = /* @__PURE__ */ new Map();
      /** Nodes registered with the dispatcher this render. */
      this.registered = /* @__PURE__ */ new Set();
      this.previousRegistered = /* @__PURE__ */ new Set();
      // ---------------------------------------------------------------------------
      // Forms and image maps
      // ---------------------------------------------------------------------------
      this.formFields = /* @__PURE__ */ new Map();
      /** `<map name>` → its `<area>` nodes, collected before each render. */
      this.imageMaps = /* @__PURE__ */ new Map();
      /** `<datalist id>` → its option values (feeds `<input list>` suggestions). */
      this.datalists = /* @__PURE__ */ new Map();
      // ---------------------------------------------------------------------------
      // Drag and drop (Draggable / DragTarget)
      // ---------------------------------------------------------------------------
      this.dragTarget = null;
      this.services = services != null ? services : new ElpianServices();
      this.host = host2;
      registerDefaultWidgets(this);
    }
    // ---------------------------------------------------------------------------
    // Configuration
    // ---------------------------------------------------------------------------
    registerWidget(type, builder) {
      this.services.registry.set(type, builder);
    }
    registerWidgets(builders) {
      for (const [k, v] of Object.entries(builders)) this.services.registry.set(k, v);
    }
    loadStylesheet(sheet) {
      this.services.stylesheets.load(sheet);
    }
    clearStylesheets() {
      this.services.stylesheets.clear();
    }
    resolveUrl(src) {
      var _a, _b, _c, _d, _e;
      if (!src || /^(https?:|data:|blob:|asset:|file:|content:)/i.test(src)) return src;
      const base = (_c = (_b = (_a = this.host).baseUrl) == null ? void 0 : _b.call(_a)) != null ? _c : null;
      if (!base) return src;
      if (src.startsWith("//")) return (base.startsWith("https") ? "https:" : "http:") + src;
      if (src.startsWith("/")) {
        const origin = (_e = (_d = /^[a-z]+:\/\/[^/]+/i.exec(base)) == null ? void 0 : _d[0]) != null ? _e : base;
        return origin + src;
      }
      return base.replace(/\/+$/, "") + "/" + src;
    }
    // ---------------------------------------------------------------------------
    // Element state
    // ---------------------------------------------------------------------------
    /** State for [elementId], created by [init] on first use; kept while the element renders. */
    stateFor(elementId, init) {
      this.seen.add(elementId);
      if (!this.state.has(elementId)) this.state.set(elementId, init());
      return this.state.get(elementId);
    }
    setState(elementId, patch) {
      var _a, _b, _c;
      const current2 = (_a = this.state.get(elementId)) != null ? _a : {};
      this.state.set(elementId, __spreadValues(__spreadValues({}, current2), patch));
      (_c = (_b = this.host).invalidate) == null ? void 0 : _c.call(_b);
    }
    // ---------------------------------------------------------------------------
    // Rendering
    // ---------------------------------------------------------------------------
    renderFromJson(json) {
      return this.render(nodeFromJson(json));
    }
    render(root) {
      this.seen = /* @__PURE__ */ new Set();
      this.formFields = /* @__PURE__ */ new Map();
      this.imageMaps = collectMaps(root);
      this.datalists = collectDatalists(root);
      this.previousRegistered = this.registered;
      this.registered = /* @__PURE__ */ new Set();
      const ctx = { engine: this, parentId: null, ancestors: [], path: "r", elementId: "r", formId: null };
      const result = this.renderNode(root, ctx, 0);
      this.collectGarbage();
      return result;
    }
    collectGarbage() {
      for (const id2 of [...this.state.keys()]) if (!this.seen.has(id2)) this.state.delete(id2);
      for (const [id2, entry] of [...this.scenes]) {
        if (!this.seen.has(id2)) {
          entry.controller.dispose();
          this.scenes.delete(id2);
        }
      }
      for (const id2 of this.previousRegistered) if (!this.registered.has(id2)) this.services.events.unregisterNode(id2);
    }
    /** Resolve the cascaded style of [node] (stylesheet + `@media` + inline + `!important`). */
    resolveStyle(node, ancestors) {
      const inline = isMap(node.props.style) ? node.props.style : null;
      const sheets = this.services.stylesheets;
      if (sheets.hasRules) {
        const computed = sheets.getComputedStyleMap(this.factsOf(node), { ancestors, inlineStyles: inline });
        return Object.keys(computed).length ? CSSParser.parse(computed) : null;
      }
      if (inline) return CSSParser.parse(sheets.substituteVariables(inline));
      return null;
    }
    factsOf(node) {
      var _a;
      return {
        tagName: node.type,
        id: (_a = node.key) != null ? _a : typeof node.props.id === "string" ? node.props.id : null,
        classes: classesOf(node),
        attributes: node.props
      };
    }
    renderNode(node, parentCtx, index) {
      var _a, _b, _c, _d, _e;
      const path = `${parentCtx.path}/${index}`;
      const elementId = (_a = node.key) != null ? _a : typeof node.props.id === "string" && node.props.id ? `#${node.props.id}` : `${path}:${node.type}`;
      this.seen.add(elementId);
      if (node.type === "#text") {
        return w("text", { text: String((_b = node.props.text) != null ? _b : "") });
      }
      const builder = this.services.registry.get(node.type);
      if (!builder) {
        (_d = (_c = this.host).log) == null ? void 0 : _d.call(_c, "warn", `Unknown widget type "${node.type}"`);
        return w("decorated", { decoration: { color: 871646006 } }, w("padding", { padding: { top: 8, right: 8, bottom: 8, left: 8 } }, w("text", { text: `Unknown widget: ${node.type}` })));
      }
      const style = (_e = this.resolveStyle(node, parentCtx.ancestors)) != null ? _e : node.style;
      const styled = style !== node.style ? __spreadProps(__spreadValues({}, node), { style }) : node;
      if ((style == null ? void 0 : style.display) === "none") return w("constrained", { width: 0, height: 0 });
      const hasEvents = !!node.events && Object.keys(node.events).length > 0;
      if (hasEvents || node.key != null) {
        this.services.events.registerNode(elementId, styled, parentCtx.parentId);
        this.registered.add(elementId);
      }
      const facts = this.factsOf(node);
      const ctx = {
        engine: this,
        parentId: hasEvents || node.key != null ? elementId : parentCtx.parentId,
        ancestors: [facts, ...parentCtx.ancestors],
        path,
        elementId,
        formId: node.type === "form" || node.type === "NextjsForm" ? elementId : parentCtx.formId
      };
      const childNodes = styled.children.map((child) => {
        var _a2;
        if (child.type === "#text") return child;
        const childStyle2 = (_a2 = this.resolveStyle(child, ctx.ancestors)) != null ? _a2 : child.style;
        return childStyle2 !== child.style ? __spreadProps(__spreadValues({}, child), { style: childStyle2 }) : child;
      });
      const withChildren = __spreadProps(__spreadValues({}, styled), { children: childNodes });
      const children = childNodes.map((child, i) => this.renderNode(child, ctx, i));
      let result = builder(withChildren, children, __spreadProps(__spreadValues({}, ctx), { parentId: ctx.parentId, elementId }));
      if (hasEvents) {
        result = this.wrapEvents(withChildren, elementId, result);
      }
      if (node.key != null && result.k == null) result = __spreadProps(__spreadValues({}, result), { k: node.key });
      return result;
    }
    /** `EventEnabledWidget`: a gesture region recognising what the node listens for. */
    wrapEvents(node, elementId, child) {
      var _a, _b, _c, _d, _e;
      const gestures = /* @__PURE__ */ new Set();
      for (const name of Object.keys((_a = node.events) != null ? _a : {})) {
        const g = EVENT_GESTURES[name.toLowerCase()];
        if (g) gestures.add(g);
        if (g === "key") gestures.add("focus");
      }
      if (gestures.size === 0) return child;
      const listensTap = gestures.has("tap");
      return w(
        "gesture",
        {
          gestures: [...gestures],
          cursor: listensTap ? (_c = (_b = node.style) == null ? void 0 : _b.cursor) != null ? _c : "pointer" : (_e = (_d = node.style) == null ? void 0 : _d.cursor) != null ? _e : null,
          focusable: gestures.has("key") || gestures.has("focus"),
          onEvent: (event) => this.handleGesture(elementId, node, event)
        },
        child,
        `ev:${elementId}`
      );
    }
    /** Translate a platform gesture into Elpian events and dispatch them. */
    handleGesture(elementId, node, event) {
      var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j, _k, _l, _m, _n, _o, _p, _q, _r, _s, _t, _u, _v, _w, _x, _y, _z;
      const events = (_a = node.events) != null ? _a : {};
      const has = (name) => Object.prototype.hasOwnProperty.call(events, name);
      const pos = event.x != null ? { x: event.x, y: (_b = event.y) != null ? _b : 0 } : void 0;
      const local = event.localX != null ? { x: event.localX, y: (_c = event.localY) != null ? _c : 0 } : pos;
      const dispatch = (type, extra = {}) => this.services.events.dispatchEvent(makeEvent(type, eventTypeFor(type), elementId, extra), elementId);
      switch (event.type) {
        case "tap":
          if (has("tap")) dispatch("tap", pos ? { position: pos, localPosition: local } : {});
          if (has("click")) dispatch("click", pos ? { position: pos, localPosition: local } : {});
          return;
        case "doubletap":
          dispatch(has("dblclick") && !has("doubletap") ? "dblclick" : "doubletap");
          return;
        case "longpress":
          dispatch(has("contextmenu") && !has("longpress") ? "contextmenu" : "longpress", pos ? { position: pos, localPosition: local } : {});
          return;
        case "tapdown":
        case "tapup":
          dispatch(event.type, { position: pos != null ? pos : { x: 0, y: 0 }, localPosition: local != null ? local : { x: 0, y: 0 } });
          return;
        case "tapcancel":
          dispatch("tapcancel");
          return;
        case "dragstart":
          if (has("dragstart")) dispatch("dragstart", { position: pos != null ? pos : { x: 0, y: 0 }, localPosition: local != null ? local : { x: 0, y: 0 } });
          return;
        case "drag":
          if (has("drag")) dispatch("drag", { position: pos != null ? pos : { x: 0, y: 0 }, localPosition: local != null ? local : { x: 0, y: 0 }, delta: { x: (_d = event.dx) != null ? _d : 0, y: (_e = event.dy) != null ? _e : 0 } });
          return;
        case "dragend":
          if (has("dragend")) dispatch("dragend", { position: { x: 0, y: 0 }, localPosition: { x: 0, y: 0 } });
          return;
        case "swipe": {
          const dir = (_j = event.direction) != null ? _j : Math.abs((_f = event.vx) != null ? _f : 0) > Math.abs((_g = event.vy) != null ? _g : 0) ? ((_h = event.vx) != null ? _h : 0) < 0 ? "left" : "right" : ((_i = event.vy) != null ? _i : 0) < 0 ? "up" : "down";
          const name = `swipe${dir}`;
          if (has(name)) dispatch(name, { velocity: { x: (_k = event.vx) != null ? _k : 0, y: (_l = event.vy) != null ? _l : 0 }, scale: 1, rotation: 0, focalPoint: { x: 0, y: 0 } });
          return;
        }
        case "pointerdown":
        case "pointerup":
        case "pointermove":
        case "pointercancel":
        case "pointerenter":
        case "pointerexit":
        case "pointerhover": {
          const alias = event.type === "pointerenter" && !has("pointerenter") && has("mouseenter") ? "mouseenter" : event.type === "pointerexit" && !has("pointerexit") && has("mouseleave") ? "mouseleave" : event.type;
          if (has(alias)) {
            dispatch(alias, {
              position: pos != null ? pos : { x: 0, y: 0 },
              localPosition: local != null ? local : { x: 0, y: 0 },
              delta: { x: (_m = event.dx) != null ? _m : 0, y: (_n = event.dy) != null ? _n : 0 },
              buttons: (_o = event.buttons) != null ? _o : 0,
              pressure: (_p = event.pressure) != null ? _p : 1,
              pointerId: (_q = event.pointerId) != null ? _q : 0
            });
          }
          return;
        }
        case "keydown":
        case "keyup":
        case "keypress":
          if (has(event.type)) {
            dispatch(event.type, {
              key: (_r = event.key) != null ? _r : "",
              keyCode: (_s = event.keyCode) != null ? _s : 0,
              altKey: !!event.altKey,
              ctrlKey: !!event.ctrlKey,
              shiftKey: !!event.shiftKey,
              metaKey: !!event.metaKey
            });
          }
          return;
        case "focus":
        case "blur":
          if (has(event.type)) dispatch(event.type);
          return;
        case "scalestart":
        case "scaleupdate":
        case "scaleend": {
          const suffix = event.type.substring(5);
          const extra = { velocity: { x: (_t = event.vx) != null ? _t : 0, y: (_u = event.vy) != null ? _u : 0 }, scale: (_v = event.scale) != null ? _v : 1, rotation: (_w = event.rotation) != null ? _w : 0, focalPoint: pos != null ? pos : { x: 0, y: 0 } };
          for (const prefix of ["scale", "pinch", "rotate"]) if (has(prefix + suffix)) dispatch(prefix + suffix, extra);
          return;
        }
        case "scroll":
          if (has("scroll")) dispatch("scroll", { data: { scrollX: (_x = event.scrollX) != null ? _x : 0, scrollY: (_y = event.scrollY) != null ? _y : 0 } });
          return;
        default:
          if (has(event.type)) dispatch(event.type, { value: event.value, data: (_z = event.data) != null ? _z : {} });
      }
    }
    /** `<label for>`: focus the control of the element with HTML id [id]. */
    focusElement(id2) {
      var _a, _b;
      (_b = (_a = this.host).focus) == null ? void 0 : _b.call(_a, id2);
    }
    /** A named form control reports its current value through [read]. */
    registerFormField(formId, name, read) {
      if (!formId || !name) return;
      let fields = this.formFields.get(formId);
      if (!fields) this.formFields.set(formId, fields = /* @__PURE__ */ new Map());
      fields.set(name, read);
    }
    formValues(formId) {
      var _a;
      const out = {};
      for (const [name, read] of (_a = this.formFields.get(formId)) != null ? _a : []) out[name] = read();
      return out;
    }
    /** Submit [formId]: the form element receives `submit` with its field values. */
    submitForm(formId) {
      const values = this.formValues(formId);
      this.services.events.dispatchEvent(makeEvent("submit", "submit", formId, { data: { values }, value: values }), formId);
    }
    dispatchTo(elementId, type, data) {
      this.services.events.dispatchEvent(makeEvent(type, eventTypeFor(type), elementId, { data }), elementId);
    }
    /** A Draggable moved: update DragTarget enter / leave / over. */
    dragOver(sourceId, e, data) {
      var _a, _b, _c, _d;
      const target = e.x != null ? (_d = (_c = (_b = this.host).hitTestDragTarget) == null ? void 0 : _c.call(_b, e.x, (_a = e.y) != null ? _a : 0)) != null ? _d : null : null;
      if (target !== this.dragTarget) {
        if (this.dragTarget) this.dispatchTo(this.dragTarget, "dragleave", { data, source: sourceId });
        if (target) this.dispatchTo(target, "dragenter", { data, source: sourceId });
        this.dragTarget = target;
      }
      if (target) this.dispatchTo(target, "dragover", { data, source: sourceId, x: e.x, y: e.y });
      this.dispatchTo(sourceId, "drag", { x: e.x, y: e.y });
    }
    /** A Draggable was released: the target under the pointer accepts it. */
    dropAt(sourceId, e, data) {
      var _a, _b, _c, _d;
      const target = e.x != null ? (_d = (_c = (_b = this.host).hitTestDragTarget) == null ? void 0 : _c.call(_b, e.x, (_a = e.y) != null ? _a : 0)) != null ? _d : null : null;
      if (target) {
        this.dispatchTo(target, "drop", { data, source: sourceId });
        this.dispatchTo(target, "accept", { data, source: sourceId });
      }
      this.dispatchTo(sourceId, "dragend", { accepted: target != null, target });
      if (this.dragTarget && this.dragTarget !== target) this.dispatchTo(this.dragTarget, "dragleave", { data, source: sourceId });
      this.dragTarget = null;
    }
    // ---------------------------------------------------------------------------
    // Scene3D
    // ---------------------------------------------------------------------------
    /** The scene controller of a Scene3D element, building / replacing its DSL scene. */
    sceneFor(elementId, sceneJson) {
      var _a, _b, _c;
      this.seen.add(elementId);
      let entry = this.scenes.get(elementId);
      if (!entry) {
        const binding2 = (_c = (_b = (_a = this.host).godotBinding) == null ? void 0 : _b.call(_a)) != null ? _c : new MockGodotBinding();
        entry = { controller: new GodotSceneController(binding2), sceneKey: null, attached: false };
        this.scenes.set(elementId, entry);
      }
      const key = sceneJson ? stableKey(sceneJson) : null;
      if (sceneJson && key !== entry.sceneKey) {
        if (entry.sceneKey == null) {
          entry.controller.adopt(new SceneDsl(entry.controller.godot).build(sceneJson));
        } else {
          entry.controller.replaceScene(sceneJson);
        }
        entry.sceneKey = key;
      }
      if (!entry.attached) {
        entry.attached = true;
        void entry.controller.godot.attachSurface();
      }
      return entry.controller;
    }
    /** The Scene3D controllers currently alive, by element id. */
    get sceneControllers() {
      return this.scenes;
    }
    // ---------------------------------------------------------------------------
    // Documents
    // ---------------------------------------------------------------------------
    /**
     * `wrapAsDocument`: a screen root scrolls vertically like `<body>` unless it
     * is a viewport-locked stage (`position: fixed`, `height: 100vh|100%`, or
     * it embeds a Scene3D).
     */
    wrapAsDocument(rendered, root) {
      if (!root || this.isViewportLockedRoot(root)) return rendered;
      return w("scroll", { axis: "vertical", stretchCross: true, fillViewport: true }, rendered);
    }
    isViewportLockedRoot(root) {
      var _a, _b, _c, _d, _e;
      const props = isMap(root.props) ? root.props : {};
      const className = (_a = root.className) != null ? _a : props.className;
      const classes = typeof className === "string" ? className.split(" ") : Array.isArray(className) ? className.map(String) : null;
      const inline = (_b = root.style) != null ? _b : props.style;
      const raw = this.services.stylesheets.getComputedStyleMap(
        { tagName: String((_c = root.type) != null ? _c : "div"), id: (_d = root.key) != null ? _d : null, classes, attributes: props },
        { inlineStyles: isMap(inline) ? inline : null }
      );
      if (String((_e = raw.position) != null ? _e : "") === "fixed") return true;
      const h = raw.height != null ? String(raw.height).trim() : null;
      if (h && (h.includes("vh") || h === "100%")) return true;
      return containsScene(root, 0);
    }
    dispose() {
      for (const entry of this.scenes.values()) entry.controller.dispose();
      this.scenes.clear();
      this.state.clear();
    }
  };
  function collectMaps(root) {
    const out = /* @__PURE__ */ new Map();
    const visit = (n) => {
      if (n.type === "map" && typeof n.props.name === "string") {
        const areas = [];
        const collect = (c) => {
          if (c.type === "area") areas.push(c);
          c.children.forEach(collect);
        };
        n.children.forEach(collect);
        out.set(n.props.name, areas);
      }
      n.children.forEach(visit);
    };
    visit(root);
    return out;
  }
  function collectDatalists(root) {
    const out = /* @__PURE__ */ new Map();
    const visit = (n) => {
      var _a, _b;
      if (n.type === "datalist" && n.props.id != null) {
        const values = [];
        for (const c of n.children) {
          if (c.type !== "option") continue;
          const v = (_b = (_a = c.props.value) != null ? _a : c.props.text) != null ? _b : c.children.map((t) => {
            var _a2;
            return (_a2 = t.props.text) != null ? _a2 : "";
          }).join("");
          if (v != null && String(v) !== "") values.push(String(v));
        }
        out.set(String(n.props.id), values);
      }
      n.children.forEach(visit);
    };
    visit(root);
    return out;
  }
  function containsScene(node, depth) {
    if (depth > 6) return false;
    if (node.type === "Scene3D" || node.type === "scene3d") return true;
    if (Array.isArray(node.children)) {
      for (const c of node.children) if (isMap(c) && containsScene(c, depth + 1)) return true;
    }
    return false;
  }

  // core/src/render/view.ts
  var ROOT_VIEW_ID = 0;

  // core/src/render/compositor.ts
  var ONE_SHOT = /* @__PURE__ */ new Set(["commands", "appendCommands", "scrollTo"]);
  function round(v) {
    return Math.round(v * 1e3) / 1e3;
  }
  var Compositor = class {
    constructor(owner) {
      this.owner = owner;
      this.views = /* @__PURE__ */ new Map();
      this.childLists = /* @__PURE__ */ new Map();
      this.pendingCommands = [];
    }
    objectFor(viewId) {
      var _a;
      return (_a = this.views.get(viewId)) == null ? void 0 : _a.ro;
    }
    hasView(viewId) {
      return this.views.has(viewId);
    }
    /** Queue an imperative command for a view (focus, scroll, play…). */
    command(viewId, name, args) {
      this.pendingCommands.push({ op: "command", id: viewId, name, args });
      this.owner.requestVisualUpdate();
    }
    /** Forget the last-sent value of [keys] so the next frame re-sends them (controlled inputs). */
    invalidateProps(viewId, keys) {
      const record = this.views.get(viewId);
      if (!record) return;
      for (const k of keys) record.props.delete(k);
      this.owner.requestVisualUpdate();
    }
    /** The absolute frame of a view (sum of ancestor frames). */
    globalFrame(ro) {
      let x = 0;
      let y = 0;
      let node = ro;
      while (node) {
        x += node.offset.x;
        y += node.offset.y;
        const parent = node.parent;
        if (parent && parent.viewKind() === "scroll") {
          const scroll = parent.scrollOffset;
          if (scroll) {
            x -= scroll.x;
            y -= scroll.y;
          }
        }
        node = parent;
      }
      return { x, y, width: ro.size.width, height: ro.size.height };
    }
    composite(root) {
      var _a;
      const placements = [];
      const lists = /* @__PURE__ */ new Map();
      const walk = (ro, parentView, ox, oy) => {
        const x = ox + ro.offset.x;
        const y = oy + ro.offset.y;
        const kind = ro.viewKind();
        if (kind) {
          const previous = ro.viewId != null ? this.views.get(ro.viewId) : void 0;
          if (ro.viewId == null || previous && (previous.kind !== kind || previous.parent !== parentView)) {
            ro.viewId = this.owner.allocateViewId();
          }
          const id2 = ro.viewId;
          const props = __spreadValues({ frame: [round(x), round(y), round(ro.size.width), round(ro.size.height)] }, ro.viewProps());
          placements.push({ id: id2, parent: parentView, kind, ro, props });
          let list2 = lists.get(parentView);
          if (!list2) lists.set(parentView, list2 = []);
          list2.push(id2);
          const origin = ro.childOriginInView();
          for (const child of ro.children) if (ro.paintsChild(child)) walk(child, id2, origin.x, origin.y);
        } else {
          for (const child of ro.children) if (ro.paintsChild(child)) walk(child, parentView, x, y);
        }
      };
      walk(root, ROOT_VIEW_ID, 0, 0);
      const ops = [];
      const nextIds = new Set(placements.map((p) => p.id));
      for (const [id2, record] of this.views) {
        if (nextIds.has(id2)) continue;
        const parentGone = record.parent !== ROOT_VIEW_ID && !nextIds.has(record.parent) && this.views.has(record.parent);
        if (!parentGone) ops.push({ op: "remove", id: id2 });
      }
      for (const id2 of [...this.views.keys()]) if (!nextIds.has(id2)) this.views.delete(id2);
      const reordered = /* @__PURE__ */ new Set();
      for (const [parent, list2] of lists) {
        const prev = this.childLists.get(parent);
        if (!prev || prev.length !== list2.length || prev.some((id2, i) => id2 !== list2[i])) reordered.add(parent);
      }
      const indexOf = /* @__PURE__ */ new Map();
      for (const list2 of lists.values()) list2.forEach((id2, i) => indexOf.set(id2, i));
      for (const p of placements) {
        const index = (_a = indexOf.get(p.id)) != null ? _a : 0;
        const existing = this.views.get(p.id);
        if (!existing) {
          const record = { kind: p.kind, parent: p.parent, ro: p.ro, props: /* @__PURE__ */ new Map() };
          for (const [k, v] of Object.entries(p.props)) if (v !== void 0 && !ONE_SHOT.has(k)) record.props.set(k, JSON.stringify(v));
          this.views.set(p.id, record);
          ops.push({ op: "create", id: p.id, kind: p.kind, parent: p.parent, index, props: stripUndefined(p.props) });
          continue;
        }
        existing.ro = p.ro;
        if (reordered.has(p.parent)) {
          ops.push({ op: "move", id: p.id, parent: p.parent, index });
          existing.parent = p.parent;
        }
        const changed = {};
        let any = false;
        const seenKeys = /* @__PURE__ */ new Set();
        for (const [k, v] of Object.entries(p.props)) {
          if (v === void 0) continue;
          if (ONE_SHOT.has(k)) {
            if (v !== null) {
              changed[k] = v;
              any = true;
            }
            continue;
          }
          seenKeys.add(k);
          const json = JSON.stringify(v);
          if (existing.props.get(k) !== json) {
            existing.props.set(k, json);
            changed[k] = v;
            any = true;
          }
        }
        for (const k of [...existing.props.keys()]) {
          if (!seenKeys.has(k)) {
            existing.props.delete(k);
            changed[k] = null;
            any = true;
          }
        }
        if (any) ops.push({ op: "update", id: p.id, props: changed });
      }
      this.childLists = lists;
      if (this.pendingCommands.length) {
        for (const cmd of this.pendingCommands) if (this.views.has(cmd.id)) ops.push(cmd);
        this.pendingCommands = [];
      }
      return ops;
    }
    /** Remove every view (unmount). */
    clear() {
      const ops = [];
      for (const [id2, record] of this.views) {
        if (record.parent === ROOT_VIEW_ID) ops.push({ op: "remove", id: id2 });
      }
      this.views.clear();
      this.childLists.clear();
      this.pendingCommands = [];
      return ops;
    }
    get viewCount() {
      return this.views.size;
    }
  };
  function stripUndefined(props) {
    const out = {};
    for (const [k, v] of Object.entries(props)) if (v !== void 0) out[k] = v;
    return out;
  }

  // core/src/render/owner.ts
  var RenderOwner = class {
    constructor(surface, platform2, hooks = {}) {
      this.surface = surface;
      this.platform = platform2;
      this.hooks = hooks;
      this.root = null;
      this.tickers = /* @__PURE__ */ new Set();
      this.frameHandle = null;
      this.dirtyPaint = /* @__PURE__ */ new Set();
      this.needsFrame = false;
      this.disposed = false;
      this.textCache = /* @__PURE__ */ new Map();
      this.nextViewId = 1;
      /** When set, the root lays out with unbounded height (document mode measures content). */
      this.rootConstraints = null;
      /** Monotonic frame clock (ms) as of the last tick. */
      this.frameTime = 0;
      /** Accessibility text scale. */
      this.textScale = 1;
      // ---------------------------------------------------------------------------
      // Hero flights
      // ---------------------------------------------------------------------------
      this.heroes = /* @__PURE__ */ new Map();
      // ---------------------------------------------------------------------------
      // Images
      // ---------------------------------------------------------------------------
      this.imageSizes = /* @__PURE__ */ new Map();
      this.compositor = new Compositor(this);
    }
    allocateViewId() {
      return this.nextViewId++;
    }
    // ---------------------------------------------------------------------------
    // Scheduling
    // ---------------------------------------------------------------------------
    requestVisualUpdate() {
      if (this.disposed) return;
      this.needsFrame = true;
      if (this.frameHandle != null) return;
      this.frameHandle = this.platform.requestFrame((t) => {
        this.frameHandle = null;
        this.flush(t);
      });
    }
    markPaintDirty(ro) {
      this.dirtyPaint.add(ro);
      this.requestVisualUpdate();
    }
    addTicker(ticker) {
      this.tickers.add(ticker);
      this.requestVisualUpdate();
    }
    removeTicker(ticker) {
      this.tickers.delete(ticker);
    }
    get hasActiveTickers() {
      return this.tickers.size > 0;
    }
    /** Run a frame now: tick animations, lay out, composite and commit. */
    flush(timeMs = this.platform.now()) {
      var _a, _b, _c;
      if (this.disposed) return [];
      this.frameTime = timeMs;
      this.needsFrame = false;
      for (const ticker of [...this.tickers]) {
        let alive = false;
        try {
          alive = ticker.tick(timeMs);
        } catch (e) {
          this.platform.log("error", `Elpian animation tick failed: ${e}`);
        }
        if (!alive) this.tickers.delete(ticker);
      }
      const root = this.root;
      let ops = [];
      if (root) {
        const vp = this.platform.viewport(this.surface);
        const constraints = (_a = this.rootConstraints) != null ? _a : tight(vp.width, vp.height);
        root.layout(constraints);
        this.updateHeroes(root);
        ops = this.compositor.composite(root);
      } else {
        ops = this.compositor.clear();
      }
      this.dirtyPaint.clear();
      if (ops.length) this.platform.commit(this.surface, ops);
      (_c = (_b = this.hooks).onFrameCommitted) == null ? void 0 : _c.call(_b, ops.length);
      if (this.tickers.size > 0 || this.needsFrame) this.requestVisualUpdate();
      return ops;
    }
    /** A hero whose tag now belongs to a different object flies from the old rect. */
    updateHeroes(root) {
      const next = /* @__PURE__ */ new Map();
      root.visit((ro) => {
        if (ro.type !== "hero" || ro.props.tag == null) return;
        next.set(String(ro.props.tag), { ro, rect: this.compositor.globalFrame(ro) });
      });
      for (const [tag, entry] of next) {
        const prev = this.heroes.get(tag);
        if (prev && prev.ro !== entry.ro && typeof entry.ro.flyFrom === "function") {
          entry.ro.flyFrom(prev.rect, this);
        }
      }
      if (next.size || this.heroes.size) this.heroes = next;
    }
    // ---------------------------------------------------------------------------
    // Measurement
    // ---------------------------------------------------------------------------
    measureText(spec, maxWidth) {
      const width = Number.isFinite(maxWidth) ? Math.max(0, Math.round(maxWidth * 100) / 100) : INF;
      const key = width + "|" + stableKey(spec);
      const hit = this.textCache.get(key);
      if (hit) return hit;
      const metrics = this.platform.measureText(spec, width);
      if (this.textCache.size > 4e3) this.textCache.clear();
      this.textCache.set(key, metrics);
      return metrics;
    }
    /** Fonts or the viewport changed: everything must be re-measured. */
    invalidateMeasurements() {
      var _a;
      this.textCache.clear();
      (_a = this.root) == null ? void 0 : _a.visit((ro) => {
        ro.needsLayout = true;
      });
      this.requestVisualUpdate();
    }
    /** Natural size of [src], or null while unknown (a load is requested). */
    imageSize(src) {
      var _a, _b, _c, _d, _e;
      const known = this.imageSizes.get(src);
      if (known && known !== "pending" && known !== "error") return known;
      if (known === void 0) {
        const direct = (_c = (_b = (_a = this.platform).imageSize) == null ? void 0 : _b.call(_a, src)) != null ? _c : null;
        if (direct) {
          this.imageSizes.set(src, direct);
          return direct;
        }
        this.imageSizes.set(src, "pending");
        (_e = (_d = this.platform).preloadImage) == null ? void 0 : _e.call(_d, src);
      }
      return null;
    }
    /** The platform finished decoding [src]; images showing it re-lay out. */
    imageLoaded(src, width, height) {
      var _a;
      if (width > 0 && height > 0) this.imageSizes.set(src, { width, height });
      else this.imageSizes.set(src, "error");
      (_a = this.root) == null ? void 0 : _a.visit((ro) => {
        if (ro.type === "image" && ro.props.src === src) ro.markNeedsLayout();
      });
    }
    // ---------------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------------
    /** Route a platform event to the render object owning [event.id]. */
    dispatchViewEvent(event) {
      const ro = this.compositor.objectFor(event.id);
      if (!ro) return;
      ro.handleViewEvent(event);
    }
    dispose() {
      var _a;
      if (this.disposed) return;
      if (this.frameHandle != null) this.platform.cancelFrame(this.frameHandle);
      this.frameHandle = null;
      this.tickers.clear();
      const ops = this.compositor.clear();
      if (ops.length) this.platform.commit(this.surface, ops);
      (_a = this.root) == null ? void 0 : _a.detach();
      this.root = null;
      this.disposed = true;
    }
    get isDisposed() {
      return this.disposed;
    }
  };

  // core/src/animation/curves.ts
  var CUBIC_ERROR_BOUND = 1e-3;
  function evaluateCubic(a, b, m) {
    return 3 * a * (1 - m) * (1 - m) * m + 3 * b * (1 - m) * m * m + m * m * m;
  }
  function cubic(a, b, c, d) {
    return (t) => {
      if (t <= 0) return 0;
      if (t >= 1) return 1;
      let start = 0;
      let end = 1;
      for (let i = 0; i < 64; i++) {
        const mid = (start + end) / 2;
        const estimate = evaluateCubic(a, c, mid);
        if (Math.abs(t - estimate) < CUBIC_ERROR_BOUND) return evaluateCubic(b, d, mid);
        if (estimate < t) start = mid;
        else end = mid;
      }
      return evaluateCubic(b, d, (start + end) / 2);
    };
  }
  function bounce(t) {
    if (t < 1 / 2.75) return 7.5625 * t * t;
    if (t < 2 / 2.75) {
      t -= 1.5 / 2.75;
      return 7.5625 * t * t + 0.75;
    }
    if (t < 2.5 / 2.75) {
      t -= 2.25 / 2.75;
      return 7.5625 * t * t + 0.9375;
    }
    t -= 2.625 / 2.75;
    return 7.5625 * t * t + 0.984375;
  }
  function elasticIn(period = 0.4) {
    return (t) => {
      if (t <= 0 || t >= 1) return t <= 0 ? 0 : 1;
      const s = period / 4;
      t = t - 1;
      return -Math.pow(2, 10 * t) * Math.sin((t - s) * (Math.PI * 2) / period);
    };
  }
  function elasticOut(period = 0.4) {
    return (t) => {
      if (t <= 0 || t >= 1) return t <= 0 ? 0 : 1;
      const s = period / 4;
      return Math.pow(2, -10 * t) * Math.sin((t - s) * (Math.PI * 2) / period) + 1;
    };
  }
  function elasticInOut(period = 0.4) {
    return (t) => {
      if (t <= 0 || t >= 1) return t <= 0 ? 0 : 1;
      const s = period / 4;
      t = 2 * t - 1;
      if (t < 0) return -0.5 * Math.pow(2, 10 * t) * Math.sin((t - s) * (Math.PI * 2) / period);
      return Math.pow(2, -10 * t) * Math.sin((t - s) * (Math.PI * 2) / period) * 0.5 + 1;
    };
  }
  function interval(begin, end, curve = Curves.linear) {
    return (t) => {
      if (end <= begin) return t >= end ? 1 : 0;
      const local = Math.max(0, Math.min(1, (t - begin) / (end - begin)));
      if (local === 0 || local === 1) return local;
      return curve(local);
    };
  }
  function steps(count, position = "end") {
    const n = Math.max(1, count);
    return (t) => {
      if (t >= 1) return 1;
      let step = Math.floor(t * n);
      if (position === "start" || position === "both") step += 1;
      const jumps = position === "both" ? n + 1 : position === "none" ? n - 1 : n;
      return Math.max(0, Math.min(1, step / Math.max(1, jumps)));
    };
  }
  var Curves = {
    linear: (t) => t,
    decelerate: (t) => {
      t = 1 - t;
      return 1 - t * t;
    },
    fastLinearToSlowEaseIn: cubic(0.18, 1, 0.04, 1),
    ease: cubic(0.25, 0.1, 0.25, 1),
    easeIn: cubic(0.42, 0, 1, 1),
    easeInToLinear: cubic(0.67, 0.03, 0.65, 0.09),
    easeInSine: cubic(0.47, 0, 0.745, 0.715),
    easeInQuad: cubic(0.55, 0.085, 0.68, 0.53),
    easeInCubic: cubic(0.55, 0.055, 0.675, 0.19),
    easeInQuart: cubic(0.895, 0.03, 0.685, 0.22),
    easeInQuint: cubic(0.755, 0.05, 0.855, 0.06),
    easeInExpo: cubic(0.95, 0.05, 0.795, 0.035),
    easeInCirc: cubic(0.6, 0.04, 0.98, 0.335),
    easeInBack: cubic(0.6, -0.28, 0.735, 0.045),
    easeOut: cubic(0, 0, 0.58, 1),
    linearToEaseOut: cubic(0.35, 0.91, 0.33, 0.97),
    easeOutSine: cubic(0.39, 0.575, 0.565, 1),
    easeOutQuad: cubic(0.25, 0.46, 0.45, 0.94),
    easeOutCubic: cubic(0.215, 0.61, 0.355, 1),
    easeOutQuart: cubic(0.165, 0.84, 0.44, 1),
    easeOutQuint: cubic(0.23, 1, 0.32, 1),
    easeOutExpo: cubic(0.19, 1, 0.22, 1),
    easeOutCirc: cubic(0.075, 0.82, 0.165, 1),
    easeOutBack: cubic(0.175, 0.885, 0.32, 1.275),
    easeInOut: cubic(0.42, 0, 0.58, 1),
    easeInOutSine: cubic(0.445, 0.05, 0.55, 0.95),
    easeInOutQuad: cubic(0.455, 0.03, 0.515, 0.955),
    easeInOutCubic: cubic(0.645, 0.045, 0.355, 1),
    easeInOutQuart: cubic(0.77, 0, 0.175, 1),
    easeInOutQuint: cubic(0.86, 0, 0.07, 1),
    easeInOutExpo: cubic(1, 0, 0, 1),
    easeInOutCirc: cubic(0.785, 0.135, 0.15, 0.86),
    easeInOutBack: cubic(0.68, -0.55, 0.265, 1.55),
    fastOutSlowIn: cubic(0.4, 0, 0.2, 1),
    slowMiddle: cubic(0.15, 0.85, 0.85, 0.15),
    bounceIn: (t) => 1 - bounce(1 - t),
    bounceOut: (t) => bounce(t),
    bounceInOut: (t) => t < 0.5 ? (1 - bounce(1 - t * 2)) * 0.5 : bounce(t * 2 - 1) * 0.5 + 0.5,
    elasticIn: elasticIn(0.4),
    elasticOut: elasticOut(0.4),
    elasticInOut: elasticInOut(0.4)
  };
  var byName = {
    linear: Curves.linear,
    ease: Curves.ease,
    easein: Curves.easeIn,
    easeout: Curves.easeOut,
    easeinout: Curves.easeInOut,
    bounce: Curves.bounceIn,
    bouncein: Curves.bounceIn,
    bounceout: Curves.bounceOut,
    bounceinout: Curves.bounceInOut,
    elastic: Curves.elasticIn,
    elasticin: Curves.elasticIn,
    elasticout: Curves.elasticOut,
    elasticinout: Curves.elasticInOut,
    decelerate: Curves.decelerate,
    fastoutslowin: Curves.fastOutSlowIn,
    slowmiddle: Curves.slowMiddle,
    fastlineartosloweasein: Curves.fastLinearToSlowEaseIn,
    easeintolinear: Curves.easeInToLinear,
    lineartoeaseout: Curves.linearToEaseOut,
    easeinsine: Curves.easeInSine,
    easeinquad: Curves.easeInQuad,
    easeincubic: Curves.easeInCubic,
    easeinquart: Curves.easeInQuart,
    easeinquint: Curves.easeInQuint,
    easeinexpo: Curves.easeInExpo,
    easeincirc: Curves.easeInCirc,
    easeinback: Curves.easeInBack,
    easeoutsine: Curves.easeOutSine,
    easeoutquad: Curves.easeOutQuad,
    easeoutcubic: Curves.easeOutCubic,
    easeoutquart: Curves.easeOutQuart,
    easeoutquint: Curves.easeOutQuint,
    easeoutexpo: Curves.easeOutExpo,
    easeoutcirc: Curves.easeOutCirc,
    easeoutback: Curves.easeOutBack,
    easeinoutsine: Curves.easeInOutSine,
    easeinoutquad: Curves.easeInOutQuad,
    easeinoutcubic: Curves.easeInOutCubic,
    easeinoutquart: Curves.easeInOutQuart,
    easeinoutquint: Curves.easeInOutQuint,
    easeinoutexpo: Curves.easeInOutExpo,
    easeinoutcirc: Curves.easeInOutCirc,
    easeinoutback: Curves.easeInOutBack,
    stepstart: steps(1, "start"),
    stepend: steps(1, "end")
  };
  function curveByName(name, fallback = Curves.linear) {
    var _a, _b;
    if (!name) return fallback;
    const raw = name.trim().toLowerCase();
    const bez = /^cubic-bezier\(\s*([-\d.]+)\s*,\s*([-\d.]+)\s*,\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\)$/.exec(raw);
    if (bez) return cubic(parseFloat(bez[1]), parseFloat(bez[2]), parseFloat(bez[3]), parseFloat(bez[4]));
    const st = /^steps\(\s*(\d+)\s*(?:,\s*([a-z-]+))?\s*\)$/.exec(raw);
    if (st) {
      const pos = (_a = st[2]) != null ? _a : "end";
      const position = pos === "start" || pos === "jump-start" ? "start" : pos === "jump-both" ? "both" : pos === "jump-none" ? "none" : "end";
      return steps(Number.parseInt(st[1], 10), position);
    }
    return (_b = byName[raw.replace(/[-_\s]/g, "")]) != null ? _b : fallback;
  }

  // core/src/animation/controller.ts
  var AnimationController = class {
    constructor(duration, initial = 0, reverseDuration = null) {
      this.duration = duration;
      this.reverseDuration = reverseDuration;
      this.status = "dismissed";
      this.owner = null;
      this.from = 0;
      this.to = 1;
      this.startTime = null;
      this.running = false;
      this.repeat = false;
      this.reverseOnRepeat = false;
      this.completer = null;
      this.listeners = /* @__PURE__ */ new Set();
      this.statusListeners = /* @__PURE__ */ new Set();
      this.value = initial;
    }
    attach(owner) {
      this.owner = owner;
      if (this.running) owner.addTicker(this);
    }
    detach() {
      var _a;
      (_a = this.owner) == null ? void 0 : _a.removeTicker(this);
      this.owner = null;
    }
    addListener(fn) {
      this.listeners.add(fn);
    }
    removeListener(fn) {
      this.listeners.delete(fn);
    }
    addStatusListener(fn) {
      this.statusListeners.add(fn);
    }
    setStatus(s) {
      if (this.status === s) return;
      this.status = s;
      for (const l of [...this.statusListeners]) l(s);
    }
    get isAnimating() {
      return this.running;
    }
    start(target) {
      var _a;
      this.from = this.value;
      this.to = target;
      this.startTime = null;
      this.running = true;
      this.setStatus(target >= this.from ? "forward" : "reverse");
      (_a = this.owner) == null ? void 0 : _a.addTicker(this);
      return new Promise((resolve) => {
        var _a2;
        (_a2 = this.completer) == null ? void 0 : _a2.call(this);
        this.completer = resolve;
      });
    }
    forward(from) {
      this.repeat = false;
      if (from != null) this.value = from;
      return this.start(1);
    }
    reverse(from) {
      this.repeat = false;
      if (from != null) this.value = from;
      return this.start(0);
    }
    animateTo(target) {
      this.repeat = false;
      return this.start(target);
    }
    /** Loop 0→1 forever (ping-pong when [reverse]). */
    repeatAnimation(reverse = false) {
      var _a;
      this.repeat = true;
      this.reverseOnRepeat = reverse;
      this.from = this.value >= 1 ? 0 : this.value;
      this.to = 1;
      this.startTime = null;
      this.running = true;
      this.setStatus("forward");
      (_a = this.owner) == null ? void 0 : _a.addTicker(this);
    }
    stop() {
      var _a, _b;
      this.running = false;
      this.repeat = false;
      (_a = this.owner) == null ? void 0 : _a.removeTicker(this);
      (_b = this.completer) == null ? void 0 : _b.call(this);
      this.completer = null;
    }
    reset(value = 0) {
      this.stop();
      this.value = value;
      this.setStatus("dismissed");
      this.notify();
    }
    notify() {
      for (const l of [...this.listeners]) l();
    }
    tick(now) {
      var _a;
      if (!this.running) return false;
      if (this.startTime == null) this.startTime = now;
      const goingBack = this.to < this.from;
      const duration = Math.max(1, goingBack && this.reverseDuration != null ? this.reverseDuration : this.duration);
      const span = Math.abs(this.to - this.from);
      const total = duration * span;
      const elapsed = now - this.startTime;
      const t = total <= 0 ? 1 : Math.min(1, elapsed / total);
      this.value = this.from + (this.to - this.from) * t;
      this.notify();
      if (t < 1) return true;
      if (this.repeat) {
        if (this.reverseOnRepeat) {
          const next = this.to >= 1 ? 0 : 1;
          this.from = this.value;
          this.to = next;
          this.setStatus(next === 1 ? "forward" : "reverse");
        } else {
          this.from = 0;
          this.to = 1;
          this.value = 0;
        }
        this.startTime = now;
        return true;
      }
      this.running = false;
      this.setStatus(this.to >= 1 ? "completed" : "dismissed");
      (_a = this.completer) == null ? void 0 : _a.call(this);
      this.completer = null;
      return false;
    }
  };
  var lerpNumber = (a, b, t) => a + (b - a) * t;
  var ImplicitValue = class {
    constructor(value, lerp, equals, onChange) {
      this.value = value;
      this.lerp = lerp;
      this.equals = equals;
      this.onChange = onChange;
      this.controller = null;
      this.curve = Curves.linear;
      this.begin = value;
      this.end = value;
    }
    get current() {
      return this.value;
    }
    get target() {
      return this.end;
    }
    get animating() {
      var _a, _b;
      return (_b = (_a = this.controller) == null ? void 0 : _a.isAnimating) != null ? _b : false;
    }
    /** Set a new target; animate when [duration] > 0 and an owner is attached. */
    set(target, duration, curve, owner) {
      var _a;
      if (this.equals(target, this.end)) return;
      if (!duration || duration <= 0 || !owner) {
        (_a = this.controller) == null ? void 0 : _a.stop();
        this.begin = this.end = this.value = target;
        this.onChange();
        return;
      }
      this.begin = this.value;
      this.end = target;
      this.curve = curve != null ? curve : Curves.linear;
      if (!this.controller) {
        this.controller = new AnimationController(duration);
        this.controller.addListener(() => {
          const t = this.curve(this.controller.value);
          this.value = this.lerp(this.begin, this.end, t);
          this.onChange();
        });
      }
      this.controller.duration = duration;
      this.controller.attach(owner);
      void this.controller.forward(0);
    }
    /** Jump without animating (initial configuration). */
    jump(value) {
      var _a;
      (_a = this.controller) == null ? void 0 : _a.stop();
      this.begin = this.end = this.value = value;
    }
    dispose() {
      var _a, _b;
      (_a = this.controller) == null ? void 0 : _a.detach();
      (_b = this.controller) == null ? void 0 : _b.stop();
    }
  };

  // core/src/render/layout/basic.ts
  function alignOffset(alignment, outer, inner) {
    return {
      x: (outer.width - inner.width) / 2 * (1 + alignment.x),
      y: (outer.height - inner.height) / 2 * (1 + alignment.y)
    };
  }
  var RenderPadding = class extends RenderObject {
    /** Padding with percentage sides resolved against the incoming max width (CSS). */
    resolvedPadding(c) {
      var _a, _b;
      const p = (_a = this.props.padding) != null ? _a : { top: 0, right: 0, bottom: 0, left: 0 };
      const pct = (_b = this.props.percent) != null ? _b : null;
      if (!pct) return p;
      const basis = c && Number.isFinite(c.maxWidth) ? c.maxWidth : 0;
      const side2 = (k) => pct[k] ? pct[k].pct / 100 * basis : p[k];
      return { top: side2("top"), right: side2("right"), bottom: side2("bottom"), left: side2("left") };
    }
    performLayout(c) {
      const p = this.resolvedPadding(c);
      const h = Math.max(0, p.left + p.right);
      const v = Math.max(0, p.top + p.bottom);
      const child = this.child;
      if (!child) {
        this.size = constrain(c, { width: h, height: v });
        return;
      }
      child.layout(deflate(c, h, v));
      child.offset = { x: p.left, y: p.top };
      this.size = constrain(c, { width: child.size.width + h, height: child.size.height + v });
    }
    computeMinIntrinsicWidth(height) {
      var _a, _b;
      const p = this.resolvedPadding(null);
      const h = p.left + p.right;
      const v = p.top + p.bottom;
      return ((_b = (_a = this.child) == null ? void 0 : _a.minIntrinsicWidth(Math.max(0, height - v))) != null ? _b : 0) + h;
    }
    computeMaxIntrinsicWidth(height) {
      var _a, _b;
      const p = this.resolvedPadding(null);
      return ((_b = (_a = this.child) == null ? void 0 : _a.maxIntrinsicWidth(Math.max(0, height - p.top - p.bottom))) != null ? _b : 0) + p.left + p.right;
    }
    computeMinIntrinsicHeight(width) {
      var _a, _b;
      const p = this.resolvedPadding(null);
      return ((_b = (_a = this.child) == null ? void 0 : _a.minIntrinsicHeight(Math.max(0, width - p.left - p.right))) != null ? _b : 0) + p.top + p.bottom;
    }
    computeMaxIntrinsicHeight(width) {
      var _a, _b;
      const p = this.resolvedPadding(null);
      return ((_b = (_a = this.child) == null ? void 0 : _a.maxIntrinsicHeight(Math.max(0, width - p.left - p.right))) != null ? _b : 0) + p.top + p.bottom;
    }
  };
  var RenderConstrainedBox = class extends RenderObject {
    additional() {
      var _a, _b, _c, _d;
      const p = this.props;
      let c = {
        minWidth: (_a = p.minWidth) != null ? _a : 0,
        maxWidth: (_b = p.maxWidth) != null ? _b : INF,
        minHeight: (_c = p.minHeight) != null ? _c : 0,
        maxHeight: (_d = p.maxHeight) != null ? _d : INF
      };
      if (p.width != null) c = __spreadProps(__spreadValues({}, c), { minWidth: p.width, maxWidth: p.width });
      if (p.height != null) c = __spreadProps(__spreadValues({}, c), { minHeight: p.height, maxHeight: p.height });
      if (c.maxWidth < c.minWidth) c.maxWidth = c.minWidth;
      if (c.maxHeight < c.minHeight) c.maxHeight = c.minHeight;
      return c;
    }
    performLayout(c) {
      const inner = enforce(this.additional(), c);
      const child = this.child;
      if (child) {
        child.layout(inner);
        child.offset = { x: 0, y: 0 };
        this.size = __spreadValues({}, child.size);
      } else {
        this.size = constrain(inner, { width: 0, height: 0 });
      }
    }
    clampW(v) {
      const a = this.additional();
      return clampN(v, a.minWidth, a.maxWidth);
    }
    clampH(v) {
      const a = this.additional();
      return clampN(v, a.minHeight, a.maxHeight);
    }
    computeMinIntrinsicWidth(height) {
      var _a, _b;
      const a = this.additional();
      if (a.minWidth >= a.maxWidth && Number.isFinite(a.minWidth)) return a.minWidth;
      return this.clampW((_b = (_a = this.child) == null ? void 0 : _a.minIntrinsicWidth(height)) != null ? _b : 0);
    }
    computeMaxIntrinsicWidth(height) {
      var _a, _b;
      const a = this.additional();
      if (a.minWidth >= a.maxWidth && Number.isFinite(a.minWidth)) return a.minWidth;
      return this.clampW((_b = (_a = this.child) == null ? void 0 : _a.maxIntrinsicWidth(height)) != null ? _b : 0);
    }
    computeMinIntrinsicHeight(width) {
      var _a, _b;
      const a = this.additional();
      if (a.minHeight >= a.maxHeight && Number.isFinite(a.minHeight)) return a.minHeight;
      return this.clampH((_b = (_a = this.child) == null ? void 0 : _a.minIntrinsicHeight(width)) != null ? _b : 0);
    }
    computeMaxIntrinsicHeight(width) {
      var _a, _b;
      const a = this.additional();
      if (a.minHeight >= a.maxHeight && Number.isFinite(a.minHeight)) return a.minHeight;
      return this.clampH((_b = (_a = this.child) == null ? void 0 : _a.maxIntrinsicHeight(width)) != null ? _b : 0);
    }
  };
  var RenderAlign = class extends RenderObject {
    performLayout(c) {
      var _a, _b, _c;
      const alignment = (_a = this.props.alignment) != null ? _a : { x: 0, y: 0 };
      const wf = (_b = this.props.widthFactor) != null ? _b : null;
      const hf = (_c = this.props.heightFactor) != null ? _c : null;
      const shrinkW = wf != null || !Number.isFinite(c.maxWidth);
      const shrinkH = hf != null || !Number.isFinite(c.maxHeight);
      const child = this.child;
      if (child) {
        child.layout(loose(c));
        this.size = constrain(c, {
          width: shrinkW ? child.size.width * (wf != null ? wf : 1) : INF,
          height: shrinkH ? child.size.height * (hf != null ? hf : 1) : INF
        });
        child.offset = alignOffset(alignment, this.size, child.size);
      } else {
        this.size = constrain(c, { width: shrinkW ? 0 : INF, height: shrinkH ? 0 : INF });
      }
    }
    computeMinIntrinsicWidth(h) {
      var _a, _b, _c;
      return ((_b = (_a = this.child) == null ? void 0 : _a.minIntrinsicWidth(h)) != null ? _b : 0) * ((_c = this.props.widthFactor) != null ? _c : 1);
    }
    computeMaxIntrinsicWidth(h) {
      var _a, _b, _c;
      return ((_b = (_a = this.child) == null ? void 0 : _a.maxIntrinsicWidth(h)) != null ? _b : 0) * ((_c = this.props.widthFactor) != null ? _c : 1);
    }
    computeMinIntrinsicHeight(w2) {
      var _a, _b, _c;
      return ((_b = (_a = this.child) == null ? void 0 : _a.minIntrinsicHeight(w2)) != null ? _b : 0) * ((_c = this.props.heightFactor) != null ? _c : 1);
    }
    computeMaxIntrinsicHeight(w2) {
      var _a, _b, _c;
      return ((_b = (_a = this.child) == null ? void 0 : _a.maxIntrinsicHeight(w2)) != null ? _b : 0) * ((_c = this.props.heightFactor) != null ? _c : 1);
    }
  };
  var RenderAspectRatio = class extends RenderObject {
    apply(c) {
      const ar = this.props.aspectRatio > 0 ? this.props.aspectRatio : 1;
      if (c.minWidth >= c.maxWidth && c.minHeight >= c.maxHeight) return smallest(c);
      let width = c.maxWidth;
      let height;
      if (Number.isFinite(width)) height = width / ar;
      else {
        height = c.maxHeight;
        width = height * ar;
      }
      if (width > c.maxWidth) {
        width = c.maxWidth;
        height = width / ar;
      }
      if (height > c.maxHeight) {
        height = c.maxHeight;
        width = height * ar;
      }
      if (width < c.minWidth) {
        width = c.minWidth;
        height = width / ar;
      }
      if (height < c.minHeight) {
        height = c.minHeight;
        width = height * ar;
      }
      if (!Number.isFinite(width) || !Number.isFinite(height)) {
        return { width: 0, height: 0 };
      }
      return constrain(c, { width, height });
    }
    performLayout(c) {
      this.size = this.apply(c);
      const child = this.child;
      if (child) {
        child.layout(tight(this.size.width, this.size.height));
        child.offset = { x: 0, y: 0 };
      }
    }
    computeMinIntrinsicWidth(height) {
      var _a, _b;
      return Number.isFinite(height) ? height * (this.props.aspectRatio || 1) : (_b = (_a = this.child) == null ? void 0 : _a.minIntrinsicWidth(height)) != null ? _b : 0;
    }
    computeMaxIntrinsicWidth(height) {
      var _a, _b;
      return Number.isFinite(height) ? height * (this.props.aspectRatio || 1) : (_b = (_a = this.child) == null ? void 0 : _a.maxIntrinsicWidth(height)) != null ? _b : 0;
    }
    computeMinIntrinsicHeight(width) {
      var _a, _b;
      return Number.isFinite(width) ? width / (this.props.aspectRatio || 1) : (_b = (_a = this.child) == null ? void 0 : _a.minIntrinsicHeight(width)) != null ? _b : 0;
    }
    computeMaxIntrinsicHeight(width) {
      var _a, _b;
      return Number.isFinite(width) ? width / (this.props.aspectRatio || 1) : (_b = (_a = this.child) == null ? void 0 : _a.maxIntrinsicHeight(width)) != null ? _b : 0;
    }
  };
  var RenderFractional = class extends RenderObject {
    performLayout(c) {
      var _a, _b, _c;
      const wf = (_a = this.props.widthFactor) != null ? _a : null;
      const hf = (_b = this.props.heightFactor) != null ? _b : null;
      let inner = __spreadValues({}, c);
      if (wf != null) {
        if (Number.isFinite(c.maxWidth)) {
          const w2 = c.maxWidth * wf;
          inner = __spreadProps(__spreadValues({}, inner), { minWidth: w2, maxWidth: w2 });
        } else if (this.props.fallbackWidth != null) {
          inner = __spreadProps(__spreadValues({}, inner), { minWidth: this.props.fallbackWidth, maxWidth: this.props.fallbackWidth });
        }
      }
      if (hf != null) {
        if (Number.isFinite(c.maxHeight)) {
          const h = c.maxHeight * hf;
          inner = __spreadProps(__spreadValues({}, inner), { minHeight: h, maxHeight: h });
        } else if (this.props.fallbackHeight != null) {
          inner = __spreadProps(__spreadValues({}, inner), { minHeight: this.props.fallbackHeight, maxHeight: this.props.fallbackHeight });
        }
      }
      const child = this.child;
      if (child) {
        child.layout(inner);
        this.size = constrain(c, child.size);
        child.offset = alignOffset((_c = this.props.alignment) != null ? _c : { x: 0, y: 0 }, this.size, child.size);
      } else {
        this.size = constrain(c, { width: inner.minWidth, height: inner.minHeight });
      }
    }
  };
  var RenderLimitedBox = class extends RenderObject {
    performLayout(c) {
      const limited = {
        minWidth: c.minWidth,
        maxWidth: Number.isFinite(c.maxWidth) ? c.maxWidth : constrainLimit(c.minWidth, this.props.maxWidth),
        minHeight: c.minHeight,
        maxHeight: Number.isFinite(c.maxHeight) ? c.maxHeight : constrainLimit(c.minHeight, this.props.maxHeight)
      };
      const child = this.child;
      if (child) {
        child.layout(limited);
        child.offset = { x: 0, y: 0 };
        this.size = constrain(c, child.size);
      } else {
        this.size = constrain(limited, { width: 0, height: 0 });
      }
    }
  };
  function constrainLimit(min, limit) {
    return limit == null ? INF : Math.max(min, limit);
  }
  var RenderOverflowBox = class extends RenderObject {
    performLayout(c) {
      var _a, _b, _c, _d, _e;
      const p = this.props;
      const inner = {
        minWidth: (_a = p.minWidth) != null ? _a : c.minWidth,
        maxWidth: (_b = p.maxWidth) != null ? _b : c.maxWidth,
        minHeight: (_c = p.minHeight) != null ? _c : c.minHeight,
        maxHeight: (_d = p.maxHeight) != null ? _d : c.maxHeight
      };
      this.size = biggest(c);
      const child = this.child;
      if (child) {
        child.layout(inner);
        child.offset = alignOffset((_e = p.alignment) != null ? _e : { x: 0, y: 0 }, this.size, child.size);
      }
    }
  };
  var RenderFittedBox = class extends RenderObject {
    constructor() {
      super(...arguments);
      this.scaleX = 1;
      this.scaleY = 1;
      this.childOffset = { x: 0, y: 0 };
    }
    performLayout(c) {
      var _a, _b;
      const child = this.child;
      if (!child) {
        this.size = smallest(c);
        return;
      }
      child.layout({ minWidth: 0, maxWidth: INF, minHeight: 0, maxHeight: INF });
      const cs = child.size;
      const fit = (_a = this.props.fit) != null ? _a : "contain";
      this.size = preserveAspect(c, cs);
      const { sx, sy } = fitScale(fit, cs, this.size);
      this.scaleX = sx;
      this.scaleY = sy;
      const scaled = { width: cs.width * sx, height: cs.height * sy };
      this.childOffset = alignOffset((_b = this.props.alignment) != null ? _b : { x: 0, y: 0 }, this.size, scaled);
      child.offset = { x: 0, y: 0 };
    }
    viewKind() {
      return "view";
    }
    viewProps() {
      return {
        clip: this.props.clip !== false,
        transform: null
      };
    }
    childOriginInView() {
      return { x: 0, y: 0 };
    }
    /** The child is wrapped in a transform view by the compositor hook below. */
    get contentTransform() {
      return multiply(translation(this.childOffset.x, this.childOffset.y), scaling(this.scaleX, this.scaleY, 1));
    }
  };
  function fitScale(fit, child, box) {
    if (child.width <= 0 || child.height <= 0) return { sx: 1, sy: 1 };
    const rw = box.width / child.width;
    const rh = box.height / child.height;
    switch (fit) {
      case "fill":
        return { sx: rw, sy: rh };
      case "cover": {
        const s = Math.max(rw, rh);
        return { sx: s, sy: s };
      }
      case "fitWidth":
        return { sx: rw, sy: rw };
      case "fitHeight":
        return { sx: rh, sy: rh };
      case "none":
        return { sx: 1, sy: 1 };
      case "scaleDown": {
        const s = Math.min(1, Math.min(rw, rh));
        return { sx: s, sy: s };
      }
      case "contain":
      default: {
        const s = Math.min(rw, rh);
        return { sx: s, sy: s };
      }
    }
  }
  function preserveAspect(c, s) {
    if (c.minWidth >= c.maxWidth && c.minHeight >= c.maxHeight) return smallest(c);
    let width = s.width;
    let height = s.height;
    if (width <= 0 || height <= 0) return constrain(c, s);
    const ar = width / height;
    if (width > c.maxWidth) {
      width = c.maxWidth;
      height = width / ar;
    }
    if (height > c.maxHeight) {
      height = c.maxHeight;
      width = height * ar;
    }
    if (width < c.minWidth) {
      width = c.minWidth;
      height = width / ar;
    }
    if (height < c.minHeight) {
      height = c.minHeight;
      width = height * ar;
    }
    return constrain(c, { width, height });
  }
  var RenderFittedContent = class extends RenderObject {
    performLayout(c) {
      const child = this.child;
      if (child) {
        child.layout(c);
        child.offset = { x: 0, y: 0 };
        this.size = __spreadValues({}, child.size);
      } else this.size = smallest(c);
    }
    viewKind() {
      return "view";
    }
    viewProps() {
      const fitted = this.parent;
      return { transform: fitted instanceof RenderFittedBox ? fitted.contentTransform : identity(), transformOrigin: [0, 0] };
    }
  };
  var RenderBaseline = class extends RenderObject {
    performLayout(c) {
      var _a, _b;
      const child = this.child;
      if (!child) {
        this.size = smallest(c);
        return;
      }
      child.layout(loose(c));
      const target = (_a = this.props.baseline) != null ? _a : 0;
      const childBaseline = (_b = child.baseline()) != null ? _b : child.size.height;
      const top = target - childBaseline;
      child.offset = { x: 0, y: top };
      this.size = constrain(c, { width: child.size.width, height: top + child.size.height });
    }
  };
  var RenderRotatedBox = class extends RenderObject {
    get turns() {
      var _a;
      return (((_a = this.props.quarterTurns) != null ? _a : 0) % 4 + 4) % 4;
    }
    performLayout(c) {
      const odd = this.turns % 2 === 1;
      const child = this.child;
      if (!child) {
        this.size = smallest(c);
        return;
      }
      child.layout(odd ? { minWidth: c.minHeight, maxWidth: c.maxHeight, minHeight: c.minWidth, maxHeight: c.maxWidth } : c);
      this.size = odd ? { width: child.size.height, height: child.size.width } : __spreadValues({}, child.size);
      child.offset = { x: 0, y: 0 };
    }
    viewKind() {
      return "view";
    }
    viewProps() {
      const child = this.child;
      if (!child) return {};
      const t = this.turns;
      const cw = child.size.width;
      const ch = child.size.height;
      const m = multiply(
        translation(this.size.width / 2, this.size.height / 2),
        multiply(rotationZ(t * Math.PI / 2), translation(-cw / 2, -ch / 2))
      );
      return { transform: m, transformOrigin: [0, 0] };
    }
    computeMinIntrinsicWidth(h) {
      var _a, _b, _c, _d;
      return this.turns % 2 ? (_b = (_a = this.child) == null ? void 0 : _a.minIntrinsicHeight(h)) != null ? _b : 0 : (_d = (_c = this.child) == null ? void 0 : _c.minIntrinsicWidth(h)) != null ? _d : 0;
    }
    computeMaxIntrinsicWidth(h) {
      var _a, _b, _c, _d;
      return this.turns % 2 ? (_b = (_a = this.child) == null ? void 0 : _a.maxIntrinsicHeight(h)) != null ? _b : 0 : (_d = (_c = this.child) == null ? void 0 : _c.maxIntrinsicWidth(h)) != null ? _d : 0;
    }
  };
  var RenderIntrinsicWidth = class extends RenderObject {
    performLayout(c) {
      const child = this.child;
      if (!child) {
        this.size = smallest(c);
        return;
      }
      let inner = c;
      const applies = !this.props.onlyWhenUnbounded || !Number.isFinite(c.maxWidth);
      if (applies && !(c.minWidth >= c.maxWidth)) {
        const w2 = clampN(child.maxIntrinsicWidth(c.maxHeight), c.minWidth, c.maxWidth);
        inner = __spreadProps(__spreadValues({}, c), { minWidth: w2, maxWidth: w2 });
      }
      child.layout(inner);
      child.offset = { x: 0, y: 0 };
      this.size = __spreadValues({}, child.size);
    }
  };
  var RenderIntrinsicHeight = class extends RenderObject {
    performLayout(c) {
      const child = this.child;
      if (!child) {
        this.size = smallest(c);
        return;
      }
      let inner = c;
      if (!(c.minHeight >= c.maxHeight)) {
        const h = clampN(child.maxIntrinsicHeight(c.maxWidth), c.minHeight, c.maxHeight);
        inner = __spreadProps(__spreadValues({}, c), { minHeight: h, maxHeight: h });
      }
      child.layout(inner);
      child.offset = { x: 0, y: 0 };
      this.size = __spreadValues({}, child.size);
    }
  };
  var RenderOffstage = class extends RenderProxy {
    performLayout(c) {
      var _a;
      if (this.props.offstage === false) {
        super.performLayout(c);
        return;
      }
      (_a = this.child) == null ? void 0 : _a.layout(c);
      this.size = smallest(c);
    }
    paintsChild() {
      return this.props.offstage === false;
    }
  };
  var RenderIndexedStack = class extends RenderObject {
    performLayout(c) {
      var _a;
      const alignment = (_a = this.props.alignment) != null ? _a : { x: -1, y: -1 };
      let w2 = 0;
      let h = 0;
      const inner = loose(c);
      for (const child of this.children) {
        child.layout(inner);
        w2 = Math.max(w2, child.size.width);
        h = Math.max(h, child.size.height);
      }
      this.size = this.children.length ? constrain(c, { width: w2, height: h }) : biggest(c);
      for (const child of this.children) child.offset = alignOffset(alignment, this.size, child.size);
    }
    paintsChild(child) {
      var _a;
      const index = Math.max(0, Math.min(this.children.length - 1, Math.trunc((_a = this.props.index) != null ? _a : 0)));
      return this.children[index] === child;
    }
  };
  var RenderSafeArea = class extends RenderPadding {
    resolvedPadding() {
      const owner = this.owner;
      const inset = owner ? owner.platform.viewport(owner.surface).safeArea : { top: 0, right: 0, bottom: 0, left: 0 };
      const p = this.props;
      return {
        top: p.top !== false ? inset.top : 0,
        right: p.right !== false ? inset.right : 0,
        bottom: p.bottom !== false ? inset.bottom : 0,
        left: p.left !== false ? inset.left : 0
      };
    }
  };
  var RenderFillAxis = class extends RenderObject {
    performLayout(c) {
      const fillW = this.props.width && Number.isFinite(c.maxWidth);
      const fillH = this.props.height && Number.isFinite(c.maxHeight);
      const inner = {
        minWidth: fillW ? c.maxWidth : c.minWidth,
        maxWidth: c.maxWidth,
        minHeight: fillH ? c.maxHeight : c.minHeight,
        maxHeight: c.maxHeight
      };
      const child = this.child;
      if (child) {
        child.layout(inner);
        child.offset = { x: 0, y: 0 };
        this.size = __spreadValues({}, child.size);
      } else {
        this.size = constrain(inner, { width: 0, height: 0 });
      }
    }
  };

  // core/src/render/layout/stack.ts
  var RenderPositioned = class extends RenderObject {
    get isPositioned() {
      const p = this.props;
      return p.top != null || p.right != null || p.bottom != null || p.left != null || p.width != null || p.height != null;
    }
    performLayout(c) {
      var _a, _b;
      const child = this.child;
      if (child) {
        child.layout(c);
        child.offset = { x: 0, y: 0 };
        this.size = __spreadValues({}, child.size);
      } else {
        this.size = constrain(c, { width: (_a = this.props.width) != null ? _a : 0, height: (_b = this.props.height) != null ? _b : 0 });
      }
    }
  };
  var RenderStack = class extends RenderObject {
    performLayout(c) {
      var _a, _b;
      const alignment = (_a = this.props.alignment) != null ? _a : { x: -1, y: -1 };
      const fit = (_b = this.props.fit) != null ? _b : "loose";
      const nonPositioned = fit === "expand" ? __spreadProps(__spreadValues({}, c), { minWidth: biggest(c).width, maxWidth: biggest(c).width, minHeight: biggest(c).height, maxHeight: biggest(c).height }) : fit === "passthrough" ? c : loose(c);
      let hasNonPositioned = false;
      let width = c.minWidth;
      let height = c.minHeight;
      for (const child of this.children) {
        if (child instanceof RenderPositioned && child.isPositioned) continue;
        hasNonPositioned = true;
        child.layout(nonPositioned);
        width = Math.max(width, child.size.width);
        height = Math.max(height, child.size.height);
      }
      this.size = hasNonPositioned ? constrain(c, { width, height }) : biggest(c);
      if (!Number.isFinite(this.size.width) || !Number.isFinite(this.size.height)) {
        this.size = constrain(c, smallest(c));
      }
      for (const child of this.children) {
        if (child instanceof RenderPositioned && child.isPositioned) {
          this.layoutPositioned(child, alignment);
        } else {
          child.offset = alignOffset(alignment, this.size, child.size);
        }
      }
    }
    layoutPositioned(child, alignment) {
      const p = child.props;
      const W = this.size.width;
      const H = this.size.height;
      let c = { minWidth: 0, maxWidth: Number.POSITIVE_INFINITY, minHeight: 0, maxHeight: Number.POSITIVE_INFINITY };
      if (p.left != null && p.right != null) {
        const w2 = Math.max(0, W - p.right - p.left);
        c = __spreadProps(__spreadValues({}, c), { minWidth: w2, maxWidth: w2 });
      } else if (p.width != null) {
        c = __spreadProps(__spreadValues({}, c), { minWidth: p.width, maxWidth: p.width });
      }
      if (p.top != null && p.bottom != null) {
        const h = Math.max(0, H - p.bottom - p.top);
        c = __spreadProps(__spreadValues({}, c), { minHeight: h, maxHeight: h });
      } else if (p.height != null) {
        c = __spreadProps(__spreadValues({}, c), { minHeight: p.height, maxHeight: p.height });
      }
      child.layout(c);
      let x;
      if (p.left != null) x = p.left;
      else if (p.right != null) x = W - p.right - child.size.width;
      else x = (W - child.size.width) / 2 * (1 + alignment.x);
      let y;
      if (p.top != null) y = p.top;
      else if (p.bottom != null) y = H - p.bottom - child.size.height;
      else y = (H - child.size.height) / 2 * (1 + alignment.y);
      child.offset = { x, y };
    }
    viewKind() {
      return this.props.clip ? "view" : null;
    }
    viewProps() {
      return { clip: !!this.props.clip };
    }
    computeMinIntrinsicWidth(h) {
      let m = 0;
      for (const ch of this.children) if (!(ch instanceof RenderPositioned && ch.isPositioned)) m = Math.max(m, ch.minIntrinsicWidth(h));
      return m;
    }
    computeMaxIntrinsicWidth(h) {
      let m = 0;
      for (const ch of this.children) if (!(ch instanceof RenderPositioned && ch.isPositioned)) m = Math.max(m, ch.maxIntrinsicWidth(h));
      return m;
    }
    computeMinIntrinsicHeight(w2) {
      let m = 0;
      for (const ch of this.children) if (!(ch instanceof RenderPositioned && ch.isPositioned)) m = Math.max(m, ch.minIntrinsicHeight(w2));
      return m;
    }
    computeMaxIntrinsicHeight(w2) {
      let m = 0;
      for (const ch of this.children) if (!(ch instanceof RenderPositioned && ch.isPositioned)) m = Math.max(m, ch.maxIntrinsicHeight(w2));
      return m;
    }
  };

  // core/src/render/paint/box.ts
  function resolveRadius(d, width, height) {
    var _a, _b;
    const px = (_a = d.radius) != null ? _a : null;
    const pct = (_b = d.radiusPercent) != null ? _b : null;
    if (!pct) return clampRadius(px, width, height);
    const basis = Math.min(width, height);
    const r = (k) => (pct[k] ? pct[k] / 100 * basis : 0) + (px ? px[k] : 0);
    return clampRadius({ topLeft: r("topLeft"), topRight: r("topRight"), bottomRight: r("bottomRight"), bottomLeft: r("bottomLeft") }, width, height);
  }
  function clampRadius(r, width, height) {
    if (!r) return null;
    const max = Math.min(width, height) / 2;
    const c = (v) => Math.max(0, Math.min(v, max));
    const out = { topLeft: c(r.topLeft), topRight: c(r.topRight), bottomRight: c(r.bottomRight), bottomLeft: c(r.bottomLeft) };
    if (!out.topLeft && !out.topRight && !out.bottomRight && !out.bottomLeft) return null;
    return out;
  }
  function decorationViewProps(d, width, height) {
    var _a, _b, _c, _d;
    return {
      background: (_a = d.color) != null ? _a : null,
      gradients: d.gradients && d.gradients.length ? d.gradients : null,
      backgroundImage: (_b = d.image) != null ? _b : null,
      border: (_c = d.border) != null ? _c : null,
      radius: d.shape === "circle" ? null : resolveRadius(d, width, height),
      oval: d.shape === "circle" ? true : void 0,
      shadows: d.shadows && d.shadows.length ? d.shadows : null,
      outline: (_d = d.outline) != null ? _d : null
    };
  }
  var RenderDecoratedBox = class extends RenderProxy {
    viewKind() {
      return "view";
    }
    viewProps() {
      var _a;
      const d = (_a = this.props.decoration) != null ? _a : {};
      return __spreadProps(__spreadValues({}, decorationViewProps(d, this.size.width, this.size.height)), { clip: this.props.clip ? true : void 0 });
    }
  };
  var RenderOpacity = class extends RenderProxy {
    viewKind() {
      return "view";
    }
    viewProps() {
      var _a;
      const o = (_a = this.props.opacity) != null ? _a : 1;
      return { opacity: o >= 1 ? void 0 : Math.max(0, o) };
    }
  };
  var RenderTransform = class extends RenderProxy {
    viewKind() {
      return "view";
    }
    effectiveMatrix() {
      var _a;
      return (_a = this.props.transform) != null ? _a : identity();
    }
    origin() {
      var _a;
      if (this.props.origin) return this.props.origin;
      const a = (_a = this.props.alignment) != null ? _a : { x: 0, y: 0 };
      return [this.size.width / 2 * (1 + a.x), this.size.height / 2 * (1 + a.y)];
    }
    viewProps() {
      const m = this.effectiveMatrix();
      if (isIdentity(m)) return { transform: null };
      return { transform: m, transformOrigin: this.origin() };
    }
    /** The full matrix in this view's coordinate space (used for hit testing). */
    matrixInSpace() {
      const [ox, oy] = this.origin();
      return aboutOrigin(this.effectiveMatrix(), ox, oy);
    }
  };
  var RenderClip = class extends RenderProxy {
    viewKind() {
      return "view";
    }
    viewProps() {
      var _a;
      if (this.props.enabled === false) return {};
      const r = (_a = this.props.radius) != null ? _a : null;
      return {
        clip: true,
        radius: r ? resolveRadius({ radius: r }, this.size.width, this.size.height) : null,
        oval: this.props.oval ? true : void 0
      };
    }
  };
  var RenderIgnorePointer = class extends RenderProxy {
    viewKind() {
      return "view";
    }
    viewProps() {
      return { pointerEvents: this.props.ignoring === false ? "auto" : "none" };
    }
  };
  var RenderVisibility = class extends RenderObject {
    performLayout(c) {
      const child = this.child;
      if (this.props.mode === "gone") {
        child == null ? void 0 : child.layout(c);
        this.size = smallest(c);
        return;
      }
      if (child) {
        child.layout(c);
        child.offset = { x: 0, y: 0 };
        this.size = __spreadValues({}, child.size);
      } else this.size = smallest(c);
    }
    paintsChild() {
      return this.props.mode !== "gone";
    }
    viewKind() {
      return this.props.mode === "hidden" ? "view" : null;
    }
    viewProps() {
      return { hidden: true };
    }
  };
  var RenderFilter = class extends RenderProxy {
    viewKind() {
      return "view";
    }
    viewProps() {
      var _a, _b, _c;
      const f = (_a = this.props.filter) != null ? _a : null;
      const b = (_b = this.props.backdrop) != null ? _b : null;
      return { filter: f, backdropFilter: b, blendMode: (_c = this.props.blendMode) != null ? _c : null };
    }
  };
  var RenderShaderMask = class extends RenderProxy {
    viewKind() {
      return "view";
    }
    viewProps() {
      var _a;
      return { shaderMask: (_a = this.props.gradient) != null ? _a : null };
    }
  };
  var RenderDefaultTextStyle = class extends RenderProxy {
    get textStyle() {
      var _a;
      return (_a = this.props.style) != null ? _a : {};
    }
  };

  // core/src/render/animated.ts
  function curveOf(props, fallback = Curves.linear) {
    const c = props.curve;
    if (typeof c === "function") return c;
    return curveByName(c, fallback);
  }
  var eq = (a, b) => deepEqual(a, b);
  function lerpNullable(a, b, t) {
    if (a == null || b == null) return t < 0.5 ? a : b;
    return a + (b - a) * t;
  }
  var RenderAnimatedPadding = class extends RenderPadding {
    init(props) {
      var _a;
      super.init(props);
      this.value = new ImplicitValue((_a = props.padding) != null ? _a : { top: 0, right: 0, bottom: 0, left: 0 }, lerpInsets, eq, () => this.markNeedsLayout());
    }
    didUpdate() {
      var _a;
      this.value.set((_a = this.props.padding) != null ? _a : { top: 0, right: 0, bottom: 0, left: 0 }, this.props.duration, curveOf(this.props), this.owner);
    }
    resolvedPadding(c) {
      const saved = this.props.padding;
      this.props.padding = this.value.current;
      const out = super.resolvedPadding(c);
      this.props.padding = saved;
      return out;
    }
    onDetach() {
      this.value.dispose();
    }
  };
  var RenderAnimatedAlign = class extends RenderAlign {
    init(props) {
      var _a;
      super.init(props);
      this.value = new ImplicitValue((_a = props.alignment) != null ? _a : { x: 0, y: 0 }, lerpAlignment, eq, () => this.markNeedsLayout());
    }
    didUpdate() {
      var _a;
      this.value.set((_a = this.props.alignment) != null ? _a : { x: 0, y: 0 }, this.props.duration, curveOf(this.props), this.owner);
    }
    performLayout(c) {
      const saved = this.props.alignment;
      this.props.alignment = this.value.current;
      super.performLayout(c);
      this.props.alignment = saved;
    }
    onDetach() {
      this.value.dispose();
    }
  };
  var RenderAnimatedOpacity = class extends RenderOpacity {
    init(props) {
      var _a;
      super.init(props);
      this.value = new ImplicitValue((_a = props.opacity) != null ? _a : 1, lerpNumber, (a, b) => a === b, () => this.markNeedsPaint());
    }
    didUpdate() {
      var _a;
      this.value.set((_a = this.props.opacity) != null ? _a : 1, this.props.duration, curveOf(this.props), this.owner);
    }
    viewProps() {
      const o = this.value.current;
      return { opacity: o >= 1 ? void 0 : Math.max(0, o) };
    }
    onDetach() {
      this.value.dispose();
    }
  };
  var lerpTransformTarget = (a, b, t) => ({
    scale: lerpNumber(a.scale, b.scale, t),
    turns: lerpNumber(a.turns, b.turns, t),
    slideX: lerpNumber(a.slideX, b.slideX, t),
    slideY: lerpNumber(a.slideY, b.slideY, t),
    tx: lerpNumber(a.tx, b.tx, t),
    ty: lerpNumber(a.ty, b.ty, t),
    base: lerpMatrix(a.base, b.base, t)
  });
  var RenderAnimatedTransform = class extends RenderTransform {
    targetOf(p) {
      var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j, _k;
      return {
        scale: (_a = p.scale) != null ? _a : 1,
        turns: (_b = p.turns) != null ? _b : 0,
        slideX: (_d = (_c = p.slide) == null ? void 0 : _c[0]) != null ? _d : 0,
        slideY: (_f = (_e = p.slide) == null ? void 0 : _e[1]) != null ? _f : 0,
        tx: (_h = (_g = p.translate) == null ? void 0 : _g[0]) != null ? _h : 0,
        ty: (_j = (_i = p.translate) == null ? void 0 : _i[1]) != null ? _j : 0,
        base: (_k = p.transform) != null ? _k : identity()
      };
    }
    init(props) {
      super.init(props);
      this.value = new ImplicitValue(this.targetOf(props), lerpTransformTarget, eq, () => this.markNeedsPaint());
    }
    didUpdate() {
      this.value.set(this.targetOf(this.props), this.props.duration, curveOf(this.props), this.owner);
    }
    effectiveMatrix() {
      const v = this.value.current;
      let m = v.base;
      if (v.slideX || v.slideY || v.tx || v.ty) {
        m = multiply(translation(v.slideX * this.size.width + v.tx, v.slideY * this.size.height + v.ty), m);
      }
      if (v.turns) m = multiply(m, rotationZ(v.turns * Math.PI * 2));
      if (v.scale !== 1) m = multiply(m, scaling(v.scale, v.scale, 1));
      return m;
    }
    onDetach() {
      this.value.dispose();
    }
  };
  var RenderAnimatedConstrained = class extends RenderConstrainedBox {
    init(props) {
      var _a, _b;
      super.init(props);
      this.value = new ImplicitValue(
        { width: (_a = props.width) != null ? _a : null, height: (_b = props.height) != null ? _b : null },
        (a, b, t) => ({ width: lerpNullable(a.width, b.width, t), height: lerpNullable(a.height, b.height, t) }),
        eq,
        () => this.markNeedsLayout()
      );
    }
    didUpdate() {
      var _a, _b;
      this.value.set({ width: (_a = this.props.width) != null ? _a : null, height: (_b = this.props.height) != null ? _b : null }, this.props.duration, curveOf(this.props), this.owner);
    }
    additional() {
      const saved = { w: this.props.width, h: this.props.height };
      this.props.width = this.value.current.width;
      this.props.height = this.value.current.height;
      const out = super.additional();
      this.props.width = saved.w;
      this.props.height = saved.h;
      return out;
    }
    onDetach() {
      this.value.dispose();
    }
  };
  var RenderAnimatedDecorated = class extends RenderDecoratedBox {
    targetOf(d) {
      var _a, _b, _c, _d, _e, _f;
      return {
        color: (_a = d == null ? void 0 : d.color) != null ? _a : null,
        radius: (_b = d == null ? void 0 : d.radius) != null ? _b : null,
        borderColor: (_d = (_c = d == null ? void 0 : d.border) == null ? void 0 : _c.top.color) != null ? _d : null,
        borderWidth: (_f = (_e = d == null ? void 0 : d.border) == null ? void 0 : _e.top.width) != null ? _f : 0
      };
    }
    init(props) {
      super.init(props);
      this.value = new ImplicitValue(
        this.targetOf(props.decoration),
        (a, b, t) => ({
          color: a.color == null || b.color == null ? t < 0.5 ? a.color : b.color : lerpColor(a.color, b.color, t),
          radius: a.radius && b.radius ? lerpRadius(a.radius, b.radius, t) : t < 0.5 ? a.radius : b.radius,
          borderColor: a.borderColor == null || b.borderColor == null ? t < 0.5 ? a.borderColor : b.borderColor : lerpColor(a.borderColor, b.borderColor, t),
          borderWidth: lerpNumber(a.borderWidth, b.borderWidth, t)
        }),
        eq,
        () => this.markNeedsPaint()
      );
    }
    didUpdate() {
      this.value.set(this.targetOf(this.props.decoration), this.props.duration, curveOf(this.props), this.owner);
    }
    viewProps() {
      var _a;
      const d = __spreadValues({}, (_a = this.props.decoration) != null ? _a : {});
      const v = this.value.current;
      d.color = v.color;
      d.radius = v.radius;
      if (d.border && v.borderColor != null) {
        const side2 = (s) => __spreadProps(__spreadValues({}, s), { color: v.borderColor, width: s.style === "none" ? s.width : v.borderWidth });
        d.border = { top: side2(d.border.top), right: side2(d.border.right), bottom: side2(d.border.bottom), left: side2(d.border.left) };
      }
      return decorationViewProps(d, this.size.width, this.size.height);
    }
    onDetach() {
      this.value.dispose();
    }
  };
  var RenderAnimatedPositioned = class extends RenderPositioned {
    targetOf(p) {
      var _a, _b, _c, _d, _e, _f;
      return { top: (_a = p.top) != null ? _a : null, right: (_b = p.right) != null ? _b : null, bottom: (_c = p.bottom) != null ? _c : null, left: (_d = p.left) != null ? _d : null, width: (_e = p.width) != null ? _e : null, height: (_f = p.height) != null ? _f : null };
    }
    init(props) {
      super.init(props);
      this.value = new ImplicitValue(
        this.targetOf(props),
        (a, b, t) => ({
          top: lerpNullable(a.top, b.top, t),
          right: lerpNullable(a.right, b.right, t),
          bottom: lerpNullable(a.bottom, b.bottom, t),
          left: lerpNullable(a.left, b.left, t),
          width: lerpNullable(a.width, b.width, t),
          height: lerpNullable(a.height, b.height, t)
        }),
        eq,
        () => this.markNeedsLayout()
      );
      Object.assign(this.props, this.value.current);
    }
    didUpdate() {
      const target = this.targetOf(this.props);
      this.value.set(target, this.props.duration, curveOf(this.props), this.owner);
      Object.assign(this.props, this.value.current);
    }
    performLayout(c) {
      Object.assign(this.props, this.value.current);
      super.performLayout(c);
    }
    markNeedsLayout() {
      if (this.value) Object.assign(this.props, this.value.current);
      super.markNeedsLayout();
    }
    onDetach() {
      this.value.dispose();
    }
  };
  var lerpTextStyle = (a, b, t) => {
    const out = __spreadValues({}, t < 0.5 ? a : b);
    if (a.color != null && b.color != null) out.color = lerpColor(a.color, b.color, t);
    for (const k of ["fontSize", "letterSpacing", "wordSpacing", "height"]) {
      const x = a[k];
      const y = b[k];
      if (x != null && y != null) out[k] = x + (y - x) * t;
    }
    if (a.fontWeight != null && b.fontWeight != null) out.fontWeight = Math.round((a.fontWeight + (b.fontWeight - a.fontWeight) * t) / 100) * 100;
    return out;
  };
  var RenderAnimatedDefaultTextStyle = class extends RenderDefaultTextStyle {
    init(props) {
      var _a;
      super.init(props);
      this.value = new ImplicitValue((_a = props.style) != null ? _a : {}, lerpTextStyle, eq, () => this.markDescendantsDirty());
    }
    didUpdate() {
      var _a;
      this.value.set((_a = this.props.style) != null ? _a : {}, this.props.duration, curveOf(this.props), this.owner);
    }
    get textStyle() {
      return this.value.current;
    }
    markDescendantsDirty() {
      this.visit((ro) => {
        if (ro.type === "text") ro.markNeedsLayout();
      });
    }
    performLayout(c) {
      const saved = this.props.style;
      this.props.style = this.value.current;
      super.performLayout(c);
      this.props.style = saved;
    }
    onDetach() {
      this.value.dispose();
    }
  };
  var RenderAnimatedSize = class extends RenderObject {
    constructor() {
      super(...arguments);
      this.controller = null;
      this.fromSize = { width: 0, height: 0 };
      this.toSize = null;
      this.hasLaidOut = false;
    }
    performLayout(c) {
      var _a, _b, _c;
      const child = this.child;
      if (!child) {
        this.size = constrain(c, { width: 0, height: 0 });
        return;
      }
      child.layout(c);
      const target = __spreadValues({}, child.size);
      if (!this.hasLaidOut || !this.props.duration) {
        this.hasLaidOut = true;
        this.toSize = target;
        this.fromSize = target;
        this.size = constrain(c, target);
      } else if (this.toSize && (target.width !== this.toSize.width || target.height !== this.toSize.height)) {
        this.fromSize = __spreadValues({}, this.size);
        this.toSize = target;
        if (!this.controller) {
          this.controller = new AnimationController(this.props.duration);
          this.controller.addListener(() => this.markNeedsLayout());
        }
        this.controller.duration = this.props.duration;
        if (this.owner) this.controller.attach(this.owner);
        void this.controller.forward(0);
      }
      const t = ((_a = this.controller) == null ? void 0 : _a.isAnimating) ? curveOf(this.props)(this.controller.value) : 1;
      const to = (_b = this.toSize) != null ? _b : target;
      this.size = constrain(c, {
        width: this.fromSize.width + (to.width - this.fromSize.width) * t,
        height: this.fromSize.height + (to.height - this.fromSize.height) * t
      });
      const a = (_c = this.props.alignment) != null ? _c : { x: 0, y: 0 };
      child.offset = { x: (this.size.width - child.size.width) / 2 * (1 + a.x), y: (this.size.height - child.size.height) / 2 * (1 + a.y) };
    }
    viewKind() {
      return "view";
    }
    viewProps() {
      return { clip: true };
    }
    onDetach() {
      var _a, _b;
      (_a = this.controller) == null ? void 0 : _a.detach();
      (_b = this.controller) == null ? void 0 : _b.stop();
    }
  };
  var RenderAnimatedCrossFade = class extends RenderObject {
    constructor() {
      super(...arguments);
      this.controller = null;
    }
    init(props) {
      super.init(props);
    }
    onAttach() {
      var _a;
      if (!this.controller) {
        this.controller = new AnimationController((_a = this.props.duration) != null ? _a : 300, this.props.showFirst === false ? 1 : 0);
        this.controller.addListener(() => this.markNeedsLayout());
      }
      this.controller.attach(this.owner);
    }
    didUpdate(old) {
      var _a;
      if (!this.controller) return;
      this.controller.duration = (_a = this.props.duration) != null ? _a : 300;
      if (old.showFirst !== false !== (this.props.showFirst !== false)) {
        if (this.props.showFirst === false) void this.controller.forward();
        else void this.controller.reverse();
      }
    }
    get t() {
      var _a, _b;
      const v = (_b = (_a = this.controller) == null ? void 0 : _a.value) != null ? _b : this.props.showFirst === false ? 1 : 0;
      return curveOf(this.props)(v);
    }
    performLayout(c) {
      var _a, _b;
      const [first2, second] = this.children;
      const inner = { minWidth: 0, maxWidth: c.maxWidth, minHeight: 0, maxHeight: c.maxHeight };
      first2 == null ? void 0 : first2.layout(inner);
      second == null ? void 0 : second.layout(inner);
      const t = this.t;
      const a = (_a = first2 == null ? void 0 : first2.size) != null ? _a : { width: 0, height: 0 };
      const b = (_b = second == null ? void 0 : second.size) != null ? _b : { width: 0, height: 0 };
      this.size = constrain(c, { width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t });
      if (first2) {
        first2.offset = { x: 0, y: 0 };
        first2.props.opacity = 1 - t;
        first2.markNeedsPaint();
      }
      if (second) {
        second.offset = { x: 0, y: 0 };
        second.props.opacity = t;
        second.markNeedsPaint();
      }
    }
    viewKind() {
      return "view";
    }
    viewProps() {
      return { clip: true };
    }
    paintsChild(child) {
      const t = this.t;
      if (child === this.children[0]) return t < 1;
      return t > 0;
    }
    onDetach() {
      var _a, _b;
      (_a = this.controller) == null ? void 0 : _a.detach();
      (_b = this.controller) == null ? void 0 : _b.stop();
    }
  };
  var RenderAnimatedSwitcher = class extends RenderObject {
    constructor() {
      super(...arguments);
      /** Children leaving, with their remaining progress controllers. */
      this.outgoing = /* @__PURE__ */ new Map();
      this.incoming = /* @__PURE__ */ new Map();
      this.mounted = false;
    }
    /** Called by the reconciler when the current child is replaced. */
    childReplaced(oldChild, newChild) {
      this.childRemoved(oldChild);
      this.startIncoming(newChild);
    }
    /** Transition [oldChild] out, then detach it. */
    childRemoved(oldChild) {
      var _a;
      const duration = (_a = this.props.duration) != null ? _a : 300;
      if (!this.owner || duration <= 0) {
        oldChild.detach();
        this.children = this.children.filter((c) => c !== oldChild);
        return;
      }
      const out = new AnimationController(duration, 1);
      out.attach(this.owner);
      out.addListener(() => this.markNeedsLayout());
      this.outgoing.set(oldChild, out);
      if (!this.children.includes(oldChild)) this.children.unshift(oldChild);
      oldChild.parent = this;
      void out.reverse().then(() => {
        this.outgoing.delete(oldChild);
        oldChild.detach();
        this.children = this.children.filter((c) => c !== oldChild);
        this.markNeedsLayout();
      });
    }
    startIncoming(child) {
      var _a;
      if (!this.owner) return;
      const c = new AnimationController((_a = this.props.duration) != null ? _a : 300, 0);
      c.attach(this.owner);
      c.addListener(() => this.markNeedsLayout());
      this.incoming.set(child, c);
      void c.forward().then(() => this.incoming.delete(child));
    }
    onAttach() {
      this.mounted = true;
    }
    progressOf(child) {
      const curve = curveOf(this.props);
      const out = this.outgoing.get(child);
      if (out) return curve(out.value);
      const inc = this.incoming.get(child);
      if (inc) return curve(inc.value);
      return 1;
    }
    performLayout(c) {
      var _a;
      let w2 = 0;
      let h = 0;
      for (const child of this.children) {
        child.layout({ minWidth: 0, maxWidth: c.maxWidth, minHeight: 0, maxHeight: c.maxHeight });
        w2 = Math.max(w2, child.size.width);
        h = Math.max(h, child.size.height);
      }
      this.size = constrain(c, { width: w2, height: h });
      for (const child of this.children) {
        child.offset = { x: (this.size.width - child.size.width) / 2, y: (this.size.height - child.size.height) / 2 };
        if (child instanceof RenderSwitcherSlot) {
          child.progress = this.progressOf(child);
          child.kind = (_a = this.props.transitionType) != null ? _a : "fade";
          child.markNeedsPaint();
        }
      }
    }
    onDetach() {
      for (const c of this.outgoing.values()) c.stop();
      for (const c of this.incoming.values()) c.stop();
      this.mounted = false;
    }
    get isMounted() {
      return this.mounted;
    }
  };
  var RenderSwitcherSlot = class extends RenderProxy {
    constructor() {
      super(...arguments);
      this.progress = 1;
      this.kind = "fade";
    }
    viewKind() {
      return "view";
    }
    viewProps() {
      const p = this.progress;
      const w2 = this.size.width;
      const h = this.size.height;
      switch (this.kind) {
        case "scale":
          return { transform: scaling(p, p, 1), transformOrigin: [w2 / 2, h / 2] };
        case "rotation":
          return { transform: rotationZ(p * Math.PI * 2), transformOrigin: [w2 / 2, h / 2] };
        case "slide":
          return { transform: translation((1 - p) * w2, 0), transformOrigin: [0, 0] };
        default:
          return { opacity: p >= 1 ? void 0 : p };
      }
    }
  };
  var RenderTransition = class extends RenderObject {
    constructor() {
      super(...arguments);
      this.controller = null;
      /** TweenAnimationBuilder: begin of the current run (animates to new ends). */
      this.tweenFrom = null;
    }
    onAttach() {
      var _a;
      if (!this.controller) {
        this.controller = new AnimationController((_a = this.props.duration) != null ? _a : 300);
        this.controller.addListener(() => this.props.kind === "size" ? this.markNeedsLayout() : this.markNeedsPaint());
      }
      this.controller.attach(this.owner);
      this.start();
    }
    start() {
      const c = this.controller;
      const kind = this.props.kind;
      if (kind === "pulse") {
        c.repeatAnimation(true);
        return;
      }
      if (this.props.repeat) {
        c.repeatAnimation(!!this.props.autoReverse);
      } else if (this.props.autoReverse) {
        void c.forward(0).then(() => c.reverse());
      } else {
        void c.forward(0);
      }
    }
    didUpdate(old) {
      var _a;
      if (!this.controller) return;
      this.controller.duration = (_a = this.props.duration) != null ? _a : 300;
      if (this.props.kind === "tween" && old.end !== this.props.end) {
        this.tweenFrom = this.value();
        void this.controller.forward(0);
      }
    }
    /** Current animated value in the begin..end range. */
    value() {
      var _a, _b, _c;
      const raw = (_b = (_a = this.controller) == null ? void 0 : _a.value) != null ? _b : 0;
      const t = curveOf(this.props, this.props.kind === "pulse" ? Curves.easeInOut : Curves.linear)(raw);
      const begin = (_c = this.tweenFrom) != null ? _c : numberOr(this.props.begin, defaultBegin(this.props.kind));
      const end = numberOr(this.props.end, defaultEnd(this.props.kind));
      return begin + (end - begin) * t;
    }
    slideValue() {
      var _a, _b, _c, _d;
      const raw = (_b = (_a = this.controller) == null ? void 0 : _a.value) != null ? _b : 0;
      const t = curveOf(this.props)(raw);
      const b = (_c = this.props.begin) != null ? _c : [-1, 0];
      const e = (_d = this.props.end) != null ? _d : [0, 0];
      return [b[0] + (e[0] - b[0]) * t, b[1] + (e[1] - b[1]) * t];
    }
    performLayout(c) {
      const child = this.child;
      if (!child) {
        this.size = constrain(c, { width: 0, height: 0 });
        return;
      }
      if (this.props.kind === "size") {
        const factor = Math.max(0, this.value());
        const horizontal = this.props.axis === "horizontal";
        child.layout(horizontal ? __spreadProps(__spreadValues({}, c), { minWidth: 0, maxWidth: INF }) : __spreadProps(__spreadValues({}, c), { minHeight: 0, maxHeight: INF }));
        const size = horizontal ? { width: child.size.width * factor, height: child.size.height } : { width: child.size.width, height: child.size.height * factor };
        this.size = constrain(c, size);
        child.offset = horizontal ? { x: (this.size.width - child.size.width) / 2, y: 0 } : { x: 0, y: (this.size.height - child.size.height) / 2 };
        return;
      }
      child.layout(c);
      child.offset = { x: 0, y: 0 };
      this.size = __spreadValues({}, child.size);
    }
    viewKind() {
      return "view";
    }
    viewProps() {
      var _a;
      const w2 = this.size.width;
      const h = this.size.height;
      const center2 = [w2 / 2, h / 2];
      switch (this.props.kind) {
        case "fade": {
          const o = Math.max(0, Math.min(1, this.value()));
          return { opacity: o >= 1 ? void 0 : o };
        }
        case "slide": {
          const [x, y] = this.slideValue();
          return { transform: translation(x * w2, y * h), transformOrigin: [0, 0] };
        }
        case "scale":
        case "pulse": {
          const s = this.value();
          return { transform: scaling(s, s, 1), transformOrigin: center2 };
        }
        case "rotation":
          return { transform: rotationZ(this.value() * Math.PI * 2), transformOrigin: center2 };
        case "size":
          return { clip: true };
        case "tween": {
          const v = this.value();
          switch ((_a = this.props.tweenType) != null ? _a : "opacity") {
            case "scale":
              return { transform: scaling(v, v, 1), transformOrigin: center2 };
            case "rotation":
              return { transform: rotationZ(v * Math.PI * 2), transformOrigin: center2 };
            case "translateX":
              return { transform: translation(v, 0), transformOrigin: [0, 0] };
            case "translateY":
              return { transform: translation(0, v), transformOrigin: [0, 0] };
            default: {
              const o = Math.max(0, Math.min(1, v));
              return { opacity: o >= 1 ? void 0 : o };
            }
          }
        }
        default:
          return {};
      }
    }
    onDetach() {
      var _a, _b;
      (_a = this.controller) == null ? void 0 : _a.detach();
      (_b = this.controller) == null ? void 0 : _b.stop();
    }
  };
  function numberOr(v, fallback) {
    return typeof v === "number" && Number.isFinite(v) ? v : fallback;
  }
  function defaultBegin(kind) {
    return kind === "pulse" ? 1 : 0;
  }
  function defaultEnd(kind) {
    return kind === "pulse" ? 1.05 : 1;
  }
  var RenderStaggered = class extends RenderObject {
    constructor() {
      super(...arguments);
      this.controller = null;
    }
    onAttach() {
      var _a;
      if (!this.controller) {
        this.controller = new AnimationController((_a = this.props.duration) != null ? _a : 1e3);
        this.controller.addListener(() => {
          for (const c of this.children) c.markNeedsPaint();
        });
      }
      this.controller.attach(this.owner);
      void this.controller.forward(0);
    }
    itemProgress(index) {
      var _a, _b, _c, _d;
      const count = this.children.length;
      const total = (_a = this.props.duration) != null ? _a : 1e3;
      const delay = (_b = this.props.staggerDelay) != null ? _b : 100;
      const totalDelay = delay * (count - 1);
      const start = Math.max(0, Math.min(1, delay * index / total));
      const end = Math.max(0, Math.min(1, (delay * index + (total - totalDelay)) / total));
      const curve = interval(start, end, curveOf(this.props, Curves.easeOut));
      return curve((_d = (_c = this.controller) == null ? void 0 : _c.value) != null ? _d : 0);
    }
    performLayout(c) {
      let y = 0;
      let w2 = 0;
      for (const child of this.children) {
        child.layout({ minWidth: 0, maxWidth: c.maxWidth, minHeight: 0, maxHeight: INF });
        child.offset = { x: 0, y };
        y += child.size.height;
        w2 = Math.max(w2, child.size.width);
      }
      this.size = constrain(c, { width: w2, height: y });
    }
    onDetach() {
      var _a, _b;
      (_a = this.controller) == null ? void 0 : _a.detach();
      (_b = this.controller) == null ? void 0 : _b.stop();
    }
  };
  var RenderStaggerItem = class extends RenderProxy {
    viewKind() {
      return "view";
    }
    viewProps() {
      const parent = this.parent;
      const index = parent ? parent.children.indexOf(this) : 0;
      const v = parent instanceof RenderStaggered ? parent.itemProgress(index) : 1;
      const o = Math.max(0, Math.min(1, v));
      return { opacity: o >= 1 ? void 0 : o, transform: v >= 1 ? null : translation(0, 20 * (1 - v)), transformOrigin: [0, 0] };
    }
  };
  var RenderShimmer = class extends RenderShaderMask {
    constructor() {
      super(...arguments);
      this.controller = null;
    }
    onAttach() {
      var _a;
      if (!this.controller) {
        this.controller = new AnimationController((_a = this.props.duration) != null ? _a : 1500);
        this.controller.addListener(() => this.markNeedsPaint());
      }
      this.controller.attach(this.owner);
      this.controller.repeatAnimation(false);
    }
    viewProps() {
      var _a, _b, _c, _d;
      const v = -1 + 3 * ((_b = (_a = this.controller) == null ? void 0 : _a.value) != null ? _b : 0);
      const base = (_c = this.props.baseColor) != null ? _c : 4292927712;
      const highlight = (_d = this.props.highlightColor) != null ? _d : 4294309365;
      const clamp = (x) => Math.max(0, Math.min(1, x));
      const gradient = {
        kind: "linear",
        colors: [base, highlight, base],
        stops: [clamp(v - 0.3), clamp(v), clamp(v + 0.3)],
        begin: { x: -1, y: 0 },
        end: { x: 1, y: 0 }
      };
      return { shaderMask: gradient };
    }
    onDetach() {
      var _a, _b;
      (_a = this.controller) == null ? void 0 : _a.detach();
      (_b = this.controller) == null ? void 0 : _b.stop();
    }
  };
  var RenderAnimatedGradient = class extends RenderDecoratedBox {
    constructor() {
      super(...arguments);
      this.controller = null;
    }
    onAttach() {
      var _a;
      if (!this.controller) {
        this.controller = new AnimationController((_a = this.props.duration) != null ? _a : 2e3);
        this.controller.addListener(() => this.markNeedsPaint());
      }
      this.controller.attach(this.owner);
      this.controller.repeatAnimation(false);
    }
    viewProps() {
      var _a, _b, _c, _d;
      const colors = (_a = this.props.colors) != null ? _a : [4280391411, 4288423856, 4293467747, 4280391411];
      const shift = (_c = (_b = this.controller) == null ? void 0 : _b.value) != null ? _c : 0;
      const stops = colors.map((_, i) => ((colors.length > 1 ? i / (colors.length - 1) : 0) + shift) % 1).sort((a, b) => a - b);
      const d = __spreadProps(__spreadValues({}, (_d = this.props.decoration) != null ? _d : {}), {
        gradients: [{ kind: "linear", colors, stops, begin: { x: -1, y: -1 }, end: { x: 1, y: 1 } }]
      });
      return decorationViewProps(d, this.size.width, this.size.height);
    }
    onDetach() {
      var _a, _b;
      (_a = this.controller) == null ? void 0 : _a.detach();
      (_b = this.controller) == null ? void 0 : _b.stop();
    }
  };
  var RenderKeyframes = class extends RenderProxy {
    constructor() {
      super(...arguments);
      this.controller = null;
      this.frames = [];
      this.iteration = 0;
      this.delayTimer = null;
    }
    init(props) {
      var _a;
      super.init(props);
      this.frames = parseFrames((_a = props.frames) != null ? _a : []);
    }
    didUpdate(old) {
      var _a;
      if (!deepEqual(old.frames, this.props.frames)) this.frames = parseFrames((_a = this.props.frames) != null ? _a : []);
      if (old.playState !== this.props.playState && this.controller) {
        if (this.props.playState === "paused") this.controller.stop();
        else this.run();
      }
    }
    onAttach() {
      var _a, _b;
      if (!this.controller) {
        this.controller = new AnimationController((_a = this.props.duration) != null ? _a : 1e3);
        this.controller.addListener(() => this.markNeedsPaint());
        this.controller.addStatusListener((s) => {
          if (s === "completed" || s === "dismissed") this.onIterationEnd();
        });
      }
      this.controller.attach(this.owner);
      const delay = (_b = this.props.delay) != null ? _b : 0;
      if (delay > 0 && this.owner) {
        this.delayTimer = this.owner.platform.setTimeout(() => {
          this.delayTimer = null;
          this.run();
        }, delay);
      } else this.run();
    }
    direction(iteration) {
      switch (this.props.direction) {
        case "reverse":
          return "reverse";
        case "alternate":
          return iteration % 2 === 0 ? "forward" : "reverse";
        case "alternate-reverse":
          return iteration % 2 === 0 ? "reverse" : "forward";
        default:
          return "forward";
      }
    }
    run() {
      var _a;
      if (!this.controller || this.props.playState === "paused") return;
      this.controller.duration = Math.max(1, (_a = this.props.duration) != null ? _a : 1e3);
      if (this.direction(this.iteration) === "forward") void this.controller.forward(0);
      else void this.controller.reverse(1);
    }
    onIterationEnd() {
      var _a;
      this.iteration++;
      const total = (_a = this.props.iterations) != null ? _a : 1;
      if (total === -1 || this.iteration < total) this.run();
      else this.markNeedsPaint();
    }
    finished() {
      var _a;
      const total = (_a = this.props.iterations) != null ? _a : 1;
      return total !== -1 && this.iteration >= total;
    }
    viewKind() {
      return "view";
    }
    viewProps() {
      var _a, _b, _c;
      if (this.frames.length === 0) return {};
      const fill = (_a = this.props.fillMode) != null ? _a : "none";
      if (this.finished() && fill !== "forwards" && fill !== "both") return {};
      const t = curveByName(this.props.timing, Curves.ease)((_c = (_b = this.controller) == null ? void 0 : _b.value) != null ? _c : 0);
      const sampled = sampleFrames(this.frames, t);
      const out = {};
      if (sampled.opacity != null) out.opacity = sampled.opacity;
      if (sampled.transform) {
        out.transform = sampled.transform;
        out.transformOrigin = [this.size.width / 2, this.size.height / 2];
      }
      if (sampled.background != null) out.background = sampled.background;
      return out;
    }
    onDetach() {
      var _a, _b;
      if (this.delayTimer != null && this.owner) this.owner.platform.clearTimeout(this.delayTimer);
      (_a = this.controller) == null ? void 0 : _a.detach();
      (_b = this.controller) == null ? void 0 : _b.stop();
    }
  };
  function parseFrames(frames) {
    return frames.map((f) => {
      var _a;
      const s = CSSParser.parse(f.styles);
      const out = { offset: f.offset };
      if (s.opacity != null) out.opacity = s.opacity;
      let m = (_a = s.transform) != null ? _a : null;
      if (s.translate) m = multiply(m != null ? m : identity(), translation(s.translate.dx, s.translate.dy));
      if (s.rotate != null) m = multiply(m != null ? m : identity(), rotationZ(s.rotate * Math.PI / 180));
      if (s.scale != null) m = multiply(m != null ? m : identity(), scaling(s.scale, s.scale, 1));
      if (m) out.transform = m;
      if (s.backgroundColor != null) out.background = s.backgroundColor;
      return out;
    }).sort((a, b) => a.offset - b.offset);
  }
  function sampleFrames(frames, t) {
    const pick2 = (key) => {
      const withKey = frames.filter((f) => f[key] !== void 0);
      if (withKey.length === 0) return void 0;
      if (t <= withKey[0].offset) return withKey[0][key];
      for (let i = 0; i < withKey.length - 1; i++) {
        const a = withKey[i];
        const b = withKey[i + 1];
        if (t >= a.offset && t <= b.offset) {
          const local = b.offset > a.offset ? (t - a.offset) / (b.offset - a.offset) : 1;
          if (key === "opacity") return a.opacity + (b.opacity - a.opacity) * local;
          if (key === "transform") return lerpMatrix(a.transform, b.transform, local);
          return lerpColor(a.background, b.background, local);
        }
      }
      return withKey[withKey.length - 1][key];
    };
    return { opacity: pick2("opacity"), transform: pick2("transform"), background: pick2("background") };
  }
  var RenderHero = class extends RenderProxy {
    constructor() {
      super(...arguments);
      this.controller = null;
      this.fromRect = null;
    }
    /** Called by the owner's hero registry after layout of a frame. */
    flyFrom(rect, owner) {
      this.fromRect = rect;
      if (!this.controller) {
        this.controller = new AnimationController(300);
        this.controller.addListener(() => this.markNeedsPaint());
      }
      this.controller.attach(owner);
      void this.controller.forward(0).then(() => {
        this.fromRect = null;
        this.markNeedsPaint();
      });
    }
    viewKind() {
      return "view";
    }
    viewProps() {
      const from = this.fromRect;
      if (!from || !this.owner || !this.controller) return { transform: null };
      const here = this.owner.compositor.globalFrame(this);
      const t = Curves.fastOutSlowIn(this.controller.value);
      const sx = this.size.width > 0 ? from.width / this.size.width : 1;
      const sy = this.size.height > 0 ? from.height / this.size.height : 1;
      const scaleX = sx + (1 - sx) * t;
      const scaleY = sy + (1 - sy) * t;
      const dx = (from.x - here.x) * (1 - t);
      const dy = (from.y - here.y) * (1 - t);
      return { transform: multiply(translation(dx, dy), scaling(scaleX, scaleY, 1)), transformOrigin: [0, 0] };
    }
    onDetach() {
      var _a, _b;
      (_a = this.controller) == null ? void 0 : _a.detach();
      (_b = this.controller) == null ? void 0 : _b.stop();
    }
  };

  // core/src/render/layout/grid.ts
  var RenderGridItem = class extends RenderObject {
    performLayout(c) {
      const child = this.child;
      if (child) {
        child.layout(c);
        child.offset = { x: 0, y: 0 };
        this.size = __spreadValues({}, child.size);
      } else this.size = constrain(c, { width: 0, height: 0 });
    }
  };
  function parseTrack(token) {
    const t = token.trim().toLowerCase();
    if (t.startsWith("minmax(")) {
      const inner = t.substring(7, t.length - 1);
      const [a, b] = splitTopLevel(inner, ",").map((s) => s.trim());
      return { kind: "minmax", min: parseTrack(a != null ? a : "auto"), max: parseTrack(b != null ? b : "auto") };
    }
    if (t.startsWith("fit-content(")) return { kind: "minmax", min: { kind: "auto" }, max: parseTrack(t.substring(12, t.length - 1)) };
    if (t.endsWith("fr")) return { kind: "fr", value: parseFloat(t) || 1 };
    if (t.endsWith("%")) return { kind: "pct", value: parseFloat(t) || 0 };
    if (t === "auto" || t === "min-content" || t === "max-content") return { kind: "auto" };
    const n = parseFloat(t);
    if (Number.isFinite(n)) {
      if (t.endsWith("rem") || t.endsWith("em")) return { kind: "px", value: n * 16 };
      return { kind: "px", value: n };
    }
    return { kind: "auto" };
  }
  function parseTemplate(template) {
    if (!template) return null;
    const value = template.trim();
    if (value === "" || value === "none") return null;
    const tracks = [];
    let autoRepeat = null;
    let autoIndex = 0;
    for (const token of splitTopLevel(value, " ")) {
      const t = token.trim();
      if (t.startsWith("[")) continue;
      if (t.toLowerCase().startsWith("repeat(")) {
        const inner = t.substring(7, t.length - 1);
        const comma = inner.indexOf(",");
        const count = inner.substring(0, comma).trim().toLowerCase();
        const body = splitTopLevel(inner.substring(comma + 1).trim(), " ").map(parseTrack);
        if (count === "auto-fill" || count === "auto-fit") {
          autoRepeat = { tracks: body, fit: count === "auto-fit" };
          autoIndex = tracks.length;
        } else {
          const n = Math.max(1, Number.parseInt(count, 10) || 1);
          for (let i = 0; i < n; i++) tracks.push(...body);
        }
      } else {
        tracks.push(parseTrack(t));
      }
    }
    if (tracks.length === 0 && !autoRepeat) return null;
    return { tracks, autoRepeat, autoIndex };
  }
  function minOf(t, basis) {
    switch (t.kind) {
      case "px":
        return t.value;
      case "pct":
        return Number.isFinite(basis) ? t.value / 100 * basis : 0;
      case "minmax":
        return minOf(t.min, basis);
      default:
        return 0;
    }
  }
  function parsePlacement(raw) {
    var _a;
    if (!raw) return { start: null, span: 1 };
    const parts = String(raw).split("/").map((p) => p.trim().toLowerCase());
    const spanMatch = /span\s+(\d+)/;
    let start = null;
    let span = 1;
    const first2 = (_a = parts[0]) != null ? _a : "";
    const m1 = spanMatch.exec(first2);
    if (m1) span = Math.max(1, Number.parseInt(m1[1], 10));
    else if (/^-?\d+$/.test(first2)) start = Number.parseInt(first2, 10);
    if (parts.length > 1) {
      const second = parts[1];
      const m2 = spanMatch.exec(second);
      if (m2) span = Math.max(1, Number.parseInt(m2[1], 10));
      else if (/^-?\d+$/.test(second) && start != null) span = Math.max(1, Number.parseInt(second, 10) - start);
    }
    return { start: start != null && start > 0 ? start - 1 : null, span };
  }
  var RenderGrid = class extends RenderObject {
    wrapFallback(c, colGap, rowGap) {
      let x = 0;
      let y = 0;
      let rowH = 0;
      let maxW = 0;
      const limit = c.maxWidth;
      for (const child of this.children) {
        child.layout({ minWidth: 0, maxWidth: limit, minHeight: 0, maxHeight: INF });
        if (x > 0 && x + child.size.width > limit) {
          x = 0;
          y += rowH + rowGap;
          rowH = 0;
        }
        child.offset = { x, y };
        x += child.size.width + colGap;
        rowH = Math.max(rowH, child.size.height);
        maxW = Math.max(maxW, x - colGap);
      }
      this.size = constrain(c, { width: maxW, height: this.children.length ? y + rowH : 0 });
    }
    performLayout(c) {
      var _a, _b, _c, _d, _e, _f, _g, _h;
      const colGap = (_a = this.props.columnGap) != null ? _a : 0;
      const rowGap = (_b = this.props.rowGap) != null ? _b : 0;
      const template = parseTemplate(this.props.columns);
      const children = this.children;
      const W = c.maxWidth;
      if (!template || !Number.isFinite(W)) {
        this.wrapFallback(c, colGap, rowGap);
        return;
      }
      let tracks;
      if (template.autoRepeat) {
        const fixed = template.tracks.reduce((s, t) => s + minOf(t, W), 0) + template.tracks.length * colGap;
        const unit = template.autoRepeat.tracks;
        const unitMin = unit.reduce((s, t) => s + Math.max(minOf(t, W), t.kind === "fr" || t.kind === "auto" ? 1 : 0), 0);
        const unitGaps = unit.length * colGap;
        let reps = Math.max(1, Math.floor((W - fixed + colGap) / (unitMin + unitGaps)));
        if (template.tracks.length === 0 && unit.length === 1) reps = Math.min(reps, Math.max(1, children.length));
        tracks = [...template.tracks.slice(0, template.autoIndex)];
        for (let i = 0; i < reps; i++) {
          tracks.push(...unit.map((t) => t.kind === "minmax" ? { kind: "minmax", min: t.min, max: { kind: "fr", value: 1 } } : t));
        }
        tracks.push(...template.tracks.slice(template.autoIndex));
      } else {
        tracks = template.tracks;
      }
      const colCount = Math.max(1, tracks.length);
      const items = [];
      const occupied = /* @__PURE__ */ new Set();
      const isFree = (row3, col, colSpan, rowSpan) => {
        if (col + colSpan > colCount) return false;
        for (let r = row3; r < row3 + rowSpan; r++) for (let k = col; k < col + colSpan; k++) if (occupied.has(r + ":" + k)) return false;
        return true;
      };
      const occupy = (row3, col, colSpan, rowSpan) => {
        for (let r = row3; r < row3 + rowSpan; r++) for (let k = col; k < col + colSpan; k++) occupied.add(r + ":" + k);
      };
      let cursorRow = 0;
      let cursorCol = 0;
      for (const child of children) {
        const pd = child instanceof RenderGridItem ? child.props : {};
        const colP = parsePlacement(pd.column);
        const rowP = parsePlacement(pd.row);
        const colSpan = Math.min(colCount, colP.span);
        const rowSpan = rowP.span;
        let row3 = (_c = rowP.start) != null ? _c : -1;
        let col = (_d = colP.start) != null ? _d : -1;
        if (col >= colCount) col = colCount - colSpan;
        if (row3 >= 0 && col >= 0) {
        } else if (row3 >= 0) {
          col = 0;
          while (!isFree(row3, col, colSpan, rowSpan)) {
            col++;
            if (col + colSpan > colCount) {
              col = 0;
              row3++;
            }
          }
        } else if (col >= 0) {
          row3 = 0;
          while (!isFree(row3, col, colSpan, rowSpan)) row3++;
        } else {
          row3 = cursorRow;
          col = cursorCol;
          while (!isFree(row3, col, colSpan, rowSpan)) {
            col++;
            if (col + colSpan > colCount) {
              col = 0;
              row3++;
            }
          }
          cursorRow = row3;
          cursorCol = col + colSpan;
          if (cursorCol >= colCount) {
            cursorCol = 0;
            cursorRow++;
          }
        }
        occupy(row3, col, colSpan, rowSpan);
        items.push({ ro: child, col, row: row3, colSpan, rowSpan });
      }
      const widths = new Array(colCount).fill(0);
      let fixedTotal = 0;
      let frTotal = 0;
      for (let i = 0; i < colCount; i++) {
        const t = (_e = tracks[i]) != null ? _e : { kind: "fr", value: 1 };
        const base = t.kind === "minmax" ? t.max : t;
        if (base.kind === "fr") frTotal += base.value;
        else if (base.kind === "auto") {
          let m = minOf(t, W);
          for (const it of items) if (it.col === i && it.colSpan === 1) m = Math.max(m, it.ro.maxIntrinsicWidth(INF));
          widths[i] = m;
          fixedTotal += m;
        } else {
          widths[i] = Math.max(minOf(t, W), minOf(base, W));
          fixedTotal += widths[i];
        }
      }
      const gaps = (colCount - 1) * colGap;
      let free = W - fixedTotal - gaps;
      if (frTotal > 0) {
        const frTracks = tracks.map((t, i) => ({ i, t: t.kind === "minmax" ? t : null, base: t.kind === "minmax" ? t.max : t })).filter((x) => x.base.kind === "fr");
        let remaining = Math.max(0, free);
        let pool = frTracks.slice();
        for (let iter = 0; iter < 4 && pool.length; iter++) {
          const totalFr = pool.reduce((s, x) => s + x.base.value, 0);
          const perFr = remaining / totalFr;
          const stuck = pool.filter((x) => x.t && minOf(x.t.min, W) > perFr * x.base.value);
          if (stuck.length === 0) {
            for (const x of pool) widths[x.i] = perFr * x.base.value;
            pool = [];
            break;
          }
          for (const x of stuck) {
            widths[x.i] = minOf(x.t.min, W);
            remaining -= widths[x.i];
          }
          pool = pool.filter((x) => !stuck.includes(x));
        }
        free = 0;
      } else if (free < 0) {
        const autoIdx = tracks.map((t, i) => t.kind === "auto" ? i : -1).filter((i) => i >= 0);
        const autoSum = autoIdx.reduce((s, i) => s + widths[i], 0);
        if (autoSum > 0) for (const i of autoIdx) widths[i] = Math.max(0, widths[i] + free * widths[i] / autoSum);
      }
      const colX = new Array(colCount);
      let acc = 0;
      for (let i = 0; i < colCount; i++) {
        colX[i] = acc;
        acc += widths[i] + colGap;
      }
      const spanWidth = (col, span) => {
        let s = 0;
        for (let k = col; k < Math.min(colCount, col + span); k++) s += widths[k];
        return s + (Math.min(span, colCount - col) - 1) * colGap;
      };
      const rowCount = items.reduce((m, it) => Math.max(m, it.row + it.rowSpan), 0);
      const rowTemplate = parseTemplate(this.props.rows);
      const autoRowTrack = this.props.autoRows ? parseTrack(String(this.props.autoRows)) : null;
      const heights = new Array(rowCount).fill(0);
      const rowFixed = new Array(rowCount).fill(false);
      for (let r = 0; r < rowCount; r++) {
        const t = (_f = rowTemplate == null ? void 0 : rowTemplate.tracks[r]) != null ? _f : autoRowTrack;
        if (t && (t.kind === "px" || t.kind === "minmax" && t.min.kind === "px")) {
          heights[r] = minOf(t, c.maxHeight);
          rowFixed[r] = t.kind === "px";
        }
      }
      const stretch = ((_g = this.props.alignItems) != null ? _g : "start") === "stretch";
      for (const it of items) {
        const width = spanWidth(it.col, it.colSpan);
        it.ro.layout({ minWidth: width, maxWidth: width, minHeight: 0, maxHeight: INF });
        if (it.rowSpan === 1 && !rowFixed[it.row]) heights[it.row] = Math.max(heights[it.row], it.ro.size.height);
      }
      for (const it of items) {
        if (it.rowSpan === 1) continue;
        let h = 0;
        for (let r = it.row; r < it.row + it.rowSpan; r++) h += heights[r];
        h += (it.rowSpan - 1) * rowGap;
        const last = it.row + it.rowSpan - 1;
        if (it.ro.size.height > h && !rowFixed[last]) heights[last] += it.ro.size.height - h;
      }
      const rowY = new Array(rowCount);
      let y = 0;
      for (let r = 0; r < rowCount; r++) {
        rowY[r] = y;
        y += heights[r] + rowGap;
      }
      const totalH = rowCount ? y - rowGap : 0;
      for (const it of items) {
        let cellH = 0;
        for (let r = it.row; r < it.row + it.rowSpan; r++) cellH += heights[r];
        cellH += (it.rowSpan - 1) * rowGap;
        if (stretch || rowFixed[it.row]) {
          const width = spanWidth(it.col, it.colSpan);
          it.ro.layout({ minWidth: width, maxWidth: width, minHeight: stretch ? cellH : 0, maxHeight: stretch ? cellH : Math.max(cellH, 0) });
        }
        let dy = 0;
        const align2 = (_h = it.ro.props.alignSelf) != null ? _h : this.props.alignItems;
        if (align2 === "center") dy = (cellH - it.ro.size.height) / 2;
        else if (align2 === "end" || align2 === "flex-end") dy = cellH - it.ro.size.height;
        it.ro.offset = { x: colX[it.col], y: rowY[it.row] + dy };
      }
      this.size = constrain(c, { width: W, height: totalH });
    }
    computeMaxIntrinsicWidth(h) {
      var _a;
      let m = 0;
      for (const ch of this.children) m = Math.max(m, ch.maxIntrinsicWidth(h));
      const template = parseTemplate(this.props.columns);
      const cols = (template == null ? void 0 : template.tracks.length) || 1;
      return m * cols + (cols - 1) * ((_a = this.props.columnGap) != null ? _a : 0);
    }
    computeMinIntrinsicWidth(h) {
      let m = 0;
      for (const ch of this.children) m = Math.max(m, ch.minIntrinsicWidth(h));
      return m;
    }
  };

  // core/src/render/layout/scroll.ts
  var RenderScroll = class extends RenderObject {
    constructor() {
      super(...arguments);
      this.scrollOffset = { x: 0, y: 0 };
      this.contentWidth = 0;
      this.contentHeight = 0;
    }
    get axis() {
      var _a;
      return (_a = this.props.axis) != null ? _a : "vertical";
    }
    performLayout(c) {
      const axis = this.axis;
      const child = this.child;
      let inner;
      if (axis === "vertical") {
        inner = {
          minWidth: this.props.stretchCross ? c.maxWidth : c.minWidth,
          maxWidth: c.maxWidth,
          // A document root is at least as tall as the viewport (Flutter's
          // ConstrainedBox(minHeight: maxHeight) inside the scroll view).
          minHeight: this.props.fillViewport && Number.isFinite(c.maxHeight) ? c.maxHeight : 0,
          maxHeight: INF
        };
        if (!Number.isFinite(inner.minWidth)) inner.minWidth = 0;
      } else if (axis === "horizontal") {
        inner = { minWidth: 0, maxWidth: INF, minHeight: this.props.stretchCross ? c.maxHeight : c.minHeight, maxHeight: c.maxHeight };
        if (!Number.isFinite(inner.minHeight)) inner.minHeight = 0;
      } else {
        inner = { minWidth: 0, maxWidth: INF, minHeight: 0, maxHeight: INF };
      }
      if (child) {
        child.layout(inner);
        child.offset = { x: 0, y: 0 };
        this.contentWidth = child.size.width;
        this.contentHeight = child.size.height;
        this.size = constrain(c, child.size);
      } else {
        this.contentWidth = 0;
        this.contentHeight = 0;
        this.size = constrain(c, { width: 0, height: 0 });
      }
      this.scrollOffset = {
        x: Math.max(0, Math.min(this.scrollOffset.x, this.contentWidth - this.size.width)),
        y: Math.max(0, Math.min(this.scrollOffset.y, this.contentHeight - this.size.height))
      };
    }
    viewKind() {
      return "scroll";
    }
    viewProps() {
      return {
        scrollAxis: this.axis,
        contentSize: [Math.max(this.contentWidth, this.size.width), Math.max(this.contentHeight, this.size.height)],
        scrollEnabled: this.props.enabled !== false,
        showScrollbar: this.props.scrollbar !== false,
        clip: true,
        gestures: this.props.reportScroll ? ["scroll"] : null
      };
    }
    handleViewEvent(event) {
      var _a, _b, _c, _d;
      if (event.type === "scroll") {
        this.scrollOffset = { x: (_a = event.scrollX) != null ? _a : this.scrollOffset.x, y: (_b = event.scrollY) != null ? _b : this.scrollOffset.y };
        (_d = (_c = this.props).onScroll) == null ? void 0 : _d.call(_c, event);
      }
    }
    computeMinIntrinsicWidth(h) {
      var _a, _b;
      return this.axis === "vertical" ? (_b = (_a = this.child) == null ? void 0 : _a.minIntrinsicWidth(h)) != null ? _b : 0 : 0;
    }
    computeMaxIntrinsicWidth(h) {
      var _a, _b;
      return (_b = (_a = this.child) == null ? void 0 : _a.maxIntrinsicWidth(h)) != null ? _b : 0;
    }
    computeMinIntrinsicHeight(w2) {
      var _a, _b;
      return this.axis === "horizontal" ? (_b = (_a = this.child) == null ? void 0 : _a.minIntrinsicHeight(w2)) != null ? _b : 0 : 0;
    }
    computeMaxIntrinsicHeight(w2) {
      var _a, _b;
      return (_b = (_a = this.child) == null ? void 0 : _a.maxIntrinsicHeight(w2)) != null ? _b : 0;
    }
  };

  // core/src/render/layout/table.ts
  var RenderTableRow = class extends RenderObject {
    performLayout(c) {
      let x = 0;
      let h = 0;
      for (const cell of this.children) {
        cell.layout({ minWidth: 0, maxWidth: INF, minHeight: 0, maxHeight: c.maxHeight });
        cell.offset = { x, y: 0 };
        x += cell.size.width;
        h = Math.max(h, cell.size.height);
      }
      this.size = constrain(c, { width: x, height: h });
    }
    viewKind() {
      return this.props.decorated ? "view" : null;
    }
    viewProps() {
      var _a;
      return { background: (_a = this.props.background) != null ? _a : null };
    }
  };
  var RenderTableCell = class extends RenderObject {
    performLayout(c) {
      var _a;
      const child = this.child;
      if (child) {
        child.layout({ minWidth: c.minWidth, maxWidth: c.maxWidth, minHeight: 0, maxHeight: c.maxHeight });
        this.size = constrain(c, child.size);
        const free = this.size.height - child.size.height;
        const va = (_a = this.props.verticalAlign) != null ? _a : "middle";
        child.offset = { x: 0, y: va === "top" ? 0 : va === "bottom" ? free : free / 2 };
      } else {
        this.size = constrain(c, { width: 0, height: 0 });
      }
    }
  };
  var RenderTable = class extends RenderObject {
    constructor() {
      super(...arguments);
      this.cells = [];
      this.columns = 0;
    }
    collect() {
      const rows = [];
      let caption = null;
      for (const child of this.children) {
        if (child instanceof RenderTableRow) rows.push(child);
        else if (!caption) caption = child;
      }
      return { rows, caption };
    }
    place(rows) {
      this.cells = [];
      const occupied = /* @__PURE__ */ new Set();
      let columns = 0;
      rows.forEach((row3, r) => {
        var _a, _b;
        let col = 0;
        for (const cellRo of row3.children) {
          if (!(cellRo instanceof RenderTableCell)) continue;
          while (occupied.has(r + ":" + col)) col++;
          const colSpan = Math.max(1, Math.trunc((_a = cellRo.props.colSpan) != null ? _a : 1));
          const rowSpan = Math.max(1, Math.min(rows.length - r, Math.trunc((_b = cellRo.props.rowSpan) != null ? _b : 1)));
          for (let rr = r; rr < r + rowSpan; rr++) for (let cc = col; cc < col + colSpan; cc++) occupied.add(rr + ":" + cc);
          this.cells.push({ ro: cellRo, row: r, col, colSpan, rowSpan });
          col += colSpan;
          columns = Math.max(columns, col);
        }
      });
      this.columns = columns;
    }
    columnWidths(available, spacing) {
      var _a;
      const n = this.columns;
      const minW = new Array(n).fill(0);
      const maxW = new Array(n).fill(0);
      const spans = this.cells.slice().sort((a, b) => a.colSpan - b.colSpan);
      for (const cell of spans) {
        const cmin = cell.ro.minIntrinsicWidth(INF);
        const cmax = cell.ro.maxIntrinsicWidth(INF);
        const fixed = (_a = cell.ro.props.width) != null ? _a : null;
        if (cell.colSpan === 1) {
          minW[cell.col] = Math.max(minW[cell.col], fixed != null ? fixed : cmin);
          maxW[cell.col] = Math.max(maxW[cell.col], fixed != null ? fixed : cmax);
        } else {
          const cols = Array.from({ length: cell.colSpan }, (_, k) => cell.col + k).filter((k) => k < n);
          const inner = (cell.colSpan - 1) * spacing;
          const curMin = cols.reduce((s, k) => s + minW[k], 0) + inner;
          const curMax = cols.reduce((s, k) => s + maxW[k], 0) + inner;
          if (cmin > curMin) for (const k of cols) minW[k] += (cmin - curMin) / cols.length;
          if (cmax > curMax) for (const k of cols) maxW[k] += (cmax - curMax) / cols.length;
        }
      }
      for (let k = 0; k < n; k++) maxW[k] = Math.max(maxW[k], minW[k]);
      const gaps = (n + 1) * spacing;
      const sumMax = maxW.reduce((a, b) => a + b, 0);
      const sumMin = minW.reduce((a, b) => a + b, 0);
      const room = available - gaps;
      if (!Number.isFinite(available) || sumMax <= room) {
        if (this.props.fullWidth && Number.isFinite(available) && sumMax > 0 && sumMax < room) {
          return maxW.map((w2) => w2 + (room - sumMax) * w2 / sumMax);
        }
        return maxW;
      }
      if (sumMin >= room) return minW;
      const extra = room - sumMin;
      const flexTotal = sumMax - sumMin;
      return minW.map((w2, k) => w2 + (flexTotal > 0 ? extra * (maxW[k] - minW[k]) / flexTotal : extra / n));
    }
    performLayout(c) {
      var _a;
      const spacing = this.props.collapse === false ? (_a = this.props.borderSpacing) != null ? _a : 2 : 0;
      const { rows, caption } = this.collect();
      this.place(rows);
      const widths = this.columnWidths(c.maxWidth, spacing);
      const colX = [];
      let x = spacing;
      for (const w2 of widths) {
        colX.push(x);
        x += w2 + spacing;
      }
      const tableWidth = Math.max(x, c.minWidth);
      const spanW = (col, span) => {
        let s = 0;
        for (let k = col; k < col + span && k < widths.length; k++) s += widths[k];
        return s + (span - 1) * spacing;
      };
      const rowH = new Array(rows.length).fill(0);
      for (const cell of this.cells) {
        const w2 = spanW(cell.col, cell.colSpan);
        cell.ro.layout({ minWidth: w2, maxWidth: w2, minHeight: 0, maxHeight: INF });
        if (cell.rowSpan === 1) rowH[cell.row] = Math.max(rowH[cell.row], cell.ro.size.height);
      }
      for (const cell of this.cells) {
        if (cell.rowSpan === 1) continue;
        let h = 0;
        for (let r = cell.row; r < cell.row + cell.rowSpan; r++) h += rowH[r];
        h += (cell.rowSpan - 1) * spacing;
        if (cell.ro.size.height > h) rowH[cell.row + cell.rowSpan - 1] += cell.ro.size.height - h;
      }
      let y = 0;
      let captionHeight = 0;
      const captionBottom = this.props.caption === "bottom";
      if (caption) {
        caption.layout({ minWidth: tableWidth, maxWidth: tableWidth, minHeight: 0, maxHeight: INF });
        captionHeight = caption.size.height;
        if (!captionBottom) {
          caption.offset = { x: 0, y: 0 };
          y = captionHeight;
        }
      }
      const rowY = [];
      y += spacing;
      for (let r = 0; r < rows.length; r++) {
        rowY.push(y);
        y += rowH[r] + spacing;
      }
      rows.forEach((row3, r) => {
        row3.size = { width: tableWidth, height: rowH[r] };
        row3.offset = { x: 0, y: rowY[r] };
        row3.needsLayout = false;
      });
      for (const cell of this.cells) {
        let h = 0;
        for (let rr = cell.row; rr < cell.row + cell.rowSpan; rr++) h += rowH[rr];
        h += (cell.rowSpan - 1) * spacing;
        const w2 = spanW(cell.col, cell.colSpan);
        cell.ro.layout({ minWidth: w2, maxWidth: w2, minHeight: h, maxHeight: h });
        cell.ro.offset = { x: colX[cell.col], y: 0 };
        if (cell.rowSpan > 1) cell.ro.offset.y = 0;
      }
      if (caption && captionBottom) {
        caption.offset = { x: 0, y };
        y += captionHeight;
      }
      this.size = constrain(c, { width: tableWidth, height: y });
    }
    computeMinIntrinsicWidth() {
      const { rows } = this.collect();
      this.place(rows);
      return this.columnWidths(0, 0).reduce((a, b) => a + b, 0);
    }
    computeMaxIntrinsicWidth() {
      const { rows } = this.collect();
      this.place(rows);
      return this.columnWidths(INF, 0).reduce((a, b) => a + b, 0);
    }
  };

  // core/src/render/layout/wrap.ts
  function distribute(alignment, free, count) {
    switch (alignment) {
      case "end":
        return { leading: free, between: 0 };
      case "center":
        return { leading: free / 2, between: 0 };
      case "spaceBetween":
        return { leading: 0, between: count > 1 ? free / (count - 1) : 0 };
      case "spaceAround": {
        const b = count > 0 ? free / count : 0;
        return { leading: b / 2, between: b };
      }
      case "spaceEvenly": {
        const b = count > 0 ? free / (count + 1) : 0;
        return { leading: b, between: b };
      }
      default:
        return { leading: 0, between: 0 };
    }
  }
  var RenderWrap = class extends RenderObject {
    performLayout(c) {
      var _a, _b, _c, _d, _e;
      const horizontal = this.props.direction !== "vertical";
      const spacing = (_a = this.props.spacing) != null ? _a : 0;
      const runSpacing = (_b = this.props.runSpacing) != null ? _b : 0;
      const mainLimit = horizontal ? c.maxWidth : c.maxHeight;
      const childC = horizontal ? { minWidth: 0, maxWidth: c.maxWidth, minHeight: 0, maxHeight: INF } : { minWidth: 0, maxWidth: INF, minHeight: 0, maxHeight: c.maxHeight };
      const main = (s) => horizontal ? s.width : s.height;
      const cross = (s) => horizontal ? s.height : s.width;
      const runs = [];
      let run = { children: [], main: 0, cross: 0 };
      for (const child of this.children) {
        child.layout(childC);
        const cm = main(child.size);
        const extra = run.children.length ? spacing : 0;
        if (run.children.length && run.main + extra + cm > mainLimit + 0.01) {
          runs.push(run);
          run = { children: [], main: 0, cross: 0 };
        }
        run.main += (run.children.length ? spacing : 0) + cm;
        run.cross = Math.max(run.cross, cross(child.size));
        run.children.push(child);
      }
      if (run.children.length) runs.push(run);
      let contentMain = 0;
      let contentCross = 0;
      for (const r of runs) {
        contentMain = Math.max(contentMain, r.main);
        contentCross += r.cross;
      }
      contentCross += Math.max(0, runs.length - 1) * runSpacing;
      this.size = constrain(c, horizontal ? { width: contentMain, height: contentCross } : { width: contentCross, height: contentMain });
      const boxMain = main(this.size);
      const boxCross = cross(this.size);
      const runDist = distribute((_c = this.props.runAlignment) != null ? _c : "start", Math.max(0, boxCross - contentCross), runs.length);
      const flipCross = this.props.verticalDirection === "up";
      let crossPos = runDist.leading;
      const runOrder = flipCross ? [...runs].reverse() : runs;
      for (const r of runOrder) {
        const dist = distribute((_d = this.props.alignment) != null ? _d : "start", Math.max(0, boxMain - r.main), r.children.length);
        let mainPos = dist.leading;
        const children = this.props.reverse ? [...r.children].reverse() : r.children;
        for (const child of children) {
          let childCross = 0;
          switch ((_e = this.props.crossAxisAlignment) != null ? _e : "start") {
            case "end":
              childCross = r.cross - cross(child.size);
              break;
            case "center":
              childCross = (r.cross - cross(child.size)) / 2;
              break;
          }
          child.offset = horizontal ? { x: mainPos, y: crossPos + childCross } : { x: crossPos + childCross, y: mainPos };
          mainPos += main(child.size) + spacing + dist.between;
        }
        crossPos += r.cross + runSpacing + runDist.between;
      }
    }
    computeMinIntrinsicWidth(height) {
      if (this.props.direction === "vertical") return this.sum("w", height);
      let m = 0;
      for (const ch of this.children) m = Math.max(m, ch.minIntrinsicWidth(INF));
      return m;
    }
    computeMaxIntrinsicWidth(height) {
      if (this.props.direction === "vertical") {
        let m = 0;
        for (const ch of this.children) m = Math.max(m, ch.maxIntrinsicWidth(INF));
        return m;
      }
      return this.sum("w", height);
    }
    computeMinIntrinsicHeight(width) {
      if (!Number.isFinite(width)) return this.computeMaxIntrinsicHeight(width);
      const saved = this.size;
      this.layout({ minWidth: 0, maxWidth: width, minHeight: 0, maxHeight: INF });
      const h = this.size.height;
      this.size = saved;
      this.needsLayout = true;
      return h;
    }
    computeMaxIntrinsicHeight(width) {
      return this.computeMinIntrinsicHeight(Number.isFinite(width) ? width : this.computeMaxIntrinsicWidth(INF));
    }
    sum(axis, extent) {
      var _a;
      const spacing = (_a = this.props.spacing) != null ? _a : 0;
      let total = 0;
      for (const ch of this.children) total += axis === "w" ? ch.maxIntrinsicWidth(extent) : 0;
      return total + Math.max(0, this.children.length - 1) * spacing;
    }
  };

  // core/src/render/paint/leaves.ts
  var RenderImage = class extends RenderObject {
    naturalSize() {
      var _a;
      const src = (_a = this.props.src) != null ? _a : null;
      if (!src || !this.owner) return null;
      return this.owner.imageSize(src);
    }
    performLayout(c) {
      const inner = enforce(tightFor({ minWidth: 0, maxWidth: INF, minHeight: 0, maxHeight: INF }, this.props.width, this.props.height), c);
      const natural = this.naturalSize();
      if (!natural) {
        this.size = smallest(inner);
        return;
      }
      this.size = preserveAspect(inner, natural);
    }
    computeMaxIntrinsicWidth(h) {
      if (this.props.width != null) return this.props.width;
      const n = this.naturalSize();
      if (!n) return 0;
      return Number.isFinite(h) && n.height > 0 ? h * n.width / n.height : n.width;
    }
    computeMinIntrinsicWidth(h) {
      return this.computeMaxIntrinsicWidth(h);
    }
    computeMaxIntrinsicHeight(w2) {
      if (this.props.height != null) return this.props.height;
      const n = this.naturalSize();
      if (!n) return 0;
      return Number.isFinite(w2) && n.width > 0 ? w2 * n.height / n.width : n.height;
    }
    computeMinIntrinsicHeight(w2) {
      return this.computeMaxIntrinsicHeight(w2);
    }
    viewKind() {
      return "image";
    }
    viewProps() {
      var _a, _b, _c, _d, _e, _f, _g;
      return {
        src: (_a = this.props.src) != null ? _a : null,
        fit: (_b = this.props.fit) != null ? _b : "contain",
        alignment: (_c = this.props.alignment) != null ? _c : null,
        alt: (_d = this.props.alt) != null ? _d : null,
        tint: (_e = this.props.tint) != null ? _e : null,
        semanticsLabel: (_g = (_f = this.props.semanticsLabel) != null ? _f : this.props.alt) != null ? _g : null,
        backgroundImage: this.props.repeat && this.props.repeat !== "no-repeat" ? { src: this.props.src, fit: null, alignment: null, repeat: this.props.repeat } : null
      };
    }
    handleViewEvent(event) {
      var _a, _b;
      (_b = (_a = this.props).onEvent) == null ? void 0 : _b.call(_a, event);
    }
  };
  var RenderControl = class extends RenderObject {
    kind() {
      return this.props.kind;
    }
    defaultSize(c) {
      var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j, _k, _l;
      const kind = this.kind();
      const view = (_a = this.props.view) != null ? _a : {};
      const fillW = (fallback) => Number.isFinite(c.maxWidth) ? c.maxWidth : fallback;
      switch (kind) {
        case "checkbox":
        case "radio":
          return { width: 48, height: 48 };
        case "switch":
          return { width: 60, height: 48 };
        case "slider":
          return { width: fillW(200), height: 48 };
        case "progress":
          return view.variant === "circular" ? { width: 36, height: 36 } : { width: fillW(200), height: (_b = view.strokeWidth) != null ? _b : 4 };
        case "textInput": {
          const ts = (_c = view.textStyle) != null ? _c : null;
          const fontSize = (_d = ts == null ? void 0 : ts.fontSize) != null ? _d : 16;
          const lineH = (_f = this.props.lineHeight) != null ? _f : fontSize * ((_e = ts == null ? void 0 : ts.height) != null ? _e : 1.5);
          const lines = Math.max(1, (_g = this.props.lines) != null ? _g : 1);
          const pad = (_h = this.props.padding) != null ? _h : [12, 0, 12, 0];
          return { width: fillW(280), height: Math.ceil(lines * lineH + pad[0] + pad[2]) };
        }
        case "select": {
          const ts = (_i = view.textStyle) != null ? _i : null;
          const fontSize = (_j = ts == null ? void 0 : ts.fontSize) != null ? _j : 14;
          const lineH = Math.max(24, fontSize * ((_k = ts == null ? void 0 : ts.height) != null ? _k : 1.3));
          const pad = (_l = this.props.padding) != null ? _l : [0, 0, 0, 0];
          return { width: fillW(200), height: Math.ceil(lineH + pad[0] + pad[2]) };
        }
        default:
          return { width: 48, height: 48 };
      }
    }
    performLayout(c) {
      var _a, _b, _c, _d;
      let size = this.defaultSize(c);
      const measured = (_d = (_a = this.owner) == null ? void 0 : (_b = _a.platform).measureControl) == null ? void 0 : _d.call(_b, { kind: this.kind(), props: (_c = this.props.view) != null ? _c : {} }, c.maxWidth);
      if (measured) size = measured;
      if (this.props.width != null) size = __spreadProps(__spreadValues({}, size), { width: this.props.width });
      if (this.props.height != null) size = __spreadProps(__spreadValues({}, size), { height: this.props.height });
      this.size = constrain(c, size);
    }
    computeMinIntrinsicWidth() {
      var _a;
      return (_a = this.props.width) != null ? _a : this.defaultSize({ minWidth: 0, maxWidth: INF, minHeight: 0, maxHeight: INF }).width;
    }
    computeMaxIntrinsicWidth() {
      return this.computeMinIntrinsicWidth();
    }
    computeMinIntrinsicHeight() {
      var _a;
      return (_a = this.props.height) != null ? _a : this.defaultSize({ minWidth: 0, maxWidth: INF, minHeight: 0, maxHeight: INF }).height;
    }
    computeMaxIntrinsicHeight() {
      return this.computeMinIntrinsicHeight();
    }
    baseline() {
      var _a, _b, _c, _d;
      if (this.kind() === "textInput" || this.kind() === "select") {
        const ts = (_b = (_a = this.props.view) == null ? void 0 : _a.textStyle) != null ? _b : null;
        const pad = (_c = this.props.padding) != null ? _c : [12, 0, 12, 0];
        return pad[0] + ((_d = ts == null ? void 0 : ts.fontSize) != null ? _d : 16) * 0.95;
      }
      return null;
    }
    viewKind() {
      return this.kind();
    }
    viewProps() {
      var _a;
      return __spreadValues({}, (_a = this.props.view) != null ? _a : {});
    }
    handleViewEvent(event) {
      var _a, _b;
      (_b = (_a = this.props).onEvent) == null ? void 0 : _b.call(_a, event);
      if (this.props.controlled && this.viewId != null && this.owner) {
        this.owner.compositor.invalidateProps(this.viewId, ["checked", "value"]);
      }
    }
  };
  var RenderCanvas = class extends RenderObject {
    constructor() {
      super(...arguments);
      this.sentGeneration = -1;
      this.sentCount = 0;
      this.sentInlineKey = null;
    }
    performLayout(c) {
      var _a, _b;
      const w2 = (_a = this.props.width) != null ? _a : null;
      const h = (_b = this.props.height) != null ? _b : null;
      const b = biggest(c);
      this.size = constrain(c, {
        width: w2 != null ? w2 : Number.isFinite(c.maxWidth) ? b.width : 0,
        height: h != null ? h : Number.isFinite(c.maxHeight) ? b.height : 0
      });
    }
    viewKind() {
      return "canvas";
    }
    viewProps() {
      var _a, _b, _c;
      const out = { background: (_a = this.props.background) != null ? _a : null };
      const ctx = this.props.context;
      if (ctx) {
        if (ctx.generation !== this.sentGeneration) {
          out.commands = ctx.commands.slice();
          this.sentGeneration = ctx.generation;
          this.sentCount = ctx.commands.length;
        } else if (ctx.commands.length > this.sentCount) {
          out.appendCommands = ctx.commands.slice(this.sentCount);
          this.sentCount = ctx.commands.length;
        }
        out.canvasVersion = ctx.version;
        return out;
      }
      const commands = (_b = this.props.commands) != null ? _b : [];
      const key = (_c = this.props.commandsKey) != null ? _c : JSON.stringify(commands);
      if (key !== this.sentInlineKey) {
        out.commands = commands;
        this.sentInlineKey = key;
      }
      return out;
    }
    /** Force the next frame to resend the full command list (e.g. after re-mount). */
    resetSent() {
      this.sentGeneration = -1;
      this.sentCount = 0;
      this.sentInlineKey = null;
    }
    handleViewEvent(event) {
      var _a, _b;
      (_b = (_a = this.props).onEvent) == null ? void 0 : _b.call(_a, event);
    }
  };
  var RenderScene3D = class extends RenderObject {
    performLayout(c) {
      var _a, _b;
      const w2 = (_a = this.props.width) != null ? _a : null;
      const h = (_b = this.props.height) != null ? _b : null;
      const width = w2 != null ? w2 : Number.isFinite(c.maxWidth) ? c.maxWidth : 300;
      const height = h != null ? h : Number.isFinite(c.maxHeight) ? c.maxHeight : width * 9 / 16;
      this.size = constrain(c, { width, height });
      for (const child of this.children) {
        child.layout({ minWidth: this.size.width, maxWidth: this.size.width, minHeight: this.size.height, maxHeight: this.size.height });
        child.offset = { x: 0, y: 0 };
      }
    }
    viewKind() {
      return "scene3d";
    }
    /** The placeholder child paints only when no engine is live. */
    paintsChild() {
      return !this.props.live;
    }
    viewProps() {
      return {
        surfaceId: this.props.surfaceId,
        clickable: !!this.props.clickable,
        gestures: this.props.clickable ? ["tap"] : null,
        clip: true
      };
    }
    handleViewEvent(event) {
      var _a, _b;
      (_b = (_a = this.props).onEvent) == null ? void 0 : _b.call(_a, event);
    }
  };
  var RenderMedia = class extends RenderObject {
    constructor() {
      super(...arguments);
      this.aspect = null;
    }
    performLayout(c) {
      var _a, _b, _c;
      const kind = this.props.kind === "audio" ? "audio" : "video";
      const w2 = (_a = this.props.width) != null ? _a : null;
      const h = (_b = this.props.height) != null ? _b : null;
      if (kind === "audio") {
        this.size = constrain(c, { width: w2 != null ? w2 : Number.isFinite(c.maxWidth) ? c.maxWidth : 300, height: h != null ? h : 54 });
        return;
      }
      const aspect = (_c = this.aspect) != null ? _c : 16 / 9;
      const width = w2 != null ? w2 : Number.isFinite(c.maxWidth) ? c.maxWidth : 300;
      const height = h != null ? h : width / aspect;
      this.size = constrain(c, { width, height });
    }
    viewKind() {
      return this.props.kind === "audio" ? "audio" : "video";
    }
    viewProps() {
      var _a, _b, _c, _d;
      return {
        src: (_a = this.props.src) != null ? _a : null,
        autoplay: !!this.props.autoplay,
        loop: !!this.props.loop,
        muted: !!this.props.muted,
        controls: this.props.controls !== false,
        poster: (_b = this.props.poster) != null ? _b : null,
        tracks: (_c = this.props.tracks) != null ? _c : null,
        fit: (_d = this.props.fit) != null ? _d : "contain"
      };
    }
    handleViewEvent(event) {
      var _a, _b;
      if (event.type === "load" && event.value && typeof event.value === "object") {
        const vw = Number(event.value.width);
        const vh = Number(event.value.height);
        if (vw > 0 && vh > 0) {
          const next = vw / vh;
          if (this.aspect == null || Math.abs(this.aspect - next) > 1e-3) {
            this.aspect = next;
            this.markNeedsLayout();
          }
        }
      }
      (_b = (_a = this.props).onEvent) == null ? void 0 : _b.call(_a, event);
    }
  };
  var RenderWeb = class extends RenderObject {
    performLayout(c) {
      var _a, _b;
      const w2 = (_a = this.props.width) != null ? _a : null;
      const h = (_b = this.props.height) != null ? _b : null;
      this.size = constrain(c, {
        width: w2 != null ? w2 : Number.isFinite(c.maxWidth) ? c.maxWidth : 300,
        height: h != null ? h : Number.isFinite(c.maxHeight) ? c.maxHeight : 150
      });
    }
    viewKind() {
      return "web";
    }
    viewProps() {
      var _a, _b;
      return { src: (_a = this.props.src) != null ? _a : null, html: (_b = this.props.html) != null ? _b : null, javascript: this.props.javascript !== false, clip: true };
    }
    handleViewEvent(event) {
      var _a, _b;
      (_b = (_a = this.props).onEvent) == null ? void 0 : _b.call(_a, event);
    }
  };
  var RenderNative = class extends RenderObject {
    performLayout(c) {
      var _a, _b, _c, _d, _e, _f, _g, _h, _i;
      const measured = (_e = (_d = (_a = this.owner) == null ? void 0 : (_b = _a.platform).measureControl) == null ? void 0 : _d.call(_b, { kind: "native", props: { component: this.props.component, componentProps: (_c = this.props.componentProps) != null ? _c : {} } }, c.maxWidth)) != null ? _e : null;
      const w2 = (_g = (_f = this.props.width) != null ? _f : measured == null ? void 0 : measured.width) != null ? _g : Number.isFinite(c.maxWidth) ? c.maxWidth : 0;
      const h = (_i = (_h = this.props.height) != null ? _h : measured == null ? void 0 : measured.height) != null ? _i : Number.isFinite(c.maxHeight) ? c.maxHeight : 0;
      this.size = constrain(c, { width: w2, height: h });
      for (const child of this.children) {
        child.layout({ minWidth: 0, maxWidth: this.size.width, minHeight: 0, maxHeight: this.size.height });
        child.offset = { x: 0, y: 0 };
      }
    }
    viewKind() {
      return "native";
    }
    viewProps() {
      var _a, _b;
      return { component: (_a = this.props.component) != null ? _a : null, componentProps: (_b = this.props.componentProps) != null ? _b : {} };
    }
    handleViewEvent(event) {
      var _a, _b;
      (_b = (_a = this.props).onEvent) == null ? void 0 : _b.call(_a, event);
    }
  };
  var RenderGesture = class extends RenderProxy {
    constructor() {
      super(...arguments);
      /** A Dismissible that was swiped away collapses to nothing. */
      this.dismissed = false;
      this.collapse = 1;
    }
    performLayout(c) {
      super.performLayout(c);
      if (this.dismissed) {
        this.size = { width: this.size.width, height: this.size.height * this.collapse };
      }
    }
    viewKind() {
      return "view";
    }
    viewProps() {
      var _a, _b, _c, _d, _e, _f, _g;
      const gestures = (_a = this.props.gestures) != null ? _a : [];
      return {
        gestures: gestures.length ? gestures : null,
        ripple: (_b = this.props.ripple) != null ? _b : null,
        cursor: (_c = this.props.cursor) != null ? _c : null,
        tooltip: (_d = this.props.tooltip) != null ? _d : null,
        focusable: this.props.focusable ? true : void 0,
        semanticsLabel: (_e = this.props.semanticsLabel) != null ? _e : null,
        role: (_f = this.props.role) != null ? _f : null,
        dragData: this.props.dragData,
        dismissDirection: (_g = this.props.dismissDirection) != null ? _g : null,
        hidden: this.dismissed && this.collapse <= 0 ? true : void 0,
        clip: this.dismissed ? true : void 0
      };
    }
    handleViewEvent(event) {
      var _a, _b;
      (_b = (_a = this.props).onEvent) == null ? void 0 : _b.call(_a, event, this);
    }
  };

  // core/src/render/paint/text.ts
  var RenderText = class extends RenderObject {
    constructor() {
      super(...arguments);
      this.metrics = null;
      this.spec = null;
    }
    /** The nearest DefaultTextStyle chain merged outermost-first. */
    inheritedStyle() {
      const chain = [];
      let node = this.parent;
      while (node) {
        if (node instanceof RenderDefaultTextStyle) chain.push(node);
        node = node.parent;
      }
      let style = {};
      let align2;
      let maxLines;
      let overflow;
      let softWrap;
      for (let i = chain.length - 1; i >= 0; i--) {
        const p = chain[i].props;
        style = mergeTextStyle(style, p.style);
        if (p.textAlign) align2 = p.textAlign;
        if (p.maxLines !== void 0) maxLines = p.maxLines;
        if (p.overflow) overflow = p.overflow;
        if (p.softWrap !== void 0) softWrap = p.softWrap;
      }
      return { style, align: align2, maxLines, overflow, softWrap };
    }
    buildSpec() {
      var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j, _k, _l, _m;
      const inherited = this.inheritedStyle();
      const base = mergeTextStyle(inherited.style, (_a = this.props.style) != null ? _a : null);
      const scale = (_c = (_b = this.owner) == null ? void 0 : _b.textScale) != null ? _c : 1;
      const inputs = (_e = this.props.spans) != null ? _e : [{ text: (_d = this.props.text) != null ? _d : "" }];
      const spans = inputs.map((s) => {
        var _a2, _b2;
        const style = mergeTextStyle(base, (_a2 = s.style) != null ? _a2 : null);
        const out = { text: applyTextTransform((_b2 = s.text) != null ? _b2 : "", style.textTransform), style: toSpec(style, scale) };
        if (s.link) out.link = s.link;
        return out;
      });
      const softWrap = (_g = (_f = this.props.softWrap) != null ? _f : inherited.softWrap) != null ? _g : true;
      return {
        spans,
        align: (_i = (_h = this.props.align) != null ? _h : inherited.align) != null ? _i : "start",
        maxLines: (_k = (_j = this.props.maxLines) != null ? _j : inherited.maxLines) != null ? _k : null,
        overflow: (_m = (_l = this.props.overflow) != null ? _l : inherited.overflow) != null ? _m : "clip",
        softWrap,
        selectable: !!this.props.selectable,
        direction: this.props.direction === "rtl" ? "rtl" : "ltr"
      };
    }
    measure(spec, maxWidth) {
      const owner = this.owner;
      if (!owner) {
        const size = spec.spans.reduce((s, sp) => s + sp.text.length * sp.style.fontSize * 0.5, 0);
        return { width: Math.min(size, maxWidth), height: 20, baseline: 15, lineCount: 1, didExceedMaxLines: false };
      }
      return owner.measureText(spec, maxWidth);
    }
    performLayout(c) {
      const spec = this.buildSpec();
      this.spec = spec;
      const maxWidth = spec.softWrap || spec.overflow === "ellipsis" || spec.overflow === "fade" ? c.maxWidth : INF;
      const metrics = this.measure(spec, maxWidth);
      this.metrics = metrics;
      this.size = constrain(c, { width: Math.ceil(metrics.width - 1e-3), height: Math.ceil(metrics.height - 1e-3) });
    }
    baseline() {
      var _a, _b;
      return (_b = (_a = this.metrics) == null ? void 0 : _a.baseline) != null ? _b : null;
    }
    computeMinIntrinsicWidth() {
      const spec = this.buildSpec();
      if (!spec.softWrap) return Math.ceil(this.measure(spec, INF).width);
      return Math.ceil(this.measure(spec, 0).width);
    }
    computeMaxIntrinsicWidth() {
      return Math.ceil(this.measure(this.buildSpec(), INF).width);
    }
    computeMinIntrinsicHeight(width) {
      return Math.ceil(this.measure(this.buildSpec(), width).height);
    }
    computeMaxIntrinsicHeight(width) {
      return this.computeMinIntrinsicHeight(width);
    }
    viewKind() {
      return "text";
    }
    viewProps() {
      var _a;
      const spec = (_a = this.spec) != null ? _a : this.buildSpec();
      const hasLinks = spec.spans.some((s) => s.link);
      return { text: spec, gestures: hasLinks ? ["tap"] : null };
    }
    handleViewEvent(event) {
      var _a, _b;
      if (event.type === "link" && typeof event.value === "string") (_b = (_a = this.props).onLink) == null ? void 0 : _b.call(_a, event.value);
    }
    get lastMetrics() {
      return this.metrics;
    }
  };

  // core/src/render/reconciler.ts
  var factories = {
    proxy: () => new RenderProxy(),
    padding: () => new RenderPadding(),
    safeArea: () => new RenderSafeArea(),
    fill: () => new RenderFillAxis(),
    constrained: () => new RenderConstrainedBox(),
    align: () => new RenderAlign(),
    aspectRatio: () => new RenderAspectRatio(),
    fractional: () => new RenderFractional(),
    limited: () => new RenderLimitedBox(),
    overflowBox: () => new RenderOverflowBox(),
    fitted: () => new RenderFittedBox(),
    fittedContent: () => new RenderFittedContent(),
    baseline: () => new RenderBaseline(),
    rotatedBox: () => new RenderRotatedBox(),
    intrinsicWidth: () => new RenderIntrinsicWidth(),
    intrinsicHeight: () => new RenderIntrinsicHeight(),
    offstage: () => new RenderOffstage(),
    indexedStack: () => new RenderIndexedStack(),
    flex: () => new RenderFlex(),
    flexible: () => new RenderFlexible(),
    wrap: () => new RenderWrap(),
    stack: () => new RenderStack(),
    positioned: () => new RenderPositioned(),
    grid: () => new RenderGrid(),
    imageMap: () => new RenderImageMap(),
    gridItem: () => new RenderGridItem(),
    scroll: () => new RenderScroll(),
    table: () => new RenderTable(),
    tableRow: () => new RenderTableRow(),
    tableCell: () => new RenderTableCell(),
    decorated: () => new RenderDecoratedBox(),
    opacity: () => new RenderOpacity(),
    transform: () => new RenderTransform(),
    clip: () => new RenderClip(),
    ignorePointer: () => new RenderIgnorePointer(),
    visibility: () => new RenderVisibility(),
    filter: () => new RenderFilter(),
    shaderMask: () => new RenderShaderMask(),
    defaultTextStyle: () => new RenderDefaultTextStyle(),
    text: () => new RenderText(),
    image: () => new RenderImage(),
    control: () => new RenderControl(),
    canvas: () => new RenderCanvas(),
    scene3d: () => new RenderScene3D(),
    media: () => new RenderMedia(),
    web: () => new RenderWeb(),
    native: () => new RenderNative(),
    gesture: () => new RenderGesture(),
    // animated
    animatedPadding: () => new RenderAnimatedPadding(),
    animatedAlign: () => new RenderAnimatedAlign(),
    animatedOpacity: () => new RenderAnimatedOpacity(),
    animatedTransform: () => new RenderAnimatedTransform(),
    animatedConstrained: () => new RenderAnimatedConstrained(),
    animatedDecorated: () => new RenderAnimatedDecorated(),
    animatedPositioned: () => new RenderAnimatedPositioned(),
    animatedDefaultTextStyle: () => new RenderAnimatedDefaultTextStyle(),
    animatedSize: () => new RenderAnimatedSize(),
    animatedCrossFade: () => new RenderAnimatedCrossFade(),
    animatedSwitcher: () => new RenderAnimatedSwitcher(),
    switcherSlot: () => new RenderSwitcherSlot(),
    transition: () => new RenderTransition(),
    staggered: () => new RenderStaggered(),
    staggerItem: () => new RenderStaggerItem(),
    shimmer: () => new RenderShimmer(),
    animatedGradient: () => new RenderAnimatedGradient(),
    keyframes: () => new RenderKeyframes(),
    hero: () => new RenderHero()
  };
  function canUpdate(ro, w2) {
    var _a;
    return ro.type === w2.t && ro.key === ((_a = w2.k) != null ? _a : null);
  }
  function propsEqual(a, b) {
    const ka = Object.keys(a).filter((k) => typeof a[k] !== "function");
    const kb = Object.keys(b).filter((k) => typeof b[k] !== "function");
    if (ka.length !== kb.length) return false;
    for (const k of ka) if (!deepEqual(a[k], b[k])) return false;
    return true;
  }
  function createRenderObject(w2, owner, parent) {
    var _a, _b;
    const factory = factories[w2.t];
    if (!factory) throw new Error(`Elpian: unknown render object type "${w2.t}"`);
    const ro = factory();
    ro.type = w2.t;
    ro.key = (_a = w2.k) != null ? _a : null;
    ro.parent = parent;
    ro.init(w2.p);
    ro.attach(owner);
    reconcileChildren(ro, (_b = w2.c) != null ? _b : [], owner);
    return ro;
  }
  function updateRenderObject(ro, w2, owner) {
    var _a;
    if (propsEqual(ro.props, w2.p)) {
      for (const [k, v] of Object.entries(w2.p)) if (typeof v === "function") ro.props[k] = v;
    } else {
      ro.update(w2.p);
    }
    reconcileChildren(ro, (_a = w2.c) != null ? _a : [], owner);
    return ro;
  }
  function reconcileRoot(root, w2, owner) {
    if (root && canUpdate(root, w2)) return updateRenderObject(root, w2, owner);
    root == null ? void 0 : root.detach();
    return createRenderObject(w2, owner, null);
  }
  function detachChild(ro) {
    ro.detach();
    ro.parent = null;
  }
  function reconcileChildren(parent, ws, owner) {
    if (parent instanceof RenderAnimatedSwitcher) {
      reconcileSwitcher(parent, ws, owner);
      return;
    }
    const old = parent.children;
    if (old.length === 0 && ws.length === 0) return;
    const result = new Array(ws.length);
    let oldTop = 0;
    let newTop = 0;
    let oldBottom = old.length - 1;
    let newBottom = ws.length - 1;
    while (oldTop <= oldBottom && newTop <= newBottom && canUpdate(old[oldTop], ws[newTop])) {
      result[newTop] = updateRenderObject(old[oldTop], ws[newTop], owner);
      oldTop++;
      newTop++;
    }
    while (oldTop <= oldBottom && newTop <= newBottom && canUpdate(old[oldBottom], ws[newBottom])) {
      oldBottom--;
      newBottom--;
    }
    const keyed = /* @__PURE__ */ new Map();
    for (let i = oldTop; i <= oldBottom; i++) {
      const o = old[i];
      if (o.key != null) keyed.set(o.type + "\0" + o.key, o);
      else detachChild(o);
    }
    while (newTop <= newBottom) {
      const w2 = ws[newTop];
      let match;
      if (w2.k != null) {
        const id2 = w2.t + "\0" + w2.k;
        match = keyed.get(id2);
        if (match) keyed.delete(id2);
      }
      result[newTop] = match ? updateRenderObject(match, w2, owner) : createRenderObject(w2, owner, parent);
      newTop++;
    }
    newBottom = ws.length - 1;
    oldBottom = old.length - 1;
    while (oldTop <= oldBottom && newTop <= newBottom) {
      result[newTop] = updateRenderObject(old[oldTop], ws[newTop], owner);
      oldTop++;
      newTop++;
    }
    for (const o of keyed.values()) detachChild(o);
    let changed = result.length !== old.length;
    for (let i = 0; i < result.length && !changed; i++) if (result[i] !== old[i]) changed = true;
    for (const r of result) r.parent = parent;
    parent.children = result;
    if (changed) parent.markNeedsLayout();
  }
  function reconcileSwitcher(parent, ws, owner) {
    var _a;
    const current2 = parent.children.filter((c) => !parent.outgoing.has(c));
    const active = (_a = current2[current2.length - 1]) != null ? _a : null;
    for (const extra of current2.slice(0, -1)) {
      detachChild(extra);
      parent.children = parent.children.filter((c) => c !== extra);
    }
    if (ws.length === 0) {
      if (active) parent.childRemoved(active);
      parent.markNeedsLayout();
      return;
    }
    const w2 = ws[ws.length - 1];
    if (active && canUpdate(active, w2)) {
      updateRenderObject(active, w2, owner);
      return;
    }
    const fresh = createRenderObject(w2, owner, parent);
    parent.children = [...parent.children.filter((c) => parent.outgoing.has(c)), fresh];
    if (active && parent.isMounted) parent.childReplaced(active, fresh);
    else if (active) detachChild(active);
    parent.markNeedsLayout();
  }

  // core/src/session/surface.ts
  var surfaces = /* @__PURE__ */ new Map();
  function surfaceById(id2) {
    return surfaces.get(id2);
  }
  var ElpianSurface = class {
    constructor(id2, options = {}) {
      this.id = id2;
      this.content = null;
      this.overlay = null;
      this.renderScheduled = false;
      this.disposed = false;
      this.lastViewport = "";
      /** Wraps the lowered content each render (e.g. the stream's AnimatedSwitcher). */
      this.decorate = null;
      var _a, _b, _c;
      this.document = (_a = options.document) != null ? _a : false;
      this.hostHooks = (_b = options.host) != null ? _b : {};
      const host2 = __spreadProps(__spreadValues({}, this.hostHooks), {
        invalidate: () => {
          var _a2, _b2;
          (_b2 = (_a2 = this.hostHooks).invalidate) == null ? void 0 : _b2.call(_a2);
          this.scheduleRender();
        },
        focus: (htmlId) => {
          if (this.hostHooks.focus) this.hostHooks.focus(htmlId);
          else this.focus(htmlId);
        },
        hitTestDragTarget: (x, y) => {
          var _a2, _b2, _c2;
          return (_c2 = (_b2 = (_a2 = this.hostHooks).hitTestDragTarget) == null ? void 0 : _b2.call(_a2, x, y)) != null ? _c2 : this.hitTestDragTarget(x, y);
        },
        log: (level, message) => this.hostHooks.log ? this.hostHooks.log(level, message) : platform().log(level, message)
      });
      if (options.engine) {
        this.engine = options.engine;
        this.engine.host = __spreadValues(__spreadValues({}, this.engine.host), host2);
      } else {
        this.engine = new ElpianEngine((_c = options.services) != null ? _c : new ElpianServices(id2), host2);
      }
      this.owner = new RenderOwner(id2, platform(), {});
      surfaces.set(id2, this);
      this.syncEnvironment();
    }
    get isDisposed() {
      return this.disposed;
    }
    get currentContent() {
      return this.content;
    }
    /** Replace the rendered Elpian JSON (null clears the surface). */
    setContent(json) {
      this.content = json;
      this.overlay = null;
      this.scheduleRender();
    }
    /** Show a lowered widget instead of content (loading / error states). */
    setOverlay(widget) {
      this.overlay = widget;
      this.scheduleRender();
    }
    /** Re-render on the next microtask (coalesces bursts of state changes). */
    scheduleRender() {
      if (this.renderScheduled || this.disposed) return;
      this.renderScheduled = true;
      Promise.resolve().then(() => {
        this.renderScheduled = false;
        this.renderNow();
      });
    }
    /** Lower and reconcile now; the owner commits on the next frame. */
    renderNow() {
      if (this.disposed) return;
      this.syncEnvironment();
      let widget = this.overlay;
      if (!widget && this.content) {
        try {
          const rendered = this.engine.renderFromJson(this.content);
          widget = this.document ? this.engine.wrapAsDocument(rendered, this.content) : rendered;
          if (this.decorate) widget = this.decorate(widget);
        } catch (e) {
          platform().log("error", `Elpian render error: ${e}`);
          widget = messageBox(`Render Error: ${e}`, 4294940672);
        }
      }
      if (!widget) {
        if (this.owner.root) {
          this.owner.root.detach();
          this.owner.root = null;
        }
        this.owner.requestVisualUpdate();
        return;
      }
      this.owner.root = reconcileRoot(this.owner.root, widget, this.owner);
      this.owner.requestVisualUpdate();
    }
    /** The platform reports a new size, safe area, text scale or theme. */
    viewportChanged() {
      if (this.syncEnvironment()) this.renderNow();
      else this.owner.requestVisualUpdate();
    }
    syncEnvironment() {
      const vp = platform().viewport(this.id);
      const key = JSON.stringify([vp.width, vp.height, vp.safeArea, vp.devicePixelRatio, vp.textScale, vp.darkMode]);
      if (key === this.lastViewport) return false;
      this.lastViewport = key;
      updateCssEnvironment({
        viewportWidth: vp.width,
        viewportHeight: vp.height,
        safeArea: vp.safeArea,
        devicePixelRatio: vp.devicePixelRatio
      });
      this.engine.services.stylesheets.darkMode = vp.darkMode;
      if (this.owner.textScale !== vp.textScale) {
        this.owner.textScale = vp.textScale;
        this.owner.invalidateMeasurements();
      }
      return true;
    }
    /** A native view reported an event (tap, change, scroll, load…). */
    dispatchViewEvent(event) {
      if (this.disposed) return;
      this.owner.dispatchViewEvent(event);
    }
    /** An image finished loading (or failed with 0×0). */
    imageLoaded(src, width, height) {
      this.owner.imageLoaded(src, width, height);
    }
    /** Fonts changed or text metrics are otherwise stale. */
    invalidateText() {
      this.owner.invalidateMeasurements();
    }
    /** Focus the control rendered for the element with HTML id [htmlId] (`<label for>`). */
    focus(htmlId) {
      var _a;
      let target = null;
      (_a = this.owner.root) == null ? void 0 : _a.visit((ro) => {
        if (!target && ro.props.focusId === htmlId && ro.viewId != null) target = ro;
      });
      const found = target;
      if (!found || found.viewId == null) return false;
      this.owner.compositor.command(found.viewId, "focus");
      return true;
    }
    /** The DragTarget element under a point in surface coordinates. */
    hitTestDragTarget(x, y) {
      var _a;
      let hit = null;
      (_a = this.owner.root) == null ? void 0 : _a.visit((ro) => {
        const id2 = ro.props.dragTargetId;
        if (!id2) return;
        const f = this.owner.compositor.globalFrame(ro);
        if (x >= f.x && y >= f.y && x <= f.x + f.width && y <= f.y + f.height) hit = id2;
      });
      return hit;
    }
    dispose() {
      if (this.disposed) return;
      this.disposed = true;
      surfaces.delete(this.id);
      this.owner.dispose();
      this.engine.dispose();
    }
  };
  function messageBox(message, color) {
    const tint = (26 << 24 | color & 16777215) >>> 0;
    return w("decorated", { decoration: { color: tint } }, w("padding", { padding: { top: 16, right: 16, bottom: 16, left: 16 } }, w("text", { text: message, style: { color } })));
  }
  function loadingIndicator() {
    return w(
      "align",
      { alignment: { x: 0, y: 0 } },
      w("control", { kind: "progress", view: { variant: "circular", value: null, strokeWidth: 4, colors: { indicator: M3.primary, track: null } } })
    );
  }

  // core/src/session/stream.ts
  function streamCommandFromDynamic(data) {
    if (typeof data === "string") return streamCommandFromDynamic(JSON.parse(data));
    if (!isMap(data)) throw new Error(`Unsupported stream payload type: ${data === null ? "null" : typeof data}.`);
    if ("type" in data && !("action" in data)) return { action: "setView", view: data };
    const action = data.action != null ? String(data.action) : "";
    if (!action) throw new Error('Stream command must contain a non-empty "action".');
    const map = (v) => {
      if (v == null) return null;
      if (isMap(v)) return v;
      throw new Error(`Expected a JSON object, got ${typeof v}.`);
    };
    const bool = (v) => {
      if (v == null) return null;
      if (typeof v === "boolean") return v;
      if (typeof v === "string" && ["true", "false"].includes(v.trim().toLowerCase())) return v.trim().toLowerCase() === "true";
      throw new Error(`Expected a bool, got ${typeof v}.`);
    };
    const int = (v) => {
      if (v == null) return null;
      if (typeof v === "number") return Math.trunc(v);
      if (typeof v === "string") {
        const n = parseInt(v, 10);
        return Number.isNaN(n) ? null : n;
      }
      throw new Error(`Expected an int, got ${typeof v}.`);
    };
    return {
      action,
      view: map(data.view),
      patch: map(data.patch),
      stylesheet: map(data.stylesheet),
      animate: bool(data.animate),
      animationDurationMs: int(data.animationDurationMs),
      animationCurve: data.animationCurve != null ? String(data.animationCurve) : null
    };
  }
  var CURVES = /* @__PURE__ */ new Set(["linear", "easeIn", "easeOut", "easeInOut", "fastOutSlowIn", "bounceIn", "bounceOut"]);
  var StreamSession = class {
    constructor(surfaceId, options = {}) {
      this.options = options;
      this.currentView = null;
      this.errorMessage = null;
      this.version = 0;
      this.activeDuration = 0;
      this.activeCurve = "linear";
      this.cancel = null;
      this.surface = new ElpianSurface(surfaceId, options.surface);
      if (options.initialStylesheet) this.surface.engine.loadStylesheet(options.initialStylesheet);
      this.surface.decorate = (content) => w("animatedSwitcher", { duration: this.activeDuration, curve: this.activeCurve, transitionType: "fade" }, [w("proxy", {}, content, `v${this.version}`)]);
      this.refresh();
    }
    get view() {
      return this.currentView;
    }
    /** Deliver one stream message (a command object, a bare view, or JSON text). */
    push(data) {
      var _a, _b;
      try {
        const command = streamCommandFromDynamic(data);
        (_b = (_a = this.options).onCommand) == null ? void 0 : _b.call(_a, command);
        this.apply(command);
        if (this.errorMessage != null) {
          this.errorMessage = null;
          this.refresh();
        }
      } catch (e) {
        this.error(e);
      }
    }
    error(e) {
      var _a, _b;
      this.errorMessage = String(e instanceof Error ? e.message : e);
      (_b = (_a = this.options).onError) == null ? void 0 : _b.call(_a, this.errorMessage);
      this.refresh();
    }
    done() {
      var _a, _b;
      (_b = (_a = this.options).onStreamDone) == null ? void 0 : _b.call(_a);
    }
    /**
     * Read commands from a streaming response: newline-delimited JSON, or
     * server-sent events (`data:` lines). Replaces any previous connection.
     */
    connect(request) {
      var _a;
      (_a = this.cancel) == null ? void 0 : _a.call(this);
      const fetchStream = platform().fetchStream;
      if (!fetchStream) {
        this.error("This platform cannot stream HTTP responses.");
        return;
      }
      let buffer = "";
      let sse = [];
      const line = (raw) => {
        const l = raw.replace(/\r$/, "");
        if (l.startsWith("data:")) {
          sse.push(l.substring(5).replace(/^ /, ""));
          return;
        }
        if (l === "") {
          if (sse.length) {
            const payload = sse.join("\n");
            sse = [];
            if (payload.trim()) this.push(payload);
          }
          return;
        }
        if (l.startsWith(":") || /^(event|id|retry):/.test(l)) return;
        if (l.trim()) this.push(l);
      };
      this.cancel = fetchStream(request, {
        onChunk: (text2) => {
          buffer += text2;
          let i;
          while ((i = buffer.indexOf("\n")) >= 0) {
            line(buffer.substring(0, i));
            buffer = buffer.substring(i + 1);
          }
        },
        onDone: () => {
          if (buffer) line(buffer);
          line("");
          buffer = "";
          this.done();
        },
        onError: (m) => this.error(m)
      });
    }
    apply(c) {
      var _a, _b, _c;
      const animate = (_a = c.animate) != null ? _a : false;
      const duration = c.animationDurationMs == null ? (_b = this.options.defaultAnimationDurationMs) != null ? _b : 240 : Math.max(0, Math.min(3e4, c.animationDurationMs));
      const curve = c.animationCurve && CURVES.has(c.animationCurve.trim()) ? c.animationCurve.trim() : (_c = this.options.defaultAnimationCurve) != null ? _c : "easeInOut";
      const setActive = () => {
        this.activeDuration = animate ? duration : 0;
        this.activeCurve = curve;
      };
      switch (c.action) {
        case "setView":
          if (!c.view) throw new Error('setView requires "view" object.');
          setActive();
          this.update(__spreadValues({}, c.view));
          return;
        case "patchView":
          if (!c.patch) throw new Error('patchView requires "patch" object.');
          if (!this.currentView) throw new Error("patchView received before any setView command.");
          setActive();
          this.update(deepMerge(this.currentView, c.patch));
          return;
        case "setStylesheet":
          if (!c.stylesheet) throw new Error('setStylesheet requires "stylesheet" object.');
          this.surface.engine.loadStylesheet(c.stylesheet);
          setActive();
          this.refresh();
          return;
        case "renderWithStylesheet":
          if (!c.stylesheet || !c.view) throw new Error('renderWithStylesheet requires both "stylesheet" and "view".');
          this.surface.engine.loadStylesheet(c.stylesheet);
          setActive();
          this.update(__spreadValues({}, c.view));
          return;
        case "clear":
          this.currentView = null;
          this.version++;
          setActive();
          this.refresh();
          return;
        default:
          throw new Error(`Unknown stream action: ${c.action}.`);
      }
    }
    update(view) {
      this.currentView = view;
      this.version++;
      this.refresh();
    }
    refresh() {
      if (this.errorMessage != null) {
        this.surface.setOverlay(messageBox(`Stream Error: ${this.errorMessage}`, 4294198070));
        return;
      }
      this.surface.setContent(this.currentView);
    }
    dispose() {
      var _a;
      (_a = this.cancel) == null ? void 0 : _a.call(this);
      this.cancel = null;
      this.surface.dispose();
    }
  };

  // core/src/fullstack/server.ts
  var _ElpianNetPolicy = class _ElpianNetPolicy {
    constructor(mode, allowlist) {
      this.mode = mode;
      this.allowlist = allowlist;
    }
    static brokered(allowlist) {
      return new _ElpianNetPolicy("brokered", [...allowlist]);
    }
    static fromManifest(value) {
      if (value === "open") return _ElpianNetPolicy.open;
      if (isMap(value)) return _ElpianNetPolicy.brokered(Array.isArray(value.allow) ? value.allow.filter((x) => typeof x === "string") : []);
      return _ElpianNetPolicy.closed;
    }
    allows(url) {
      if (this.mode === "closed") return false;
      if (this.mode === "open") return true;
      const host2 = hostOf(url);
      if (!host2) return false;
      return this.allowlist.some((e) => matches(e.toLowerCase(), host2.toLowerCase()));
    }
  };
  _ElpianNetPolicy.closed = new _ElpianNetPolicy("closed", []);
  _ElpianNetPolicy.open = new _ElpianNetPolicy("open", []);
  var ElpianNetPolicy = _ElpianNetPolicy;
  function matches(entry, host2) {
    if (entry.startsWith("*.")) {
      const suffix = entry.substring(2);
      return host2 !== suffix && host2.length > suffix.length && host2.endsWith(suffix) && host2[host2.length - suffix.length - 1] === ".";
    }
    return host2 === entry;
  }
  function hostOf(url) {
    const m = /^[a-zA-Z][\w+.-]*:\/\/(?:[^@/?#]*@)?(\[[^\]]+\]|[^:/?#]+)/.exec(url);
    return m ? m[1] : null;
  }
  var ElpianServerClient = class {
    constructor(baseUrl, appId, netPolicy = ElpianNetPolicy.closed, authorization = null, timeoutMs = 15e3) {
      this.baseUrl = baseUrl;
      this.appId = appId;
      this.netPolicy = netPolicy;
      this.authorization = authorization;
      this.closed = false;
      this.cancels = /* @__PURE__ */ new Set();
      this.timeoutMs = timeoutMs;
    }
    /** Host handlers for a mini app runtime: `server.call`, `server.render`, `net.fetch`. */
    get hostHandlers() {
      return {
        "server.call": (_a, p) => this.invoke(p, false),
        "server.render": (_a, p) => this.invoke(p, true),
        "net.fetch": (_a, p) => this.clientFetch(p)
      };
    }
    headers() {
      return __spreadValues({ "content-type": "application/json" }, this.authorization ? { authorization: this.authorization } : {});
    }
    async post(url, body) {
      const fetch = platform().fetch;
      if (!fetch) throw new Error("no HTTP client");
      return fetch({ url, method: "POST", headers: this.headers(), body: JSON.stringify(body), timeoutMs: this.timeoutMs });
    }
    async invoke(payload, render) {
      var _a, _b, _c;
      const args = positional(payload);
      const name = args[0];
      if (typeof name !== "string" || !name) return "null";
      const body = args.length > 1 ? args[1] : {};
      const path = render ? "render" : "fn";
      const url = `${this.baseUrl}/apps/${encodeURIComponent(this.appId)}/${path}/${encodeURIComponent(name)}`;
      try {
        const res = await this.post(url, body);
        if (res.status !== 200) return typedError((_a = errorMessage(res.body)) != null ? _a : "the call failed");
        const decoded = JSON.parse(res.body);
        if (isMap(decoded) && decoded.ok === true) return JSON.stringify((_b = decoded.result) != null ? _b : null);
        return typedError((_c = errorMessage(res.body)) != null ? _c : "the call failed");
      } catch (e) {
        const text2 = String(e);
        if (/timed? ?out/i.test(text2)) return typedError("the server did not answer in time");
        if (/network|connect|resolve|unreachable/i.test(text2)) return typedError("the server could not be reached");
        platform().log("warn", `ElpianServerClient: ${this.appId}/${path} failed: ${e}`);
        return typedError("the call failed");
      }
    }
    async clientFetch(payload) {
      var _a;
      const url = positional(payload)[0];
      if (typeof url !== "string") return "null";
      if (!this.netPolicy.allows(url)) return typedError("the request was not permitted");
      try {
        const res = await this.post(`${this.baseUrl}/apps/${this.appId}/proxy`, { url });
        if (res.status !== 200) return typedError("the request was not permitted");
        const decoded = JSON.parse(res.body);
        if (isMap(decoded) && decoded.ok === true) return JSON.stringify((_a = decoded.result) != null ? _a : null);
      } catch (e) {
      }
      return typedError("the request was not permitted");
    }
    async renderComponent(name, args) {
      var _a;
      const raw = await this.invoke(JSON.stringify([name, args]), true);
      try {
        const d = JSON.parse(raw);
        if (isMap(d) && d.error != null) return { error: isMap(d.error) ? String((_a = d.error.message) != null ? _a : "the call failed") : String(d.error) };
        if (isMap(d)) return { payload: d };
      } catch (e) {
      }
      return { error: "the server returned no payload" };
    }
    async callAction(name, args) {
      var _a;
      const raw = await this.invoke(JSON.stringify([name, args]), false);
      try {
        const d = JSON.parse(raw);
        if (isMap(d) && d.error != null) return { error: isMap(d.error) ? String((_a = d.error.message) != null ? _a : "the call failed") : String(d.error) };
        return { result: d };
      } catch (e) {
        return { error: "the call failed" };
      }
    }
    /**
     * Stream a component: newline-delimited frames, each a stream command
     * (`{"action":"error"}` frames surface as errors). Returns a canceller.
     */
    streamComponent(name, args, sink) {
      const fetchStream = platform().fetchStream;
      if (!fetchStream || this.closed) {
        sink.onError("the stream could not be opened");
        sink.onDone();
        return () => {
        };
      }
      let buffer = "";
      let finished = false;
      const finish = () => {
        if (finished) return;
        finished = true;
        this.cancels.delete(cancel);
        sink.onDone();
      };
      const emit = (line) => {
        var _a;
        try {
          const d = JSON.parse(line);
          if (isMap(d) && d.action === "error") sink.onError(String((_a = d.message) != null ? _a : "the stream failed"));
          else sink.onFrame(d);
        } catch (e) {
          platform().log("debug", `ElpianServerClient: ${this.appId} dropped an unparseable stream line`);
        }
      };
      const cancelStream = fetchStream(
        { url: `${this.baseUrl}/apps/${encodeURIComponent(this.appId)}/stream/${encodeURIComponent(name)}`, method: "POST", headers: this.headers(), body: JSON.stringify(args), timeoutMs: this.timeoutMs },
        {
          onChunk: (text2) => {
            buffer += text2;
            let i;
            while ((i = buffer.indexOf("\n")) >= 0) {
              const line = buffer.substring(0, i).trim();
              buffer = buffer.substring(i + 1);
              if (line) emit(line);
            }
          },
          onDone: () => {
            const tail = buffer.trim();
            if (tail) emit(tail);
            finish();
          },
          onError: (m) => {
            sink.onError(/time/i.test(m) ? "the stream timed out" : /status|HTTP/i.test(m) ? "the stream could not be opened" : "the stream failed");
            finish();
          }
        }
      );
      const cancel = () => {
        cancelStream();
        finish();
      };
      this.cancels.add(cancel);
      return cancel;
    }
    /** Show a streamed component on a surface (ElpianStreamWidget over streamComponent). */
    mountStream(surfaceId, name, args, options = {}) {
      const session = new StreamSession(surfaceId, options);
      const cancel = this.streamComponent(name, args, { onFrame: (f) => session.push(f), onError: (m) => session.error(m), onDone: () => session.done() });
      const dispose = session.dispose.bind(session);
      session.dispose = () => {
        cancel();
        dispose();
      };
      return session;
    }
    close() {
      this.closed = true;
      for (const c of [...this.cancels]) c();
    }
  };
  function positional(payload) {
    try {
      const d = JSON.parse(payload);
      return Array.isArray(d) ? d : [d];
    } catch (e) {
      return [];
    }
  }
  function errorMessage(body) {
    try {
      const d = JSON.parse(body);
      if (isMap(d) && typeof d.error === "string") return d.error;
    } catch (e) {
    }
    return null;
  }
  function typedError(message) {
    return JSON.stringify({ error: { code: "unavailable", message } });
  }
  var ServerComponentSession = class {
    constructor(surfaceId, options) {
      this.options = options;
      this.payload = null;
      this.error = null;
      this.loading = true;
      this.generation = 0;
      this.timer = null;
      this.disposed = false;
      this.stylesheetKey = null;
      this.surface = new ElpianSurface(surfaceId, options.surface);
      this.registerIslands();
      void this.fetch();
      this.scheduleRevalidation();
    }
    registerIslands() {
      var _a, _b;
      const engine = this.surface.engine;
      for (const [name, build] of Object.entries((_a = this.options.islandBuilders) != null ? _a : {})) {
        const builder = (node, children) => build(__spreadValues(__spreadValues({}, node.props), children.length ? { "#children": children } : {}));
        engine.registerWidget(name, builder);
      }
      for (const [name, component] of Object.entries((_b = this.options.nativeIslands) != null ? _b : {})) {
        engine.registerWidget(
          name,
          (node, children) => {
            var _a2, _b2, _c, _d;
            return w("native", { component, componentProps: __spreadValues({}, node.props), width: (_b2 = (_a2 = node.style) == null ? void 0 : _a2.width) != null ? _b2 : null, height: (_d = (_c = node.style) == null ? void 0 : _c.height) != null ? _d : null, onEvent: () => {
            } }, children);
          }
        );
      }
    }
    /** Change name/args/revalidation (didUpdateWidget). */
    update(next) {
      var _a;
      const prev = this.options;
      this.options = __spreadValues(__spreadValues({}, prev), next);
      this.registerIslands();
      if (next.name != null && next.name !== prev.name || next.args != null && !sameArgs((_a = prev.args) != null ? _a : {}, next.args)) void this.fetch();
      if (next.revalidateMs !== void 0 && next.revalidateMs !== prev.revalidateMs) this.scheduleRevalidation();
    }
    scheduleRevalidation() {
      if (this.timer != null) platform().clearTimeout(this.timer);
      this.timer = null;
      const interval2 = this.options.revalidateMs;
      if (!interval2 || interval2 <= 0) return;
      const tick = () => {
        if (this.disposed) return;
        this.timer = platform().setTimeout(tick, interval2);
        void this.fetch();
      };
      this.timer = platform().setTimeout(tick, interval2);
    }
    async fetch() {
      var _a, _b;
      const gen = ++this.generation;
      if (this.payload == null) {
        this.loading = true;
        this.paint();
      }
      const result = await this.options.client.renderComponent(this.options.name, (_a = this.options.args) != null ? _a : {});
      if (this.disposed || gen !== this.generation) return;
      this.loading = false;
      if (result.error != null) this.error = result.error;
      else {
        this.error = null;
        this.payload = (_b = result.payload) != null ? _b : null;
      }
      this.paint();
    }
    /** Islands the payload declares that no builder handles. */
    unresolvedIslands() {
      var _a;
      const declared = (_a = this.payload) == null ? void 0 : _a.clientComponents;
      if (!isMap(declared)) return [];
      return Object.keys(declared).filter((k) => {
        var _a2, _b;
        return !(k in ((_a2 = this.options.islandBuilders) != null ? _a2 : {})) && !(k in ((_b = this.options.nativeIslands) != null ? _b : {}));
      });
    }
    paint() {
      var _a;
      if (this.disposed) return;
      const s = this.surface;
      const errorBox = (m) => {
        var _a2, _b, _c;
        return (_c = (_b = (_a2 = this.options).errorBuilder) == null ? void 0 : _b.call(_a2, m)) != null ? _c : w("padding", { padding: { top: 12, right: 12, bottom: 12, left: 12 } }, w("text", { text: m, style: { color: 4289930782 } }));
      };
      const payload = this.payload;
      if (!payload) {
        if (this.error != null) s.setOverlay(errorBox(this.error));
        else if (this.loading) s.setOverlay((_a = this.options.pending) != null ? _a : loadingIndicator());
        else s.setContent(null);
        return;
      }
      if (!isMap(payload.component)) {
        s.setOverlay(errorBox("the server component returned no component tree"));
        return;
      }
      if (isMap(payload.stylesheet)) {
        const key = stableKey(payload.stylesheet);
        if (key !== this.stylesheetKey) {
          this.stylesheetKey = key;
          s.engine.loadStylesheet(payload.stylesheet);
        }
      }
      s.setContent(payload.component);
    }
    dispose() {
      this.disposed = true;
      if (this.timer != null) platform().clearTimeout(this.timer);
      this.surface.dispose();
    }
  };
  function sameArgs(a, b) {
    const ka = Object.keys(a);
    if (ka.length !== Object.keys(b).length) return false;
    return ka.every((k) => b[k] === a[k]);
  }

  // core/src/scope/scope.ts
  var ScopeContract = {
    type: "Scope",
    renderTokenProp: "__scopeRenderToken",
    wrapperKeySuffix: "__scope",
    isScopeNode(node) {
      return isMap(node) && String(node.type) === "Scope";
    }
  };
  var tokenCounter = 0;
  var ScopePatch = {
    normalizeKey(scopeKey) {
      if (scopeKey == null) return null;
      const k = String(scopeKey).trim();
      return k === "" || k === "null" ? null : k;
    },
    ensureKey(json, key) {
      if (json.key != null && String(json.key) !== "") return json;
      return __spreadProps(__spreadValues({}, json), { key });
    },
    markRerender(json) {
      markTokensInPlace(json);
      return json;
    },
    replaceByKey(tree, targetKey, replacement) {
      return replace(tree, targetKey, replacement, []);
    },
    /** Patch [tree]; falls back to the whole [view] when the key is absent. */
    apply(tree, view, scopeKey) {
      const key = ScopePatch.normalizeKey(scopeKey);
      if (key == null || tree == null) return ScopePatch.markRerender(view);
      const replacement = ScopePatch.markRerender(ScopePatch.ensureKey(view, key));
      return ScopePatch.replaceByKey(tree, key, replacement) ? tree : view;
    },
    /** Like [apply], but returns null (drop) when the key is absent. */
    applyBounded(tree, view, scopeKey) {
      const key = ScopePatch.normalizeKey(scopeKey);
      if (key == null || tree == null) return ScopePatch.markRerender(view);
      const replacement = ScopePatch.markRerender(ScopePatch.ensureKey(view, key));
      return ScopePatch.replaceByKey(tree, key, replacement) ? tree : null;
    }
  };
  function replace(node, targetKey, replacement, scopeAncestors) {
    if (node.key != null && String(node.key) === targetKey) {
      for (const k of Object.keys(node)) delete node[k];
      Object.assign(node, replacement);
      markNodes(scopeAncestors);
      return true;
    }
    const isScope = ScopeContract.isScopeNode(node);
    if (isScope) scopeAncestors.push(node);
    const children = node.children;
    if (Array.isArray(children)) {
      for (const child of children) {
        if (!isMap(child)) continue;
        if (replace(child, targetKey, replacement, scopeAncestors)) {
          if (isScope) scopeAncestors.pop();
          return true;
        }
      }
    }
    if (isScope) scopeAncestors.pop();
    return false;
  }
  function markNodes(scopeNodes) {
    for (const n of scopeNodes) n.props = __spreadProps(__spreadValues({}, isMap(n.props) ? n.props : {}), { [ScopeContract.renderTokenProp]: ++tokenCounter });
  }
  function markTokensInPlace(node) {
    if (!isMap(node)) return;
    if (ScopeContract.isScopeNode(node)) node.props = __spreadProps(__spreadValues({}, isMap(node.props) ? node.props : {}), { [ScopeContract.renderTokenProp]: ++tokenCounter });
    if (Array.isArray(node.children)) for (const c of node.children) markTokensInPlace(c);
  }

  // core/src/util/typed.ts
  function makeResponse(type, value) {
    return JSON.stringify({ type, data: { value } });
  }
  var NULL_RESPONSE = makeResponse("null", null);
  var OK_RESPONSE = makeResponse("i16", 0);
  var ONE_RESPONSE = makeResponse("i16", 1);
  function toTypedVmValue(value) {
    if (value === null || value === void 0) return { type: "null", data: { value: null } };
    if (typeof value === "boolean") return { type: "bool", data: { value } };
    if (typeof value === "number") {
      if (Number.isInteger(value) && Number.isSafeInteger(value)) {
        return { type: "i64", data: { value } };
      }
      return { type: "f64", data: { value } };
    }
    if (typeof value === "string") return { type: "string", data: { value } };
    if (Array.isArray(value)) {
      return { type: "array", data: { value: value.map(toTypedVmValue) } };
    }
    if (typeof value === "object") {
      const out = {};
      for (const [k, v] of Object.entries(value)) {
        out[k] = toTypedVmValue(v);
      }
      return { type: "object", data: { value: out } };
    }
    return { type: "string", data: { value: String(value) } };
  }

  // core/src/vm/host-api-catalog.ts
  var coreApiNames = /* @__PURE__ */ new Set([
    "log",
    "println",
    "stringify",
    "render",
    "updateApp",
    "env.get"
  ]);
  var timerApiNames = /* @__PURE__ */ new Set([
    "setTimeout",
    "setInterval",
    "clearTimeout",
    "clearInterval"
  ]);
  var domApiNames = /* @__PURE__ */ new Set([
    "dom.getElementById",
    "dom.getElementsByClassName",
    "dom.getElementsByTagName",
    "dom.querySelector",
    "dom.querySelectorAll",
    "dom.createElement",
    "dom.removeElement",
    "dom.clear",
    "dom.setTextContent",
    "dom.setInnerHtml",
    "dom.setAttribute",
    "dom.getAttribute",
    "dom.removeAttribute",
    "dom.hasAttribute",
    "dom.setStyle",
    "dom.getStyle",
    "dom.setStyleObject",
    "dom.addClass",
    "dom.removeClass",
    "dom.hasClass",
    "dom.toggleClass",
    "dom.appendChild",
    "dom.insertBefore",
    "dom.removeChild",
    "dom.replaceChild",
    "dom.addEventListener",
    "dom.removeEventListener",
    "dom.dispatchEvent",
    "dom.toJson",
    "dom.getAllElements"
  ]);
  var canvasApiNames = /* @__PURE__ */ new Set([
    "canvas.ctx.create",
    "canvas.ctx.dispose",
    "canvas.ctx.clear",
    "canvas.ctx.setSize",
    "canvas.ctx.addCommand",
    "canvas.ctx.addCommands",
    "canvas.addCommand",
    "canvas.addCommands",
    "canvas.clear",
    "canvas.getCommands",
    "canvas.beginPath",
    "canvas.closePath",
    "canvas.moveTo",
    "canvas.lineTo",
    "canvas.quadraticCurveTo",
    "canvas.bezierCurveTo",
    "canvas.arc",
    "canvas.arcTo",
    "canvas.ellipse",
    "canvas.rect",
    "canvas.roundRect",
    "canvas.circle",
    "canvas.fillRect",
    "canvas.strokeRect",
    "canvas.clearRect",
    "canvas.fillCircle",
    "canvas.strokeCircle",
    "canvas.fillPolygon",
    "canvas.strokePolygon",
    "canvas.fillText",
    "canvas.strokeText",
    "canvas.drawImage",
    "canvas.drawImageRect",
    "canvas.fill",
    "canvas.stroke",
    "canvas.clip",
    "canvas.save",
    "canvas.restore",
    "canvas.translate",
    "canvas.rotate",
    "canvas.scale",
    "canvas.transform",
    "canvas.setTransform",
    "canvas.resetTransform",
    "canvas.setFillStyle",
    "canvas.setStrokeStyle",
    "canvas.setLineWidth",
    "canvas.setLineCap",
    "canvas.setLineJoin",
    "canvas.setMiterLimit",
    "canvas.setLineDash",
    "canvas.setLineDashOffset",
    "canvas.setShadowBlur",
    "canvas.setShadowColor",
    "canvas.setShadowOffsetX",
    "canvas.setShadowOffsetY",
    "canvas.setGlobalAlpha",
    "canvas.setGlobalCompositeOperation",
    "canvas.setFont",
    "canvas.setTextAlign",
    "canvas.setTextBaseline",
    "canvas.createLinearGradient",
    "canvas.createRadialGradient",
    "canvas.addColorStop",
    "canvas.createPattern",
    "canvas.putImageData",
    "canvas.getImageData",
    "canvas.createImageData"
  ]);
  var netApiNames = /* @__PURE__ */ new Set([
    "net.fetch",
    "net.open",
    "net.send",
    "net.recv",
    "net.close"
  ]);
  var fsApiNames = /* @__PURE__ */ new Set([
    "fs.read",
    "fs.write",
    "fs.append",
    "fs.delete",
    "fs.list",
    "fs.exists",
    "fs.stat",
    "fs.mkdir"
  ]);
  var gpuApiNames = /* @__PURE__ */ new Set([
    "gpu.submit",
    "gpu.writeBuffer",
    "gpu.writeTexture",
    "gpu.readBuffer",
    "gpu.surfaceInfo",
    "gpu.define",
    "gpu.undefine"
  ]);
  var timeApiNames = /* @__PURE__ */ new Set([
    "time.now",
    "time.monotonic"
  ]);
  var randomApiNames = /* @__PURE__ */ new Set([
    "random.next",
    "random.bytes"
  ]);
  var taskApiNames = /* @__PURE__ */ new Set([
    "task.init",
    "task.spawn",
    "task.poll",
    "task.join",
    "task.relay",
    "task.stats"
  ]);
  var hostMessagingApiNames = /* @__PURE__ */ new Set([
    "host.send",
    "host.request"
  ]);
  var surfaceApiNames = /* @__PURE__ */ new Set([
    "godot.op",
    "godot.batch",
    "flutter.op",
    "flutter.batch"
  ]);
  var serverApiNames = /* @__PURE__ */ new Set([
    "server.call",
    "server.render",
    "stream.emit"
  ]);
  var stateApiNames = /* @__PURE__ */ new Set([
    "kv.get",
    "kv.set",
    "kv.delete",
    "kv.list",
    "secret.get",
    "cache.revalidate",
    "ctx.user"
  ]);
  var vmApiNames = /* @__PURE__ */ new Set([
    "vm.import",
    "vm.spawn",
    "vm.pause",
    "vm.resume",
    "vm.terminate",
    "vm.state",
    "vm.usage",
    "vm.usageTree",
    "vm.limits",
    "vm.setLimits",
    "vm.permissions",
    "vm.setPermission",
    "vm.list",
    "vm.info",
    "vm.send",
    "vm.grant"
  ]);
  var allHostApiNames = /* @__PURE__ */ new Set([
    ...coreApiNames,
    ...timerApiNames,
    ...domApiNames,
    ...canvasApiNames,
    ...netApiNames,
    ...fsApiNames,
    ...gpuApiNames,
    ...timeApiNames,
    ...randomApiNames,
    ...taskApiNames,
    ...hostMessagingApiNames,
    ...surfaceApiNames,
    ...serverApiNames,
    ...stateApiNames,
    ...vmApiNames
  ]);
  var capabilityOf = {
    "cache.revalidate": "state",
    "canvas.addColorStop": "canvas",
    "canvas.addCommand": "canvas",
    "canvas.addCommands": "canvas",
    "canvas.arc": "canvas",
    "canvas.arcTo": "canvas",
    "canvas.beginPath": "canvas",
    "canvas.bezierCurveTo": "canvas",
    "canvas.circle": "canvas",
    "canvas.clear": "canvas",
    "canvas.clearRect": "canvas",
    "canvas.clip": "canvas",
    "canvas.closePath": "canvas",
    "canvas.createImageData": "canvas",
    "canvas.createLinearGradient": "canvas",
    "canvas.createPattern": "canvas",
    "canvas.createRadialGradient": "canvas",
    "canvas.ctx.addCommand": "canvas",
    "canvas.ctx.addCommands": "canvas",
    "canvas.ctx.clear": "canvas",
    "canvas.ctx.create": "canvas",
    "canvas.ctx.dispose": "canvas",
    "canvas.ctx.setSize": "canvas",
    "canvas.drawImage": "canvas",
    "canvas.drawImageRect": "canvas",
    "canvas.ellipse": "canvas",
    "canvas.fill": "canvas",
    "canvas.fillCircle": "canvas",
    "canvas.fillPolygon": "canvas",
    "canvas.fillRect": "canvas",
    "canvas.fillText": "canvas",
    "canvas.getCommands": "canvas",
    "canvas.getImageData": "canvas",
    "canvas.lineTo": "canvas",
    "canvas.moveTo": "canvas",
    "canvas.putImageData": "canvas",
    "canvas.quadraticCurveTo": "canvas",
    "canvas.rect": "canvas",
    "canvas.resetTransform": "canvas",
    "canvas.restore": "canvas",
    "canvas.rotate": "canvas",
    "canvas.roundRect": "canvas",
    "canvas.save": "canvas",
    "canvas.scale": "canvas",
    "canvas.setFillStyle": "canvas",
    "canvas.setFont": "canvas",
    "canvas.setGlobalAlpha": "canvas",
    "canvas.setGlobalCompositeOperation": "canvas",
    "canvas.setLineCap": "canvas",
    "canvas.setLineDash": "canvas",
    "canvas.setLineDashOffset": "canvas",
    "canvas.setLineJoin": "canvas",
    "canvas.setLineWidth": "canvas",
    "canvas.setMiterLimit": "canvas",
    "canvas.setShadowBlur": "canvas",
    "canvas.setShadowColor": "canvas",
    "canvas.setShadowOffsetX": "canvas",
    "canvas.setShadowOffsetY": "canvas",
    "canvas.setStrokeStyle": "canvas",
    "canvas.setTextAlign": "canvas",
    "canvas.setTextBaseline": "canvas",
    "canvas.setTransform": "canvas",
    "canvas.stroke": "canvas",
    "canvas.strokeCircle": "canvas",
    "canvas.strokePolygon": "canvas",
    "canvas.strokeRect": "canvas",
    "canvas.strokeText": "canvas",
    "canvas.transform": "canvas",
    "canvas.translate": "canvas",
    "clearInterval": "timers",
    "clearTimeout": "timers",
    "ctx.user": "state",
    "dom.addClass": "dom",
    "dom.addEventListener": "dom",
    "dom.appendChild": "dom",
    "dom.clear": "dom",
    "dom.createElement": "dom",
    "dom.dispatchEvent": "dom",
    "dom.getAllElements": "dom",
    "dom.getAttribute": "dom",
    "dom.getElementById": "dom",
    "dom.getElementsByClassName": "dom",
    "dom.getElementsByTagName": "dom",
    "dom.getStyle": "dom",
    "dom.hasAttribute": "dom",
    "dom.hasClass": "dom",
    "dom.insertBefore": "dom",
    "dom.querySelector": "dom",
    "dom.querySelectorAll": "dom",
    "dom.removeAttribute": "dom",
    "dom.removeChild": "dom",
    "dom.removeClass": "dom",
    "dom.removeElement": "dom",
    "dom.removeEventListener": "dom",
    "dom.replaceChild": "dom",
    "dom.setAttribute": "dom",
    "dom.setInnerHtml": "dom",
    "dom.setStyle": "dom",
    "dom.setStyleObject": "dom",
    "dom.setTextContent": "dom",
    "dom.toJson": "dom",
    "dom.toggleClass": "dom",
    "env.get": "environment",
    "flutter.batch": "surface",
    "flutter.op": "surface",
    "fs.append": "storage",
    "fs.delete": "storage",
    "fs.exists": "storage",
    "fs.list": "storage",
    "fs.mkdir": "storage",
    "fs.read": "storage",
    "fs.stat": "storage",
    "fs.write": "storage",
    "godot.batch": "surface",
    "godot.op": "surface",
    "gpu.define": "gpu",
    "gpu.readBuffer": "gpu",
    "gpu.submit": "gpu",
    "gpu.surfaceInfo": "gpu",
    "gpu.undefine": "gpu",
    "gpu.writeBuffer": "gpu",
    "gpu.writeTexture": "gpu",
    "host.request": "host_messaging",
    "host.send": "host_messaging",
    "kv.delete": "state",
    "kv.get": "state",
    "kv.list": "state",
    "kv.set": "state",
    "log": "logging",
    "net.close": "network",
    "net.fetch": "network",
    "net.open": "network",
    "net.recv": "network",
    "net.send": "network",
    "println": "logging",
    "random.bytes": "randomness",
    "random.next": "randomness",
    "render": "render",
    "secret.get": "state",
    "server.call": "server_call",
    "server.render": "server_call",
    "setInterval": "timers",
    "setTimeout": "timers",
    "stream.emit": "server_call",
    "stringify": "other",
    "task.init": "tasks",
    "task.join": "tasks",
    "task.poll": "tasks",
    "task.relay": "tasks",
    "task.spawn": "tasks",
    "task.stats": "tasks",
    "time.monotonic": "clock",
    "time.now": "clock",
    "updateApp": "render",
    "vm.grant": "vm_manage",
    "vm.import": "module_import",
    "vm.info": "vm_manage",
    "vm.limits": "vm_manage",
    "vm.list": "vm_manage",
    "vm.pause": "vm_manage",
    "vm.permissions": "vm_manage",
    "vm.resume": "vm_manage",
    "vm.send": "vm_manage",
    "vm.setLimits": "vm_manage",
    "vm.setPermission": "vm_manage",
    "vm.spawn": "vm_manage",
    "vm.state": "vm_manage",
    "vm.terminate": "vm_manage",
    "vm.usage": "vm_manage",
    "vm.usageTree": "vm_manage"
  };
  function capabilityFor(apiName) {
    return Object.prototype.hasOwnProperty.call(capabilityOf, apiName) ? capabilityOf[apiName] : "other";
  }

  // core/src/host/host-handler.ts
  var HostHandler = class {
    constructor(services, options = {}) {
      this.services = services;
      this.options = options;
    }
    get dom() {
      return this.services.dom;
    }
    scoped(id2) {
      return this.services.scopeId(id2);
    }
    log(message) {
      var _a, _b;
      (_b = (_a = this.options).log) == null ? void 0 : _b.call(_a, message);
    }
    handleHostCall(apiName, payload) {
      const { onAuthorize, onCallRefused } = this.options;
      if (onAuthorize && !onAuthorize(apiName)) {
        onCallRefused == null ? void 0 : onCallRefused(apiName);
        this.log(`HostHandler[${this.services.appId}]: ${apiName} refused by policy`);
        return NULL_RESPONSE;
      }
      if (domApiNames.has(apiName)) return this.handleDomApi(apiName, payload);
      if (canvasApiNames.has(apiName)) return this.handleCanvasApi(apiName, payload);
      switch (apiName) {
        case "render":
          return this.handleRender(payload);
        case "updateApp":
          return this.handleUpdateApp(payload);
        case "println":
          return this.handlePrintln(payload);
        case "env.get":
          return this.handleEnvGet();
        case "stringify":
          return makeResponse("string", payload);
        default:
          return this.unserviced(apiName);
      }
    }
    unserviced(apiName) {
      var _a, _b;
      const known = allHostApiNames.has(apiName);
      (_b = (_a = this.options).onUnservicedApi) == null ? void 0 : _b.call(_a, apiName, known);
      this.log(
        known ? `HostHandler: ${apiName} is advertised by the VM but not serviced here; returning null` : `HostHandler: unknown host API ${apiName}; returning null`
      );
      return NULL_RESPONSE;
    }
    handleRender(payload) {
      var _a, _b, _c, _d;
      try {
        const args = asHostArgs(parseVmPayload(payload));
        const viewArg = args.length ? args[0] : null;
        const scopeKey = args.length > 1 ? asNullableString(args[1]) : null;
        const viewJson = coerceJsonMap(viewArg);
        if (viewJson) (_b = (_a = this.options).onRender) == null ? void 0 : _b.call(_a, viewJson, scopeKey);
        else if (typeof viewArg === "string") (_d = (_c = this.options).onRender) == null ? void 0 : _d.call(_c, { type: "Text", props: { text: viewArg } }, scopeKey);
      } catch (e) {
        this.log(`HostHandler: render error: ${e}`);
      }
      return OK_RESPONSE;
    }
    handleUpdateApp(payload) {
      var _a, _b;
      try {
        const parsed = unwrapHostArgs(parseVmPayload(payload));
        if (isMap(parsed)) (_b = (_a = this.options).onUpdateApp) == null ? void 0 : _b.call(_a, parsed);
      } catch (e) {
        this.log(`HostHandler: updateApp error: ${e}`);
      }
      return OK_RESPONSE;
    }
    handlePrintln(payload) {
      var _a, _b;
      const parsed = unwrapHostArgs(parseVmPayload(payload));
      (_b = (_a = this.options).onPrintln) == null ? void 0 : _b.call(_a, typeof parsed === "string" ? parsed : payload);
      return OK_RESPONSE;
    }
    handleEnvGet() {
      var _a, _b, _c;
      return makeResponse("object", (_c = (_b = (_a = this.options).onGetEnvironment) == null ? void 0 : _b.call(_a)) != null ? _c : {});
    }
    // ---------------------------------------------------------------------------
    // dom.*
    // ---------------------------------------------------------------------------
    handleDomApi(apiName, payload) {
      var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j, _k, _l, _m, _n, _o, _p, _q;
      try {
        const args = normalizedArgs(payload);
        const dom = this.dom;
        const s = (k) => args[k] == null ? "" : String(args[k]);
        const el = (key = "id") => this.elementFromArgs(args, key);
        switch (apiName) {
          case "dom.createElement": {
            const classes = Array.isArray(args.classes) ? args.classes.map(String) : null;
            return makeResponse("object", encodeElement(dom.createElement(args.tagName != null ? String(args.tagName) : "div", { id: args.id != null ? String(args.id) : null, classes })));
          }
          case "dom.getElementById":
            return makeResponse("object", encodeElement(dom.getElementById(s("id"))));
          case "dom.getElementsByClassName":
            return makeResponse("array", encodeElements(dom.getElementsByClassName(s("className"))));
          case "dom.getElementsByTagName":
            return makeResponse("array", encodeElements(dom.getElementsByTagName(s("tagName"))));
          case "dom.querySelector":
            return makeResponse("object", encodeElement(dom.querySelector(s("selector"))));
          case "dom.querySelectorAll":
            return makeResponse("array", encodeElements(dom.querySelectorAll(s("selector"))));
          case "dom.removeElement": {
            const e = el();
            if (e) dom.removeElement(e);
            return OK_RESPONSE;
          }
          case "dom.clear":
            dom.clear();
            return OK_RESPONSE;
          case "dom.setTextContent": {
            const e = el();
            if (e) e.textContent = args.text != null ? String(args.text) : null;
            return OK_RESPONSE;
          }
          case "dom.setInnerHtml": {
            const e = el();
            if (e) e.innerHTML = args.html != null ? String(args.html) : null;
            return OK_RESPONSE;
          }
          case "dom.setAttribute":
            (_a = el()) == null ? void 0 : _a.setAttribute(s("name"), args.value);
            return OK_RESPONSE;
          case "dom.getAttribute":
            return makeResponse("string", String((_c = (_b = el()) == null ? void 0 : _b.getAttribute(s("name"))) != null ? _c : ""));
          case "dom.removeAttribute":
            (_d = el()) == null ? void 0 : _d.removeAttribute(s("name"));
            return OK_RESPONSE;
          case "dom.hasAttribute":
            return makeResponse("bool", (_f = (_e = el()) == null ? void 0 : _e.hasAttribute(s("name"))) != null ? _f : false);
          case "dom.setStyle":
            (_g = el()) == null ? void 0 : _g.setStyle(s("property"), args.value);
            return OK_RESPONSE;
          case "dom.getStyle":
            return makeResponse("string", String((_i = (_h = el()) == null ? void 0 : _h.getStyle(s("property"))) != null ? _i : ""));
          case "dom.setStyleObject":
            (_j = el()) == null ? void 0 : _j.setStyleObject(isMap(args.styles) ? args.styles : {});
            return OK_RESPONSE;
          case "dom.addClass":
            (_k = el()) == null ? void 0 : _k.addClass(s("className"));
            return OK_RESPONSE;
          case "dom.removeClass":
            (_l = el()) == null ? void 0 : _l.removeClass(s("className"));
            return OK_RESPONSE;
          case "dom.hasClass":
            return makeResponse("bool", (_n = (_m = el()) == null ? void 0 : _m.hasClass(s("className"))) != null ? _n : false);
          case "dom.toggleClass":
            (_o = el()) == null ? void 0 : _o.toggleClass(s("className"));
            return OK_RESPONSE;
          case "dom.appendChild": {
            const parent = el("parentId");
            const child = el("childId");
            if (parent && child) parent.appendChild(child);
            return OK_RESPONSE;
          }
          case "dom.insertBefore": {
            const parent = el("parentId");
            const child = el("newChildId");
            if (parent && child) parent.insertBefore(child, el("referenceChildId"));
            return OK_RESPONSE;
          }
          case "dom.removeChild": {
            const parent = el("parentId");
            const child = el("childId");
            if (parent && child) parent.removeChild(child);
            return OK_RESPONSE;
          }
          case "dom.replaceChild": {
            const parent = el("parentId");
            const fresh = el("newChildId");
            const old = el("oldChildId");
            if (parent && fresh && old) parent.replaceChild(fresh, old);
            return OK_RESPONSE;
          }
          case "dom.addEventListener": {
            const e = el();
            const event = s("event");
            const callback = args.callback != null ? String(args.callback) : null;
            if (e && callback) {
              e.addEventListener(
                event,
                (data) => {
                  var _a2, _b2;
                  return (_b2 = (_a2 = this.options).onUpdateApp) == null ? void 0 : _b2.call(_a2, __spreadValues({ domEvent: callback, elementId: e.id, event }, data !== void 0 ? { data } : {}));
                }
              );
            }
            return OK_RESPONSE;
          }
          case "dom.removeEventListener":
            (_p = el()) == null ? void 0 : _p.removeEventListener(s("event"));
            return OK_RESPONSE;
          case "dom.dispatchEvent":
            (_q = el()) == null ? void 0 : _q.dispatchEvent(s("event"), args.data);
            return OK_RESPONSE;
          case "dom.toJson": {
            const e = el();
            return makeResponse("object", e ? e.toJson() : {});
          }
          case "dom.getAllElements":
            return makeResponse("array", encodeElements(dom.allElements));
        }
        return OK_RESPONSE;
      } catch (e) {
        this.log(`HostHandler: dom API error (${apiName}): ${e}`);
        return OK_RESPONSE;
      }
    }
    elementFromArgs(args, key) {
      var _a, _b;
      const raw = (_a = args[key]) != null ? _a : args.selector;
      const id2 = raw == null ? "" : String(raw);
      if (!id2) return null;
      return (_b = this.dom.getElementById(id2)) != null ? _b : this.dom.querySelector(id2);
    }
    // ---------------------------------------------------------------------------
    // canvas.*
    // ---------------------------------------------------------------------------
    handleCanvasApi(apiName, payload) {
      try {
        if (apiName.startsWith("canvas.ctx.")) return this.handleCanvasContextApi(apiName, payload);
        const args = normalizedArgs(payload);
        const canvas = this.services.canvas;
        switch (apiName) {
          case "canvas.clear":
            canvas.clear();
            return OK_RESPONSE;
          case "canvas.getCommands":
            return makeResponse(
              "array",
              canvas.commands.map((c) => __spreadValues({ type: c.type, params: c.params }, c.id != null ? { id: c.id } : {}))
            );
          case "canvas.addCommand": {
            const cmd = commandFromArgs(args);
            if (cmd) canvas.addCommand(cmd);
            return OK_RESPONSE;
          }
          case "canvas.addCommands":
            canvas.addCommands((Array.isArray(args.commands) ? args.commands : []).filter(isMap).map(commandFromJson));
            return OK_RESPONSE;
        }
        const name = apiName.replace(/^canvas\./, "");
        if (isCanvasCommandType(name)) canvas.addCommand({ type: name, params: args });
        return OK_RESPONSE;
      } catch (e) {
        this.log(`HostHandler: canvas API error (${apiName}): ${e}`);
        return OK_RESPONSE;
      }
    }
    handleCanvasContextApi(apiName, payload) {
      var _a, _b, _c, _d, _e, _f;
      const args = normalizedArgs(payload);
      const store = this.services.canvasContexts;
      const id2 = args.id != null ? String(args.id) : null;
      const ctx = () => id2 == null ? void 0 : store.get(this.scoped(id2));
      switch (apiName) {
        case "canvas.ctx.create": {
          const created = store.create({
            id: id2 == null || id2 === "" ? null : this.scoped(id2),
            width: (_a = toNumber(args.width)) != null ? _a : 0,
            height: (_b = toNumber(args.height)) != null ? _b : 0
          });
          return makeResponse("string", id2 != null ? id2 : created.id);
        }
        case "canvas.ctx.dispose":
          if (id2) store.dispose(this.scoped(id2));
          return OK_RESPONSE;
        case "canvas.ctx.clear":
          (_c = ctx()) == null ? void 0 : _c.clear();
          return OK_RESPONSE;
        case "canvas.ctx.setSize": {
          const c = ctx();
          if (c) c.setSize((_d = toNumber(args.width)) != null ? _d : c.width, (_e = toNumber(args.height)) != null ? _e : c.height);
          return OK_RESPONSE;
        }
        case "canvas.ctx.addCommand": {
          const c = ctx();
          const json = (_f = args.command) != null ? _f : args;
          if (c && isMap(json)) c.addCommand(commandFromJson(json));
          return OK_RESPONSE;
        }
        case "canvas.ctx.addCommands": {
          const c = ctx();
          if (c && Array.isArray(args.commands)) c.addCommands(args.commands.filter(isMap).map(commandFromJson));
          return OK_RESPONSE;
        }
      }
      return OK_RESPONSE;
    }
  };
  function commandFromArgs(args) {
    const t = args.type != null ? String(args.type) : null;
    if (!t || !isCanvasCommandType(t)) return null;
    return { type: t, params: isMap(args.params) ? __spreadValues({}, args.params) : {}, id: args.id != null ? String(args.id) : null };
  }
  function encodeElement(e) {
    return e ? e.encode() : null;
  }
  function encodeElements(list2) {
    return list2.map((e) => e.encode());
  }
  function asNullableString(value) {
    if (value == null) return null;
    const s = String(value).trim();
    return s === "" || s === "null" ? null : s;
  }

  // core/src/host/timers.ts
  var MAX_DELAY = 2 ** 31;
  var VmTimerHostApi = class {
    constructor(invoke, onError) {
      this.invoke = invoke;
      this.onError = onError;
      this.nextId = 1;
      this.timeouts = /* @__PURE__ */ new Map();
      this.intervals = /* @__PURE__ */ new Map();
      this.disposed = false;
    }
    handle(apiName, payload) {
      var _a;
      try {
        switch (apiName) {
          case "setTimeout":
            return this.setTimer(payload, false);
          case "setInterval":
            return this.setTimer(payload, true);
          case "clearTimeout":
          case "clearInterval":
            return this.clear(payload);
          default:
            return OK_RESPONSE;
        }
      } catch (e) {
        (_a = this.onError) == null ? void 0 : _a.call(this, `VmTimerHostApi error (${apiName}): ${e}`);
        return OK_RESPONSE;
      }
    }
    /** Live timer count (governance usage). */
    get activeCount() {
      return this.timeouts.size + this.intervals.size;
    }
    dispose() {
      this.disposed = true;
      const p = platform();
      for (const h of this.timeouts.values()) p.clearTimeout(h);
      for (const i of this.intervals.values()) p.clearTimeout(i.handle);
      this.timeouts.clear();
      this.intervals.clear();
    }
    setTimer(payload, repeat) {
      var _a, _b;
      const args = normalized(payload);
      const handler = (_b = (_a = args.handler) != null ? _a : args.callback) != null ? _b : args.fn;
      if (handler == null || String(handler) === "") return OK_RESPONSE;
      const name = String(handler);
      const delay = readDelay(args);
      const input = readInputJson(args);
      const id2 = this.nextId++;
      const p = platform();
      if (repeat) {
        const entry = { handle: 0 };
        const tick = () => {
          if (this.disposed || !this.intervals.has(id2)) return;
          entry.handle = p.setTimeout(tick, Math.max(delay, 0));
          void this.safeInvoke(name, input);
        };
        entry.handle = p.setTimeout(tick, Math.max(delay, 0));
        this.intervals.set(id2, entry);
      } else {
        this.timeouts.set(
          id2,
          p.setTimeout(() => {
            this.timeouts.delete(id2);
            if (!this.disposed) void this.safeInvoke(name, input);
          }, delay)
        );
      }
      return makeResponse("i64", id2);
    }
    clear(payload) {
      const id2 = readId(payload);
      if (id2 == null) return OK_RESPONSE;
      const p = platform();
      const t = this.timeouts.get(id2);
      if (t !== void 0) {
        p.clearTimeout(t);
        this.timeouts.delete(id2);
      }
      const i = this.intervals.get(id2);
      if (i) {
        p.clearTimeout(i.handle);
        this.intervals.delete(id2);
      }
      return OK_RESPONSE;
    }
    async safeInvoke(handler, input) {
      var _a;
      try {
        await this.invoke(handler, input);
      } catch (e) {
        (_a = this.onError) == null ? void 0 : _a.call(this, `VmTimerHostApi invoke error (${handler}): ${e}`);
      }
    }
  };
  function parsePayload(payload) {
    if (!payload) return null;
    let parsed;
    try {
      parsed = JSON.parse(payload);
    } catch (e) {
      if (payload.length >= 2 && payload.startsWith('"') && payload.endsWith('"')) return payload.substring(1, payload.length - 1);
      return payload;
    }
    if (Array.isArray(parsed)) return parsed.length ? parsed[0] : null;
    if (isMap(parsed) && isMap(parsed.data) && "value" in parsed.data) return parsed.data.value;
    return parsed;
  }
  function normalized(payload) {
    const p = parsePayload(payload);
    return isMap(p) ? p : {};
  }
  function readDelay(args) {
    var _a, _b;
    const raw = (_b = (_a = args.delay) != null ? _a : args.ms) != null ? _b : args.interval;
    let v = 0;
    if (typeof raw === "number") v = Math.round(raw);
    else if (typeof raw === "string" && /^-?\d+$/.test(raw.trim())) v = parseInt(raw, 10);
    return Math.max(0, Math.min(MAX_DELAY, Number.isFinite(v) ? v : 0));
  }
  function readInputJson(args) {
    if (typeof args.inputJson === "string") return args.inputJson;
    if ("input" in args) return JSON.stringify(args.input);
    return null;
  }
  function readId(payload) {
    var _a, _b;
    const p = parsePayload(payload);
    const v = isMap(p) ? (_b = (_a = p.id) != null ? _a : p.timerId) != null ? _b : p.value : p;
    if (typeof v === "number") return Math.round(v);
    if (typeof v === "string" && /^-?\d+$/.test(v.trim())) return parseInt(v, 10);
    return null;
  }

  // core/src/vm/governance.ts
  var ElpianGovernanceException = class extends Error {
    constructor(reason, call = null) {
      super(call == null ? `ElpianGovernanceException: ${reason}` : `ElpianGovernanceException: ${call} failed: ${reason}`);
      this.reason = reason;
      this.call = call;
    }
  };
  function decodeGovernanceReply(raw, call) {
    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch (e) {
      throw new ElpianGovernanceException(`malformed reply: ${e}`, call != null ? call : null);
    }
    if (!isMap(parsed)) throw new ElpianGovernanceException(`expected an object, got ${raw}`, call != null ? call : null);
    if (typeof parsed.error === "string") throw new ElpianGovernanceException(parsed.error, call != null ? call : null);
    return parsed;
  }
  var Limits = {
    unlimited: Object.freeze({}),
    /** `ResourceLimits::sandboxed()`. */
    sandboxed: Object.freeze({
      maxInstructions: 5e7,
      maxInstructionsPerTurn: 5e6,
      maxMemoryBytes: 64 * 1024 * 1024,
      maxStorageBytes: 16 * 1024 * 1024,
      maxCallDepth: 1024
    }),
    toJson(l) {
      var _a, _b, _c, _d, _e;
      return {
        maxInstructions: (_a = l.maxInstructions) != null ? _a : null,
        maxInstructionsPerTurn: (_b = l.maxInstructionsPerTurn) != null ? _b : null,
        maxMemoryBytes: (_c = l.maxMemoryBytes) != null ? _c : null,
        maxStorageBytes: (_d = l.maxStorageBytes) != null ? _d : null,
        maxCallDepth: (_e = l.maxCallDepth) != null ? _e : null
      };
    },
    fromJson(j) {
      const n = (v) => typeof v === "number" ? v : null;
      return {
        maxInstructions: n(j.maxInstructions),
        maxInstructionsPerTurn: n(j.maxInstructionsPerTurn),
        maxMemoryBytes: n(j.maxMemoryBytes),
        maxStorageBytes: n(j.maxStorageBytes),
        maxCallDepth: n(j.maxCallDepth)
      };
    },
    /** The tighter of each axis (null = unbounded). */
    tightest(a, b) {
      const t = (x, y) => x == null ? y != null ? y : null : y == null ? x : Math.min(x, y);
      return {
        maxInstructions: t(a.maxInstructions, b.maxInstructions),
        maxInstructionsPerTurn: t(a.maxInstructionsPerTurn, b.maxInstructionsPerTurn),
        maxMemoryBytes: t(a.maxMemoryBytes, b.maxMemoryBytes),
        maxStorageBytes: t(a.maxStorageBytes, b.maxStorageBytes),
        maxCallDepth: t(a.maxCallDepth, b.maxCallDepth)
      };
    }
  };
  var ZERO_USAGE = Object.freeze({
    instructions: 0,
    instructionsThisTurn: 0,
    memoryBytes: 0,
    peakMemoryBytes: 0,
    storageBytes: 0,
    callDepth: 0,
    peakCallDepth: 0
  });
  function usageFromJson(j) {
    const n = (v) => typeof v === "number" ? Math.trunc(v) : 0;
    return {
      instructions: n(j.instructions),
      instructionsThisTurn: n(j.instructionsThisTurn),
      memoryBytes: n(j.memoryBytes),
      peakMemoryBytes: n(j.peakMemoryBytes),
      storageBytes: n(j.storageBytes),
      callDepth: n(j.callDepth),
      peakCallDepth: n(j.peakCallDepth)
    };
  }
  function pressureAgainst(usage, limits) {
    const out = {};
    const add = (axis, used, max) => {
      if (max != null && max > 0) out[axis] = used / max;
    };
    add("instructions", usage.instructions, limits.maxInstructions);
    add("instructionsPerTurn", usage.instructionsThisTurn, limits.maxInstructionsPerTurn);
    add("memory", usage.memoryBytes, limits.maxMemoryBytes);
    add("storage", usage.storageBytes, limits.maxStorageBytes);
    add("callDepth", usage.callDepth, limits.maxCallDepth);
    return out;
  }
  var CAPABILITIES = [
    "logging",
    "gpu",
    "module_import",
    "network",
    "storage",
    "clock",
    "randomness",
    "vm_manage",
    "dom",
    "canvas",
    "render",
    "timers",
    "environment",
    "tasks",
    "host_messaging",
    "surface",
    "server_call",
    "state",
    "other"
  ];
  function capabilityFromWireName(name) {
    return CAPABILITIES.includes(name) ? name : null;
  }
  var ElpianCapabilities = class _ElpianCapabilities {
    constructor(allowed) {
      this.allowed = allowed;
    }
    static fromJson(json) {
      const map = {};
      for (const [k, v] of Object.entries(json)) {
        const cap = capabilityFromWireName(k);
        if (cap && typeof v === "boolean") map[cap] = v;
      }
      return new _ElpianCapabilities(map);
    }
    /** Unknown reads as denied — an unrecognised gate must never be a pass. */
    allows(c) {
      var _a;
      return (_a = this.allowed[c]) != null ? _a : false;
    }
    get granted() {
      return Object.keys(this.allowed).filter((k) => this.allowed[k]);
    }
    get denied() {
      return Object.keys(this.allowed).filter((k) => this.allowed[k] === false);
    }
    toJson() {
      return __spreadValues({}, this.allowed);
    }
  };
  function vmStateFromJson(j) {
    const states = ["running", "pause_requested", "paused", "terminate_requested", "terminated"];
    const s = states.includes(j.state) ? j.state : "terminated";
    const r = typeof j.trapReason === "string" && j.trapReason ? j.trapReason : null;
    return { state: s, trapReason: r, processing: j.processing === true };
  }
  function treeFromJson(j) {
    const list2 = (v) => Array.isArray(v) ? v.map(String) : [];
    return { parent: typeof j.parent === "string" ? j.parent : null, children: list2(j.children), subtree: list2(j.subtree) };
  }
  function snapshotFromJson(j) {
    var _a;
    const m = (v) => isMap(v) ? v : {};
    return {
      machineId: String((_a = j.machineId) != null ? _a : ""),
      state: vmStateFromJson(m(j.state)),
      limits: Limits.fromJson(m(j.limits)),
      usage: usageFromJson(m(j.usage)),
      subtreeUsage: usageFromJson(m(j.subtreeUsage)),
      localCapabilities: ElpianCapabilities.fromJson(m(j.localCapabilities)),
      effectiveCapabilities: ElpianCapabilities.fromJson(m(j.effectiveCapabilities)),
      tree: treeFromJson(m(j.tree))
    };
  }
  var FULL_SUPPORT = Object.freeze({ capabilities: true, instructionBudget: true, memoryBudget: true, storageBudget: true, lifecycle: true, hierarchy: true });
  var NO_SUPPORT = Object.freeze({ capabilities: false, instructionBudget: false, memoryBudget: false, storageBudget: false, lifecycle: false, hierarchy: false });
  var HostSideGovernor = class {
    constructor(machineId, enforcesInstructions, hooks = {}) {
      this.machineId = machineId;
      this.enforcesInstructions = enforcesInstructions;
      this.hooks = hooks;
      this.limits = Limits.unlimited;
      this.currentUsage = __spreadValues({}, ZERO_USAGE);
      this.runState = "running";
      this.reason = null;
      this.caps = /* @__PURE__ */ new Map();
      this.defaultAllow = true;
    }
    get governanceSupport() {
      return { capabilities: true, instructionBudget: this.enforcesInstructions, memoryBudget: false, storageBudget: false, lifecycle: true, hierarchy: false };
    }
    get trapReason() {
      return this.reason;
    }
    /** Gate and meter one host call; returns the refusal reason or null. */
    checkAndCharge(apiName, bytes = 0) {
      var _a;
      if (this.runState !== "running") return `instance is ${this.runState}`;
      const capability = (_a = capabilityFromWireName(capabilityFor(apiName))) != null ? _a : "other";
      if (!this.allows(capability)) return `capability ${capability} is denied`;
      const next = this.currentUsage.instructions + 1;
      const max = this.limits.maxInstructions;
      if (max != null && next > max) {
        this.trap(`host-call limit exceeded (${max})`);
        return this.reason;
      }
      const nextBytes = this.currentUsage.storageBytes + bytes;
      const maxBytes = this.limits.maxStorageBytes;
      if (maxBytes != null && nextBytes > maxBytes) {
        this.trap(`host-byte limit exceeded (${maxBytes})`);
        return this.reason;
      }
      this.currentUsage = __spreadProps(__spreadValues({}, this.currentUsage), { instructions: next, instructionsThisTurn: this.currentUsage.instructionsThisTurn + 1, storageBytes: nextBytes });
      return null;
    }
    chargeInstructions(steps2) {
      this.currentUsage = __spreadProps(__spreadValues({}, this.currentUsage), {
        instructions: this.currentUsage.instructions + steps2,
        instructionsThisTurn: this.currentUsage.instructionsThisTurn + steps2
      });
      const max = this.limits.maxInstructions;
      if (max != null && this.currentUsage.instructions > max) this.trap(`instruction limit exceeded (${max})`);
    }
    beginTurn() {
      this.currentUsage = __spreadProps(__spreadValues({}, this.currentUsage), { instructionsThisTurn: 0 });
    }
    trap(reason) {
      var _a, _b, _c;
      (_a = this.reason) != null ? _a : this.reason = reason;
      this.runState = "terminated";
      (_c = (_b = this.hooks).onTerminate) == null ? void 0 : _c.call(_b);
    }
    allows(c) {
      var _a;
      return (_a = this.caps.get(c)) != null ? _a : this.defaultAllow;
    }
    async setLimits(limits) {
      this.limits = __spreadValues({}, limits);
    }
    async getLimits() {
      return __spreadValues({}, this.limits);
    }
    async usage() {
      return __spreadValues({}, this.currentUsage);
    }
    async subtreeUsage() {
      return __spreadValues({}, this.currentUsage);
    }
    async setCapability(capability, allowed) {
      this.caps.set(capability, allowed);
    }
    async sandbox(granted) {
      this.caps.clear();
      this.defaultAllow = false;
      for (const c of granted) this.caps.set(c, true);
    }
    async localCapabilities() {
      const out = {};
      for (const c of CAPABILITIES) out[c] = this.allows(c);
      return new ElpianCapabilities(out);
    }
    effectiveCapabilities() {
      return this.localCapabilities();
    }
    async allowsApi(apiName) {
      var _a;
      return this.allows((_a = capabilityFromWireName(capabilityFor(apiName))) != null ? _a : "other");
    }
    async state() {
      return { state: this.runState, trapReason: this.reason, processing: false };
    }
    async pause() {
      var _a, _b;
      if (this.runState === "running") {
        this.runState = "paused";
        (_b = (_a = this.hooks).onPause) == null ? void 0 : _b.call(_a);
      }
    }
    async resumeExecution() {
      var _a, _b;
      if (this.runState === "paused") {
        this.runState = "running";
        (_b = (_a = this.hooks).onResume) == null ? void 0 : _b.call(_a);
      }
    }
    async terminate() {
      var _a, _b;
      this.runState = "terminated";
      (_b = (_a = this.hooks).onTerminate) == null ? void 0 : _b.call(_a);
    }
  };
  function binding() {
    var _a;
    return hasPlatform() ? (_a = platform().elpianVm) != null ? _a : null : null;
  }
  async function govCall(symbol, args) {
    const b = binding();
    if (!b || !b.isAvailable()) {
      throw new ElpianGovernanceException(`the Elpian runtime is not available${(b == null ? void 0 : b.lastError()) ? `: ${b.lastError()}` : ""}`, symbol);
    }
    const raw = await b.governance(symbol, args);
    if (raw == null) throw new ElpianGovernanceException(`the loaded runtime does not export ${symbol} \u2014 rebuild it`, symbol);
    return raw;
  }
  var obj = async (symbol, args) => decodeGovernanceReply(await govCall(symbol, args), symbol);
  async function list(symbol, args) {
    const raw = await govCall(symbol, args);
    let decoded;
    try {
      decoded = JSON.parse(raw);
    } catch (e) {
      throw new ElpianGovernanceException(`malformed reply: ${e}`, symbol);
    }
    if (Array.isArray(decoded)) return decoded;
    if (isMap(decoded) && typeof decoded.error === "string") throw new ElpianGovernanceException(decoded.error, symbol);
    throw new ElpianGovernanceException(`expected an array, got ${raw}`, symbol);
  }
  var governanceProbe = null;
  var ElpianVmGovernor = class {
    constructor(machineId) {
      this.machineId = machineId;
    }
    get governanceSupport() {
      const b = binding();
      return b && b.isAvailable() && governanceProbe !== false ? FULL_SUPPORT : NO_SUPPORT;
    }
    async setLimits(limits) {
      await obj("elpian_set_limits", [this.machineId, JSON.stringify(Limits.toJson(limits))]);
    }
    async getLimits() {
      return Limits.fromJson(await obj("elpian_limits", [this.machineId]));
    }
    async usage() {
      return usageFromJson(await obj("elpian_usage", [this.machineId]));
    }
    async subtreeUsage() {
      return usageFromJson(await obj("elpian_subtree_usage", [this.machineId]));
    }
    async chargeStorage(deltaBytes) {
      await obj("elpian_charge_storage", [this.machineId, deltaBytes]);
    }
    async setCapability(capability, allowed) {
      await obj("elpian_set_capability", [this.machineId, capability, allowed ? 1 : 0]);
    }
    async setCapabilities(changes) {
      await obj("elpian_set_capabilities", [this.machineId, JSON.stringify(changes)]);
    }
    async sandbox(granted) {
      await obj("elpian_sandbox_capabilities", [this.machineId, JSON.stringify([...granted])]);
    }
    async localCapabilities() {
      return ElpianCapabilities.fromJson(await obj("elpian_local_capabilities", [this.machineId]));
    }
    async effectiveCapabilities() {
      return ElpianCapabilities.fromJson(await obj("elpian_effective_capabilities", [this.machineId]));
    }
    async allowsApi(apiName) {
      return (await obj("elpian_capability_allows", [this.machineId, apiName])).allowed === true;
    }
    async state() {
      return vmStateFromJson(await obj("elpian_state", [this.machineId]));
    }
    async pause() {
      await obj("elpian_pause", [this.machineId]);
    }
    async resumeExecution() {
      await obj("elpian_resume", [this.machineId]);
    }
    async terminate() {
      await obj("elpian_terminate", [this.machineId]);
    }
  };
  var ElpianTreeGovernor = class {
    get isAvailable() {
      const b = binding();
      return !!b && b.isAvailable();
    }
    async adopt(parentId, childId) {
      await obj("elpian_adopt", [parentId, childId]);
    }
    async tree(machineId) {
      return treeFromJson(await obj("elpian_tree", [machineId]));
    }
    affected(reply) {
      return Array.isArray(reply.affected) ? reply.affected.map(String) : [];
    }
    async pauseTree(machineId) {
      return this.affected(await obj("elpian_pause_tree", [machineId]));
    }
    async terminateTree(machineId) {
      return this.affected(await obj("elpian_terminate_tree", [machineId]));
    }
    async destroyTree(machineId) {
      return this.affected(await obj("elpian_destroy_tree", [machineId]));
    }
    async enforceTreeBudgets() {
      return (await list("elpian_enforce_tree_budgets", [])).filter(isMap).map((j) => {
        var _a, _b;
        return { machineId: String((_a = j.machineId) != null ? _a : ""), axis: String((_b = j.axis) != null ? _b : "unknown"), destroyed: Array.isArray(j.destroyed) ? j.destroyed.map(String) : [] };
      });
    }
    async snapshot(machineId) {
      return snapshotFromJson(await obj("elpian_snapshot", [machineId]));
    }
  };

  // core/src/vm/runtime.ts
  function parseExecResult(raw) {
    try {
      const j = JSON.parse(raw);
      return {
        hasHostCall: (j == null ? void 0 : j.hasHostCall) === true,
        hostCallData: typeof (j == null ? void 0 : j.hostCallData) === "string" ? j.hostCallData : "",
        resultValue: typeof (j == null ? void 0 : j.resultValue) === "string" ? j.resultValue : ""
      };
    } catch (e) {
      return { hasHostCall: false, hostCallData: "", resultValue: "" };
    }
  }
  function errorResult(reason) {
    return JSON.stringify({ hasHostCall: false, hostCallData: "", resultValue: JSON.stringify({ error: reason }) });
  }
  function log(message) {
    try {
      platform().log("debug", message);
    } catch (e) {
    }
  }
  var BaseClient = class {
    constructor(machineId) {
      this.machineId = machineId;
      this.hostHandlers = /* @__PURE__ */ new Map();
      this.defaultHostHandler = null;
      this.globalHostData = {};
    }
    registerHostHandler(apiName, handler) {
      this.hostHandlers.set(apiName, handler);
    }
    registerHostHandlers(handlers) {
      for (const [k, v] of Object.entries(handlers)) this.hostHandlers.set(k, v);
    }
    setDefaultHostHandler(handler) {
      this.defaultHostHandler = handler;
    }
    /** The built-ins every runtime answers when no handler is registered. */
    builtin(label, apiName, payload) {
      switch (apiName) {
        case "println":
          log(`${label}[${this.machineId}]: ${payload}`);
          return OK_RESPONSE;
        case "env.get":
          return JSON.stringify({ type: "object", data: { value: this.globalHostData } });
        case "stringify":
          return JSON.stringify({ type: "string", data: { value: payload } });
        default:
          log(`${label}: Unhandled host call: ${apiName}`);
          return OK_RESPONSE;
      }
    }
  };
  var _ElpianVm = class _ElpianVm extends BaseClient {
    constructor(machineId) {
      super(machineId);
      this.cbCounter = 0;
      this.running = false;
      this.governor = new ElpianVmGovernor(machineId);
    }
    static binding() {
      var _a;
      return (_a = platform().elpianVm) != null ? _a : null;
    }
    static get isRuntimeAvailable() {
      var _a, _b;
      return (_b = (_a = _ElpianVm.binding()) == null ? void 0 : _a.isAvailable()) != null ? _b : false;
    }
    static get lastApiError() {
      var _a, _b;
      return (_b = (_a = _ElpianVm.binding()) == null ? void 0 : _a.lastError()) != null ? _b : "no Elpian VM binding on this platform";
    }
    static async initialize() {
      var _a;
      await ((_a = _ElpianVm.binding()) == null ? void 0 : _a.init());
    }
    static require() {
      const b = _ElpianVm.binding();
      if (!b || !b.isAvailable()) throw new Error(`Elpian VM runtime unavailable: ${_ElpianVm.lastApiError}`);
      return b;
    }
    static async fromAst(machineId, astJson) {
      return await _ElpianVm.require().createFromAst(machineId, astJson) ? new _ElpianVm(machineId) : null;
    }
    static async fromCode(machineId, code) {
      return await _ElpianVm.require().createFromCode(machineId, code) ? new _ElpianVm(machineId) : null;
    }
    /** [bytecode] as base64. */
    static async fromBytecode(machineId, bytecodeBase64) {
      return await _ElpianVm.require().createFromBytecode(machineId, bytecodeBase64) ? new _ElpianVm(machineId) : null;
    }
    static async validateAst(astJson) {
      var _a, _b;
      return (_b = await ((_a = _ElpianVm.binding()) == null ? void 0 : _a.validateAst(astJson))) != null ? _b : false;
    }
    get isRunning() {
      return this.running;
    }
    async setGlobalHostData(data) {
      this.globalHostData = __spreadValues({}, data);
    }
    async run() {
      this.running = true;
      try {
        const b = _ElpianVm.binding();
        return await this.loop(b ? await b.execute(this.machineId) : errorResult("native_lib_not_loaded"));
      } finally {
        this.running = false;
      }
    }
    async callFunction(funcName) {
      this.running = true;
      const cb = ++this.cbCounter;
      try {
        const b = _ElpianVm.binding();
        return await this.loop(b ? await b.executeFunc(this.machineId, funcName, cb) : errorResult("native_lib_not_loaded"));
      } finally {
        this.running = false;
      }
    }
    async callFunctionWithInput(funcName, inputJson) {
      this.running = true;
      const cb = ++this.cbCounter;
      try {
        const b = _ElpianVm.binding();
        return await this.loop(b ? await b.executeFuncWithInput(this.machineId, funcName, inputJson, cb) : errorResult("native_lib_not_loaded"));
      } finally {
        this.running = false;
      }
    }
    async deliverHostMessage(messageJson) {
      const cb = ++this.cbCounter;
      const b = _ElpianVm.binding();
      return this.loop(b ? await b.deliverHostMessage(this.machineId, messageJson, cb) : errorResult("native_lib_not_loaded"));
    }
    /** hasHostCall → handle → continueExecution, until the VM yields a value. */
    async loop(raw) {
      var _a, _b;
      let result = parseExecResult(raw);
      const b = _ElpianVm.binding();
      while (result.hasHostCall && b) {
        let apiName = "";
        let payload = "";
        try {
          const data = JSON.parse(result.hostCallData);
          apiName = String((_a = data.apiName) != null ? _a : "");
          payload = typeof data.payload === "string" ? data.payload : JSON.stringify((_b = data.payload) != null ? _b : null);
        } catch (e) {
          log(`ElpianVm: malformed host call: ${e}`);
        }
        let response;
        try {
          response = await this.handle(apiName, payload);
        } catch (e) {
          log(`ElpianVm: Host call error for ${apiName}: ${e}`);
          response = JSON.stringify({ type: "string", data: { value: `error: ${e}` } });
        }
        result = parseExecResult(await b.continueExecution(this.machineId, response));
      }
      return result.resultValue;
    }
    async handle(apiName, payload) {
      var _a;
      const h = (_a = this.hostHandlers.get(apiName)) != null ? _a : this.defaultHostHandler;
      if (h) return await h(apiName, payload);
      return this.builtin("ElpianVm", apiName, payload);
    }
    async dispose() {
      var _a;
      await ((_a = _ElpianVm.binding()) == null ? void 0 : _a.destroy(this.machineId));
    }
  };
  _ElpianVm.treeGovernor = new ElpianTreeGovernor();
  var ElpianVm = _ElpianVm;
  var ASK_HOST_BOOTSTRAP = `
globalThis.askHost = function(apiName) {
  var args = Array.prototype.slice.call(arguments, 1);
  var payload = '';
  if (args.length === 1) {
    payload = args[0];
  } else if (args.length > 1) {
    payload = args;
  }
  var encoded = typeof payload === 'string' ? payload : JSON.stringify(payload);
  return __elpianHostCall(String(apiName), encoded === undefined ? 'null' : encoded);
};
`;
  var QuickJsVm = class _QuickJsVm extends BaseClient {
    constructor(machineId) {
      super(machineId);
      this.sandbox = null;
      this.bootCode = null;
      this.disposed = false;
      this.governor = new HostSideGovernor(machineId, false, { onTerminate: () => void this.dispose() });
    }
    static get isRuntimeAvailable() {
      return platform().jsSandbox != null;
    }
    static async fromCode(machineId, code) {
      const factory = platform().jsSandbox;
      if (!factory) throw new Error("QuickJS runtime unavailable: the platform provides no JS sandbox");
      const vm = new _QuickJsVm(machineId);
      vm.sandbox = await factory.create(machineId);
      vm.sandbox.setHostCallHandler((api, payload) => vm.dispatchHostCall(api, payload));
      await vm.sandbox.evaluate(ASK_HOST_BOOTSTRAP);
      vm.bootCode = code;
      return vm;
    }
    static async fromAst() {
      throw new Error("QuickJS runtime expects JavaScript source in `code`; AST JSON is only supported by the Elpian runtime.");
    }
    async setGlobalHostData(data) {
      this.globalHostData = __spreadValues({}, data);
      if (!this.sandbox) return;
      const encoded = JSON.stringify(JSON.stringify(this.globalHostData));
      await this.sandbox.evaluate(`(function() {
  var __env = JSON.parse(${encoded});
  globalThis.__ELPIAN_HOST_ENV__ = __env;
  globalThis.ELPIAN_HOST_ENV = __env;
  globalThis.getElpianHostEnv = function() { return globalThis.__ELPIAN_HOST_ENV__; };
})();`);
    }
    async runCode(code) {
      if (!this.sandbox || this.disposed) return "";
      this.governor.beginTurn();
      return await this.sandbox.evaluate(code);
    }
    async run() {
      if (!this.bootCode) return "";
      return this.runCode(this.bootCode);
    }
    async callFunction(funcName) {
      return this.runCode(`${funcName}();`);
    }
    async callFunctionWithInput(funcName, inputJson) {
      return this.runCode(`${funcName}(JSON.parse(${JSON.stringify(inputJson)}));`);
    }
    /** The capability gate: every QuickJS host call crosses here. */
    dispatchHostCall(apiName, payload) {
      var _a;
      const refusal = this.governor.checkAndCharge(apiName, payload.length);
      if (refusal != null) {
        log(`QuickJs[${this.machineId}]: ${apiName} refused \u2014 ${refusal}`);
        return NULL_RESPONSE;
      }
      const h = (_a = this.hostHandlers.get(apiName)) != null ? _a : this.defaultHostHandler;
      if (h) {
        const r = h(apiName, payload);
        return typeof r === "string" ? r : OK_RESPONSE;
      }
      return this.builtin("QuickJsVm", apiName, payload);
    }
    async dispose() {
      var _a;
      if (this.disposed) return;
      this.disposed = true;
      (_a = this.sandbox) == null ? void 0 : _a.dispose();
      this.sandbox = null;
    }
  };
  function parseWasmConfig(source) {
    const raw = JSON.parse(source);
    if (!isMap(raw)) throw new Error("WASM runtime config must be a JSON object.");
    const e = isMap(raw.exports) ? raw.exports : {};
    const s = (v, d) => v == null ? d : String(v);
    return {
      wasmBase64: raw.wasmBase64 != null ? String(raw.wasmBase64) : null,
      wasmAssetPath: raw.wasmAssetPath != null ? String(raw.wasmAssetPath) : null,
      exports: {
        memory: s(e.memory, "memory"),
        alloc: s(e.alloc, "alloc"),
        dealloc: s(e.dealloc, "dealloc"),
        run: s(e.run, "run"),
        callFunction: s(e.callFunction, "call_function"),
        callFunctionWithInput: s(e.callFunctionWithInput, "call_function_with_input"),
        getResultPtr: s(e.getResultPtr, "get_result_ptr"),
        getResultLen: s(e.getResultLen, "get_result_len")
      }
    };
  }
  var WasmVm = class _WasmVm extends BaseClient {
    constructor(machineId) {
      super(machineId);
      this.instance = null;
      this.config = null;
      this.bootCode = null;
      this.governor = new HostSideGovernor(machineId, true, { onTerminate: () => void this.dispose() });
    }
    static get isRuntimeAvailable() {
      return platform().wasm != null;
    }
    static async fromCode(machineId, code) {
      const vm = new _WasmVm(machineId);
      vm.bootCode = code;
      return vm;
    }
    static async fromAst() {
      throw new Error("WASM runtime expects JSON runtime config in `code`.");
    }
    async setGlobalHostData(data) {
      this.globalHostData = __spreadValues({}, data);
    }
    async run() {
      if (!this.bootCode) return "";
      await this.ensureLoaded(this.bootCode);
      this.governor.beginTurn();
      this.require(this.config.exports.run, []);
      return this.readResult();
    }
    async callFunction(funcName) {
      this.assertLoaded();
      this.governor.beginTurn();
      const fn = this.writeString(funcName);
      try {
        this.require(this.config.exports.callFunction, [fn.ptr, fn.length]);
        return this.readResult();
      } finally {
        this.dealloc(fn);
      }
    }
    async callFunctionWithInput(funcName, inputJson) {
      this.assertLoaded();
      this.governor.beginTurn();
      const fn = this.writeString(funcName);
      const input = this.writeString(inputJson);
      try {
        this.require(this.config.exports.callFunctionWithInput, [fn.ptr, fn.length, input.ptr, input.length]);
        return this.readResult();
      } finally {
        this.dealloc(fn);
        this.dealloc(input);
      }
    }
    async ensureLoaded(configJson) {
      if (this.instance) return;
      const engine = platform().wasm;
      if (!engine) throw new Error("WASM runtime unavailable: the platform provides no WebAssembly engine");
      const config = parseWasmConfig(configJson);
      const bytes = await loadWasmBytes(config);
      this.config = config;
      this.instance = await engine.instantiate(bytes, (_module, name, args) => this.onImport(name, args));
      if (!this.instance.hasExport(config.exports.memory)) throw new Error(`WASM memory export not found: ${config.exports.memory}`);
    }
    onImport(name, args) {
      if (name !== "elpian_host_call" || args.length < 6 || !this.instance) return [0];
      const [apiPtr, apiLen, payloadPtr, payloadLen, outPtr, outCap] = args.map((a) => Math.trunc(Number(a)));
      const apiName = this.readString(apiPtr, apiLen);
      const payload = this.readString(payloadPtr, payloadLen);
      return [this.writeInto(this.dispatchHostCall(apiName, payload), outPtr, outCap)];
    }
    dispatchHostCall(apiName, payload) {
      var _a;
      const refusal = this.governor.checkAndCharge(apiName, payload.length);
      if (refusal != null) {
        log(`WasmVm[${this.machineId}]: ${apiName} refused \u2014 ${refusal}`);
        return NULL_RESPONSE;
      }
      const h = (_a = this.hostHandlers.get(apiName)) != null ? _a : this.defaultHostHandler;
      if (h) {
        const r = h(apiName, payload);
        return typeof r === "string" ? r : OK_RESPONSE;
      }
      return this.builtin("WasmVm", apiName, payload);
    }
    require(name, args) {
      if (!this.instance) throw new Error("WASM instance is not loaded.");
      if (!this.instance.hasExport(name)) throw new Error(`WASM function export not found: ${name}`);
      return this.instance.call(name, args);
    }
    writeString(text2) {
      var _a;
      const bytes = utf8Encode(text2);
      const ptr = Math.trunc(Number((_a = this.require(this.config.exports.alloc, [bytes.length])[0]) != null ? _a : 0));
      if (ptr <= 0) throw new Error(`WASM alloc returned invalid pointer for length ${bytes.length}.`);
      const mem = this.config.exports.memory;
      if (ptr + bytes.length > this.instance.memoryLength(mem)) throw new Error(`WASM memory write out of range (ptr=${ptr} len=${bytes.length}).`);
      this.instance.memoryWrite(mem, ptr, bytes);
      return { ptr, length: bytes.length };
    }
    writeInto(text2, ptr, capacity) {
      if (capacity <= 0) return 0;
      const bytes = utf8Encode(text2);
      const length = Math.min(bytes.length, capacity);
      const mem = this.config.exports.memory;
      if (ptr < 0 || ptr + length > this.instance.memoryLength(mem)) return 0;
      this.instance.memoryWrite(mem, ptr, bytes.subarray(0, length));
      return length;
    }
    readString(ptr, len) {
      if (len <= 0) return "";
      const mem = this.config.exports.memory;
      if (ptr < 0 || ptr + len > this.instance.memoryLength(mem)) return "";
      return utf8Decode(this.instance.memoryRead(mem, ptr, len));
    }
    readResult() {
      var _a, _b;
      const ptr = Math.trunc(Number((_a = this.require(this.config.exports.getResultPtr, [])[0]) != null ? _a : 0));
      const len = Math.trunc(Number((_b = this.require(this.config.exports.getResultLen, [])[0]) != null ? _b : 0));
      if (ptr <= 0 || len <= 0) return "";
      return this.readString(ptr, len);
    }
    dealloc(text2) {
      var _a;
      const name = (_a = this.config) == null ? void 0 : _a.exports.dealloc;
      if (!name || !this.instance || !this.instance.hasExport(name)) return;
      this.instance.call(name, [text2.ptr, text2.length]);
    }
    assertLoaded() {
      if (!this.instance || !this.config) throw new Error("WASM runtime is not initialized. Call run() first.");
    }
    async dispose() {
      var _a;
      (_a = this.instance) == null ? void 0 : _a.dispose();
      this.instance = null;
      this.config = null;
    }
  };
  async function loadWasmBytes(config) {
    if (config.wasmBase64) return base64Decode(config.wasmBase64);
    if (!config.wasmAssetPath) throw new Error("WASM config must provide either `wasmBase64` or `wasmAssetPath`.");
    const load = platform().loadAsset;
    if (!load) throw new Error("This platform cannot load bundled assets.");
    return base64Decode(await load(config.wasmAssetPath, "base64"));
  }
  async function initializeRuntime(kind) {
    if (kind === "elpian") await ElpianVm.initialize();
  }

  // core/src/session/miniapp.ts
  var MiniAppSession = class {
    constructor(surfaceId, options) {
      this.options = options;
      this.runtimeVm = null;
      this.timers = null;
      this.currentView = null;
      this.envData = {};
      this.envDigest = null;
      this.disposed = false;
      this.loading = true;
      this.errorMessage = null;
      this.surface = new ElpianSurface(surfaceId, options.surface);
      if (options.stylesheet) this.engine.loadStylesheet(options.stylesheet);
      this.showState();
    }
    get engine() {
      return this.surface.engine;
    }
    get runtime() {
      return this.runtimeVm;
    }
    get error() {
      return this.errorMessage;
    }
    get isLoading() {
      return this.loading;
    }
    get view() {
      return this.currentView;
    }
    /** Create the runtime, wire the host APIs, run the program and the entry function. */
    async start() {
      var _a, _b, _c, _d, _e, _f;
      const o = this.options;
      const kind = (_a = o.runtime) != null ? _a : "elpian";
      try {
        let vm = (_b = o.runtimeClient) != null ? _b : null;
        if (vm) {
        } else if (kind === "elpian") {
          await initializeRuntime(kind);
          if (o.bytecodeBase64) vm = await ElpianVm.fromBytecode(o.machineId, o.bytecodeBase64);
          else if (o.code != null) vm = await ElpianVm.fromCode(o.machineId, o.code);
          else if (o.astJson != null) vm = await ElpianVm.fromAst(o.machineId, o.astJson);
          if (!vm) {
            const detail = ElpianVm.lastApiError;
            return this.fail(detail ? `Failed to create VM: ${detail}` : "Failed to create VM");
          }
        } else if (kind === "quickjs") {
          await initializeRuntime(kind);
          if (o.code == null) return this.fail("QuickJS runtime requires `code` (JavaScript source).");
          vm = await QuickJsVm.fromCode(o.machineId, o.code);
        } else {
          if (o.code == null) return this.fail("WASM runtime requires `code` (WASM config JSON).");
          vm = await WasmVm.fromCode(o.machineId, o.code);
        }
        if (this.disposed) {
          if (!o.runtimeClient) await vm.dispose();
          return;
        }
        this.runtimeVm = vm;
        this.engine.services.events.onGlobalEvent((event) => void this.routeEventToVm(event));
        const handler = new HostHandler(this.engine.services, {
          onRender: (view, scopeKey) => this.applyRender(view, scopeKey),
          onUpdateApp: (data) => {
            var _a2;
            (_a2 = o.onUpdateApp) == null ? void 0 : _a2.call(o, data);
            if (o.entryFunction) void this.callEntryFunction();
          },
          onPrintln: (_c = o.onPrintln) != null ? _c : (m) => platform().log("info", `[${o.machineId}] ${m}`),
          onGetEnvironment: () => this.envData,
          onAuthorize: o.onAuthorize,
          onCallRefused: o.onCallRefused,
          onUnservicedApi: o.onUnservicedApi,
          log: (m) => platform().log("debug", m)
        });
        (_d = this.timers) == null ? void 0 : _d.dispose();
        const runtimeVm = vm;
        this.timers = new VmTimerHostApi(
          async (fn, input) => {
            if (this.disposed) return;
            if (input == null) await runtimeVm.callFunction(fn);
            else await runtimeVm.callFunctionWithInput(fn, input);
          },
          (m) => platform().log("warn", `ElpianMiniApp: ${m}`)
        );
        const handlers = {};
        for (const api of allHostApiNames) handlers[api] = (name, payload) => handler.handleHostCall(name, payload);
        for (const api of timerApiNames) handlers[api] = (name, payload) => this.timers.handle(name, payload);
        Object.assign(handlers, (_e = o.hostHandlers) != null ? _e : {});
        vm.registerHostHandlers(handlers);
        await this.syncHostEnvironment(true);
        await vm.run();
        if (o.entryFunction) await this.callEntryFunction();
        this.loading = false;
        this.showState();
        (_f = o.onReady) == null ? void 0 : _f.call(o);
      } catch (e) {
        this.fail(String(e instanceof Error ? e.message : e));
      }
    }
    fail(message) {
      var _a, _b;
      this.errorMessage = message;
      this.loading = false;
      (_b = (_a = this.options).onError) == null ? void 0 : _b.call(_a, message);
      this.showState();
    }
    showState() {
      var _a;
      if (this.disposed) return;
      const defaults = (_a = this.options.showDefaultStates) != null ? _a : true;
      if (this.errorMessage != null) {
        this.surface.setOverlay(defaults ? messageBox(`VM Error: ${this.errorMessage}`, 4294198070) : null);
        return;
      }
      if (this.loading && this.currentView == null) {
        this.surface.setOverlay(defaults ? loadingIndicator() : null);
        return;
      }
      this.surface.setContent(this.currentView);
    }
    applyRender(view, scopeKey) {
      const next = ScopePatch.applyBounded(this.currentView, view, scopeKey);
      if (next == null) {
        platform().log("debug", `ElpianMiniApp: scoped render targeted missing scope "${scopeKey}"; keeping current view.`);
        return;
      }
      this.currentView = next;
      if (this.errorMessage == null) this.surface.setContent(next);
      void this.syncHostEnvironment(false);
    }
    async routeEventToVm(event) {
      var _a, _b;
      const vm = this.runtimeVm;
      if (!vm || this.disposed) return;
      const nodeId = event.currentTarget;
      if (!nodeId) return;
      const handler = (_b = (_a = this.engine.services.events.getNode(nodeId)) == null ? void 0 : _a.events) == null ? void 0 : _b[event.type];
      if (typeof handler !== "string" || !handler) return;
      const payload = JSON.stringify(toTypedVmValue(eventToJson(event)));
      try {
        await vm.callFunctionWithInput(handler, payload);
      } catch (e) {
        try {
          await vm.callFunction(handler);
        } catch (fallback) {
          platform().log("warn", `ElpianMiniApp: Error calling event handler "${handler}": ${e}; fallback failed: ${fallback}`);
        }
      }
    }
    async callEntryFunction() {
      const vm = this.runtimeVm;
      const fn = this.options.entryFunction;
      if (!vm || !fn) return;
      try {
        if (this.options.entryInput != null) await vm.callFunctionWithInput(fn, this.options.entryInput);
        else await vm.callFunction(fn);
      } catch (e) {
        platform().log("warn", `ElpianMiniApp: Error calling ${fn}: ${e}`);
      }
    }
    /** Call a guest function (ElpianVmController.callFunction). */
    async callFunction(funcName, input) {
      const vm = this.runtimeVm;
      if (!vm) return "";
      return input != null ? vm.callFunctionWithInput(funcName, input) : vm.callFunction(funcName);
    }
    /** The platform reports a viewport / safe-area / theme change. */
    viewportChanged() {
      this.surface.viewportChanged();
      void this.syncHostEnvironment(true);
    }
    async syncHostEnvironment(force) {
      const next = this.buildHostEnvironment();
      const digest = JSON.stringify(next);
      const changed = digest !== this.envDigest;
      if (changed) {
        this.envDigest = digest;
        this.envData = next;
      }
      if (!this.runtimeVm || !changed && !force) return;
      try {
        await this.runtimeVm.setGlobalHostData(this.envData);
      } catch (e) {
        platform().log("warn", `ElpianMiniApp: failed to sync host env: ${e}`);
      }
    }
    buildHostEnvironment() {
      var _a, _b, _c, _d, _e, _f, _g;
      const vp = platform().viewport(this.surface.id);
      const href = (_a = vp.href) != null ? _a : "";
      let page = { href, scheme: "", host: "", port: null, path: "", query: "", queryParameters: {}, fragment: "" };
      const m = /^([a-zA-Z][\w+.-]*):(?:\/\/([^/?#:]*)(?::(\d+))?)?([^?#]*)(?:\?([^#]*))?(?:#(.*))?$/.exec(href);
      if (m) {
        const query = (_b = m[5]) != null ? _b : "";
        const params = {};
        for (const part of query.split("&")) {
          if (!part) continue;
          const i = part.indexOf("=");
          const k = decodeURIComponentSafe(i < 0 ? part : part.substring(0, i));
          params[k] = decodeURIComponentSafe(i < 0 ? "" : part.substring(i + 1));
        }
        page = { href, scheme: m[1], host: (_c = m[2]) != null ? _c : "", port: m[3] != null ? Number(m[3]) : null, path: (_d = m[4]) != null ? _d : "", query, queryParameters: params, fragment: (_e = m[6]) != null ? _e : "" };
      }
      return __spreadValues({
        machineId: this.options.machineId,
        runtime: runtimeName((_f = this.options.runtime) != null ? _f : "elpian"),
        viewport: {
          width: vp.width,
          height: vp.height,
          devicePixelRatio: vp.devicePixelRatio,
          orientation: vp.width >= vp.height ? "landscape" : "portrait"
        },
        screen: { physicalWidth: vp.width * vp.devicePixelRatio, physicalHeight: vp.height * vp.devicePixelRatio },
        safeArea: __spreadValues({}, vp.safeArea),
        page,
        platform: { isWeb: vp.isWeb, defaultTargetPlatform: vp.platform, locale: vp.locale }
      }, (_g = this.options.hostEnvironment) != null ? _g : {});
    }
    async dispose() {
      var _a;
      if (this.disposed) return;
      this.disposed = true;
      (_a = this.timers) == null ? void 0 : _a.dispose();
      this.timers = null;
      const vm = this.runtimeVm;
      this.runtimeVm = null;
      this.surface.dispose();
      if (!this.options.runtimeClient) await (vm == null ? void 0 : vm.dispose());
    }
  };
  function runtimeName(kind) {
    return kind === "quickjs" ? "quickJs" : kind;
  }
  function decodeURIComponentSafe(s) {
    try {
      return decodeURIComponent(s.replace(/\+/g, " "));
    } catch (e) {
      return s;
    }
  }

  // core/src/session/nextjs.ts
  function envelopeFromJson(json) {
    if (!isMap(json.component)) throw new Error('Next.js payload must contain a "component" object that matches Elpian JSON.');
    const obj2 = (k) => {
      const v = json[k];
      if (v != null && !isMap(v)) throw new Error(`"${k}" must be a JSON object when provided.`);
      return v != null ? v : null;
    };
    const str2 = (k) => {
      const v = json[k];
      if (v != null && typeof v !== "string") throw new Error(`"${k}" must be a string when provided.`);
      return v != null ? v : null;
    };
    return {
      component: json.component,
      stylesheet: obj2("stylesheet"),
      meta: obj2("meta"),
      navigation: obj2("navigation"),
      clientComponents: obj2("clientComponents"),
      jsCode: str2("jsCode"),
      vmAstJson: str2("vmAstJson"),
      jsEntryFunction: str2("jsEntryFunction")
    };
  }
  function buildRouteRequest(route, props, context) {
    return __spreadValues(__spreadValues({ route }, props ? { props } : {}), context ? { context } : {});
  }
  var InMemoryTokenStore = class {
    constructor() {
      this.access = null;
      this.refresh = null;
    }
    get accessToken() {
      return this.access;
    }
    get refreshToken() {
      return this.refresh;
    }
    get hasSession() {
      return !!this.access;
    }
    async ensureReady() {
    }
    save(t) {
      if (t.access != null) this.access = t.access;
      if (t.refresh != null) this.refresh = t.refresh;
    }
    clear() {
      this.access = null;
      this.refresh = null;
    }
  };
  var PlatformTokenStore = class {
    constructor(namespace = "elpian") {
      this.namespace = namespace;
      this.access = null;
      this.refresh = null;
      this.ready = null;
    }
    get accessKey() {
      return `${this.namespace}_access_token`;
    }
    get refreshKey() {
      return `${this.namespace}_refresh_token`;
    }
    get accessToken() {
      return this.access;
    }
    get refreshToken() {
      return this.refresh;
    }
    get hasSession() {
      return !!this.access;
    }
    ensureReady() {
      var _a;
      return (_a = this.ready) != null ? _a : this.ready = (async () => {
        var _a2, _b, _c, _d;
        try {
          const p = platform();
          this.access = (_b = (_a2 = p.storageGet) == null ? void 0 : _a2.call(p, this.accessKey)) != null ? _b : null;
          this.refresh = (_d = (_c = p.storageGet) == null ? void 0 : _c.call(p, this.refreshKey)) != null ? _d : null;
        } catch (e) {
        }
      })();
    }
    save(t) {
      var _a, _b;
      const p = platform();
      if (t.access != null) {
        this.access = t.access;
        (_a = p.storageSet) == null ? void 0 : _a.call(p, this.accessKey, t.access);
      }
      if (t.refresh != null) {
        this.refresh = t.refresh;
        (_b = p.storageSet) == null ? void 0 : _b.call(p, this.refreshKey, t.refresh);
      }
    }
    clear() {
      var _a, _b;
      const p = platform();
      this.access = null;
      this.refresh = null;
      (_a = p.storageSet) == null ? void 0 : _a.call(p, this.accessKey, null);
      (_b = p.storageSet) == null ? void 0 : _b.call(p, this.refreshKey, null);
    }
  };
  function nextjsAuthConfig(c = {}) {
    var _a, _b, _c, _d;
    return { store: (_a = c.store) != null ? _a : new PlatformTokenStore(), loginRoute: (_b = c.loginRoute) != null ? _b : "/auth", refreshRoute: (_c = c.refreshRoute) != null ? _c : "/auth/refresh", bearerScheme: (_d = c.bearerScheme) != null ? _d : "Bearer" };
  }
  var ClientCompRouting = {
    separator: "::",
    namespaced(mountId, fn) {
      return `${mountId}::${fn}`;
    },
    parse(handler) {
      const idx = handler.indexOf("::");
      if (idx <= 0) return null;
      return { mountId: handler.substring(0, idx), fn: handler.substring(idx + 2) };
    },
    /** Prefix every un-namespaced handler in [node] with [mountId] (in place). */
    namespaceHandlers(node, mountId) {
      if (isMap(node.events)) {
        const ns = {};
        for (const [k, v] of Object.entries(node.events)) ns[k] = typeof v === "string" && v && !v.includes("::") ? ClientCompRouting.namespaced(mountId, v) : v;
        node.events = ns;
      }
      if (Array.isArray(node.children)) {
        for (const c of node.children) if (isMap(c)) ClientCompRouting.namespaceHandlers(c, mountId);
      }
      return node;
    }
  };
  var HOST_OK = '{"type":"i16","data":{"value":1}}';
  var NextjsSession = class {
    constructor(surfaceId, options) {
      this.options = options;
      this.history = [];
      this.lastScriptSignature = null;
      this.scriptRendered = null;
      this.lastEnvelopeComponent = null;
      this.previousComponent = null;
      this.clientComponentCache = /* @__PURE__ */ new Map();
      this.pageVm = null;
      this.pageTimers = null;
      this.liveComps = /* @__PURE__ */ new Map();
      this.compSeq = 0;
      this.loadGeneration = 0;
      this.payload = null;
      this.loadError = null;
      this.loading = true;
      this.lastStylesheetKey = null;
      this.disposed = false;
      var _a, _b, _c, _d;
      if (!options.loader && !options.serverBaseUrl) throw new Error("Either provide loader or serverBaseUrl for automatic Next.js loading.");
      this.currentRoute = options.route;
      const origin = originOf((_a = options.serverBaseUrl) != null ? _a : null);
      this.surface = new ElpianSurface(surfaceId, __spreadProps(__spreadValues({}, (_b = options.surface) != null ? _b : {}), {
        document: true,
        host: __spreadProps(__spreadValues({}, (_d = (_c = options.surface) == null ? void 0 : _c.host) != null ? _d : {}), {
          navigate: (href, replace2) => this.navigate(href, replace2),
          submitForm: (action, values) => this.handleFormSubmit(action, values),
          sceneTap: (props) => void this.dispatchSceneTap(props),
          baseUrl: () => {
            var _a2, _b2, _c2, _d2;
            return (_d2 = (_c2 = (_b2 = (_a2 = options.surface) == null ? void 0 : _a2.host) == null ? void 0 : _b2.baseUrl) == null ? void 0 : _c2.call(_b2)) != null ? _d2 : origin;
          }
        })
      }));
      this.surface.engine.services.events.onGlobalEvent((e) => void this.routeEvent(e));
      void this.load();
    }
    get route() {
      return this.currentRoute;
    }
    get canGoBack() {
      return this.history.length > 0;
    }
    // ---------------------------------------------------------------------------
    // Navigation
    // ---------------------------------------------------------------------------
    navigate(route, replace2 = false) {
      if (this.currentRoute === route && !replace2) return;
      void this.disposePageVm();
      if (!replace2) this.history.push(this.currentRoute);
      this.currentRoute = route;
      this.beginReload();
    }
    back() {
      if (!this.history.length) return false;
      void this.disposePageVm();
      this.currentRoute = this.history.pop();
      this.beginReload();
      return true;
    }
    refresh() {
      void this.disposePageVm();
      this.beginReload();
    }
    beginReload() {
      var _a, _b, _c, _d;
      this.previousComponent = (_b = (_a = this.scriptRendered) != null ? _a : this.lastEnvelopeComponent) != null ? _b : this.previousComponent;
      this.scriptRendered = null;
      this.lastEnvelopeComponent = null;
      this.lastScriptSignature = null;
      (_d = (_c = this.options).onRouteChanged) == null ? void 0 : _d.call(_c, this.currentRoute);
      void this.load();
    }
    applyServerNavigation(nav) {
      if (!nav || !Object.keys(nav).length) return;
      if (nav.back === true) {
        microtask(() => this.back());
        return;
      }
      if (nav.refresh === true) {
        microtask(() => this.refresh());
        return;
      }
      const to = nav.redirectTo != null ? String(nav.redirectTo) : "";
      if (to) {
        const replace2 = nav.replace === true;
        if (to !== this.currentRoute || replace2) microtask(() => this.navigate(to, replace2));
      }
    }
    // ---------------------------------------------------------------------------
    // Loading
    // ---------------------------------------------------------------------------
    async load() {
      const generation2 = ++this.loadGeneration;
      this.loading = true;
      this.loadError = null;
      this.paint();
      try {
        const payload = await this.loadPayload();
        if (generation2 !== this.loadGeneration || this.disposed) return;
        this.payload = payload;
        this.loading = false;
        this.onPayload();
      } catch (e) {
        if (generation2 !== this.loadGeneration || this.disposed) return;
        this.loading = false;
        this.loadError = e;
        this.paint();
      }
    }
    async loadPayload() {
      var _a, _b, _c, _d;
      await this.disposeClientComps();
      this.compSeq = 0;
      await ((_a = this.options.auth) == null ? void 0 : _a.store.ensureReady());
      const loader = (_b = this.options.loader) != null ? _b : (r, o) => this.httpLoader(r, o);
      let payload = await loader(this.currentRoute, { props: this.options.props, headers: this.options.headers });
      this.captureAuth(payload);
      const auth = this.options.auth;
      if (auth && !this.options.loader) {
        const nav = payload.navigation;
        if (isMap(nav) && String((_c = nav.redirectTo) != null ? _c : "") === auth.loginRoute && auth.store.refreshToken) {
          if (await this.tryRefresh()) {
            payload = await this.httpLoader(this.currentRoute, { props: this.options.props, headers: this.options.headers });
            this.captureAuth(payload);
          }
        }
      }
      const envelope = envelopeFromJson(payload);
      const component = await this.resolveClientComponentNodes(envelope.component, (_d = envelope.clientComponents) != null ? _d : null);
      return __spreadProps(__spreadValues({}, payload), { component });
    }
    onPayload() {
      const payload = this.payload;
      if (!payload) return;
      let envelope;
      try {
        envelope = envelopeFromJson(payload);
      } catch (e) {
        this.loadError = e;
        this.paint();
        return;
      }
      this.lastEnvelopeComponent = envelope.component;
      this.triggerScriptExecution(envelope);
      this.applyServerNavigation(envelope.navigation);
      if (envelope.stylesheet) {
        const key = stableKey(envelope.stylesheet);
        if (key !== this.lastStylesheetKey) {
          this.lastStylesheetKey = key;
          this.surface.engine.loadStylesheet(envelope.stylesheet);
        }
      }
      this.paint();
    }
    /** Put the current state on the surface (FutureBuilder.build). */
    paint() {
      var _a;
      if (this.disposed) return;
      const s = this.surface;
      if (this.loading) {
        const fallback = this.previousComponent;
        if (fallback) {
          s.decorate = (content) => w("stack", { fit: "loose" }, [
            content,
            w("positioned", { top: 0, left: 0, right: 0 }, w("control", { kind: "progress", view: { variant: "linear", value: null, strokeWidth: 2, colors: { indicator: M3.primary, track: M3.secondaryContainer } } }))
          ]);
          s.setContent(fallback);
        } else {
          s.decorate = null;
          s.setOverlay(loadingIndicator());
        }
        return;
      }
      s.decorate = null;
      if (this.loadError != null) {
        s.setOverlay(
          w("align", { alignment: { x: 0, y: 0 } }, w("text", { text: `Next.js payload error on "${this.currentRoute}": ${errorText(this.loadError)}`, align: "center" }))
        );
        return;
      }
      if (!this.payload) {
        s.setOverlay(w("align", { alignment: { x: 0, y: 0 } }, w("text", { text: "Next.js payload was empty." })));
        return;
      }
      this.foldClientCompRenders();
      s.setContent((_a = this.scriptRendered) != null ? _a : this.lastEnvelopeComponent);
    }
    // ---------------------------------------------------------------------------
    // HTTP
    // ---------------------------------------------------------------------------
    buildUrl(route) {
      var _a;
      const base = ((_a = this.options.serverBaseUrl) != null ? _a : "").replace(/\/+$/, "");
      if (route.startsWith("http://") || route.startsWith("https://")) return route;
      if (!route || route === "/") return base;
      return `${base}${route.startsWith("/") ? route : `/${route}`}`;
    }
    authHeaders() {
      const a = this.options.auth;
      const t = a == null ? void 0 : a.store.accessToken;
      return t ? { authorization: `${a.bearerScheme} ${t}` } : {};
    }
    async request(req) {
      var _a;
      const fetch = platform().fetch;
      if (!fetch) throw new Error("This platform provides no HTTP client.");
      return fetch(__spreadValues({ timeoutMs: (_a = this.options.timeoutMs) != null ? _a : 12e4 }, req));
    }
    async httpLoader(route, o) {
      var _a, _b, _c, _d;
      if (!this.options.serverBaseUrl) throw new Error("serverBaseUrl is required when no custom loader is provided.");
      if (((_a = this.options.requestMode) != null ? _a : "routePath") === "routePath") {
        const url2 = this.buildUrl(route);
        const res2 = await this.request({
          url: url2,
          method: "GET",
          headers: __spreadValues(__spreadValues(__spreadValues({
            accept: "application/vnd.elpian+json, application/json",
            "x-elpian-route": route
          }, o.props && Object.keys(o.props).length ? { "x-elpian-props": JSON.stringify(o.props) } : {}), this.authHeaders()), (_b = o.headers) != null ? _b : {})
        });
        if (res2.status < 200 || res2.status >= 300) throw new Error(`Next.js route ${url2} returned HTTP ${res2.status}: ${res2.body}`);
        const decoded2 = JSON.parse(res2.body);
        if (!isMap(decoded2)) throw new Error("Next.js route response must decode to a JSON object.");
        return decoded2;
      }
      const url = this.buildUrl((_c = this.options.endpoint) != null ? _c : "/api/elpian-render");
      const res = await this.request({
        url,
        method: "POST",
        headers: __spreadValues(__spreadValues({ "content-type": "application/json" }, this.authHeaders()), (_d = o.headers) != null ? _d : {}),
        body: JSON.stringify(buildRouteRequest(route, o.props))
      });
      if (res.status < 200 || res.status >= 300) throw new Error(`Next.js endpoint ${url} returned HTTP ${res.status}: ${res.body}`);
      const decoded = JSON.parse(res.body);
      if (!isMap(decoded)) throw new Error("Next.js payload must decode to a JSON object.");
      return decoded;
    }
    async postJson(route, body) {
      var _a;
      const res = await this.request({
        url: this.buildUrl(route),
        method: "POST",
        headers: __spreadValues(__spreadValues({
          "content-type": "application/json",
          accept: "application/vnd.elpian+json, application/json",
          "x-elpian-route": route
        }, this.authHeaders()), (_a = this.options.headers) != null ? _a : {}),
        body: JSON.stringify(body != null ? body : null)
      });
      const decoded = JSON.parse(res.body);
      if (!isMap(decoded)) throw new Error("Action response must decode to a JSON object.");
      return decoded;
    }
    captureAuth(envelope) {
      const a = this.options.auth;
      if (!a || !isMap(envelope.meta)) return;
      const meta = envelope.meta;
      if (meta.clearAuth === true) {
        a.store.clear();
        return;
      }
      if ("auth" in meta) {
        if (isMap(meta.auth)) a.store.save({ access: meta.auth.accessToken != null ? String(meta.auth.accessToken) : null, refresh: meta.auth.refreshToken != null ? String(meta.auth.refreshToken) : null });
        else if (meta.auth == null) a.store.clear();
      }
    }
    async tryRefresh() {
      const a = this.options.auth;
      const rt = a == null ? void 0 : a.store.refreshToken;
      if (!a || !rt) return false;
      try {
        const env2 = await this.postJson(a.refreshRoute, { refreshToken: rt });
        const auth = isMap(env2.meta) ? env2.meta.auth : null;
        if (isMap(auth) && auth.accessToken != null) {
          a.store.save({ access: String(auth.accessToken), refresh: auth.refreshToken != null ? String(auth.refreshToken) : null });
          return true;
        }
      } catch (e) {
      }
      a.store.clear();
      return false;
    }
    async handleFormSubmit(action, values) {
      try {
        const env2 = await this.postJson(action, values);
        this.captureAuth(env2);
        if (isMap(env2.navigation) && Object.keys(env2.navigation).length) {
          this.applyServerNavigation(env2.navigation);
          return null;
        }
        const inline = firstText(env2.component);
        if (inline != null) return inline;
        if (isMap(env2.component)) this.setScriptRendered(env2.component);
        return null;
      } catch (e) {
        return `Request failed: ${errorText(e)}`;
      }
    }
    // ---------------------------------------------------------------------------
    // Client components
    // ---------------------------------------------------------------------------
    async resolveClientComponentNodes(node, packed) {
      var _a, _b;
      const type = String((_a = node.type) != null ? _a : "");
      if (type === "clientComp" || type === "client-component") {
        return (_b = await this.resolveClientComponentNode(node, packed)) != null ? _b : { type: "Text", props: { text: "Failed to execute client component jsCode" } };
      }
      if (Array.isArray(node.children)) {
        const children = [];
        for (const c of node.children) children.push(isMap(c) ? await this.resolveClientComponentNodes(c, packed) : c);
        return __spreadProps(__spreadValues({}, node), { children });
      }
      return node;
    }
    async resolveClientComponentNode(node, packed) {
      var _a, _b, _c, _d, _e, _f;
      const props = isMap(node.props) ? __spreadValues({}, node.props) : {};
      let jsCode = node.jsCode != null ? String(node.jsCode) : props.jsCode != null ? String(props.jsCode) : null;
      let entry = String((_b = (_a = node.jsEntryFunction) != null ? _a : props.jsEntryFunction) != null ? _b : "MainComponent");
      if (!jsCode) {
        const p = this.findPackedScript(node, props, packed);
        jsCode = (_c = p == null ? void 0 : p.jsCode) != null ? _c : null;
        entry = (_d = p == null ? void 0 : p.jsEntryFunction) != null ? _d : entry;
      }
      if (!jsCode && this.options.serverBaseUrl) {
        const f = await this.fetchClientComponentScript(node, props);
        jsCode = (_e = f == null ? void 0 : f.jsCode) != null ? _e : null;
        entry = (_f = f == null ? void 0 : f.jsEntryFunction) != null ? _f : entry;
      }
      if (!jsCode) return null;
      return this.mountClientComponent(jsCode, entry, props, node.style);
    }
    async mountClientComponent(jsCode, entryFunction, props, style) {
      const mountId = `cc${this.compSeq++}`;
      const machineId = `nextjs-${mountId}-${Date.now()}${Math.floor(Math.random() * 1e3)}`;
      let vm;
      try {
        vm = await QuickJsVm.fromCode(machineId, jsCode);
      } catch (e) {
        platform().log("warn", `NextjsSession: clientComp "${mountId}" create failed: ${e}`);
        return null;
      }
      const record = { mountId, vm, style: isMap(style) ? style : null, timer: null, latest: null, dirty: false };
      this.liveComps.set(mountId, record);
      let resolveFirst = () => {
      };
      let firstDone = false;
      const firstRender = new Promise((r) => resolveFirst = r);
      const handler = new HostHandler(this.surface.engine.services, {
        onRender: (view) => {
          record.latest = ClientCompRouting.namespaceHandlers(view, mountId);
          if (!firstDone) {
            firstDone = true;
            resolveFirst();
          } else {
            record.dirty = true;
            this.paint();
          }
        },
        onPrintln: (m) => platform().log("info", `NextjsSession[${mountId}]: ${m}`)
      });
      record.timer = new VmTimerHostApi(
        async (fn, input) => {
          if (input == null) await vm.callFunction(fn);
          else await vm.callFunctionWithInput(fn, input);
        },
        (m) => platform().log("warn", `NextjsSession[${mountId} timer]: ${m}`)
      );
      vm.registerHostHandlers(this.hostHandlers(handler, record.timer, () => record.vm));
      try {
        await vm.run();
        await vm.callFunctionWithInput(entryFunction, JSON.stringify(props));
        let timeout = null;
        await Promise.race([
          firstRender,
          new Promise((r) => {
            timeout = platform().setTimeout(() => {
              platform().log("warn", `NextjsSession: clientComp "${mountId}" first render timed out`);
              r();
            }, 3e3);
          })
        ]);
        if (timeout != null) platform().clearTimeout(timeout);
      } catch (e) {
        platform().log("warn", `NextjsSession: clientComp "${mountId}" exec failed: ${e}`);
        this.liveComps.delete(mountId);
        await disposeComp(record);
        return null;
      }
      record.dirty = false;
      return { type: ScopeContract.type, key: `${mountId}__scope`, props: {}, children: [this.compContent(record)] };
    }
    compContent(record) {
      var _a;
      const node = __spreadProps(__spreadValues({}, (_a = record.latest) != null ? _a : { type: "div" }), { key: record.mountId });
      if (record.style) node.style = isMap(node.style) ? __spreadValues(__spreadValues({}, record.style), node.style) : record.style;
      return node;
    }
    foldClientCompRenders() {
      var _a;
      if (!this.liveComps.size) return;
      const tree = (_a = this.scriptRendered) != null ? _a : this.lastEnvelopeComponent;
      if (!tree) return;
      let any = false;
      for (const r of this.liveComps.values()) {
        if (!r.dirty || !r.latest) continue;
        if (ScopePatch.replaceByKey(tree, r.mountId, this.compContent(r))) {
          r.dirty = false;
          any = true;
        }
      }
      if (any) this.scriptRendered = tree;
    }
    async disposeClientComps() {
      const comps = [...this.liveComps.values()];
      this.liveComps.clear();
      for (const c of comps) await disposeComp(c);
    }
    findPackedScript(node, props, packed) {
      if (!packed || !Object.keys(packed).length) return null;
      for (const key of lookupKeys(node, props)) {
        const p = normalizePacked(packed[key]);
        if (p) return p;
      }
      const values = Object.values(packed);
      return values.length === 1 ? normalizePacked(values[0]) : null;
    }
    async fetchClientComponentScript(node, props) {
      var _a, _b;
      const keys = lookupKeys(node, props);
      for (const k of keys) {
        const c = this.clientComponentCache.get(k);
        const p = c ? normalizePacked(c) : null;
        if (p) return p;
      }
      try {
        const res = await this.request({
          url: this.buildUrl((_a = this.options.endpoint) != null ? _a : "/api/elpian-client-component"),
          method: "POST",
          headers: __spreadValues(__spreadValues({ "content-type": "application/json", accept: "application/json" }, this.authHeaders()), (_b = this.options.headers) != null ? _b : {}),
          body: JSON.stringify({ route: this.currentRoute, lookupKeys: keys, componentNode: node })
        });
        if (res.status < 200 || res.status >= 300) return null;
        const decoded = JSON.parse(res.body);
        if (!isMap(decoded)) return null;
        if (isMap(decoded.clientComponents)) {
          for (const [k, v] of Object.entries(decoded.clientComponents)) {
            if (isMap(v)) this.clientComponentCache.set(k, __spreadValues({}, v));
            else if (typeof v === "string") this.clientComponentCache.set(k, { jsCode: v });
          }
        }
        const direct = normalizePacked(decoded);
        if (direct) {
          for (const k of keys) this.clientComponentCache.set(k, __spreadValues({}, direct));
          return direct;
        }
        for (const k of keys) {
          const c = this.clientComponentCache.get(k);
          const p = c ? normalizePacked(c) : null;
          if (p) return p;
        }
      } catch (e) {
      }
      return null;
    }
    // ---------------------------------------------------------------------------
    // Page scripts
    // ---------------------------------------------------------------------------
    triggerScriptExecution(envelope) {
      var _a, _b, _c;
      if (!envelope.jsCode && !envelope.vmAstJson) return;
      const signature = `${this.currentRoute}|${(_a = envelope.jsEntryFunction) != null ? _a : "MainComponent"}|${(_b = envelope.jsCode) != null ? _b : ""}|${(_c = envelope.vmAstJson) != null ? _c : ""}`;
      if (this.lastScriptSignature === signature) return;
      this.lastScriptSignature = signature;
      void this.executeEnvelopeScripts(envelope);
    }
    async executeEnvelopeScripts(envelope) {
      var _a, _b, _c, _d, _e;
      try {
        if (envelope.jsCode) await this.runPageScript(envelope.jsCode, (_a = envelope.jsEntryFunction) != null ? _a : "MainComponent");
        if (envelope.vmAstJson) {
          await ElpianVm.initialize();
          const vm = await ElpianVm.fromAst(`nextjs-ast-${Date.now()}`, envelope.vmAstJson);
          if (!vm) throw new Error("Failed to create Elpian VM from AST payload.");
          vm.registerHostHandler("render", (_api, payload) => {
            this.setScriptRendered(decodeRenderPayload(payload));
            return HOST_OK;
          });
          try {
            const output = await vm.run();
            this.setScriptRendered(decodeRenderPayload(output));
            (_c = (_b = this.options).onScriptExecuted) == null ? void 0 : _c.call(_b, { route: this.currentRoute, kind: "vmAst", output });
          } finally {
            await vm.dispose();
          }
        }
      } catch (e) {
        (_e = (_d = this.options).onScriptError) == null ? void 0 : _e.call(_d, e);
        platform().log("warn", `NextjsSession script execution error: ${e}`);
      }
    }
    async runPageScript(jsCode, entryFunction) {
      var _a, _b;
      await this.disposePageVm();
      const vm = await QuickJsVm.fromCode(`nextjs-page-${Date.now()}`, jsCode);
      this.pageVm = vm;
      const handler = new HostHandler(this.surface.engine.services, {
        onRender: (view, scopeKey) => this.applyClientRender(view, scopeKey),
        onPrintln: (m) => platform().log("info", `NextjsSession[page]: ${m}`)
      });
      this.pageTimers = new VmTimerHostApi(
        async (fn, input) => {
          if (!this.pageVm) return;
          if (input == null) await vm.callFunction(fn);
          else await vm.callFunctionWithInput(fn, input);
        },
        (m) => platform().log("warn", `NextjsSession[page timer]: ${m}`)
      );
      vm.registerHostHandlers(this.hostHandlers(handler, this.pageTimers, () => this.pageVm));
      await vm.run();
      if (entryFunction) {
        const initial = await vm.callFunction(entryFunction);
        const seeded = decodeRenderPayload(initial);
        if (seeded && seeded.type != null && this.scriptRendered == null) this.setScriptRendered(seeded);
      }
      (_b = (_a = this.options).onScriptExecuted) == null ? void 0 : _b.call(_a, { route: this.currentRoute, kind: "js", output: "" });
    }
    hostHandlers(handler, timers, vm) {
      const out = {};
      for (const api of allHostApiNames) out[api] = (n, p) => handler.handleHostCall(n, p);
      for (const api of timerApiNames) out[api] = (n, p) => timers.handle(n, p);
      out.fetch = (_n, p) => {
        void this.hostFetch(vm(), p);
        return HOST_OK;
      };
      out.submit = (_n, p) => {
        void this.hostSubmit(vm(), p);
        return HOST_OK;
      };
      out.navigate = (_n, p) => this.hostNavigate(p);
      out.mountFragment = (_n, p) => {
        void this.hostMountFragment(vm(), p);
        return HOST_OK;
      };
      return out;
    }
    async hostFetch(vm, payload) {
      var _a;
      try {
        const args = firstArgMap(payload);
        const route = args.route != null ? String(args.route) : "";
        if (!route) return;
        const loader = (_a = this.options.loader) != null ? _a : (r, o) => this.httpLoader(r, o);
        const envelope = await loader(route, { headers: this.options.headers });
        const onData = args.onData != null ? String(args.onData) : "";
        if (onData && vm) await vm.callFunctionWithInput(onData, JSON.stringify(envelope));
      } catch (e) {
        platform().log("warn", `NextjsSession[fetch]: ${e}`);
      }
    }
    async hostSubmit(vm, payload) {
      try {
        const args = firstArgMap(payload);
        const route = args.route != null ? String(args.route) : "";
        if (!route) return;
        const env2 = await this.postJson(route, args.body);
        this.captureAuth(env2);
        if (isMap(env2.navigation) && Object.keys(env2.navigation).length) this.applyServerNavigation(env2.navigation);
        const onResult = args.onResult != null ? String(args.onResult) : "";
        if (onResult && vm) await vm.callFunctionWithInput(onResult, JSON.stringify(env2));
      } catch (e) {
        platform().log("warn", `NextjsSession[submit]: ${e}`);
      }
    }
    async hostMountFragment(vm, payload) {
      var _a;
      try {
        const args = firstArgMap(payload);
        const route = args.route != null ? String(args.route) : "";
        if (!route) return;
        const scopeKey = args.scopeKey != null ? String(args.scopeKey) : null;
        const loader = (_a = this.options.loader) != null ? _a : (r, o) => this.httpLoader(r, o);
        const envelope = await loader(route, { headers: this.options.headers });
        this.captureAuth(envelope);
        if (isMap(envelope.navigation) && Object.keys(envelope.navigation).length) this.applyServerNavigation(envelope.navigation);
        if (isMap(envelope.component)) {
          const resolved = await this.resolveClientComponentNodes(envelope.component, isMap(envelope.clientComponents) ? envelope.clientComponents : null);
          this.applyClientRender(resolved, scopeKey);
        }
        const onData = args.onData != null ? String(args.onData) : "";
        if (onData && vm) await vm.callFunctionWithInput(onData, JSON.stringify(envelope));
      } catch (e) {
        platform().log("warn", `NextjsSession[mountFragment]: ${e}`);
      }
    }
    hostNavigate(payload) {
      try {
        const nav = firstArgMap(payload);
        if (Object.keys(nav).length) this.applyServerNavigation(nav);
      } catch (e) {
        platform().log("warn", `NextjsSession[page navigate]: ${e}`);
      }
      return HOST_OK;
    }
    applyClientRender(view, scopeKey) {
      var _a;
      if (this.disposed) return;
      const key = ScopePatch.normalizeKey(scopeKey);
      if (key == null) {
        this.setScriptRendered(view);
        return;
      }
      const next = ScopePatch.applyBounded((_a = this.scriptRendered) != null ? _a : this.lastEnvelopeComponent, view, key);
      if (next == null) {
        platform().log("debug", `NextjsSession: scoped render targeted missing scope "${key}"; keeping current screen.`);
        return;
      }
      this.setScriptRendered(next);
    }
    setScriptRendered(component) {
      if (!component || this.disposed) return;
      this.scriptRendered = component;
      if (!this.loading) this.paint();
    }
    async disposePageVm() {
      var _a;
      (_a = this.pageTimers) == null ? void 0 : _a.dispose();
      this.pageTimers = null;
      const vm = this.pageVm;
      this.pageVm = null;
      if (vm) {
        try {
          await vm.dispose();
        } catch (e) {
        }
      }
    }
    // ---------------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------------
    async routeEvent(event) {
      var _a, _b, _c, _d, _e;
      const nodeId = event.currentTarget;
      if (!nodeId) return;
      const handler = (_b = (_a = this.surface.engine.services.events.getNode(nodeId)) == null ? void 0 : _a.events) == null ? void 0 : _b[event.type];
      if (typeof handler !== "string" || !handler) return;
      const r = ClientCompRouting.parse(handler);
      const vm = r ? (_d = (_c = this.liveComps.get(r.mountId)) == null ? void 0 : _c.vm) != null ? _d : null : this.pageVm;
      const fn = (_e = r == null ? void 0 : r.fn) != null ? _e : handler;
      if (!vm) return;
      const input = { type: event.type };
      if (event.position) {
        input.x = event.position.x;
        input.y = event.position.y;
      } else if (event.value !== void 0) input.value = event.value;
      try {
        await vm.callFunctionWithInput(fn, JSON.stringify(input));
      } catch (e) {
        try {
          await vm.callFunction(fn);
        } catch (e2) {
          platform().log("warn", `NextjsSession: event handler "${handler}" failed: ${e2}`);
        }
      }
    }
    async dispatchSceneTap(props) {
      if (this.options.onSceneTap) {
        this.options.onSceneTap(props);
        return;
      }
      const vm = this.pageVm;
      if (vm) {
        try {
          await vm.callFunctionWithInput("__onSceneTap", JSON.stringify(props));
          return;
        } catch (e) {
        }
      }
      const href = props.panelHref;
      if (typeof href === "string" && href) this.navigate(href);
    }
    viewportChanged() {
      this.surface.viewportChanged();
    }
    async dispose() {
      if (this.disposed) return;
      this.disposed = true;
      this.loadGeneration++;
      await this.disposePageVm();
      await this.disposeClientComps();
      this.surface.dispose();
    }
  };
  async function disposeComp(c) {
    var _a;
    (_a = c.timer) == null ? void 0 : _a.dispose();
    c.timer = null;
    try {
      await c.vm.dispose();
    } catch (e) {
    }
  }
  function lookupKeys(node, props) {
    const fields = ["clientComponentKey", "componentKey", "componentId", "id", "name", "path", "componentPath", "module"];
    const keys = /* @__PURE__ */ new Set();
    for (const src of [node, props]) {
      for (const f of fields) {
        const t = src[f] != null ? String(src[f]).trim() : "";
        if (t) keys.add(t);
      }
    }
    if (!keys.size) keys.add(`anon-${hashString(stableKey(node))}-${hashString(stableKey(props))}`);
    return [...keys];
  }
  function hashString(s) {
    let h = 0;
    for (let i = 0; i < s.length; i++) h = Math.imul(31, h) + s.charCodeAt(i) | 0;
    return Math.abs(h);
  }
  function normalizePacked(raw) {
    if (typeof raw === "string" && raw.trim()) return { jsCode: raw.trim(), jsEntryFunction: "MainComponent" };
    if (isMap(raw)) {
      const js = raw.jsCode != null ? String(raw.jsCode) : "";
      if (!js.trim()) return null;
      const entry = raw.jsEntryFunction != null ? String(raw.jsEntryFunction) : "";
      return { jsCode: js, jsEntryFunction: entry || "MainComponent" };
    }
    return null;
  }
  function decodeRenderPayload(payload) {
    try {
      const d = JSON.parse(payload);
      if (isMap(d)) return isMap(d.component) ? d.component : d;
    } catch (e) {
    }
    return null;
  }
  function firstArgMap(payload) {
    let parsed;
    try {
      parsed = JSON.parse(payload);
    } catch (e) {
      return {};
    }
    if (Array.isArray(parsed) && parsed.length) parsed = parsed[0];
    if (typeof parsed === "string") {
      try {
        parsed = JSON.parse(parsed);
      } catch (e) {
        return {};
      }
    }
    return isMap(parsed) ? parsed : {};
  }
  function firstText(node) {
    if (!isMap(node)) return null;
    if (isMap(node.props) && typeof node.props.text === "string") {
      const t = node.props.text;
      if (t.trim().length > 2 && !t.includes("\u2715")) return t;
    }
    if (Array.isArray(node.children)) {
      for (const c of node.children) {
        const r = firstText(c);
        if (r != null) return r;
      }
    }
    return null;
  }
  function originOf(url) {
    if (!url) return null;
    const m = /^([a-zA-Z][\w+.-]*:\/\/[^/?#]+)/.exec(url);
    return m ? m[1] : null;
  }
  function errorText(e) {
    return e instanceof Error ? e.message : String(e);
  }
  function microtask(fn) {
    void Promise.resolve().then(fn);
  }

  // core/src/superapp/superapp.ts
  var MiniAppManifests = {
    create(m) {
      return __spreadValues({
        version: "0.0.0",
        entrypoint: "main",
        runtime: "elpian",
        requestedCapabilities: /* @__PURE__ */ new Set(),
        requestedLimits: null,
        allowsChildren: false,
        metadata: {}
      }, m);
    },
    fromJson(json) {
      const caps = /* @__PURE__ */ new Set();
      for (const raw of Array.isArray(json.requestedCapabilities) ? json.requestedCapabilities : []) {
        const c = capabilityFromWireName(String(raw));
        if (c) caps.add(c);
      }
      const runtime = json.runtime === "quickJs" || json.runtime === "quickjs" ? "quickjs" : json.runtime === "wasm" ? "wasm" : "elpian";
      return {
        id: typeof json.id === "string" ? json.id : "",
        name: typeof json.name === "string" ? json.name : typeof json.id === "string" ? json.id : "Untitled",
        version: typeof json.version === "string" ? json.version : "0.0.0",
        entrypoint: typeof json.entrypoint === "string" ? json.entrypoint : "main",
        runtime,
        requestedCapabilities: caps,
        requestedLimits: isMap(json.requestedLimits) ? Limits.fromJson(json.requestedLimits) : null,
        allowsChildren: json.allowsChildren === true,
        metadata: isMap(json.metadata) ? json.metadata : {}
      };
    },
    toJson(m) {
      return __spreadValues(__spreadProps(__spreadValues({
        id: m.id,
        name: m.name,
        version: m.version,
        entrypoint: m.entrypoint,
        runtime: m.runtime === "quickjs" ? "quickJs" : m.runtime,
        requestedCapabilities: [...m.requestedCapabilities]
      }, m.requestedLimits ? { requestedLimits: Limits.toJson(m.requestedLimits) } : {}), {
        allowsChildren: m.allowsChildren
      }), Object.keys(m.metadata).length ? { metadata: m.metadata } : {});
    },
    validate(m) {
      if (!m.id) return "a mini app must declare an id";
      if (m.id.includes("::")) return 'a mini app id may not contain "::"';
      if (!m.entrypoint) return "a mini app must declare an entrypoint";
      return null;
    }
  };
  var MiniAppGrants = {
    /** Render-only: no network, storage, clock, randomness or nested apps. */
    get untrusted() {
      return { capabilities: /* @__PURE__ */ new Set(["render", "dom", "canvas", "surface", "logging"]), limits: Limits.sandboxed, mayHostChildren: false, allowedApis: null };
    },
    get trusted() {
      return { capabilities: new Set(CAPABILITIES), limits: Limits.unlimited, mayHostChildren: true, allowedApis: null };
    }
  };
  var MiniAppPolicy = class _MiniAppPolicy {
    constructor(manifest, grant, capabilities, limits, mayHostChildren, deniedRequests) {
      this.manifest = manifest;
      this.grant = grant;
      this.capabilities = capabilities;
      this.limits = limits;
      this.mayHostChildren = mayHostChildren;
      this.deniedRequests = deniedRequests;
    }
    static resolve(manifest, grant) {
      const requested = manifest.requestedCapabilities.size === 0 ? grant.capabilities : manifest.requestedCapabilities;
      const allowed = new Set([...requested].filter((c) => grant.capabilities.has(c)));
      const denied = new Set([...requested].filter((c) => !grant.capabilities.has(c)));
      return new _MiniAppPolicy(
        manifest,
        grant,
        allowed,
        _MiniAppPolicy.tightest(manifest.requestedLimits, grant.limits),
        manifest.allowsChildren && grant.mayHostChildren && allowed.has("vm_manage"),
        denied
      );
    }
    allowsApi(apiName, capability) {
      if (!this.capabilities.has(capability)) return false;
      return this.grant.allowedApis == null || this.grant.allowedApis.has(apiName);
    }
    static tightest(a, b) {
      return a == null ? b : Limits.tightest(a, b);
    }
  };
  var MiniAppException = class extends Error {
    constructor(appId, reason) {
      super(`MiniAppException(${appId}): ${reason}`);
      this.appId = appId;
      this.reason = reason;
    }
  };
  var MiniAppHost = class _MiniAppHost {
    constructor(policy, runtime, parent) {
      this.policy = policy;
      this.runtime = runtime;
      this.parent = parent;
      this.kids = [];
      this.disposed = false;
      this.sessions = [];
      this.machineId = runtime.machineId;
      this.engineServices = new ElpianServices(this.machineId);
    }
    get id() {
      return this.policy.manifest.id;
    }
    get governor() {
      return this.runtime.governor;
    }
    get children() {
      return [...this.kids];
    }
    get isDisposed() {
      return this.disposed;
    }
    static async launch(opts) {
      var _a, _b;
      const { manifest, grant, source } = opts;
      const parent = (_a = opts.parent) != null ? _a : null;
      const invalid = MiniAppManifests.validate(manifest);
      if (invalid) throw new MiniAppException(manifest.id, invalid);
      const policy = MiniAppPolicy.resolve(manifest, grant);
      const machineId = (_b = opts.machineIdOverride) != null ? _b : parent == null ? manifest.id : `${parent.machineId}.${manifest.id}`;
      const runtime = await startRuntime(manifest, source, machineId);
      const host2 = new _MiniAppHost(policy, runtime, parent);
      if (parent) await ElpianVm.treeGovernor.adopt(parent.machineId, machineId);
      await host2.governor.sandbox(policy.capabilities);
      await host2.governor.setLimits(policy.limits);
      return host2;
    }
    /** A HostHandler whose every call passes this app's policy first. */
    createHostHandler(cb = {}) {
      return new HostHandler(this.engineServices, __spreadProps(__spreadValues({}, cb), { onAuthorize: (api) => this.authorizes(api) }));
    }
    authorizes(apiName) {
      var _a;
      const capability = (_a = capabilityFromWireName(capabilityFor(apiName))) != null ? _a : "other";
      return this.policy.allowsApi(apiName, capability);
    }
    /**
     * Render this mini app on the platform surface [surfaceId]: runs the
     * program and its manifest entrypoint, with this app's policy gating every
     * host call.
     */
    async mount(surfaceId, options = {}) {
      var _a, _b;
      if (this.disposed) throw new MiniAppException(this.id, "cannot mount a disposed app");
      const session = new MiniAppSession(surfaceId, __spreadProps(__spreadValues({}, options), {
        machineId: this.machineId,
        runtime: this.policy.manifest.runtime,
        runtimeClient: this.runtime,
        entryFunction: (_a = options.entryFunction) != null ? _a : this.policy.manifest.entrypoint,
        onAuthorize: (api) => this.authorizes(api),
        surface: __spreadProps(__spreadValues({}, (_b = options.surface) != null ? _b : {}), { services: this.engineServices })
      }));
      this.sessions.push(session);
      await session.start();
      return session;
    }
    async spawnChild(opts) {
      var _a;
      if (this.disposed) throw new MiniAppException(this.id, "cannot spawn a child from a disposed app");
      if (!this.policy.mayHostChildren) {
        throw new MiniAppException(
          this.id,
          "this mini app is not permitted to host children \u2014 it needs `allowsChildren` in its manifest, `mayHostChildren` in its grant, and the vm_manage capability"
        );
      }
      const child = await _MiniAppHost.launch({ manifest: opts.manifest, grant: this.narrow((_a = opts.grant) != null ? _a : null), source: opts.source, parent: this });
      this.kids.push(child);
      return child;
    }
    narrow(requested) {
      const p = this.policy;
      const base = requested != null ? requested : { capabilities: p.capabilities, limits: p.limits, mayHostChildren: p.mayHostChildren, allowedApis: p.grant.allowedApis };
      return {
        capabilities: new Set([...base.capabilities].filter((c) => p.capabilities.has(c))),
        limits: MiniAppPolicy.tightest(base.limits, p.limits),
        mayHostChildren: base.mayHostChildren && p.mayHostChildren,
        allowedApis: intersectApis(base.allowedApis, p.grant.allowedApis)
      };
    }
    usage() {
      return this.governor.usage();
    }
    branchUsage() {
      return this.governor.subtreeUsage();
    }
    async pressure() {
      return pressureAgainst(await this.branchUsage(), this.policy.limits);
    }
    async dispose() {
      if (this.disposed) return;
      this.disposed = true;
      for (const child of [...this.kids]) await child.dispose();
      this.kids.length = 0;
      for (const s of this.sessions) await s.dispose();
      this.sessions = [];
      try {
        await this.runtime.dispose();
      } finally {
        this.engineServices.dispose();
      }
    }
  };
  async function startRuntime(manifest, source, machineId) {
    switch (manifest.runtime) {
      case "elpian": {
        await ElpianVm.initialize();
        const vm = await ElpianVm.fromCode(machineId, source);
        if (!vm) throw new MiniAppException(manifest.id, `the Elpian runtime could not start it: ${ElpianVm.lastApiError}`);
        return vm;
      }
      case "quickjs":
        return QuickJsVm.fromCode(machineId, source);
      case "wasm":
        return WasmVm.fromCode(machineId, source);
    }
  }
  function intersectApis(a, b) {
    if (a == null) return b;
    if (b == null) return a;
    return new Set([...a].filter((x) => b.has(x)));
  }

  // core/src/bridge/sessions.ts
  var SessionRegistry = class {
    constructor(emit) {
      this.emit = emit;
      this.entries = /* @__PURE__ */ new Map();
    }
    has(surfaceId) {
      return this.entries.has(surfaceId);
    }
    get(surfaceId) {
      return this.entries.get(surfaceId);
    }
    /** Open a session of [kind] on [surfaceId] (closing any session already there). */
    async open(kind, surfaceId, options) {
      var _a, _b, _c, _d, _e, _f, _g, _h, _i, _j, _k, _l, _m, _n, _o;
      await this.close(surfaceId);
      const emit = (event, payload = null) => this.emit(surfaceId, event, payload);
      const surfaceOpts = {
        document: options.document === true,
        host: {
          openUrl: (url) => {
            var _a2, _b2;
            return (_b2 = (_a2 = platform()).openUrl) == null ? void 0 : _b2.call(_a2, url);
          },
          sceneTap: (props) => emit("sceneTap", props),
          baseUrl: () => typeof options.baseUrl === "string" ? options.baseUrl : null,
          navigate: (href, replace2) => emit("navigate", { href, replace: replace2 })
        }
      };
      let entry;
      switch (kind) {
        case "json": {
          const surface = new ElpianSurface(surfaceId, surfaceOpts);
          if (options.stylesheet) surface.engine.loadStylesheet(options.stylesheet);
          if (isMap(options.view)) surface.setContent(options.view);
          entry = {
            kind,
            surface,
            dispose: () => surface.dispose(),
            viewportChanged: () => surface.viewportChanged(),
            call: (method, args) => {
              var _a2, _b2, _c2;
              switch (method) {
                case "setContent":
                  surface.setContent(isMap(args[0]) ? args[0] : null);
                  return null;
                case "patch": {
                  const next = ScopePatch.applyBounded(surface.currentContent, args[0], (_a2 = args[1]) != null ? _a2 : null);
                  if (next) surface.setContent(next);
                  return next != null;
                }
                case "merge":
                  surface.setContent(deepMerge((_b2 = surface.currentContent) != null ? _b2 : {}, (_c2 = args[0]) != null ? _c2 : {}));
                  return null;
                case "loadStylesheet":
                  surface.engine.loadStylesheet(args[0]);
                  surface.scheduleRender();
                  return null;
                case "clearStylesheets":
                  surface.engine.clearStylesheets();
                  surface.scheduleRender();
                  return null;
              }
              throw new Error(`json session has no method ${method}`);
            }
          };
          break;
        }
        case "miniapp": {
          const session = new MiniAppSession(surfaceId, {
            machineId: String((_a = options.machineId) != null ? _a : surfaceId),
            runtime: runtimeOf(options.runtime),
            code: (_b = options.code) != null ? _b : null,
            astJson: (_c = options.astJson) != null ? _c : isMap(options.ast) ? JSON.stringify(options.ast) : null,
            bytecodeBase64: (_d = options.bytecodeBase64) != null ? _d : null,
            stylesheet: (_e = options.stylesheet) != null ? _e : null,
            entryFunction: (_f = options.entryFunction) != null ? _f : null,
            entryInput: options.entryInput != null ? typeof options.entryInput === "string" ? options.entryInput : JSON.stringify(options.entryInput) : null,
            hostEnvironment: isMap(options.hostEnvironment) ? options.hostEnvironment : void 0,
            showDefaultStates: options.showDefaultStates !== false,
            onPrintln: (m) => emit("println", m),
            onUpdateApp: (d) => emit("updateApp", d),
            onError: (m) => emit("error", m),
            onReady: () => emit("ready"),
            onCallRefused: (api) => emit("callRefused", api),
            onUnservicedApi: (api, advertised) => emit("unservicedApi", { api, advertised }),
            surface: surfaceOpts
          });
          entry = {
            kind,
            surface: session.surface,
            dispose: () => session.dispose(),
            viewportChanged: () => session.viewportChanged(),
            call: (method, args) => {
              var _a2, _b2, _c2, _d2, _e2, _f2, _g2, _h2;
              switch (method) {
                case "callFunction":
                  return session.callFunction(String(args[0]), args[1] == null ? null : typeof args[1] === "string" ? args[1] : JSON.stringify(args[1]));
                case "usage":
                  return (_a2 = session.runtime) == null ? void 0 : _a2.governor.usage();
                case "state":
                  return (_b2 = session.runtime) == null ? void 0 : _b2.governor.state();
                case "pause":
                  return (_c2 = session.runtime) == null ? void 0 : _c2.governor.pause();
                case "resume":
                  return (_d2 = session.runtime) == null ? void 0 : _d2.governor.resumeExecution();
                case "terminate":
                  return (_e2 = session.runtime) == null ? void 0 : _e2.governor.terminate();
                case "setLimits":
                  return (_g2 = session.runtime) == null ? void 0 : _g2.governor.setLimits(Limits.fromJson((_f2 = args[0]) != null ? _f2 : {}));
                case "sandbox":
                  return (_h2 = session.runtime) == null ? void 0 : _h2.governor.sandbox(capsOf(args[0]));
                case "view":
                  return session.view;
              }
              throw new Error(`miniapp session has no method ${method}`);
            }
          };
          void session.start();
          break;
        }
        case "superapp": {
          const manifest = MiniAppManifests.fromJson(isMap(options.manifest) ? options.manifest : {});
          const grant = grantOf(options.grant);
          const host2 = await MiniAppHost.launch({ manifest, grant, source: String((_g = options.source) != null ? _g : "") }).catch((e) => {
            emit("error", String(e instanceof Error ? e.message : e));
            return null;
          });
          if (!host2) return;
          const session = await host2.mount(surfaceId, {
            stylesheet: (_h = options.stylesheet) != null ? _h : null,
            entryInput: options.entryInput != null ? typeof options.entryInput === "string" ? options.entryInput : JSON.stringify(options.entryInput) : null,
            showDefaultStates: options.showDefaultStates !== false,
            onPrintln: (m) => emit("println", m),
            onUpdateApp: (d) => emit("updateApp", d),
            onError: (m) => emit("error", m),
            onReady: () => emit("ready", { denied: [...host2.policy.deniedRequests] }),
            onCallRefused: (api) => emit("callRefused", api),
            onUnservicedApi: (api, advertised) => emit("unservicedApi", { api, advertised }),
            surface: surfaceOpts
          });
          entry = {
            kind,
            surface: session.surface,
            dispose: () => host2.dispose(),
            viewportChanged: () => session.viewportChanged(),
            call: async (method, args) => {
              var _a2, _b2;
              switch (method) {
                case "callFunction":
                  return session.callFunction(String(args[0]), args[1] == null ? null : typeof args[1] === "string" ? args[1] : JSON.stringify(args[1]));
                case "usage":
                  return host2.usage();
                case "branchUsage":
                  return host2.branchUsage();
                case "pressure":
                  return host2.pressure();
                case "policy":
                  return { capabilities: [...host2.policy.capabilities], denied: [...host2.policy.deniedRequests], limits: host2.policy.limits, mayHostChildren: host2.policy.mayHostChildren };
                case "spawnChild": {
                  const child = await host2.spawnChild({ manifest: MiniAppManifests.fromJson((_a2 = args[0]) != null ? _a2 : {}), source: String((_b2 = args[1]) != null ? _b2 : ""), grant: args[2] ? grantOf(args[2]) : null });
                  return { machineId: child.machineId };
                }
                case "pause":
                  return host2.governor.pause();
                case "resume":
                  return host2.governor.resumeExecution();
                case "terminate":
                  return host2.governor.terminate();
              }
              throw new Error(`superapp session has no method ${method}`);
            }
          };
          break;
        }
        case "stream": {
          const session = new StreamSession(surfaceId, {
            initialStylesheet: isMap(options.initialStylesheet) ? options.initialStylesheet : null,
            defaultAnimationDurationMs: typeof options.defaultAnimationDurationMs === "number" ? options.defaultAnimationDurationMs : void 0,
            defaultAnimationCurve: typeof options.defaultAnimationCurve === "string" ? options.defaultAnimationCurve : void 0,
            onCommand: (c) => emit("command", c),
            onStreamDone: () => emit("streamDone"),
            onError: (m) => emit("error", m),
            surface: surfaceOpts
          });
          if (isMap(options.request)) session.connect(options.request);
          entry = {
            kind,
            surface: session.surface,
            dispose: () => session.dispose(),
            viewportChanged: () => session.surface.viewportChanged(),
            call: (method, args) => {
              switch (method) {
                case "push":
                  session.push(args[0]);
                  return null;
                case "error":
                  session.error(args[0]);
                  return null;
                case "done":
                  session.done();
                  return null;
                case "connect":
                  session.connect(args[0]);
                  return null;
              }
              throw new Error(`stream session has no method ${method}`);
            }
          };
          break;
        }
        case "nextjs": {
          const auth = isMap(options.auth) ? nextjsAuthConfig({
            store: options.auth.persist === false ? new InMemoryTokenStore() : new PlatformTokenStore(String((_i = options.auth.namespace) != null ? _i : "elpian")),
            loginRoute: options.auth.loginRoute,
            refreshRoute: options.auth.refreshRoute,
            bearerScheme: options.auth.bearerScheme
          }) : null;
          const session = new NextjsSession(surfaceId, {
            route: String((_j = options.route) != null ? _j : "/"),
            serverBaseUrl: (_k = options.serverBaseUrl) != null ? _k : null,
            endpoint: (_l = options.endpoint) != null ? _l : null,
            requestMode: options.requestMode === "apiEndpoint" ? "apiEndpoint" : "routePath",
            props: isMap(options.props) ? options.props : null,
            headers: isMap(options.headers) ? options.headers : null,
            auth,
            timeoutMs: typeof options.timeoutMs === "number" ? options.timeoutMs : void 0,
            onScriptExecuted: (r) => emit("scriptExecuted", r),
            onScriptError: (e) => emit("scriptError", String(e)),
            onRouteChanged: (route) => emit("routeChanged", route),
            onSceneTap: options.handleSceneTaps === true ? (p) => emit("sceneTap", p) : void 0,
            surface: __spreadProps(__spreadValues({}, surfaceOpts), { host: __spreadProps(__spreadValues({}, surfaceOpts.host), { navigate: void 0 }) })
          });
          entry = {
            kind,
            surface: session.surface,
            dispose: () => session.dispose(),
            viewportChanged: () => session.viewportChanged(),
            call: (method, args) => {
              switch (method) {
                case "navigate":
                  session.navigate(String(args[0]), args[1] === true);
                  return null;
                case "back":
                  return session.back();
                case "refresh":
                  session.refresh();
                  return null;
                case "route":
                  return session.route;
                case "canGoBack":
                  return session.canGoBack;
              }
              throw new Error(`nextjs session has no method ${method}`);
            }
          };
          break;
        }
        case "server": {
          const client = new ElpianServerClient(
            String((_m = options.baseUrl) != null ? _m : ""),
            String((_n = options.appId) != null ? _n : ""),
            ElpianNetPolicy.fromManifest(options.netPolicy),
            options.authorization != null ? String(options.authorization) : null,
            typeof options.timeoutMs === "number" ? options.timeoutMs : 15e3
          );
          const session = new ServerComponentSession(surfaceId, {
            client,
            name: String((_o = options.name) != null ? _o : ""),
            args: isMap(options.args) ? options.args : {},
            nativeIslands: isMap(options.nativeIslands) ? options.nativeIslands : void 0,
            revalidateMs: typeof options.revalidateMs === "number" ? options.revalidateMs : null,
            surface: surfaceOpts
          });
          entry = {
            kind,
            surface: session.surface,
            dispose: () => {
              session.dispose();
              client.close();
            },
            viewportChanged: () => session.surface.viewportChanged(),
            call: (method, args) => {
              var _a2, _b2;
              switch (method) {
                case "update":
                  session.update((_a2 = args[0]) != null ? _a2 : {});
                  return null;
                case "refresh":
                  return session.fetch();
                case "callAction":
                  return client.callAction(String(args[0]), (_b2 = args[1]) != null ? _b2 : {});
                case "unresolvedIslands":
                  return session.unresolvedIslands();
              }
              throw new Error(`server session has no method ${method}`);
            }
          };
          break;
        }
        default:
          throw new Error(`unknown session kind "${kind}"`);
      }
      this.entries.set(surfaceId, entry);
    }
    async call(surfaceId, method, args) {
      const e = this.entries.get(surfaceId);
      if (!e) throw new Error(`no session on surface "${surfaceId}"`);
      return await e.call(method, args);
    }
    dispatchViewEvent(surfaceId, event) {
      var _a;
      (_a = surfaceById(surfaceId)) == null ? void 0 : _a.dispatchViewEvent(event);
    }
    viewportChanged(surfaceId) {
      var _a;
      const e = this.entries.get(surfaceId);
      if (e) e.viewportChanged();
      else (_a = surfaceById(surfaceId)) == null ? void 0 : _a.viewportChanged();
    }
    /** An image finished loading: every surface showing it relayouts. */
    imageLoaded(src, width, height) {
      for (const e of this.entries.values()) e.surface.imageLoaded(src, width, height);
    }
    /** Fonts loaded / changed: re-measure text everywhere. */
    invalidateText() {
      for (const e of this.entries.values()) {
        e.surface.invalidateText();
        e.surface.scheduleRender();
      }
    }
    async close(surfaceId) {
      const e = this.entries.get(surfaceId);
      if (!e) return;
      this.entries.delete(surfaceId);
      await e.dispose();
    }
    async closeAll() {
      for (const id2 of [...this.entries.keys()]) await this.close(id2);
    }
  };
  function runtimeOf(v) {
    return v === "quickjs" || v === "quickJs" ? "quickjs" : v === "wasm" ? "wasm" : "elpian";
  }
  function capsOf(v) {
    const out = /* @__PURE__ */ new Set();
    if (Array.isArray(v)) for (const x of v) {
      const c = capabilityFromWireName(String(x));
      if (c) out.add(c);
    }
    return out;
  }
  function grantOf(v) {
    if (v === "trusted") return MiniAppGrants.trusted;
    if (!isMap(v)) return MiniAppGrants.untrusted;
    const base = v.base === "trusted" ? MiniAppGrants.trusted : MiniAppGrants.untrusted;
    return {
      capabilities: Array.isArray(v.capabilities) ? capsOf(v.capabilities) : base.capabilities,
      limits: isMap(v.limits) ? Limits.fromJson(v.limits) : base.limits,
      mayHostChildren: typeof v.mayHostChildren === "boolean" ? v.mayHostChildren : base.mayHostChildren,
      allowedApis: Array.isArray(v.allowedApis) ? new Set(v.allowedApis.map(String)) : base.allowedApis
    };
  }

  // core/src/bridge/core-api.ts
  function installNativeCore(host2) {
    const hostVersion = host2.bridgeVersion();
    if (hostVersion !== ELPIAN_BRIDGE_VERSION) {
      host2.log("warn", `Elpian bridge version mismatch: core ${ELPIAN_BRIDGE_VERSION}, host ${hostVersion}`);
    }
    setPlatform(nativeHostPlatform(host2));
    const registry = new SessionRegistry((surface, event, payload) => {
      let json;
      try {
        json = JSON.stringify(payload != null ? payload : null);
      } catch (e) {
        json = JSON.stringify(String(payload));
      }
      host2.emit(surface, event, json);
    });
    const report = (surface, requestId, p) => {
      p.then(
        (value) => host2.emit(surface, "result", safeJson({ requestId, ok: true, value: value != null ? value : null })),
        (e) => host2.emit(surface, "result", safeJson({ requestId, ok: false, error: e instanceof Error ? e.message : String(e) }))
      );
    };
    const core = {
      version: ELPIAN_BRIDGE_VERSION,
      open(kind, surfaceId, optionsJson) {
        let options = {};
        try {
          options = JSON.parse(optionsJson || "{}");
        } catch (e) {
          host2.emit(surfaceId, "error", JSON.stringify(`invalid options: ${e}`));
          return;
        }
        registry.open(kind, surfaceId, options).catch((e) => host2.emit(surfaceId, "error", JSON.stringify(e instanceof Error ? e.message : String(e))));
      },
      call(surfaceId, method, argsJson, requestId) {
        let args = [];
        try {
          const parsed = JSON.parse(argsJson || "[]");
          args = Array.isArray(parsed) ? parsed : [parsed];
        } catch (e) {
          args = [];
        }
        report(surfaceId, requestId, registry.call(surfaceId, method, args));
      },
      close(surfaceId) {
        void registry.close(surfaceId);
      },
      dispatchViewEvent(surfaceId, eventJson) {
        try {
          registry.dispatchViewEvent(surfaceId, JSON.parse(eventJson));
        } catch (e) {
          platform().log("warn", `Elpian: bad view event: ${e}`);
        }
      },
      viewportChanged: (surfaceId) => registry.viewportChanged(surfaceId),
      invalidateText: () => registry.invalidateText(),
      fireTimer(handle) {
        const cb = pending.timers.get(handle);
        if (!cb) return;
        pending.timers.delete(handle);
        guard(cb);
      },
      frame(timeMs) {
        const frames = pending.frames.splice(0);
        for (const f of frames) guard(() => f(timeMs));
      },
      fetchResult(id2, ok, json) {
        var _a, _b, _c;
        const p = pending.fetches.get(id2);
        if (!p) return;
        pending.fetches.delete(id2);
        if (!ok) {
          p.reject(new Error(json || "request failed"));
          return;
        }
        try {
          const r = JSON.parse(json);
          p.resolve({ status: Number((_a = r.status) != null ? _a : 0), headers: (_b = r.headers) != null ? _b : {}, body: String((_c = r.body) != null ? _c : "") });
        } catch (e) {
          p.reject(new Error(`malformed response: ${e}`));
        }
      },
      fetchChunk(id2, text2) {
        var _a;
        (_a = pending.streams.get(id2)) == null ? void 0 : _a.onChunk(text2);
      },
      fetchDone(id2) {
        const h = pending.streams.get(id2);
        pending.streams.delete(id2);
        h == null ? void 0 : h.onDone();
      },
      fetchError(id2, message) {
        const h = pending.streams.get(id2);
        pending.streams.delete(id2);
        h == null ? void 0 : h.onError(message);
      },
      assetResult(id2, ok, data) {
        const p = pending.assets.get(id2);
        if (!p) return;
        pending.assets.delete(id2);
        if (ok) p.resolve(data);
        else p.reject(new Error(data || "asset not found"));
      },
      imageLoaded(src, width, height) {
        for (const l of pending.imageListeners) l(src, width, height);
        registry.imageLoaded(src, width, height);
      },
      godotReply(id2, json) {
        const r = pending.godotReplies.get(id2);
        pending.godotReplies.delete(id2);
        r == null ? void 0 : r(json);
      },
      godotStats(id2, json) {
        const r = pending.godotStats.get(id2);
        pending.godotStats.delete(id2);
        r == null ? void 0 : r(json);
      },
      godotSignal(callbackId, argsJson) {
        guard(() => {
          var _a, _b;
          return (_b = (_a = pending).godotSignal) == null ? void 0 : _b.call(_a, callbackId, argsJson);
        });
      },
      sandboxHostCall(handle, apiName, payload) {
        const h = pending.sandboxes.get(handle);
        if (!h) return '{"type":"null","data":{"value":null}}';
        try {
          return h(apiName, payload);
        } catch (e) {
          platform().log("warn", `Elpian sandbox host call ${apiName} failed: ${e}`);
          return '{"type":"null","data":{"value":null}}';
        }
      },
      wasmImport(handle, module, name, argsJson) {
        const h = pending.wasmImports.get(handle);
        if (!h) return "[0]";
        try {
          const args = JSON.parse(argsJson || "[]");
          return JSON.stringify(h(module, name, Array.isArray(args) ? args.map(Number) : []));
        } catch (e) {
          platform().log("warn", `Elpian wasm import ${module}.${name} failed: ${e}`);
          return "[0]";
        }
      }
    };
    return core;
  }
  function guard(fn) {
    var _a;
    try {
      fn();
    } catch (e) {
      try {
        platform().log("error", `Elpian: ${e instanceof Error ? `${e.message}
${(_a = e.stack) != null ? _a : ""}` : String(e)}`);
      } catch (e2) {
      }
    }
  }
  function safeJson(v) {
    var _a;
    try {
      return JSON.stringify(v);
    } catch (e) {
      return JSON.stringify({ requestId: (_a = v == null ? void 0 : v.requestId) != null ? _a : 0, ok: false, error: "unserialisable result" });
    }
  }

  // core/src/native-entry.ts
  var host = globalThis.__elpianHost;
  if (!host) throw new Error("Elpian core: __elpianHost is not defined");
  globalThis.__elpianCore = installNativeCore(host);
})();
