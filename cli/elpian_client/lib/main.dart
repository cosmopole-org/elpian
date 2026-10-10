import 'dart:convert';
import 'dart:typed_data';

import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const ElpianClientApp());

/// Standalone web shell for dynamically served Elpian applications.
///
/// This project deliberately imports no example application. It fetches the
/// same-origin CLI manifest, downloads its client AST/bytecode, and creates the
/// Elpian WASM VM that renders the guest UI.
class ElpianClientApp extends StatelessWidget {
  const ElpianClientApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Elpian',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
        // The VM renders an arbitrary widget tree, not a Scaffold of its own.
        // Establish a transparent Material boundary so its Text widgets inherit
        // the theme's body style instead of MaterialApp's intentionally loud
        // fallback (yellow double underlines for content with no Material
        // ancestor). Transparency lets the guest keep control of its canvas.
        home: const Material(
          type: MaterialType.transparency,
          child: DynamicElpianClient(),
        ),
      );
}

class DynamicElpianClient extends StatefulWidget {
  const DynamicElpianClient({super.key});

  @override
  State<DynamicElpianClient> createState() => _DynamicElpianClientState();
}

class _DynamicElpianClientState extends State<DynamicElpianClient> {
  late Future<_ClientProgram> _program = _fetchProgram();

  Future<_ClientProgram> _fetchProgram() async {
    final nonce = DateTime.now().microsecondsSinceEpoch;
    final manifestUri =
        Uri.base.resolve('__elpian/elpian.manifest.json?v=$nonce');
    final manifestResponse = await http.get(manifestUri, headers: const {
      'cache-control': 'no-cache',
    });
    if (manifestResponse.statusCode != 200) {
      throw Exception(
          'GET $manifestUri returned HTTP ${manifestResponse.statusCode}');
    }
    final manifest = jsonDecode(manifestResponse.body);
    if (manifest is! Map<String, dynamic>) {
      throw const FormatException('Elpian manifest must be a JSON object');
    }
    final client = manifest['client'];
    if (client is! Map<String, dynamic>) {
      throw const FormatException('Elpian manifest has no client target');
    }
    final format = client['format'];
    final url = client['url'];
    if ((format != 'bytecode' && format != 'ast') || url is! String) {
      throw const FormatException('Invalid Elpian client artifact declaration');
    }
    final artifactUri = Uri.base.resolve('$url?v=$nonce');
    final artifactResponse = await http.get(artifactUri, headers: const {
      'cache-control': 'no-cache',
    });
    if (artifactResponse.statusCode != 200) {
      throw Exception(
          'GET $artifactUri returned HTTP ${artifactResponse.statusCode}');
    }
    if (artifactResponse.bodyBytes.isEmpty) {
      throw const FormatException('Elpian client artifact is empty');
    }
    final agents = agentEndpointDefaults(manifest, Uri.base);
    return _ClientProgram(format as String, artifactResponse.bodyBytes,
        appId: agents.appId, baseUrl: agents.baseUrl);
  }

  void _retry() => setState(() => _program = _fetchProgram());

  @override
  Widget build(BuildContext context) => FutureBuilder<_ClientProgram>(
        future: _program,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return _LoadFailure(
                message: snapshot.error.toString(), retry: _retry);
          }
          final program = snapshot.requireData;
          if (program.format == 'bytecode') {
            return ElpianVmWidget.fromBytecode(
              machineId: 'elpian-dynamic-client',
              bytecode: Uint8List.fromList(program.bytes),
              agentAppId: program.appId,
              agentBaseUrl: program.baseUrl,
              errorBuilder: (error) =>
                  _LoadFailure(message: error, retry: _retry),
            );
          }
          return ElpianVmWidget.fromAst(
            machineId: 'elpian-dynamic-client',
            astJson: utf8.decode(program.bytes),
            agentAppId: program.appId,
            agentBaseUrl: program.baseUrl,
            errorBuilder: (error) =>
                _LoadFailure(message: error, retry: _retry),
          );
        },
      );
}

class _ClientProgram {
  final String format;
  final Uint8List bytes;
  final String? appId;
  final String baseUrl;
  const _ClientProgram(this.format, this.bytes,
      {required this.appId, required this.baseUrl});
}

/// Where the served mini app's agents live: the manifest's `app` id, and the
/// directory the shell was served from as the base URL — so `A2UISurface`
/// widgets and `agent.*` calls post to `<base>/apps/<app>/agent/<agent>` on the
/// same dev server (`elpian run dev`). A manifest without `app` leaves agents
/// unconfigured (static A2UI still renders).
({String? appId, String baseUrl}) agentEndpointDefaults(
    Map<String, dynamic> manifest, Uri base) {
  final app = manifest['app'];
  return (
    appId: app is String && app.isNotEmpty ? app : null,
    baseUrl: base.resolve('.').toString(),
  );
}

class _LoadFailure extends StatelessWidget {
  final String message;
  final VoidCallback retry;
  const _LoadFailure({required this.message, required this.retry});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF10141D),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline,
                      size: 48, color: Colors.orange),
                  const SizedBox(height: 20),
                  const Text('Elpian client could not start',
                      style:
                          TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  SelectableText(message, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: retry, child: const Text('Retry')),
                ],
              ),
            ),
          ),
        ),
      );
}
