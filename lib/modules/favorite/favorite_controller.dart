import 'dart:async';
import 'package:pure_live/core/common/core_log.dart';
import 'dart:developer' as developer;

import 'package:pure_live/common/index.dart';
import 'package:pure_live/plugins/event_bus.dart';
import 'package:pure_live/modules/tags/live_tag.dart';
import 'package:pure_live/modules/tags/tag_management_controller.dart';
import 'package:pure_live/common/services/settings/refresh_config_controller.dart';

class FavoriteController extends LocalReactivePageController<LiveRoom> with GetTickerProviderStateMixin {
  final TagManagementController tagController = Get.find<TagManagementController>();
  final RefreshConfigController refreshConfigController = Get.find<RefreshConfigController>();

  late TabController tabController;

  final tabBottomIndex = 0.obs;
  final tabSiteIndex = 0.obs;
  final tabOnlineIndex = 0.obs;
  StreamSubscription<dynamic>? subscription;
  StreamSubscription<dynamic>? roomChangedSubscription;

  StreamSubscription<dynamic>? _configSubscription;
  Timer? _autoRefreshTimer;
  Stopwatch? _refreshStopwatch;
  Timer? _debounceTimer;
  final List<Worker> _audienceWorkers = [];

  /// 是否进入过历史页签：离开时站点 TabBar 已重建，需要同步重置站点/标签选择
  bool _historyTabVisited = false;

  final onlineRooms = <LiveRoom>[].obs;
  final offlineRooms = <LiveRoom>[].obs;
  final allRooms = <LiveRoom>[].obs;
  // 观看历史（第 4 个页签）：按 watchedAt 倒序的最近观看直播间
  final historyRooms = <LiveRoom>[].obs;
  final selectedTagId = TagManagementController.allTagKey.obs;
  final visibleTags = <LiveTag>[].obs;

  // ===== 批量管理模式 =====
  /// 是否处于多选模式（进入后点击卡片=切换选中，长按菜单禁用）。
  final selectionMode = false.obs;

  /// 已选房间的 identityKey 集合。
  final selectedKeys = <String>[].obs;

  bool isSelected(LiveRoom room) => selectedKeys.contains(room.identityKey);

  void enterSelectionMode() {
    selectionMode.value = true;
    selectedKeys.clear();
  }

  void exitSelectionMode() {
    selectionMode.value = false;
    selectedKeys.clear();
  }

  void toggleSelection(LiveRoom room) {
    final key = room.identityKey;
    if (selectedKeys.contains(key)) {
      selectedKeys.remove(key);
    } else {
      selectedKeys.add(key);
    }
  }

  /// 按当前过滤结果全选/反选。
  void selectAllVisible() {
    final visible = getFilteredRooms();
    if (visible.every((r) => selectedKeys.contains(r.identityKey))) {
      for (final room in visible) {
        selectedKeys.remove(room.identityKey);
      }
    } else {
      for (final room in visible) {
        if (!selectedKeys.contains(room.identityKey)) selectedKeys.add(room.identityKey);
      }
    }
  }

  /// 批量移出已选房间。
  void batchRemoveSelected() {
    final keys = selectedKeys.toSet();
    final rooms = List<LiveRoom>.from(SettingsService.to.fav.favoriteRooms.v);
    rooms.removeWhere((r) => keys.contains(r.identityKey));
    SettingsService.to.fav.favoriteRooms.v = rooms;
    SmartDialog.showToast(i18n('batch_removed'));
    exitSelectionMode();
  }

  /// 批量设置备注（留空=清除）。
  void batchSetNote(String note) {
    final keys = selectedKeys.toSet();
    final rooms = List<LiveRoom>.from(SettingsService.to.fav.favoriteRooms.v);
    for (final r in rooms) {
      if (keys.contains(r.identityKey)) r.note = note;
    }
    SettingsService.to.fav.favoriteRooms.v = rooms;
    SmartDialog.showToast(i18n('note_saved'));
  }

  /// 批量合并标签（并集）。
  void batchAddTags(List<String> tagIds) {
    final keys = selectedKeys.toSet();
    final rooms = List<LiveRoom>.from(SettingsService.to.fav.favoriteRooms.v);
    for (final r in rooms) {
      if (!keys.contains(r.identityKey)) continue;
      final merged = List<String>.from(r.tagIds);
      for (final id in tagIds) {
        if (!merged.contains(id)) merged.add(id);
      }
      r.tagIds = merged;
    }
    SettingsService.to.fav.favoriteRooms.v = rooms;
    SmartDialog.showToast(i18n('batch_tags_applied'));
  }

