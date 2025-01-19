import 'package:pure_live/common/models/live_room.dart';
import 'package:pure_live/core/interface/live_site_mixin.dart';

mixin CCSiteMixin on SiteAccount, SiteVideoHeaders, SiteOpen {
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
}
