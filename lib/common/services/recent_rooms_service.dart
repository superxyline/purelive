import 'dart:async';

import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/consts/app_consts.dart';
import 'package:pure_live/routes/app_navigation.dart';

/// 桌面长按图标快捷方式（最多 3 个）：**累计观看时长最长的 3 位主播**。
///
/// 数据来自 [WatchStatsService]（按房间累计观看秒数），启动时与每次观看
/// 结算后刷新快捷方式。桌面点击快捷方式（冷启动经 `getPendingShortcut`，
/// 热启动经 `onShortcut` 通道回调）后，等路由就绪再进入对应直播间。
class RecentRoomsService extends GetxService {
  static const int maxRooms = 3;
  static const String _channelName = 'pure_live/app_shortcuts';

  final RxList<LiveRoom> rooms = <LiveRoom>[].obs;
  MethodChannel? _channel;
  Timer? _pendingNavigationTimer;

  static RecentRoomsService? _instance;
  static RecentRoomsService get instance => _instance!;

  @override
  void onInit() {
    super.onInit();
    _instance = this;
    _channel = const MethodChannel(_channelName);
    _channel?.setMethodCallHandler(_onNativeCall);
    if (Get.isRegistered<WatchStatsService>()) {
      WatchStatsService.instance.onStatsCommitted = _refreshFromWatchStats;
    }
    _refreshFromWatchStats();
    _handlePendingShortcut();
  }

  @override
  void onClose() {
    _pendingNavigationTimer?.cancel();
    super.onClose();
  }

  /// 从观看统计重建快捷方式列表：按累计观看时长降序取前 3 位主播。
  void _refreshFromWatchStats() {
    try {
      final entries = Get.isRegistered<WatchStatsService>()
          ? WatchStatsService.instance.sortedEntries().take(maxRooms)
          : const <MapEntry<String, Map<String, dynamic>>>[];
      final list = entries
          .map((entry) {
            final value = entry.value;
            return LiveRoom(
              platform: ((value['platform'] as String?) ?? '').trim(),
              roomId: ((value['roomId'] as String?) ?? '').trim(),
              nick: (value['nick'] as String?) ?? '',
            );
          })
          .where((room) => (room.platform?.isNotEmpty == true) && (room.roomId?.isNotEmpty == true))
          .toList();
      rooms.assignAll(list);
    } catch (_) {
      // 统计数据异常时保留现有列表，后续结算会再刷新
    }
    _syncShortcuts();
  }

