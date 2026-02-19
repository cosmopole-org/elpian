/// Interactive demos that test the automatic VM ↔ UI event bridge.
///
/// Each demo uses [ElpianEngine] with string-based event handlers in the
/// JSON view tree. The engine's [EventDispatcher.vmEventCallback] is wired
/// to a handler that simulates what [ElpianVmWidget] does internally:
/// it receives the VM function name and the event, mutates state, and
/// re-renders the view. This exercises the full bridge without needing
/// the Rust VM FFI, making it deployable on Flutter web / GitHub Pages.
library;

import 'package:flutter/material.dart';
import 'package:elpian_ui/elpian_ui.dart';

// ---------------------------------------------------------------------------
// Demo page
// ---------------------------------------------------------------------------

class VmEventDemoPage extends StatefulWidget {
  const VmEventDemoPage({super.key});

  @override
  State<VmEventDemoPage> createState() => _VmEventDemoPageState();
}

class _VmEventDemoPageState extends State<VmEventDemoPage> {
  final ElpianEngine _engine = ElpianEngine();

  // -- Toggle state --
  bool _isOn = false;

  // -- Counter state --
  int _count = 0;

  // -- Form state --
  String _username = '';
  String? _greeting;

  @override
  void initState() {
    super.initState();
    // This is exactly what ElpianVmWidget does after creating the VM.
    // String event handlers in JSON nodes are routed here automatically.
    _engine.eventDispatcher.vmEventCallback = _handleVmEvent;
  }

  @override
  void dispose() {
    _engine.eventDispatcher.vmEventCallback = null;
    super.dispose();
  }

  // -----------------------------------------------------------------------
  // VM event callback — the heart of the bridge
  // -----------------------------------------------------------------------

  Future<void> _handleVmEvent(String funcName, ElpianEvent event) async {
    switch (funcName) {
      // Toggle demo
      case 'onToggle':
        setState(() => _isOn = !_isOn);
        break;

      // Counter demo
      case 'onIncrement':
        setState(() => _count++);
        break;
      case 'onDecrement':
        setState(() => _count--);
        break;
      case 'onReset':
        setState(() => _count = 0);
        break;

      // Form demo
      case 'onInput':
        if (event is ElpianInputEvent) {
          _username = event.value?.toString() ?? '';
        }
        break;
      case 'onSubmit':
        setState(() {
          _greeting = _username.isEmpty
              ? 'Please enter a name first!'
              : 'Hello, $_username!';
        });
        break;
    }
  }

  // -----------------------------------------------------------------------
  // Toggle demo view
  // -----------------------------------------------------------------------

  Map<String, dynamic> _buildToggleView() {
    final color = _isOn ? '#4CAF50' : '#EF4444';
    final label = _isOn ? 'ON' : 'OFF';
    return {
      'type': 'div',
      'style': {
        'padding': '32',
        'alignItems': 'center',
      },
      'children': [
        {
          'type': 'Text',
          'props': {'data': label},
          'style': {
            'fontSize': 56,
            'fontWeight': 'bold',
            'color': color,
          },
        },
        {
          'type': 'Button',
          'key': 'toggle-btn',
          'props': {'text': 'Toggle'},
          'style': {
            'marginTop': '24',
            'padding': '14 48',
            'backgroundColor': '#6C63FF',
            'color': '#FFFFFF',
            'borderRadius': 12,
            'fontSize': 16,
          },
          'events': {'click': 'onToggle'},
        },
      ],
    };
  }

  // -----------------------------------------------------------------------
  // Counter demo view
  // -----------------------------------------------------------------------

