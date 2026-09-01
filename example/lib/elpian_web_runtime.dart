import 'package:flutter/material.dart';

import 'remote_elpian_app.dart';

void main() => runApp(const ElpianWebRuntime());

/// Dedicated deployment shell used by `elpian run build/dev`.
/// It has no examples fallback: its only job is to load the same-origin
/// Elpian manifest and execute the client program in the WASM VM.
class ElpianWebRuntime extends StatelessWidget {
  const ElpianWebRuntime({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Elpian App',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true),
        home: const RemoteElpianApp(),
      );
}
