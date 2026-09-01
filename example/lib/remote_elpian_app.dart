import 'dart:convert';
import 'dart:typed_data';

import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Loads the application manifest emitted by `elpian dev` from the same origin.
/// If no manifest exists, [fallback] keeps the normal examples export usable.
class RemoteElpianApp extends StatefulWidget {
  final Widget? fallback;
  const RemoteElpianApp({super.key, this.fallback});

  @override
  State<RemoteElpianApp> createState() => _RemoteElpianAppState();
}

class _RemoteElpianAppState extends State<RemoteElpianApp> {
  late final Future<_RemoteLoad> _program = _load();

  Future<_RemoteLoad> _load() async {
    try {
      final manifestUri = Uri.base.resolve(
          '/__elpian/elpian.manifest.json?v=${DateTime.now().millisecondsSinceEpoch}');
      final response = await http.get(manifestUri);
      if (response.statusCode != 200) {
        return _RemoteLoad.error(
            'Application manifest returned HTTP ${response.statusCode}.');
      }
      final manifest = jsonDecode(response.body) as Map<String, dynamic>;
      final client = manifest['client'] as Map<String, dynamic>?;
      if (client == null) {
        return const _RemoteLoad.error(
            'The Elpian manifest does not contain a client target.');
      }
      final artifact =
          await http.get(Uri.base.resolve(client['url'] as String));
      if (artifact.statusCode != 200) {
        throw Exception('artifact HTTP ${artifact.statusCode}');
      }
      return _RemoteLoad.program(
          _RemoteProgram(client['format'] as String, artifact.bodyBytes));
    } catch (error) {
      return _RemoteLoad.error('Unable to load the Elpian application: $error');
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_RemoteLoad>(
        future: _program,
        builder: (context, snapshot) {
          final load = snapshot.data;
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          if (load == null || load.program == null) {
            if (widget.fallback != null) return widget.fallback!;
            return _RemoteLoadError(load?.error ?? 'Unknown loading error');
          }
          final program = load.program!;
          if (program.format == 'bytecode') {
            return ElpianVmWidget.fromBytecode(
              machineId: 'elpian-dev-client',
              bytecode: Uint8List.fromList(program.bytes),
            );
          }
          return ElpianVmWidget.fromAst(
            machineId: 'elpian-dev-client',
            astJson: utf8.decode(program.bytes),
          );
        },
      );
}

class _RemoteProgram {
  final String format;
  final Uint8List bytes;
  const _RemoteProgram(this.format, this.bytes);
}

class _RemoteLoad {
  final _RemoteProgram? program;
  final String? error;
  const _RemoteLoad.program(this.program) : error = null;
  const _RemoteLoad.error(this.error) : program = null;
}

class _RemoteLoadError extends StatelessWidget {
  final String message;
  const _RemoteLoadError(this.message);

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF10141D),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: SelectableText(
              'Elpian application failed to load.\n\n$message',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ),
      );
}
