import 'dart:convert';
import '../models/stac_node.dart';

class JsonParser {
  static StacNode parse(String jsonString) {
    final Map<String, dynamic> json = jsonDecode(jsonString);
    return StacNode.fromJson(json);
  }

  static List<StacNode> parseList(String jsonString) {
    final List<dynamic> jsonList = jsonDecode(jsonString);
    return jsonList.map((json) => StacNode.fromJson(json as Map<String, dynamic>)).toList();
  }

  static String stringify(StacNode node) {
    return jsonEncode(node.toJson());
  }

  static String stringifyList(List<StacNode> nodes) {
    return jsonEncode(nodes.map((node) => node.toJson()).toList());
  }
}
