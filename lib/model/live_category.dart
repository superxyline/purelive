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
      : id = json['id']?.toString() ?? '',
        name = json['name']?.toString() ?? '',
        children = (json['children'] as List? ?? [])
            .map((e) => LiveArea.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();

  @override
  String toString() {
    return json.encode({
      "name": name,
      "id": id,
      "children": children,
    });
  }
}
