import 'dart:convert';
import 'dart:developer';
import 'dart:math' as math;
import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/danmaku/douyin_danmaku.dart';
import 'package:pure_live/plugins/http_client.dart';

import '../interface/live_danmaku.dart';
import '../interface/live_site.dart';

class DouyinSite implements LiveSite {
  @override
  String id = 'douyin';

  @override
  String name = '抖音';

  @override
  LiveDanmaku getDanmaku() => DouyinDanmaku();
  Map<String, dynamic> headers = {
    "Authority": "live.douyin.com",
    "Referer": "https://live.douyin.com",
    "User-Agent":
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.51",
  };

  Future<Map<String, dynamic>> getRequestHeaders() async {
    try {
      if (headers.containsKey("cookie")) {
        return headers;
      }
      var head = await HttpClient.instance
          .head("https://live.douyin.com", header: headers);
      head.headers["set-cookie"]?.forEach((element) {
        var cookie = element.split(";")[0];
        if (cookie.contains("ttwid")) {
          headers["cookie"] = cookie;
        }
      });
      return headers;
    } catch (e) {
      return headers;
    }
  }

  @override
  Future<List<List<LiveArea>>> getAreaList() async {
    List<List<LiveArea>> areaList = [];

    try {
      var result = await HttpClient.instance.getText(
        "https://live.douyin.com/hot_live",
        queryParameters: {},
        header: {
          "Authority": "live.douyin.com",
          "Referer": "https://live.douyin.com",
          "User-Agent":
              "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.51",
        },
      );

      var renderData =
          RegExp(r'\{\\"pathname\\":\\"\/hot_live\\",\\"categoryData.*?\]\\n')
                  .firstMatch(result)
                  ?.group(0) ??
              "";
      var renderDataJson = json.decode(renderData
          .trim()
          .replaceAll('\\"', '"')
          .replaceAll(r"\\", r"\")
          .replaceAll(']\\n', ""));

      List<dynamic> data = renderDataJson["categoryData"] ?? [];
      for (var areaType in data) {
        List<LiveArea> subAreaList = [];
        List<dynamic> areaInfoList = areaType["sub_partition"];
        var id =
            '${areaType["partition"]["id_str"]},${areaType["partition"]["type"]}';
        for (var areaInfo in areaInfoList) {
          var subId =
              '${areaInfo["partition"]["id_str"]},${areaInfo["partition"]["type"]}';
          LiveArea area = LiveArea();
          area.platform = 'douyin';
          area.areaType = id;
          area.typeName = areaType["partition"]["title"] ?? '';
          area.areaId = subId;
          area.areaName = areaInfo["partition"]["title"] ?? '';
          area.areaPic = areaInfo['pic'] ?? '';
          subAreaList.add(area);
        }
        areaList.add(subAreaList);
      }
    } catch (e) {
      log(e.toString(), name: 'DouyuApi.getAreaList');
      return areaList;
    }
    return areaList;
  }

  @override
  Future<List<LiveRoom>> getAreaRooms(LiveArea area,
      {int page = 1, int size = 20}) async {
    List<LiveRoom> list = [];

    try {
      var ids = area.areaId.split(',');
      var partitionId = ids[0];
      var partitionType = ids[1];
      var result = await HttpClient.instance.getJson(
        "https://live.douyin.com/webcast/web/partition/detail/room/",
        queryParameters: {
          "aid": 6383,
          "app_name": "douyin_web",
          "live_id": 1,
          "device_platform": "web",
          "count": 20,
          "offset": (page - 1) * 20,
          "partition": partitionId,
          "partition_type": partitionType,
          "req_from": 2
        },
        header: await getRequestHeaders(),
      );
      List<dynamic> roomInfoList = result["data"]["data"] ?? [];
      for (var roomInfo in roomInfoList) {
        var room = LiveRoom(roomInfo['web_rid'].toString());
        room.platform = 'douyin';
        room.userId = roomInfo['web_rid'];
        room.nick = roomInfo["room"]["owner"]["nickname"] ?? '';
        room.title = roomInfo["room"]["title"] ?? '';
        room.cover = roomInfo["room"]["cover"]["url_list"][0] ?? '';
        room.avatar =
            roomInfo["room"]["owner"]["avatar_thumb"]["url_list"][0].toString();
        room.area = roomInfo['tag_name'];
        room.watching =
            roomInfo["room"]?["room_view_stats"]?["display_value"].toString() ??
                '';
        room.liveStatus = LiveStatus.live;
        list.add(room);
      }
    } catch (e) {
      log(e.toString(), name: 'BilibiliApi.getAreaRooms');
      return list;
    }
    return list;
  }

  @override
  Future<Map<String, List<String>>> getLiveStream(LiveRoom room) async {
    Map<String, List<String>> links = {};
    try {
      var detail = await getRoomWebDetail(room.roomId);
      var requestHeader = await getRequestHeaders();
      var webRid = room.roomId;
      var realRoomId =
          detail["roomStore"]["roomInfo"]["room"]["id_str"].toString();
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
          "browser_version": "114.0.1823.51"
        },
        header: requestHeader,
      );

      var roomInfo = result["data"]["data"][0];
      Map data = roomInfo["stream_url"];
      var streamflvUrls = [];
      var streamhlsUrls = [];
      data['flv_pull_url'].forEach((key, value) {
        streamflvUrls.add(value);
      });
      data['hls_pull_url_map'].forEach((key, value) {
        streamhlsUrls.add(value);
      });
      List<String> resolutions = ['原画', '蓝光8M', '蓝光4M', '超清', '流畅'];
      var index = 0;
      for (var rate in resolutions.take(streamflvUrls.length)) {
        links[rate] ??= [];
        links[rate]?.add(streamflvUrls[index]);
        links[rate]?.add(streamhlsUrls[index]);
        index++;
      }
    } catch (e) {
      log(e.toString(), name: 'HuyaApi.getRoomStreamLink');
      return links;
    }
    return links;
  }

  @override
  Future<List<LiveRoom>> getRecommend({int page = 1, int size = 20}) async {
    List<LiveRoom> list = [];

    try {
      var result = await HttpClient.instance.getJson(
        "https://live.douyin.com/webcast/web/partition/detail/room/",
        queryParameters: {
          "aid": 6383,
          "app_name": "douyin_web",
          "live_id": 1,
          "device_platform": "web",
          "count": 20,
          "offset": (page - 1) * 20,
          "partition": 720,
          "partition_type": 1,
        },
        header: await getRequestHeaders(),
      );
      //  debugPrint(result["data"]["data"].toString());
      for (var roomInfo in result["data"]["data"] ?? []) {
        var room = LiveRoom(roomInfo['web_rid'].toString());
        room.platform = 'douyin';
        room.userId = roomInfo['web_rid'];
        room.nick = roomInfo["room"]["owner"]["nickname"] ?? '';
        room.title = roomInfo["room"]["title"] ?? '';
        room.cover = roomInfo["room"]["cover"]["url_list"][0] ?? '';
        room.avatar =
            roomInfo["room"]["owner"]["avatar_thumb"]["url_list"][0].toString();
        room.area = roomInfo['tag_name'];
        room.watching =
            roomInfo["room"]?["room_view_stats"]?["display_value"].toString() ??
                '';
        room.liveStatus = LiveStatus.live;
        list.add(room);
      }
    } catch (e) {
      log(e.toString(), name: 'DouYinApi.getRecommend');
      return list;
    }
    return list;
  }

  Future<Map> getRoomWebDetail(String webRid) async {
    var result = await HttpClient.instance.getText(
      "https://live.douyin.com/$webRid",
      queryParameters: {},
      header: {
        "Accept":
            "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
        "Authority": "live.douyin.com",
        "Referer": "https://live.douyin.com",
        "Cookie": "__ac_nonce=${generateRandomString(21)}",
        "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.51",
      },
    );

    var renderData = RegExp(r'\{\\"state\\":\{\\"isLiveModal.*?\]\\n')
            .firstMatch(result)
            ?.group(0) ??
        "";
    var str = renderData
        .trim()
        .replaceAll('\\"', '"')
        .replaceAll(r"\\", r"\")
        .replaceAll(']\\n', "");
    var renderDataJson = json.decode(str);

    return renderDataJson["state"];
    // return renderDataJson["app"]["initialState"]["roomStore"]["roomInfo"]
    //         ["room"]["id_str"]
    //     .toString();
  }

  Future<DouyinDanmakuArgs?> getDouyinDanmakuArgs(String roomId) async {
    try {
      var detail = await getRoomWebDetail(roomId);
      var realRoomId = detail["roomStore"]["roomInfo"]["room"]["id_str"].toString();
      var webRid = roomId;
      var userUniqueId =
          detail["userStore"]["odin"]["user_unique_id"].toString();
      return DouyinDanmakuArgs(
        webRid: webRid,
        roomId: realRoomId,
        userId: userUniqueId,
        cookie: headers["cookie"] ?? '',
      );
    } catch (e) {
      log(e.toString(), name: 'DouYin.getDouyinDanmakuArgs');
      return null;
    }
  }

  @override
  Future<LiveRoom> getRoomInfo(LiveRoom room) async {
    try {
      var detail = await getRoomWebDetail(room.roomId);
      var requestHeader = await getRequestHeaders();
      var webRid = room.roomId;
      var realRoomId =
          detail["roomStore"]["roomInfo"]["room"]["id_str"].toString();
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
          "browser_version": "114.0.1823.51"
        },
        header: requestHeader,
      );

      var roomInfo = result["data"]["data"][0];
      var userInfo = result["data"]["user"];
      room.followers = userInfo['follow_info']['follow_status_str'] ?? '';
      room.liveStatus =
          roomInfo['status'] == 2 ? LiveStatus.live : LiveStatus.offline;
    } catch (e) {
      log(e.toString(), name: 'BilibiliApi.getRoomInfo');
      return room;
    }
    return room;
  }

  @override
  Future<List<LiveRoom>> search(String keyWords) async {
    List<LiveRoom> list = [];

    try {
      String serverUrl = "https://www.douyin.com/aweme/v1/web/live/search/";

      var uri = Uri.parse(serverUrl)
          .replace(scheme: "https", port: 443, queryParameters: {
        "device_platform": "webapp",
        "aid": "6383",
        "channel": "channel_pc_web",
        "search_channel": "aweme_live",
        "keyword": keyWords,
        "search_source": "switch_tab",
        "query_correct_type": "1",
        "is_filter_search": "0",
        "from_group_id": "",
        "offset": ((1 - 1) * 10).toString(),
        "count": "20",
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
          "Authority": "live.douyin.com",
          "Referer": "https://www.douyin.com/",
          "Cookie": "__ac_nonce=${generateRandomString(21)}",
          "User-Agent":
              "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.51",
        },
      );
      List<dynamic> ownerList = result["data"] ?? [];
      // log(json.decode(ownerList[0]["lives"]["rawdata"].toString())["owner"]["web_rid"].toString());
      for (var item in ownerList) {
        var ownerInfo = json.decode(item["lives"]["rawdata"].toString());

        LiveRoom owner = LiveRoom(ownerInfo["owner"]["web_rid"].toString());
        owner.platform = "douyin";
        owner.userId = ownerInfo["owner"]["web_rid"]?.toString() ?? '';
        owner.nick = ownerInfo["owner"]["nickname"] ?? '';
        owner.title = ownerInfo["title"] ?? '';
        owner.cover = ownerInfo["cover"]["url_list"][0] ?? '';
        owner.avatar =
            ownerInfo["owner"]["avatar_thumb"]["url_list"][0].toString();
        owner.liveStatus = ownerInfo["owner"]['status'] == 2
            ? LiveStatus.live
            : LiveStatus.offline;
        list.add(owner);
      }
    } catch (e) {
      log(e.toString(), name: 'DouyinApi.search');
      return list;
    }
    return list;
  }

  Future<String> signUrl(String url) async {
    try {
      // 发起一个签名请求
      // 服务端代码：https://github.com/5ime/Tiktok_Signature
      var signResult = await HttpClient.instance.postJson(
        "https://tk.nsapps.cn/",
        queryParameters: {},
        header: {"Content-Type": "application/json"},
        data: {
          "url": url,
          "userAgent":
              "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.51"
        },
      );
      var requlestUrl = signResult["data"]["url"].toString();
      return requlestUrl;
    } catch (e) {
      return url;
    }
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
}
