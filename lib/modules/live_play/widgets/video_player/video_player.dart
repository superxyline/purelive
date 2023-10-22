import 'dart:io';

import 'package:better_player/better_player.dart';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller_panel.dart';
import 'package:media_kit_video/media_kit_video.dart' as media_kit_video;

class VideoPlayer extends StatelessWidget {
  final VideoController controller;
  const VideoPlayer({
    Key? key,
    required this.controller,
  }) : super(key: key);

  Widget _buildVideoPanel() {
    return VideoControllerPanel(
      controller: controller,
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDesktop = Platform.isWindows;
    if (isDesktop) {
      return Obx(() => media_kit_video.Video(
            key: controller.key,
            controller: controller.mediaPlayerController,
            fit: controller.videoFit.value,
            controls: (state) => _buildVideoPanel(),
          ));
    }else{
      return Stack(
        children: [
          BetterPlayer(
            key: controller.playerKey,
            controller: controller.mobileController!,
          ),
          _buildVideoPanel(),
        ],
      );
    }
  }
}
