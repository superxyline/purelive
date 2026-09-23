import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/tags/live_tag.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';

class TagManagementController extends GetxController {
  static const String _storageKey = 'user_custom_tags_v5';
  static const String _roomTagsMappingKey = 'room_to_tags_mapping_v1';
  final RxMap<String, List<String>> roomTagsMap = <String, List<String>>{}.obs;
  final RxList<LiveTag> tags = <LiveTag>[].obs;
  static const Map<String, String> allTag = {'all': '全部'};
  static String get allTagKey => allTag.keys.first;
  static String get allTagLabel => allTag.values.first;

  /// 分区自动标签的虚拟 id 前缀。分区标签不写入标签体系，仅在关注页
  /// 按 room.area 动态生成/过滤，id = 'area:' + 分区名，与时间戳 id 不冲突。
  static const String areaTagPrefix = 'area:';
  static String areaTagId(String area) => '$areaTagPrefix$area';
  static bool isAreaTag(String id) => id.startsWith(areaTagPrefix);
  static String? areaNameFromTagId(String id) =>
      isAreaTag(id) ? id.substring(areaTagPrefix.length) : null;
  @override
  void onInit() {
    super.onInit();
    _loadTags();
    _loadRoomTagsMapping();
  }

  void _loadTags() {
    final List<dynamic>? storedTags = HivePrefUtil.getAnyPref(_storageKey);
    if (storedTags != null) {
      final list = storedTags.map((e) => LiveTag.fromJson(Map<String, dynamic>.from(e))).toList();
      list.sort((a, b) => a.order.compareTo(b.order));
      tags.assignAll(list);
    } else {
      tags.clear();
    }
  }

  Future<void> saveTags() async {
    await HivePrefUtil.setAnyPref(_storageKey, tags.map((e) => e.toJson()).toList());
  }

  Future<void> saveRoomTagsMapping() async {
    await HivePrefUtil.setAnyPref(_roomTagsMappingKey, roomTagsMap);
  }

  /// [roomKey] 使用复合身份 `platform:roomId`（上游修复：不同平台房间号相同会互相覆盖）。
  /// [legacyRoomId] 迁移用：写入新键时顺手删除旧的纯 roomId 键。
  void setRoomTags(String roomKey, List<String> newTagIds, {String? legacyRoomId}) {
    if (newTagIds.isEmpty) {
      roomTagsMap.remove(roomKey);
    } else {
      roomTagsMap[roomKey] = newTagIds;
    }
    if (legacyRoomId != null && legacyRoomId != roomKey) {
      roomTagsMap.remove(legacyRoomId);
    }

    roomTagsMap.refresh();
    saveRoomTagsMapping();
  }

  void _loadRoomTagsMapping() {
    final Map<dynamic, dynamic>? storedMap = HivePrefUtil.getAnyPref(_roomTagsMappingKey);

    if (storedMap != null) {
      final convertedMap = storedMap.map((key, value) {
        return MapEntry(key.toString(), List<String>.from(value as List));
      });
      roomTagsMap.assignAll(convertedMap);
    }
  }

  List<String> getTagsForRoom(LiveRoom room) {
    // 新键 platform:roomId 优先，回退旧的纯 roomId 键（读侧兼容，写侧逐步迁移）
    final legacy = roomTagsMap[room.roomId.toString()];
    return roomTagsMap[room.identityKey] ?? legacy ?? [];
  }

  bool addTag(String name, String description) {
    final cleanName = name.trim();
    if (cleanName.isEmpty) return false;

    final exists = tags.any((tag) => tag.name.toLowerCase() == cleanName.toLowerCase());
    if (exists) return false;

    final newTag = LiveTag(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: cleanName,
      description: description.trim(),
      order: tags.length,
    );

    tags.add(newTag);
    saveTags();
    return true;
  }

  void updateAllTags(List<LiveTag> newList) {
    tags.assignAll(newList);
    for (int i = 0; i < tags.length; i++) {
      tags[i].order = i;
    }
    tags.refresh();
    saveTags();
  }

  bool updateTag(int index, String newName, String newDescription) {
    final cleanName = newName.trim();
    if (cleanName.isEmpty) return false;

    if (tags[index].name != cleanName) {
      final exists = tags.any((tag) => tag.name.toLowerCase() == cleanName.toLowerCase());
      if (exists) return false;
    }

    tags[index].name = cleanName;
    tags[index].description = newDescription.trim();
    tags.refresh();
    saveTags();
    return true;
  }

  void pinToTop(int index) {
    if (index <= 0 || index >= tags.length) return;

    final targetTag = tags.removeAt(index);
    tags.insert(0, targetTag);

    _refreshSequentialOrders();
  }

  void togglePinStatus(int index) {
    _refreshSequentialOrders();
  }

  void deleteTag(int index) {
    tags.removeAt(index);
    _refreshSequentialOrders();
  }

  void _refreshSequentialOrders() {
    for (int i = 0; i < tags.length; i++) {
      tags[i].order = i;
    }
    tags.refresh();
    saveTags();
  }

  Map<String, dynamic> exportToJson() {
    return {'tags': tags.map((e) => e.toJson()).toList(), 'roomTagsMap': roomTagsMap};
  }

  void importFromJson(Map<String, dynamic>? json) {
    if (json == null) return;

    if (json.containsKey('tags') && json['tags'] != null) {
      final storedTags = json['tags'] as List;
      final list = storedTags.map((e) => LiveTag.fromJson(Map<String, dynamic>.from(e))).toList();
      list.sort((a, b) => a.order.compareTo(b.order));
      tags.assignAll(list);
      saveTags();
    }

    if (json.containsKey('roomTagsMap') && json['roomTagsMap'] != null) {
      final storedMap = json['roomTagsMap'] as Map;
      final convertedMap = storedMap.map((key, value) {
        return MapEntry(key.toString(), List<String>.from(value as List));
      });
      roomTagsMap.assignAll(convertedMap);
      saveRoomTagsMapping();
    }
  }
}
