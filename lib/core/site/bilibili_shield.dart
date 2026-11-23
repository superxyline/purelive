import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/site/bilibili_site.dart';

/// 官方屏蔽用户条目（uid + 昵称，来自 getInfoByUser.shield_info.shield_user_list）
class ShieldUserInfo {
  final int uid;
  final String uname;

  const ShieldUserInfo({required this.uid, required this.uname});

  factory ShieldUserInfo.fromJson(Map json) => ShieldUserInfo(
        uid: (json["uid"] as num?)?.toInt() ?? 0,
        uname: json["uname"]?.toString() ?? "",
      );
}

/// B 站官方直播弹幕屏蔽接口（账号级数据，云端为唯一数据源，本地只存快照）。
/// 参考实现：PiliPlus lib/http/live.dart 的 getLiveInfoByUser / addShieldKeyword / delShieldKeyword。
/// 写接口全部依赖登录 cookie 中的 bili_jct（csrf），未登录时调用方应先检查 [hasShieldCredentials]。
extension BilibiliShieldApi on BiliBiliSite {
  /// 拉取账号级屏蔽列表时使用的参考房间号（getInfoByUser 必须带 room_id，
  /// 但列表本身是账号级的，任意有效房间均可；取 B 站官方直播间）。
  static const int kShieldRefRoomId = 21449164;

  String get _csrf => RegExp(r'bili_jct=([^;]+)').firstMatch(cookie)?.group(1) ?? '';

  /// 写接口（增删关键词）是否可用：依赖登录 cookie
  bool get hasShieldCredentials => _csrf.isNotEmpty;

  /// 拉取官方屏蔽关键词与屏蔽用户列表。
  /// 返回 (是否成功, 消息, 关键词列表, 屏蔽用户列表)。
  Future<(bool, String, List<String>, List<ShieldUserInfo>)> fetchShieldInfo({int? roomId}) async {
    try {
      if (!hasShieldCredentials) {
        return (false, '请先在设置中登录B站账号', const <String>[], const <ShieldUserInfo>[]);
      }
      const baseUrl = "https://api.live.bilibili.com/xlive/web-room/v1/index/getInfoByUser";
      final signed = await getWbiSign(
        "$baseUrl?room_id=${roomId ?? kShieldRefRoomId}&from=0&not_mock_enter_effect=1&web_location=444.8",
      );
      final result = await HttpClient.instance.getJson(baseUrl, queryParameters: signed, header: await getHeader());
      if (result["code"] != 0) {
        return (
          false,
          result["message"]?.toString() ?? '拉取失败（code=${result["code"]}）',
          const <String>[],
          const <ShieldUserInfo>[],
        );
      }
      final shieldInfo = result["data"]?["shield_info"];
      final keywords = ((shieldInfo?["keyword_list"] as List?) ?? const [])
          .map((e) => e.toString())
          .where((e) => e.isNotEmpty)
          .toList();
      final users = ((shieldInfo?["shield_user_list"] as List?) ?? const [])
          .whereType<Map>()
          .map(ShieldUserInfo.fromJson)
          .toList();
      return (true, '拉取成功', keywords, users);
    } catch (e) {
      return (false, '拉取失败：$e', const <String>[], const <ShieldUserInfo>[]);
    }
  }

  /// 拉取并写入本地快照（互动体验页与管理页共用入口）。
  /// 返回 (是否成功, 消息, 关键词数, 屏蔽用户数)。
  Future<(bool, String, int, int)> fetchAndSaveShieldSnapshot({int? roomId}) async {
    final (ok, msg, keywords, users) = await fetchShieldInfo(roomId: roomId);
    if (!ok) return (ok, msg, 0, 0);
    final dm = SettingsService.to.danmaku;
    dm.officialShieldKeywords
      ..clear()
      ..addAll(keywords);
    dm.officialShieldUsers
      ..clear()
      ..addAll(users.map((u) => '${u.uid}|${u.uname}'));
    dm.lastOfficialShieldFetch.v = DateTime.now().millisecondsSinceEpoch;
    return (true, msg, keywords.length, users.length);
  }

  /// 添加屏蔽关键词（同步到 B 站云端）
  Future<(bool, String)> addShieldKeyword(String keyword) => _postShieldKeyword(
        "https://api.live.bilibili.com/xlive/web-ucenter/v1/banned/AddShieldKeyword",
        keyword,
      );

  /// 删除屏蔽关键词（同步到 B 站云端）
  Future<(bool, String)> delShieldKeyword(String keyword) => _postShieldKeyword(
        "https://api.live.bilibili.com/xlive/web-ucenter/v1/banned/DelShieldKeyword",
        keyword,
      );

  Future<(bool, String)> _postShieldKeyword(String url, String keyword) async {
    try {
      final csrf = _csrf;
      if (csrf.isEmpty) {
        return (false, '请先在设置中登录B站账号');
      }
      final result = await HttpClient.instance.postJson(
        url,
        header: await getHeader(),
        data: {
          'keyword': keyword,
          'csrf': csrf,
          'csrf_token': csrf,
        },
        formUrlEncoded: true,
      );
      if (result["code"] == 0) {
        return (true, '操作成功');
      }
      return (false, result["message"]?.toString() ?? '操作失败（code=${result["code"]}）');
    } catch (e) {
      return (false, '操作失败：$e');
    }
  }
}
