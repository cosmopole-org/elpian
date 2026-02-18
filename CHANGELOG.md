# Changelog

## [2.0.0] - 2025

### Changed
- Renamed project from `stac_flutter_ui` to `elpian_ui`
- Renamed all `Stac`-prefixed classes to `Elpian` (ElpianEngine, ElpianNode, etc.)
- Moved project from `stac_flutter_ui/` subdirectory to repository root
- Updated GitHub Actions workflow for root-level project structure

### Added
- Elpian VM - Sandboxed Rust VM with FFI (native) and WASM (web) support
- 3D scene graph rendering via Bevy (Rust/GPU) and pure-Dart canvas renderer
- 2D Canvas API with 50+ drawing commands
- VM-driven UI rendering with `ElpianVmWidget`
- Bevy 3D scene widget with JSON scene definitions
- Pure-Dart 3D game engine with software rendering
- 20+ animation widgets (AnimatedScale, AnimatedRotation, Shimmer, Pulse, etc.)

## [1.0.0] - 2024

### Added
- Initial release
- 60+ Flutter widget builders with CSS property support
- 70+ HTML5 element implementations
- 150+ CSS properties (flexbox, grid, transforms, animations, filters)
- JSON DSL rendering engine (ElpianEngine)
- DOM API (ElpianDOM) with query selectors and element manipulation
- CSS stylesheet parser with media queries
- JSON stylesheet system with variables, keyframes, and builder pattern
- Event system with 40+ event types, bubbling, capturing, and delegation
- Widget registry system for custom widget registration
- Example applications and test suite
