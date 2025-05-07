import 'dart:async';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/base/base_controller.dart';

import '../util/update_room_util.dart';

class HistoryController extends BasePageController<LiveRoom> {

  HistoryController();

  @override
  void onInit() {
    easyRefreshController = EasyRefreshController(controlFinishRefresh: true, controlFinishLoad: true);
    super.onInit();
  }

  @override
  Future<List<LiveRoom>> getData(int page, int pageSize) async {
    final SettingsService settings = Get.find<SettingsService>();
    bool result = await UpdateRoomUtil.updateRoomList(settings.historyRooms, settings);
    if (result) {
      easyRefreshController.finishRefresh(IndicatorResult.success);
      easyRefreshController.resetFooter();
    } else {
      easyRefreshController.finishRefresh(IndicatorResult.fail);
    }
    final rooms = settings.historyRooms.toList().reversed.toList();
    return rooms;
  }
}
