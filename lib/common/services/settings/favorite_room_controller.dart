import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/consts/app_consts.dart';
import 'package:pure_live/common/services/utils/backup_migration_util.dart';

class FavoriteRoomController extends GetxController {
  final RxList<String> shieldList = hiveStringList('shieldList', []);
  final RxList<String> blockedDanmakuUsers = hiveStringList('blockedDanmakuUsers', []);
  final RxList<String> hotAreasList = hiveStringList('hotAreasList', AppConsts.supportSites);
  final RxInt siteCatalogMigration = hiveInt('siteCatalogMigration', 0);
  final RxString preferPlatform = hiveString('preferPlatform', Sites.bilibiliSite);

  /// 开播即置顶的房间（identityKey 集合）：置顶直播间开播后在"已开播/已关注"
  /// 页签恒排最前。独立集合存储而非 LiveRoom 字段——收藏条目会被直播详情
  /// 刷新整体替换（updateRoom），字段会被平台新数据冲掉。
  final RxList<String> pinnedRooms = hiveStringList('pinnedRooms', []);
  final Rx<List<LiveRoom>> favoriteRooms = hiveObject(
    'favoriteRooms',
    <LiveRoom>[],
    fromJson: (json) {
      return List<LiveRoom>.from((json['list'] ?? []).map((e) => LiveRoom.fromJson(e)));
    },
    toJson: (list) {
      return {'list': list.map((e) => e.toJson()).toList()};
    },
  );

  /// 观看历史：最近观看的直播间，按 watchedAt 倒序，超出上限自动裁剪。
  /// 仅本地存储，不参与备份/NAS 同步。
  final Rx<List<LiveRoom>> watchHistory = hiveObject(
    'watchHistory',
    <LiveRoom>[],
    fromJson: (json) {
      return List<LiveRoom>.from((json['list'] ?? []).map((e) => LiveRoom.fromJson(e)));
    },
    toJson: (list) {
      return {'list': list.map((e) => e.toJson()).toList()};
    },
  );

  @override
  void onInit() {
    super.onInit();
    if (siteCatalogMigration.v < 2) {
      for (final site in Sites.supportSites) {
        if (!hotAreasList.contains(site.id)) hotAreasList.add(site.id);
      }
      siteCatalogMigration.v = 2;
    }
  }

  final Rx<List<LiveArea>> favoriteAreas = hiveObject(
    'favoriteAreas',
    <LiveArea>[],
    fromJson: (json) {
      return List<LiveArea>.from((json['list'] ?? []).map((e) => LiveArea.fromJson(e)));
    },
    toJson: (list) {
      return {'list': list.map((e) => e.toJson()).toList()};
    },
  );

  // 复合身份（上游 2.5.1）：不同平台存在相同房间号，只比 roomId 会互相覆盖/误判已关注
  bool isFavorite(LiveRoom room) => favoriteRooms.v.any((e) => e.hasSameIdentity(room));
  bool isFavoriteArea(LiveArea area) => favoriteAreas.v.any((e) => e.areaId == area.areaId);

  bool isPinned(LiveRoom room) => pinnedRooms.contains(room.identityKey);

  /// 切换置顶并返回置顶后的状态。
  bool togglePinned(LiveRoom room) {
    final key = room.identityKey;
    if (pinnedRooms.contains(key)) {
      pinnedRooms.remove(key);
    } else {
      pinnedRooms.add(key);
    }
    pinnedRooms.refresh();
    return pinnedRooms.contains(key);
  }

  bool addRoom(LiveRoom room) {
    if (isFavorite(room)) return false;
    favoriteRooms.v.add(room);
    favoriteRooms.refresh();
    return true;
  }

  bool removeRoom(LiveRoom room) {
    final res = favoriteRooms.v.remove(room);
    favoriteRooms.refresh();
    return res;
  }

  bool updateRoom(LiveRoom room) {
    final idx = favoriteRooms.v.indexWhere((e) => e.hasSameIdentity(room));
    if (idx == -1) return false;
    final previous = favoriteRooms.v[idx];
    // 平台详情不认识本地字段：整体替换前把旧条目的备注/标签回填。
    // 否则进一次直播间（onInitPlayerState 拿到详情后调本方法同步收藏）备注就被
    // 冲成空，退出后卡片回落到平台原名，且没有任何路径能自愈（必须重新编辑）。
    // 只在平台新对象没带值时才回填，调用方主动设置的字段不会被覆盖。
    if (!identical(previous, room)) {
      if ((room.note ?? '').isEmpty) room.note = previous.note;
      if (room.tagIds.isEmpty) room.tagIds = List<String>.from(previous.tagIds);
    }
    favoriteRooms.v[idx] = room;
    favoriteRooms.refresh();
    return true;
  }

  bool addArea(LiveArea area) {
    if (isFavoriteArea(area)) return false;
    favoriteAreas.v.add(area);
    favoriteAreas.refresh();
    return true;
  }

  bool removeArea(LiveArea area) {
    final res = favoriteAreas.v.remove(area);
    favoriteAreas.refresh();
    return res;
  }

