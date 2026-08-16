import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/modules/esports/esports_match.dart';

/// 电竞赛事数据服务（多数据源）。
///
/// - **CS（CS2）**：完美世界电竞数据中心 `esports.wanmei.com`
///   `GET /apg/eventcenter/csgo/getMatchList?matchTime=YYYY-MM-DD HH:mm:ss`
///   需要 HMAC-SHA256 签名（密钥与规范化规则为 2026-08 实测逆向结果）
/// - **LOL（英雄联盟）/ Valorant（瓦罗兰特）**：Riot 系赛事官网
///   `lolesports.com/schedule` / `valorantesports.com/schedule`
///   页面 HTML 内嵌完整赛程 JSON（两站结构一致，官方 API 公开 key 已失效，改走页面数据）
///
/// Dota2 数据源暂未接入（完美世界 web 端无 Dota2 赛事接口，待后续方案）。
class EsportsService {
  // ---------------------------------------------------------------------------
  // 完美世界电竞（CS）
  // ---------------------------------------------------------------------------

  static const String kWanmeiHost = 'https://esports.wanmei.com';
  static const String kWanmeiMatchListPath = '/apg/eventcenter/csgo/getMatchList';

  /// HMAC 签名密钥（逆向自 data.wanmei.com 前端 JS，2026-08 实测有效）
  static const String kWanmeiHmacKey = '828a59393861babc4a27e23f87fc77ab8dc9347dc6550c5e7e51e9b1af2de812';

  static const String kUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36';
  static const String kWanmeiReferer = 'https://data.wanmei.com/';

  /// 拉取 [from]（含）到 [to]（含）之间的 CS 赛事（按天查询，每天一次请求）。
  Future<List<EsportsMatch>> fetchCsMatches({required DateTime from, required DateTime to}) async {
    final List<EsportsMatch> all = [];
    final int days = to.difference(from).inDays + 1;
    for (int i = 0; i < days; i++) {
      final day = from.add(Duration(days: i));
      final String matchTime =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')} 00:00:00';
      try {
        final list = await _fetchWanmeiDay(matchTime);
        all.addAll(list);
      } catch (_) {
        // 单天失败不中断，继续其他天
      }
    }
    all.sort((a, b) => a.startTime.compareTo(b.startTime));
    return all;
  }

  Future<List<EsportsMatch>> _fetchWanmeiDay(String matchTime) async {
    final params = <String, dynamic>{'matchTime': matchTime};
    final sign = _wanmeiSign(params);
    final result = await HttpClient.instance.getJson(
      '$kWanmeiHost$kWanmeiMatchListPath',
      queryParameters: params,
      header: {
        'user-agent': kUserAgent,
        'referer': kWanmeiReferer,
        'accept': 'application/json, text/plain, */*',
        'X-Timestamp': sign.timestamp,
        'X-Nonce': sign.nonce,
        'X-Signature': sign.signature,
      },
    );
    if (result is! Map<String, dynamic> || result['code'] != 0) {
      return [];
    }
    final matchResponse = result['result'];
    if (matchResponse is! Map<String, dynamic>) return [];
    final raw = matchResponse['matchResponse'];
    if (raw is! Map<String, dynamic>) return [];
    final dtoList = raw['dtoList'];
    if (dtoList is! List) return [];

    final List<EsportsMatch> list = [];
    for (final item in dtoList) {
      if (item is! Map<String, dynamic>) continue;
      final match = EsportsMatch.fromWanmeiJson(item);
      if (match.startTime > 0 && (match.hasTeams || match.matchName.isNotEmpty)) {
        list.add(match);
      }
    }
    return list;
  }

  /// 完美世界 HMAC 签名（逆向自前端 `Wp/Yp/Nl/$p` 逻辑，实测有效）：
  /// 1. 参数值转字符串、加入 timestamp/nonce
  /// 2. 按 key 排序、同 key 值排序，拼 `key=value&...`（空格编码为 `+`）
  /// 3. `X-Signature = HmacSHA256(规范化串, 固定密钥)`
  ({String timestamp, String nonce, String signature}) _wanmeiSign(Map<String, dynamic> params) {
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final random = Random.secure();
    final nonce =
        List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

    String qo(String e) => Uri.encodeComponent(e).replaceAll('%20', '+');

    final n = <String, List<String>>{};
    params.forEach((k, v) => n[k.toString()] = [v.toString()]);
    n['timestamp'] = [timestamp];
    n['nonce'] = [nonce];
    final keys = n.keys.toList()..sort();
    final parts = <String>[];
    for (final key in keys) {
      final vals = List<String>.from(n[key]!)..sort();
      for (final v in vals) {
        parts.add('${qo(key)}=${qo(v)}');
      }
    }
    final normalized = parts.join('&');
    final hmac = Hmac(sha256, utf8.encode(kWanmeiHmacKey));
    final signature = hmac.convert(utf8.encode(normalized)).toString();
    return (timestamp: timestamp, nonce: nonce, signature: signature);
  }

