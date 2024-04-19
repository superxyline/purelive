import 'package:get/get.dart';
import 'package:pure_live/core/sites.dart';
import 'package:pure_live/common/base/base_controller.dart';

class SearchListController extends BasePageController {
  final keyword = "".obs;

  final Site site;
  SearchListController(this.site);

  @override
  Future refreshData() async {
    if (keyword.value.isEmpty) {
      return;
    }
    return await super.refreshData();
  }

  @override
  Future<List> getData(int page, int pageSize) async {
    if (keyword.value.isEmpty) {
      return [];
    }
    var result = await site.liveSite.searchRooms(keyword.value, page: page);
    return result.items;
  }

  void clear() {
    currentPage = 1;
    list.value = [];
  }
}
