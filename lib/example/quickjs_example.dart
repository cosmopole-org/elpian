import 'dart:convert';

import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter/material.dart';

/// Demonstrates running JavaScript programs through [ElpianRuntime.quickJs]
/// while still rendering via Elpian's JSON DSL and host APIs.
class QuickJsExamplePage extends StatelessWidget {
  const QuickJsExamplePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('QuickJS Runtime Examples'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Counter'),
              Tab(text: 'Clock'),
              Tab(text: 'Host Data'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _QuickJsCounterDemo(),
            _QuickJsClockDemo(),
            _QuickJsHostDataDemo(),
          ],
        ),
      ),
    );
  }
}

class _QuickJsCounterDemo extends StatelessWidget {
  const _QuickJsCounterDemo();

  @override
  Widget build(BuildContext context) {
    return ElpianVmWidget.fromCode(
      machineId: 'quickjs-counter-demo',
      runtime: ElpianRuntime.quickJs,
      code: _counterProgram,
    );
  }
}

class _QuickJsClockDemo extends StatefulWidget {
  const _QuickJsClockDemo();

  @override
  State<_QuickJsClockDemo> createState() => _QuickJsClockDemoState();
}

class _QuickJsClockDemoState extends State<_QuickJsClockDemo> {
  final _controller = ElpianVmController();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ElpianVmScope(
            controller: _controller,
            machineId: 'quickjs-clock-demo',
            runtime: ElpianRuntime.quickJs,
            code: _clockProgram,
            entryFunction: 'tick',
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _controller.callFunction('tick'),
              icon: const Icon(Icons.schedule),
              label: const Text('Refresh from JS'),
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickJsHostDataDemo extends StatelessWidget {
  const _QuickJsHostDataDemo();

  @override
  Widget build(BuildContext context) {
    return ElpianVmWidget.fromCode(
      machineId: 'quickjs-host-data-demo',
      runtime: ElpianRuntime.quickJs,
      code: _hostDataProgram,
      onUpdateApp: (data) {
        debugPrint('QuickJS updateApp payload: ${jsonEncode(data)}');
      },
      onPrintln: (msg) {
        debugPrint('QuickJS println: $msg');
      },
      hostHandlers: {
        'getProfile': (apiName, payload) async {
          return jsonEncode({
            'type': 'string',
            'data': {
              'value': jsonEncode({
                'name': 'Elpian User',
                'role': 'Runtime Tester',
                'project': 'QuickJS + UI bridge',
              }),
            },
          });
        },
      },
    );
  }
}

const String _counterProgram = r'''
let count = 0;

function buildView() {
  askHost('render', JSON.stringify({
    type: 'Column',
    props: {
      style: {
        padding: '20',
        backgroundColor: '#f5f7ff'
      }
    },
    children: [
      {
        type: 'Text',
        props: {
          text: 'QuickJS Counter',
          style: { fontSize: '22', fontWeight: 'bold' }
        }
      },
      {
        type: 'Text',
        props: {
          text: `Current value: ${count}`,
          style: { fontSize: '18', color: '#3247D6' }
        }
      },
      {
        type: 'Text',
        props: {
          text: 'Tap card to increment from JS event handler',
          style: { fontSize: '14', color: '#666666' }
        }
      }
    ],
    events: {
      tap: 'increment'
    }
  }));
}

function increment() {
  count += 1;
  askHost('println', `Count changed to ${count}`);
  buildView();
}

buildView();
''';

const String _clockProgram = r'''
function tick() {
  const now = new Date().toISOString();
  askHost('render', JSON.stringify({
    type: 'Container',
    props: {
      style: {
        padding: '20',
        backgroundColor: '#101523',
        borderRadius: '12'
      }
    },
    children: [
      {
        type: 'Text',
        props: {
          text: 'QuickJS Clock',
          style: { color: '#FFFFFF', fontSize: '20', fontWeight: 'bold' }
        }
      },
      {
        type: 'SizedBox',
        props: { style: { height: '8' } }
      },
      {
        type: 'Text',
        props: {
          text: now,
          style: { color: '#9ec0ff', fontSize: '16' }
        }
      }
    ]
  }));
}

tick();
''';

const String _hostDataProgram = r'''
function loadProfile() {
  const profileTyped = askHost('getProfile', '{}');
  let profile = { name: 'Unknown', role: 'Unknown', project: 'Unknown' };
  try {
    const parsedTyped = JSON.parse(profileTyped);
    if (parsedTyped && parsedTyped.data && parsedTyped.data.value) {
      profile = JSON.parse(parsedTyped.data.value);
    }
  } catch (e) {
    askHost('println', `Profile parse failed: ${String(e)}`);
  }

  askHost('updateApp', JSON.stringify({
    source: 'quickjs',
    action: 'profileLoaded',
    profile
  }));

  askHost('render', JSON.stringify({
    type: 'Column',
    props: { style: { padding: '20' } },
    children: [
      {
        type: 'Text',
        props: {
          text: 'Host API Roundtrip',
          style: { fontSize: '20', fontWeight: 'bold' }
        }
      },
      {
        type: 'Text',
        props: { text: `Name: ${profile.name}` }
      },
      {
        type: 'Text',
        props: { text: `Role: ${profile.role}` }
      },
      {
        type: 'Text',
        props: { text: `Project: ${profile.project}` }
      }
    ]
  }));
}

loadProfile();
''';
