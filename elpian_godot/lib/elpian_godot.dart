/// The embedded Godot 4 engine for Elpian's `Scene3D` widget.
///
/// This package carries only the **native** side — the Android/iOS platform view
/// and the op transport. The Dart API you actually use (`Scene3D`,
/// `GodotSceneController`, the op protocol) lives in `elpian_ui`; add this
/// package to an app that needs real 3D, and `Scene3D` stops showing its
/// placeholder.
///
/// See README.md for the build steps — the Godot library AAR and the packed
/// op-sink project are not checked in.
library elpian_godot;
