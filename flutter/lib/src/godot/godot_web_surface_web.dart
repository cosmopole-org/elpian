/// The web viewport: the Godot HTML5 export's canvas, embedded as a Flutter
/// platform view.
///
/// The other targets hand `Scene3D` a native platform view (`AndroidView` /
/// `UiKitView`) whose surface the embedded engine renders into. On the web the
/// engine is a WebAssembly build drawing into a DOM `<canvas>`, which
/// [HtmlElementView] embeds the same way — Flutter positions and sizes the
/// slot, so the canvas tracks the widget's layout with no overlay arithmetic.
///
/// The canvas is created and owned by the page glue in
/// `godot/web/elpian_godot_web.js`; this file only asks for the element
/// belonging to a given surface. That split is deliberate: a Godot export must
/// be handed a canvas that already exists when it boots, so the glue owns the
/// element's lifetime and Flutter merely borrows it into the widget tree.
///
/// Elements are addressed through `dart:js_interop` rather than `package:web`
/// so the package gains no dependency for one `createElement` call.
library;

import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

/// The platform view type registered for a Godot surface.
const String godotWebViewType = 'elpian-godot-surface';

bool _registered = false;

/// `window.__elpianGodotSurface(surfaceId)` — the glue's element factory. Absent
/// when no Godot export is on the page.
@JS('__elpianGodotSurface')
external JSFunction? get _surfaceFactory;

@JS('document.createElement')
external JSObject _createElement(JSString tag);

void _register() {
  if (_registered) return;
  _registered = true;
  ui_web.platformViewRegistry.registerViewFactory(
    godotWebViewType,
    (int viewId, {Object? params}) {
      final surfaceId = params is Map ? (params['surfaceId'] as int? ?? 0) : 0;
      final element = _surfaceFactory?.callAsFunction(null, surfaceId.toJS);
      // No glue on the page: an empty box, so the tree still builds. Not
      // normally reached — `Scene3D` only asks for a viewport once the binding
      // reports `isLive`, which requires the glue.
      return element ?? _createElement('div'.toJS);
    },
  );
}

/// The Godot canvas for [surfaceId], embedded as a platform view.
Widget? buildGodotWebSurface(int surfaceId) {
  _register();
  return HtmlElementView(
    viewType: godotWebViewType,
    creationParams: {'surfaceId': surfaceId},
  );
}
