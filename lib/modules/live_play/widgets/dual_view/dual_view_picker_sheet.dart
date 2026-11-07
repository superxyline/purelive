import 'package:cached_network_image/cached_network_image.dart';
import 'package:pure_live/common/index.dart';

/// 双开"选择副直播间"面板（底部抽屉）。
///
/// 提供"收藏 / 搜索"两个标签：收藏直接挑一个已收藏的主播，
/// 搜索支持按平台搜索直播间。选中后通过 [onPicked] 回调交给副窗口。
class DualViewPickerSheet extends StatefulWidget {
  const DualViewPickerSheet({super.key, required this.onPicked, this.title});

  final ValueChanged<LiveRoom> onPicked;

  /// 自定义标题；为空时用双开的默认标题（副音轨复用同一面板）
  final String? title;

  @override
  State<DualViewPickerSheet> createState() => _DualViewPickerSheetState();
}

class _DualViewPickerSheetState extends State<DualViewPickerSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );

  String _platform = Sites().availableSites().first.id;
  final TextEditingController _searchCtrl = TextEditingController();
  final _searching = false.obs;
  final _results = <LiveRoom>[].obs;

  /// 收藏 tab 的开播状态刷新：打开面板时先按缓存展示，
  /// 后台并发拉一遍 getLiveStatus，让已开播的房间顶到前面。
  final _statusRefreshing = false.obs;
  bool _statusRefreshed = false;

  /// 状态快通道并发度/超时，与关注页 [FavoriteController] 保持一致。
  static const int _statusBatchSize = 12;
  static const Duration _statusTimeout = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _refreshLiveStatusOnce();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// 只拉"是否开播"并写回收藏缓存（复用关注页的并发 worker 模式），
  /// 排序交给 [_sortedFavoriteRooms]，列表随 Rx 更新自动重排。
  Future<void> _refreshLiveStatusOnce() async {
    if (_statusRefreshed) return;
    _statusRefreshed = true;
    final rooms = SettingsService.to.fav.favoriteRooms.v
        .where((r) => (r.platform?.isNotEmpty ?? false) && r.roomId != null)
        .toList();
    if (rooms.isEmpty) return;

    _statusRefreshing.value = true;
    final persistedRooms = List<LiveRoom>.from(SettingsService.to.fav.favoriteRooms.v);
    var dirty = false;

    void flush({bool force = false}) {
      if (!dirty && !force) return;
      dirty = false;
      SettingsService.to.fav.favoriteRooms.v = List<LiveRoom>.from(persistedRooms);
    }

    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= rooms.length) return;
        final room = rooms[i];
        final bool isLive;
        try {
          isLive = await Sites.of(room.platform!)
              .liveSite
              .getLiveStatus(platform: room.platform!, roomId: room.roomId!)
              .timeout(_statusTimeout);
        } catch (_) {
          continue;
        }
        final idx = persistedRooms.indexWhere(
          (e) => e.roomId == room.roomId && e.platform == room.platform,
        );
        if (idx == -1) continue;
        final target = persistedRooms[idx];
        final nextStatus = isLive ? LiveStatus.live : LiveStatus.offline;
        if (target.liveStatus == nextStatus) continue;
        target.liveStatus = nextStatus;
        target.status = isLive;
        dirty = true;
        flush();
      }
    }

    try {
      await Future.wait(List.generate(_statusBatchSize, (_) => worker()));
    } finally {
      flush(force: true);
      _statusRefreshing.value = false;
    }
  }

  /// 已开播在前，组内按热度降序；未开播的保持收藏顺序。
  List<LiveRoom> _sortedFavoriteRooms() {
    final app = SettingsService.to.app;
    final rooms = List<LiveRoom>.from(SettingsService.to.fav.favoriteRooms.v);
    rooms.sort((a, b) {
      final la = a.liveStatus == LiveStatus.live && a.status == true ? 1 : 0;
      final lb = b.liveStatus == LiveStatus.live && b.status == true ? 1 : 0;
      if (la != lb) return lb.compareTo(la);
      if (la == 0) return 0;
      return b.audienceSortValue(
        preferRealOnline: app.preferRealOnlineCounts.v,
        platformEnabled: app.isRealOnlineEnabledFor(b.platform),
      ) - a.audienceSortValue(
        preferRealOnline: app.preferRealOnlineCounts.v,
        platformEnabled: app.isRealOnlineEnabledFor(a.platform),
      );
    });
    return rooms;
  }

  Future<void> _doSearch() async {
    final keyword = _searchCtrl.text.trim();
    if (keyword.isEmpty) return;
    _searching.value = true;
    try {
      final list = await Sites.of(_platform).liveSite.searchRooms(keyword);
      _results.value = list;
    } catch (_) {
      _results.value = [];
    } finally {
      _searching.value = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title ?? i18n("dual_view_select_title"),
                    style: AppTextStyles.t16.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabController,
            tabs: [
              Tab(text: i18n("dual_view_tab_favorite")),
              Tab(text: i18n("dual_view_tab_search")),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildFavoriteTab(theme), _buildSearchTab(theme)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFavoriteTab(ThemeData theme) {
    return Obx(() {
      final rooms = _sortedFavoriteRooms();
      if (rooms.isEmpty) {
        return AppStatusView(
          type: AppStatusType.empty,
          icon: Icons.favorite_border_rounded,
          title: i18n("dual_view_tab_favorite"),
          subtitle: '',
        );
      }
      return Column(
        children: [
          // 开播状态刷新提示：刷新完成后自动消失，不阻塞浏览。
          Obx(() {
            if (!_statusRefreshing.value) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    i18n("refresh_refreshing"),
                    style: AppTextStyles.t12.copyWith(color: theme.hintColor),
                  ),
                ],
              ),
            );
          }),
          Expanded(
            child: ListView.separated(
              itemCount: rooms.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 68),
              itemBuilder: (context, index) {
                final room = rooms[index];
                return _RoomTile(room: room, onTap: () => widget.onPicked(room));
              },
            ),
          ),
        ],
      );
    });
  }

  Widget _buildSearchTab(ThemeData theme) {
    final sites = Sites().availableSites();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: sites
                  .map(
                    (site) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(site.name),
                        selected: _platform == site.id,
                        onSelected: (_) => setState(() => _platform = site.id),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: TextField(
            controller: _searchCtrl,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _doSearch(),
            decoration: InputDecoration(
              hintText: i18n("dual_view_search_hint"),
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: IconButton(
                icon: const Icon(Icons.arrow_forward, size: 20),
                onPressed: _doSearch,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        Expanded(
          child: Obx(() {
            if (_searching.value) {
              return const Center(child: CircularProgressIndicator());
            }
            if (_results.isEmpty) {
              return AppStatusView(
                type: AppStatusType.empty,
                icon: Icons.search_off_rounded,
                title: i18n("dual_view_search_empty"),
                subtitle: '',
              );
            }
            return ListView.separated(
              itemCount: _results.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 68),
              itemBuilder: (context, index) {
                final room = _results[index];
                return _RoomTile(
                  room: room,
                  onTap: () => widget.onPicked(room),
                );
              },
            );
          }),
        ),
      ],
    );
  }
}

/// 直播间列表项（头像 + 昵称 + 标题 + 平台/状态）
class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.room, required this.onTap});

  final LiveRoom room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final live = room.liveStatus == LiveStatus.live && room.status == true;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        radius: 24,
        foregroundImage: room.avatar != null && room.avatar!.isNotEmpty
            ? CachedNetworkImageProvider(room.avatar!)
            : null,
        backgroundColor: Theme.of(context).disabledColor,
      ),
      title: Text(
        room.nick ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.t15,
      ),
      subtitle: Text(
        room.title ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.t12,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(room.platform?.toUpperCase() ?? '', style: AppTextStyles.t11),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: live ? const Color(0xFFE53935) : Colors.grey,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                live ? i18n("online_room_title") : i18n("offline_room_title"),
                style: AppTextStyles.t11.copyWith(
                  color: live ? const Color(0xFFE53935) : Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
