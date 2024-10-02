import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/common/core_log.dart';
import 'package:pure_live/modules/util/site_logo_widget.dart';

class FavoritePage extends GetView<FavoriteController> {
  const FavoritePage({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraint) {
      bool showAction = Get.width <= 680;
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          scrolledUnderElevation: 0,
          leading: showAction ? const MenuButton() : null,
          actions: showAction
              ? [
            PopupMenuButton(
              tooltip: '搜索',
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              offset: const Offset(12, 0),
              position: PopupMenuPosition.under,
              icon: const Icon(Icons.read_more_sharp),
              onSelected: (int index) {
                if (index == 0) {
                  Get.toNamed(RoutePath.kSearch);
                } else {
                  Get.toNamed(RoutePath.kToolbox);
                }
              },
              itemBuilder: (BuildContext context) {
                return [
                  const PopupMenuItem(
                    value: 0,
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: MenuListTile(
                      leading: Icon(CustomIcons.search),
                      text: "搜索直播",
                    ),
                  ),
                  const PopupMenuItem(
                    value: 1,
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: MenuListTile(
                      leading: Icon(Icons.link),
                      text: "链接访问",
                    ),
                  ),
                ];
              },
            )
          ]
              : null,
          title: TabBar(
            controller: controller.tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.center,
            labelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            labelPadding: const EdgeInsets.symmetric(horizontal: 12),
            indicatorSize: TabBarIndicatorSize.label,
            tabs: [
              Tab(text: S
                  .of(context)
                  .online_room_title),
              Tab(text: S
                  .of(context)
                  .offline_room_title),
            ],
          ),
        ),
        body: TabBarView(
          controller: controller.tabController,
          children: [
            _RoomGridView(controller.onlineRooms),
            _RoomGridView(controller.offlineRooms),
          ],
        ),
      );
    });
  }
}

class _RoomGridView extends GetView<FavoriteController> {
  _RoomGridView(this.sourceRxList) {
    sourceRxList.listen((onData) {
      // CoreLog.d("sourceRxList change ... ${sourceRxList.hashCode} \n ${StackTrace.current.toString()}");
      CoreLog.d("sourceRxList change ... ${sourceRxList.hashCode} ");
      initSiteSet(onData);
      filter();
    });
    initSiteSet(sourceRxList.value);
    filter();
  }

  /// 存储已有的站点
  final siteSet = <String>{};

  void initSiteSet(List<LiveRoom> list) {
    siteSet.clear();
    siteSet.add(Sites.allSite);
    for (var room in list) {
      if (room.platform != null) {
        siteSet.add(room.platform!);
      }
    }
  }

  final RxList<LiveRoom> dataList = <LiveRoom>[].obs;
  final RxList<LiveRoom> sourceRxList;
  final refreshController = EasyRefreshController(
    controlFinishRefresh: true,
    controlFinishLoad: true,
  );
  final dense = Get
      .find<SettingsService>()
      .enableDenseFavorites
      .value;

  int sortByWatching(LiveRoom a, LiveRoom b) =>
      readableCountStrToNum(b.watching)
          .compareTo(readableCountStrToNum(a.watching));
  var isSort = false.obs;

  Rx<String> selectedSite = Rx(Sites.allSite);

  bool filterSite(LiveRoom a) =>
      selectedSite.value == Sites.allSite || a.platform == selectedSite.value;

  void filter() {
    // CoreLog.d("selectedSite ${selectedSite}");
    var list = sourceRxList.value;
    list = list.where(filterSite).toList();
    // CoreLog.d("${jsonEncode(list)}");
    if (isSort.value) {
      list.sort(sortByWatching);
    }
    dataList.value = list;
    // sort();
  }

  Future onRefresh() async {
    bool result = await controller.onRefresh();
    CoreLog.d("onRefresh favorite ...");
    if (!result) {
      refreshController.finishRefresh(IndicatorResult.success);
      refreshController.resetFooter();
    } else {
      refreshController.finishRefresh(IndicatorResult.fail);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraint) {
      final width = constraint.maxWidth;
      int crossAxisCount =
      width > 1280 ? 4 : (width > 960 ? 3 : (width > 640 ? 2 : 1));
      if (dense) {
        crossAxisCount =
        width > 1280 ? 5 : (width > 960 ? 4 : (width > 640 ? 3 : 2));
      }
      return EasyRefresh(
        controller: refreshController,
        onRefresh: onRefresh,
        onLoad: () {
          refreshController.finishLoad(IndicatorResult.success);
        },
        child: () {
          // CoreLog.d("rebuild dataList");
          // CoreLog.d("dataList \n ${jsonEncode(dataList.value)}");
          return Obx(() =>
          dataList.isNotEmpty
              ? Scaffold(
              body: () {
                CoreLog.d("MasonryGridView.count change ");
                return MasonryGridView.count(
                  padding: const EdgeInsets.all(5),
                  controller: ScrollController(),
                  crossAxisCount: crossAxisCount,
                  itemCount: dataList.length,
                  itemBuilder: (context, index) =>
                      RoomCard(
                        room: dataList[index],
                        dense: dense,
                      ),
                );
              }(),

              // 浮动按钮
              floatingActionButtonLocation:
              FloatingActionButtonLocation.endFloat,
              floatingActionButton: FloatingActionButton(
                  onPressed: () {
                    showFilter();
                  },
                  child: const Icon(Icons.local_offer)))
              : EmptyView(
            icon: Icons.favorite_rounded,
            title: S
                .of(context)
                .empty_favorite_online_title,
            subtitle: S
                .of(context)
                .empty_favorite_online_subtitle,
          ));
        }(),
      );
    });
  }

  void showFilter({BuildContext? context}) {
    var curContext = context ?? Get.context!;
    showModalBottomSheet(
      context: curContext,
      constraints: const BoxConstraints(
        maxWidth: 600,
      ),
      isScrollControlled: true,
      builder: (_) =>
          Container(
            padding: EdgeInsets.only(
              bottom: MediaQuery
                  .of(Get.context!)
                  .padding
                  .bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text("排序"),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    if (isSort.value != true) {
                      isSort.value = true;
                      filter();
                    }
                    Navigator.pop(curContext);
                  },
                ),
                ...siteSet.map((siteId) {
                  var site = Sites.allLiveSite;
                  if (siteId != Sites.allSite) {
                    site = Sites.of(siteId);
                  }
                  return ListTile(
                    leading: SiteWidget.getSiteLogeImage(site.id),
                    title: Text(site.name),
                    onTap: () {
                      selectedSite.value = site.id;
                      filter();
                      Navigator.pop(curContext);
                    },
                    selected: site.id == selectedSite.value,
                  );
                })
              ],
            ),
          ),
    );
  }
}
