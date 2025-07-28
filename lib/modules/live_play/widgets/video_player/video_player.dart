import 'dart:io';
import 'package:get/get.dart';
import 'package:floating/floating.dart';
import 'package:pure_live/common/index.dart';
import 'package:media_kit_video/media_kit_video.dart' as media_kit_video;
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller_panel.dart';
import 'package:media_kit_video/media_kit_video_controls/src/controls/methods/video_state.dart';

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
                    () => Transform.scale(
                      scale: !widget.controller.isVerticalDirection ? 1 : 9 / 16,
                      child: Transform.rotate(
                        angle: widget.controller.angle.value,
                        child: media_kit_video.Video(
                          key: widget.controller.key,
                          width: widget.controller.videoSizeWidth.value,
                          height: widget.controller.videoSizeHeight.value,
                          pauseUponEnteringBackgroundMode: !widget.controller.settings.enableBackgroundPlay.value,
                          resumeUponEnteringForegroundMode: !widget.controller.settings.enableBackgroundPlay.value,
                          controller: widget.controller.mediaPlayerController,
                          fit: widget.controller.settings.videofitArrary[widget.controller.videoFitIndex.value],
                          controls: widget.controller.room.platform == Sites.iptvSite
                              ? media_kit_video.MaterialVideoControls
                              : widget.controller.isFullscreen.value
                              ? media_kit_video.MaterialVideoControls
                              : null,
                        ),
                      ),
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
                    () => Transform.scale(
                      scale: !widget.controller.isVerticalDirection ? 1 : 9 / 16,
                      child: Transform.rotate(
                        angle: widget.controller.angle.value,
                        child: media_kit_video.Video(
                          key: widget.controller.key,
                          width: widget.controller.videoSizeWidth.value,
                          height: widget.controller.videoSizeHeight.value,
                          pauseUponEnteringBackgroundMode: !widget.controller.settings.enableBackgroundPlay.value,
                          resumeUponEnteringForegroundMode: !widget.controller.settings.enableBackgroundPlay.value,
                          controller: widget.controller.mediaPlayerController,
                          fit: widget.controller.settings.videofitArrary[widget.controller.videoFitIndex.value],
                          controls: widget.controller.room.platform == Sites.iptvSite
                              ? media_kit_video.MaterialVideoControls
                              : widget.controller.isFullscreen.value
                              ? media_kit_video.MaterialVideoControls
                              : null,
                        ),
                      ),
                    ),
                  ),
                  VideoControllerPanel(controller: widget.controller),
                ],
              ),
            ),
          ),
        );
      } else {
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
                  () => Transform.scale(
                    scale: !widget.controller.isVerticalDirection ? 1 : 9 / 16,
                    child: Transform.rotate(
                      angle: widget.controller.angle.value,
                      child: BetterPlayer(
                        key: widget.controller.playerKey,
                        controller: widget.controller.mobileController!,
                      ),
                    ),
                  ),
                ),
                VideoControllerPanel(controller: widget.controller),
              ],
            ),
          ),
        );
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
              () => Transform.scale(
                scale: !widget.controller.isVerticalDirection ? 1 : 9 / 16,
                child: Transform.rotate(
                  angle: widget.controller.angle.value,
                  child: media_kit_video.Video(
                    key: widget.controller.key,
                    width: widget.controller.videoSizeWidth.value,
                    height: widget.controller.videoSizeHeight.value,
                    pauseUponEnteringBackgroundMode: !widget.controller.settings.enableBackgroundPlay.value,
                    resumeUponEnteringForegroundMode: !widget.controller.settings.enableBackgroundPlay.value,
                    controller: widget.controller.mediaPlayerController,
                    fit: widget.controller.settings.videofitArrary[widget.controller.videoFitIndex.value],
                    controls: widget.controller.room.platform == Sites.iptvSite
                        ? media_kit_video.MaterialVideoControls
                        : null,
                  ),
                ),
              ),
            ),
            VideoControllerPanel(controller: widget.controller),
          ],
        ),
      ),
    );
  }
}