  LiveRoom? _findByType(String type) {
    final parts = type.split('|');
    if (parts.length != 2) return null;
    for (final room in rooms) {
      if (room.platform == parts[0] && room.roomId == parts[1]) return room;
    }
    return null;
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method == 'onShortcut' && call.arguments is String) {
      _navigateByType(call.arguments as String);
    }
    return null;
  }

  Future<void> _handlePendingShortcut() async {
    // 冷启动时 Flutter 通道未必立刻可用，稍作延迟并重试
    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        final pending = await _channel?.invokeMethod<String>('getPendingShortcut');
        if (pending != null && pending.isNotEmpty) {
          _navigateByType(pending);
        }
        return;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 400));
      }
    }
  }

  void _navigateByType(String type) {
    // 热门快捷方式（manifest 静态定义，值为 popular）：回首页切"热门"页签
    if (type == 'popular') {
      unawaited(_navigateToPopular());
      return;
    }
    // 赛事中心（桌面小组件赛事行复用该值）
    if (type == 'esports') {
      _navigateWhenReady(null);
      return;
    }
    // 最近观看快捷方式命中才带完整信息（头像/标题），未命中（如桌面小组件
    // 点击的任意关注直播间）用 platform|roomId 构造轻量房间直接进详情页，
    // 详情由直播间页自身加载。
    final room = _findByType(type) ?? _roomFromType(type);
    if (room == null) return;
    _navigateWhenReady(room);
  }

  /// 从 "platform|roomId" 构造最小可导航的房间对象。
  LiveRoom? _roomFromType(String type) {
    final parts = type.split('|');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) return null;
    return LiveRoom(platform: parts[0], roomId: parts[1], nick: '');
  }

  /// 热门快捷方式：回到首页根路由并切到"热门直播间"页签。
  ///
  /// 就绪判定与 [_navigateWhenReady] 一致（冷启动等 splash → offAllNamed 完成）；
  /// 额外延迟一小段时间再设页签，避免与首页 initState 的 _syncInitialIndex
  /// （按用户菜单配置初始化页签）竞态。用户菜单里没有"热门"时回退到第一个页签。
  Future<void> _navigateToPopular([int attempt = 0]) async {
    final currentRoute = Get.currentRoute;
    if (currentRoute.isEmpty || currentRoute == RoutePath.kSplash) {
      if (attempt >= 20) return;
      _pendingNavigationTimer?.cancel();
      _pendingNavigationTimer = Timer(const Duration(milliseconds: 500), () {
        _navigateToPopular(attempt + 1);
      });
      return;
    }
    try {
      if (currentRoute != RoutePath.kInitial) {
        // 一路弹回首页根路由（route.isFirst 在该 Get 版本下类型解析异常，
        // 用字符串比较等价实现）
        Get.until((_) => Get.currentRoute == RoutePath.kInitial);
      }
      await Future.delayed(const Duration(milliseconds: 700));
      if (Get.isRegistered<FavoriteController>()) {
        final activeIds = SettingsService.to.app.savedMenuIds.v;
        var target = HomeMenu.popular;
        if (activeIds.isNotEmpty && !activeIds.contains(target.id)) {
          target = HomeMenu.fromId(activeIds.first) ?? target;
        }
        Get.find<FavoriteController>().tabBottomIndex.value = target.index;
      }
    } catch (_) {
      if (attempt < 20) {
        _pendingNavigationTimer?.cancel();
        _pendingNavigationTimer = Timer(const Duration(milliseconds: 500), () {
          _navigateToPopular(attempt + 1);
        });
      }
    }
  }

  /// 冷启动时首页/路由可能尚未挂载，导航失败则延迟重试。
  /// 另需等待启动页跳转完成：冷启动流程为 kSplash → offAllNamed(首页)，
  /// 在 splash 期间推入的路由会被 offAllNamed 整个冲掉（表现为落到首页列表）。
  Future<void> _navigateWhenReady(LiveRoom? room, [int attempt = 0]) async {
    final currentRoute = Get.currentRoute;
    if (currentRoute.isEmpty || currentRoute == RoutePath.kSplash) {
      if (attempt >= 20) return;
      _pendingNavigationTimer?.cancel();
      _pendingNavigationTimer = Timer(const Duration(milliseconds: 500), () {
        _navigateWhenReady(room, attempt + 1);
      });
      return;
    }
    try {
      if (room == null) {
        await Get.toNamed(RoutePath.kEsports);
        // 启动竞态兜底：若冷启动的 offAllNamed(首页) 恰在本次导航前后才完成，
        // 赛事页会被整个冲掉（表现为落在首页）。稍候校验，被冲掉则重推一次。
        await Future.delayed(const Duration(milliseconds: 900));
        if (Get.currentRoute != RoutePath.kEsports && attempt < 20) {
          _pendingNavigationTimer?.cancel();
          _pendingNavigationTimer = Timer(const Duration(milliseconds: 300), () {
            _navigateWhenReady(room, attempt + 1);
          });
          return;
        }
      } else {
        await AppNavigator.toLiveRoomDetail(liveRoom: room);
      }
    } catch (_) {
      if (attempt < 20) {
        _pendingNavigationTimer?.cancel();
        _pendingNavigationTimer = Timer(const Duration(milliseconds: 500), () {
          _navigateWhenReady(room, attempt + 1);
        });
      }
    }
  }

  Future<void> _syncShortcuts() async {
    try {
      final items = rooms
          .map((room) => {
                'id': '${room.platform}|${room.roomId}',
                'label': (room.nick?.isNotEmpty == true ? room.nick : room.title) ?? '',
              })
          .toList();
      await _channel?.invokeMethod('setShortcuts', {'items': items});
    } catch (_) {
      // 原生侧未就绪（如启动极早期）时忽略，下次刷新会再同步
    }
  }
}
