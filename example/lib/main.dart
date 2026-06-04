import 'package:flutter/material.dart';

import 'examples/tps_game_example.dart';
import 'examples/tps_game_bevy_example.dart';

void main() {
  runApp(const ElpianGameApp());
}

/// Entry point for the Elpian example deployment.
///
/// The main route opens an A/B launcher for the third-person shooter — a
/// complete game implemented entirely in a single QuickJS script running on the
/// Elpian runtime (see `examples/tps_game_program.dart`). The same game can be
/// rendered by either the Flutter-Impeller `GameScene` renderer or the Rust/Bevy
/// `BevyScene` renderer, so the two backends can be compared side by side.
class ElpianGameApp extends StatelessWidget {
  const ElpianGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Elpian Strike Force',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4CC9F0),
          brightness: Brightness.dark,
        ),
      ),
      home: const TpsLauncherPage(),
    );
  }
}

/// Landing screen letting the player launch the TPS on either 3D backend.
class TpsLauncherPage extends StatelessWidget {
  const TpsLauncherPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070D),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'ELPIAN STRIKE FORCE',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFE6F0FF),
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Downtown · choose a 3D renderer',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF8FA3BF), fontSize: 14),
                ),
                const SizedBox(height: 32),
                _LaunchButton(
                  label: 'Play — Bevy (Rust)',
                  subtitle: 'Software rasterizer · migration target',
                  primary: true,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TpsGameBevyPage()),
                  ),
                ),
                const SizedBox(height: 16),
                _LaunchButton(
                  label: 'Play — Impeller (Dart)',
                  subtitle: 'Original GameScene · A/B baseline',
                  primary: false,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TpsGamePage()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LaunchButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool primary;
  final VoidCallback onTap;

  const _LaunchButton({
    required this.label,
    required this.subtitle,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFF4CC9F0);
    return Material(
      color: primary ? accent.withValues(alpha: 0.16) : const Color(0xFF0C121C),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: primary ? accent.withValues(alpha: 0.7) : const Color(0x33FFFFFF),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: primary ? const Color(0xFFE6F0FF) : const Color(0xFFC8D4E4),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF7E90A8), fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
