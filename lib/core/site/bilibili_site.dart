// ignore_for_file: avoid_function_literals_in_foreach_calls

import 'dart:convert';
import 'dart:developer';
import 'package:pure_live/core/danmaku/bilibili_danmaku.dart';
import 'package:pure_live/core/interface/live_danmaku.dart';
import 'package:pure_live/common/models/index.dart';
import 'package:http/http.dart' as http;

import '../interface/live_site.dart';

class BilibiliSite implements LiveSite {
  @override
  String id = 'bilibili';

  @override
  String name = '哔哩';

  @override
  LiveDanmaku getDanmaku() => BiliBiliDanmaku();

  static Future<dynamic> _getJson(String url) async {
    Map<String, String> headers = {
      'User-Agent':
          'Mozilla/5.0 (iPhone; CPU iPhone OS 12_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148',
      'cookie': 'buvid3=infoc;'
    };

    var resp = await http.get(
      Uri.parse(url),
      headers: headers,
    );
    return await jsonDecode(utf8.decode(resp.bodyBytes));
  }

  @override
  Future<Map<String, List<String>>> getLiveStream(LiveRoom room) async {
    Map<String, List<String>> links = {};

    String defaultQn = '10000';
    String reqUrl =
        'https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo'
        '?room_id=${room.roomId}&qn=$defaultQn&platform=h5&ptype=8'
        '&codec=0,1&format=0,1,2&protocol=0,1';

    try {
      dynamic streamJson = await _getJson(reqUrl);

      // get quality name map
      var qnMap = <int, String>{};
      var qnList = streamJson['data']['playurl_info']['playurl']['g_qn_desc'];
      for (var item in qnList) {
        qnMap[item['qn']] = item['desc'];
      }

      // get supported rates
      var streamList = streamJson['data']['playurl_info']['playurl']['stream'];
      var streamProtocol =
          streamList[1]['format'][0] ?? streamList[0]['format'][0];
      List<dynamic> rates = streamProtocol['codec'][0]['accept_qn'];

      for (var qn in rates) {
        var name = qnMap[qn] ?? qn.toString();

        String qnUrl =
            'https://api.live.bilibili.com/xlive/web-room/v2/index/getRoomPlayInfo'
            '?room_id=${room.roomId}&qn=$qn&platform=h5&ptype=8'
            '&codec=0,1&format=0,1,2&protocol=0,1';
        dynamic qnJson = await _getJson(qnUrl);

        var qnStreamList = qnJson['data']['playurl_info']['playurl']['stream'];
        var qnStreamProtocol =
            qnStreamList[1]['format'][0] ?? qnStreamList[0]['format'][0];

        // get m3u8 default, if not, get unplayable flv
        for (int i = 0; i < qnStreamList.length; i++) {
          if (qnStreamList[i]['protocol_name'] == 'http_hls') {
            for (int j = 0; j < qnStreamList[i]['format'].length; j++) {
              if (qnStreamList[i]['format'][j]['format_name'] == 'fmp4') {
                qnStreamProtocol = qnStreamList[i]['format'][j];
                break;
              }
            }
          }
        }

        links[name] ??= [];
        var baseUrl = qnStreamProtocol['codec'][0]['base_url'];
        var urlInfo = qnStreamProtocol['codec'][0]['url_info'];
        for (var item in urlInfo) {
          links[name]?.add("${item['host']}$baseUrl${item['extra']}");
        }
      }
    } catch (e) {
      log(e.toString(), name: 'BilibiliApi.getRoomStreamLink');
      return links;
    }
    return links;
  }

  @override
  Future<LiveRoom> getRoomInfo(LiveRoom room) async {
    String reqUrl = 'https://api.live.bilibili.com/xlive/web-room/v1/index/'
        'getH5InfoByRoom?room_id=${room.roomId}';

    try {
      dynamic response = await _getJson(reqUrl);
      if (response['code'] == 0) {
        Map data = response['data'];
        room.platform = 'bilibili';
        room.userId = room.roomId;
        room.title = data['room_info']?['title'] ?? '';
        room.nick = data['anchor_info']?['base_info']?['uname'] ?? '';
        room.cover = data['room_info']?['cover'] ?? '';
        room.avatar = data['anchor_info']?['base_info']?['face'] ?? '';
        room.area = data['room_info']?['area_name'] ?? '';
        room.watching = data['watched_show']?['num']?.toString() ?? '';
        room.followers =
            data['anchor_info']?['relation_info']?['attention']?.toString() ??
                '';
        room.liveStatus = (data['room_info']?.containsKey('live_status') &&
                data['room_info']?['live_status'] == 1)
            ? LiveStatus.live
            : LiveStatus.offline;
      }
    } catch (e) {
      log(e.toString(), name: 'BilibiliApi.getRoomInfo');
      return room;
    }
    return room;
  }

