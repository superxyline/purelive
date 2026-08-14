import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/utils/utils.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/core/tars/huya_follow_structs.dart';
import 'package:pure_live/core/tars/huya_user_id.dart';
import 'package:pure_live/pkg/tars/net/base_tars_http.dart';

/// 关注同步结果
class FollowSyncResult {
  final String platform;
  final int total;
  final int added;
  final int existed;
  final int failed;
  final int filtered;
  final String? error;

  const FollowSyncResult({
    required this.platform,
    this.total = 0,
    this.added = 0,
    this.existed = 0,
    this.failed = 0,
    this.filtered = 0,
    this.error,
  });

  bool get success => error == null;
}

/// 各平台关注列表同步（B站 / 斗鱼 / 虎牙）
class FollowSyncService {
  FollowSyncService._();

  static const String _webUa =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

  /// 斗鱼头像前缀
  static const String _douyuAvatarPrefix = "https://apic.douyucdn.cn/upload/";

  /// 虎牙网页端 UA
  static const String _huyaUa = "webh5&0.1.0&websocket";

  /// 虎牙一次同步最多处理的主播数（TAF 逐条查询，限制数量避免超时）
  static const int _huyaMaxProcess = 60;

  // ---------------- B站 ----------------
  static Future<FollowSyncResult> syncBilibili() async {
    final cookie = SettingsService.to.cookieManager.bilibiliCookie.v;
    final uid = SettingsService.to.cookieManager.bilibiliUid.v;
    if (cookie.isEmpty || uid <= 0) {
      return const FollowSyncResult(
        platform: Sites.bilibiliSite,
        error: "not_login",
      );
    }

    final rooms = <LiveRoom>[];
    var failed = 0;
    var filtered = 0;
    try {
      // B站"我的关注"接口返回每个关注主播的上次直播结束时间，
      // 用于过滤掉一周内未直播过的主播（拉取失败时降级为不过滤）。
      final lastLiveMap = await _bilibiliLastLiveMap(cookie);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      const weekSeconds = 7 * 24 * 60 * 60;
      var page = 1;
      while (true) {
        final result = await HttpClient.instance.getJson(
          "https://api.bilibili.com/x/relation/followings",
          queryParameters: {
            "vmid": uid,
            "pn": page,
            "ps": 50,
            "order": "desc",
            "order_type": "attention",
          },
          header: {
            "cookie": cookie,
            "user-agent": _webUa,
            "referer": "https://space.bilibili.com/",
          },
        );
        if (result == null || result["code"] != 0) {
          return FollowSyncResult(
            platform: Sites.bilibiliSite,
            error: result?["message"]?.toString() ?? "api_error",
          );
        }
        final list = (result["data"]?["list"] as List?) ?? [];
        if (list.isEmpty) break;

        final mids = list
            .map((e) => e["mid"]?.toString() ?? "")
            .where((m) => m.isNotEmpty && m != "0")
            .toList();
        if (mids.isNotEmpty) {
          final roomMap = await _bilibiliRoomBaseInfo(mids, cookie);
          for (final item in list) {
            final mid = item["mid"]?.toString() ?? "";
            final lastLive = lastLiveMap[mid];
            if (lastLive != null) {
              final hasStreamedThisWeek =
                  lastLive.liveStatus == 1 ||
                  (lastLive.recordLiveTime > 0 &&
                      now - lastLive.recordLiveTime <= weekSeconds);
              if (!hasStreamedThisWeek) {
                filtered++;
                continue;
              }
            }
            final info = roomMap[mid];
            if (info == null || (info["room_id"] ?? 0).toString() == "0") {
              failed++;
              continue;
            }
            final live = (info["live_status"] ?? 0).toString() == "1";
            rooms.add(
              LiveRoom(
                roomId: info["room_id"].toString(),
                userId: mid,
                nick: item["uname"]?.toString() ?? "",
                avatar: item["face"]?.toString() ?? "",
                title: info["title"]?.toString() ?? "",
                area: info["area_name"]?.toString() ?? "",
                watching: info["online"]?.toString() ?? "0",
                platform: Sites.bilibiliSite,
                liveStatus: live ? LiveStatus.live : LiveStatus.offline,
                status: live,
              ),
            );
          }
        }
        if (list.length < 50) break;
        page++;
      }
    } catch (e) {
      return FollowSyncResult(
        platform: Sites.bilibiliSite,
        error: e.toString(),
      );
    }
    return _commitRooms(rooms, Sites.bilibiliSite, failed, filtered: filtered);
  }

