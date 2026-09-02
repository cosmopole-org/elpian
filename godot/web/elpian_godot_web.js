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
  var booted = false;

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

  // The engine is booted from the exported config rather than a hand-written
  // one: `gdextensionLibs`, `fileSizes` and the executable/pack names are all
  // decided by the export and change with the Godot version. The CI job writes
  // them out beside the export as godot_config.json.
  function boot(canvas) {
    if (booted) return;
    booted = true;
    Promise.all([
      loadScript(resolve('godot/elpian_godot.js')),
      fetch(resolve('godot/godot_config.json')).then(function (r) { return r.json(); }),
    ]).then(function (results) {
      var config = results[1] || {};
      config.canvas = canvas;
      // 1 = adapt the framebuffer to the canvas element's size, which is what
      // Flutter is sizing for us via the platform view slot.
      config.canvasResizePolicy = 1;
      // Godot would otherwise steal focus from the Flutter view on boot.
      config.focusCanvas = false;
      var engine = new window.Engine(config);
      return engine.startGame();
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
    if (booted) {
      console.warn('[elpian-godot] only one Scene3D can be live on the web; surface ' + id + ' is empty');
      surfaces[id] = host;
      return host;
    }

    var canvas = document.createElement('canvas');
    canvas.style.display = 'block';
    canvas.style.width = '100%';
    canvas.style.height = '100%';
    // Godot reads these for its initial framebuffer; canvasResizePolicy then
    // keeps them in step with the element.
    canvas.width = 1;
    canvas.height = 1;
    host.appendChild(canvas);
    surfaces[id] = host;
    boot(canvas);
    return host;
  };
})();
