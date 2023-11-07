import 'dart:convert';
import 'dart:developer';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pure_live/core/iptv/src/m3u_item.dart';
import 'package:pure_live/core/iptv/src/m3u_list.dart';

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
    List<IptvCategoryItem> list = [];
    try {
       final m3uList = await M3uList.loadFromFile(prefix + filePath);
      for (M3uItem item in m3uList.items) {
        list.add(IptvCategoryItem(
            id: 'id${item.link}', name: item.title, liveUrl: item.link));
      }
    } catch (e) {
      log(e.toString());
    }
    return list;
  }

  static Future<List<IptvCategoryItem>> readRecommandsItems() async {
    String path = 'assets/iptv/recomand/11.m3u';
    List<IptvCategoryItem> list = [];
    try {
      final m3uList = await M3uList.loadFromFile(path);
      for (M3uItem item in m3uList.items) {
        list.add(IptvCategoryItem(
            id: 'id${item.link}', name: item.title, liveUrl: item.link));
      }
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
