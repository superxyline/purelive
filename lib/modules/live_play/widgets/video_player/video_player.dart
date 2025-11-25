import 'dart:io';
import 'dart:math';
import 'package:get/get.dart';
import 'package:floating/floating.dart';
import 'package:pure_live/common/index.dart';
import 'package:media_kit_video/media_kit_video.dart' as media_kit_video;
import 'package:pure_live/modules/live_play/widgets/video_player/fijk_helper.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller_panel.dart';

class VideoPlayer extends StatefulWidget {
  final VideoController controller;
  const VideoPlayer({super.key, required this.controller});

  @override
  State<VideoPlayer> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends State<VideoPlayer> {
  Widget _buildIjkPanel(
    FijkPlayer fijkPlayer,
    FijkData fijkData,
    BuildContext context,
    Size viewSize,
    Rect texturePos,
  ) {
    Rect rect = widget.controller.ijkPlayer.value.fullScreen
        ? Rect.fromLTWH(0, 0, viewSize.width, viewSize.height)
        : Rect.fromLTRB(
            max(0.0, texturePos.left),
            max(0.0, texturePos.top),
            min(viewSize.width, texturePos.right),
            min(viewSize.height, texturePos.bottom),
          );
    return Positioned.fromRect(
      rect: rect,
      child: VideoControllerPanel(controller: widget.controller),
    );
  }

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
                fit: StackFit.passthrough,
                children: [
                  Container(
                    color: Colors.black, // 设置你想要的背景色
                  ),
                  Obx(
                    () => media_kit_video.Video(
                      key: ValueKey(widget.controller.videoFit.value),
                      pauseUponEnteringBackgroundMode: !widget.controller.settings.enableBackgroundPlay.value,
                      resumeUponEnteringForegroundMode: !widget.controller.settings.enableBackgroundPlay.value,
                      controller: widget.controller.mediaPlayerController,
                      fit: widget.controller.videoFit.value,
                      controls: widget.controller.room.platform == Sites.iptvSite
                          ? media_kit_video.MaterialVideoControls
                          : (state) => VideoControllerPanel(controller: widget.controller),
                    ),
                  ),
                ],
              ),
            ),
          ),
          childWhenEnabled: Material(
            child: Scaffold(
              resizeToAvoidBottomInset: true,
              body: Stack(
                fit: StackFit.passthrough,
                children: [
                  Container(
                    color: Colors.black, // 设置你想要的背景色
                  ),
                  Obx(
                    () => media_kit_video.Video(
                      key: ValueKey(widget.controller.videoFit.value),
                      pauseUponEnteringBackgroundMode: !widget.controller.settings.enableBackgroundPlay.value,
                      resumeUponEnteringForegroundMode: !widget.controller.settings.enableBackgroundPlay.value,
                      controller: widget.controller.mediaPlayerController,
                      fit: widget.controller.videoFit.value,
                      controls: widget.controller.room.platform == Sites.iptvSite
                          ? media_kit_video.MaterialVideoControls
                          : (state) => VideoControllerPanel(controller: widget.controller),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      } else {
        return AspectRatio(
          aspectRatio: 16 / 9,
          key: ValueKey(widget.controller.videoFit.value),
          child: FijkView(
            player: widget.controller.ijkPlayer,
            fit: FijkHelper.getIjkBoxFit(widget.controller.videoFit.value),
            fs: false,
            color: Colors.black,
            panelBuilder: _buildIjkPanel,
          ),
        );
      }
    }
    return Material(
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          fit: StackFit.passthrough,
          children: [
            Container(
              color: Colors.black, // 设置你想要的背景色
            ),
            Obx(
              () => media_kit_video.Video(
                key: ValueKey(widget.controller.videoFit.value),
                pauseUponEnteringBackgroundMode: !widget.controller.settings.enableBackgroundPlay.value,
                resumeUponEnteringForegroundMode: !widget.controller.settings.enableBackgroundPlay.value,
                controller: widget.controller.mediaPlayerController,
                fit: widget.controller.videoFit.value,
                controls: widget.controller.room.platform == Sites.iptvSite
                    ? media_kit_video.MaterialVideoControls
                    : (state) => VideoControllerPanel(controller: widget.controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
