import 'dart:io';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:gsy_video_player/gsy_video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:media_kit_video/media_kit_video.dart' as media_kit_video;
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

class _VideoPlayerState extends State<VideoPlayer> with WidgetsBindingObserver {
  bool hasRender = false;
  Widget _buildVideoPanel() {
    return VideoControllerPanel(
      controller: widget.controller,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    if (!widget.controller.initialized.value) {
      final navigator = Navigator.of(context);
      setState(() {
        widget.controller.navigatorState = navigator;
      });
      widget.controller.initialized.value = true;
    }
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    bool isDesktop = Platform.isWindows;
    if (isDesktop || widget.controller.videoPlayerIndex == 4) {
      return Obx(() => widget.controller.mediaPlayerControllerInitialized.value
          ? media_kit_video.Video(
              key: widget.controller.key,
              controller: widget.controller.mediaPlayerController,
              fit: widget.controller.settings.videofitArrary[widget.controller.videoFitIndex.value],
              controls: widget.controller.room.platform == Sites.iptvSite
                  ? media_kit_video.MaterialVideoControls
                  : (state) => _buildVideoPanel(),
            )
          : Card(
              elevation: 0,
              margin: const EdgeInsets.all(0),
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              clipBehavior: Clip.antiAlias,
              color: Get.theme.focusColor,
              child: CachedNetworkImage(
                cacheManager: CustomCacheManager.instance,
                imageUrl: widget.controller.room.cover!,
                fit: BoxFit.fill,
                errorWidget: (context, error, stackTrace) => const Center(
                  child: Icon(Icons.live_tv_rounded, size: 48),
                ),
              ),
            ));
    } else {
      return GsyPlayerVideoFullScreen(
        controller: widget.controller.gsyVideoPlayerController,
        routePageBuilder: (context, animation, second, controllerProvider) => AnimatedBuilder(
          animation: animation,
          builder: (context, child) => GsyEnterFullScreen(
            controller: widget.controller.gsyVideoPlayerController,
            controllerProvider: controllerProvider,
          ),
        ),
        playerView: Stack(
          children: [
            GsyVideoPlayer(
              alignment: Alignment.center,
              fit: widget.controller.videoFit.value,
              width: MediaQuery.of(context).size.width,
              height: MediaQuery.of(context).size.height,
              controller: widget.controller.gsyVideoPlayerController,
            ),
            _buildVideoPanel(),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