  @override
  Future<List<LiveRoom>> getRecommend({int page = 1, int size = 20}) async {
    List<LiveRoom> list = [];
    String url = 'https://api.live.bilibili.com/room/v1/room/get_user_recommend'
        '?page=$page&page_size=$size';

    try {
      dynamic response = await _getJson(url);
      if (response['code'] == 0) {
        List<dynamic> roomList = response['data'];
        for (var roomInfo in roomList) {
          var room = LiveRoom(roomInfo['roomid'].toString());
          room.platform = 'bilibili';
          room.userId = room.roomId;
          room.nick = roomInfo['uname'] ?? '';
          room.title = roomInfo['title'] ?? '';
          room.cover = roomInfo['user_cover'];
          room.avatar = roomInfo['face'];
          room.area = roomInfo['areaName'] ?? '';
          room.watching = roomInfo['watched_show']?['num']?.toString() ?? '';
          room.liveStatus = LiveStatus.live;
          list.add(room);
        }
      }
    } catch (e) {
      log(e.toString(), name: 'BilibiliApi.getRecommend');
      return list;
    }
    return list;
  }

  @override
  Future<List<List<LiveArea>>> getAreaList() async {
    List<List<LiveArea>> areaList = [];
    String url =
        'https://api.live.bilibili.com/xlive/web-interface/v1/index/getWebAreaList?source_id=2';

    try {
      dynamic response = await _getJson(url);
      if (response['code'] == 0) {
        List<dynamic> data = response['data']['data'];
        data.forEach((areaType) {
          List<LiveArea> subAreaList = [];
          List<dynamic> areaInfoList = areaType['list'];
          areaInfoList.forEach((areaInfo) {
            LiveArea area = LiveArea();
            area.platform = 'bilibili';
            area.areaType = areaInfo['parent_id']?.toString() ?? '';
            area.typeName = areaInfo['parent_name'] ?? '';
            area.areaId = areaInfo['id']?.toString() ?? '';
            area.areaName = areaInfo['name'] ?? '';
            area.areaPic = areaInfo['pic'] ?? '';
            subAreaList.add(area);
          });
          areaList.add(subAreaList);
        });
      }
    } catch (e) {
      log(e.toString(), name: 'BilibiliApi.getAreaList');
      return areaList;
    }
    return areaList;
  }

  @override
  Future<List<LiveRoom>> getAreaRooms(LiveArea area,
      {int page = 1, int size = 20}) async {
    List<LiveRoom> list = [];
    String url =
        'https://api.live.bilibili.com/xlive/web-interface/v1/second/getList?'
        'platform=web&parent_area_id=${area.areaType}&area_id=${area.areaId}&'
        'sort_type=&page=$page';

    try {
      dynamic response = await _getJson(url);
      if (response['code'] == 0) {
        List<dynamic> roomInfoList = response['data']['list'];
        for (var roomInfo in roomInfoList) {
          var room = LiveRoom(roomInfo['roomid'].toString());
          room.platform = 'bilibili';
          room.userId = room.roomId;
          room.nick = roomInfo['uname'] ?? '';
          room.title = roomInfo['title'] ?? '';
          room.cover = roomInfo['cover'] ?? '';
          room.avatar = roomInfo['face'] ?? '';
          room.area = area.areaName;
          room.watching = roomInfo['watched_show']?['num']?.toString() ?? '';
          room.liveStatus = LiveStatus.live;
          list.add(room);
        }
      }
    } catch (e) {
      log(e.toString(), name: 'BilibiliApi.getAreaRooms');
      return list;
    }
    return list;
  }

  @override
  Future<List<LiveRoom>> search(String keyWords) async {
    List<LiveRoom> list = [];
    String url = 'https://api.bilibili.com/x/web-interface/search/'
        'type?context=&search_type=live_user&cover_type=user_cover'
        '&page=1&order=&keyword=$keyWords&category_id=&__refresh__=true'
        '&_extra=&highlight=1&single_column=0';

    try {
      dynamic response = await _getJson(url);
      if (response['code'] == 0) {
        List<dynamic> ownerList = response['data']['result'];
        for (Map ownerInfo in ownerList) {
          LiveRoom owner = LiveRoom(ownerInfo['roomid'].toString());
          owner.platform = 'bilibili';
          owner.userId = owner.roomId;
          final nick = ownerInfo['uname'] ?? '';
          owner.nick = nick
              .replaceAll('<em class="keyword">', '')
              .replaceAll('</em>', '');
          owner.avatar = 'https:${ownerInfo['uface'] ?? ''}';
          owner.area = ownerInfo['cate_name'] ?? '';
          owner.followers = ownerInfo['attentions']?.toString() ?? '';
          owner.liveStatus = (ownerInfo['is_live'] ?? false)
              ? LiveStatus.live
              : LiveStatus.offline;
          list.add(owner);
        }
      }
    } catch (e) {
      log(e.toString(), name: 'BilibiliApi.search');
      return list;
    }
    return list;
  }
}
