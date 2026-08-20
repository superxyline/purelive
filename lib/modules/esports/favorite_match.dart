import 'esports_match.dart';

/// 被用户关注的赛事（用于通知栏到点提醒）。
class FavoriteMatch {
  final String matchId;
  final String gameKey; // cs / lol / valorant / dota2
  final int startTime; // unix 秒
  final String display;

  const FavoriteMatch({
    required this.matchId,
    required this.gameKey,
    required this.startTime,
    required this.display,
  });

  factory FavoriteMatch.fromEsportsMatch(EsportsMatch m) {
    final vs = m.teamAName.isNotEmpty && m.teamBName.isNotEmpty
        ? '${m.teamAName} vs ${m.teamBName}'
        : '';
    final title = vs.isNotEmpty
        ? vs
        : (m.seriesName.isNotEmpty ? m.seriesName : m.matchName);
    return FavoriteMatch(
      matchId: m.matchId,
      gameKey: m.gameKey,
      startTime: m.startTime,
      display: title.isEmpty ? m.gameName : title,
    );
  }

  bool get isCs => gameKey == 'cs';

  Map<String, dynamic> toJson() => {
        'matchId': matchId,
        'gameKey': gameKey,
        'startTime': startTime,
        'display': display,
      };

  factory FavoriteMatch.fromJson(Map<String, dynamic> json) => FavoriteMatch(
        matchId: json['matchId']?.toString() ?? '',
        gameKey: json['gameKey']?.toString() ?? 'other',
        startTime: json['startTime'] is num ? (json['startTime'] as num).toInt() : 0,
        display: json['display']?.toString() ?? '',
      );
}
