import 'package:flutter/material.dart';
import '../models/stac_node.dart';

class StacScaffold {
  static Widget build(StacNode node, List<Widget> children) {
    PreferredSizeWidget? appBar;
    Widget? body;
    
    if (children.isNotEmpty) {
      body = children.last;
    }
    
    return Scaffold(
      appBar: appBar,
      body: body,
    );
  }
}
