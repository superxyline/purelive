import 'dart:async';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/base/base_controller.dart';

class PopularGridController extends BasePageController<LiveRoom> {
  final Site site;

  PopularGridController(this.site);

  @override
  Future<List<LiveRoom>> getData(int page, int pageSize) async {
    var result = await site.liveSite.getRecommendRooms(page: page, nick: '热门');
    if (site.id == Sites.iptvSite && list.isNotEmpty) {
      return [];
    }
    return result.items;
  }
}
