<<<<<<< HEAD
=======


>>>>>>> 3248227e738197247e8ebbc391480065a5c0fab4
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
    return media_kit_video.Video(
<<<<<<< HEAD
      controller: widget.controller.controller,
      fit: widget.controller.videoFit.value,
      controls: media_kit_video.NoVideoControls,
    );
=======
          key: widget.controller.key,
          controller: widget.controller.controller,
          fit: widget.controller.videoFit.value,
          controls: (state) => _buildVideoPanel(),
        );
>>>>>>> 3248227e738197247e8ebbc391480065a5c0fab4
  }

  Widget _buildVideoPanel() {
    return VideoControllerPanel(
      key: Key("${widget.controller.hashCode}_danmaku"),
      controller: widget.controller,
    );
  }

  Widget _buildPlayer() {
    return Stack(
      children: [
        _buildVideoFrame()
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