  // ---------------------------------------------------------------------------
  // lolesports（LOL）
  // ---------------------------------------------------------------------------

  static const String kLolesportsScheduleUrl = 'https://lolesports.com/schedule';
  static const String kValorantScheduleUrl = 'https://valorantesports.com/schedule';

  /// 抓取 Riot 系赛事官网赛程页并解析内嵌的 EventMatch JSON。
  /// 页面数据覆盖"当前周"的比赛（含已结束与未开始）。
  /// [gameKey]/[gameName] 区分 LOL 与 Valorant（两站结构一致）。
  Future<List<EsportsMatch>> fetchRiotMatches({
    required String url,
    required String gameKey,
    required String gameName,
  }) async {
    final String html = await HttpClient.instance.getText(
      url,
      header: {
        'user-agent': kUserAgent,
        'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      },
    );
    final List<EsportsMatch> all = [];
    final List<Map<String, dynamic>> events = extractRiotEvents(html);
    for (final event in events) {
      final match = EsportsMatch.fromLolesportsJson(event, gameKey: gameKey, gameName: gameName);
      if (match.startTime > 0) {
        all.add(match);
      }
    }
    all.sort((a, b) => a.startTime.compareTo(b.startTime));
    return all;
  }

  /// LOL（英雄联盟）赛程
  Future<List<EsportsMatch>> fetchLolMatches({required DateTime from, required DateTime to}) {
    return fetchRiotMatches(url: kLolesportsScheduleUrl, gameKey: 'lol', gameName: '英雄联盟');
  }

  /// Valorant（瓦罗兰特）赛程
  Future<List<EsportsMatch>> fetchValorantMatches({required DateTime from, required DateTime to}) {
    return fetchRiotMatches(url: kValorantScheduleUrl, gameKey: 'valorant', gameName: 'Valorant');
  }

  /// 从 Riot 系官网页面 HTML 提取所有 `"EsportsData","events":[...]` JSON 块并合并。
  /// 页面为 Next.js 服务端渲染，数据块可能分散在多个位置，逐块提取。
  /// 公开以便单元测试（不依赖网络）。
  List<Map<String, dynamic>> extractRiotEvents(String html) {
    const marker = '"EsportsData","events":[';
    final List<Map<String, dynamic>> all = [];
    int searchFrom = 0;
    while (true) {
      final idx = html.indexOf(marker, searchFrom);
      if (idx < 0) break;
      final start = html.indexOf('[', idx);
      if (start < 0) break;
      final end = findJsonArrayEnd(html, start);
      if (end < 0) break;
      try {
        final dynamic data = jsonDecode(html.substring(start, end + 1));
        if (data is List) {
          for (final item in data) {
            if (item is Map<String, dynamic> && item['__typename'] == 'EventMatch') {
              all.add(item);
            }
          }
        }
      } catch (_) {
        // 单块解析失败跳过
      }
      searchFrom = end + 1;
    }
    return all;
  }

  /// 从 [start]（指向 `[`）做括号深度匹配，返回数组结束的 `]` 下标（含字符串与转义处理）。
  /// 公开以便单元测试。
  int findJsonArrayEnd(String html, int start) {
    int depth = 0;
    bool inString = false;
    bool escaped = false;
    for (int i = start; i < html.length; i++) {
      final ch = html[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == r'\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
      } else {
        if (ch == '"') {
          inString = true;
        } else if (ch == '[') {
          depth++;
        } else if (ch == ']') {
          depth--;
          if (depth == 0) return i;
        }
      }
    }
    return -1;
  }

  // ---------------------------------------------------------------------------
  // 聚合入口
  // ---------------------------------------------------------------------------

  /// 拉取 [from]（含）到 [to]（含）之间的全部赛事（CS + LOL + Valorant）。
  /// 各源独立容错：单个数据源失败不影响其他源。
  Future<List<EsportsMatch>> fetchMatches({required DateTime from, required DateTime to}) async {
    final List<EsportsMatch> all = [];
    try {
      all.addAll(await fetchCsMatches(from: from, to: to));
    } catch (_) {}
    try {
      all.addAll(await fetchLolMatches(from: from, to: to));
    } catch (_) {}
    try {
      all.addAll(await fetchValorantMatches(from: from, to: to));
    } catch (_) {}
    all.sort((a, b) => a.startTime.compareTo(b.startTime));
    return all;
  }
}
