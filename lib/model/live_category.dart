import 'dart:convert';

import 'package:pure_live/common/models/index.dart';

class LiveCategory {
  final String name;
  final String id;
  final List<LiveArea> children;
  LiveCategory({
    required this.id,
    required this.name,
    required this.children,
  });

  LiveCategory.fromJson(Map<String, dynamic> json)
      : name = json['name'] ?? '',
        id = json['id'] ?? '',
        children = jsonDecode(json['children'] ?? "[]") as List<LiveArea>;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'id': id,
      'children': jsonEncode(children),
    };
  }

  @override
  String toString() {
    return json.encode({
      "name": name,
      "id": id,
      "children": children,
    });
  }
}
