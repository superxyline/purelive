import 'package:remixicon/remixicon.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:pure_live/common/index.dart';

class PopularGridView extends StatefulWidget {
  final String tag;
  const PopularGridView(this.tag, {super.key});
  @override
  State<PopularGridView> createState() => _PopularGridViewState();
}

class _PopularGridViewState extends State<PopularGridView> with AutomaticKeepAliveClientMixin {
  BasePageScrollAndStateBone<LiveRoom> get controller =>
      Get.find<BasePageScrollAndStateBone<LiveRoom>>(tag: widget.tag);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return LayoutBuilder(
      builder: (context, constraint) {
        final width = constraint.maxWidth;
        final crossAxisCount = width > 1280 ? 5 : (width > 960 ? 4 : (width > 640 ? 3 : 2));
        return BasePageView<BasePageScrollAndStateBone<LiveRoom>, LiveRoom>(
          controller: controller,
          showScrollToTopBtn: SettingsService.to.page.showScrollToTopBtn.v,
          pageSizeOptions: SettingsService.to.page.pageSizeOptions,
          showPageSizeSelector: SettingsService.to.page.showPageSizeSelector.v,
          emptyBuilder: (c) => AppStatusView(
            type: AppStatusType.empty,
            icon: RemixIcons.fire_fill,
            title: i18n("empty_live_title"),
            subtitle: i18n("empty_live_subtitle"),
            buttonText: i18n('refresh'),
            onButtonPressed: () => controller.refreshData(),
          ),
          contentBuilder: (context, list, scrollController) {
            final spacing = SettingsService.to.theme.crossAxisSpacing.v;
            final itemWidth = (width - 12 - spacing * (crossAxisCount - 1)) / crossAxisCount;
            return GridView.builder(
              // 底部补上导航栏 inset：首页沉浸后手势条区域被列表覆盖，最后一个卡片要能滚出小白条
              padding: EdgeInsets.fromLTRB(6, 6, 6, 6 + MediaQuery.paddingOf(context).bottom),
              controller: scrollController,
              scrollCacheExtent: ScrollCacheExtent.pixels(width > 680 ? 960 : 480),
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: false,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: spacing,
                mainAxisSpacing: SettingsService.to.theme.mainAxisSpacing.v,
                mainAxisExtent: itemWidth * 9 / 16 + 72,
              ),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final room = list[index];
                return RoomCard(key: ValueKey('${room.platform}:${room.roomId}'), room: room, dense: true);
              },
            );
          },
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;
}
