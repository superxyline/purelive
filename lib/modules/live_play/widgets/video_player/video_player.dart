import 'dart:io';

import 'package:better_player_v3/better_player.dart';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller_panel.dart';
import 'package:media_kit_video/media_kit_video.dart' as media_kit_video;

class VideoPlayer extends StatefulWidget {
  final VideoController controller;
  const VideoPlayer({
    Key? key,
    required this.controller,
  }) : super(key: key);

  @override
  State<VideoPlayer> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends State<VideoPlayer> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  Widget _buildVideoFrame() {
    if (Platform.isWindows || Platform.isLinux) {
      return Obx(() => media_kit_video.Video(
            key: widget.controller.key,
            controller: widget.controller.desktopController,
            fit: widget.controller.videoFit.value,
            controls: (state) => _buildVideoPanel(),
          ));
    } else {
      return BetterPlayer(
        key: widget.controller.playerKey,
        controller: widget.controller.mobileController!,
      );
    }
  }

  Widget _buildVideoPanel() {
    return VideoControllerPanel(
      controller: widget.controller,
    );
  }

  Widget _buildPlayer() {
    return Stack(
      children: [
        _buildVideoFrame(),
        if (Platform.isAndroid || Platform.isIOS) _buildVideoPanel(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildPlayer();
  }

  @override
  void dispose() {
    super.dispose();
  }
}
