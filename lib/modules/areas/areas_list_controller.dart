import 'dart:convert';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/model/live_category.dart';
import 'package:pure_live/common/base/base_controller.dart';
import 'package:pure_live/plugins/cache_to_file.dart';

class AreasListController extends BasePageController<AppLiveCategory> {
  final Site site;
  final tabIndex = 0.obs;
  AreasListController(this.site);

  @override
  Future<List<AppLiveCategory>> getData(int page, int pageSize) async {
    var cacheKey = "${site.id}_${tabIndex.value}_${page}_$pageSize";
    if(await CustomCache.instance.isExistCache(cacheKey)) {
      return (await CustomCache.instance.getCache<List<AppLiveCategory>>(cacheKey))!;
    }
    var result = await site.liveSite.getCategores(page, pageSize);
    var list = result.map((e) => AppLiveCategory.fromLiveCategory(e)).toList();
    CustomCache.instance.setCache(cacheKey, list);
    return list;
  }
}

class AppLiveCategory extends LiveCategory {
  var showAll = false.obs;
  AppLiveCategory({
    required super.id,
    required super.name,
    required super.children,
  }) {
    showAll.value = children.length < 19;
  }

  List<LiveArea> get take15 => children.take(15).toList();

  factory AppLiveCategory.fromLiveCategory(LiveCategory item) {
    return AppLiveCategory(
      children: item.children,
      id: item.id,
      name: item.name,
    );
  }
  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['id'] = id;
    json['name'] = name;
    json['children'] = children.map((LiveArea e) => jsonEncode(e.toJson())).toList();
    return json;
  }
}
