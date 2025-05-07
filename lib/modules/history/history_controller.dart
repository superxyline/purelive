import 'dart:async';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/base/base_controller.dart';
import 'package:pure_live/modules/util/rx_util.dart';

import '../../common/base/one_base_controller.dart';
import '../util/update_room_util.dart';

class HistoryController extends OneBaseController<LiveRoom> {

  HistoryController();

  static HistoryController instance = HistoryController();

  @override
  Future refreshData() async {
    final SettingsService settings = SettingsService.instance;
    bool result = await UpdateRoomUtil.updateRoomList(settings.historyRooms, settings);
    if (result) {
      easyRefreshController.finishRefresh(IndicatorResult.success);
      easyRefreshController.resetFooter();
    } else {
      easyRefreshController.finishRefresh(IndicatorResult.fail);
    }
    return super.refreshData();
  }

  @override
  Future<List<LiveRoom>> getData(int page, int pageSize) async {
    final SettingsService settings = SettingsService.instance;
    final rooms = settings.historyRooms.toList().reversed.toList();
    canLoadMore.updateValueNotEquate(false);
    return rooms;
  }

}
