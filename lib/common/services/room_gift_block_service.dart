import 'dart:convert';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';

/// 按直播间维度的礼物卡片屏蔽：被屏蔽的礼物名在该直播间内不再弹出
/// 全屏左下角卡片；弹幕列表中的礼物卡片不受影响。
///
/// 存储：单条 Hive key 存 `Map<platform|roomId, List<礼物名>>`，
/// key 设计与 [WatchStatsService] 一致，避免跨平台同房间号冲突。
class RoomGiftBlockService extends GetxService {
  static const String _storageKey = 'blockedGiftsByRoomV1';

  /// key（platform|roomId）→ 该房间被屏蔽的礼物名列表
  final RxMap<String, List<String>> blockedGifts = <String, List<String>>{}.obs;

  static RoomGiftBlockService? _instance;
  static RoomGiftBlockService get instance => _instance!;

  @override
  void onInit() {
    super.onInit();
    _instance = this;
    _load();
  }

  void _load() {
    try {
      final raw = HivePrefUtil.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      blockedGifts.clear();
      map.forEach((key, value) {
        if (value is List) {
          blockedGifts[key] = value.map((e) => e.toString()).toList();
        }
      });
    } catch (_) {
      // 存量数据损坏时静默忽略
    }
  }

  void _save() {
    try {
      HivePrefUtil.setString(_storageKey, jsonEncode(blockedGifts));
    } catch (_) {}
  }

  static String roomKey(String? platform, String? roomId) =>
      '${platform ?? ''}|${roomId ?? ''}';

  /// 当前房间被屏蔽的礼物名列表（拷贝，供 UI 展示）
  List<String> blockedGiftsOf(String? platform, String? roomId) {
    final list = blockedGifts[roomKey(platform, roomId)];
    return list == null ? const <String>[] : List<String>.from(list);
  }

  bool isBlocked(String? platform, String? roomId, String? giftName) {
    final name = giftName?.trim() ?? '';
    if (name.isEmpty) return false;
    return blockedGifts[roomKey(platform, roomId)]?.contains(name) ?? false;
  }

  void blockGift(String? platform, String? roomId, String giftName) {
    final name = giftName.trim();
    final key = roomKey(platform, roomId);
    if (name.isEmpty || key == '|') return;
    final list = blockedGifts[key] ?? <String>[];
    if (!list.contains(name)) list.add(name);
    blockedGifts[key] = list;
    _save();
  }

  void unblockGift(String? platform, String? roomId, String giftName) {
    final key = roomKey(platform, roomId);
    final list = blockedGifts[key];
    if (list == null) return;
    list.remove(giftName.trim());
    if (list.isEmpty) {
      blockedGifts.remove(key);
    } else {
      blockedGifts[key] = list;
    }
    _save();
  }
}
