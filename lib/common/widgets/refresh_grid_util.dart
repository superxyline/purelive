import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:get/get.dart';
import 'package:pure_live/common/base/base_controller.dart';
import 'package:pure_live/common/l10n/generated/l10n.dart';
import 'package:pure_live/common/widgets/room_card.dart';
import 'package:pure_live/common/widgets/status/app_loadding_widget.dart';

import 'empty_view.dart';

final class RefreshGridUtil {
  /// 每行多少个
  static int getCrossAxisCount(BoxConstraints constraint) {
    final width = constraint.maxWidth;
    final crossAxisCount = width > 1280 ? 5 : (width > 960 ? 4 : (width > 640 ? 3 : 2));
    return crossAxisCount;
  }

  static Widget buildRoomCard(BasePageController controller, {IndexedWidgetBuilder? itemBuilder}) {
    itemBuilder ??= (context, index) => RoomCard(room: controller.list[index], dense: true);
    return LayoutBuilder(
      builder: (context, constraint) {
        final crossAxisCount = getCrossAxisCount(constraint);
        return Obx(() => EasyRefresh(
            controller: controller.easyRefreshController,
            onRefresh: controller.refreshData,
            onLoad: controller.loadData,
            child: Stack(children: [
              controller.list.isNotEmpty
                  ? MasonryGridView.count(
                      /// 缓存数目， 减少卡顿
                      cacheExtent: 3500,

                      padding: const EdgeInsets.all(5),
                      controller: controller.scrollController,
                      crossAxisCount: crossAxisCount,
                      itemCount: controller.list.length,
                      itemBuilder: itemBuilder!,
                    )
                  : EmptyView(
                      icon: Icons.live_tv_rounded,
                      title: S.current.empty_live_title,
                      subtitle: S.current.empty_live_subtitle,
                      boxConstraints: constraint,
                    ),
              Visibility(
                visible: (controller.loadding.value),
                child: const AppLoaddingWidget(),
              ),
            ])));
      },
    );
  }
}
