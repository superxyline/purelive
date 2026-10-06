import 'dart:async';
import 'dart:convert';

import 'package:pure_live/get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/services/utils/hive_rx.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/plugins/event_bus.dart';
import 'package:pure_live/common/services/settings/favorite_room_controller.dart';
import 'package:pure_live/common/services/room_gift_block_service.dart';

/// NAS Web 服务常连同步：
/// - 存 NAS 地址（扫码/手输/局域网自动发现，一次长期有效）
/// - 关注列表与屏蔽三件套（弹幕关键词/屏蔽用户/按房间礼物屏蔽）与 NAS
///   `synced-follows.json` 同步：拉取只加不删，推送全量覆盖
/// - 关注变更后自动防抖推送到 NAS（Web 端关注页与本机共享同一份数据）
class NasSyncController extends GetxController {
  static NasSyncController get to => Get.find<NasSyncController>();

  /// NAS Web 地址，如 http://192.168.31.26:8090
  final RxString serverAddress = hiveString('nasServerAddress', '');

  /// 关注变更后自动推送
  final RxBool autoPush = hiveBool('nasAutoPush', true);

  StreamSubscription<dynamic>? _eventSub;
  Timer? _pushTimer;

  String get baseUrl {
    var a = serverAddress.v.trim();
    if (a.isEmpty) return '';
    if (!a.startsWith('http://') && !a.startsWith('https://')) a = 'http://$a';
    return a.replaceAll(RegExp(r'/+$'), '');
  }

  void saveAddress(String addr) {
    final normalized = addr.trim();
    serverAddress.v = normalized;
  }

  @override
  void onInit() {
    super.onInit();
    if (baseUrl.isEmpty) return;
    _eventSub = EventBus.instance.listen('refresh_favorite_rooms', (_) => _debouncedPush());
  }

  @override
  void onClose() {
    _eventSub?.cancel();
    _pushTimer?.cancel();
    super.onClose();
  }

  void _debouncedPush() {
    if (!autoPush.v || baseUrl.isEmpty) return;
    _pushTimer?.cancel();
    _pushTimer = Timer(const Duration(seconds: 3), () {
      push().catchError((_) => false);
    });
  }

  /// 本地关注列表序列化
  List<Map<String, dynamic>> _followsSnapshot() {
    final fav = Get.find<FavoriteRoomController>();
    return fav.favoriteRooms.v
        .map((r) => {
              'platform': r.platform,
              'roomId': r.roomId,
              'nick': r.nick,
              'title': r.title,
              'cover': r.cover,
            })
        .toList();
  }

  /// 本地屏蔽三件套序列化（关键词/屏蔽用户/按房间礼物屏蔽）
  Map<String, dynamic> _shieldsSnapshot() {
    final fav = Get.find<FavoriteRoomController>();
    return {
      'keywords': List<String>.from(fav.shieldList.v),
      'users': List<String>.from(fav.blockedDanmakuUsers.v),
      'giftBlocks': RoomGiftBlockService.instance.snapshot(),
    };
  }

  /// 把本地关注+屏蔽全量推到 NAS（覆盖写；推之前先做过并集拉取则不会丢 NAS 独有项）
  Future<bool> push() async {
    final addr = baseUrl;
    if (addr.isEmpty) return false;
    try {
      final resp = await HttpClient.instance.postJson(
        '$addr/api/sync/data',
        data: {'list': _followsSnapshot(), 'shields': _shieldsSnapshot()},
      );
      final body = resp is String ? jsonDecode(resp) : resp;
      return body['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// 从 NAS 拉取关注+屏蔽并入本地（只加不删）。
  /// [pushBack] 为 true 时拉完把并集推回 NAS（一键并集语义）。
  /// 返回新增关注条数；失败返回 -1。
  Future<int> pull({bool pushBack = false}) async {
    final addr = baseUrl;
    if (addr.isEmpty) return -1;
    final fav = Get.find<FavoriteRoomController>();
    List<dynamic> list;
    Map<String, dynamic>? shields;
    try {
      final resp = await HttpClient.instance.getJson('$addr/api/sync/data');
      final body = resp is String ? jsonDecode(resp) : resp;
      list = (body['list'] as List?) ?? [];
      shields = body['shields'] is Map ? Map<String, dynamic>.from(body['shields']) : null;
    } catch (_) {
      return -1;
    }
    var added = 0;
    for (final item in list) {
      if (item is! Map) continue;
      final platform = item['platform']?.toString() ?? '';
      final roomId = item['roomId']?.toString() ?? '';
      if (platform.isEmpty || roomId.isEmpty) continue;
      final exists = fav.favoriteRooms.v.any((r) => r.platform == platform && r.roomId == roomId);
      if (exists) continue;
      fav.addRoom(LiveRoom.fromJson({
        'platform': platform,
        'roomId': roomId,
        'nick': item['nick'] ?? '',
        'title': item['title'] ?? '',
        'cover': item['cover'] ?? '',
      }));
      added++;
    }
    // 屏蔽并集：关键词/屏蔽用户只加不删；按房间礼物屏蔽同 key 礼物名取并集
    if (shields != null) {
      final mergeList = (dynamic v) => (v as List?)
          ?.map((e) => e?.toString() ?? '')
          .where((s) => s.trim().isNotEmpty)
          .toList() ??
          <String>[];
      final kw = mergeList(shields['keywords']);
      for (final k in kw) {
        if (!fav.shieldList.v.contains(k)) fav.shieldList.v.add(k);
      }
      final users = mergeList(shields['users']);
      for (final u in users) {
        if (!fav.blockedDanmakuUsers.v.contains(u)) fav.blockedDanmakuUsers.v.add(u);
      }
      if (shields['giftBlocks'] is Map) {
        RoomGiftBlockService.instance.mergeUnion(
          (shields['giftBlocks'] as Map).map(
            (k, v) => MapEntry(k.toString(), (v as List? ?? []).map((e) => e.toString()).toList()),
          ),
        );
      }
    }
    if (pushBack) await push();
    return added;
  }

  /// 一键同步：先拉并集再推回（NAS↔本机双向补齐）。
  Future<void> syncNow() async {
    final added = await _syncDirection(() => pull(pushBack: true));
    if (added < 0) {
      ToastUtil.show(i18n('nas_sync_failed'));
    } else {
      ToastUtil.show('${i18n('nas_sync_done')}${added > 0 ? ' (+$added)' : ''}');
    }
  }

  /// 仅推送：本地覆盖 NAS（不动本地数据）。
  Future<void> pushNow() async {
    final ok = await _syncDirection(push);
    ToastUtil.show(ok >= 0 ? i18n('nas_push_done') : i18n('nas_sync_failed'));
  }

  /// 仅拉取：NAS 并集入本地，不回推 NAS。
  Future<void> pullNow() async {
    final added = await _syncDirection(() => pull());
    if (added < 0) {
      ToastUtil.show(i18n('nas_sync_failed'));
    } else {
      ToastUtil.show('${i18n('nas_pull_done')}${added > 0 ? ' (+$added)' : ''}');
    }
  }

  /// 方向动作公共前置：地址校验 + 事件计数转换（push 失败返回 -1）
  Future<int> _syncDirection(Future<dynamic> Function() action) async {
    if (baseUrl.isEmpty) {
      ToastUtil.show(i18n('nas_addr_invalid'));
      return -1;
    }
    final result = await action();
    if (result is bool) return result ? 0 : -1;
    if (result is int) return result;
    return -1;
  }
}