  /// B站关注主播的上次直播信息（uid -> (直播状态, 上次直播结束时间戳)）。
  ///
  /// 使用 B站"我的关注"接口：
  /// https://api.live.bilibili.com/xlive/web-ucenter/user/following
  /// 其中 `record_live_time` 为主播上一次直播结束时间戳（秒），正在直播时为 0。
  /// 拉取失败时返回已获取的部分数据，不阻塞同步流程。
  static Future<Map<String, ({int liveStatus, int recordLiveTime})>>
  _bilibiliLastLiveMap(String cookie) async {
    final result = <String, ({int liveStatus, int recordLiveTime})>{};
    try {
      var page = 1;
      while (true) {
        final json = await HttpClient.instance.getJson(
          "https://api.live.bilibili.com/xlive/web-ucenter/user/following",
          queryParameters: {
            "page": page,
            "page_size": 50,
            "ignoreRecord": 1,
            "hit_ab": true,
          },
          header: {
            "cookie": cookie,
            "user-agent": _webUa,
            "referer": "https://live.bilibili.com/",
          },
        );
        if (json == null || json["code"] != 0) break;
        final data = (json["data"] as Map?) ?? const {};
        final list = (data["list"] as List?) ?? const [];
        for (final item in list) {
          final uid = item["uid"]?.toString() ?? "";
          if (uid.isEmpty || uid == "0") continue;
          result[uid] = (
            liveStatus: (item["live_status"]?.toString() ?? "0") == "1" ? 1 : 0,
            recordLiveTime:
                int.tryParse(item["record_live_time"]?.toString() ?? "") ?? 0,
          );
        }
        final totalPage = (data["totalPage"] as num?)?.toInt() ?? 0;
        if (list.length < 50 || page >= totalPage) break;
        page++;
      }
    } catch (_) {
      // 忽略单个接口异常，使用已获取的部分数据
    }
    return result;
  }

  static Future<Map<String, dynamic>> _bilibiliRoomBaseInfo(
    List<String> mids,
    String cookie,
  ) async {
    final result = await HttpClient.instance.getJson(
      "https://api.live.bilibili.com/xlive/web-room/v1/index/getRoomBaseInfo",
      queryParameters: {"req_biz": "web_relation_component", "uids": mids},
      header: {
        "cookie": cookie,
        "user-agent": _webUa,
        "referer": "https://live.bilibili.com/",
      },
    );
    final byUids = (result?["data"]?["by_uids"] as Map?) ?? {};
    return byUids.map((k, v) => MapEntry(k.toString(), v));
  }

  // ---------------- 斗鱼 ----------------
  static Future<FollowSyncResult> syncDouyu() async {
    final cookie = SettingsService.to.cookieManager.douyuCookie.v;
    if (cookie.isEmpty) {
      return const FollowSyncResult(
        platform: Sites.douyuSite,
        error: "not_login",
      );
    }

    final rooms = <LiveRoom>[];
    var failed = 0;
    try {
      var page = 1;
      while (true) {
        final result = await HttpClient.instance.getJson(
          "https://www.douyu.com/wgapi/livenc/liveweb/follow/list",
          queryParameters: {"type": 1, "page": page, "pageSize": 100},
          header: {
            "cookie": cookie,
            "user-agent": _webUa,
            "referer": "https://www.douyu.com/follow",
          },
        );
        if (result == null || ((result["error"] ?? result["code"]) ?? -1) != 0) {
          return FollowSyncResult(
            platform: Sites.douyuSite,
            error: result?["msg"]?.toString() ?? "api_error",
          );
        }
        final data = (result["data"] as Map?) ?? {};
        final list = (data["list"] as List?) ?? [];
        for (final item in list) {
          final rid =
              item["rid"]?.toString() ?? item["room_id"]?.toString() ?? "";
          if (rid.isEmpty || rid == "0") {
            failed++;
            continue;
          }
          final av = item["al"]?.toString() ?? item["avatar"]?.toString() ?? "";
          rooms.add(
            LiveRoom(
              roomId: rid,
              nick: item["nn"]?.toString() ?? item["nick"]?.toString() ?? "",
              title:
                  item["rn"]?.toString() ?? item["room_name"]?.toString() ?? "",
              avatar: av.isNotEmpty ? "$_douyuAvatarPrefix${av}_big.jpg" : "",
              area:
                  item["c2name"]?.toString() ??
                  item["category"]?.toString() ??
                  "",
              watching:
                  item["ol"]?.toString() ?? item["online"]?.toString() ?? "0",
              platform: Sites.douyuSite,
              liveStatus: LiveStatus.offline,
              status: false,
            ),
          );
        }
        final total = (data["total"] as num?)?.toInt() ?? 0;
        if (list.isEmpty || page * 100 >= total) break;
        page++;
      }
    } catch (e) {
      return FollowSyncResult(platform: Sites.douyuSite, error: e.toString());
    }
    return _commitRooms(rooms, Sites.douyuSite, failed);
  }

