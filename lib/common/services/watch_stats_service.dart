import 'dart:async';
import 'dart:convert';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/utils/hive_pref_util.dart';

/// 本地观看统计：按直播间维度累计观看时长（总计 + 按天）与观看期间收到的
/// 礼物（件数 + 价值估算），全部仅存本地。
///
/// 进入直播间时 [startSession]，离开/切房时 [stopSession] 结算；
/// 会话期间每 60 秒提交一次，异常退出最多丢 1 分钟。
class WatchStatsService extends GetxService {
  static const String _storageKey = 'watchStatsV1';

  String? _currentKey;
  LiveRoom? _currentRoom;
  DateTime? _sessionStart;
  Timer? _commitTimer;

  /// 当前会话未提交的礼物累计（抖音连击的增量状态也在这里）
  final GiftTally _sessionGifts = GiftTally();

  /// key（platform|roomId）→ 统计条目
  /// {nick, platform, roomId, total, daily, giftCount, giftPaidCount, giftValueFen}
  final Map<String, Map<String, dynamic>> stats = {};

  /// 统计结算回调（每次写入后触发）。桌面快捷方式等依赖观看时长的
  /// 功能据此刷新。回调在结算同步流程内执行，保持轻量。
  void Function()? onStatsCommitted;

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

  /// 记录观看期间收到的一条礼物消息。
  ///
  /// 只累计网络礼物：本地互动礼物（自己发的，`data['local'] == true`）
  /// 不算"收到"。累计只放在内存里，由 [_commit] 随会话一起落盘。
  void recordGift(LiveMessage msg) {
    final room = _currentRoom;
    if (_currentKey == null || room == null) return;
    final data = msg.data;
    if (data is! Map) return;
    if (data['local'] == true) return;
    _sessionGifts.add(
      platform: room.platform ?? '',
      data: data,
      userKey: msg.userId.isNotEmpty ? msg.userId : msg.userName,
      reportedCount: msg.giftCount,
    );
  }

  /// 离开直播间/切房时结算。
  void stopSession() {
    _commit();
    _commitTimer?.cancel();
    _commitTimer = null;
    _currentKey = null;
    _currentRoom = null;
    _sessionStart = null;
    _sessionGifts.reset();
  }

  void _commit() {
    final key = _currentKey;
    final start = _sessionStart;
    final room = _currentRoom;
    if (key == null || start == null || room == null) return;
    final seconds = DateTime.now().difference(start).inSeconds;
    // 时长不足 1 秒且没有待结算礼物时才跳过，避免刚提交过就丢礼物
    final hasGifts = !_sessionGifts.isEmpty;
    if (seconds <= 0 && !hasGifts) return;
    if (seconds > 0) _sessionStart = DateTime.now();
    final entry = stats.putIfAbsent(
      key,
      () => {
        'nick': room.nick ?? '',
        'platform': room.platform ?? '',
        'roomId': room.roomId ?? '',
        'total': 0,
        'daily': <String, int>{},
        'giftCount': 0,
        'giftPaidCount': 0,
        'giftValueFen': 0,
      },
    );
    final nick = (room.nick?.isNotEmpty == true ? room.nick : room.title) ?? '';
    if (nick.isNotEmpty) entry['nick'] = nick;
    if (seconds > 0) {
      entry['total'] = ((entry['total'] as int?) ?? 0) + seconds;
      final daily = Map<String, int>.from((entry['daily'] as Map?)?.cast<String, int>() ?? const {});
      final today = _dayKey(DateTime.now());
      daily[today] = (daily[today] ?? 0) + seconds;
      entry['daily'] = daily;
    }
    if (hasGifts) {
      entry['giftCount'] = ((entry['giftCount'] as int?) ?? 0) + _sessionGifts.count;
      entry['giftPaidCount'] = ((entry['giftPaidCount'] as int?) ?? 0) + _sessionGifts.paidCount;
      entry['giftValueFen'] = ((entry['giftValueFen'] as int?) ?? 0) + _sessionGifts.valueFen;
      _sessionGifts.reset();
    }
    _save();
    onStatsCommitted?.call();
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

  /// 全部直播间累计收到的礼物件数。
  int totalGiftCount() =>
      stats.values.fold(0, (sum, entry) => sum + ((entry['giftCount'] as int?) ?? 0));

  /// 全部直播间累计礼物价值估算（人民币分）。
  int totalGiftValueFen() =>
      stats.values.fold(0, (sum, entry) => sum + entryGiftValueFen(entry));

  /// 全部直播间累计主播到手估算（人民币分）。
  /// 到手比例按平台不同，必须逐条按各条目所属平台折算后再求和。
  int totalGiftIncomeFen() =>
      stats.values.fold(0, (sum, entry) => sum + entryGiftIncomeFen(entry));

  /// 单条统计的礼物价值（人民币分）。
  static int entryGiftValueFen(Map<String, dynamic> entry) => (entry['giftValueFen'] as int?) ?? 0;

  /// 单条统计的主播到手估算（人民币分）。
  static int entryGiftIncomeFen(Map<String, dynamic> entry) => GiftValueRules.anchorFen(
    (entry['platform'] as String?) ?? '',
    entryGiftValueFen(entry),
  );

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
