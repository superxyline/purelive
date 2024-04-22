import 'dart:async';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';

class FavoriteController extends GetxController with GetTickerProviderStateMixin {
  final SettingsService settings = Get.find<SettingsService>();
  late TabController tabController;
  late TabController tabSiteController;
  final tabBottomIndex = 0.obs;
  final tabSiteIndex = 0.obs;
  final tabOnlineIndex = 0.obs;
  bool isFirstLoad = true;
  FavoriteController() {
    tabController = TabController(length: 2, vsync: this);
    tabSiteController = TabController(length: Sites().availableSites().length + 1, vsync: this);
  }

  @override
  void onInit() {
    super.onInit();
    // 初始化关注页
    syncRooms();
    // 监听settings rooms变化
    settings.favoriteRooms.listen((rooms) => syncRooms());
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

  final onlineRooms = [].obs;
  final offlineRooms = [].obs;

  void syncRooms() {
    onlineRooms.clear();
    offlineRooms.clear();
    onlineRooms.addAll(settings.favoriteRooms.where((room) => room.liveStatus == LiveStatus.live));
    offlineRooms.addAll(settings.favoriteRooms.where((room) => room.liveStatus != LiveStatus.live));
    for (var room in onlineRooms) {
      if (int.tryParse(room.watching!) == null) {
        room.watching = "0";
      }
    }
    onlineRooms.sort((a, b) => int.parse(b.watching!).compareTo(int.parse(a.watching!)));
  }

  Future<bool> onRefresh() async {
    // 自动刷新时间为0关闭。不是手动刷新并且不是第一次刷新
    if (isFirstLoad) {
      await const Duration(seconds: 1).delay();
    }
    bool hasError = false;
    List<Future<LiveRoom>> futures = [];
    if (settings.favoriteRooms.value.isEmpty) {
      return false;
    }
    var currentRooms = settings.favoriteRooms.value;
    if (tabSiteIndex.value != 0) {
      currentRooms = settings.favoriteRooms.value
          .where((element) => element.platform == Sites().availableSites()[tabSiteIndex.value].id)
          .toList();
    }

    for (final room in currentRooms) {
      futures.add(Sites.of(room.platform!)
          .liveSite
          .getRoomDetail(roomId: room.roomId!, platform: room.platform!, title: room.title!, nick: room.nick!));
    }
    List<List<Future<LiveRoom>>> groupedList = [];

    // 每次循环处理四个元素
    for (int i = 0; i < futures.length; i += 3) {
      // 获取当前循环开始到下一个四个元素的位置（但不超过原列表长度）
      int end = i + 3;
      if (end > futures.length) {
        end = futures.length;
      }
      // 截取当前四个元素的子列表
      List<Future<LiveRoom>> subList = futures.sublist(i, end);
      // 将子列表添加到结果列表中
      groupedList.add(subList);
    }
    try {
      for (var i = 0; i < groupedList.length; i++) {
        await Future.delayed(const Duration(milliseconds: 300));
        final rooms = await Future.wait(groupedList[i]);
        for (var room in rooms) {
          settings.updateRoom(room);
        }
        syncRooms();
      }
    } catch (e) {
      hasError = true;
    }
    isFirstLoad = false;
    return hasError;
  }
}
