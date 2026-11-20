import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:remixicon/remixicon.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/favorite/favorite_tag_bar.dart';
import 'package:pure_live/modules/favorite/room_grid_view.dart';
import 'package:pure_live/common/widgets/common_appbar_actions.dart';
import 'package:pure_live/modules/tags/tag_management_controller.dart';
import 'package:pure_live/modules/favorite/batch_actions_bar.dart';

class FavoritePage extends GetView<FavoriteController> {
  const FavoritePage({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraint) {
        return Obx(() {
          bool showAction = Get.width <= 680;
          final menuCount = SettingsService.to.app.savedMenuIds.v.length;
          final availableSitesList = Sites().availableSites(containsAll: true);

          if (controller.selectionMode.value) {
            return Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: controller.exitSelectionMode,
                ),
                title: Text(i18n('selected_count', args: {'n': '${controller.selectedKeys.length}'})),
                actions: [
                  IconButton(
                    tooltip: i18n('select_all'),
                    icon: const Icon(Icons.select_all_rounded),
                    onPressed: controller.selectAllVisible,
                  ),
                ],
              ),
              body: DefaultTabController(
                length: availableSitesList.length,
                child: Stack(
                  children: [
                    _FavoriteSiteTabs(controller: controller, availableSitesList: availableSitesList),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: MediaQuery.paddingOf(context).bottom + 16,
                      child: BatchActionsBar(controller: controller),
                    ),
                  ],
                ),
              ),
            );
          }

          return Scaffold(
            appBar: AppBar(
              centerTitle: true,
              leading: (showAction || menuCount <= 1) ? const MenuButton() : null,
              actions: [
                // 历史记录页签：批量管理与站点筛选无意义，换为清空历史入口
                if (controller.tabOnlineIndex.value == 3) ...[
                  IconButton(
                    tooltip: i18n('history_clear'),
                    icon: const Icon(Remix.delete_bin_line),
                    onPressed: () => _confirmClearHistory(context),
                  ),
                ] else ...[
                  IconButton(
                    tooltip: i18n('batch_manage'),
                    icon: const Icon(Remix.checkbox_multiple_line),
                    onPressed: controller.enterSelectionMode,
                  ),
                ],
                if (showAction) ...[const SizedBox(width: 4), CommonAppBarActions()],
              ],
              title: TabBar(
                controller: controller.tabController,
                isScrollable: true,
                tabs: [
                  Tab(text: i18n("online_room_title")),
                  Tab(text: i18n("offline_room_title")),
                  Tab(text: i18n("favorites_all")),
                  Tab(text: i18n("history_title")),
                ],
              ),
            ),
            body: controller.tabOnlineIndex.value == 3
                ? const _HistoryTabView()
                : DefaultTabController(
                    length: availableSitesList.length,
                    child: _FavoriteSiteTabs(controller: controller, availableSitesList: availableSitesList),
                  ),
          );
        });
      },
    );
  }

  /// 清空观看历史（历史页签 AppBar 入口，带确认）。
  void _confirmClearHistory(BuildContext context) {
    final theme = Theme.of(context);
    Get.dialog(
      AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(i18n('history_clear'), style: AppTextStyles.t16.copyWith(fontWeight: FontWeight.bold)),
        content: Text(
          i18n('history_clear_confirm'),
          style: AppTextStyles.t14.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text(i18n('cancel'), style: AppTextStyles.t14.copyWith(color: theme.colorScheme.secondary)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Get.back();
              controller.clearHistory();
            },
            child: Text(i18n('confirm'), style: AppTextStyles.t14.copyWith(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

/// 观看历史页签：跨平台聚合展示最近观看的直播间。
/// 数据源 [FavoriteController.historyRooms]，存储侧按 watchedAt 倒序维护；
/// 与收藏页签不同，这里没有站点页签/标签筛选，条数即历史上限（≤100），无需分页。
class _HistoryTabView extends GetView<FavoriteController> {
  const _HistoryTabView();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final rooms = controller.historyRooms;
      if (rooms.isEmpty) {
        return AppStatusView(
          type: AppStatusType.empty,
          icon: Remix.time_line,
          title: i18n('history_empty_title'),
          subtitle: i18n('history_empty_subtitle'),
        );
      }
      final dense = SettingsService.to.app.enableDenseFavorites.v;
      return LayoutBuilder(
        builder: (context, constraint) {
          final width = constraint.maxWidth;
          int crossAxisCount = width > 1280 ? 4 : (width > 960 ? 3 : (width > 640 ? 2 : 1));
          if (dense) {
            crossAxisCount = width > 1280 ? 5 : (width > 960 ? 4 : (width > 640 ? 3 : 2));
          }
          final spacing = SettingsService.to.theme.crossAxisSpacing.v;
          final itemWidth = (width - 24 - spacing * (crossAxisCount - 1)) / crossAxisCount;
          return GridView.builder(
            // 底部补上导航栏 inset：最后一个卡片要能滚出手势条区域
            padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.paddingOf(context).bottom),
            scrollCacheExtent: ScrollCacheExtent.pixels(width > 680 ? 960 : 480),
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: false,
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: spacing,
              mainAxisSpacing: SettingsService.to.theme.mainAxisSpacing.v,
              mainAxisExtent: itemWidth * 9 / 16 + (dense ? 72 : 84),
            ),
            itemCount: rooms.length,
            itemBuilder: (context, index) {
              final room = rooms[index];
              return RoomCard(
                key: ValueKey('history:${room.platform}:${room.roomId}'),
                room: room,
                dense: dense,
                // 历史记录跨平台聚合，一律显示平台徽标区分来源
                showPlatformBadge: true,
              );
            },
          );
        },
      );
    });
  }
}

