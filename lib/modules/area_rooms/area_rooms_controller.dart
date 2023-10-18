import 'package:pure_live/common/base/base_controller.dart';
import 'package:pure_live/common/index.dart';

class AreaRoomsController extends BaseListController<LiveRoom> {
  AreaRoomsController(this.area);

  final LiveArea area;

  @override
  Future<List<LiveRoom>> getData(int page, int pageSize) async {
    return await Sites.of(area.platform)
        .liveSite
        .getAreaRooms(area, page: page, size: pageSize);
  }

  @override
  void onInit() {
    super.onInit();
    scrollController.addListener(() {
      final pos = scrollController.position;
      if (pos.maxScrollExtent - pos.pixels < 100) {
        onLoading();
      }
    });
  }
}
