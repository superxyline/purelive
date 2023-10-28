import 'dart:io';
import 'dart:math';

import 'package:better_player/better_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fijkplayer/fijkplayer.dart';
import 'package:flutter_aliplayer/flutter_aliplayer.dart';
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
  bool hasRender = false;
  Widget _buildVideoPanel() {
    return VideoControllerPanel(
      controller: widget.controller,
    );
  }

  @override
  void initState() {
    super.initState();
  }

  Widget _buildIjkPanel(FijkPlayer fijkPlayer, FijkData fijkData,
      BuildContext context, Size viewSize, Rect texturePos) {
    Rect rect = widget.controller.fijkPlayer.value.fullScreen
        ? Rect.fromLTWH(0, 0, viewSize.width, viewSize.height)
        : Rect.fromLTRB(
            max(0.0, texturePos.left),
            max(0.0, texturePos.top),
            min(viewSize.width, texturePos.right),
            min(viewSize.height, texturePos.bottom));
    return Positioned.fromRect(rect: rect, child: _buildVideoPanel());
  }

  ImageProvider? getRoomCover(cover) {
    try {
      return CachedNetworkImageProvider(cover);
    } catch (e) {
      return null;
    }
  }

  FijkFit getFijkFit(BoxFit boxFit) {
    FijkFit fijkFit = FijkFit.contain;
    if (boxFit == BoxFit.contain) {
      fijkFit = FijkFit.contain;
    } else if (boxFit == BoxFit.cover) {
      fijkFit = FijkFit.cover;
    } else if (boxFit == BoxFit.fill) {
      fijkFit = FijkFit.fill;
    } else if (boxFit == BoxFit.fitHeight) {
      fijkFit = FijkFit.fitHeight;
    } else if (boxFit == BoxFit.fitWidth) {
      fijkFit = FijkFit.fitWidth;
    }
    return fijkFit;
  }

  @override
  Widget build(BuildContext context) {
    bool isDesktop = Platform.isWindows;
    if (isDesktop) {
      return Obx(() => widget.controller.mediaPlayerControllerInitialized.value ?  media_kit_video.Video(
            key: widget.controller.key,
            controller: widget.controller.mediaPlayerController,
            fit: widget.controller.videoFit.value,
            controls: (state) => _buildVideoPanel(),
          ): Card(
        elevation: 0,
        margin: const EdgeInsets.all(0),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        clipBehavior: Clip.antiAlias,
        color: Get.theme.focusColor,
        child: CachedNetworkImage(
          imageUrl: widget.controller.room.cover!,
          fit: BoxFit.fill,
          errorWidget: (context, error, stackTrace) => const Center(
            child: Icon(Icons.live_tv_rounded, size: 48),
          ),
        ),
      ));
    } else {
      if (widget.controller.videoPlayerIndex == 0) {
        return Stack(
          children: [
            BetterPlayer(
              key: widget.controller.playerKey,
              controller: widget.controller.mobileController!,
            ),
            _buildVideoPanel(),
          ],
        );
      }
      if (widget.controller.videoPlayerIndex == 1) {
        return Obx(
          () => !widget.controller.playerRefresh.value
              ? FijkView(
                  player: widget.controller.fijkPlayer,
                  color: Colors.black,
                  fit: getFijkFit(widget.controller.videoFit.value),
                  cover: getRoomCover(widget.controller.room.cover),
                  fs: false,
                  panelBuilder: _buildIjkPanel)
              : Card(
                  elevation: 0,
                  margin: const EdgeInsets.all(0),
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero),
                  clipBehavior: Clip.antiAlias,
                  color: Get.theme.focusColor,
                  child: CachedNetworkImage(
                    imageUrl: widget.controller.room.cover!,
                    fit: BoxFit.fill,
                    errorWidget: (context, error, stackTrace) => const Center(
                      child: Icon(Icons.live_tv_rounded, size: 48),
                    ),
                  ),
                ),
        );
      }
      if (widget.controller.videoPlayerIndex == 2) {
        return Obx(
          () => !widget.controller.playerRefresh.value
              ? Stack(
                  children: [
                    AliPlayerView(
                        onCreated: widget.controller.onViewPlayerCreated,
                        x: 0.0,
                        y: 0.0,
                        width: MediaQuery.of(context).size.width,
                        height: MediaQuery.of(context).size.height),
                    _buildVideoPanel(),
                  ],
                )
              : Card(
                  elevation: 0,
                  margin: const EdgeInsets.all(0),
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.zero),
                  clipBehavior: Clip.antiAlias,
                  color: Get.theme.focusColor,
                  child: CachedNetworkImage(
                    imageUrl: widget.controller.room.cover!,
                    fit: BoxFit.fill,
                    errorWidget: (context, error, stackTrace) => const Center(
                      child: Icon(Icons.live_tv_rounded, size: 48),
                    ),
                  ),
                ),
        );
      }
      return Card(
        elevation: 0,
        margin: const EdgeInsets.all(0),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        clipBehavior: Clip.antiAlias,
        color: Get.theme.focusColor,
        child: CachedNetworkImage(
          imageUrl: widget.controller.room.cover!,
          fit: BoxFit.fill,
          errorWidget: (context, error, stackTrace) => const Center(
            child: Icon(Icons.live_tv_rounded, size: 48),
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
}
