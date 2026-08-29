import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';
import 'package:pure_live/routes/app_navigation.dart';

/// 最近打开的直播间：桌面长按图标快捷方式（最多 3 个）。
///
/// 进入直播间时调用 [record] 记录并实时更新快捷方式；桌面点击快捷方式
/// （冷启动经 `getPendingShortcut`，热启动经 `onShortcut` 通道回调）后，
/// 等路由就绪再进入对应直播间。
class RecentRoomsService extends GetxService {
  static const int maxRooms = 3;
  static const String _storageKey = 'recentOpenRooms';
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
    _loadFromStorage();
    _channel = const MethodChannel(_channelName);
    _channel?.setMethodCallHandler(_onNativeCall);
    _syncShortcuts();
    _handlePendingShortcut();
  }

  @override
  void onClose() {
    _pendingNavigationTimer?.cancel();
    super.onClose();
  }

  void _loadFromStorage() {
    try {
      final raw = HivePrefUtil.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List? ?? const [])
          .map((item) => LiveRoom.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
      rooms.assignAll(list);
    } catch (_) {
      // 存量数据损坏时静默忽略，后续 record 会重建
    }
  }

  /// 进入直播间时记录：最新在前、按 platform+roomId 去重、超限裁剪。
  void record(LiveRoom room) {
    final platform = room.platform?.trim() ?? '';
    final roomId = room.roomId?.trim() ?? '';
    if (platform.isEmpty || roomId.isEmpty) return;
    rooms.removeWhere((e) => e.platform == platform && e.roomId == roomId);
    rooms.insert(0, room);
    while (rooms.length > maxRooms) {
      rooms.removeLast();
    }
    try {
      HivePrefUtil.setString(_storageKey, jsonEncode(rooms.map((e) => e.toJson()).toList()));
    } catch (_) {}
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
    // 赛事中心快捷方式（manifest 静态定义，值为 esports）
    if (type == 'esports') {
      _navigateWhenReady(null);
      return;
    }
    final room = _findByType(type);
    if (room == null) return;
    _navigateWhenReady(room);
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
      // 原生侧未就绪（如启动极早期）时忽略，下次 record 会再同步
    }
  }
}
