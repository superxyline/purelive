import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math;
import 'package:get/get.dart';
import 'package:pure_live/model/live_category.dart';
import 'package:pure_live/core/common/core_log.dart';
import 'package:pure_live/common/models/live_area.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/common/http_client.dart';
import 'package:pure_live/model/live_play_quality.dart';
import 'package:pure_live/core/interface/live_site.dart';
import 'package:pure_live/model/live_search_result.dart';
import 'package:pure_live/common/models/live_message.dart';
import 'package:pure_live/core/common/convert_helper.dart';
import 'package:pure_live/model/live_category_result.dart';
import 'package:pure_live/core/danmaku/douyin_danmaku.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';
import 'package:pure_live/common/services/settings_service.dart';

class DouyinSite implements LiveSite {
  @override
  String id = "douyin";

  @override
  String name = "抖音直播";

  @override
  LiveDanmaku getDanmaku() => DouyinDanmaku();
  final SettingsService settings = Get.find<SettingsService>();

  static const String kDefaultUserAgent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0";

  static const String kDefaultReferer = "https://live.douyin.com";

  static const String kDefaultAuthority = "live.douyin.com";

  Map<String, dynamic> headers = {
    "Authority": kDefaultAuthority,
    "Referer": kDefaultReferer,
    "User-Agent": kDefaultUserAgent,
  };

  Future<Map<String, dynamic>> getRequestHeaders() async {
    try {
      if (headers.containsKey("cookie")) {
        return headers;
      }
      var head = await HttpClient.instance.head("https://live.douyin.com", header: headers);
      head.headers["set-cookie"]?.forEach((element) {
        var cookie = element.split(";")[0];
        if (cookie.contains("ttwid")) {
          headers["cookie"] = cookie;
        }
      });
      return headers;
    } catch (e) {
      CoreLog.error(e);
      return headers;
    }
  }

