# Examples

This folder contains JSON scenes and demo runners for the Elpian UI/world converter.

How to run the main UI demo (from workspace root):

```bash
cargo run --bin elpian
```

This runs the binary which loads `src/examples/ui_example.json` by default.

Other example scenes:

- `src/examples/material_and_3d.json` — demonstrates new Material components (`IconButton`, `Divider`, `List`, `Drawer`) and 3D primitives (cube, sphere, plane).
- `src/examples/advanced_ui.json` — advanced UI components demo (sliders, checkboxes, radio buttons).
- `src/examples/animations.json` — animation and particle demos.

To run a different example, edit `src/main.rs` to call the example runner you prefer (e.g., update `run_ui_demo()` to point to another JSON), or run the example modules directly when building an executable.
