import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/common/core_log.dart';
import 'package:pure_live/core/site/douyin/douyin_danmaku.dart';
import 'package:pure_live/core/interface/live_site_mixin.dart';

mixin DouyinSiteMixin on SiteAccount, SiteVideoHeaders, SiteOpen {
  @override
  String getJumpToNativeUrl(LiveRoom liveRoom) {
    try {
      var args = liveRoom.danmakuData as DouyinDanmakuArgs;
      return "snssdk1128://webcast_room?room_id=${args.roomId}";
    } catch (e) {
      CoreLog.w("$e");
      return "";
    }
  }

  @override
  String getJumpToWebUrl(LiveRoom liveRoom) {
    try {
      var args = liveRoom.danmakuData as DouyinDanmakuArgs;
      return "https://live.douyin.com/${args.webRid}";
    } catch (e) {
      CoreLog.w("$e");
      return "";
    }
  }
}
