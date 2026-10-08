/// Non-web stand-in for `godot_web_surface_web.dart`.
///
/// Selected by the conditional import in `scene3d_widget.dart` wherever
/// `dart:ui_web` does not exist, so a native build never references the web
/// platform-view registry.
library;

import 'package:flutter/widgets.dart';

/// No web surface off the web; the caller falls back to its placeholder.
Widget? buildGodotWebSurface(int surfaceId) => null;
