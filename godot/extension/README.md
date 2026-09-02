# Elpian Scene3D GDExtension

This directory owns the native Godot half of Elpian's `Scene3D` widget. It is
deliberately small: Godot receives scene operations from Flutter and executes
them through `ElpianScene3D` and the reflective `GodotController`.

The extension does **not** embed another Elpian VM or a Flutter engine. The app
already owns the VM, and both Android and web provide their own transport. This
keeps the extension independent of the Rust C ABI and avoids linking unrelated
runtime code into Godot's WebAssembly side module.

## Build

Use the Godot 4.3 bindings selected by the artifact workflow:

```sh
git clone --depth 1 -b godot-4.3-stable \
  https://github.com/godotengine/godot-cpp godot-cpp
scons platform=linux target=template_release
```

For the web export, match the non-threaded Godot template:

```sh
scons platform=web target=template_release threads=no
```

Artifacts are written to `../godot-project/bin/`. The global constants table is
generated from godot-cpp's `extension_api.json`. `build_profile.json` limits
godot-cpp generation and compilation to the engine classes used by the
interpreter and their dependencies. Generated files and the godot-cpp checkout
are not committed.

The initial interpreter implementation was consolidated here from the
Cosmopole `victor` repository at commit
`0a1dda221fe6f6889b08cb4fbe9213ee1753fbc3`. This directory is now the canonical
source for Elpian's Godot extension.