/// Keeps the inherited site [TabController] listener stable across Obx rebuilds.
///
/// Registering the listener inside `build` accumulated callbacks whenever a
/// room status changed, which made tab swipes and later refreshes progressively
/// more expensive on desktop.
class _FavoriteSiteTabs extends StatefulWidget {
  const _FavoriteSiteTabs({required this.controller, required this.availableSitesList});

  final FavoriteController controller;
  final List<Site> availableSitesList;

  @override
  State<_FavoriteSiteTabs> createState() => _FavoriteSiteTabsState();
}

class _FavoriteSiteTabsState extends State<_FavoriteSiteTabs> {
  TabController? _tabController;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextController = DefaultTabController.of(context);
    if (identical(nextController, _tabController)) return;
    _tabController?.removeListener(_handleTabChanged);
    _tabController = nextController..addListener(_handleTabChanged);
  }

  void _handleTabChanged() {
    final tabController = _tabController;
    if (tabController == null) return;
    // 点击标签：indexIsChanging=true 时 index 已是目标页，立即切换数据源，
    // 否则动画期间目标标签会显示上一个站点的旧内容，动画结束才刷新。
    if (tabController.indexIsChanging) {
      _applyTab(tabController.index);
      return;
    }
    // 滑动切换：拖动过程中 index 逐帧变化，落定后再切换数据源。
    _applyTab(tabController.index);
  }

  void _applyTab(int index) {
    final controller = widget.controller;
    if (controller.tabSiteIndex.value == index) return;
    controller.selectedTagId.value = TagManagementController.allTagKey;
    controller.tabSiteIndex.value = index;
    controller.currentPage = 1;
  }

  @override
  void dispose() {
    _tabController?.removeListener(_handleTabChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final availableSitesList = widget.availableSitesList;
    final tabController = _tabController ?? DefaultTabController.of(context);
    return Column(
      children: [
        TabBar(
          isScrollable: true,
          tabs: availableSitesList
              .asMap()
              .entries
              .map(
                (e) => Tab(
                  child: PlatformTab(
                    siteId: e.value.id,
                    label: e.value.name,
                    tabController: tabController,
                    index: e.key,
                  ),
                ),
              )
              .toList(),
        ),
        // 标签筛选行固定在滚动区之外：下拉刷新/上拉加载的浮动指示器不再与标签名重叠
        const FavoriteTagBar(),
        Expanded(
          child: BasePageView<FavoriteController, LiveRoom>(
            controller: controller,
            enableRefresh: true,
            enableLoadMore: true,
            emptyBuilder: (context) => AppStatusView(
              type: AppStatusType.empty,
              icon: Remix.heart_3_fill,
              title: i18n("empty_favorite_online_title"),
              subtitle: i18n("empty_favorite_online_subtitle"),
            ),
            showScrollToTopBtn: SettingsService.to.page.showScrollToTopBtn.v,
            showPageSizeSelector: SettingsService.to.page.showPageSizeSelector.v,
            pageSizeOptions: SettingsService.to.page.pageSizeOptions,
            contentBuilder: (context, list, scrollController) {
              return TabBarView(
                children: availableSitesList.map((e) {
                  return RoomGridView(
                    site: e.id,
                    isOnline: controller.tabOnlineIndex.value != 1,
                    scrollController: scrollController,
                    displayList: list,
                    hideBadges: controller.tabOnlineIndex.value == 2,
                  );
                }).toList(),
              );
            },
          ),
        ),
      ],
    );
  }
}
