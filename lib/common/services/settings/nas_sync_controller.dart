import 'dart:async';
import 'dart:convert';

import 'package:pure_live/get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/common/services/utils/hive_rx.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/plugins/event_bus.dart';
import 'package:pure_live/common/services/settings/favorite_room_controller.dart';

/// NAS Web 服务常连同步：
/// - 存 NAS 地址（扫码/手输一次，长期有效）
/// - 关注列表与 NAS 的 `synced-follows.json` 做并集（拉取只加不删，推送全量覆盖）
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

  /// 把本地关注全量推到 NAS（覆盖写；推之前先做过并集拉取则不会丢 NAS 独有项）
  Future<bool> push() async {
    final addr = baseUrl;
    if (addr.isEmpty) return false;
    final fav = Get.find<FavoriteRoomController>();
    final list = fav.favoriteRooms.v
        .map((r) => {
              'platform': r.platform,
              'roomId': r.roomId,
              'nick': r.nick,
              'title': r.title,
              'cover': r.cover,
            })
        .toList();
    try {
      final resp = await HttpClient.instance.postJson(
        '$addr/api/sync/follows',
        data: {'list': list},
      );
      final body = resp is String ? jsonDecode(resp) : resp;
      return body['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// 从 NAS 拉取关注并入本地（只加不删），完成后把并集推回 NAS。
  /// 返回新增条数；失败返回 -1。
  Future<int> pullMerge() async {
    final addr = baseUrl;
    if (addr.isEmpty) return -1;
    final fav = Get.find<FavoriteRoomController>();
    List<dynamic> list;
    try {
      final resp = await HttpClient.instance.getJson('$addr/api/sync/follows');
      final body = resp is String ? jsonDecode(resp) : resp;
      list = (body['list'] as List?) ?? [];
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
    // 并集拉完推回：本机多出的关注补给 NAS
    await push();
    return added;
  }

  /// 一键同步：先拉并集再推回。
  Future<void> syncNow() async {
    if (baseUrl.isEmpty) {
      ToastUtil.show(i18n('nas_addr_invalid'));
      return;
    }
    final added = await pullMerge();
    if (added < 0) {
      ToastUtil.show(i18n('nas_sync_failed'));
    } else {
      ToastUtil.show('${i18n('nas_sync_done')}${added > 0 ? ' (+$added)' : ''}');
    }
  }
}
