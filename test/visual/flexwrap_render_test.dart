import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:elpian_ui/elpian_ui.dart';

import 'visual_harness.dart';

Map<String, dynamic> _wrappingRow(int cards) => {
      'type': 'Row',
      'style': {'flexWrap': 'wrap', 'gap': 8},
      'children': [
        for (int i = 0; i < cards; i++)
          {
            'type': 'Container',
            'style': {
              'width': 140,
              'height': 60,
              'backgroundColor': i.isEven ? '#3F51B5' : '#E91E63',
              'borderRadius': 8,
            },
            'children': const [],
          },
      ],
    };

void main() {
  testWidgets('Row with flexWrap:wrap produces a Wrap and does not overflow',
      timeout: const Timeout(Duration(seconds: 60)), (tester) async {
    final engine = ElpianEngine();
    // 8 cards * 140px > 800px default viewport: with the fix this wraps instead
    // of throwing a RenderFlex overflow.
    final widget = engine.renderFromJson(_wrappingRow(8));

    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(key: key, child: widget),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    // A Wrap is emitted (not a Row), and no overflow exception was thrown.
    expect(find.byType(Wrap), findsOneWidget);
    expect(find.byType(Row), findsNothing);
    expect(tester.takeException(), isNull);

    File? file;
    await tester.runAsync(() async {
      file = await captureBoundaryToPng(key, 'flexwrap_row');
    });
    expect(file!.existsSync(), isTrue);
  });

  testWidgets('Row without flexWrap stays a Row',
      timeout: const Timeout(Duration(seconds: 60)), (tester) async {
    final engine = ElpianEngine();
    final widget = engine.renderFromJson({
      'type': 'Row',
      'style': {'gap': 8},
      'children': [
        {'type': 'Container', 'style': {'width': 40, 'height': 40}, 'children': const []},
        {'type': 'Container', 'style': {'width': 40, 'height': 40}, 'children': const []},
      ],
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: widget)));
    await tester.pump();
    expect(find.byType(Row), findsOneWidget);
    expect(find.byType(Wrap), findsNothing);
  });
}