  Map<String, dynamic> _buildCounterView() {
    return {
      'type': 'div',
      'style': {
        'padding': '32',
        'alignItems': 'center',
      },
      'children': [
        {
          'type': 'Text',
          'props': {'data': '$_count'},
          'style': {
            'fontSize': 64,
            'fontWeight': 'bold',
            'color': '#818CF8',
          },
        },
        {
          'type': 'Text',
          'props': {'data': 'Tap the buttons to change the count'},
          'style': {
            'fontSize': 13,
            'color': '#94A3B8',
            'marginTop': '4',
          },
        },
        {
          'type': 'Row',
          'style': {
            'marginTop': '24',
            'gap': 12,
            'justifyContent': 'center',
          },
          'children': [
            {
              'type': 'Button',
              'key': 'dec-btn',
              'props': {'text': '−'},
              'style': {
                'padding': '12 28',
                'backgroundColor': '#EF4444',
                'color': '#FFFFFF',
                'borderRadius': 10,
                'fontSize': 22,
              },
              'events': {'click': 'onDecrement'},
            },
            {
              'type': 'Button',
              'key': 'reset-btn',
              'props': {'text': 'Reset'},
              'style': {
                'padding': '12 24',
                'backgroundColor': 'rgba(255,255,255,0.08)',
                'color': '#E2E8F0',
                'borderRadius': 10,
                'fontSize': 14,
              },
              'events': {'click': 'onReset'},
            },
            {
              'type': 'Button',
              'key': 'inc-btn',
              'props': {'text': '+'},
              'style': {
                'padding': '12 28',
                'backgroundColor': '#4CAF50',
                'color': '#FFFFFF',
                'borderRadius': 10,
                'fontSize': 22,
              },
              'events': {'click': 'onIncrement'},
            },
          ],
        },
      ],
    };
  }

  // -----------------------------------------------------------------------
  // Form demo view
  // -----------------------------------------------------------------------

  Map<String, dynamic> _buildFormView() {
    return {
      'type': 'div',
      'style': {
        'padding': '32',
        'alignItems': 'center',
      },
      'children': [
        if (_greeting != null) ...[
          {
            'type': 'div',
            'style': {
              'backgroundColor': '#E8F5E9',
              'padding': '16 24',
              'borderRadius': 12,
              'marginBottom': '20',
            },
            'children': [
              {
                'type': 'Text',
                'props': {'data': _greeting!},
                'style': {
                  'fontSize': 20,
                  'fontWeight': 'bold',
                  'color': '#2E7D32',
                },
              },
            ],
          },
        ],
        {
          'type': 'TextField',
          'key': 'name-input',
          'props': {
            'hint': 'Enter your name',
            'value': _username,
          },
          'style': {
            'padding': '12',
            'borderRadius': 8,
            'width': 260,
            'backgroundColor': '#1E293B',
            'color': '#E2E8F0',
          },
          'events': {'change': 'onInput'},
        },
        {
          'type': 'Button',
          'key': 'submit-btn',
          'props': {'text': 'Submit'},
          'style': {
            'marginTop': '16',
            'padding': '12 40',
            'backgroundColor': '#2196F3',
            'color': '#FFFFFF',
            'borderRadius': 10,
            'fontSize': 16,
          },
          'events': {'click': 'onSubmit'},
        },
      ],
    };
  }

  // -----------------------------------------------------------------------
  // Build
  // -----------------------------------------------------------------------

  Widget _buildDemoCard(String title, String subtitle, Map<String, dynamic> viewJson) {
    return Container(
      width: 380,
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Card header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF334155), height: 32),
          // Rendered engine output
          _engine.renderFromJson(viewJson),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
            child: Column(
              children: [
                // Page title
                const Icon(Icons.touch_app, color: Color(0xFF818CF8), size: 40),
                const SizedBox(height: 12),
                const Text(
                  'VM Event Bridge Demos',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'UI events automatically call VM functions via string handlers.\n'
                  'Each button\'s "events" map contains a VM function name as a string.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 40),

                // Toggle demo
                _buildDemoCard(
                  'Toggle Switch',
                  'events: {"click": "onToggle"}',
                  _buildToggleView(),
                ),

                // Counter demo
                _buildDemoCard(
                  'Counter',
                  'events: {"click": "onIncrement"} / "onDecrement" / "onReset"',
                  _buildCounterView(),
                ),

                // Form demo
                _buildDemoCard(
                  'Form Submit',
                  'events: {"change": "onInput", "click": "onSubmit"}',
                  _buildFormView(),
                ),

                const SizedBox(height: 16),
                const Text(
                  'These demos exercise the same EventDispatcher.vmEventCallback\n'
                  'bridge that ElpianVmWidget wires up internally.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 12,
                    height: 1.5,
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
