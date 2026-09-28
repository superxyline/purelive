import 'dart:async';
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

  final onlineRooms = <LiveRoom>[].obs;
  final offlineRooms = <LiveRoom>[].obs;
  final allRooms = <LiveRoom>[].obs;
  final selectedTagId = TagManagementController.allTagKey.obs;
  final visibleTags = <LiveTag>[].obs;

  FavoriteController() : super();

  @override
  void onInit() {
    super.onInit();

    tabController = TabController(length: 3, vsync: this);

    debounce(SettingsService.to.fav.favoriteRooms, (_) => applyLocalFilter(), time: const Duration(milliseconds: 1000));

    ever(selectedTagId, (_) => applyLocalFilter());
    ever(tabSiteIndex, (_) => applyLocalFilter());
    ever(tabOnlineIndex, (_) => applyLocalFilter());
    ever(tagController.tags, (_) => applyLocalFilter());
    ever(tagController.roomTagsMap, (_) => applyLocalFilter());
    _audienceWorkers.add(ever(SettingsService.to.app.preferRealOnlineCounts, (_) => applyLocalFilter()));
    _audienceWorkers.add(ever(SettingsService.to.app.realOnlinePlatforms, (_) => applyLocalFilter()));

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
      if (selectedTagId.value == TagManagementController.allTagKey) {
        return _audienceSortValue(b).compareTo(_audienceSortValue(a));
      }
      int sa = _getRoomTagScore(a);
      int sb = _getRoomTagScore(b);
      if (sa != sb) return sb.compareTo(sa);
      return _audienceSortValue(b).compareTo(_audienceSortValue(a));
    });
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

    final persistedRooms = List<LiveRoom>.from(SettingsService.to.fav.favoriteRooms.v);
    var dirty = false;
    var lastPush = DateTime.now();

    // 结果节流推送：150ms 合并一次，避免每个房间都触发大列表排序/标签匹配。
    void flush({bool force = false}) {
      if (!dirty) return;
      final now = DateTime.now();
      if (!force && now.difference(lastPush) < const Duration(milliseconds: 150)) return;
      lastPush = now;
      dirty = false;
      SettingsService.to.fav.favoriteRooms.v = List<LiveRoom>.from(persistedRooms);
      applyLocalFilter();
    }

    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= valid.length) return;
        final room = valid[i];
        final bool isLive;
        try {
          isLive = await Sites.of(room.platform!)
              .liveSite
              .getLiveStatus(platform: room.platform!, roomId: room.roomId!)
              .timeout(_statusTimeout);
        } catch (_) {
          // 单个房间失败不影响其它：保留上一次状态继续下一个。
          continue;
        }
        final idx = persistedRooms.indexWhere(
          (e) => e.roomId == room.roomId && e.platform == room.platform,
        );
        if (idx == -1) continue;
        final target = persistedRooms[idx];
        final nextStatus = isLive ? LiveStatus.live : LiveStatus.offline;
        if (target.liveStatus == nextStatus) continue;
        // 只改开播状态，其它卡片字段维持缓存值，避免大列表闪烁。
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
    }
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

          final results = await Future.wait(futures);
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
