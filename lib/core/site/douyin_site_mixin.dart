import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/danmaku/douyin_danmaku.dart';
import 'package:pure_live/core/interface/live_site_mixin.dart';

mixin DouyinSiteMixin on SiteAccount, SiteVideoHeaders, SiteOpen {
  @override
  String getJumpToNativeUrl(LiveRoom liveRoom) {
    try {
      var args = liveRoom.data as DouyinDanmakuArgs;
      return "snssdk1128://webcast_room?room_id=${args.roomId}";
    } catch (e) {
      return "";
    }
  }

  @override
  String getJumpToWebUrl(LiveRoom liveRoom) {
    try {
      var args = liveRoom.data as DouyinDanmakuArgs;
      return "https://live.douyin.com/${args.webRid}";
    } catch (e) {
      return "";
    }
  }
}
