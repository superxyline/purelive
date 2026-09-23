import 'dart:math';
import 'dart:convert';

import 'package:pure_live/common/index.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:pure_live/model/live_category.dart';
import 'package:pure_live/model/live_anchor_item.dart';
import 'package:pure_live/core/site/douyu/douyu_utils.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/core/danmaku/douyu_danmaku.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';
import 'package:pure_live/modules/live_play/controllers/player_controller.dart';

class DouyuSite implements LiveSite {
  @override
  String id = Sites.douyuSite;

  @override
  String name = "斗鱼直播";

  @override
  LiveDanmaku getDanmaku() => DouyuDanmaku();

  @override
  Future<List<LiveCategory>> getCategores(int page, int pageSize) async {
    List<LiveCategory> categories = [];
    var result = await HttpClient.instance.getJson("https://m.douyu.com/api/cate/list");
    var subCateList = result["data"]["cate2Info"] as List;
    for (var item in result["data"]["cate1Info"]) {
      var cate1Id = item["cate1Id"];
      var cate1Name = item["cate1Name"];
      List<LiveArea> subCategories = [];
      subCateList.where((x) => x["cate1Id"] == cate1Id).forEach((element) {
        subCategories.add(
          LiveArea(
            areaPic: element["icon"].toString(),
            areaId: element["cate2Id"].toString(),
            typeName: cate1Name.toString(),
            areaType: cate1Id.toString(),
            platform: Sites.douyuSite,
            areaName: element["cate2Name"].toString(),
          ),
        );
      });
      categories.add(LiveCategory(id: cate1Id.toString(), name: cate1Name.toString(), children: subCategories));
    }
    // 根据ID排序
    categories.sort((a, b) => int.parse(a.id).compareTo(int.parse(b.id)));

    return categories;
  }

  Future<List<LiveArea>> getSubCategories(LiveCategory liveCategory) async {
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/japi/weblist/apinc/getC2List",
      queryParameters: {"shortName": liveCategory.name, "customClassId": liveCategory.id, "offset": 0, "limit": 200},
    );

    List<LiveArea> subs = [];
    for (var item in result["data"]["list"]) {
      subs.add(
        LiveArea(
          areaPic: item["squareIconUrlW"].toString(),
          areaId: item["cid2"].toString(),
          typeName: liveCategory.name,
          areaType: liveCategory.id,
          platform: Sites.douyuSite,
          areaName: item["cname2"].toString(),
        ),
      );
    }

