import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/interface/live_site_mixin.dart';

mixin KuaishouSiteMixin on SiteAccount, SiteVideoHeaders, SiteOpen {
  @override
  String getJumpToNativeUrl(LiveRoom liveRoom) {
    try {
      var appUrl =
          "kwai://liveaggregatesquare?liveStreamId=${liveRoom.link}&recoStreamId=${liveRoom.link}&recoLiveStreamId=${liveRoom.link}&liveSquareSource=28&path=/rest/n/live/feed/sharePage/slide/more&mt_product=H5_OUTSIDE_CLIENT_SHARE";
      return appUrl;
    } catch (e) {
      return "";
    }
  }

  @override
  String getJumpToWebUrl(LiveRoom liveRoom) {
    try {
      var webUrl = "https://live.kuaishou.com/u/${liveRoom.roomId}";
      return webUrl;
    } catch (e) {
      return "";
    }
  }
}
