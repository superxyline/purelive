import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller_panel.dart';

class VideoPlayer extends StatefulWidget {
  final VideoController controller;
  const VideoPlayer({super.key, required this.controller});

  @override
  State<VideoPlayer> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends State<VideoPlayer> {
  VideoController get controller => widget.controller;

  Widget buildLoading() {
    return Material(
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          Container(
            color: Colors.black, // 设置你想要的背景色
          ),
          Container(
            color: Colors.black,
            child: const Center(
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(strokeWidth: 6, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (controller.globalPlayer.isPlaying.value) {
        return widget.controller.globalPlayer.getVideoWidget(VideoControllerPanel(controller: widget.controller));
      }
      return buildLoading();
    });
  }
}
