/// 电竞赛事日程数据模型。
///
/// 支持两个数据源（归一化到统一字段）：
/// - 完美世界电竞（CS2）：`esports.wanmei.com` 接口，毫秒时间戳
/// - lolesports 官方（LOL）：`lolesports.com/schedule` 页面内嵌 JSON，ISO 时间
class EsportsMatch {
  /// 比赛唯一 ID（字符串形式，兼容 int/string 两种返回）
  final String matchId;

  /// 游戏名称（如：英雄联盟 / CS）
  final String gameName;

  /// 归一化游戏标识：lol / cs / dota2 / other
  final String gameKey;

  /// 联赛名称（如：英雄联盟职业联赛 / Esports World Cup）
  final String seriesName;

  /// 联赛简称（如：LPL / EWC-2026）
  final String seriesShortName;

  /// 比赛阶段（如：Week 12 / 常规赛）
  final String gameStage;

  /// 开赛时间（unix 秒，UTC）
  final int startTime;

  /// 结束时间（unix 秒，UTC，可能为 0）
  final int endTime;

  /// 状态：1=未开始 2=进行中 3=已结束（其余视为未知）
  final int status;

  /// A 队名称
  final String teamAName;

  /// A 队 Logo
  final String teamALogo;

  /// B 队名称
  final String teamBName;

  /// B 队 Logo
  final String teamBLogo;

  /// A 队当前比分（可能无）
  final int scoreA;

  /// B 队当前比分（可能无）
  final int scoreB;

  /// 关联直播间 ID（可能为空，当前版本未使用）
  final String roomId;

  /// 比赛标题（部分赛事只有标题没有对阵）
  final String matchName;

  const EsportsMatch({
    required this.matchId,
    required this.gameName,
    required this.gameKey,
    required this.seriesName,
    required this.seriesShortName,
    required this.gameStage,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.teamAName,
    required this.teamALogo,
    required this.teamBName,
    required this.teamBLogo,
    required this.scoreA,
    required this.scoreB,
    required this.roomId,
    required this.matchName,
  });

  /// 本地时区的开赛时间
  DateTime get startDateTime => DateTime.fromMillisecondsSinceEpoch(startTime * 1000);

  /// 是否已结束
  bool get isEnded => status == 3;

  /// 是否进行中
  bool get isLive => status == 2;

  /// 是否未开始
  bool get isUpcoming => status == 1;

  /// 是否包含有效对阵（双方队伍名至少一个非空）
  bool get hasTeams => teamAName.isNotEmpty || teamBName.isNotEmpty;

  /// 规范化队标 URL：明文 http 转 https（Android 默认禁明文 HTTP，且 https 均可用）
  static String normalizeLogoUrl(String url) {
    if (url.startsWith('http://')) {
      return 'https://${url.substring(7)}';
    }
    return url;
  }

  // ---------------------------------------------------------------------------
  // 完美世界电竞（CS2）解析
  // ---------------------------------------------------------------------------

  /// 从完美世界电竞 `getMatchList` 返回的 item 解析。
  /// 字段结构（实测）：csgoEventDTO(赛事)、team1DTO/team2DTO(队伍)、
  /// score1/score2(比分)、startTime/endTime(毫秒)、status、bo。
  factory EsportsMatch.fromWanmeiJson(Map<String, dynamic> item) {
    String str(dynamic v) => v == null ? '' : v.toString();
    int intVal(dynamic v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? 0 : 0);

    final Map<String, dynamic> event =
        item['csgoEventDTO'] is Map ? Map<String, dynamic>.from(item['csgoEventDTO'] as Map) : const {};
    final Map<String, dynamic> teamA =
        item['team1DTO'] is Map ? Map<String, dynamic>.from(item['team1DTO'] as Map) : const {};
    final Map<String, dynamic> teamB =
        item['team2DTO'] is Map ? Map<String, dynamic>.from(item['team2DTO'] as Map) : const {};

    // 毫秒时间戳 → 秒
    final int startMs = intVal(item['startTime']);
    final int endMs = intVal(item['endTime']);

    // 状态：完美世界 status 3=已结束；有比分且已过结束时间视为已结束
    int status = intVal(item['status']);
    final int scoreA = intVal(item['score1']);
    final int scoreB = intVal(item['score2']);
    final bool hasScore = scoreA > 0 || scoreB > 0;
    if (status == 3 || (hasScore && endMs > 0 && endMs < DateTime.now().millisecondsSinceEpoch)) {
      status = 3;
    } else if (status != 2 && status != 3) {
      status = 1;
    }

    // 赛事名优先中文
    final String eventNameZh = str(event['nameZh']);
    final String eventName = str(event['name']);
    final String seriesName = eventNameZh.isNotEmpty ? eventNameZh : eventName;

    String teamALogoUrl = str(teamA['logoWhite']);
    if (teamALogoUrl.isEmpty) teamALogoUrl = str(teamA['logoBlack']);
    String teamBLogoUrl = str(teamB['logoWhite']);
    if (teamBLogoUrl.isEmpty) teamBLogoUrl = str(teamB['logoBlack']);
    teamALogoUrl = EsportsMatch.normalizeLogoUrl(teamALogoUrl);
    teamBLogoUrl = EsportsMatch.normalizeLogoUrl(teamBLogoUrl);

    return EsportsMatch(
      matchId: str(item['matchId']),
      gameName: 'CS',
      gameKey: 'cs',
      seriesName: seriesName,
      seriesShortName: eventNameZh.isNotEmpty ? eventNameZh : eventName,
      gameStage: str(item['stageName'] ?? item['eventSubTypeName']),
      startTime: startMs > 0 ? startMs ~/ 1000 : 0,
      endTime: endMs > 0 ? endMs ~/ 1000 : 0,
      status: status,
      teamAName: str(teamA['name']),
      teamALogo: teamALogoUrl,
      teamBName: str(teamB['name']),
      teamBLogo: teamBLogoUrl,
      scoreA: scoreA,
      scoreB: scoreB,
      roomId: str(item['roomId'] ?? item['liveRoomInfo']),
      matchName: str(item['matchName'] ?? item['bo']),
    );
  }

