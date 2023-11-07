import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;

class IptvUtils {
  static const String directoryPath = '/assets/iptv/';
  static const String category = 'category';
  static const String recomand = 'recomand';

  static Future<List<IptvCategory>> readCategory() async {
    String jsonData = await loadJsonFromAssets('assets/iptv/categories.json');
    List json = jsonDecode(jsonData);
    return json.map((e) => IptvCategory.fromJson(e)).toList();
  }

  static Future<String> loadJsonFromAssets(String assetsPath) async {
    return await rootBundle.loadString(assetsPath);
  }

  static Future<List<IptvCategoryItem>> readCategoryItems(filePath) async {
    String prefix = 'assets/iptv/category/';
    // String jsonData = await loadJsonFromAssets(prefix + filePath);
    // print(jsonData.split(',').length);
    final file = File(prefix + filePath); // 替换成你的文件路径
    List<String> lines = await file.readAsLines();
    RegExp exp = RegExp(r'(?:(?:https?|ftp):\/\/)?[\w/\-?=%.]+\.[\w/\-?=%.]+');
    List<IptvCategoryItem> list = [];
    for (var i = 0; i < lines.length; i++) {
      List<String> linesObj = lines[i].split(',');
      if (linesObj.length > 1 && exp.hasMatch(linesObj[1])) {
        list.add(IptvCategoryItem(
            id: i.toString(), name: linesObj[0], liveUrl: linesObj[1]));
      }
    }
    return list;
  }

  static Future<List<IptvCategoryItem>> readRecommandsItems() async {
    String path = 'assets/iptv/recomand/index.txt';
    // String jsonData = await loadJsonFromAssets(prefix + filePath);
    // print(jsonData.split(',').length);
    final file = File(path); // 替换成你的文件路径
    List<String> lines = await file.readAsLines();
    RegExp exp = RegExp(r'(?:(?:https?|ftp):\/\/)?[\w/\-?=%.]+\.[\w/\-?=%.]+');
    List<IptvCategoryItem> list = [];
    for (var i = 0; i < lines.length; i++) {
      List<String> linesObj = lines[i].split(',');
      if (linesObj.length > 1 && exp.hasMatch(linesObj[1])) {
        list.add(IptvCategoryItem(
            id: i.toString(), name: linesObj[0], liveUrl: linesObj[1]));
      }
    }
    return list;
  }
}

class IptvCategory {
  final String id;
  final String name;
  final String path;

  IptvCategory({required this.id, required this.name, required this.path});

  factory IptvCategory.fromJson(Map<String, dynamic> json) {
    return IptvCategory(
      name: json['name'],
      id: json['id'],
      path: json['path'],
    );
  }
}

class IptvCategoryItem {
  final String id;
  final String name;
  final String liveUrl;

  IptvCategoryItem(
      {required this.id, required this.name, required this.liveUrl});

  factory IptvCategoryItem.fromJson(Map<String, dynamic> json) {
    return IptvCategoryItem(
      name: json['name'],
      id: json['id'],
      liveUrl: json['liveUrl'],
    );
  }
}
