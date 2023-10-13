import 'package:pure_live/common/base/base_controller.dart';
import 'package:pure_live/common/index.dart';

class SearchListController extends BaseListController<LiveRoom> {
  String keyword = "";
  final Site site;
  SearchListController(
    this.site,
  );

  @override
  Future onRefresh() async {
    if (keyword.isEmpty) return;
    return await super.onRefresh();
  }

  @override
  Future<List<LiveRoom>> getData(int page, int pageSize) async {
    return await site.liveSite.search(keyword);
  }

  void clear() {
    pageEmpty.value = false;
    list.clear();
  }
}