  // ---------------------------------------------------------------------------
  // lolesports（LOL）解析
  // ---------------------------------------------------------------------------

  /// 从 Riot 系赛事官网（lolesports.com / valorantesports.com）页面内嵌的
  /// EventMatch JSON 解析。两个站点结构一致。
  /// 字段结构（实测）：blockName(阶段)、startTime(ISO)、state、league、
  /// tournament、matchTeams[{name, code, image, result.gameWins}]。
  /// [gameKey]/[gameName] 用于区分 LOL 与 Valorant。
  factory EsportsMatch.fromLolesportsJson(Map<String, dynamic> event, {String gameKey = 'lol', String gameName = '英雄联盟'}) {
    String str(dynamic v) => v == null ? '' : v.toString();

    final Map<String, dynamic> league =
        event['league'] is Map ? Map<String, dynamic>.from(event['league'] as Map) : const {};
    final Map<String, dynamic> tournament =
        event['tournament'] is Map ? Map<String, dynamic>.from(event['tournament'] as Map) : const {};
    final List<dynamic> teams = event['matchTeams'] is List ? event['matchTeams'] as List : const [];

    String teamAName = '';
    String teamALogo = '';
    String teamBName = '';
    String teamBLogo = '';
    int scoreA = 0;
    int scoreB = 0;
    if (teams.isNotEmpty) {
      final Map<String, dynamic> tA = teams[0] is Map ? Map<String, dynamic>.from(teams[0] as Map) : const {};
      teamAName = str(tA['name']);
      teamALogo = normalizeLogoUrl(str(tA['image']));
      final dynamic rA = tA['result'];
      if (rA is Map) {
        scoreA = rA['gameWins'] is num ? (rA['gameWins'] as num).toInt() : 0;
      }
    }
    if (teams.length > 1) {
      final Map<String, dynamic> tB = teams[1] is Map ? Map<String, dynamic>.from(teams[1] as Map) : const {};
      teamBName = str(tB['name']);
      teamBLogo = normalizeLogoUrl(str(tB['image']));
      final dynamic rB = tB['result'];
      if (rB is Map) {
        scoreB = rB['gameWins'] is num ? (rB['gameWins'] as num).toInt() : 0;
      }
    }

    // 状态映射：unstarted=1 live=2 completed=3
    int status = 1;
    switch (str(event['state'])) {
      case 'live':
        status = 2;
        break;
      case 'completed':
        status = 3;
        break;
    }

    final String leagueName = str(league['name']);
    final String tournamentName = str(tournament['name']);
    final String seriesName = tournamentName.isNotEmpty ? tournamentName : leagueName;

    return EsportsMatch(
      matchId: str(event['id']),
      gameName: gameName,
      gameKey: gameKey,
      seriesName: seriesName,
      seriesShortName: leagueName.isNotEmpty ? leagueName : seriesName,
      gameStage: str(event['blockName']),
      startTime: (DateTime.tryParse(str(event['startTime']))?.millisecondsSinceEpoch ?? 0) ~/ 1000,
      endTime: (DateTime.tryParse(str(event['endTime']))?.millisecondsSinceEpoch ?? 0) ~/ 1000,
      status: status,
      teamAName: teamAName,
      teamALogo: teamALogo,
      teamBName: teamBName,
      teamBLogo: teamBLogo,
      scoreA: scoreA,
      scoreB: scoreB,
      roomId: '',
      matchName: str(event['matchName']),
    );
  }
}
