/// The third-person shooter running on the **Rust/Bevy** software renderer.
///
/// This page hosts the exact same QuickJS program as the Impeller TPS, but with
/// the one-line `SCENE_WIDGET` flipped to `BevyScene` (see [tpsGameProgramBevy]).
/// The Bevy path renders the 3D layer with the Rust software rasterizer (native
/// FFI / WASM), falling back to the pure-Dart `DartSceneRenderer` when the native
/// library is unavailable — so it still runs on web / GitHub Pages.
///
/// Gameplay, HUD, controls, AI, the baked city and the streamed glTF models are
/// identical to the Impeller build; this is the migration-target showcase and
/// the B side of the A/B comparison.
library;

import 'package:flutter/material.dart';
import 'package:elpian_ui/elpian_ui.dart';

import 'tps_game_example.dart' show GameLoading, TpsBackChip;
import 'tps_game_program.dart';

/// Full-screen page that runs the QuickJS TPS on the Bevy/Rust `BevyScene`
/// 3D renderer.
class TpsGameBevyPage extends StatelessWidget {
  const TpsGameBevyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070D),
      body: Stack(
        children: [
          ElpianVmWidget.fromCode(
            machineId: 'elpian-tps-shooter-bevy',
            runtime: ElpianRuntime.quickJs,
            code: tpsGameProgramBevy,
            loadingWidget: const GameLoading(),
            onPrintln: (msg) {
              debugPrint('[tps-bevy] $msg');
            },
          ),
          const TpsBackChip(),
        ],
      ),
    );
  }
}
