import 'dart:async';

import 'package:pure_live/get/get.dart';
import 'package:pure_live/modules/esports/esports_match.dart';
import 'package:pure_live/modules/esports/favorite_match_controller.dart';
import 'package:pure_live/modules/esports/esports_service.dart';

/// 赛事页控制器：加载 完美世界(CS) + lolesports(LOL/Valorant) 赛事日程。
/// Dota2 数据源暂未接入，筛选时显示占位提示。
class EsportsController extends GetxController {
  final EsportsService _service = EsportsService();

  /// 游戏筛选：0=全部 1=CS 2=Dota2 3=英雄联盟 4=Valorant
  final RxInt gameFilter = 1.obs;

  /// 赛事名筛选（空字符串 = 全部赛事）
  final RxString seriesFilter = ''.obs;

  /// 日期筛选（null = 全部日期）
  final Rx<DateTime?> dateFilter = Rx<DateTime?>(null);

  /// 只看已关注赛事
  final RxBool showOnlyFavorites = false.obs;

  /// 加载中
  final RxBool loading = false.obs;

  /// 错误信息（为空表示无错误；加载失败但至少一个数据源成功时为空）
  final RxString error = ''.obs;

  /// 赛事日程列表（CS + LOL + Valorant 合并）
  final RxList<EsportsMatch> matches = <EsportsMatch>[].obs;

  /// 已加载的日期范围（用于页面标题展示）
  DateTime? loadedFrom;
  DateTime? loadedTo;

  /// 游戏筛选选项（key 与 i18n 对应）
  static const List<String> gameFilterKeys = [
    'esports_filter_all',
    'esports_filter_cs',
    'esports_filter_dota2',
    'esports_filter_lol',
    'esports_filter_valorant',
  ];

  /// 归一化游戏标识集合
  static const Map<int, String> _filterGameKeys = {
    1: 'cs',
    2: 'dota2',
    3: 'lol',
    4: 'valorant',
  };

  /// 冷启动预取缓存：App 启动后在后台预取赛事数据，进入赛事页时直接命中缓存，
  /// 省去点击标签后的转圈等待。缓存一次性使用，命中后即清空。
  static List<EsportsMatch>? _prefetchedMatches;