  FavoriteController() : super();

  @override
  void onInit() {
    super.onInit();

    tabController = TabController(length: 4, vsync: this);

    debounce(SettingsService.to.fav.favoriteRooms, (_) => applyLocalFilter(), time: const Duration(milliseconds: 1000));

    ever(selectedTagId, (_) => applyLocalFilter());
    ever(tabSiteIndex, (_) => applyLocalFilter());
    ever(tabOnlineIndex, (_) => applyLocalFilter());
    ever(tagController.tags, (_) => applyLocalFilter());
    ever(tagController.roomTagsMap, (_) => applyLocalFilter());
    _audienceWorkers.add(ever(SettingsService.to.app.preferRealOnlineCounts, (_) => applyLocalFilter()));
    _audienceWorkers.add(ever(SettingsService.to.app.realOnlinePlatforms, (_) => applyLocalFilter()));
    // 观看历史：存储变化（记录/裁剪/清空）即同步到页签数据源
    _audienceWorkers.add(ever(SettingsService.to.fav.watchHistory, (_) => syncHistory()));
    syncHistory();
    // 置顶切换：立即重排并落到显示池
    _audienceWorkers.add(ever(SettingsService.to.fav.pinnedRooms, (_) {
      syncRooms();
      applyLocalFilter();
    }));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      applyLocalFilter();
      // 冷启动：列表先用缓存渲染，随后跑一次轻量的开播状态快通道，把在线房间
      // 尽快顶上来。不显示加载态、不阻塞界面，人气/时长角标等交给后续详情刷新。
      unawaited(_primeLiveStatusIfNeeded(getAllRooms()));
    });

    tabController.addListener(() {
      if (tabOnlineIndex.value != tabController.index) {
        tabOnlineIndex.value = tabController.index;
        if (Get.width > 680) {
          currentPage = 1;
        }
        // 历史页签没有站点/标签筛选（DefaultTabController 被移出渲染树），
        // 回到收藏页签时站点 TabBar 已重建为第一项，同步数据源索引，
        // 避免站点选中项与过滤数据不一致。
        if (tabController.index == 3) {
          _historyTabVisited = true;
        } else if (_historyTabVisited) {
          _historyTabVisited = false;
          tabSiteIndex.value = 0;
          selectedTagId.value = TagManagementController.allTagKey;
        }
        applyLocalFilter();
      }
    });

    _setupRefreshStrategy();
    _configSubscription = refreshConfigController.configChanges.listen((config) {
      _setupRefreshStrategy();
    });

    listenFavorite();
    listenRoomChanged();
  }

  void _setupRefreshStrategy() {
    _autoRefreshTimer?.cancel();
    final bool isEnabled = refreshConfigController.autoRefreshFavorite.value;
    final int interval = refreshConfigController.autoRefreshInterval.value;
    if (isEnabled && interval > 0) {
      _autoRefreshTimer = Timer.periodic(Duration(minutes: interval), (timer) => refreshData());
    }
  }

  void debounceRefresh() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _fullRefreshRooms();
    });
  }

  @override
  void onClose() {
    tabController.dispose();
    subscription?.cancel();
    roomChangedSubscription?.cancel();
    _configSubscription?.cancel();
    _autoRefreshTimer?.cancel();
    _debounceTimer?.cancel();
    for (final worker in _audienceWorkers) {
      worker.dispose();
    }
    super.onClose();
  }

  void listenFavorite() {
    subscription = EventBus.instance.listen('refresh_favorite_rooms', (data) {
      debounceRefresh();
    });
  }

  void listenRoomChanged() {
    roomChangedSubscription = EventBus.instance.listen('refresh_room_changed', (data) {
      syncRooms();
    });
  }

  void changeSelectedTag(String tagId) {
    selectedTagId.value = tagId;
    if (Get.width > 680) {
      currentPage = 1;
    }
    applyLocalFilter();
  }

  void updateRoomTags(LiveRoom room, List<String> newTagIds) {
    tagController.setRoomTags(room.identityKey, newTagIds, legacyRoomId: room.roomId.toString());
    applyLocalFilter();
  }

  List<LiveRoom> getAllRooms() {
    return List<LiveRoom>.from(SettingsService.to.fav.favoriteRooms.v);
  }

  bool _roomMatchesSelectedTag(LiveRoom room) {
    final tagId = selectedTagId.value;
    // 分区自动标签按 room.area 匹配（跨平台同分区归到同一标签，如斗鱼/虎牙的 CS2）
    final areaName = TagManagementController.areaNameFromTagId(tagId);
    if (areaName != null) {
      return room.area?.trim() == areaName;
    }
    return tagController.getTagsForRoom(room).contains(tagId);
  }

  List<LiveRoom> getFilteredRoomsIgnoringLiveStatus() {
    final List<LiveRoom> source = List<LiveRoom>.from(SettingsService.to.fav.favoriteRooms.v);

    final currentAvailableSites = Sites().availableSites(containsAll: true);
    if (tabSiteIndex.value < 0 || tabSiteIndex.value >= currentAvailableSites.length) {
      return [];
    }

    final activeSite = currentAvailableSites[tabSiteIndex.value];
    List<LiveRoom> siteFiltered = source;

    if (activeSite.id != Sites.allSite) {
      siteFiltered = source.where((room) {
        return room.platform?.toUpperCase() == activeSite.id.toUpperCase();
      }).toList();
    }

    if (selectedTagId.value == TagManagementController.allTagKey) {
      return siteFiltered;
    }

    return siteFiltered.where(_roomMatchesSelectedTag).toList();
  }

  List<LiveRoom> getFilteredRooms() {
    syncRooms();

    List<LiveRoom> source;

    switch (tabOnlineIndex.value) {
      case 0:
        source = onlineRooms;
        break;

      case 1:
        source = offlineRooms;
        break;

      case 2:
        source = allRooms;
        break;

      default:
        source = onlineRooms;
    }

    final currentAvailableSites = Sites().availableSites(containsAll: true);
    if (tabSiteIndex.value < 0 || tabSiteIndex.value >= currentAvailableSites.length) {
      return [];
    }

    final activeSite = currentAvailableSites[tabSiteIndex.value];
    List<LiveRoom> siteFiltered = source;

    if (activeSite.id != Sites.allSite) {
      siteFiltered = source.where((room) {
        return room.platform?.toUpperCase() == activeSite.id.toUpperCase();
      }).toList();
    }

    if (selectedTagId.value == TagManagementController.allTagKey) {
      return siteFiltered;
    }

    return siteFiltered.where(_roomMatchesSelectedTag).toList();
  }

  /// 同步观看历史页签数据源：存储本身按 watchedAt 倒序维护，直接拷贝展示。
  void syncHistory() {
    historyRooms.assignAll(SettingsService.to.fav.watchHistory.v);
  }

  /// 清空观看历史（带确认，由页面调用）。
  void clearHistory() {
    SettingsService.to.fav.clearWatchHistory();
  }

  void syncRooms() {
    onlineRooms.clear();
    offlineRooms.clear();
    allRooms.clear();

    final List<LiveRoom> roomsBase = List<LiveRoom>.from(SettingsService.to.fav.favoriteRooms.v);
    onlineRooms.addAll(roomsBase.where((r) => r.liveStatus == LiveStatus.live && r.isRecord == false));

    offlineRooms.addAll(roomsBase.where((r) => r.liveStatus != LiveStatus.live));

    allRooms.addAll(roomsBase);

    final currentAvailableSites = Sites().availableSites(containsAll: true);
    visibleTags.clear();

    if (tabSiteIndex.value >= 0 && tabSiteIndex.value < currentAvailableSites.length) {
      final activeSite = currentAvailableSites[tabSiteIndex.value];
      List<LiveRoom> target;

      switch (tabOnlineIndex.value) {
        case 0:
          target = onlineRooms;
          break;

        case 1:
          target = offlineRooms;
          break;

        case 2:
          target = allRooms;
          break;

        default:
          target = onlineRooms;
      }
      final Set<String> tagIds = {};
      final Set<String> areaNames = {};

      for (var room in target) {
        if (activeSite.id == Sites.allSite || room.platform?.toUpperCase() == activeSite.id.toUpperCase()) {
          tagIds.addAll(tagController.getTagsForRoom(room));
          final area = room.area?.trim() ?? '';
          if (area.isNotEmpty) areaNames.add(area);
        }
      }

      final tags = tagController.tags.where((t) => tagIds.contains(t.id)).toList();
      tags.sort((a, b) => a.order.compareTo(b.order));
      // 分区自动标签：来源于房间自身的 area 字段，动态生成不落盘，
      // 排在用户自定义标签之后，按名称排序。
      final areaTags = areaNames
          .map((name) => LiveTag(id: TagManagementController.areaTagId(name), name: name))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      visibleTags.assignAll(tags + areaTags);
    }

    onlineRooms.sort((a, b) {
      // 开播即置顶：置顶的直播间开播后恒排最前，置顶组内仍按原有排序
      final int pa = _pinnedSortValue(a);
      final int pb = _pinnedSortValue(b);
      if (pa != pb) return pb.compareTo(pa);
      if (selectedTagId.value == TagManagementController.allTagKey) {
        return _audienceSortValue(b).compareTo(_audienceSortValue(a));
      }
      int sa = _getRoomTagScore(a);
      int sb = _getRoomTagScore(b);
      if (sa != sb) return sb.compareTo(sa);
      return _audienceSortValue(b).compareTo(_audienceSortValue(a));
    });
    // 全部关注（已关注标签）：直播优先，其次按热度排序
    allRooms.sort((a, b) {
      int la = a.liveStatus == LiveStatus.live ? 1 : 0;
      int lb = b.liveStatus == LiveStatus.live ? 1 : 0;
      if (la != lb) return lb.compareTo(la);
      // 直播组内再置顶：置顶的直播间开播后排在其他开播直播间之前
      final int pa = _pinnedSortValue(a);
      final int pb = _pinnedSortValue(b);
      if (pa != pb) return pb.compareTo(pa);
      if (selectedTagId.value == TagManagementController.allTagKey) {
        return _audienceSortValue(b).compareTo(_audienceSortValue(a));
      }
      int sa = _getRoomTagScore(a);
      int sb = _getRoomTagScore(b);
      if (sa != sb) return sb.compareTo(sa);
      return _audienceSortValue(b).compareTo(_audienceSortValue(a));
    });
  }

  /// 开播即置顶的排序权重：置顶且开播=1，其余=0（未开播的置顶房间不置顶）。
  int _pinnedSortValue(LiveRoom room) {
    return (room.liveStatus == LiveStatus.live && SettingsService.to.fav.isPinned(room)) ? 1 : 0;
  }

  int _audienceSortValue(LiveRoom room) {
    final app = SettingsService.to.app;
    return room.audienceSortValue(
      preferRealOnline: app.preferRealOnlineCounts.v,
      platformEnabled: app.isRealOnlineEnabledFor(room.platform),
    );
  }

  int _getRoomTagScore(LiveRoom room) {
    final ids = tagController.getTagsForRoom(room);
    if (ids.isEmpty) return 0;

    int highest = 0;
    const maxScore = 1000000;

    for (var id in ids) {
      final idx = tagController.tags.indexWhere((t) => id == t.id);
      if (idx != -1) {
        final tag = tagController.tags[idx];
        final score = maxScore - tag.order * 100;
        if (score > highest) highest = score;
      }
    }
    return highest;
  }

  void applyLocalFilter() {
    final filtered = getFilteredRooms();
    updateLocalReactivePool(filtered);
  }

  @override
  Future<void> refreshData() async {
    currentPage = 1;
    // 冷启动/本次会话首次刷新：先出开播状态，再补角标详情。
    await _primeLiveStatusIfNeeded(getFilteredRoomsIgnoringLiveStatus());
    await _fullRefreshFilterRooms();
  }

  Future<void> _fullRefreshFilterRooms() async {
    loadding.value = true;
    List<LiveRoom> roomsToRefresh = getFilteredRoomsIgnoringLiveStatus();
    await _refreshRoomDetails(roomsToRefresh);
    applyLocalFilter();
    loadding.value = false;
    EventBus.instance.emit('refresh_favorite_finish', true);
  }

  Future<void> _fullRefreshRooms() async {
    loadding.value = true;
    List<LiveRoom> roomsToRefresh = getAllRooms();
    await _primeLiveStatusIfNeeded(roomsToRefresh);
    await _refreshRoomDetails(roomsToRefresh);
    applyLocalFilter();
    loadding.value = false;
    EventBus.instance.emit('refresh_favorite_finish', true);
  }

  /// 本次会话是否已跑过"状态优先"快通道。
  /// 只在冷启动/首次进入时打 getLiveStatus；后续下拉、双击、定时刷新直接走详情
  /// （详情本身也带回开播状态），避免每个房间被请求两次。
  bool _statusPrimed = false;

  /// 状态快通道并发度：只取开播状态，比详情便宜得多，可以开大。
  static const int _statusBatchSize = 12;

  /// 单个状态请求超时：个别平台卡住时不拖垮整批。
  static const Duration _statusTimeout = Duration(seconds: 5);

  /// 冷启动/首次刷新时先用轻量的开播状态接口把在线房间顶上来。
  Future<void> _primeLiveStatusIfNeeded(List<LiveRoom> rooms) async {
    if (_statusPrimed) return;
    _statusPrimed = true;
    await _refreshLiveStatusOnly(rooms);
  }

  /// 只拉"是否开播"，让在线房间立刻出现；人气、开播时长等角标交给后续详情刷新。
  ///
  /// 详情刷新每批只有 [refreshConfigController.maxConcurrentRefresh] 个、每 400ms
  /// 才推一次界面，房间一多用户看到的一直是上一次的旧状态。状态接口轻量得多，
  /// 先跑一遍就能先给出"谁在播"，卡片标题/封面/人气沿用缓存，不会闪成空白。
  ///
  /// 2026-09-26 起改为并发池流式：[_statusBatchSize] 个常驻 worker 竞争消费
  /// 房间队列，谁先返回谁先更新并推 UI——上一版按批串行、每批 await 整批
  /// （最慢者可拖到 5s 超时），关注一多要等好几轮，冷启动开播列表迟迟不全。
  Future<void> _refreshLiveStatusOnly(List<LiveRoom> rooms) async {
    final valid = rooms.where((r) => (r.platform?.isNotEmpty ?? false) && r.roomId != null).toList();
    if (valid.isEmpty) return;

    var dirty = false;
    var lastPush = DateTime.now();

    // 本轮产生的状态变更（identity → 新状态），flush 时合并进【最新】的收藏列表。
    // 旧实现直接持有列表快照整体覆盖写回，会与并行的详情刷新互相回滚对方刚
    // 写入的数据（卡片字段被旧对象替换回去），表现为列表偶发大面积异常。
    final statusUpdates = <String, LiveStatus>{};

    // 结果节流推送：150ms 合并一次，避免每个房间都触发大列表排序/标签匹配。
    void flush({bool force = false}) {
      if (!dirty) return;
      final now = DateTime.now();
      if (!force && now.difference(lastPush) < const Duration(milliseconds: 150)) return;
      lastPush = now;
      dirty = false;
      // 读最新列表，只把状态字段按房间合并进去——不回滚其他路径的并发写入。
      final latest = List<LiveRoom>.from(SettingsService.to.fav.favoriteRooms.v);
      var merged = false;
      statusUpdates.forEach((key, nextStatus) {
        final idx = latest.indexWhere((e) => e.identityKey == key);
        if (idx == -1) return;
        if (latest[idx].liveStatus != nextStatus) {
          latest[idx].liveStatus = nextStatus;
          latest[idx].status = nextStatus == LiveStatus.live;
          merged = true;
        }
      });
      statusUpdates.clear();
      if (!merged) return;
      SettingsService.to.fav.favoriteRooms.v = latest;
      applyLocalFilter();
    }

    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= valid.length) return;
        final room = valid[i];
        bool isLive;
        try {
          isLive = await Sites.of(room.platform!)
              .liveSite
              .getLiveStatus(platform: room.platform!, roomId: room.roomId!)
              .timeout(_statusTimeout);
        } catch (_) {
          // 单个房间失败：重试一次再放弃；仍失败则保留上一次状态继续下一个。
          try {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            isLive = await Sites.of(room.platform!)
                .liveSite
                .getLiveStatus(platform: room.platform!, roomId: room.roomId!)
                .timeout(_statusTimeout);
          } catch (_) {
            // 查询失败≠离线：保留上一次状态，只记日志供排查平台接口问题。
            CoreLog.w('fav-status failed: ${room.platform}/${room.roomId}');
            continue;
          }
        }
        _applyStatus(room, isLive ? LiveStatus.live : LiveStatus.offline, statusUpdates, () {
          dirty = true;
          flush();
        });
      }
    }

    try {
      await Future.wait(List.generate(_statusBatchSize, (_) => worker()));
    } finally {
      flush(force: true);
    }
  }

  /// 平台开播状态连续失败计数（诊断日志用：某个平台连续失败多次会列为嫌疑）。
  final _statusFailures = <String, int>{};

  void _applyStatus(LiveRoom room, LiveStatus nextStatus, Map<String, LiveStatus> updates, VoidCallback onDirty) {
    if (nextStatus == LiveStatus.offline) {
      // 误判下播的防线：一个之前在线的房间突然消失，多数是平台风控/接口降级
      // 返回了不可信的失败态。只有连续两次查询都得到离线才接受。
      final failCount = (_statusFailures[room.identityKey] ?? 0) + 1;
      _statusFailures[room.identityKey] = failCount;
      if (failCount < 2) return;
    } else {
      _statusFailures.remove(room.identityKey);
    }
    updates[room.identityKey] = nextStatus;
    onDirty();
  }

  /// 分批增量推到界面的最小间隔：既让卡片尽快更新，又避免大列表反复
  /// 触发排序/标签匹配而卡顿。
  static const Duration _progressivePushInterval = Duration(milliseconds: 400);

  /// 详情刷新是否正在进行：避免启动刷新与下拉/双击刷新叠加，重复打接口。
  bool _refreshingDetails = false;

  Future<void> _refreshRoomDetails(List<LiveRoom> rooms) async {
    if (_refreshingDetails) return;
    final valid = rooms.where((r) => r.platform?.isNotEmpty ?? false).toList();
    if (valid.isEmpty) return;

    _refreshingDetails = true;
    _refreshStopwatch = Stopwatch()..start();

    final int batch = refreshConfigController.maxConcurrentRefresh.value > 0
        ? refreshConfigController.maxConcurrentRefresh.value
        : 5;
    final persistedRooms = List<LiveRoom>.from(SettingsService.to.fav.favoriteRooms.v);
    var changed = false;
    var lastPush = DateTime.now();

    try {
      for (int i = 0; i < valid.length; i += batch) {
        final end = i + batch > valid.length ? valid.length : i + batch;
        final batchRooms = valid.sublist(i, end);

        try {
          final futures = batchRooms
              .map(
                (room) => Sites.of(room.platform!).liveSite.getRoomDetail(
                  roomId: room.roomId!,
                  platform: room.platform!,
                  // 列表只需要卡片字段：跳过弹幕发现/签名、粉丝抓取等
                  // 只有进房间才需要的请求，显著缩短批量刷新耗时。
                  light: true,
                ),
              )
              .toList();

          // 单个房间请求失败不能丢掉同批已成功的其它房间更新：
          // Future.wait 任一错误即整批抛出，catch 后批内结果全部丢弃，
          // 曾导致一次网络抖动让整批房间的卡片/状态停留在旧值。
          final results = <LiveRoom>[];
          for (final future in futures) {
            try {
              results.add(await future);
            } catch (_) {}
          }
          for (var updated in results) {
            final idx = persistedRooms.indexWhere(
              (e) => e.roomId == updated.roomId && e.platform == updated.platform,
            );
            if (idx == -1) continue;
            // 本次请求失败（平台返回空对象）时保留原卡片数据，不清空也不落盘，
            // 否则一次瞬时超时就会把标题/封面清掉并持久化。
            if (!updated.hasUsableCardData) continue;
            // 平台详情接口不认识本地标签；刷新时保留它们。整个刷新周期
            // 只提交一次 Hive，避免每个房间各写一份完整收藏列表。
            updated.tagIds = List<String>.from(persistedRooms[idx].tagIds);
            // 本地备注同理：平台详情不认识它，刷新时原样保留。
            updated.note = persistedRooms[idx].note;
            // 开播中的房间若本次刷新没取到开播时间（多为接口被风控降级），
            // 保留上一次的值，避免角标被静默清掉。
            if (updated.liveStartTime == null &&
                updated.liveStatus == LiveStatus.live &&
                persistedRooms[idx].liveStartTime != null) {
              updated.liveStartTime = persistedRooms[idx].liveStartTime;
            }
            persistedRooms[idx] = updated;
            changed = true;
          }
        } catch (e) {
          developer.log('Error refreshing room details: $e');
        }

        // 每批就绪后就把已有结果推给界面（按时间节流），不必等所有房间
        // 刷完——否则大列表下界面会长时间停留在上一次的旧状态。
        if (changed && DateTime.now().difference(lastPush) >= _progressivePushInterval) {
          lastPush = DateTime.now();
          // 必须传新列表实例：Rx 对同一个对象不判为变化，否则既不会通知
          // 界面也不会写盘。
          SettingsService.to.fav.favoriteRooms.v = List<LiveRoom>.from(persistedRooms);
          applyLocalFilter();
        }
      }

      if (changed) SettingsService.to.fav.favoriteRooms.v = List<LiveRoom>.from(persistedRooms);
    } finally {
      _refreshingDetails = false;
      _refreshStopwatch?.stop();
      _refreshStopwatch = null;
    }
  }
}
