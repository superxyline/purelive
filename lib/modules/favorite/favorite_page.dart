import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/widgets/keep_alive_wrapper.dart';
import 'package:pure_live/common/widgets/settings/settings_list_item.dart';
import 'package:pure_live/core/common/core_log.dart';
import 'package:pure_live/modules/util/site_logo_widget.dart';

class FavoritePage extends GetView<FavoriteController> {
  const FavoritePage({super.key});

  @override
  Widget build(BuildContext context) {
    return KeepAliveWrapper(child: LayoutBuilder(builder: (context, constraint) {
      bool showAction = Get.width <= 680;
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          scrolledUnderElevation: 0,
          leading: showAction ? const MenuButton() : null,
          actions: showAction
              ? [
                  PopupMenuButton(
                    tooltip: S.current.search,
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
                        PopupMenuItem(
                          value: 0,
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: MenuListTile(
                            leading: Icon(CustomIcons.search),
                            text: S.current.live_room_search,
                          ),
                        ),
                        PopupMenuItem(
                          value: 1,
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: MenuListTile(
                            leading: Icon(Icons.link),
                            text: S.current.live_room_link_access,
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
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            labelPadding: const EdgeInsets.symmetric(horizontal: 12),
            indicatorSize: TabBarIndicatorSize.label,
            tabs: [
              Tab(text: S.current.online_room_title),
              Tab(text: S.current.offline_room_title),
            ],
          ),
        ),
        body: TabBarView(
          controller: controller.tabController,
          children: [
            KeepAliveWrapper(
              child: _RoomGridView(FavoriteController.onlineRoomsIndex),
            ),
            KeepAliveWrapper(child: _RoomGridView(FavoriteController.offlineRoomsIndex)),
          ],
        ),
      );
    }));
  }
}

class _RoomGridView extends GetView<FavoriteController> {
  _RoomGridView(this.selectIndex) {
    // sourceRxList.listen((onData) {
    //   // CoreLog.d("sourceRxList change ... ${sourceRxList.hashCode} \n ${StackTrace.current.toString()}");
    //   CoreLog.d("sourceRxList change ... ${sourceRxList.hashCode} ");
    //   initSiteSet(onData);
    //   filter();
    // });
  }

  final int selectIndex;

  final refreshController = EasyRefreshController(
    controlFinishRefresh: true,
    controlFinishLoad: true,
  );
  final dense = Get.find<SettingsService>().enableDenseFavorites.value;

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
      int crossAxisCount = width > 1280 ? 4 : (width > 960 ? 3 : (width > 640 ? 2 : 1));
      if (dense) {
        crossAxisCount = width > 1280 ? 5 : (width > 960 ? 4 : (width > 640 ? 3 : 2));
      }
      return EasyRefresh(
        controller: refreshController,
        onRefresh: onRefresh,
        onLoad: () {
          refreshController.finishLoad(IndicatorResult.none);
        },
        child: () {
          // CoreLog.d("rebuild dataList");
          // CoreLog.d("dataList \n ${jsonEncode(dataList.value)}");
          return Obx(() => controller.filterDataList[selectIndex].isNotEmpty
              ? Scaffold(
                  body: () {
                    CoreLog.d("MasonryGridView.count change ");
                    return MasonryGridView.count(
                      cacheExtent: 3500,
                      padding: const EdgeInsets.all(5),
                      controller: ScrollController(),
                      crossAxisCount: crossAxisCount,
                      itemCount: controller.filterDataList[selectIndex].length,
                      itemBuilder: (context, index) => RoomCard(
                        room: controller.filterDataList[selectIndex][index],
                        dense: dense,
                      ),
                    );
                  }(),

                  // 浮动按钮
                  floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
                  floatingActionButton: FloatingActionButton(
                      key: UniqueKey(),
                      onPressed: () {
                        showFilter();
                      },
                      child: const Icon(Icons.local_offer)))
              : EmptyView(
                  icon: Icons.favorite_rounded,
                  title: S.current.empty_favorite_online_title,
                  subtitle: S.current.empty_favorite_online_subtitle,
                  boxConstraints: constraint,
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
      builder: (_) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(Get.context!).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...controller.siteSetList[selectIndex].map((siteId) {
              var site = Sites.allLiveSite;
              if (siteId != Sites.allSite) {
                site = Sites.of(siteId);
              }
              return SettingsListItem(
                leading: SiteWidget.getSiteLogeImage(site.id),
                title: Text(Sites.getSiteName(site.id)),
                onTap: () {
                  var curSiteId = controller.selectedSiteList[selectIndex];
                  if (curSiteId != site.id) {
                    controller.selectedSiteList[selectIndex] = site.id;
                    controller.filterDate(selectIndex);
                  }
                  Navigator.pop(curContext);
                },
                selected: site.id == controller.selectedSiteList[selectIndex],
              );
            }),
          ],
        ),
      ),
    );
  }
}
