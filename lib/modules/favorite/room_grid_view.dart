import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:pure_live/common/index.dart';

class RoomGridView extends GetView<FavoriteController> {
  const RoomGridView({
    super.key,
    required this.site,
    required this.isOnline,
    required this.scrollController,
    required this.displayList,
    this.hideBadges = false,
  });

  final String site;
  final bool isOnline;
  final ScrollController scrollController;
  final List<LiveRoom> displayList;
  final bool hideBadges;

  @override
  Widget build(BuildContext context) {
    final dense = SettingsService.to.app.enableDenseFavorites.v;

    return LayoutBuilder(
      builder: (context, constraint) {
        final width = constraint.maxWidth;
        int crossAxisCount = width > 1280 ? 4 : (width > 960 ? 3 : (width > 640 ? 2 : 1));
        if (dense) {
          crossAxisCount = width > 1280 ? 5 : (width > 960 ? 4 : (width > 640 ? 3 : 2));
        }

        // 标签筛选行已上移到 favorite_page 的固定布局（FavoriteTagBar），
        // 避免下拉刷新/上拉加载的浮动指示器与标签名重叠。
        return Align(
          alignment: Alignment.topCenter,
          child: Obx(() {
            final spacing = SettingsService.to.theme.crossAxisSpacing.v;
            final itemWidth = (width - 24 - spacing * (crossAxisCount - 1)) / crossAxisCount;
            return GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              controller: scrollController,
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
              itemCount: displayList.length,
              itemBuilder: (context, index) {
                final room = displayList[index];
                return RoomCard(
                  key: ValueKey('${room.platform}:${room.roomId}'),
                  room: room,
                  dense: dense,
                  hideBadges: hideBadges,
                  // 仅聚合页签（全部）需要平台名区分来源
                  showPlatformBadge: site == Sites.allSite,
                );
              },
            );
          }),
        );
      },
    );
  }
}
