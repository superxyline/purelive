import 'dart:io';
import 'package:get/get.dart';
import 'package:floating/floating.dart';
import 'package:pure_live/common/index.dart';
import 'package:media_kit_video/media_kit_video.dart' as media_kit_video;
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller_panel.dart';

class VideoPlayer extends StatefulWidget {
  final VideoController controller;
  const VideoPlayer({super.key, required this.controller});

  @override
  State<VideoPlayer> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends State<VideoPlayer> {
  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      if (widget.controller.videoPlayerIndex == 0) {
        return PiPSwitcher(
          floating: widget.controller.pip,
          childWhenDisabled: Material(
            child: Scaffold(
              resizeToAvoidBottomInset: true,
              body: Stack(
                fit: StackFit.expand, // 使Stack填充整个父容器
                children: [
                  Container(
                    color: Colors.black, // 设置你想要的背景色
                  ),
                  Obx(
                    () => media_kit_video.Video(
                      key: widget.controller.key,
                      pauseUponEnteringBackgroundMode: !widget.controller.settings.enableBackgroundPlay.value,
                      resumeUponEnteringForegroundMode: !widget.controller.settings.enableBackgroundPlay.value,
                      controller: widget.controller.mediaPlayerController,
                      fit: widget.controller.settings.videofitArrary[widget.controller.videoFitIndex.value],
                      controls: widget.controller.room.platform == Sites.iptvSite
                          ? media_kit_video.MaterialVideoControls
                          : widget.controller.isFullscreen.value
                          ? (state) => VideoControllerPanel(controller: widget.controller)
                          : null,
                    ),
                  ),
                  VideoControllerPanel(controller: widget.controller),
                ],
              ),
            ),
          ),
          childWhenEnabled: Material(
            child: Scaffold(
              resizeToAvoidBottomInset: true,
              body: Stack(
                fit: StackFit.expand, // 使Stack填充整个父容器
                children: [
                  Container(
                    color: Colors.black, // 设置你想要的背景色
                  ),
                  Obx(
                    () => media_kit_video.Video(
                      key: widget.controller.key,
                      pauseUponEnteringBackgroundMode: !widget.controller.settings.enableBackgroundPlay.value,
                      resumeUponEnteringForegroundMode: !widget.controller.settings.enableBackgroundPlay.value,
                      controller: widget.controller.mediaPlayerController,
                      fit: widget.controller.settings.videofitArrary[widget.controller.videoFitIndex.value],
                      controls: widget.controller.room.platform == Sites.iptvSite
                          ? media_kit_video.MaterialVideoControls
                          : widget.controller.isFullscreen.value
                          ? (state) => VideoControllerPanel(controller: widget.controller)
                          : null,
                    ),
                  ),
                  VideoControllerPanel(controller: widget.controller),
                ],
              ),
            ),
          ),
        );
      } else {
        return BetterPlayer(key: widget.controller.playerKey, controller: widget.controller.mobileController!);
      }
    }
    return Material(
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          fit: StackFit.expand, // 使Stack填充整个父容器
          children: [
            Container(
              color: Colors.black, // 设置你想要的背景色
            ),
            Obx(
              () => media_kit_video.Video(
                key: widget.controller.key,
                pauseUponEnteringBackgroundMode: !widget.controller.settings.enableBackgroundPlay.value,
                resumeUponEnteringForegroundMode: !widget.controller.settings.enableBackgroundPlay.value,
                controller: widget.controller.mediaPlayerController,
                fit: widget.controller.settings.videofitArrary[widget.controller.videoFitIndex.value],
                controls: widget.controller.room.platform == Sites.iptvSite
                    ? media_kit_video.MaterialVideoControls
                    : widget.controller.isFullscreen.value
                    ? (state) => VideoControllerPanel(controller: widget.controller)
                    : null,
              ),
            ),
            VideoControllerPanel(controller: widget.controller),
          ],
        ),
      ),
    );
  }
}
