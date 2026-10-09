/// Elpian's embedded Godot 4 surface: the `Scene3D` widget, its controller and
/// the op protocol they speak.
///
/// Import this on its own when you are working with 3D and do not need the 2D
/// widget set. Everything here is also exported from `elpian_ui.dart`.
///
/// The native side lives in the separate `elpian_godot` plugin package; without
/// it `Scene3D` renders a placeholder rather than failing.
library;

export 'src/godot/scene3d_widget.dart';
export 'src/godot/godot_controller.dart';
export 'src/godot/godot_object.dart';
export 'src/godot/godot_values.dart';
export 'src/godot/protocol.dart';
export 'src/godot/scene_dsl.dart';
export 'src/godot/godot_binding.dart';
export 'src/godot/scene_taps.dart';
