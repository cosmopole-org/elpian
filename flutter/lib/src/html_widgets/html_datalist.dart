import 'package:flutter/material.dart';
import '../models/elpian_node.dart';

/// `<datalist id>`: a list of `<option>` suggestions. Not rendered itself —
/// the engine indexes it (`DocumentIndex`) and every `<input list="id">`
/// offers its options as autocomplete suggestions (see `HtmlInput`).
class HtmlDatalist {
  static Widget build(ElpianNode node, List<Widget> children) {
    return const SizedBox.shrink();
  }
}
