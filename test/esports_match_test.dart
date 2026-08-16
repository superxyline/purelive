import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:pure_live/modules/esports/esports_match.dart';
import 'package:pure_live/modules/esports/esports_service.dart';

void main() {
  group('EsportsMatch.fromWanmeiJson（完美世界 CS 数据源）', () {
    // 数据样本取自 2026-08-15 实测接口返回
    final Map<String, dynamic> item = {
      'bo': 'bo3',
      'matchId': 2396585,
      'matchType': 1,
      'score1': 2,
      'score2': 0,
      'startTime': 1786727700000,
      'endTime': 1786733968000,
      'status': 3,
      'csgoEventDTO': {
        'name': 'Esports World Cup 2026',
        'nameZh': 'EWC-2026',
        'prize': '\$2,000,000',
        'level': 'T1',
        'startTime': 1786528800000,
        'status': 1,
      },
      'team1DTO': {'name': 'PVISION', 'logoWhite': 'https://cdn.wmpvp.com/a.png'},
      'team2DTO': {'name': 'FaZe', 'logoWhite': 'https://cdn.wmpvp.com/b.png'},
    };

    test('解析赛事/队伍/比分/时间', () {
      final m = EsportsMatch.fromWanmeiJson(item);
      expect(m.gameKey, 'cs');
      expect(m.seriesName, 'EWC-2026');
      expect(m.seriesShortName, 'EWC-2026');
      expect(m.teamAName, 'PVISION');
      expect(m.teamBName, 'FaZe');
      expect(m.teamALogo, 'https://cdn.wmpvp.com/a.png');
      expect(m.scoreA, 2);
      expect(m.scoreB, 0);
      expect(m.matchId, '2396585');
    });

    test('毫秒时间戳转为秒', () {
      final m = EsportsMatch.fromWanmeiJson(item);
      expect(m.startTime, 1786727700);
      expect(m.endTime, 1786733968);
    });

    test('status=3 映射为已结束', () {
      final m = EsportsMatch.fromWanmeiJson(item);
      expect(m.isEnded, true);
      expect(m.isLive, false);
      expect(m.isUpcoming, false);
    });

    test('已过结束时间且有比分视为已结束', () {
      final data = Map<String, dynamic>.from(item);
      data['status'] = 2; // 状态不明
      data['endTime'] = DateTime.now().millisecondsSinceEpoch - 60000; // 已过去
      final m = EsportsMatch.fromWanmeiJson(data);
      expect(m.isEnded, true);
    });

    test('字段缺失容错不崩溃', () {
      final m = EsportsMatch.fromWanmeiJson(const {});
      expect(m.gameKey, 'cs');
      expect(m.teamAName, '');
      expect(m.startTime, 0);
      expect(m.matchId, '');
    });
  });

  group('EsportsMatch.fromLolesportsJson（lolesports LOL 数据源）', () {
    // 数据样本取自 2026-08-16 实测页面内嵌 JSON
    final Map<String, dynamic> event = {
      '__typename': 'EventMatch',
      'id': '116889604984157289',
      'blockName': 'Week 12',
      'startTime': '2026-08-16T03:00:00Z',
      'state': 'unstarted',
      'type': 'match',
      'league': {'__typename': 'League', 'id': '1', 'name': 'LCK Challengers', 'slug': 'lck_challengers_league'},
      'tournament': {'__typename': 'Tournament', 'id': '2', 'name': 'Split 3 2026'},
      'matchTeams': [
        {
          'name': 'T1 Esports Academy',
          'image': 'http://static.lolesports.com/teams/t1.png',
          'code': 'T1A',
          'result': {'gameWins': 0, 'outcome': null},
        },
        {
          'name': 'DNS Challengers',
          'image': 'http://static.lolesports.com/teams/dns.png',
          'code': 'DNS',
          'result': {'gameWins': 0, 'outcome': null},
        },
      ],
    };

    test('解析联赛/队伍/时间/状态', () {
      final m = EsportsMatch.fromLolesportsJson(event);
      expect(m.gameKey, 'lol');
      expect(m.seriesName, 'Split 3 2026');
      expect(m.seriesShortName, 'LCK Challengers');
      expect(m.gameStage, 'Week 12');
      expect(m.teamAName, 'T1 Esports Academy');
      expect(m.teamBName, 'DNS Challengers');
      expect(m.teamALogo, 'http://static.lolesports.com/teams/t1.png');
      expect(m.isUpcoming, true);
    });

    test('ISO 时间转为秒', () {
      final m = EsportsMatch.fromLolesportsJson(event);
      expect(m.startTime, DateTime.utc(2026, 8, 16, 3, 0).millisecondsSinceEpoch ~/ 1000);
    });

    test('completed 映射为已结束并解析 gameWins 比分', () {
      final data = jsonDecode(jsonEncode(event)) as Map<String, dynamic>;
      data['state'] = 'completed';
      (data['matchTeams'] as List)[0]['result'] = {'gameWins': 2, 'outcome': 'win'};
      (data['matchTeams'] as List)[1]['result'] = {'gameWins': 1, 'outcome': 'loss'};
      final m = EsportsMatch.fromLolesportsJson(data);
      expect(m.isEnded, true);
      expect(m.scoreA, 2);
      expect(m.scoreB, 1);
    });

    test('live 映射为进行中', () {
      final data = jsonDecode(jsonEncode(event)) as Map<String, dynamic>;
      data['state'] = 'live';
      final m = EsportsMatch.fromLolesportsJson(data);
      expect(m.isLive, true);
    });

    test('Valorant 用同构解析器（gameKey=valorant）', () {
      final data = jsonDecode(jsonEncode(event)) as Map<String, dynamic>;
      data['league'] = {'name': 'Game Changers EMEA'};
      data['blockName'] = 'Playoffs';
      final m = EsportsMatch.fromLolesportsJson(data, gameKey: 'valorant', gameName: 'Valorant');
      expect(m.gameKey, 'valorant');
      expect(m.gameName, 'Valorant');
      expect(m.seriesShortName, 'Game Changers EMEA');
      expect(m.gameStage, 'Playoffs');
    });
  });

  group('EsportsService.extractRiotEvents（HTML 提取）', () {
    test('从 HTML 提取 EventMatch 数据块', () {
      // 模拟真实 lolesports/valorantesports 页面：数据块以未转义 JSON 形式内嵌
      final html = '<html><body>'
          '<div>{"__typename":"Split","id":"1"}</div>'
          '{"EsportsData","events":['
          '{"__typename":"EventMatch","id":"111","startTime":"2026-08-16T03:00:00Z",'
          '"state":"unstarted","league":{"name":"LPL"},"tournament":{"name":"Split"},'
          '"matchTeams":[{"name":"A","result":{"gameWins":0}},{"name":"B","result":{"gameWins":0}}]},'
          '{"__typename":"Other","id":"222"}'
          ']}'
          '</body></html>';
      final service = EsportsService();
      final events = service.extractRiotEvents(html);
      expect(events, hasLength(1));
      expect(events.first['id'], '111');
      expect(events.first['league'], isA<Map>());
    });

    test('findJsonArrayEnd 正确处理嵌套与字符串', () {
      final service = EsportsService();
      const html = r'''prefix [{"a":"[b]","c":["d","e"]},{"f":1}] suffix''';
      final end = service.findJsonArrayEnd(html, html.indexOf('['));
      expect(html[end], ']');
      final json = jsonDecode(html.substring(html.indexOf('['), end + 1));
      expect(json, hasLength(2));
    });
  });
}
