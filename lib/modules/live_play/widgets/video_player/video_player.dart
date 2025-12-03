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
    return widget.controller.globalPlayer.getVideoWidget(VideoControllerPanel(controller: widget.controller));
  }
}

class TimeOutVideoWidget extends StatelessWidget {
  const TimeOutVideoWidget({super.key, required this.controller});

  final VideoController controller;
  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Obx(
              () => Text(
                '${controller.room.platform == Sites.iptvSite ? controller.room.title : controller.room.nick ?? ''}',
                style: const TextStyle(fontSize: 16, color: Colors.white),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      S.of(context).play_video_failed,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                  const Text("该房间未开播或已下播", style: TextStyle(color: Colors.white, fontSize: 14)),
                  const Text("请刷新或者切换其他直播间进行观看吧", style: TextStyle(color: Colors.white, fontSize: 14)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
