/// Non-web stand-in for `godot_binding_web.dart`.
///
/// Selected by the conditional import in `godot_binding.dart` on every target
/// that lacks `dart:js_interop`, so a native build never compiles the web
/// transport (and never pulls `dart:js_interop` into a VM/AOT compile).
library;

import 'godot_binding.dart';

/// No web transport off the web. [resolveGodotBinding] falls back to the mock.
GodotBinding? createWebGodotBinding() => null;
