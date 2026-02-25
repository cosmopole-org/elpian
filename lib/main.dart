import 'package:flutter/material.dart';

import 'example/dom_canvas_logic_example.dart';
import 'example/quickjs_calculator_example.dart';
import 'example/quickjs_example.dart';
import 'example/quickjs_whiteboard_example.dart';
import 'example/vm_example.dart';

void main() {
  runApp(const ElpianExamplesApp());
}

class ElpianExamplesApp extends StatelessWidget {
  const ElpianExamplesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Elpian Examples',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
      ),
      home: const ElpianExamplesHome(),
    );
  }
}

class ElpianExamplesHome extends StatelessWidget {
  const ElpianExamplesHome({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                color: Theme.of(context).colorScheme.surface,
                child: const TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: 'Calculator'),
                    Tab(text: 'Whiteboard'),
                    Tab(text: 'QuickJS Runtime'),
                    Tab(text: 'AST VM'),
                    Tab(text: 'DOM + Canvas'),
                  ],
                ),
              ),
              const Expanded(
                child: TabBarView(
                  physics: NeverScrollableScrollPhysics(),
                  children: [
                    QuickJsCalculatorExamplePage(),
                    QuickJsWhiteboardExamplePage(),
                    QuickJsExamplePage(),
                    VmExamplePage(),
                    DomCanvasLogicExamplePage(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
