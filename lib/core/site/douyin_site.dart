import 'dart:convert';
import 'dart:math' as math;

import 'package:pure_live/common/index.dart';
import 'package:pure_live/model/live_category.dart';
import 'package:pure_live/core/common/core_log.dart';
import 'package:pure_live/model/live_anchor_item.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/core/scripts/douyin_sign.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/common/convert_helper.dart';
import 'package:pure_live/core/danmaku/douyin_danmaku.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';
import 'package:pure_live/core/utils/douyin/douyin_request_params.dart';

class DouyinSite implements LiveSite {
  @override
  String id = Sites.douyinSite;

  @override
  String name = "抖音直播";

  @override
  LiveDanmaku getDanmaku() => DouyinDanmaku();

  /// 使用 QQBrowser User-Agent（参考 DouyinLiveRecorder）
  static const String kDefaultUserAgent =
      "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.5845.97 Safari/537.36 Core/1.116.567.400 QQBrowser/19.7.6764.400";

  static const String kDefaultReferer = "https://live.douyin.com";

  static const String kDefaultAuthority = "live.douyin.com";

  /// 用户设置的 cookie
  static String cookie = "";
  static Future<String>? _anonymousCookieRequest;

  Map<String, dynamic> headers = {
    "Authority": kDefaultAuthority,
    "Referer": kDefaultReferer,
    "User-Agent": kDefaultUserAgent,
  };

  Future<Map<String, dynamic>> getRequestHeaders() async {
    try {
      if (cookie.isNotEmpty) {
        return {...headers, "cookie": cookie};
      } else if (SettingsService.to.cookieManager.douyinCookie.v.isNotEmpty) {
        cookie = SettingsService.to.cookieManager.douyinCookie.v;
        return {...headers, "cookie": cookie};
      }

      final anonymousCookie = await (_anonymousCookieRequest ??= _fetchAnonymousCookie());
      _anonymousCookieRequest = null;
      if (anonymousCookie.isNotEmpty) {
        cookie = anonymousCookie;
        return {...headers, "cookie": cookie};
      }
      return Map<String, dynamic>.from(headers);
    } catch (e) {
      _anonymousCookieRequest = null;
      CoreLog.error(e);
      return Map<String, dynamic>.from(headers);
    }
  }

  Future<String> _fetchAnonymousCookie() async {
    final response = await HttpClient.instance.get(
      'https://live.douyin.com/',
      queryParameters: const {'from_nav': '1'},
      header: headers,
    );
    final setCookieValues = response.headers.map['set-cookie'] ?? const <String>[];
    final pairs = <String>[];
    for (final value in setCookieValues) {
      final pair = value.split(';').first.trim();
      if (pair.startsWith('ttwid=') || pair.startsWith('UIFID_TEMP=')) {
        pairs.add(pair);
      }
    }
    return pairs.join('; ');
  }

  Future<Map<String, dynamic>> getUserInfoByCookie(String cookie) async {
    try {
      final url = "https://live.douyin.com/webcast/user/me/";
      final result = await HttpClient.instance.getJson(
        url,
        queryParameters: {"aid": DouyinRequestParams.aidValue},
        header: {
          "user-agent": DouyinRequestParams.kDefaultUserAgent,
          'accept': 'application/json, text/plain, */*',
          'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
          "Cookie": cookie,
        },
      );
      if (result is Map<String, dynamic>) {
        final data = result["data"];
        if (data is Map<String, dynamic>) {
          return data;
        }
      }
      return {};
    } catch (e) {
      CoreLog.error(e);
    }
    return {};
  }

