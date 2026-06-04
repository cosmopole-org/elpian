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
/// The Bevy/Rust variant lives in `tps_game_bevy_example.dart`; both are reached
/// from the A/B launcher in `main.dart`.
library;

import 'package:flutter/material.dart';
import 'package:elpian_ui/elpian_ui.dart';

import 'tps_game_program.dart';

/// Full-screen, mobile-optimized page that runs the QuickJS third-person
/// shooter on the Flutter-Impeller `GameScene` 3D renderer.
class TpsGamePage extends StatelessWidget {
  const TpsGamePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070D),
      body: Stack(
        children: [
          ElpianVmWidget.fromCode(
            machineId: 'elpian-tps-shooter',
            runtime: ElpianRuntime.quickJs,
            code: tpsGameProgram,
            loadingWidget: const GameLoading(),
            onPrintln: (msg) {
              // Useful for debugging the JS game loop during development.
              debugPrint('[tps] $msg');
            },
          ),
          const TpsBackChip(),
        ],
      ),
    );
  }
}

/// A small, unobtrusive "back to menu" chip shown in the top-left safe area of
/// a game page so the player can return to the A/B launcher. Hidden when the
/// route can't be popped (e.g. when a game page is itself the home route).
class TpsBackChip extends StatelessWidget {
  const TpsBackChip({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Navigator.of(context).canPop()) return const SizedBox.shrink();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: const Color(0xCC0A1018),
            shape: const StadiumBorder(
              side: BorderSide(color: Color(0x668FA3BF)),
            ),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => Navigator.of(context).maybePop(),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.chevron_left, size: 18, color: Color(0xFF8FA3BF)),
                    Text('Menu',
                        style: TextStyle(
                            color: Color(0xFF8FA3BF),
                            fontSize: 13,
                            letterSpacing: 1.0)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Loading splash shown while the QuickJS combat systems boot. Shared by both
/// the Impeller and Bevy TPS pages.
class GameLoading extends StatelessWidget {
  const GameLoading({super.key});

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