  // ---------------- 虎牙 ----------------
  static Future<FollowSyncResult> syncHuya() async {
    final cookie = SettingsService.to.cookieManager.huyaCookie.v;
    if (cookie.isEmpty) {
      return const FollowSyncResult(
        platform: Sites.huyaSite,
        error: "not_login",
      );
    }
    final uid = _cookieValue(cookie, "udb_uid");
    final yyuid = _cookieValue(cookie, "yyuid");
    final lUid = int.tryParse(uid.isEmpty ? yyuid : uid) ?? 0;
    if (lUid <= 0) {
      return const FollowSyncResult(
        platform: Sites.huyaSite,
        error: "huya_cookie_invalid",
      );
    }

    final rooms = <LiveRoom>[];
    var failed = 0;
    try {
      final client = BaseTarsHttp(
        "http://wup.huya.com",
        "huyauserui",
        headers: {
          "Origin": "https://www.huya.com",
          "Referer": "https://www.huya.com/",
          "User-Agent": _webUa,
        },
      );
      final req = GetAllSubscribeToUidListReq()
        ..tId = _buildHuyaUserId(cookie, lUid)
        ..lUid = lUid;
      final rsp = GetAllSubscribeToUidListRsp();
      final result = await client.tupRequest(
        "getAllSubscribeToUidList",
        req,
        rsp,
      );

      final allUid = result.vAllUid;
      final toProcess = allUid.length > _huyaMaxProcess
          ? allUid.sublist(0, _huyaMaxProcess)
          : allUid;
      for (final presenterUid in toProcess) {
        try {
          final profile = await _huyaGetUserProfile(
            client,
            cookie,
            lUid,
            presenterUid,
          );
          final roomId = profile.roomId;
          if (roomId.isEmpty || roomId == "0") {
            failed++;
            continue;
          }
          rooms.add(
            LiveRoom(
              roomId: roomId,
              userId: presenterUid.toString(),
              nick: profile.nick,
              avatar: profile.avatar,
              platform: Sites.huyaSite,
              liveStatus: LiveStatus.offline,
              status: false,
            ),
          );
        } catch (_) {
          failed++;
        }
      }
    } catch (e) {
      return FollowSyncResult(platform: Sites.huyaSite, error: e.toString());
    }
    return _commitRooms(rooms, Sites.huyaSite, failed);
  }

  static Future<({String nick, String avatar, String roomId})>
  _huyaGetUserProfile(
    BaseTarsHttp client,
    String cookie,
    int lUid,
    int presenterUid,
  ) async {
    final req = GetUserProfileReq()
      ..tId = _buildHuyaUserId(cookie, lUid)
      ..lUid = presenterUid;
    final rsp = GetUserProfileRsp();
    final result = await client.tupRequest("getUserProfile", req, rsp);
    final profile = result.tUserProfile;
    return (
      nick: profile.tUserBase.sNickName,
      avatar: profile.tUserBase.sAvatarUrl,
      roomId: profile.tPresenterBase.iRoomId.toString(),
    );
  }

  static HuyaUserId _buildHuyaUserId(String cookie, int lUid) {
    return HuyaUserId()
      ..lUid = lUid
      ..sGuid = _cookieValue(cookie, "guid")
      ..sCookie = cookie.replaceAll(RegExp(r"\s"), "")
      ..sHuYaUA = _huyaUa
      ..iTokenType = 0;
  }

  static String _cookieValue(String cookie, String name) {
    final match = RegExp(
      '(?:^|;)\\s*${RegExp.escape(name)}=([^;]*)',
    ).firstMatch(cookie);
    return match?.group(1)?.trim() ?? "";
  }

  // ---------------- 公共 ----------------
  static int _addRoom(LiveRoom room) {
    final fav = SettingsService.to.fav;
    if (fav.isFavorite(room)) return 0;
    return fav.addRoom(room) ? 1 : 0;
  }

  static FollowSyncResult _commitRooms(
    List<LiveRoom> rooms,
    String platform,
    int failed, {
    int filtered = 0,
  }) {
    var added = 0;
    var existed = 0;
    for (final room in rooms) {
      if (_addRoom(room) == 1) {
        added++;
      } else {
        existed++;
      }
    }
    return FollowSyncResult(
      platform: platform,
      total: rooms.length + failed + filtered,
      added: added,
      existed: existed,
      failed: failed,
      filtered: filtered,
    );
  }

  /// 执行同步并展示加载与结果
  static Future<void> runAndShowResult({
    required Future<FollowSyncResult> Function() task,
    required String loadingMsg,
  }) async {
    SmartDialog.showLoading(msg: loadingMsg);
    FollowSyncResult result;
    try {
      result = await task();
    } catch (e) {
      result = FollowSyncResult(platform: "", error: e.toString());
    } finally {
      SmartDialog.dismiss(status: SmartStatus.loading);
    }

    if (!result.success) {
      final msg = result.error == "not_login"
          ? i18n("follow_sync_not_login")
          : result.error == "huya_cookie_invalid"
          ? i18n("follow_sync_huya_cookie_invalid")
          : i18n("follow_sync_failed", args: {'msg': result.error ?? ""});
      Utils.showAlertDialog(msg, title: i18n("follow_sync_title"));
      return;
    }

    final summary = result.filtered > 0
        ? i18n(
            "follow_sync_summary_filtered",
            args: {
              'total': result.total.toString(),
              'added': result.added.toString(),
              'existed': result.existed.toString(),
              'failed': result.failed.toString(),
              'filtered': result.filtered.toString(),
            },
          )
        : i18n(
            "follow_sync_summary",
            args: {
              'total': result.total.toString(),
              'added': result.added.toString(),
              'existed': result.existed.toString(),
              'failed': result.failed.toString(),
            },
          );
    await Utils.showAlertDialog(summary, title: i18n("follow_sync_title"));
  }
}
