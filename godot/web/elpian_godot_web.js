// Page glue for the Godot HTML5 export — the web half of the embedded-Godot
// seam, mirroring what ElpianGodotPlugin/OpQueue do on Android.
//
// Three parties meet on `window`:
//
//   Dart  (godot_binding_web.dart)  pushes JSON messages onto __elpianGodotQueue
//                                   and polls __elpianGodotReplies.pending
//   Godot (OpSink.gd)               calls __elpianGodotDrain() each frame and
//                                   __elpianGodotReply(entry) for awaited batches
//   Flutter (godot_web_surface_web) calls __elpianGodotSurface(id) for the
//                                   element to embed as a platform view
//
// Load order matters: the drain hook must exist *before* the engine boots,
// because OpSink.gd decides once, in _ready, whether it is running on the web
// transport. Installing the hooks is therefore the first thing this file does,
// synchronously at parse time, and the engine is only started later from
// __elpianGodotSurface.
//
// Presence of __elpianGodotDrain is also what Dart's WebGodotBinding.isLive
// reports, and hence what makes Scene3D swap its placeholder for a real
// viewport. So this script must not install the hook unless it can actually
// boot an engine.
(function () {
  'use strict';

  if (window.__elpianGodotDrain) return; // already installed

  var queue = window.__elpianGodotQueue || (window.__elpianGodotQueue = []);
  var replies = window.__elpianGodotReplies || (window.__elpianGodotReplies = { pending: null });

  // ---- Dart -> Godot ------------------------------------------------------
  // Dart pushes one JSON *object* per message; OpSink parses one JSON *array*
  // per drain, so the batch is assembled here rather than crossing the bridge
  // one message at a time.
  window.__elpianGodotDrain = function () {
    if (!queue.length) return '';
    var batch = '[' + queue.join(',') + ']';
    queue.length = 0;
    return batch;
  };

  // ---- Godot -> Dart ------------------------------------------------------
  // Entries accumulate until Dart's poll picks them up; it clears `pending` by
  // writing null, so appending to whatever is already there preserves any reply
  // that landed between two polls.
  window.__elpianGodotReply = function (entry) {
    var list = [];
    if (replies.pending) {
      try { list = JSON.parse(replies.pending) || []; } catch (e) { list = []; }
    }
    list.push(entry);
    replies.pending = JSON.stringify(list);
  };

  // ---- the surface --------------------------------------------------------
  var surfaces = {};
  var booted = false;   // the engine has actually been handed a canvas
  var claimed = false;  // a surface has taken the engine (set synchronously)

  function resolve(path) {
    return new URL(path, document.baseURI).href;
  }

  function loadScript(src) {
    return new Promise(function (ok, fail) {
      var el = document.createElement('script');
      el.src = src;
      el.onload = ok;
      el.onerror = function () { fail(new Error('failed to load ' + src)); };
      document.head.appendChild(el);
    });
  }

  // The export is deployed *beside* the page, not in a subdirectory, because
  // that is the only layout Godot's own loader supports.
  //
  // engine.js resolves every file through a `locateFile` that rewrites only
  // paths beginning with `godot.` and returns everything else untouched, so a
  // name from the exported config is resolved against the document. This file
  // used to keep the export in `godot/` and rebase those names onto it, which
  // fetched correctly but broke the GDExtension: `gdextensionLibs` entries go
  // into Emscripten's `dynamicLibraries` verbatim and are registered under
  // exactly that string, while Godot's OS_Web::open_dynamic_library dlopen()s
  // the *basename* of `res://bin/libelpian_godot.web.wasm32.wasm`. A rebased
  // absolute URL therefore never matched:
  //
  //   Can't open dynamic library: bin/libelpian_godot.web.wasm32.wasm
  //   ElpianScene3D (elpian_godot GDExtension) not loaded
  //
  // and Scene3D showed a live but empty canvas. Leaving the names bare while
  // the export sat in `godot/` was no better — the fetch then 404s against the
  // document root, and a failed asyncLoad never clears its run dependency, so
  // the engine hangs forever on `loadDylibs` instead of failing:
  //
  //   still waiting on run dependencies: dependency: al libelpian_...wasm
  //
  // Putting the export beside the page satisfies both: the bare names resolve,
  // and they keep the basename identity dlopen needs. Nothing to rebase.
  var ENGINE_DIR = '';

  // The engine is booted from the exported config rather than a hand-written
  // one: `gdextensionLibs`, `fileSizes` and the executable/pack names are all
  // decided by the export and change with the Godot version. The CI job writes
  // them out beside the export as godot_config.json.
  // Emscripten's GL layer resolves the canvas with
  // `document.querySelector('#' + canvas.id)`, so the canvas needs a non-empty
  // id *and* has to be in the document by the time the engine starts. Flutter
  // only inserts the platform-view element after the view factory returns, so
  // booting immediately raced that and died with
  //   Failed to execute 'querySelector' on 'Document': '#' is not a valid selector
  // — the id was empty, and the element was not attached yet either.
  function whenConnected(el, done) {
    var waited = 0;
    (function check() {
      if (el.isConnected) return done();
      waited += 32;
      if (waited > 10000) {
        console.error('[elpian-godot] surface never entered the document; not starting');
        delete window.__elpianGodotDrain;
        return;
      }
      setTimeout(check, 32);
    })();
  }

  // Keep the framebuffer in step with the slot Flutter sized. Godot's web
  // display server picks the new size up on its own once the canvas changes.
  function trackSize(canvas, host) {
    var apply = function () {
      var r = host.getBoundingClientRect();
      var dpr = window.devicePixelRatio || 1;
      var w = Math.max(1, Math.round(r.width * dpr));
      var h = Math.max(1, Math.round(r.height * dpr));
      if (canvas.width !== w) canvas.width = w;
      if (canvas.height !== h) canvas.height = h;
      // Godot writes inline px dimensions on some paths; keep the element
      // itself filling the slot regardless.
      canvas.style.width = '100%';
      canvas.style.height = '100%';
    };
    apply();
    if (typeof ResizeObserver === 'function') {
      new ResizeObserver(apply).observe(host);
    } else {
      window.addEventListener('resize', apply);
    }
    // The engine sets its own dimensions while starting up, so re-assert once
    // the first frames have gone through.
    setTimeout(apply, 100);
    setTimeout(apply, 1000);
  }

  function boot(canvas, host) {
    if (booted) return;
    booted = true;
    Promise.all([
      loadScript(resolve(ENGINE_DIR + 'elpian_godot.js')),
      fetch(resolve(ENGINE_DIR + 'godot_config.json')).then(function (r) { return r.json(); }),
    ]).then(function (results) {
      var config = results[1] || {};
      config.canvas = canvas;
      // 0 = leave the canvas alone. Neither policy Godot offers fits a platform
      // view: 1 pins the canvas to the *project* resolution (which is what
      // silently overwrote our `width:100%` with `1152px`, leaving the stage
      // part-covered), and 2 sizes it to the whole window, which is not the slot
      // Flutter gave us. The element's size is Flutter's decision, so we own the
      // framebuffer and track the slot ourselves.
      config.canvasResizePolicy = 0;
      // Godot would otherwise steal focus from the Flutter view on boot.
      config.focusCanvas = false;
      var engine = new window.Engine(config);
      return engine.startGame().then(function () { trackSize(canvas, host); });
    }).catch(function (e) {
      console.error('[elpian-godot] engine failed to start:', e);
      // Stop claiming to be live so Scene3D falls back to its placeholder
      // instead of showing a dead canvas.
      delete window.__elpianGodotDrain;
    });
  }

  window.__elpianGodotSurface = function (surfaceId) {
    var id = String(surfaceId);
    if (surfaces[id]) return surfaces[id];

    var host = document.createElement('div');
    host.style.width = '100%';
    host.style.height = '100%';
    host.style.overflow = 'hidden';

    // A Godot web export drives exactly one canvas per page, so only the first
    // surface gets the engine. A second Scene3D on the same page is a real
    // limitation of the platform, not a bug to paper over silently.
    //
    // Claimed synchronously rather than keyed off `booted`: the boot itself now
    // waits for the canvas to enter the document, so two surfaces created in one
    // frame would otherwise both believe they were first.
    if (claimed) {
      console.warn('[elpian-godot] only one Scene3D can be live on the web; surface ' + id + ' is empty');
      surfaces[id] = host;
      return host;
    }

    var canvas = document.createElement('canvas');
    // Non-empty and unique: emscripten looks the canvas up by `#<id>`.
    canvas.id = 'elpian-godot-canvas-' + id;
    canvas.style.display = 'block';
    canvas.style.width = '100%';
    canvas.style.height = '100%';
    // Godot reads these for its initial framebuffer; canvasResizePolicy then
    // keeps them in step with the element.
    canvas.width = 1;
    canvas.height = 1;
    host.appendChild(canvas);
    surfaces[id] = host;
    claimed = true;
    whenConnected(canvas, function () { boot(canvas, host); });
    return host;
  };
})();