  /// 记录观看历史：同身份房间去重置顶并合并最新信息，超出上限裁掉最旧的。
  /// 幂等：同一直播间反复进入/切清晰度只会置顶刷新，不会产生重复条目。
  /// 注意：直接引用传入的房间对象（与收藏 updateRoom 同语义），不得清空其
  /// tagIds/note——调用方传入的是播放页正在使用的 detail，后续还会同步进收藏。
  void recordWatchHistory(LiveRoom room, {int? limit}) {
    final maxCount = limit ?? SettingsService.to.app.watchHistoryLimit.v;
    if (maxCount <= 0) {
      // 上限为 0 视为关闭记录功能，清空既有历史。
      if (watchHistory.v.isNotEmpty) watchHistory.v.clear();
      watchHistory.refresh();
      return;
    }
    room.watchedAt = DateTime.now().millisecondsSinceEpoch;
    watchHistory.v.removeWhere((e) => e.hasSameIdentity(room));
    watchHistory.v.insert(0, room);
    if (watchHistory.v.length > maxCount) {
      watchHistory.v.removeRange(maxCount, watchHistory.v.length);
    }
    watchHistory.refresh();
  }

  void clearWatchHistory() {
    watchHistory.v.clear();
    watchHistory.refresh();
  }

  /// 按当前上限立即裁剪历史（设置里调小上限后调用）。
  void recordWatchHistoryTrim() {
    final maxCount = SettingsService.to.app.watchHistoryLimit.v;
    if (maxCount <= 0) {
      clearWatchHistory();
      return;
    }
    if (watchHistory.v.length > maxCount) {
      watchHistory.v.removeRange(maxCount, watchHistory.v.length);
      watchHistory.refresh();
    }
  }

  void addShieldList(String value) => shieldList.v.add(value);
  void removeShieldList(int idx) => shieldList.v.removeAt(idx);
  void addBlockedDanmakuUser(String value) {
    final user = value.trim();
    if (user.isNotEmpty && !blockedDanmakuUsers.contains(user)) blockedDanmakuUsers.add(user);
  }

  void removeBlockedDanmakuUser(int idx) => blockedDanmakuUsers.removeAt(idx);

  LiveRoom? getRoomById(String roomId, String platform) {
    for (final room in favoriteRooms.v) {
      if (room.roomId == roomId && room.platform == platform) {
        return room;
      }
    }
    return null;
  }

  void changePreferPlatform(String name) {
    final list = Sites.supportSites.map((e) => e.id).toList();
    if (list.contains(name)) {
      preferPlatform.v = name;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'shieldList': shieldList.v,
      'blockedDanmakuUsers': blockedDanmakuUsers.v,
      'hotAreasList': hotAreasList.v,
      'preferPlatform': preferPlatform.v,
      'pinnedRooms': pinnedRooms.v,
      'favoriteRooms': favoriteRooms.v.map((e) => e.toJson()).toList(),
      'favoriteAreas': favoriteAreas.v.map((e) => e.toJson()).toList(),
    };
  }

  void fromJson(Map<String, dynamic> json) {
    shieldList.v = List<String>.from(json['shieldList'] ?? []);
    blockedDanmakuUsers.v = List<String>.from(json['blockedDanmakuUsers'] ?? []);

    hotAreasList.v = List<String>.from(json['hotAreasList'] ?? AppConsts.supportSites);

    preferPlatform.v = json['preferPlatform'] ?? Sites.bilibiliSite;

    pinnedRooms.v = List<String>.from(json['pinnedRooms'] ?? []);

    favoriteRooms.v = BackupMigrationUtil.parseObjectList(json['favoriteRooms'], (m) => LiveRoom.fromJson(m));

    favoriteAreas.v = BackupMigrationUtil.parseObjectList(json['favoriteAreas'], (m) => LiveArea.fromJson(m));
  }

  static Map<String, dynamic> extractConfig(Map<String, dynamic>? rootConfig) {
    final favorite = rootConfig?['favorite'] as Map<String, dynamic>? ?? {};
    return {
      'shieldList': List<String>.from(favorite['shieldList'] ?? []),
      'blockedDanmakuUsers': List<String>.from(favorite['blockedDanmakuUsers'] ?? []),
      'hotAreasList': List<String>.from(favorite['hotAreasList'] ?? AppConsts.supportSites),
      'preferPlatform': favorite['preferPlatform'] ?? Sites.bilibiliSite,
      'pinnedRooms': List<String>.from(favorite['pinnedRooms'] ?? []),
      'favoriteRooms': BackupMigrationUtil.parseObjectList(
        favorite['favoriteRooms'],
        LiveRoom.fromJson,
      ).map((e) => e.toJson()).toList(),
      'favoriteAreas': BackupMigrationUtil.parseObjectList(
        favorite['favoriteAreas'],
        LiveArea.fromJson,
      ).map((e) => e.toJson()).toList(),
    };
  }

  static Map<String, dynamic> mergeConfig(Map<String, dynamic> rootConfig, Map<String, dynamic> updateFields) {
    final favorite = Map<String, dynamic>.from(rootConfig['favorite'] ?? {});
    updateFields.forEach((k, v) => favorite[k] = v);
    rootConfig['favorite'] = favorite;
    return rootConfig;
  }
}
