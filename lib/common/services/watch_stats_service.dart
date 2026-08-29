import 'dart:async';
import 'dart:convert';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';

/// 本地观看统计：按直播间维度累计观看时长（总计 + 按天），全部仅存本地。
///
/// 进入直播间时 [startSession]，离开/切房时 [stopSession] 结算；
/// 会话期间每 60 秒提交一次，异常退出最多丢 1 分钟。
class WatchStatsService extends GetxService {
  static const String _storageKey = 'watchStatsV1';

  String? _currentKey;
  LiveRoom? _currentRoom;
  DateTime? _sessionStart;
  Timer? _commitTimer;

  /// key（platform|roomId）→ 统计条目 {nick, platform, roomId, total, daily}
  final Map<String, Map<String, dynamic>> stats = {};

  static WatchStatsService? _instance;
  static WatchStatsService get instance => _instance!;

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
      stats.clear();
      map.forEach((key, value) {
        if (value is Map) stats[key] = Map<String, dynamic>.from(value);
      });
    } catch (_) {
      // 存量数据损坏时静默忽略，后续会话会重建
    }
  }

  void _save() {
    try {
      HivePrefUtil.setString(_storageKey, jsonEncode(stats));
    } catch (_) {}
  }

  /// 进入直播间开始计时；同一房间重复调用幂等。
  void startSession(LiveRoom room) {
    final key = _roomKey(room);
    if (key.isEmpty) return;
    if (_currentKey == key && _sessionStart != null) return;
    stopSession();
    _currentKey = key;
    _currentRoom = room;
    _sessionStart = DateTime.now();
    _commitTimer?.cancel();
    _commitTimer = Timer.periodic(const Duration(seconds: 60), (_) => _commit());
  }

  /// 离开直播间/切房时结算。
  void stopSession() {
    _commit();
    _commitTimer?.cancel();
    _commitTimer = null;
    _currentKey = null;
    _currentRoom = null;
    _sessionStart = null;
  }

  void _commit() {
    final key = _currentKey;
    final start = _sessionStart;
    final room = _currentRoom;
    if (key == null || start == null || room == null) return;
    final seconds = DateTime.now().difference(start).inSeconds;
    if (seconds <= 0) return;
    _sessionStart = DateTime.now();
    final entry = stats.putIfAbsent(
      key,
      () => {
        'nick': room.nick ?? '',
        'platform': room.platform ?? '',
        'roomId': room.roomId ?? '',
        'total': 0,
        'daily': <String, int>{},
      },
    );
    final nick = (room.nick?.isNotEmpty == true ? room.nick : room.title) ?? '';
    if (nick.isNotEmpty) entry['nick'] = nick;
    entry['total'] = ((entry['total'] as int?) ?? 0) + seconds;
    final daily = Map<String, int>.from((entry['daily'] as Map?)?.cast<String, int>() ?? const {});
    final today = _dayKey(DateTime.now());
    daily[today] = (daily[today] ?? 0) + seconds;
    entry['daily'] = daily;
    _save();
  }

  /// 清除全部统计（当前会话从现在重新累计）。
  void clearAll() {
    stats.clear();
    _save();
  }

  /// 累计观看秒数。
  int totalSeconds() =>
      stats.values.fold(0, (sum, entry) => sum + ((entry['total'] as int?) ?? 0));

  /// 近 7 天（含今天）累计观看秒数。
  int weekSeconds() {
    var sum = 0;
    for (var i = 0; i <= 6; i++) {
      final day = _dayKey(DateTime.now().subtract(Duration(days: i)));
      for (final entry in stats.values) {
        final daily = (entry['daily'] as Map?)?.cast<String, int>() ?? const {};
        sum += daily[day] ?? 0;
      }
    }
    return sum;
  }

  /// 按累计时长降序的统计条目。
  List<MapEntry<String, Map<String, dynamic>>> sortedEntries() {
    final entries = stats.entries.where((e) => ((e.value['total'] as int?) ?? 0) > 0).toList();
    entries.sort((a, b) => ((b.value['total'] as int?) ?? 0).compareTo(((a.value['total'] as int?) ?? 0)));
    return entries;
  }

  String _dayKey(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  String _roomKey(LiveRoom room) => '${room.platform ?? ''}|${room.roomId ?? ''}';
}

/// 时长格式化：秒 → 「x 小时 y 分钟」/「x 分钟」/「x 秒」。
String formatWatchDuration(int seconds) {
  if (seconds < 60) return '$seconds 秒';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '$minutes 分钟';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分钟';
}
