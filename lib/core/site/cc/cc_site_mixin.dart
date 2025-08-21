import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/interface/live_site_mixin.dart';

mixin CCSiteMixin on SiteAccount, SiteVideoHeaders, SiteOpen, SiteParse {
  final platform = Sites.ccSite;
  @override
  String getJumpToNativeUrl(LiveRoom liveRoom) {
    try {
      return "cc://join-room/${liveRoom.roomId}/${liveRoom.userId}/";
    } catch (e) {
      return "";
    }
  }

  @override
  String getJumpToWebUrl(LiveRoom liveRoom) => "https://cc.163.com/${liveRoom.roomId}";

  @override
  Future<SiteParseBean> parse(String url) async {
    String realUrl = getHttpUrl(url);
    var siteParseBean = emptySiteParseBean;
    if(realUrl.isEmpty) return siteParseBean;
    // 解析跳转
    List<RegExp> regExpJumpList = [
    ];
    siteParseBean = await parseJumpUrl(regExpJumpList, realUrl);
    if(siteParseBean.roomId.isNotEmpty) {
      return siteParseBean;
    }

    List<RegExp> regExpBeanList = [
      // 网易 CC
      RegExp(r"cc\.163\.com/([a-zA-Z0-9]+)$"),
      RegExp(r"cc\.163\.com/cc/([a-zA-Z0-9]+)$"),
    ];
    siteParseBean = await parseUrl(regExpBeanList, realUrl, platform);
    return siteParseBean;
  }
}