  @override
  Future<List<LiveCategory>> getCategores(int page, int pageSize) async {
    List<LiveCategory> categories = [];
    var renderData =
        '{"pathname":"/","categoryData":[{"partition":{"id_str":"4609","type":1,"title":"主机游戏"},"sub_partition":[{"partition":{"id_str":"633","type":1,"title":"魔兽世界"},"sub_partition":[]},{"partition":{"id_str":"2607","type":1,"title":"永劫无间"},"sub_partition":[]},{"partition":{"id_str":"716","type":1,"title":"横版格斗"},"sub_partition":[]},{"partition":{"id_str":"1054","type":1,"title":"魔兽争霸3"},"sub_partition":[]},{"partition":{"id_str":"725","type":1,"title":"其他主机游戏"},"sub_partition":[]},{"partition":{"id_str":"623","type":1,"title":"我的世界"},"sub_partition":[]},{"partition":{"id_str":"705","type":1,"title":"仁王"},"sub_partition":[]},{"partition":{"id_str":"1215","type":1,"title":"糖豆人"},"sub_partition":[]}]},{"partition":{"id_str":"591","type":1,"title":"棋牌桌游"},"sub_partition":[{"partition":{"id_str":"592","type":1,"title":"斗地主"},"sub_partition":[]},{"partition":{"id_str":"624","type":1,"title":"麻将"},"sub_partition":[]},{"partition":{"id_str":"597","type":1,"title":"象棋"},"sub_partition":[]},{"partition":{"id_str":"729","type":1,"title":"其他棋牌游戏"},"sub_partition":[]},{"partition":{"id_str":"619","type":1,"title":"军棋"},"sub_partition":[]},{"partition":{"id_str":"5163","type":1,"title":"网易狼人杀"},"sub_partition":[]},{"partition":{"id_str":"5168","type":1,"title":"红狼（口袋狼人杀）"},"sub_partition":[]},{"partition":{"id_str":"1395","type":1,"title":"三国杀手游"},"sub_partition":[]}]},{"partition":{"id_str":"4627","type":1,"title":"角色扮演"},"sub_partition":[{"partition":{"id_str":"1251","type":1,"title":"原神"},"sub_partition":[]},{"partition":{"id_str":"2078","type":1,"title":"问道端游"},"sub_partition":[]},{"partition":{"id_str":"590","type":1,"title":"明日之后"},"sub_partition":[]},{"partition":{"id_str":"1603","type":1,"title":"皇室战争"},"sub_partition":[]},{"partition":{"id_str":"1240","type":1,"title":"光遇"},"sub_partition":[]},{"partition":{"id_str":"1102","type":1,"title":"问道手游"},"sub_partition":[]},{"partition":{"id_str":"2939","type":1,"title":"幻塔"},"sub_partition":[]},{"partition":{"id_str":"3637","type":1,"title":"经典天龙八部"},"sub_partition":[]}]},{"partition":{"id_str":"4630","type":1,"title":"休闲游戏"},"sub_partition":[{"partition":{"id_str":"3143","type":1,"title":"蛋仔派对"},"sub_partition":[]},{"partition":{"id_str":"5065","type":1,"title":"美食DIY"},"sub_partition":[]},{"partition":{"id_str":"651","type":1,"title":"植物大战僵尸"},"sub_partition":[]},{"partition":{"id_str":"6470","type":1,"title":"识字大师"},"sub_partition":[]},{"partition":{"id_str":"698","type":1,"title":"球球大作战"},"sub_partition":[]},{"partition":{"id_str":"1467","type":1,"title":"元气骑士"},"sub_partition":[]},{"partition":{"id_str":"1108","type":1,"title":"开心消消乐"},"sub_partition":[]},{"partition":{"id_str":"3447","type":1,"title":"找不同"},"sub_partition":[]}]},{"partition":{"id_str":"4618","type":1,"title":"竞技游戏"},"sub_partition":[{"partition":{"id_str":"1270","type":1,"title":"5v5推塔手游"},"sub_partition":[]},{"partition":{"id_str":"580","type":1,"title":"DOTA2"},"sub_partition":[]},{"partition":{"id_str":"655","type":1,"title":"赛车游戏"},"sub_partition":[]},{"partition":{"id_str":"687","type":1,"title":"格斗手游"},"sub_partition":[]},{"partition":{"id_str":"1106","type":1,"title":"跑跑卡丁车手游"},"sub_partition":[]},{"partition":{"id_str":"579","type":1,"title":"DOTA"},"sub_partition":[]},{"partition":{"id_str":"586","type":1,"title":"第五人格"},"sub_partition":[]},{"partition":{"id_str":"5618","type":1,"title":"梦三国"},"sub_partition":[]}]},{"partition":{"id_str":"4606","type":1,"title":"策略游戏"},"sub_partition":[{"partition":{"id_str":"1305","type":1,"title":"坦克世界"},"sub_partition":[]},{"partition":{"id_str":"1321","type":1,"title":"怀旧FC"},"sub_partition":[]},{"partition":{"id_str":"1055","type":1,"title":"帝国时代"},"sub_partition":[]},{"partition":{"id_str":"1457","type":1,"title":"合金弹头"},"sub_partition":[]},{"partition":{"id_str":"708","type":1,"title":"战舰世界"},"sub_partition":[]},{"partition":{"id_str":"1458","type":1,"title":"魂斗罗"},"sub_partition":[]},{"partition":{"id_str":"672","type":1,"title":"西游释厄传"},"sub_partition":[]},{"partition":{"id_str":"1052","type":1,"title":"恐龙快打"},"sub_partition":[]}]},{"partition":{"id_str":"4603","type":1,"title":"射击游戏"},"sub_partition":[{"partition":{"id_str":"648","type":1,"title":"CS:GO"},"sub_partition":[]},{"partition":{"id_str":"5746","type":1,"title":"无畏契约"},"sub_partition":[]},{"partition":{"id_str":"613","type":1,"title":"吃鸡手游"},"sub_partition":[]},{"partition":{"id_str":"600","type":1,"title":"射击游戏"},"sub_partition":[]},{"partition":{"id_str":"589","type":1,"title":"香肠派对"},"sub_partition":[]},{"partition":{"id_str":"4879","type":1,"title":"暗区突围"},"sub_partition":[]},{"partition":{"id_str":"4472","type":1,"title":"Apex英雄"},"sub_partition":[]},{"partition":{"id_str":"659","type":1,"title":"CS 1.6"},"sub_partition":[]}]},{"partition":{"id_str":"5837","type":1,"title":"卡牌游戏"},"sub_partition":[{"partition":{"id_str":"4817","type":1,"title":"崩坏：星穹铁道"},"sub_partition":[]},{"partition":{"id_str":"657","type":1,"title":"阴阳师"},"sub_partition":[]},{"partition":{"id_str":"1591","type":1,"title":"明日方舟"},"sub_partition":[]},{"partition":{"id_str":"3889","type":1,"title":"炉石传说"},"sub_partition":[]},{"partition":{"id_str":"4840","type":1,"title":"铁杆三国"},"sub_partition":[]},{"partition":{"id_str":"4844","type":1,"title":"山海经异兽录"},"sub_partition":[]},{"partition":{"id_str":"4183","type":1,"title":"少年三国志2"},"sub_partition":[]},{"partition":{"id_str":"6380","type":1,"title":"新不良人"},"sub_partition":[]}]},{"partition":{"id_str":"10000","type":3,"title":"娱乐天地"},"sub_partition":[{"partition":{"id_str":"2823","type":2,"title":"时尚"},"sub_partition":[]},{"partition":{"id_str":"2726","type":2,"title":"舞蹈"},"sub_partition":[]},{"partition":{"id_str":"2707","type":2,"title":"音乐"},"sub_partition":[]},{"partition":{"id_str":"2842","type":2,"title":"语音互动"},"sub_partition":[]},{"partition":{"id_str":"2836","type":2,"title":"情感"},"sub_partition":[]},{"partition":{"id_str":"2786","type":2,"title":"美食"},"sub_partition":[]},{"partition":{"id_str":"2791","type":2,"title":"运动"},"sub_partition":[]},{"partition":{"id_str":"2742","type":2,"title":"户外"},"sub_partition":[]}]},{"partition":{"id_str":"10001","type":3,"title":"科技文化"},"sub_partition":[{"partition":{"id_str":"2800","type":2,"title":"教育"},"sub_partition":[]},{"partition":{"id_str":"2756","type":2,"title":"人文艺术"},"sub_partition":[]}]}]}';
    var renderDataJson =
        json.decode(renderData.trim().replaceAll('\\"', '"').replaceAll(r"\\", r"\").replaceAll(']\\n', ""));
    for (var item in renderDataJson["categoryData"]) {
      List<LiveArea> subs = [];
      var id = '${item["partition"]["id_str"]},${item["partition"]["type"]}';
      for (var subItem in item["sub_partition"]) {
        var subCategory = LiveArea(
          areaId: '${subItem["partition"]["id_str"]},${subItem["partition"]["type"]}',
          typeName: item["partition"]["title"] ?? '',
          areaType: id,
          areaName: subItem["partition"]["title"] ?? '',
          areaPic: "",
          platform: 'douyin',
        );
        subs.add(subCategory);
      }

      var category = LiveCategory(
        children: subs,
        id: id,
        name: asT<String?>(item["partition"]["title"]) ?? "",
      );
      subs.insert(
          0,
          LiveArea(
            areaId: category.id,
            typeName: category.name,
            areaType: category.id,
            areaPic: "",
            areaName: category.name,
            platform: 'douyin',
          ));
      categories.add(category);
    }
    return categories;
  }

  @override
  Future<LiveCategoryResult> getCategoryRooms(LiveArea category, {int page = 1}) async {
    var ids = category.areaType?.split(',');
    var partitionId = ids?[0];
    var partitionType = ids?[1];

    var result = await HttpClient.instance.getText(
      "https://live.douyin.com/category/${partitionType}_$partitionId/",
      queryParameters: {'enter_from_merge': 'page_refresh'},
      header: await getRequestHeaders(),
    );
    var renderData = RegExp(r'\{\\"tdkMeta\\":.*?\]\\n').firstMatch(result)?.group(0) ?? "";
    var hasMore = false;
    var items = <LiveRoom>[];
    try {
      var text = renderData
          .trim()
          .replaceAll('\\"', '"')
          .replaceAll(r"\\", r"\")
          .replaceAll(']\n', "")
          .replaceAll(']\\n', "")
          .replaceAll("\$undefined", "")
          .toString();
      var renderDataJson = json.decode(text);
      hasMore = (renderDataJson["roomsData"]["data"] as List).length >= 15;

      for (var item in renderDataJson["roomsData"]["data"] ?? []) {
        var roomItem = LiveRoom(
          roomId: item["web_rid"],
          title: item["room"]["title"].toString(),
          cover: item["cover"],
          nick: item["room"]["owner"]["nickname"].toString(),
          liveStatus: LiveStatus.live,
          avatar: item["avatar"],
          status: true,
          platform: 'douyin',
          area: item['tag_name'].toString(),
          watching: item["room"]?["room_view_stats"]?["display_value"].toString() ?? '',
        );
        items.add(roomItem);
      }
    } catch (e) {
      log(e.toString());
    }
    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    var result = await HttpClient.instance.getJson(
      "https://live.douyin.com/webcast/web/partition/detail/room/",
      queryParameters: {
        "aid": 6383,
        "app_name": "douyin_web",
        "live_id": 1,
        "device_platform": "web",
        "count": 15,
        "offset": (page - 1) * 15,
        "partition": 720,
        "partition_type": 1,
      },
      header: await getRequestHeaders(),
    );

    var hasMore = (result["data"]["data"] as List).length >= 15;
    var items = <LiveRoom>[];

    for (var item in result["data"]["data"]) {
      var roomItem = LiveRoom(
        roomId: item["web_rid"],
        title: item["room"]["title"].toString(),
        cover: item["room"]["cover"]["url_list"][0].toString(),
        nick: item["room"]["owner"]["nickname"].toString(),
        platform: 'douyin',
        area: item["tag_name"] ?? '热门推荐',
        avatar: item["room"]["owner"]["avatar_thumb"]["url_list"][0].toString(),
        watching: item["room"]?["room_view_stats"]?["display_value"].toString() ?? '',
        liveStatus: LiveStatus.live,
      );
      items.add(roomItem);
    }
    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  @override
  Future<LiveRoom> getRoomDetail({required String roomId}) async {
    try {
      var detail = await getRoomWebDetail(roomId);
      var requestHeader = await getRequestHeaders();
      var webRid = roomId;
      var realRoomId = detail["roomStore"]["roomInfo"]["room"]["id_str"].toString();
      var userUniqueId = detail["userStore"]["odin"]["user_unique_id"].toString();
      var result = await HttpClient.instance.getJson(
        "https://live.douyin.com/webcast/room/web/enter/",
        queryParameters: {
          "aid": 6383,
          "app_name": "douyin_web",
          "live_id": 1,
          "device_platform": "web",
          "enter_from": "web_live",
          "web_rid": webRid,
          "room_id_str": realRoomId,
          "enter_source": "",
          "Room-Enter-User-Login-Ab": 0,
          "is_need_double_stream": false,
          "cookie_enabled": true,
          "screen_width": 1980,
          "screen_height": 1080,
          "browser_language": "zh-CN",
          "browser_platform": "Win32",
          "browser_name": "Edge",
          "browser_version": "120.0.0.0"
        },
        header: requestHeader,
      );
      var roomInfo = result["data"]["data"][0];
      var userInfo = result["data"]["user"];
      var partition = result["data"]['partition_road_map'];
      var roomStatus = (asT<int?>(roomInfo["status"]) ?? 0) == 2;
      return LiveRoom(
        roomId: roomId,
        title: roomInfo["title"].toString(),
        cover: roomStatus ? roomInfo["cover"]["url_list"][0].toString() : "",
        nick: userInfo["nickname"].toString(),
        avatar: userInfo["avatar_thumb"]["url_list"][0].toString(),
        watching: roomInfo?["room_view_stats"]?["display_value"].toString() ?? '',
        liveStatus: roomStatus ? LiveStatus.live : LiveStatus.offline,
        link: "https://live.douyin.com/$webRid",
        area: partition?['partition']?['title'].toString() ?? '',
        status: roomStatus,
        platform: 'douyin',
        introduction: roomInfo["title"].toString(),
        notice: "",
        danmakuData: DouyinDanmakuArgs(
          webRid: webRid,
          roomId: realRoomId,
          userId: userUniqueId,
          cookie: headers["cookie"],
        ),
        data: roomInfo["stream_url"],
      );
    } catch (e) {
      LiveRoom liveRoom = settings.getLiveRoomByRoomId(roomId);
      liveRoom.liveStatus = LiveStatus.offline;
      liveRoom.status = false;
      return liveRoom;
    }
  }

  Future<Map> getRoomWebDetail(String webRid) async {
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
    });
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

    var renderData = RegExp(r'\{\\"state\\":\{\\"isLiveModal.*?\]\\n').firstMatch(result)?.group(0) ?? "";
    var str = renderData.trim().replaceAll('\\"', '"').replaceAll(r"\\", r"\").replaceAll(']\\n', "");
    var renderDataJson = json.decode(str);

    return renderDataJson["state"];
    // return renderDataJson["app"]["initialState"]["roomStore"]["roomInfo"]
    //         ["room"]["id_str"]
    //     .toString();
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites({required LiveRoom detail}) async {
    List<LivePlayQuality> qualities = [];
    var qualityData = json.decode(detail.data["live_core_sdk_data"]["pull_data"]["stream_data"])["data"];
    var qulityList = detail.data["live_core_sdk_data"]["pull_data"]["options"]["qualities"];
    for (var quality in qulityList) {
      var qualityItem = LivePlayQuality(
        quality: quality["name"],
        sort: quality["level"],
        data: <String>[
          qualityData[quality["sdk_key"]]["main"]["flv"].toString(),
          qualityData[quality["sdk_key"]]["main"]["hls"].toString(),
        ],
      );
      qualities.add(qualityItem);
    }
    qualities.sort((a, b) => b.sort.compareTo(a.sort));
    return qualities;
  }

  @override
  Future<List<String>> getPlayUrls({required LiveRoom detail, required LivePlayQuality quality}) async {
    return quality.data;
  }

  @override
  Future<LiveSearchRoomResult> searchRooms(String keyword, {int page = 1}) async {
    String serverUrl = "https://www.douyin.com/aweme/v1/web/live/search/";
    var uri = Uri.parse(serverUrl).replace(scheme: "https", port: 443, queryParameters: {
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
      "browser_version": "114.0.1823.58",
      "browser_online": "true",
      "engine_name": "Blink",
      "engine_version": "114.0.0.0",
      "os_name": "Windows",
      "os_version": "10",
      "cpu_core_num": "12",
      "device_memory": "8",
      "platform": "PC",
      "downlink": "4.7",
      "effective_type": "4g",
      "round_trip_time": "100",
      "webid": "7247041636524377637",
    });
    var requlestUrl = await signUrl(uri.toString());
    var result = await HttpClient.instance.getJson(
      requlestUrl,
      queryParameters: {},
      header: {
        "Accept":
            "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
        "Authority": kDefaultAuthority,
        "Referer": kDefaultReferer,
        "Cookie": "__ac_nonce=${generateRandomString(21)}",
        "User-Agent": kDefaultUserAgent,
      },
    );
    var items = <LiveRoom>[];
    var queryList = result["data"] ?? [];
    for (var item in queryList) {
      var itemData = json.decode(item["lives"]["rawdata"].toString());
      var roomStatus = (asT<int?>(itemData["status"]) ?? 0) == 2;
      var roomItem = LiveRoom(
        roomId: itemData["owner"]["web_rid"].toString(),
        title: itemData["title"].toString(),
        cover: itemData["cover"]["url_list"][0].toString(),
        nick: itemData["owner"]["nickname"].toString(),
        platform: 'douyin',
        avatar: itemData["owner"]["avatar_thumb"]["url_list"][0].toString(),
        liveStatus: roomStatus ? LiveStatus.live : LiveStatus.offline,
        area: '',
        status: roomStatus,
        watching: itemData["stats"]["total_user_str"].toString(),
      );
      items.add(roomItem);
    }
    return LiveSearchRoomResult(hasMore: queryList.length > 0, items: items);
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(String keyword, {int page = 1}) async {
    throw Exception("抖音暂不支持搜索主播，请直接搜索直播间");
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    var result = await getRoomDetail(roomId: roomId);
    return result.status!;
  }

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage({required String roomId}) {
    return Future.value(<LiveSuperChatMessage>[]);
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

  Future<String> signUrl(String url) async {
    try {
      // 发起一个签名请求
      // 服务端代码：https://github.com/5ime/Tiktok_Signature
      var signResult = await HttpClient.instance.postJson(
        "https://tk.nsapps.cn/",
        queryParameters: {},
        header: {"Content-Type": "application/json"},
        data: {"url": url, "userAgent": kDefaultUserAgent},
      );
      var requlestUrl = signResult["data"]["url"].toString();
      return requlestUrl;
    } catch (e) {
      CoreLog.error(e);
      return url;
    }
  }
}
