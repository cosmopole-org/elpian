/// Third-person shooter game implemented entirely in a single QuickJS script
/// that runs on the Elpian runtime.
///
/// The Dart side is intentionally tiny: it only hosts a full-screen
/// [ElpianVmWidget] running the QuickJS program in [tpsGameProgram]. All game
/// logic, state management, the 3D scene graphics DSL, the HUD, and the
/// touch controls (movement joystick, look pad, fire / reload / jump buttons)
/// live in JavaScript and drive the renderer through `askHost('render', ...)`.
///
/// The 3D world is rendered by Elpian's pure-Dart `GameScene` widget (no native
/// library or WASM required), so it works on web / GitHub Pages out of the box.
library;

import 'package:flutter/material.dart';
import 'package:elpian_ui/elpian_ui.dart';

import 'tps_game_program.dart';

/// Full-screen, mobile-optimized page that runs the QuickJS third-person
/// shooter. This is wired as the home route of the example app.
class TpsGamePage extends StatelessWidget {
  const TpsGamePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070D),
      body: ElpianVmWidget.fromCode(
        machineId: 'elpian-tps-shooter',
        runtime: ElpianRuntime.quickJs,
        code: tpsGameProgram,
        loadingWidget: const _GameLoading(),
        onPrintln: (msg) {
          // Useful for debugging the JS game loop during development.
          debugPrint('[tps] $msg');
        },
      ),
    );
  }
}

class _GameLoading extends StatelessWidget {
  const _GameLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF05070D),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(
            width: 46,
            height: 46,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4CC9F0)),
            ),
          ),
          SizedBox(height: 18),
          Text(
            'Booting combat systems…',
            style: TextStyle(
              color: Color(0xFF8FA3BF),
              fontSize: 14,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