    return subs;
  }

  @override
  Future<List<LiveRoom>> getCategoryRooms(LiveArea category, {int page = 1, int pageSize = 30}) async {
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/gapi/rkc/directory/mixList/2_${category.areaId}/$page",
      queryParameters: {},
    );

    var items = <LiveRoom>[];
    for (var item in result['data']['rl']) {
      if (item["type"] != 1) {
        continue;
      }
      var roomItem = LiveRoom(
        cover: item['rs16'].toString(),
        watching: item['ol'].toString(),
        popularity: item['ol'].toString(),
        audienceMetricType: AudienceMetricType.popularity,
        roomId: item['rid'].toString(),
        title: item['rn'].toString(),
        nick: item['nn'].toString(),
        area: item['c2name'].toString(),
        liveStatus: LiveStatus.live,
        avatar: item['av'].toString().isNotEmpty ? 'https://apic.douyucdn.cn/upload/${item['av']}_middle.jpg' : '',
        status: true,
        platform: Sites.douyuSite,
      );
      items.add(roomItem);
    }
    return items;
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    var data = detail.data.toString();
    data += "&cdn=&rate=-1&ver=Douyu_223061205&iar=1&ive=1&hevc=0&fa=0";
    List<LivePlayQuality> qualities = [];
    var result = await HttpClient.instance.postJson(
      "https://www.douyu.com/lapi/live/getH5Play/${detail.roomId}",
      data: data,
      formUrlEncoded: true,
    );

    var cdns = <String>[];
    for (var item in result["data"]["cdnsWithName"]) {
      cdns.add(item["cdn"].toString());
    }
    // 如果cdn以scdn开头，将其放到最后
    cdns.sort((a, b) {
      if (a.startsWith("scdn") && !b.startsWith("scdn")) {
        return 1;
      } else if (!a.startsWith("scdn") && b.startsWith("scdn")) {
        return -1;
      }
      return 0;
    });
    for (var item in result["data"]["multirates"]) {
      qualities.add(LivePlayQuality(quality: item["name"].toString(), data: DouyuPlayData(item["rate"], cdns)));
    }
    return qualities;
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async {
    var data = quality.data as DouyuPlayData;

    List<String> urls = [];
    for (var item in data.cdns) {
      try {
        var url = await getPlayUrl(detail.roomId!, data.rate, item);
        if (url.isNotEmpty) {
          urls.add(url);
        }
      } on DouyuPlayApiException {
        // 单条 CDN 失败继续试下一条（上游语义：只淘汰失败候选）
      }
    }
    return urls;
  }

  /// 上游 H5 取流：DouyuUtils 纯 Dart 签名 + getH5PlayV1，描述符过期自动强刷重试一次。
  Future<String> getPlayUrl(String roomId, int rate, String cdn) async {
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final args = await DouyuUtils.sign(roomId, rate: rate, cdn: cdn, forceRefresh: attempt > 0);
        final result = await HttpClient.instance.postJson(
          "https://www.douyu.com/lapi/live/getH5PlayV1/$roomId",
          data: args,
          formUrlEncoded: true,
          header: DouyuUtils.requestHeaders(roomId),
        );
        if (result is! Map) throw const DouyuPlayApiException('H5 play response is not an object');
        final errorCode = result['error'] ?? result['code'] ?? -1;
        final code = errorCode is num ? errorCode.toInt() : int.tryParse(errorCode.toString()) ?? -1;
        if (code != 0) {
          throw DouyuPlayApiException('H5 play API error $code ${result['msg'] ?? ''}');
        }
        final data = result['data'];
        if (data is! Map) throw const DouyuPlayApiException('H5 play response missing data');
        return parsePlayUrl(Map<String, dynamic>.from(data));
      } catch (e) {
        lastError = e;
        if (attempt == 0) continue;
        if (e is DouyuPlayApiException) rethrow;
        throw DouyuPlayApiException('H5 play request failed after retry', cause: e);
      }
    }
    throw DouyuPlayApiException('H5 play request failed after retry', cause: lastError);
  }

  /// 上游 parsePlayUrl：rtmp_live 已是完整地址时优先，防止 `base/https://...` 双重拼接。
  static String parsePlayUrl(Map<String, dynamic> data) {
    final unescape = HtmlUnescape();
    final live = unescape.convert(data['rtmp_live']?.toString().trim() ?? '');
    if (_isPlayableUrl(live)) return live;
    for (final baseKey in const <String>['rtmp_url', 'flv_url']) {
      final base = unescape.convert(data[baseKey]?.toString().trim() ?? '');
      if (base.isEmpty || live.isEmpty) continue;
      final combined = '${base.replaceFirst(RegExp(r'/+$'), '')}/${live.replaceFirst(RegExp(r'^/+'), '')}';
      if (_isPlayableUrl(combined)) return combined;
    }
    for (final key in const <String>['player_1', 'stream_url', 'url']) {
      final value = unescape.convert(data[key]?.toString().trim() ?? '');
      if (_isPlayableUrl(value)) return value;
    }
    final flvUrl = unescape.convert(data['flv_url']?.toString().trim() ?? '');
    if (_isDirectMediaUrl(flvUrl)) return flvUrl;
    throw const DouyuPlayApiException('H5 play response has no playable URL');
  }

  static bool _isPlayableUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && uri.host.isNotEmpty && const {'http', 'https', 'rtmp'}.contains(uri.scheme);
  }

  static bool _isDirectMediaUrl(String value) {
    if (!_isPlayableUrl(value)) return false;
    final path = Uri.parse(value).path.toLowerCase();
    return path.endsWith('.flv') || path.endsWith('.m3u8') || path.endsWith('.mp4');
  }

  @override
  Future<List<LiveRoom>> getRecommendRooms({int page = 1, int pageSize = 30}) async {
    try {
      var result = await HttpClient.instance.getJson(
        "https://www.douyu.com/japi/weblist/apinc/allpage/6/$page",
        queryParameters: {},
      );

      var items = <LiveRoom>[];
      for (var item in result['data']['rl']) {
        if (item["type"] != 1) {
          continue;
        }

        var roomItem = LiveRoom(
          cover: item['rs16'].toString(),
          watching: item['ol'].toString(),
          popularity: item['ol'].toString(),
          audienceMetricType: AudienceMetricType.popularity,
          roomId: item['rid'].toString(),
          title: item['rn'].toString(),
          nick: item['nn'].toString(),
          area: item['c2name'].toString(),
          avatar: item['av'] ?? '',
          platform: Sites.douyuSite,
          status: true,
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
  Future<LiveRoom> getRoomDetail({required String platform, required String roomId, bool light = false}) async {
    try {
      var result = await HttpClient.instance.getJson(
        "https://www.douyu.com/betard/$roomId",
        queryParameters: {},
        header: {
          'referer': 'https://www.douyu.com/$roomId',
          'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.43',
        },
      );
      Map roomInfo;
      if (result is String) {
        roomInfo = json.decode(result)["room"];
      } else {
        roomInfo = result["room"];
      }

      // 列表刷新（light）：主播粉丝数不参与卡片渲染，跳过该请求，每房间只发一次
      // betard。取流签名已改为上游 DouyuUtils（纯 Dart，getEncryption 描述符 +
      // getH5PlayV1），不再需要 homeH5Enc 的 crptext。
      var fans = '';
      if (light) {
        fans = '';
      } else {
        fans = await _fetchAnchorFans(roomId);
      }

      // 斗鱼开播时间为 show_time（秒级时间戳）
      final douyuLiveTime = roomInfo["show_time"] is num
          ? (roomInfo["show_time"] as num).toInt()
          : int.tryParse(roomInfo["show_time"]?.toString() ?? '') ?? 0;

      return LiveRoom(
        cover: roomInfo["room_pic"].toString(),
        watching: roomInfo["room_biz_all"]["hot"].toString(),
        popularity: roomInfo["room_biz_all"]["hot"].toString(),
        audienceMetricType: AudienceMetricType.popularity,
        roomId: roomId,
        title: roomInfo["room_name"].toString(),
        nick: roomInfo["owner_name"].toString(),
        avatar: roomInfo["owner_avatar"].toString(),
        introduction: roomInfo["show_details"].toString(),
        area: roomInfo["second_lvl_name"]?.toString() ?? '',
        // 粉丝数：主播卡片接口的 data.roomInfo.fansNum
        followers: fans,
        notice: "",
        liveStatus: roomInfo["show_status"] == 1 ? LiveStatus.live : LiveStatus.offline,
        status: roomInfo["show_status"] == 1,
        liveStartTime: douyuLiveTime > 0 ? douyuLiveTime * 1000 : null,
        danmakuData: roomInfo["room_id"].toString(),
        platform: Sites.douyuSite,
        link: "https://www.douyu.com/$roomId",
        isRecord: roomInfo["videoLoop"] == 1,
      );
    } catch (e) {
      if (Get.isRegistered<PlayerController>()) {
        final PlayerController playerController = Get.find<PlayerController>();
        final currentRoom = playerController.currentRoom;
        if (currentRoom != null) return currentRoom.getLiveRoomWithError();
      }
      return LiveRoom(roomId: roomId, platform: platform).getLiveRoomWithError();
    }
  }

  /// 斗鱼主播卡片接口里的粉丝数。
  /// betard 接口不含粉丝数（只有 fans_bn 粉丝牌名），open.douyucdn.cn 的
  /// fans_num 已失效恒为 0；该接口免签名免登录，字段在 data.roomInfo.fansNum。
  Future<String> _fetchAnchorFans(String roomId) async {
    try {
      final result = await HttpClient.instance.getJson(
        "https://www.douyu.com/wgapi/livenc/liveweb/getAnchorNewCard",
        queryParameters: {"rid": roomId, "client_sys": "web"},
        header: {
          'referer': 'https://www.douyu.com/$roomId',
          'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.43',
        },
      );
      final decoded = result is String ? json.decode(result) : result;
      final fans = decoded?["data"]?["roomInfo"]?["fansNum"];
      return fans?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  Future<List<LiveRoom>> searchRooms(String keyword, {int page = 1, int pageSize = 30}) async {
    var did = generateRandomString(32);
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/japi/search/api/searchShow",
      queryParameters: {"kw": keyword, "page": page, "pageSize": 20},
      header: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.51',
        'referer': 'https://www.douyu.com/search/',
        'Cookie': 'dy_did=$did;acf_did=$did',
      },
    );
    if (result['error'] != 0) {
      throw Exception(result['msg']);
    }
    var items = <LiveRoom>[];

    var queryList = result["data"]["relateShow"] ?? [];
    for (var item in queryList) {
      var liveStatus = (int.tryParse(item["isLive"].toString()) ?? 0) == 1;
      var roomType = (int.tryParse(item["roomType"].toString()) ?? 0);
      var roomItem = LiveRoom(
        roomId: item["rid"].toString(),
        title: item["roomName"].toString(),
        cover: item["roomSrc"].toString(),
        area: item["cateName"].toString(),
        avatar: item["avatar"].toString(),
        liveStatus: liveStatus && roomType == 0 ? LiveStatus.live : LiveStatus.offline,
        status: liveStatus && roomType == 0,
        nick: item["nickName"].toString(),
        platform: Sites.douyuSite,
        watching: item["hot"].toString(),
        popularity: item["hot"].toString(),
        audienceMetricType: AudienceMetricType.popularity,
      );
      items.add(roomItem);
    }
    return items;
  }

  //生成指定长度的16进制随机字符串
  String generateRandomString(int length) {
    var random = Random.secure();
    var values = List<int>.generate(length, (i) => random.nextInt(16));
    StringBuffer stringBuffer = StringBuffer();
    for (var item in values) {
      stringBuffer.write(item.toRadixString(16));
    }
    return stringBuffer.toString();
  }

  @override
  Future<List<LiveAnchorItem>> searchAnchors(String keyword, {int page = 1, int pageSize = 30}) async {
    var did = generateRandomString(32);
    var result = await HttpClient.instance.getJson(
      "https://www.douyu.com/japi/search/api/searchUser",
      queryParameters: {"kw": keyword, "page": page, "pageSize": 20, "filterType": 1},
      header: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.51',
        'referer': 'https://www.douyu.com/search/',
        'Cookie': 'dy_did=$did;acf_did=$did',
      },
    );

    var items = <LiveAnchorItem>[];
    for (var item in result["data"]["relateUser"]) {
      var liveStatus = (int.tryParse(item["anchorInfo"]["isLive"].toString()) ?? 0) == 1;
      var roomType = (int.tryParse(item["anchorInfo"]["roomType"].toString()) ?? 0);
      var roomItem = LiveAnchorItem(
        roomId: item["anchorInfo"]["rid"].toString(),
        avatar: item["anchorInfo"]["avatar"].toString(),
        userName: item["anchorInfo"]["nickName"].toString(),
        liveStatus: liveStatus && roomType == 0,
      );
      items.add(roomItem);
    }
    return items;
  }

  @override
  Future<bool> getLiveStatus({required String platform, required String roomId}) async {
    var detail = await getRoomDetail(roomId: roomId, platform: platform);
    return detail.status!;
  }

  int parseHotNum(String hn) {
    try {
      var num = double.parse(hn.replaceAll("万", ""));
      if (hn.contains("万")) {
        num *= 10000;
      }
      return num.round();
    } catch (_) {
      return -999;
    }
  }

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage({required String roomId}) {
    //尚不支持
    return Future.value([]);
  }

  @override
  Future<(bool, String)> sendDanmaku({required String roomId, required String message}) async {
    return (false, i18n('send_danmaku_unsupported'));
  }
}

class DouyuPlayData {
  final int rate;
  final List<String> cdns;
  DouyuPlayData(this.rate, this.cdns);
}

class DouyuPlayApiException implements Exception {
  const DouyuPlayApiException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null ? 'DouyuPlayApiException: $message' : 'DouyuPlayApiException: $message ($cause)';
}
