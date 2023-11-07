import 'dart:convert';
import 'dart:developer';
import 'package:flutter/services.dart' show rootBundle;

class IptvUtils {
  static const String directoryPath = '/assets/iptv/';
  static const String category = 'category';
  static const String recomand = 'recomand';

  static Future<List<IptvCategory>> readCategory() async {
    try {
      String jsonData = await loadJsonFromAssets('assets/iptv/categories.json');
      List json = jsonDecode(jsonData);
      return json.map((e) => IptvCategory.fromJson(e)).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<String> loadJsonFromAssets(String assetsPath) async {
    return await rootBundle.loadString(assetsPath);
  }

  static Future<List<IptvCategoryItem>> readCategoryItems(filePath) async {
    String prefix = 'assets/iptv/category/';
    RegExp exp = RegExp(r'(?:(?:https?|ftp):\/\/)?[\w/\-?=%.]+\.[\w/\-?=%.]+');
    List<IptvCategoryItem> list = [];
    try {
      await loadJsonFromAssets(prefix + filePath).then((value) {
      for (String i in const LineSplitter().convert(value)) {
        List<String> linesObj = i.split(',');
        if (linesObj.length > 1 && exp.hasMatch(linesObj[1])) {
          list.add(IptvCategoryItem(
              id: i.toString(), name: linesObj[0], liveUrl: linesObj[1]));
        }
      }
    });
    } catch (e) {
      log(e.toString());
    }
    return list;
  }

  static Future<List<IptvCategoryItem>> readRecommandsItems() async {
    String path = 'assets/iptv/recomand/index.txt';
    RegExp exp = RegExp(r'(?:(?:https?|ftp):\/\/)?[\w/\-?=%.]+\.[\w/\-?=%.]+');
    List<IptvCategoryItem> list = [];
    try {
      await loadJsonFromAssets(path).then((value) {
      for (String i in const LineSplitter().convert(value)) {
        List<String> linesObj = i.split(',');
        if (linesObj.length > 1 && exp.hasMatch(linesObj[1])) {
          list.add(IptvCategoryItem(
              id: i.toString(), name: linesObj[0], liveUrl: linesObj[1]));
        }
      }
    });
    } catch (e) {
      log(e.toString());
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
