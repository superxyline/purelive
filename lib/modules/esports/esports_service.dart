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
/// - **DOTA2**：超凡电竞 `api-m.chaofan.com`
///   `GET /api/v1/tournament/list`（赛事）→ `GET /api/v1/tournament/match`（比赛）
///   无鉴权、无签名（2026-11 实测）
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

  // ---------------------------------------------------------------------------
  // 超凡电竞（DOTA2）
  // ---------------------------------------------------------------------------

  static const String kChaofanApiRoot = 'https://api-m.chaofan.com';
  static const int kChaofanDota2GameId = 3;

  /// 拉取 [from]（含）到 [to]（含）之间的 DOTA2 赛程。
  ///
  /// 该站没有「全局比赛列表」接口，只有赛事级：先按状态拉赛事列表，
  /// 再逐个赛事拉比赛（`tournament/match`），客户端按 start_time 裁到目标区间。
  ///
  /// - 状态 1=即将开赛、2=进行中；已结束的场次会混在进行中的赛事里，
  ///   所以这两个状态合起来就覆盖了「今天 ~ +N 天」需要的全部数据
  ///   （status=3 是 1000+ 个历史赛事，拉不动也不必要）。
  /// - 赛事数很少，两级请求无需分页。
  /// - 接口无鉴权、不校验 Referer/Origin（2026-11 实测），只需常规 UA。
  Future<List<EsportsMatch>> fetchDota2Matches({required DateTime from, required DateTime to}) async {
    final int fromSec = from.millisecondsSinceEpoch ~/ 1000;
    final int toSec = to.millisecondsSinceEpoch ~/ 1000;

    // 赛事元数据：id → (logo, title)，供 match 补齐赛事 logo / 名称
    final Map<String, ({String logo, String title})> tournaments = {};
    for (final status in const [1, 2]) {
      try {
        final list = await _fetchChaofanTournaments(status: status);
        for (final t in list) {
          tournaments[t.id] = (logo: t.logo, title: t.title);
        }
      } catch (_) {
        // 单个状态失败不影响另一个状态
      }
    }
    if (tournaments.isEmpty) return const [];

    final List<EsportsMatch> all = [];
    final entries = tournaments.entries.toList();
    const int concurrency = 5;
    for (int i = 0; i < entries.length; i += concurrency) {
      final chunk = entries.sublist(i, min(i + concurrency, entries.length));
      final results = await Future.wait(
        chunk.map((e) async {
          try {
            return await _fetchChaofanMatches(e.key);
          } catch (_) {
            return const <Map<String, dynamic>>[];
          }
        }),
      );
      for (int j = 0; j < chunk.length; j++) {
        final meta = chunk[j].value;
        for (final item in results[j]) {
          final match = EsportsMatch.fromChaofanJson(
            item,
            seriesLogo: meta.logo,
            seriesName: meta.title,
          );
          if (match.startTime == 0) continue;
          // 客户端按日期裁剪：该接口按"赛事"返回，不含日期参数
          if (match.startTime < fromSec || match.startTime > toSec) continue;
          all.add(match);
        }
      }
    }

    // 同一场比赛可能同时出现在"即将开赛"和"进行中"两个列表里
    final Set<String> seen = {};
    all.removeWhere((m) => m.matchId.isNotEmpty && !seen.add(m.matchId));
    all.sort((a, b) => a.startTime.compareTo(b.startTime));
    return all;
  }

  Future<List<({String id, String title, String logo})>> _fetchChaofanTournaments({
    required int status,
  }) async {
    final out = <({String id, String title, String logo})>[];
    final seen = <String>{};
    // 🔴 首轮请求**不带 date**：该参数会把 start_time 早于 date 的赛事整个
    // 过滤掉——进行中的长周期赛事（BLAST 擂台赛 11-07 开赛、梦幻联赛 30 季
    // 11-14 开赛）全部被挡，2026-11-28 实测 status=2 带 date 只回 3/5 个赛事
    // （这就是"网页能看到 BLAST 擂台赛、App 看不到"的根因）。
    // 翻页游标用响应里的 down_time（时间戳，<=0 表示没有下一页）。
    int? cursor;
    // 赛事数很少，最多翻 3 页足够，避免异常返回把请求量拉爆。
    for (int page = 0; page < 3; page++) {
      final result = await HttpClient.instance.getJson(
        '$kChaofanApiRoot/api/v1/tournament/list',
        queryParameters: {
          'game_id': kChaofanDota2GameId,
          'status': status,
          'date': ?cursor,
        },
        header: {
          'user-agent': kUserAgent,
          'accept': 'application/json, text/plain, */*',
        },
      );
      if (result is! Map<String, dynamic> || result['code'] != 0) break;
      final data = result['data'];
      if (data is! Map<String, dynamic>) break;
      final list = data['list'];
      if (list is! List) break;

      for (final item in list) {
        if (item is! Map) continue;
        final id = item['id']?.toString() ?? '';
        if (id.isEmpty || !seen.add(id)) continue;
        out.add((
          id: id,
          title: item['title']?.toString() ?? '',
          logo: item['logo']?.toString() ?? '',
        ));
      }

      final downTime = data['down_time'];
      final allCounts = data['all_counts'];
      final int down = downTime is num ? downTime.toInt() : -1;
      final int total = allCounts is num ? allCounts.toInt() : 0;
      if (down <= 0) break;
      if (total > 0 && out.length >= total) break;
      cursor = down;
    }
    return out;
  }

  Future<List<Map<String, dynamic>>> _fetchChaofanMatches(String tournamentId) async {
    final result = await HttpClient.instance.getJson(
      '$kChaofanApiRoot/api/v1/tournament/match',
      queryParameters: {'tournament_id': tournamentId},
      header: {
        'user-agent': kUserAgent,
        'accept': 'application/json, text/plain, */*',
      },
    );
    if (result is! Map<String, dynamic> || result['code'] != 0) return const [];
    final data = result['data'];
    if (data is! Map<String, dynamic>) return const [];
    final list = data['list'];
    if (list is! List) return const [];
    final out = <Map<String, dynamic>>[];
    for (final item in list) {
      if (item is Map<String, dynamic>) out.add(item);
    }
    return out;
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

  /// 拉取 [from]（含）到 [to]（含）之间的全部赛事（CS + LOL + Valorant + DOTA2）。
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
    try {
      all.addAll(await fetchDota2Matches(from: from, to: to));
    } catch (_) {}
    all.sort((a, b) => a.startTime.compareTo(b.startTime));
    return all;
  }
}
