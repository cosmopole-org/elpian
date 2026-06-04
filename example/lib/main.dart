import 'package:flutter/material.dart';

import 'examples/tps_game_example.dart';

void main() {
  runApp(const ElpianGameApp());
}

/// Entry point for the Elpian example deployment.
///
/// The GitHub Pages build targets this file, so the main route opens directly
/// into the third-person shooter — a complete game implemented entirely in a
/// single QuickJS script running on the Elpian runtime (see
/// `examples/tps_game_program.dart`).
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
      home: const TpsGamePage(),
    );
  }
}
