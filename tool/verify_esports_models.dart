// 精简验证脚本：只验证纯 Dart 的 EsportsMatch 解析器（不触发任何 native hooks/FFI 依赖）
// 运行：dart --packages=.dart_tool/package_config.json tool/verify_esports_models.dart
import 'dart:convert';
import 'package:pure_live/modules/esports/esports_match.dart';

int _failures = 0;
void check(String name, bool cond, [String? detail]) {
  if (cond) {
    print('  PASS: $name');
  } else {
    _failures++;
    print('  FAIL: $name ${detail ?? ''}');
  }
}

void main() {
  print('=== 完美世界 CS 解析器 ===');
  final wanmeiItem = {
    'bo': 'bo3',
    'matchId': 2396585,
    'score1': 2,
    'score2': 0,
    'startTime': 1786727700000,
    'endTime': 1786733968000,
    'status': 3,
    'csgoEventDTO': {'name': 'Esports World Cup 2026', 'nameZh': 'EWC-2026', 'level': 'T1'},
    'team1DTO': {'name': 'PVISION', 'logoWhite': 'https://cdn.wmpvp.com/a.png'},
    'team2DTO': {'name': 'FaZe', 'logoWhite': 'https://cdn.wmpvp.com/b.png'},
  };
  final cs = EsportsMatch.fromWanmeiJson(wanmeiItem);
  check('gameKey=cs', cs.gameKey == 'cs');
  check('seriesName=EWC-2026', cs.seriesName == 'EWC-2026', cs.seriesName);
  check('teamA=PVISION', cs.teamAName == 'PVISION', cs.teamAName);
  check('score 2:0', cs.scoreA == 2 && cs.scoreB == 0);
  check('毫秒→秒', cs.startTime == 1786727700, '${cs.startTime}');
  check('status=3 isEnded', cs.isEnded);
  check('logo 优先 logoWhite', cs.teamALogo == 'https://cdn.wmpvp.com/a.png');
  final csEmpty = EsportsMatch.fromWanmeiJson(const {});
  check('空字段容错', csEmpty.teamAName == '' && csEmpty.startTime == 0 && csEmpty.matchId == '');

  print('=== lolesports LOL 解析器 ===');
  final lolEvent = {
    '__typename': 'EventMatch',
    'id': '116889604984157289',
    'blockName': 'Week 12',
    'startTime': '2026-08-16T03:00:00Z',
    'state': 'unstarted',
    'league': {'name': 'LCK Challengers', 'slug': 'lck_challengers_league'},
    'tournament': {'name': 'Split 3 2026'},
    'matchTeams': [
      {'name': 'T1 Esports Academy', 'image': 'http://static.lolesports.com/teams/t1.png', 'result': {'gameWins': 0}},
      {'name': 'DNS Challengers', 'image': 'http://static.lolesports.com/teams/dns.png', 'result': {'gameWins': 0}},
    ],
  };
  final lol = EsportsMatch.fromLolesportsJson(lolEvent);
  check('gameKey=lol', lol.gameKey == 'lol');
  check('seriesName=Split 3 2026', lol.seriesName == 'Split 3 2026', lol.seriesName);
  check('seriesShort=LCK Challengers', lol.seriesShortName == 'LCK Challengers');
  check('stage=Week 12', lol.gameStage == 'Week 12');
  check('teamA', lol.teamAName == 'T1 Esports Academy');
  check('isUpcoming', lol.isUpcoming);
  check('ISO→秒', lol.startTime == DateTime.utc(2026, 8, 16, 3, 0).millisecondsSinceEpoch ~/ 1000, '${lol.startTime}');

  final lolDone = jsonDecode(jsonEncode(lolEvent)) as Map<String, dynamic>;
  lolDone['state'] = 'completed';
  (lolDone['matchTeams'] as List)[0]['result'] = {'gameWins': 2};
  (lolDone['matchTeams'] as List)[1]['result'] = {'gameWins': 1};
  final lolDoneMatch = EsportsMatch.fromLolesportsJson(lolDone);
  check('completed→isEnded', lolDoneMatch.isEnded);
  check('gameWins 比分 2:1', lolDoneMatch.scoreA == 2 && lolDoneMatch.scoreB == 1);

  print('=== Valorant 解析（同 Riot 结构） ===');
  final valEvent = jsonDecode(jsonEncode(lolEvent)) as Map<String, dynamic>;
  valEvent['league'] = {'name': 'Game Changers EMEA'};
  valEvent['blockName'] = 'Playoffs';
  final val = EsportsMatch.fromLolesportsJson(valEvent, gameKey: 'valorant', gameName: 'Valorant');
  check('gameKey=valorant', val.gameKey == 'valorant');
  check('gameName=Valorant', val.gameName == 'Valorant');
  check('league=Game Changers EMEA', val.seriesShortName == 'Game Changers EMEA');
  check('stage=Playoffs', val.gameStage == 'Playoffs');
  check('队伍复用', val.teamAName == 'T1 Esports Academy');

  print('');
  print(_failures == 0 ? 'ALL MODEL TESTS PASSED' : '$_failures TEST(S) FAILED');
}
