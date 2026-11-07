import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/modules/esports/esports_match.dart';
import 'package:pure_live/modules/esports/esports_service.dart';
import 'package:pure_live/modules/esports/favorite_match_controller.dart';
import 'package:pure_live/plugins/event_bus.dart';

/// 桌面小组件（小米澎湃OS 风格 AppWidget）数据服务。
///
/// 职责：把"已开播关注直播间热度前 4"和"已关注赛事时间序前 4"写入原生侧
/// SharedPreferences，并触发 AppWidget 重绘。刷新时机：
/// - 服务初始化（App 启动）；
/// - 每 5 分钟定时（App 存活期间）；
/// - 关注列表刷新完成（EventBus `refresh_favorite_finish`）；
/// - 小组件上的刷新按钮（原生 `WidgetRefreshReceiver` → 通道 `refresh`）。
/// App 不在运行时小组件展示最后一次写入的缓存，点刷新按钮会先读缓存重绘，
/// 并唤醒 App 拉取最新数据。
class AppWidgetService extends GetxService {
  static const MethodChannel _channel = MethodChannel('pure_live/app_widget');

  /// 定时刷新间隔：小组件的时效性靠它兜底
  static const Duration _refreshInterval = Duration(minutes: 5);

  /// 直播间开播状态刷新并发度/超时（与关注页快通道一致）
  static const int _statusBatchSize = 12;
  static const Duration _statusTimeout = Duration(seconds: 5);

  /// 赛事抓取窗口：昨天（补正在进行的）到 7 天后
  static const int _esportsDaysAhead = 7;

  Timer? _timer;
  StreamSubscription? _favoriteRefreshSub;
  bool _refreshing = false;

  @override
  void onInit() {
    super.onInit();
    _channel.setMethodCallHandler(_onNativeCall);
    _favoriteRefreshSub = EventBus.instance.listen('refresh_favorite_finish', (_) {
      unawaited(refresh());
    });
    // 延后几秒：避开首页首屏的网络竞争
    Future.delayed(const Duration(seconds: 4), () => unawaited(refresh()));
    _timer = Timer.periodic(_refreshInterval, (_) => unawaited(refresh()));
  }

