import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/common/core_log.dart';

import '../util/update_room_util.dart';

class FavoriteController extends GetxController
    with GetTickerProviderStateMixin {
  final SettingsService settings = Get.find<SettingsService>();
  late TabController tabController;
  late TabController tabSiteController;
  final tabBottomIndex = 0.obs;
  final tabSiteIndex = 0.obs;
  final tabOnlineIndex = 0.obs;
  bool isFirstLoad = true;

  FavoriteController() {
    tabController = TabController(length: 2, vsync: this);
    tabSiteController =
        TabController(length: Sites().availableSites().length + 1, vsync: this);
  }

  final workerList = <Worker>[];
  final listenList = <StreamSubscription>[];

  @override
  void onInit() {
    super.onInit();
    // 初始化关注页
    syncRooms();
    workerList.clear();
    listenList.clear();
    // 监听settings rooms变化
    // debounce(settings.favoriteRooms, (rooms) => syncRooms(), time: const Duration(milliseconds: 1000));
    listenList.add(settings.favoriteRoomsLengthChangeFlag.listen((rooms) => syncRooms()));
    listenList.add(onlineRooms.listen((rooms) {CoreLog.d("onlineRooms ....");}));
    onRefresh();
    tabController.addListener(() {
      tabOnlineIndex.value = tabController.index;
    });
    tabSiteController.addListener(() {
      tabSiteIndex.value = tabSiteController.index;
    });
    // 定时自动刷新
    if (settings.autoRefreshTime.value != 0) {
      Timer.periodic(
        Duration(minutes: settings.autoRefreshTime.value),
        (timer) => onRefresh(),
      );
    }
  }

  final onlineRooms = <LiveRoom>[].obs;
  final offlineRooms = <LiveRoom>[].obs;

  void syncRooms() {
    CoreLog.d("syncRooms ....");
    // CoreLog.d(StackTrace.current.toString());
    // onlineRooms.clear();
    // offlineRooms.clear();
    // onlineRooms.addAll();
    var onlineList = settings.favoriteRooms
        .where((room) => room.liveStatus == LiveStatus.live)
        .map((room) {
      room.watching =
          readableCount(readableCountStrToNum(room.watching).toString());
      return room;
    }).toList();
    onlineList.sort((a,b)=> readableCountStrToNum(b.watching).compareTo( readableCountStrToNum(a.watching)));
    onlineRooms.value = onlineList;

    var offlineList = settings.favoriteRooms
        .where((room) => room.liveStatus == LiveStatus.offline)
        .map((room) {
      room.watching =
          readableCount(readableCountStrToNum(room.watching).toString());
      return room;
    }).toList();
    offlineRooms.value = offlineList;
    // onlineRooms.sort(
    //     (a, b) => int.parse(b.watching!).compareTo(int.parse(a.watching!)));
  }

  Future<bool> onRefresh() async {
    // 自动刷新时间为0关闭。不是手动刷新并且不是第一次刷新
    if (isFirstLoad) {
      await const Duration(seconds: 1).delay();
    }
    bool hasError = false;
    if (settings.favoriteRooms.value.isEmpty) {
      return false;
    }
    var currentRooms = settings.favoriteRooms.value;
    if (tabSiteIndex.value != 0) {
      currentRooms = settings.favoriteRooms.value
          .where((element) =>
              element.platform ==
              Sites().availableSites(containsAll: true)[tabSiteIndex.value].id)
          .toList();
    }

    hasError = await UpdateRoomUtil.updateRoomList(currentRooms, settings);
    syncRooms();
    isFirstLoad = false;
    return hasError;
  }

  @override
  void dispose() {
    workerList.map((w) {
      w.dispose();
    });
    workerList.clear();
    listenList.map((w) {
      w.cancel();
    });
    listenList.clear();
    super.dispose();
  }
}
