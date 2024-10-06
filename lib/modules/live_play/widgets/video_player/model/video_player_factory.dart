
import 'dart:io';

import 'package:gsy_video_player/gsy_video_player.dart';

import 'gsy_video_play.dart';
import 'mpv_video_play.dart';
import 'video_play_impl.dart';

final class VideoPlayerFactory{
  static List<VideoPlayerInterFace> get allVideoPlayerList {
    var list = <VideoPlayerInterFace>[
      GsyVideoPlay(playerName: "Exo播放器", playerType: GsyVideoPlayerType.exo),
      GsyVideoPlay(playerName: "系统播放器", playerType: GsyVideoPlayerType.sysytem),
      GsyVideoPlay(playerName: "IJK播放器", playerType: GsyVideoPlayerType.ijk),
      GsyVideoPlay(playerName: "阿里播放器", playerType: GsyVideoPlayerType.ali),
      MpvVideoPlay(playerName: "MPV播放器",),
    ];
    return list;
  }

  static List<VideoPlayerInterFace> getSupportVideoPlayerList() {
    return allVideoPlayerList.where((videoPlayer)=>videoPlayer.supportPlatformList.contains(Platform.operatingSystem))
        .toList();
  }

}