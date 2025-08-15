import 'package:dio/dio.dart' as dio;
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/common/core_log.dart';
import 'package:pure_live/routes/app_navigation.dart';

class ToolBoxController extends GetxController {
  final TextEditingController roomJumpToController = TextEditingController();
  final TextEditingController getUrlController = TextEditingController();

  void jumpToRoom(String e) async {
    if (e.isEmpty) {
      SmartDialog.showToast(S.current.link_empty);
      return;
    }
    var parseResult = await parse(e);
    if (parseResult.isEmpty || parseResult.first == "") {
      SmartDialog.showToast(S.current.live_room_link_parse_failed);
      return;
    }
    String platform = parseResult[1];

    AppNavigator.toLiveRoomDetail(
      liveRoom: LiveRoom(
        roomId: parseResult.first,
        platform: platform,
        title: "",
        cover: '',
        nick: "",
        watching: '',
        avatar: "",
        area: '',
        liveStatus: LiveStatus.live,
        status: true,
        data: '',
        danmakuData: '',
      ),
    );
  }

  void getPlayUrl(String e) async {
    if (e.isEmpty) {
      SmartDialog.showToast(S.current.link_empty);
      return;
    }
    var parseResult = await parse(e);
    if (parseResult.isEmpty && parseResult.first == "") {
      SmartDialog.showToast(S.current.live_room_link_parse_failed);
      return;
    }
    String platform = parseResult[1];
    try {
      SmartDialog.showLoading(msg: "");
      var detail = await Sites.of(platform).liveSite.getRoomDetail(
            roomId: parseResult.first,
            platform: platform,
            nick: '',
            title: '',
          );
      var qualites = await Sites.of(platform).liveSite.getPlayQualites(detail: detail);
      SmartDialog.dismiss(status: SmartStatus.loading);
      if (qualites.isEmpty) {
        SmartDialog.showToast(S.current.live_room_clarity_parse_failed);

        return;
      }
      var result = await Get.dialog(SimpleDialog(
        title: Text(S.current.live_room_clarity_select),
        children: qualites
            .map(
              (e) => ListTile(
                title: Text(
                  e.quality,
                  textAlign: TextAlign.center,
                ),
                onTap: () {
                  Navigator.of(Get.context!).pop(e);
                },
              ),
            )
            .toList(),
      ));
      if (result == null) {
        return;
      }
      SmartDialog.showLoading(msg: "");
      var playUrls = await Sites.of(platform).liveSite.getPlayUrls(detail: detail, quality: result);
      SmartDialog.dismiss(status: SmartStatus.loading);
      await Get.dialog(SimpleDialog(
        title: Text(S.current.live_room_clarity_line_select),
        children: playUrls
            .map(
              (e) => ListTile(
                title: Text(
                  "${S.current.live_room_clarity_line} ${playUrls.indexOf(e) + 1}",
                ),
                subtitle: Text(
                  e.playUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: e.playUrl));
                  Navigator.of(Get.context!).pop();
                  SmartDialog.showToast(S.current.live_room_link_direct_copied);
                },
              ),
            )
            .toList(),
      ));
    } catch (e) {
      CoreLog.error(e);
      SmartDialog.showToast(S.current.live_room_link_direct_read_failed);
    } finally {
      SmartDialog.dismiss(status: SmartStatus.loading);
    }
  }

  Future<List> parse(String url) async {
    final urlRegExp = RegExp(r"((https?:www\.)|(https?:\/\/)|(www\.))[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9]{1,6}(\/[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)?");
    List<String?> urlMatches = urlRegExp.allMatches(url).map((m) => m.group(0)).toList();
    if (urlMatches.isEmpty) return [];
    String realUrl = urlMatches.first!;
    var id = "";
    realUrl = urlMatches.first!;

    // 解析跳转
    List<RegExp> regExpJumpList = [
      // bilibili 网站 解析跳转
      RegExp(r"https?:\/\/b23.tv\/[0-9a-z-A-Z]+")

    ];
    for (var i = 0; i < regExpJumpList.length; i++) {
      var regExp = regExpJumpList[i];
      var u = regExp.firstMatch(realUrl)?.group(0) ?? "";
      if(u != "") {
        var location = await getLocation(u);
        return await parse(location);
      }
    }

    if (realUrl.contains("v.douyin.com")) {
      final id = await getRealDouyinUrl(realUrl);
      return [id, Sites.douyinSite];
    }

    List<RegExpBean> regExpBeanList = [
      // bilibili 网站匹配
      RegExpBean(regExp: RegExp(r"bilibili\.com/([\d|\w]+)$"), siteType: Sites.bilibiliSite),
      RegExpBean(regExp: RegExp(r"bilibili\.com/h5/([\d\w]+)$"), siteType: Sites.bilibiliSite),

      // 斗鱼
      RegExpBean(regExp: RegExp(r"douyu\.com/([\d|\w]+)[/]?$"), siteType: Sites.douyuSite),
      RegExpBean(regExp: RegExp(r"douyu\.com/topic/[\w\d]+\?.*rid=([^&]+).*$"), siteType: Sites.douyuSite),

      // 虎牙
      RegExpBean(regExp: RegExp(r"huya\.com/([\d|\w]+)$"), siteType: Sites.huyaSite),

      // 快手
      RegExpBean(regExp: RegExp(r"live\.kuaishou\.com/u/([a-zA-Z0-9]+)$"), siteType: Sites.kuaishouSite),

      // 抖音
      RegExpBean(regExp: RegExp(r"live\.douyin\.com/([\d|\w]+)"), siteType: Sites.douyinSite),

      // 网易 CC
      RegExpBean(regExp: RegExp(r"cc\.163\.com/([a-zA-Z0-9]+)$"), siteType: Sites.ccSite),
      RegExpBean(regExp: RegExp(r"cc\.163\.com/cc/([a-zA-Z0-9]+)$"), siteType: Sites.ccSite),

    ];
    for (var i = 0; i < regExpBeanList.length; i++) {
      var regExpBean = regExpBeanList[i];
      id = regExpBean.regExp.firstMatch(realUrl)?.group(1) ?? "";
      if (id != "") {
        return [id, regExpBean.siteType];
      }
    }

    return [];
  }

  Future<String> getRealDouyinUrl(String url) async {
    final urlRegExp = RegExp(r"((https?:www\.)|(https?:\/\/)|(www\.))[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9]{1,6}(\/[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)?");
    List<String?> urlMatches = urlRegExp.allMatches(url).map((m) => m.group(0)).toList();
    String realUrl = urlMatches.first!;
    var headers = {
      "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
      "Accept": "*/*",
      "Accept-Encoding": "gzip, deflate, br, zstd",
      "Origin": "https://live.douyin.com",
      "Referer": "https://live.douyin.com/",
      "Sec-Fetch-Site": "cross-site",
      "Sec-Fetch-Mode": "cors",
      "Sec-Fetch-Dest": "empty",
      "Accept-Language": "zh-CN,zh;q=0.9"
    };
    dio.Response response = await dio.Dio().get(
      realUrl,
      options: dio.Options(followRedirects: true, headers: headers, maxRedirects: 100),
    );
    final liveResponseRegExp = RegExp(r"/reflow/(\d+)");
    String reflow = liveResponseRegExp.firstMatch(response.realUri.toString())?.group(0) ?? "";
    var liveResponse = await dio.Dio().get("https://webcast.amemv.com/webcast/room/reflow/info/", queryParameters: {
      "room_id": reflow.split("/").last.toString(),
      'verifyFp': '',
      'type_id': 0,
      'live_id': 1,
      'sec_user_id': '',
      'app_id': 1128,
      'msToken': '',
      'X-Bogus': '',
    });
    var room = liveResponse.data['data']['room']['owner']['web_rid'];
    return room.toString();
  }

  Future<String> getLocation(String url) async {
    try {
      if (url.isEmpty) return "";
      await dio.Dio().get(
        url,
        options: dio.Options(
          followRedirects: false,
        ),
      );
    } on dio.DioException catch (e) {
      CoreLog.error(e);
      if (e.response!.statusCode == 302) {
        var redirectUrl = e.response!.headers.value("Location");
        if (redirectUrl != null) {
          return redirectUrl;
        }
      }
    } catch (e) {
      CoreLog.error(e);
    }
    return "";
  }
}

class RegExpBean {
  late RegExp regExp;
  late String siteType;

  RegExpBean({
    required this.regExp,
    required this.siteType,
  });
}
