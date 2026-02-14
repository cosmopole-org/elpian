import 'package:flutter/material.dart';
import 'package:stac_flutter_ui/stac_flutter_ui.dart';

/// Example demonstrating the Elpian Rust VM integration with Flutter.
///
/// The VM runs sandboxed code that produces a JSON view tree,
/// which is rendered using the StacEngine's HTML/CSS/Flutter widgets.
class VmExampleApp extends StatelessWidget {
  const VmExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Elpian VM Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const VmExamplePage(),
    );
  }
}

class VmExamplePage extends StatefulWidget {
  const VmExamplePage({super.key});

  @override
  State<VmExamplePage> createState() => _VmExamplePageState();
}

class _VmExamplePageState extends State<VmExamplePage> {
  final _controller = ElpianVmController();

  /// Example Elpian source code that renders a UI via the VM.
  ///
  /// The VM code creates a JSON representation of the view tree
  /// and calls askHost("render", viewJson) to display it in Flutter.
  static const _exampleCode = r'''
    def title = "Hello from Elpian VM!"
    def subtitle = "This UI is rendered by sandboxed Rust VM code"

    def view = {
      "type": "Column",
      "props": {
        "style": {
          "padding": "24",
          "backgroundColor": "#ffffff"
        }
      },
      "children": [
        {
          "type": "Container",
          "props": {
            "style": {
              "padding": "16",
              "backgroundColor": "#e8eaf6",
              "borderRadius": "12"
            }
          },
          "children": [
            {
              "type": "Text",
              "props": {
                "text": title,
                "style": {
                  "fontSize": "24",
                  "fontWeight": "bold",
                  "color": "#1a237e"
                }
              }
            }
          ]
        },
        {
          "type": "SizedBox",
          "props": {
            "style": { "height": "16" }
          }
        },
        {
          "type": "Text",
          "props": {
            "text": subtitle,
            "style": {
              "fontSize": "16",
              "color": "#424242"
            }
          }
        },
        {
          "type": "SizedBox",
          "props": {
            "style": { "height": "24" }
          }
        },
        {
          "type": "Row",
          "props": {
            "style": {
              "gap": "12"
            }
          },
          "children": [
            {
              "type": "Container",
              "props": {
                "style": {
                  "padding": "12",
                  "backgroundColor": "#c8e6c9",
                  "borderRadius": "8",
                  "flex": "1"
                }
              },
              "children": [
                {
                  "type": "Text",
                  "props": {
                    "text": "Sandboxed",
                    "style": { "fontWeight": "bold", "color": "#2e7d32" }
                  }
                },
                {
                  "type": "Text",
                  "props": {
                    "text": "Code runs in a secure Rust VM",
                    "style": { "fontSize": "12", "color": "#388e3c" }
                  }
                }
              ]
            },
            {
              "type": "Container",
              "props": {
                "style": {
                  "padding": "12",
                  "backgroundColor": "#bbdefb",
                  "borderRadius": "8",
                  "flex": "1"
                }
              },
              "children": [
                {
                  "type": "Text",
                  "props": {
                    "text": "Cross-platform",
                    "style": { "fontWeight": "bold", "color": "#1565c0" }
                  }
                },
                {
                  "type": "Text",
                  "props": {
                    "text": "Mobile, Desktop & Web",
                    "style": { "fontSize": "12", "color": "#1976d2" }
                  }
                }
              ]
            }
          ]
        }
      ]
    }

    askHost("render", view)
  ''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Elpian VM Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ElpianVmScope(
        controller: _controller,
        machineId: 'example-vm',
        code: _exampleCode,
        onPrintln: (message) {
          debugPrint('VM says: $message');
        },
        loadingWidget: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading VM...'),
            ],
          ),
        ),
        errorBuilder: (error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  'VM Error',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(error, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
