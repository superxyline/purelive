import 'package:pure_live/common/index.dart';
import 'favorite_match.dart';

/// 关注的赛事（Hive 持久化，赛事页星标 + 后台到点提醒共用）。
class FavoriteMatchController extends GetxController {
  final Rx<List<FavoriteMatch>> favoriteMatches = hiveObject(
    'favoriteMatches',
    <FavoriteMatch>[],
    fromJson: (json) => List<FavoriteMatch>.from(
        (json['list'] ?? []).map((e) => FavoriteMatch.fromJson(e))),
    toJson: (list) => {'list': list.map((e) => e.toJson()).toList()},
  );

  bool isFavorite(String matchId) =>
      favoriteMatches.v.any((e) => e.matchId == matchId);

  Set<String> get favoriteMatchIds =>
      favoriteMatches.v.map((e) => e.matchId).toSet();

  /// 切换关注，返回是否已关注
  bool toggle(FavoriteMatch match) {
    final list = List<FavoriteMatch>.from(favoriteMatches.v);
    final idx = list.indexWhere((e) => e.matchId == match.matchId);
    if (idx >= 0) {
      list.removeAt(idx);
      favoriteMatches.v = list;
      return false;
    }
    list.add(match);
    favoriteMatches.v = list;
    return true;
  }
}
