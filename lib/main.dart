import 'dart:convert';

import 'package:elpian_ui/elpian_ui.dart';
import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ElpianVmScope(
        controller: _controller,
        machineId: 'elpian-unified-demo',
        runtime: ElpianRuntime.quickJs,
        code: _unifiedProgram,
        onUpdateApp: (data) {
          debugPrint('updateApp: ${jsonEncode(data)}');
        },
        onPrintln: (msg) {
          debugPrint('println: $msg');
        },
        hostHandlers: {
          'getProfile': (apiName, payload) async {
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

/// The entire application lives inside this single JavaScript program.
///
/// It manages:
///   • Top-level tab navigation (UI, Canvas, VM, DOM+Canvas)
///   • Per-tab sub-navigation
///   • Counter state, clock state, theme toggle, host-data roundtrip
///   • Canvas command generation
///   • DOM host-API calls
///
/// Everything is rendered through `askHost('render', ...)`.
const String _unifiedProgram = r'''
// ─────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────
let activeTab = 0;
let activeSubTab = 0;

// Counter demo
let count = 0;

// Clock demo
let clockTime = new Date().toISOString();

// Theme demo
let isDark = false;

// Host data demo
let profile = null;

// DOM + Canvas demo
let domCanvasCount = 0;
let domCanvasColors = ['#4f46e5', '#059669', '#dc2626', '#d97706'];
let domCanvasColorIdx = 0;

const TABS = ['UI Widgets', 'Canvas', 'VM Demos', 'DOM + Canvas'];

// ─────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────
function text(t, style) {
  return { type: 'Text', props: { text: String(t), style: style || {} } };
}

function heading(t, size) {
  return text(t, { fontSize: String(size || 22), fontWeight: 'bold', color: '#1e293b' });
}

function subheading(t) {
  return text(t, { fontSize: '17', fontWeight: '600', color: '#475569' });
}

function spacer(h) {
  return { type: 'SizedBox', props: { style: { height: String(h || 12) } } };
}

function card(children, extraStyle) {
  const base = {
    padding: '16',
    backgroundColor: '#ffffff',
    borderRadius: '12',
    border: '1px solid #e2e8f0'
  };
  return {
    type: 'Container',
    props: { style: Object.assign(base, extraStyle || {}) },
    children: children
  };
}

function btn(label, handler, style) {
  const base = {
    backgroundColor: '#6366f1',
    color: '#ffffff',
    padding: '10 20',
    borderRadius: '8',
    fontSize: '14',
    fontWeight: '600'
  };
  return {
    type: 'Button',
    props: { text: label, style: Object.assign(base, style || {}) },
    events: { tap: handler }
  };
}

function col(children, style) {
  return { type: 'Column', props: { style: style || {} }, children: children };
}

function row(children, style) {
  return { type: 'Row', props: { style: style || {} }, children: children };
}

function divider() {
  return { type: 'Container', props: { style: { height: '1', backgroundColor: '#e2e8f0', margin: '8 0' } } };
}

// ─────────────────────────────────────────────────────────
// Tab bar (rendered as part of the QuickJS view tree)
// ─────────────────────────────────────────────────────────
function buildTabBar() {
  const tabs = TABS.map((label, i) => {
    const isActive = i === activeTab;
    return {
      type: 'Container',
      props: {
        style: {
          padding: '12 20',
          backgroundColor: isActive ? '#6366f1' : '#f1f5f9',
          borderRadius: '8 8 0 0',
          margin: '0 2 0 0'
        }
      },
      events: { tap: 'switchTab_' + i },
      children: [
        text(label, {
          fontSize: '14',
          fontWeight: isActive ? 'bold' : '500',
          color: isActive ? '#ffffff' : '#64748b'
        })
      ]
    };
  });

  return {
    type: 'Container',
    props: {
      style: {
        backgroundColor: '#f8fafc',
        padding: '12 16 0 16',
        borderRadius: '0',
        border: '0 0 1px 0 solid #e2e8f0'
      }
    },
    children: [
      row([
        text('Elpian', { fontSize: '20', fontWeight: 'bold', color: '#6366f1', margin: '0 16 0 0' }),
        text('Unified QuickJS Example', { fontSize: '14', color: '#94a3b8' })
      ], { alignItems: 'center', margin: '0 0 12 0' }),
      { type: 'Row', props: { style: { gap: '0' } }, children: tabs }
    ]
  };
}

// ─────────────────────────────────────────────────────────
// Sub-tab builder
// ─────────────────────────────────────────────────────────
function buildSubTabs(labels) {
  const chips = labels.map((label, i) => {
    const isActive = i === activeSubTab;
    return {
      type: 'Container',
      props: {
        style: {
          padding: '8 16',
          backgroundColor: isActive ? '#e0e7ff' : '#f8fafc',
          borderRadius: '20',
          border: isActive ? '1px solid #6366f1' : '1px solid #e2e8f0'
        }
      },
      events: { tap: 'switchSubTab_' + i },
      children: [
        text(label, {
          fontSize: '13',
          fontWeight: isActive ? '600' : '400',
          color: isActive ? '#4338ca' : '#64748b'
        })
      ]
    };
  });
  return row(chips, { gap: '8', margin: '0 0 16 0', flexWrap: 'wrap' });
}

// ─────────────────────────────────────────────────────────
// TAB 0 – UI Widgets
// ─────────────────────────────────────────────────────────
function buildUiWidgetsTab() {
  const subTabs = ['Flutter Widgets', 'HTML Elements', 'Dashboard'];
  const content = [buildFlutterWidgets, buildHtmlElements, buildDashboard];
  const idx = Math.min(activeSubTab, content.length - 1);
  return col([
    buildSubTabs(subTabs),
    content[idx]()
  ], { padding: '16' });
}

function buildFlutterWidgets() {
  return col([
    heading('Flutter Widgets'),
    spacer(8),
    card([
      text('This card is rendered entirely from QuickJS.', { fontSize: '15', color: '#475569' }),
      spacer(8),
      text('The engine supports all standard Flutter & HTML widgets.', { fontSize: '14', color: '#64748b' })
    ]),
    spacer(12),
    subheading('Buttons'),
    spacer(8),
    row([
      btn('Primary', 'noop', {}),
      btn('Success', 'noop', { backgroundColor: '#10b981' }),
      btn('Danger', 'noop', { backgroundColor: '#ef4444' }),
      btn('Warning', 'noop', { backgroundColor: '#f59e0b', color: '#1e293b' })
    ], { gap: '8', flexWrap: 'wrap' }),
    spacer(16),
    subheading('Cards Row'),
    spacer(8),
    row([
      card([
        text('1,234', { fontSize: '28', fontWeight: 'bold', color: '#ffffff' }),
        text('Users', { fontSize: '13', color: '#e2e8f0' })
      ], { backgroundColor: '#6366f1', flex: '1' }),
      card([
        text('567', { fontSize: '28', fontWeight: 'bold', color: '#ffffff' }),
        text('Sales', { fontSize: '13', color: '#e2e8f0' })
      ], { backgroundColor: '#10b981', flex: '1' }),
      card([
        text('89%', { fontSize: '28', fontWeight: 'bold', color: '#ffffff' }),
        text('Uptime', { fontSize: '13', color: '#e2e8f0' })
      ], { backgroundColor: '#f59e0b', flex: '1' })
    ], { gap: '12' }),
    spacer(16),
    subheading('Chips'),
    spacer(8),
    {
      type: 'Wrap',
      props: { style: { gap: '8' } },
      children: [
        { type: 'Chip', props: { label: 'Flutter' }, style: { backgroundColor: '#e0e7ff' } },
        { type: 'Chip', props: { label: 'Dart' }, style: { backgroundColor: '#fce7f3' } },
        { type: 'Chip', props: { label: 'QuickJS' }, style: { backgroundColor: '#d1fae5' } },
        { type: 'Chip', props: { label: 'Elpian' }, style: { backgroundColor: '#fef3c7' } }
      ]
    }
  ]);
}

function buildHtmlElements() {
  return col([
    heading('HTML Elements'),
    spacer(8),
    { type: 'h1', props: { text: 'Heading 1' }, style: { color: '#e11d48' } },
    { type: 'h2', props: { text: 'Heading 2' }, style: { color: '#7c3aed' } },
    { type: 'h3', props: { text: 'Heading 3' }, style: { color: '#2563eb' } },
    spacer(8),
    { type: 'p', props: { text: 'This is a paragraph rendered from the QuickJS runtime through the Elpian engine.' }, style: { fontSize: '16', color: '#475569', lineHeight: '1.6' } },
    spacer(8),
    {
      type: 'ul',
      children: [
        { type: 'li', props: { text: 'Unordered list item 1' } },
        { type: 'li', props: { text: 'Unordered list item 2' } },
        { type: 'li', props: { text: 'Unordered list item 3' } }
      ]
    },
    spacer(8),
    {
      type: 'details',
      children: [
        { type: 'summary', props: { text: 'Click to expand' } },
        { type: 'p', props: { text: 'Hidden content revealed by the <details> element!' } }
      ]
    },
    spacer(8),
    row([
      { type: 'kbd', props: { text: 'Ctrl' } },
      text(' + ', { fontSize: '14' }),
      { type: 'kbd', props: { text: 'C' } }
    ], { alignItems: 'center', gap: '4' }),
    spacer(8),
    { type: 'progress', props: { value: 0.7, max: 1.0 }, style: { margin: '8 0' } },
    spacer(8),
    {
      type: 'blockquote',
      children: [
        { type: 'p', props: { text: '"The best way to predict the future is to invent it." — Alan Kay' } }
      ]
    }
  ]);
}

function buildDashboard() {
  return col([
    heading('Dashboard'),
    spacer(8),
    {
      type: 'header',
      style: { backgroundColor: '#1e293b', padding: '16', borderRadius: '10', margin: '0 0 12 0' },
      children: [
        { type: 'h2', props: { text: 'Statistics Overview' }, style: { color: '#ffffff', margin: '0' } }
      ]
    },
    row([
      card([
        text('Revenue', { fontSize: '13', color: '#94a3b8' }),
        text('$42,580', { fontSize: '24', fontWeight: 'bold', color: '#10b981' })
      ], { flex: '1' }),
      card([
        text('Orders', { fontSize: '13', color: '#94a3b8' }),
        text('1,847', { fontSize: '24', fontWeight: 'bold', color: '#6366f1' })
      ], { flex: '1' }),
      card([
        text('Customers', { fontSize: '13', color: '#94a3b8' }),
        text('3,210', { fontSize: '24', fontWeight: 'bold', color: '#f59e0b' })
      ], { flex: '1' })
    ], { gap: '12' }),
    spacer(12),
    card([
      subheading('Recent Activity'),
      spacer(8),
      text('• New user signed up – john@example.com', { fontSize: '14', color: '#64748b' }),
      text('• Order #1847 completed', { fontSize: '14', color: '#64748b' }),
      text('• Server uptime: 99.98%', { fontSize: '14', color: '#64748b' }),
      text('• 12 new support tickets', { fontSize: '14', color: '#64748b' })
    ]),
    spacer(12),
    {
      type: 'footer',
      style: { padding: '14', backgroundColor: '#f1f5f9', borderRadius: '10' },
      children: [
        { type: 'p', props: { text: '© 2025 Elpian UI – QuickJS Unified Demo' }, style: { textAlign: 'center', color: '#94a3b8', margin: '0', fontSize: '13' } }
      ]
    }
  ]);
}

// ─────────────────────────────────────────────────────────
// TAB 1 – Canvas
// ─────────────────────────────────────────────────────────
function buildCanvasTab() {
  const subTabs = ['Shapes', 'Paths & Curves', 'Text', 'Gradients'];
  const content = [buildCanvasShapes, buildCanvasPaths, buildCanvasText, buildCanvasGradients];
  const idx = Math.min(activeSubTab, content.length - 1);
  return col([
    buildSubTabs(subTabs),
    content[idx]()
  ], { padding: '16' });
}

function buildCanvasShapes() {
  return col([
    heading('Basic Shapes'),
    spacer(8),
    subheading('Rectangles'),
    {
      type: 'Canvas',
      props: {
        width: 400, height: 160,
        commands: [
          { type: 'setFillStyle', params: { color: '#ef4444' } },
          { type: 'fillRect', params: { x: 20, y: 20, width: 100, height: 80 } },
          { type: 'setStrokeStyle', params: { color: '#3b82f6' } },
          { type: 'setLineWidth', params: { width: 3 } },
          { type: 'strokeRect', params: { x: 140, y: 20, width: 100, height: 80 } },
          { type: 'setFillStyle', params: { color: '#22c55e' } },
          { type: 'beginPath', params: {} },
          { type: 'roundRect', params: { x: 260, y: 20, width: 100, height: 80, radius: 12 } },
          { type: 'fill', params: {} }
        ]
      }
    },
    spacer(12),
    subheading('Circles'),
    {
      type: 'Canvas',
      props: {
        width: 400, height: 160,
        commands: [
          { type: 'setFillStyle', params: { color: '#8b5cf6' } },
          { type: 'fillCircle', params: { cx: 70, cy: 80, radius: 50 } },
          { type: 'setStrokeStyle', params: { color: '#f97316' } },
          { type: 'setLineWidth', params: { width: 4 } },
          { type: 'strokeCircle', params: { cx: 200, cy: 80, radius: 50 } },
          { type: 'setFillStyle', params: { color: '#06b6d4' } },
          { type: 'beginPath', params: {} },
          { type: 'ellipse', params: { cx: 330, cy: 80, rx: 55, ry: 40 } },
          { type: 'fill', params: {} }
        ]
      }
    }
  ]);
}

function buildCanvasPaths() {
  return col([
    heading('Paths & Curves'),
    spacer(8),
    subheading('Bezier Curves'),
    {
      type: 'Canvas',
      props: {
        width: 400, height: 160,
        commands: [
          { type: 'setStrokeStyle', params: { color: '#3b82f6' } },
          { type: 'setLineWidth', params: { width: 3 } },
          { type: 'beginPath', params: {} },
          { type: 'moveTo', params: { x: 50, y: 80 } },
          { type: 'bezierCurveTo', params: { cp1x: 100, cp1y: 10, cp2x: 150, cp2y: 150, x: 200, y: 80 } },
          { type: 'stroke', params: {} },
          { type: 'setStrokeStyle', params: { color: '#22c55e' } },
          { type: 'beginPath', params: {} },
          { type: 'moveTo', params: { x: 220, y: 80 } },
          { type: 'quadraticCurveTo', params: { cpx: 280, cpy: 10, x: 340, y: 80 } },
          { type: 'stroke', params: {} }
        ]
      }
    },
    spacer(12),
    subheading('Triangle'),
    {
      type: 'Canvas',
      props: {
        width: 400, height: 160,
        commands: [
          { type: 'setFillStyle', params: { color: '#f97316' } },
          { type: 'setStrokeStyle', params: { color: '#c2410c' } },
          { type: 'setLineWidth', params: { width: 3 } },
          { type: 'beginPath', params: {} },
          { type: 'moveTo', params: { x: 200, y: 20 } },
          { type: 'lineTo', params: { x: 280, y: 140 } },
          { type: 'lineTo', params: { x: 120, y: 140 } },
          { type: 'closePath', params: {} },
          { type: 'fill', params: {} },
          { type: 'stroke', params: {} }
        ]
      }
    }
  ]);
}

function buildCanvasText() {
  return col([
    heading('Text Rendering'),
    spacer(8),
    {
      type: 'Canvas',
      props: {
        width: 400, height: 220,
        commands: [
          { type: 'setFillStyle', params: { color: '#1e293b' } },
          { type: 'setFont', params: { font: '24px Arial' } },
          { type: 'fillText', params: { text: 'Hello Canvas!', x: 40, y: 40 } },
          { type: 'setFont', params: { font: 'bold 28px Arial' } },
          { type: 'setFillStyle', params: { color: '#3b82f6' } },
          { type: 'fillText', params: { text: 'Bold Text', x: 40, y: 80 } },
          { type: 'setFont', params: { font: 'italic 20px Arial' } },
          { type: 'setFillStyle', params: { color: '#22c55e' } },
          { type: 'fillText', params: { text: 'Italic Text', x: 40, y: 120 } },
          { type: 'setStrokeStyle', params: { color: '#ef4444' } },
          { type: 'setLineWidth', params: { width: 1.5 } },
          { type: 'setFont', params: { font: 'bold 30px Arial' } },
          { type: 'strokeText', params: { text: 'Outlined', x: 40, y: 168 } },
          { type: 'setFillStyle', params: { color: '#fbbf24' } },
          { type: 'setFont', params: { font: 'bold 26px Arial' } },
          { type: 'fillText', params: { text: 'Golden', x: 40, y: 210 } }
        ]
      }
    }
  ]);
}

function buildCanvasGradients() {
  return col([
    heading('Gradients'),
    spacer(8),
    subheading('Linear Gradient'),
    {
      type: 'Canvas',
      props: {
        width: 400, height: 120,
        commands: [
          { type: 'createLinearGradient', params: { id: 'g1', x1: 40, y1: 60, x2: 360, y2: 60, colors: ['#ef4444', '#8b5cf6', '#3b82f6'] } },
          { type: 'setFillGradient', params: { id: 'g1' } },
          { type: 'fillRect', params: { x: 40, y: 20, width: 320, height: 80 } }
        ]
      }
    },
    spacer(12),
    subheading('Radial Gradient'),
    {
      type: 'Canvas',
      props: {
        width: 400, height: 180,
        commands: [
          { type: 'createRadialGradient', params: { id: 'g2', cx: 200, cy: 90, radius: 70, colors: ['#fbbf24', '#f97316', '#ef4444'] } },
          { type: 'setFillGradient', params: { id: 'g2' } },
          { type: 'fillCircle', params: { cx: 200, cy: 90, radius: 70 } }
        ]
      }
    }
  ]);
}

// ─────────────────────────────────────────────────────────
// TAB 2 – VM Demos (all driven by QuickJS state)
// ─────────────────────────────────────────────────────────
function buildVmDemosTab() {
  const subTabs = ['Counter', 'Clock', 'Theme Toggle', 'Host Data'];
  const content = [buildCounterDemo, buildClockDemo, buildThemeDemo, buildHostDataDemo];
  const idx = Math.min(activeSubTab, content.length - 1);
  return col([
    buildSubTabs(subTabs),
    content[idx]()
  ], { padding: '16' });
}

function buildCounterDemo() {
  return col([
    heading('Interactive Counter'),
    spacer(8),
    card([
      text('QuickJS Counter', { fontSize: '18', fontWeight: 'bold', color: '#1e293b' }),
      spacer(8),
      text(`Current value: ${count}`, { fontSize: '32', fontWeight: 'bold', color: '#6366f1' }),
      spacer(4),
      text('Tap the buttons below or the card to increment.', { fontSize: '14', color: '#94a3b8' })
    ], { border: '2px solid #e0e7ff' }),
    spacer(12),
    row([
      btn('− Decrement', 'decrement', { backgroundColor: '#64748b', flex: '1' }),
      btn('+ Increment', 'increment', { flex: '1' }),
    ], { gap: '8' }),
    spacer(8),
    btn('Reset', 'resetCounter', { backgroundColor: '#ef4444' })
  ]);
}

function buildClockDemo() {
  return col([
    heading('QuickJS Clock'),
    spacer(8),
    card([
      text('Current Time', { fontSize: '16', fontWeight: '600', color: '#94a3b8' }),
      spacer(8),
      text(clockTime, { fontSize: '22', fontWeight: 'bold', color: '#10b981' }),
      spacer(4),
      text('Press Refresh to update the timestamp from JS Date().', { fontSize: '13', color: '#94a3b8' })
    ], { backgroundColor: '#0f172a', border: 'none' }),
    spacer(12),
    btn('Refresh Clock', 'refreshClock', { backgroundColor: '#10b981' })
  ]);
}

function buildThemeDemo() {
  const bg = isDark ? '#1e293b' : '#ffffff';
  const fg = isDark ? '#f8fafc' : '#1e293b';
  const sub = isDark ? '#94a3b8' : '#64748b';
  const label = isDark ? 'Dark Mode' : 'Light Mode';
  const icon = isDark ? '🌙' : '☀️';

  return col([
    heading('Theme Toggle'),
    spacer(8),
    {
      type: 'Container',
      props: {
        style: {
          padding: '24',
          backgroundColor: bg,
          borderRadius: '12',
          border: isDark ? '1px solid #334155' : '1px solid #e2e8f0'
        }
      },
      children: [
        text(`${icon}  ${label}`, { fontSize: '22', fontWeight: 'bold', color: fg }),
        spacer(8),
        text('This entire card adapts based on a single boolean toggled in JS.', { fontSize: '14', color: sub }),
        spacer(8),
        text(`isDark = ${isDark}`, { fontSize: '13', fontWeight: '600', color: isDark ? '#818cf8' : '#6366f1' })
      ]
    },
    spacer(12),
    btn('Toggle Theme', 'toggleTheme', { backgroundColor: isDark ? '#818cf8' : '#6366f1' })
  ]);
}

function buildHostDataDemo() {
  const items = [];
  items.push(heading('Host Data Roundtrip'));
  items.push(spacer(8));
  items.push(text('Calls askHost("getProfile") to fetch data from the Dart host, parses the typed response, and renders it.', { fontSize: '14', color: '#64748b' }));
  items.push(spacer(12));

  if (profile) {
    items.push(card([
      text('Profile Loaded', { fontSize: '16', fontWeight: 'bold', color: '#10b981' }),
      spacer(8),
      text(`Name: ${profile.name}`, { fontSize: '15', color: '#1e293b' }),
      text(`Role: ${profile.role}`, { fontSize: '15', color: '#1e293b' }),
      text(`Project: ${profile.project}`, { fontSize: '15', color: '#1e293b' })
    ]));
  } else {
    items.push(card([
      text('No profile loaded yet.', { fontSize: '15', color: '#94a3b8' })
    ]));
  }

  items.push(spacer(12));
  items.push(btn('Load Profile', 'loadProfile', { backgroundColor: '#0891b2' }));
  return col(items);
}

// ─────────────────────────────────────────────────────────
// TAB 3 – DOM + Canvas (host APIs)
// ─────────────────────────────────────────────────────────
function buildDomCanvasTab() {
  return col([
    heading('DOM + Canvas Host APIs'),
    spacer(4),
    text('Uses askHost("dom.*") and askHost("canvas.*") to interact with the Dart-side host APIs, then renders combined output.', { fontSize: '14', color: '#64748b' }),
    spacer(12),
    buildDomCanvasCard(),
    spacer(8),
    buildDomCanvasCanvas(),
    spacer(12),
    row([
      btn('− Decrement', 'domCanvasDec', { backgroundColor: '#64748b', flex: '1' }),
      btn('+ Increment', 'domCanvasInc', { flex: '1' })
    ], { gap: '8' })
  ], { padding: '16' });
}

function typedValueOf(response) {
  try {
    const parsed = JSON.parse(response);
    if (parsed && parsed.data) return parsed.data.value;
  } catch (_) {}
  return null;
}

function buildDomCanvasCard() {
  askHost('dom.clear', '{}');
  askHost('dom.createElement', JSON.stringify({ tagName: 'div', id: 'rootCard' }));
  askHost('dom.setStyleObject', JSON.stringify({
    id: 'rootCard',
    styles: { padding: '14', backgroundColor: '#ffffff', borderRadius: '12', border: '1px solid #dbe2ff' }
  }));
  askHost('dom.createElement', JSON.stringify({ tagName: 'h3', id: 'title' }));
  askHost('dom.setTextContent', JSON.stringify({ id: 'title', text: 'DOM API Card' }));
  askHost('dom.createElement', JSON.stringify({ tagName: 'p', id: 'desc' }));
  askHost('dom.setTextContent', JSON.stringify({
    id: 'desc',
    text: `Counter: ${domCanvasCount} | Color: ${domCanvasColors[domCanvasColorIdx]}`
  }));
  askHost('dom.appendChild', JSON.stringify({ parentId: 'rootCard', childId: 'title' }));
  askHost('dom.appendChild', JSON.stringify({ parentId: 'rootCard', childId: 'desc' }));
  const rootResponse = askHost('dom.toJson', JSON.stringify({ id: 'rootCard' }));
  return typedValueOf(rootResponse) || { type: 'Text', props: { text: 'DOM unavailable' } };
}

function buildDomCanvasCanvas() {
  askHost('canvas.clear', '{}');
  askHost('canvas.setFillStyle', JSON.stringify({ color: '#f8faff' }));
  askHost('canvas.fillRect', JSON.stringify({ x: 0, y: 0, width: 400, height: 140 }));
  askHost('canvas.setFillStyle', JSON.stringify({ color: domCanvasColors[domCanvasColorIdx] }));
  askHost('canvas.fillRect', JSON.stringify({ x: 20, y: 20, width: Math.max(40, 40 + domCanvasCount * 20), height: 36 }));
  askHost('canvas.setStrokeStyle', JSON.stringify({ color: '#111827' }));
  askHost('canvas.setLineWidth', JSON.stringify({ width: 2 }));
  askHost('canvas.strokeRect', JSON.stringify({ x: 20, y: 20, width: 300, height: 36 }));
  askHost('canvas.fillText', JSON.stringify({ text: `count=${domCanvasCount}`, x: 20, y: 88 }));
  const resp = askHost('canvas.getCommands', '{}');
  const cmds = typedValueOf(resp) || [];
  return {
    type: 'Canvas',
    props: { width: 400, height: 140, commands: cmds }
  };
}

// ─────────────────────────────────────────────────────────
// Root renderer
// ─────────────────────────────────────────────────────────
function renderApp() {
  const tabContent = [buildUiWidgetsTab, buildCanvasTab, buildVmDemosTab, buildDomCanvasTab];
  const idx = Math.min(activeTab, tabContent.length - 1);

  askHost('render', JSON.stringify({
    type: 'Column',
    children: [
      buildTabBar(),
      {
        type: 'Expanded',
        children: [
          {
            type: 'ListView',
            props: { style: { backgroundColor: '#f8fafc' } },
            children: [tabContent[idx]()]
          }
        ]
      }
    ]
  }));
}

// ─────────────────────────────────────────────────────────
// Event handlers (called from Flutter via tap events)
// ─────────────────────────────────────────────────────────

// Tab switching
function switchTab_0() { activeTab = 0; activeSubTab = 0; renderApp(); }
function switchTab_1() { activeTab = 1; activeSubTab = 0; renderApp(); }
function switchTab_2() { activeTab = 2; activeSubTab = 0; renderApp(); }
function switchTab_3() { activeTab = 3; activeSubTab = 0; renderApp(); }

// Sub-tab switching
function switchSubTab_0() { activeSubTab = 0; renderApp(); }
function switchSubTab_1() { activeSubTab = 1; renderApp(); }
function switchSubTab_2() { activeSubTab = 2; renderApp(); }
function switchSubTab_3() { activeSubTab = 3; renderApp(); }

// Counter
function increment() {
  count += 1;
  askHost('println', `Count: ${count}`);
  askHost('updateApp', JSON.stringify({ source: 'quickjs', action: 'increment', value: count }));
  renderApp();
}

function decrement() {
  count = Math.max(0, count - 1);
  askHost('println', `Count: ${count}`);
  renderApp();
}

function resetCounter() {
  count = 0;
  renderApp();
}

// Clock
function refreshClock() {
  clockTime = new Date().toISOString();
  renderApp();
}

// Theme
function toggleTheme() {
  isDark = !isDark;
  askHost('println', `Theme toggled: isDark=${isDark}`);
  renderApp();
}

// Host data
function loadProfile() {
  const response = askHost('getProfile', '{}');
  try {
    const parsed = JSON.parse(response);
    if (parsed && parsed.type === 'string' && parsed.data && parsed.data.value) {
      profile = JSON.parse(parsed.data.value);
    }
  } catch (e) {
    askHost('println', `Profile parse error: ${String(e)}`);
  }
  askHost('updateApp', JSON.stringify({ source: 'quickjs', action: 'profileLoaded', profile: profile }));
  renderApp();
}

// DOM+Canvas
function domCanvasInc() {
  domCanvasCount += 1;
  domCanvasColorIdx = (domCanvasColorIdx + 1) % domCanvasColors.length;
  renderApp();
}

function domCanvasDec() {
  domCanvasCount = Math.max(0, domCanvasCount - 1);
  domCanvasColorIdx = (domCanvasColorIdx + domCanvasColors.length - 1) % domCanvasColors.length;
  renderApp();
}

// No-op for static buttons
function noop() {}

// ─────────────────────────────────────────────────────────
// Boot
// ─────────────────────────────────────────────────────────
renderApp();
''';