  String extractCategoryDataJson(String source) {
    final startPattern = r'{\"pathname\":\"/\",\"categoryData\":';
    int startIndex = source.indexOf(startPattern);
    if (startIndex == -1) return '';
    int openBraces = 0;
    bool foundFirstBrace = false;
    for (int i = startIndex; i < source.length; i++) {
      if (source[i] == '{') {
        openBraces++;
        foundFirstBrace = true;
      } else if (source[i] == '}') {
        openBraces--;
      }
      if (foundFirstBrace && openBraces == 0) {
        String rawData = source.substring(startIndex, i + 1);
        return rawData.replaceAll('\\"', '"').replaceAll(r'\\', r'\');
      }
    }
    return '';
  }

  @override
  Future<List<LiveCategory>> getCategores(int page, int pageSize) async {
    List<LiveCategory> categories = [];
    var result = await HttpClient.instance.getText(
      "https://live.douyin.com/",
      queryParameters: {"from_nav": "1"},
      header: await getRequestHeaders(),
    );

    String extracted = extractCategoryDataJson(result);
    var renderDataJson = json.decode(extracted);
    var data = renderDataJson["categoryData"];
    for (var item in data) {
      List<LiveArea> subs = [];
      var id = '${item["partition"]["id_str"]},${item["partition"]["type"]}';
      for (var subItem in item["sub_partition"]) {
        var subCategory = LiveArea(
          areaId: '${subItem["partition"]["id_str"]},${subItem["partition"]["type"]}',
          typeName: item["partition"]["title"] ?? '',
          areaType: id,
          areaName: subItem["partition"]["title"] ?? '',
          areaPic: "",
          platform: Sites.douyinSite,
        );
        subs.add(subCategory);
      }

      var category = LiveCategory(children: subs, id: id, name: asT<String?>(item["partition"]["title"]) ?? "");
      subs.insert(
        0,
        LiveArea(
          areaId: category.id,
          typeName: category.name,
          areaType: category.id,
          areaPic: "",
          areaName: category.name,
          platform: Sites.douyinSite,
        ),
      );
      categories.add(category);
    }
    return categories;
  }

  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    var ids = category.areaId?.split(',');
    var partitionId = ids?[0];
    var partitionType = ids?[1];

    String serverUrl = "https://live.douyin.com/webcast/web/partition/detail/room/v2/";
    var uri = Uri.parse(serverUrl).replace(
      scheme: "https",
      port: 443,
      queryParameters: {
        "aid": '6383',
        "app_name": "douyin_web",
        "live_id": '1',
        "device_platform": "web",
        "language": "zh-CN",
        "enter_from": "link_share",
        "cookie_enabled": "true",
        "screen_width": "1980",
        "screen_height": "1080",
        "browser_language": "zh-CN",
        "browser_platform": "Win32",
        "browser_name": "Edge",
        "browser_version": "125.0.0.0",
        "browser_online": "true",
        "count": '15',
        "offset": ((page - 1) * 15).toString(),
        "partition": partitionId,
        "partition_type": partitionType,
        "req_from": '2',
      },
    );
    var requestUrl = DouyinSign.getAbogusUrl(uri.toString(), kDefaultUserAgent);
    var result = await HttpClient.instance.getJson(requestUrl, header: await getRequestHeaders());
    var items = <LiveRoom>[];
    for (var item in result["data"]["data"]) {
      var roomItem = LiveRoom(
        roomId: item["web_rid"],
        title: item["room"]["title"].toString(),
        cover: item["room"]["cover"]["url_list"][0].toString(),
        nick: item["room"]["owner"]["nickname"].toString(),
        liveStatus: LiveStatus.live,
        avatar: item["room"]["owner"]["avatar_thumb"]["url_list"][0].toString(),
        status: true,
        platform: Sites.douyinSite,
        area: item['tag_name'].toString(),
        watching: item["room"]?["room_view_stats"]?["display_value"].toString() ?? '',
        totalViewers: item["room"]?["room_view_stats"]?["display_value"].toString() ?? '',
        onlineViewers: _douyinOnlineViewers(item["room"]),
        audienceMetricType: AudienceMetricType.totalViewers,
      );
      items.add(roomItem);
    }
    return items;
  }

  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    try {
      String serverUrl = "https://live.douyin.com/webcast/web/partition/detail/room/v2/";
      var uri = Uri.parse(serverUrl).replace(
        scheme: "https",
        port: 443,
        queryParameters: {
          "aid": '6383',
          "app_name": "douyin_web",
          "live_id": '1',
          "device_platform": "web",
          "language": "zh-CN",
          "enter_from": "link_share",
          "cookie_enabled": "true",
          "screen_width": "1980",
          "screen_height": "1080",
          "browser_language": "zh-CN",
          "browser_platform": "Win32",
          "browser_name": "Edge",
          "browser_version": "125.0.0.0",
          "browser_online": "true",
          "count": '20',
          "offset": ((page - 1) * 20).toString(),
          "partition": '720',
          "partition_type": '1',
          "req_from": '2',
        },
      );
      var requestUrl = DouyinSign.getAbogusUrl(uri.toString(), kDefaultUserAgent);
      var result = await HttpClient.instance.getJson(requestUrl, header: await getRequestHeaders());
      var items = <LiveRoom>[];
      for (var item in result["data"]["data"]) {
        var roomItem = LiveRoom(
          roomId: item["web_rid"],
          title: item["room"]["title"].toString(),
          cover: item["room"]["cover"]["url_list"][0].toString(),
          nick: item["room"]["owner"]["nickname"].toString(),
          platform: Sites.douyinSite,
          area: item["tag_name"] ?? '热门推荐',
          avatar: item["room"]["owner"]["avatar_thumb"]["url_list"][0].toString(),
          watching: item["room"]?["room_view_stats"]?["display_value"].toString() ?? '',
          totalViewers: item["room"]?["room_view_stats"]?["display_value"].toString() ?? '',
          onlineViewers: _douyinOnlineViewers(item["room"]),
          audienceMetricType: AudienceMetricType.totalViewers,
          liveStatus: LiveStatus.live,
        );
        items.add(roomItem);
      }
      return items;
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  @override
  Future<LiveRoom> getRoomDetail({required String platform, required String roomId}) async {
    if (roomId.length <= 16) {
      return await getRoomDetailByWebRid(roomId);
    }
    return await getRoomDetailByRoomId(roomId);
  }

  Future<LiveRoom> getRoomDetailByRoomId(String roomId) async {
    // 读取房间信息
    var roomData = await _getRoomDataByRoomId(roomId);

    // 通过房间信息获取WebRid
    var webRid = roomData["data"]["room"]["owner"]["web_rid"].toString();

    // 读取用户唯一ID，用于弹幕连接
    // 似乎这个参数不是必须的，先随机生成一个
    //var userUniqueId = await _getUserUniqueId(webRid);
    var userUniqueId = generateRandomNumber(12).toString();

    var room = roomData["data"]["room"];
    var owner = room["owner"];

    var status = asT<int?>(room["status"]) ?? 0;

    // roomId是一次性的，用户每次重新开播都会生成一个新的roomId
    // 所以如果roomId对应的直播间状态不是直播中，就通过webRid获取直播间信息
    if (status == 4) {
      var result = await getRoomDetailByWebRid(webRid);
      return result;
    }

    var roomStatus = status == 2;
    // 主要是为了获取cookie,用于弹幕websocket连接
    var headers = await getRequestHeaders();

    // 抖音开播时间为 create_time（秒级时间戳）
    final douyinStartTime = room["create_time"] is num
        ? (room["create_time"] as num).toInt()
        : int.tryParse(room["create_time"]?.toString() ?? '') ?? 0;

    return LiveRoom(
      roomId: webRid,
      title: room["title"].toString(),
      cover: roomStatus ? room["cover"]["url_list"][0].toString() : "",
      nick: owner["nickname"].toString(),
      avatar: owner["avatar_thumb"]["url_list"][0].toString(),
      watching: roomStatus ? room["room_view_stats"]["display_value"].toString() : "",
      totalViewers: roomStatus ? room["room_view_stats"]["display_value"].toString() : '',
      onlineViewers: roomStatus ? _douyinOnlineViewers(room) : '',
      audienceMetricType: AudienceMetricType.totalViewers,
      status: roomStatus,
      link: "https://live.douyin.com/$webRid",
      platform: Sites.douyinSite,
      area: '',
      liveStatus: roomStatus ? LiveStatus.live : LiveStatus.offline,
      liveStartTime: roomStatus && douyinStartTime > 0 ? douyinStartTime * 1000 : null,
      introduction: owner["signature"].toString(),
      notice: "",
      // 粉丝数：reflow/info 的 data.room.owner.follow_info（同一份响应，零额外请求）
      followers: parseFollowersFromOwner(owner),
      danmakuData: DouyinDanmakuArgs(webRid: webRid, roomId: roomId, userId: userUniqueId, cookie: headers["cookie"]),
      data: room["stream_url"],
    );
  }

  /// 通过WebRid获取直播间信息
  /// - [webRid] 直播间RID
  /// - 返回直播间信息
  Future<LiveRoom> getRoomDetailByWebRid(String webRid) async {
    try {
      var result = await _getRoomDetailByWebRidApi(webRid);
      return result;
    } catch (e) {
      CoreLog.error(e);
    }
    return await _getRoomDetailByWebRidHtml(webRid);
  }

  /// 通过WebRid访问直播间API，从API中获取直播间信息
  /// - [webRid] 直播间RID
  /// - 返回直播间信息
  Future<LiveRoom> _getRoomDetailByWebRidApi(String webRid) async {
    // 读取房间信息
    var data = await _getRoomDataByApi(webRid);

    var roomData = data["data"][0];
    var userData = data["user"];
    var roomId = roomData["id_str"].toString();

    // 读取用户唯一ID，用于弹幕连接
    // 似乎这个参数不是必须的，先随机生成一个
    //var userUniqueId = await _getUserUniqueId(webRid);
    var userUniqueId = generateRandomNumber(12).toString();

    var owner = roomData["owner"];

    var roomStatus = (asT<int?>(roomData["status"]) ?? 0) == 2;

    // 主要是为了获取cookie,用于弹幕websocket连接
    var headers = await getRequestHeaders();

    // 抖音开播时间为 create_time（秒级时间戳）
    final douyinStartTime = roomData["create_time"] is num
        ? (roomData["create_time"] as num).toInt()
        : int.tryParse(roomData["create_time"]?.toString() ?? '') ?? 0;

    // web enter 接口的 follow_info 只有关注状态、没有粉丝数，房间页 HTML 的
    // room 对象又没有 create_time（实测），两者都缺的这两项统一从 reflow/info
    // 补一次（同一个请求，不额外增加开销）。
    final extra = await _fetchRoomExtra(roomId);
    // 开播时间：enter 自带 create_time 时优先用它，缺失时用 reflow 的
    final startTimeSec = douyinStartTime > 0 ? douyinStartTime : extra.startTimeSec;

    return LiveRoom(
      roomId: webRid,
      title: roomData["title"].toString(),
      cover: roomStatus ? roomData["cover"]["url_list"][0].toString() : "",
      nick: roomStatus ? owner["nickname"].toString() : userData["nickname"].toString(),
      avatar: roomStatus
          ? owner["avatar_thumb"]["url_list"][0].toString()
          : userData["avatar_thumb"]["url_list"][0].toString(),
      watching: roomStatus ? roomData["room_view_stats"]["display_value"].toString() : "",
      totalViewers: roomStatus ? roomData["room_view_stats"]["display_value"].toString() : '',
      onlineViewers: roomStatus ? _douyinOnlineViewers(roomData) : '',
      audienceMetricType: AudienceMetricType.totalViewers,
      status: roomStatus,
      liveStatus: roomStatus ? LiveStatus.live : LiveStatus.offline,
      liveStartTime: roomStatus && startTimeSec > 0 ? startTimeSec * 1000 : null,
      link: "https://live.douyin.com/$webRid",
      platform: Sites.douyinSite,
      area: '',
      introduction: owner?["signature"]?.toString() ?? "",
      notice: "",
      followers: extra.followers,
      danmakuData: DouyinDanmakuArgs(webRid: webRid, roomId: roomId, userId: userUniqueId, cookie: headers["cookie"]),
      data: roomStatus ? roomData["stream_url"] : {},
    );
  }

  /// 从 reflow/info（App 接口）取网页与 enter 接口都拿不到的两项：
  /// 主播粉丝数（`owner.follow_info`）与本次开播时间（`create_time`，秒级）。
  /// 房间页 HTML 的 room 对象没有 create_time，web enter 的 follow_info
  /// 只有关注状态，只有这个接口两样都有，且匿名可访问。
  Future<({String followers, int startTimeSec})> _fetchRoomExtra(String roomId) async {
    if (roomId.isEmpty) return (followers: '', startTimeSec: 0);
    try {
      final roomData = await _getRoomDataByRoomId(roomId);
      final room = roomData["data"]?["room"];
      return (
        followers: parseFollowersFromOwner(room?["owner"]),
        startTimeSec: asT<int?>(room?["create_time"]) ?? 0,
      );
    } catch (e) {
      CoreLog.error(e);
      return (followers: '', startTimeSec: 0);
    }
  }

  /// 从 owner.follow_info 取主播粉丝数。
  static String parseFollowersFromOwner(dynamic owner) {
    if (owner is! Map) return '';
    final followInfo = owner["follow_info"];
    if (followInfo is! Map) return '';
    // 数字字段优先：follower_count_str 有时是"515.6万"这类展示串，
    // 统一交给展示层的 readableCount 格式化，各平台口径才一致。
    final value = followInfo["follower_count"] ?? followInfo["follower_count_str"];
    final text = value?.toString() ?? '';
    return text == '0' ? '' : text;
  }

  /// 通过WebRid访问直播间网页，从网页HTML中获取直播间信息
  /// - [webRid] 直播间RID
  /// - 返回直播间信息
  Future<LiveRoom> _getRoomDetailByWebRidHtml(String roomId) async {
    var detail = await _getRoomDataByHtml(roomId);
    var webRid = roomId;

    var realRoomId = detail["roomStore"]["roomInfo"]["room"]["id_str"].toString();
    var userUniqueId = detail["userStore"]["odin"]["user_unique_id"].toString();
    var roomInfo = detail["roomStore"]["roomInfo"]["room"];
    var owner = roomInfo["owner"];
    var anchor = detail["roomStore"]["roomInfo"]["anchor"];
    var roomStatus = (asT<int?>(roomInfo["status"]) ?? 0) == 2;

    // 主要是为了获取cookie,用于弹幕websocket连接
    var headers = await getRequestHeaders();

    // 抖音开播时间为 create_time（秒级时间戳）
    final douyinStartTime = roomInfo["create_time"] is num
        ? (roomInfo["create_time"] as num).toInt()
        : int.tryParse(roomInfo["create_time"]?.toString() ?? '') ?? 0;

    // 房间页 HTML 里既没有主播粉丝数、也没有 create_time（实测 room 对象只有
    // 标题/状态等字段），统一从 reflow/info 兜底取回，否则角标与粉丝行都不显示。
    final extra = await _fetchRoomExtra(realRoomId);
    final startTimeSec = douyinStartTime > 0 ? douyinStartTime : extra.startTimeSec;

    return LiveRoom(
      roomId: roomId,
      title: roomInfo["title"].toString(),
      cover: roomStatus ? roomInfo["cover"]["url_list"][0].toString() : "",
      nick: roomStatus ? owner["nickname"].toString() : anchor["nickname"].toString(),
      avatar: roomStatus
          ? owner["avatar_thumb"]["url_list"][0].toString()
          : anchor["avatar_thumb"]["url_list"][0].toString(),
      watching: roomInfo?["room_view_stats"]?["display_value"].toString() ?? '',
      totalViewers: roomInfo?["room_view_stats"]?["display_value"].toString() ?? '',
      onlineViewers: _douyinOnlineViewers(roomInfo),
      audienceMetricType: AudienceMetricType.totalViewers,
      liveStatus: roomStatus ? LiveStatus.live : LiveStatus.offline,
      liveStartTime: roomStatus && startTimeSec > 0 ? startTimeSec * 1000 : null,
      link: "https://live.douyin.com/$webRid",
      area: '',
      status: roomStatus,
      platform: Sites.douyinSite,
      introduction: roomInfo["title"].toString(),
      notice: "",
      followers: extra.followers,
      danmakuData: DouyinDanmakuArgs(
        webRid: webRid,
        roomId: realRoomId,
        userId: userUniqueId,
        cookie: headers["cookie"],
      ),
      data: roomStatus ? roomInfo["stream_url"] : {},
    );
  }

  /// 读取用户的唯一ID
  /// - [webRid] 直播间RID
  // ignore: unused_element
  Future<String> _getUserUniqueId(String webRid) async {
    try {
      var webInfo = await _getRoomDataByHtml(webRid);
      return webInfo["userStore"]["odin"]["user_unique_id"].toString();
    } catch (e) {
      return generateRandomNumber(12).toString();
    }
  }

  /// 进入直播间前需要先获取cookie
  /// - [webRid] 直播间RID
  Future<String> _getWebCookie(String webRid) async {
    var headResp = await HttpClient.instance.head("https://live.douyin.com/$webRid", header: headers);
    var dyCookie = "";
    headResp.headers["set-cookie"]?.forEach((element) {
      var cookie = element.split(";")[0];
      if (cookie.contains("ttwid")) {
        dyCookie += "$cookie;";
      }
      if (cookie.contains("__ac_nonce")) {
        dyCookie += "$cookie;";
      }
      if (cookie.contains("msToken")) {
        dyCookie += "$cookie;";
      }
    });
    return dyCookie;
  }

  /// 通过webRid获取直播间Web信息
  /// - [webRid] 直播间RID
  Future<Map> _getRoomDataByHtml(String webRid) async {
    var dyCookie = await _getWebCookie(webRid);
    var result = await HttpClient.instance.getText(
      "https://live.douyin.com/$webRid",
      queryParameters: {},
      header: {
        "Authority": kDefaultAuthority,
        "Referer": kDefaultReferer,
        "Cookie": dyCookie,
        "User-Agent": kDefaultUserAgent,
      },
    );

    var renderData = RegExp(r'\{\\"state\\":\{\\"appStore.*?\]\\n').firstMatch(result)?.group(0) ?? "";
    var str = renderData.trim().replaceAll('\\"', '"').replaceAll(r"\\", r"\").replaceAll(']\\n', "");

    var renderDataJson = json.decode(str);
    return renderDataJson["state"];
  }

  /// 通过webRid获取直播间Web信息
  /// - [webRid] 直播间RID
  Future<Map> _getRoomDataByApi(String webRid) async {
    String serverUrl = "https://live.douyin.com/webcast/room/web/enter/";
    var uri = Uri.parse(serverUrl).replace(
      scheme: "https",
      port: 443,
      queryParameters: {
        "aid": '6383',
        "app_name": "douyin_web",
        "live_id": '1',
        "device_platform": "web",
        "enter_from": "web_live",
        "web_rid": webRid,
        "room_id_str": "",
        "enter_source": "",
        "Room-Enter-User-Login-Ab": '0',
        "is_need_double_stream": 'false',
        "cookie_enabled": 'true',
        "screen_width": '1980',
        "screen_height": '1080',
        "browser_language": "zh-CN",
        "browser_platform": "Win32",
        "browser_name": "Edge",
        "browser_version": "125.0.0.0",
      },
    );
    var requestUrl = DouyinSign.getAbogusUrl(uri.toString(), kDefaultUserAgent);
    var requestHeader = await getRequestHeaders();
    var result = await HttpClient.instance.getJson(requestUrl, header: requestHeader);

    return result["data"];
  }

  /// 通过roomId获取直播间信息
  /// - [roomId] 直播间ID
  Future<Map> _getRoomDataByRoomId(String roomId) async {
    var result = await HttpClient.instance.getJson(
      'https://webcast.amemv.com/webcast/room/reflow/info/',
      queryParameters: {
        "type_id": 0,
        "live_id": 1,
        "room_id": roomId,
        "sec_user_id": "",
        "version_code": "99.99.99",
        "app_id": 6383,
      },
      header: await getRequestHeaders(),
    );
    return result;
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    List<LivePlayQuality> qualities = [];

    var qulityList = detail.data["live_core_sdk_data"]["pull_data"]["options"]["qualities"];
    var streamData = detail.data["live_core_sdk_data"]["pull_data"]["stream_data"].toString();

    if (!streamData.startsWith('{')) {
      var flvList = (detail.data["flv_pull_url"] as Map).values.cast<String>().toList();
      var hlsList = (detail.data["hls_pull_url_map"] as Map).values.cast<String>().toList();
      for (var quality in qulityList) {
        int level = quality["level"];
        List<String> urls = [];
        var flvIndex = flvList.length - level;
        if (flvIndex >= 0 && flvIndex < flvList.length) {
          urls.add(flvList[flvIndex]);
        }
        var hlsIndex = hlsList.length - level;
        if (hlsIndex >= 0 && hlsIndex < hlsList.length) {
          urls.add(hlsList[hlsIndex]);
        }
        var qualityItem = LivePlayQuality(quality: quality["name"], sort: level, data: urls);
        if (urls.isNotEmpty) {
          qualities.add(qualityItem);
        }
      }
    } else {
      var qualityData = json.decode(streamData)["data"] as Map;
      for (var quality in qulityList) {
        List<String> urls = [];
        var flvUrl = qualityData[quality["sdk_key"]]?["main"]?["flv"]?.toString();

        if (flvUrl != null && flvUrl.isNotEmpty) {
          urls.add(flvUrl);
        }
        var hlsUrl = qualityData[quality["sdk_key"]]?["main"]?["hls"]?.toString();
        if (hlsUrl != null && hlsUrl.isNotEmpty) {
          urls.add(hlsUrl);
        }
        var qualityItem = LivePlayQuality(quality: quality["name"], sort: quality["level"], data: urls);
        if (urls.isNotEmpty) {
          qualities.add(qualityItem);
        }
      }
    }

    qualities.sort((a, b) => b.sort.compareTo(a.sort));
    return qualities;
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async {
    return quality.data;
  }

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async {
    String serverUrl = "https://www.douyin.com/aweme/v1/web/live/search/";
    var uri = Uri.parse(serverUrl).replace(
      scheme: "https",
      port: 443,
      queryParameters: {
        "device_platform": "webapp",
        "aid": "6383",
        "channel": "channel_pc_web",
        "search_channel": "aweme_live",
        "keyword": keyword,
        "search_source": "switch_tab",
        "query_correct_type": "1",
        "is_filter_search": "0",
        "from_group_id": "",
        "offset": ((page - 1) * 10).toString(),
        "count": "10",
        "pc_client_type": "1",
        "version_code": "170400",
        "version_name": "17.4.0",
        "cookie_enabled": "true",
        "screen_width": "1980",
        "screen_height": "1080",
        "browser_language": "zh-CN",
        "browser_platform": "Win32",
        "browser_name": "Edge",
        "browser_version": "125.0.0.0",
        "browser_online": "true",
        "engine_name": "Blink",
        "engine_version": "125.0.0.0",
        "os_name": "Windows",
        "os_version": "10",
        "cpu_core_num": "12",
        "device_memory": "8",
        "platform": "PC",
        "downlink": "10",
        "effective_type": "4g",
        "round_trip_time": "100",
        "webid": "7382872326016435738",
      },
    );
    var requlestUrl = uri.toString();
    var headResp = await getRequestHeaders();
    var dyCookie = headResp['cookie'];
    var result = await HttpClient.instance.getJson(
      requlestUrl,
      queryParameters: {},
      header: {
        "Authority": 'www.douyin.com',
        'accept': 'application/json, text/plain, */*',
        'accept-language': 'zh-CN,zh;q=0.9,en;q=0.8',
        'cookie': dyCookie,
        'priority': 'u=1, i',
        'referer': 'https://www.douyin.com/search/${Uri.encodeComponent(keyword)}?type=live',
        'sec-ch-ua': '"Microsoft Edge";v="125", "Chromium";v="125", "Not.A/Brand";v="24"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"Windows"',
        'sec-fetch-dest': 'empty',
        'sec-fetch-mode': 'cors',
        'sec-fetch-site': 'same-origin',
        'user-agent': DouyinRequestParams.kDefaultUserAgent,
      },
    );
    if (result == "" || result == 'blocked') {
      throw Exception("抖音直播搜索被限制，请稍后再试");
    }
    var items = <LiveRoom>[];
    for (var item in result["data"] ?? []) {
      var itemData = json.decode(item["lives"]["rawdata"].toString());
      var roomStatus = (asT<int?>(itemData["status"]) ?? 0) == 2;
      var roomItem = LiveRoom(
        roomId: itemData["owner"]["web_rid"].toString(),
        title: itemData["title"].toString(),
        cover: itemData["cover"]["url_list"][0].toString(),
        nick: itemData["owner"]["nickname"].toString(),
        platform: Sites.douyinSite,
        avatar: itemData["owner"]["avatar_thumb"]["url_list"][0].toString(),
        liveStatus: roomStatus ? LiveStatus.live : LiveStatus.offline,
        area: '',
        status: roomStatus,
        watching: itemData["stats"]["total_user_str"].toString(),
        totalViewers: itemData["stats"]["total_user_str"].toString(),
        onlineViewers: _douyinOnlineViewers(itemData),
        audienceMetricType: AudienceMetricType.totalViewers,
      );
      items.add(roomItem);
    }
    return items;
  }

  @override
  Future<List<LiveAnchorItem>> searchAnchors(String keyword, {int page = 1, int pageSize = 30}) async {
    throw Exception("抖音暂不支持搜索主播，请直接搜索直播间");
  }

  @override
  Future<bool> getLiveStatus({required String platform, required String roomId}) async {
    var result = await getRoomDetail(roomId: roomId, platform: platform);
    return result.status!;
  }

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage({required String roomId}) {
    return Future.value(<LiveSuperChatMessage>[]);
  }

  @override
  Future<(bool, String)> sendDanmaku({required String roomId, required String message}) async {
    return (false, i18n('send_danmaku_unsupported'));
  }

  //生成指定长度的16进制随机字符串
  String generateRandomString(int length) {
    var random = math.Random.secure();
    var values = List<int>.generate(length, (i) => random.nextInt(16));
    StringBuffer stringBuffer = StringBuffer();
    for (var item in values) {
      stringBuffer.write(item.toRadixString(16));
    }
    return stringBuffer.toString();
  }

  // 生成随机的数字
  int generateRandomNumber(int length) {
    var random = math.Random.secure();
    var values = List<int>.generate(length, (i) => random.nextInt(10));
    StringBuffer stringBuffer = StringBuffer();
    for (var item in values) {
      stringBuffer.write(item);
    }
    return int.tryParse(stringBuffer.toString()) ?? math.Random().nextInt(1000000000);
  }
}

String _douyinOnlineViewers(dynamic room) {
  if (room is! Map) return '';
  final stats = room['room_view_stats'];
  final roomStats = room['stats'];
  final candidates = <dynamic>[
    // 匿名首页 Feed 把并发在线人数放在 room 顶层（上游 v2.9.7 优化），
    // 顶层字段须排在嵌套兼容字段之前，避免过期的嵌套占位值掩盖真实在线数。
    room['user_count'],
    room['user_count_str'],
    room['online_user_count'],
    room['online_user_for_anchor'],
    if (stats is Map) stats['user_count'],
    if (stats is Map) stats['online_user_count'],
    if (stats is Map) stats['online_user_for_anchor'],
    if (roomStats is Map) roomStats['user_count'],
    if (roomStats is Map) roomStats['online_user_count'],
    if (roomStats is Map) roomStats['online_user_for_anchor'],
  ];
  for (final value in candidates) {
    final text = value?.toString().trim() ?? '';
    if (LiveRoom.parseAudienceNumber(text) > 0) return text;
  }
  return '';
}
