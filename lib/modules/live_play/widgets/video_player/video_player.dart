import 'dart:io';

import 'package:get/get.dart';
import 'package:gsy_video_player/gsy_video_player.dart';
import 'package:media_kit_video/media_kit_video.dart' as media_kit_video;
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller_panel.dart';

class VideoPlayer extends StatefulWidget {
  final VideoController controller;

  const VideoPlayer({
    super.key,
    required this.controller,
  });

  @override
  State<VideoPlayer> createState() => _VideoPlayerState();
}

class _VideoPlayerState extends State<VideoPlayer> {
  bool hasRender = false;

  Widget _buildVideoPanel() {
    return VideoControllerPanel(
      controller: widget.controller,
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDesktop = Platform.isWindows ||
        Platform.isMacOS ||
        Platform.isLinux ||
        Platform.isFuchsia;

    /// 使用 mpv 解码
    if (isDesktop || widget.controller.videoPlayerIndex == 4) {
      return Stack(children: [
        Obx(() =>
            media_kit_video.Video(
              key: widget.controller.key,
              controller: widget.controller.mediaPlayerController,
              pauseUponEnteringBackgroundMode:
              !widget.controller.settings.enableBackgroundPlay.value,
              // 进入背景模式时暂停
              resumeUponEnteringForegroundMode: true,
              // 进入前景模式后恢复
              fit: widget.controller.settings
                  .videofitArrary[widget.controller.videoFitIndex.value],
              controls: widget.controller.room.platform == Sites.iptvSite
                  ? media_kit_video.MaterialVideoControls
                  : (state) => _buildVideoPanel(),
            )),

        /// 封面
        // Obx(() => Visibility(
        //     visible: !widget.controller.mediaPlayerControllerInitialized.value,
        //     child: Card(
        //       elevation: 0,
        //       margin: const EdgeInsets.all(0),
        //       shape:
        //           const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        //       clipBehavior: Clip.antiAlias,
        //       color: Get.theme.focusColor,
        //       child: CacheNetWorkUtils.getCacheImageV2(widget.controller.room.cover!),
        //     ))),

        /// 视频加载中
        Center(
          child: // 中间
          StreamBuilder(
            stream:
            widget.controller.mediaPlayerController.player.stream.buffering,
            initialData:
            widget.controller.mediaPlayerController.player.state.buffering,
            builder: (_, s) =>
                Visibility(
                  visible: s.data ?? false,
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
          ),
        ),
      ]);
    } else {
      return Obx(() =>
          Stack(children: [
            if (widget.controller.mediaPlayerControllerInitialized.value)
              Chewie(
                controller: widget.controller.chewieController,
              ),
            // return Card(
            //   elevation: 0,
            //   margin: const EdgeInsets.all(0),
            //   shape:
            //       const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
            //   clipBehavior: Clip.antiAlias,
            //   color: Get.theme.focusColor,
            //   child: CacheNetWorkUtils.getCacheImageV2(widget.controller.room.cover!),
            //

            /// 视频加载中
            Visibility(
                visible: !widget.controller.isBuffering.value,
                child: const Center(
                  child: CircularProgressIndicator(),
                )),
          ]));
    }
  }
}