  /// 后台预取（冷启动后调用）。失败静默，不影响进入页面后的正常加载流程。
  static Future<void> prefetch() async {
    if (_prefetchedMatches != null) return;
    try {
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day);
      final to = from.add(const Duration(days: 8)).subtract(const Duration(seconds: 1));
      final list = await EsportsService().fetchMatches(from: from, to: to);
      if (list.isNotEmpty) _prefetchedMatches = list;
    } catch (_) {}
  }

  @override
  void onInit() {
    super.onInit();
    // 默认选中今天，配合默认 CS 游戏筛选展示今日 CS 赛事
    final DateTime now = DateTime.now();
    dateFilter.value = DateTime(now.year, now.month, now.day);
    loadData();
  }

  /// 刷新数据（首次加载显示转圈；已有数据时后台刷新，旧内容保留到新数据到达）
  /// 是否已应用过"默认热度赛事"筛选（每次控制器生命周期只应用一次，
  /// 之后用户手动切回"全部"不会被覆盖）
  bool _defaultSeriesApplied = false;

  /// CS 赛事加载完成后，默认选中热度最高的赛事（而非显示全部）。
  /// 热度评分：进行中 > 官方重要 > 官方热门 > T1/T2 > 即将开赛。
  String? _pickHottestSeries() {
    final csMatches = matches.where((m) => m.gameKey == 'cs').toList();
    if (csMatches.isEmpty) return null;
    final bySeries = <String, List<EsportsMatch>>{};
    for (final m in csMatches) {
      bySeries.putIfAbsent(m.seriesName, () => []).add(m);
    }
    String? best;
    var bestScore = -1;
    bySeries.forEach((name, list) {
      var score = 0;
      for (final m in list) {
        if (m.isLive) score += 30;
        if (m.eventImportant) score += 10;
        if (m.eventHot) score += 5;
        if (m.eventLevel == 'T1') {
          score += 8;
        } else if (m.eventLevel == 'T2') {
          score += 3;
        }
        if (m.isUpcoming) score += 1;
      }
      if (score > bestScore) {
        bestScore = score;
        best = name;
      }
    });
    return best;
  }

  Future<void> loadData() async {
    if (loading.value) return;
    // 冷启动预取命中：直接渲染缓存数据（不转圈），随后走一次后台刷新保持新鲜
    final prefetched = _prefetchedMatches;
    if (matches.isEmpty && prefetched != null) {
      _prefetchedMatches = null;
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day);
      final to = from.add(const Duration(days: 8)).subtract(const Duration(seconds: 1));
      matches.assignAll(prefetched);
      loadedFrom = from;
      loadedTo = to;
      unawaited(loadData());
      return;
    }
    // 已有数据时视为后台刷新：不置 loading，避免页面主体被替换成加载动画
    final bool isRefresh = matches.isNotEmpty;
    if (!isRefresh) {
      loading.value = true;
    }
    error.value = '';
    try {
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day);
      final to = DateTime(now.year, now.month, now.day).add(const Duration(days: 8)).subtract(const Duration(seconds: 1));
      final list = await _service.fetchMatches(from: from, to: to);
      matches.assignAll(list);
      loadedFrom = from;
      loadedTo = to;
      // CS 默认选中热度最高赛事：避免"全部+按时间排序"淹没重点比赛。
      // 若该赛事当天没有比赛，则自动放开日期筛选，保证有内容展示。
      if (!_defaultSeriesApplied && gameFilter.value == 1 && list.isNotEmpty) {
        _defaultSeriesApplied = true;
        final hottest = _pickHottestSeries();
        if (hottest != null && hottest.isNotEmpty && seriesFilter.value.isEmpty) {
          seriesFilter.value = hottest;
          final day = dateFilter.value;
          final hasMatchToday = day == null ||
              matches.any((m) =>
                  m.gameKey == 'cs' && m.seriesName == hottest &&
                  (m.startDateTime.year == day.year &&
                      m.startDateTime.month == day.month &&
                      m.startDateTime.day == day.day));
          if (!hasMatchToday) dateFilter.value = null;
        }
      }
      if (list.isEmpty) {
        error.value = 'esports_load_failed';
      }
    } catch (_) {
      matches.clear();
      error.value = 'esports_load_failed';
    } finally {
      loading.value = false;
    }
  }

  /// 切换游戏筛选（重置赛事筛选，保留日期筛选）
  void setGameFilter(int index) {
    gameFilter.value = index;
    seriesFilter.value = '';
  }

  /// 当前筛选是否为 Dota2（用于页面显示"暂未接入"提示）
  bool get isDota2Filter => gameFilter.value == 2;

  /// 日期筛选选项：今天 到 +7 天
  List<DateTime> get dateFilterOptions {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return [for (int i = 0; i <= 7; i++) today.add(Duration(days: i))];
  }

  /// 当前游戏筛选下可用的赛事名列表（去重排序）
  List<String> get availableSeries {
    final key = _filterGameKeys[gameFilter.value];
    final Iterable<EsportsMatch> list =
        key == null ? matches : matches.where((m) => m.gameKey == key);
    final names = list.map((m) => m.seriesName).where((n) => n.isNotEmpty).toSet().toList();
    names.sort();
    return names;
  }

  /// 当前筛选下的赛事列表（游戏 + 赛事名 + 日期 三级过滤）。
  /// Dota2（key=dota2）暂未接入数据源，恒为空列表。
  List<EsportsMatch> get filteredMatches {
    Iterable<EsportsMatch> list = matches;
    final key = _filterGameKeys[gameFilter.value];
    if (key != null) {
      list = list.where((m) => m.gameKey == key);
    }
    final series = seriesFilter.value;
    if (series.isNotEmpty) {
      list = list.where((m) => m.seriesName == series);
    }
    final date = dateFilter.value;
    if (date != null) {
      list = list.where((m) {
        final d = m.startDateTime;
        return d.year == date.year && d.month == date.month && d.day == date.day;
      });
    }
    if (showOnlyFavorites.value) {
      final Set<String> favIds =
          Get.find<FavoriteMatchController>().favoriteMatchIds;
      list = list.where((m) => favIds.contains(m.matchId));
    }
    return list.toList();
  }

  /// 按日期分组（key 为当天 0 点），保持日期升序
  Map<DateTime, List<EsportsMatch>> groupByDate(List<EsportsMatch> list) {
    final map = <DateTime, List<EsportsMatch>>{};
    for (final match in list) {
      final day = DateTime(match.startDateTime.year, match.startDateTime.month, match.startDateTime.day);
      map.putIfAbsent(day, () => []).add(match);
    }
    final sortedKeys = map.keys.toList()..sort();
    return {for (final k in sortedKeys) k: map[k]!};
  }
}
