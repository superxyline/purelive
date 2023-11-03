import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/search/search_list_controller.dart';
import 'package:pure_live/plugins/cache_network.dart';
import 'package:pure_live/routes/app_navigation.dart';

class SearchListView extends StatelessWidget {
  final String tag;

  const SearchListView(this.tag, {Key? key}) : super(key: key);

  SearchListController get controller =>
      Get.find<SearchListController>(tag: tag);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraint) {
      final width = constraint.maxWidth;
      final crossAxisCount =
          width > 1280 ? 4 : (width > 960 ? 3 : (width > 640 ? 2 : 1));
      return Obx(() => EasyRefresh(
            controller: controller.easyRefreshController,
            onRefresh: controller.refreshData,
            onLoad: controller.loadData,
            child: controller.list.isNotEmpty
                ? MasonryGridView.count(
                    padding: const EdgeInsets.all(8),
                    physics: const BouncingScrollPhysics(),
                    controller: controller.scrollController,
                    crossAxisCount: crossAxisCount,
                    itemCount: controller.list.length,
                    itemBuilder: (context, index) {
                      final room = controller.list[index];
                      return OwnerCard(room: room);
                    })
                : EmptyView(
                    icon: Icons.live_tv_rounded,
                    title: S.of(context).empty_search_title,
                    subtitle: S.of(context).empty_search_subtitle,
                  ),
          ));
    });
  }
}

class OwnerCard extends StatefulWidget {
  const OwnerCard({Key? key, required this.room}) : super(key: key);

  final LiveRoom room;

  @override
  State<OwnerCard> createState() => _OwnerCardState();
}

class _OwnerCardState extends State<OwnerCard> {
  SettingsService settings = Get.find<SettingsService>();

  void _onTap(BuildContext context) async {
    AppNavigator.toLiveRoomDetail(liveRoom: widget.room);
  }

  late bool isFavorite = settings.isFavorite(widget.room);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: () => _onTap(context),
        leading:
          CacheNetWorkUtils.getCacheImage(widget.room.avatar!,errorWidget: const Center(
                                child: Icon(
                                  Icons.live_tv_rounded,
                                  size: 20,
                                ),
                              ),radius: 20),
        title: Text(
          widget.room.nick!,
          maxLines: 1,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          widget.room.area!.isEmpty
              ? "${widget.room.platform?.toUpperCase()}"
              : "${widget.room.platform?.toUpperCase()} - ${widget.room.area}",
          maxLines: 1,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        trailing: FilledButton.tonal(
          onPressed: () {
            setState(() => isFavorite = !isFavorite);
            if (isFavorite) {
              settings.addRoom(widget.room);
            } else {
              settings.removeRoom(widget.room);
            }
          },
          style: isFavorite
              ? null
              : FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.surface),
          child: Text(
            isFavorite ? S.of(context).unfollow : S.of(context).follow,
          ),
        ),
      ),
    );
  }
}