  @override
  void onClose() {
    _timer?.cancel();
    _favoriteRefreshSub?.cancel();
    super.onClose();
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method == 'refresh') {
      unawaited(refresh());
    }
    return null;
  }

  /// 拉最新数据并推送小组件（幂等：进行中直接跳过）。
  Future<void> refresh() async {
    if (!PlatformUtils.isAndroid || _refreshing) return;
    _refreshing = true;
    try {
      final live = await _collectLiveRooms();
      final esports = await _collectEsports();
      await _channel.invokeMethod('updateWidgets', {
        'live': jsonEncode(live),
        'esports': jsonEncode(esports),
      });
    } catch (e) {
      // 原生侧未就绪（冷启动极早期）或无小组件时静默忽略
      debugPrint('[AppWidgetService] refresh failed: $e');
    } finally {
      _refreshing = false;
    }
  }

  // ---------------------------------------------------------------------------
  // 直播间热度榜
  // ---------------------------------------------------------------------------

  /// 刷新关注直播间开播状态（写回缓存，与关注页口径一致），
  /// 返回"已开播在前 + 热度降序"的前 4 个房间的展示数据。
  Future<List<Map<String, dynamic>>> _collectLiveRooms() async {
    final all = SettingsService.to.fav.favoriteRooms.v
        .where((r) => (r.platform?.isNotEmpty ?? false) && (r.roomId?.isNotEmpty ?? false))
        .toList();
    if (all.isEmpty) return const [];

    await _refreshLiveStatus(all);

    final app = SettingsService.to.app;
    int sortValue(LiveRoom room) => room.audienceSortValue(
          preferRealOnline: app.preferRealOnlineCounts.v,
          platformEnabled: app.isRealOnlineEnabledFor(room.platform),
        );
    final rooms = List<LiveRoom>.from(all)
      ..sort((a, b) {
        final la = a.liveStatus == LiveStatus.live && a.status == true ? 1 : 0;
        final lb = b.liveStatus == LiveStatus.live && b.status == true ? 1 : 0;
        if (la != lb) return lb.compareTo(la);
        return sortValue(b).compareTo(sortValue(a));
      });

    return rooms.take(4).map((room) {
      final live = room.liveStatus == LiveStatus.live && room.status == true;
      final heat = (room.watching?.trim().isNotEmpty ?? false) ? room.watching!.trim() : (room.popularity ?? '');
      return <String, dynamic>{
        'platform': room.platform ?? '',
        'roomId': room.roomId ?? '',
        'nick': room.nick ?? '',
        'title': room.title ?? '',
        'heat': heat,
        'live': live,
      };
    }).toList();
  }

  /// 并发拉开播状态并写回关注缓存（复用关注页快通道的 worker 模式）。
  Future<void> _refreshLiveStatus(List<LiveRoom> rooms) async {
    final persistedRooms = List<LiveRoom>.from(SettingsService.to.fav.favoriteRooms.v);
    var dirty = false;
    void flush() {
      if (!dirty) return;
      dirty = false;
      SettingsService.to.fav.favoriteRooms.v = List<LiveRoom>.from(persistedRooms);
    }

    var next = 0;
    Future<void> worker() async {
      while (true) {
        final i = next++;
        if (i >= rooms.length) return;
        final room = rooms[i];
        final bool isLive;
        try {
          isLive = await Sites.of(room.platform!)
              .liveSite
              .getLiveStatus(platform: room.platform!, roomId: room.roomId!)
              .timeout(_statusTimeout);
        } catch (_) {
          continue;
        }
        final idx = persistedRooms.indexWhere(
          (e) => e.roomId == room.roomId && e.platform == room.platform,
        );
        if (idx == -1) continue;
        final target = persistedRooms[idx];
        final nextStatus = isLive ? LiveStatus.live : LiveStatus.offline;
        if (target.liveStatus == nextStatus) continue;
        target.liveStatus = nextStatus;
        target.status = isLive;
        dirty = true;
        flush();
      }
    }

    await Future.wait(List.generate(_statusBatchSize, (_) => worker()));
    dirty = true;
    flush();
  }

  // ---------------------------------------------------------------------------
  // 赛事日程
  // ---------------------------------------------------------------------------

  /// 已关注赛事按开始时间升序前 4 场。
  Future<List<Map<String, dynamic>>> _collectEsports() async {
    final Set<String> favIds;
    if (Get.isRegistered<FavoriteMatchController>()) {
      favIds = Get.find<FavoriteMatchController>().favoriteMatchIds;
    } else {
      return const [];
    }
    if (favIds.isEmpty) return const [];

    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 1));
    final to = now.add(const Duration(days: _esportsDaysAhead));
    final List<EsportsMatch> matches;
    try {
      matches = await EsportsService().fetchMatches(from: from, to: to);
    } catch (_) {
      return const [];
    }
    final favorited = matches.where((m) => favIds.contains(m.matchId)).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    // 只渲染前 2 场（小组件 2×2 版式），队徽提前取好（base64 供原生解码）
    final top = favorited.take(2).toList();
    final logoA = <String, String>{};
    final logoB = <String, String>{};
    for (final match in top) {
      logoA[match.matchId] = await _fetchLogoBase64(match.teamALogo);
      logoB[match.matchId] = await _fetchLogoBase64(match.teamBLogo);
    }

    return top.map((match) {
      final series = match.seriesShortName.isNotEmpty
          ? match.seriesShortName
          : (match.seriesName.isNotEmpty ? match.seriesName : match.gameName);
      final hasScore = match.scoreA > 0 || match.scoreB > 0;
      final live = match.status == 2;
      return <String, dynamic>{
        'series': series,
        'teamA': match.teamAName,
        'teamB': match.teamBName,
        'logoA': logoA[match.matchId] ?? '',
        'logoB': logoB[match.matchId] ?? '',
        'score': hasScore ? '${match.scoreA} : ${match.scoreB}' : '',
        'live': live,
        'ended': match.status == 3,
        'statusText': live ? '进行中' : (match.status == 3 ? '已结束' : '前瞻'),
        'timeText': _formatMatchTime(match.startDateTime, now),
      };
    }).toList();
  }

  /// 队徽/赛事图标 → base64（原生 RemoteViews 只认本地位图）。
  /// 带内存缓存：徽标 URL 固定，5 分钟刷新不必重复下载。
  final Map<String, String> _logoBase64Cache = {};

  Future<String> _fetchLogoBase64(String url) async {
    if (url.isEmpty) return '';
    final cached = _logoBase64Cache[url];
    if (cached != null) return cached;
    try {
      final bytes = await HttpClient.instance
          .getBytes(url, header: {'user-agent': 'Mozilla/5.0'})
          .timeout(const Duration(seconds: 6));
      if (bytes.isEmpty) return '';
      final b64 = base64Encode(bytes);
      _logoBase64Cache[url] = b64;
      return b64;
    } catch (_) {
      return '';
    }
  }

  /// 未开始显示具体日期时间，当天带"今天"前缀；进行中/已结束由原生侧展示状态标记。
  String _formatMatchTime(DateTime start, DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    final sameDay = start.year == now.year && start.month == now.month && start.day == now.day;
    final hhmm = '${two(start.hour)}:${two(start.minute)}';
    if (sameDay) return '今天 $hhmm';
    return '${two(start.month)}-${two(start.day)} $hhmm';
  }
}
