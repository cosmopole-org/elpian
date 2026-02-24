import 'dart:convert';

import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

void main() {
  runApp(const ElpianUnifiedApp());
}

/// Minimal Flutter shell – the entire UI (tabs, containers, demos) is
/// rendered by a single QuickJS program via [ElpianVmScope].
class ElpianUnifiedApp extends StatelessWidget {
  const ElpianUnifiedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Elpian Unified Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const _UnifiedShell(),
    );
  }
}

class _UnifiedShell extends StatefulWidget {
  const _UnifiedShell();

  @override
  State<_UnifiedShell> createState() => _UnifiedShellState();
}

class _UnifiedShellState extends State<_UnifiedShell> {
  final _controller = ElpianVmController();
  String? _program;
  String? _programError;

  @override
  void initState() {
    super.initState();
    _loadProgram();
  }

  Future<void> _loadProgram() async {
    try {
      final code = await rootBundle.loadString('assets/unified_program.js');
      if (!mounted) return;
      setState(() {
        _program = code;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _programError = 'Failed to load assets/unified_program.js: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_programError != null) {
      return Scaffold(
        body: Center(
          child: Text(
            _programError!,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    if (_program == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      body: ElpianVmScope(
        controller: _controller,
        machineId: 'elpian-unified-demo',
        runtime: ElpianRuntime.quickJs,
        code: _program,
        onUpdateApp: (data) {
          debugPrint('updateApp: ${jsonEncode(data)}');
        },
        onPrintln: (msg) {
          debugPrint('println: $msg');
        },
        hostHandlers: {
          'getProfile': (apiName, payload) {
            return jsonEncode({
              'type': 'string',
              'data': {
                'value': jsonEncode({
                  'name': 'Elpian User',
                  'role': 'Runtime Tester',
                  'project': 'QuickJS Unified Demo',
                }),
              },
            });
          },
        },
      ),
    );
  }
}
