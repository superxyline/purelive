import 'package:get/get.dart';
import 'package:pure_live/modules/esports/esports_match.dart';
import 'package:pure_live/modules/esports/esports_service.dart';

/// 赛事页控制器：加载 完美世界(CS) + lolesports(LOL) 赛事日程。
/// Dota2 数据源暂未接入，筛选时显示占位提示。
class EsportsController extends GetxController {
  final EsportsService _service = EsportsService();

  /// 游戏筛选：0=全部 1=英雄联盟 2=Dota2 3=CS 4=Valorant
  final RxInt gameFilter = 0.obs;

  /// 加载中
  final RxBool loading = false.obs;

  /// 错误信息（为空表示无错误；加载失败但至少一个数据源成功时为空）
  final RxString error = ''.obs;

  /// 赛事日程列表（CS + LOL 合并）
  final RxList<EsportsMatch> matches = <EsportsMatch>[].obs;

  /// 已加载的日期范围（用于页面标题展示）
  DateTime? loadedFrom;
  DateTime? loadedTo;

  /// 游戏筛选选项（key 与 i18n 对应）
  static const List<String> gameFilterKeys = [
    'esports_filter_all',
    'esports_filter_lol',
    'esports_filter_dota2',
    'esports_filter_cs',
    'esports_filter_valorant',
  ];

  /// 归一化游戏标识集合
  static const Map<int, String> _filterGameKeys = {
    1: 'lol',
    2: 'dota2',
    3: 'cs',
    4: 'valorant',
  };

  @override
  void onInit() {
    super.onInit();
    loadData();
  }

  /// 刷新数据（下拉刷新/重试）
  Future<void> loadData() async {
    if (loading.value) return;
    loading.value = true;
    error.value = '';
    try {
      final now = DateTime.now();
      final from = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
      final to = DateTime(now.year, now.month, now.day).add(const Duration(days: 8)).subtract(const Duration(seconds: 1));
      final list = await _service.fetchMatches(from: from, to: to);
      matches.assignAll(list);
      loadedFrom = from;
      loadedTo = to;
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

  /// 当前筛选下的赛事列表。
  /// Dota2（key=dota2）暂未接入数据源，恒为空列表。
  List<EsportsMatch> get filteredMatches {
    final key = _filterGameKeys[gameFilter.value];
    if (key == null) return matches;
    return matches.where((m) => m.gameKey == key).toList();
  }

  /// 当前筛选是否为 Dota2（用于页面显示"暂未接入"提示）
  bool get isDota2Filter => gameFilter.value == 2;

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
