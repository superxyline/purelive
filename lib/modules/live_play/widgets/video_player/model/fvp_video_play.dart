import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:pure_live/common/services/settings_service.dart';
import 'package:pure_live/core/common/core_log.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller.dart'
    as video_player;
import 'package:pure_live/modules/live_play/widgets/video_player/video_controller_panel.dart';
import 'package:pure_live/modules/util/listen_list_util.dart';
import 'package:pure_live/modules/util/rx_util.dart';
import 'package:video_player/video_player.dart';

import 'video_play_impl.dart';

/// FVP 播放器
class FvpVideoPlay extends VideoPlayerInterFace with ChangeNotifier {
  // Video player control
  late VideoPlayerController videoPlayerController =
      VideoPlayerController.networkUrl(Uri.parse(""));

  // late ChewieController chewieController;

  late Rx<ChewieController> chewieController =
      ChewieController(videoPlayerController: videoPlayerController).obs;

  /// 存储 Stream 流监听
  /// 默认视频 MPV 视频监听流
  final defaultVideoStreamSubscriptionList = <StreamSubscription>[];

  final SettingsService settings = Get.find<SettingsService>();

  @override
  late final String playerName;

  FvpVideoPlay({
    required this.playerName,
  });

  late video_player.VideoController controller;

  @override
  void init({required video_player.VideoController controller}) {
    this.controller = controller;
    ListenListUtil.clearStreamSubscriptionList(
        defaultVideoStreamSubscriptionList);

    VideoPlayerOptions options =
        VideoPlayerOptions(allowBackgroundPlayback: true);
    videoPlayerController = VideoPlayerController.networkUrl(
      Uri.parse(""),
      videoPlayerOptions: options,
    );
    chewieController.value = ChewieController(
      videoPlayerController: videoPlayerController,
      autoPlay: false,
      looping: false,
      draggableProgressBar: false,
      overlay: VideoControllerPanel(
        controller: controller,
      ),
      showControls: false,
      useRootNavigator: true,
      showOptions: false,
    );

    // var enableCodec = settings.enableCodec.value;

    //notifyListeners();
  }

  // void EventsListener(VideoEventType event) {
  //   if (event == VideoEventType.onError) {
  //     hasError.value = true;
  //     isPlaying.value = false;
  //     CoreLog.d('VideoPlayer error ${videoPlayerController.value.what}');
  //   } else {
  //     isPlaying.value = videoPlayerController.value.isPlaying;
  //   }
  // }

  /// VideoPlayer 释放监听
  void disposeVideoPlayerListener() {
    // chewieController.value.videoPlayerController.value.
    // chewieController.value.removeListener(EventsListener);
  }

  @override
  void dispose() {
    ListenListUtil.clearStreamSubscriptionList(
        defaultVideoStreamSubscriptionList);
    disposeVideoPlayerListener();
    videoPlayerController.removeListener(listenerVideo);
    chewieController.value.addListener(chewieControllerListener);
    videoPlayerController.dispose();
    chewieController.value.dispose();
    super.dispose();
  }

  @override
  Future<void> enterFullscreen() async {
    chewieController.value.enterFullScreen();
  }

  @override
  Future<void> exitFullScreen() async {
    chewieController.value.exitFullScreen();
  }

  @override
  Future<void> openVideo(String datasource, Map<String, String> headers) async {
    isBuffering.updateValueNotEquate(false);
    isPlaying.updateValueNotEquate(false);
    CoreLog.d("play url: $datasource");
    // fix datasource empty error
    if (datasource.isEmpty) {
      hasError.value = true;
      return;
    } else {
      hasError.value = false;
    }
    VideoPlayerOptions options =
        VideoPlayerOptions(allowBackgroundPlayback: true);

    var oldVideo = videoPlayerController;
    videoPlayerController.removeListener(listenerVideo);
    try {
      oldVideo.dispose();
    } catch (e) {
      CoreLog.error(e);
    }
    // videoPlayerController.remove
    videoPlayerController = VideoPlayerController.networkUrl(
      Uri.parse(datasource),
      videoPlayerOptions: options,
    );

    videoPlayerController.addListener(listenerVideo);
    // await videoPlayerController.initialize();
    var oldValue = chewieController.value;
    try {
      oldValue.removeListener(chewieControllerListener);
      oldValue.dispose();
    } catch (e) {
      CoreLog.error(e);
    }
    chewieController.value = ChewieController(
      videoPlayerController: videoPlayerController,
      autoPlay: true,
      looping: false,
      draggableProgressBar: true,
      overlay: VideoControllerPanel(
        controller: controller,
      ),
      showControls: false,
      useRootNavigator: true,
      showOptions: false,
      // isLive: true,
    );

    chewieController.value.addListener(chewieControllerListener);

    // oldVideo.dispose();
    // oldValue.dispose();
  }

  void chewieControllerListener() {
    var tmpIsLive = chewieController.value.isLive;
    var tmpIsPlaying = chewieController.value.isPlaying;
    var tmpIsFullScreen = chewieController.value.isFullScreen;
    CoreLog.d(
        "isLive $tmpIsLive isPlaying $tmpIsPlaying isFullScreen $tmpIsFullScreen");
    isFullscreen.updateValueNotEquate(tmpIsFullScreen);
    isPlaying.updateValueNotEquate(tmpIsPlaying);
  }

  void listenerVideo() {
    // videoPlayerController.printInfo();
    // videoPlayerController.printError();
    var isError = videoPlayerController.value.errorDescription != null;
    if (isError) {
      CoreLog.d("Error: ${videoPlayerController.value.errorDescription}");
    }
    hasError.updateValueNotEquate(
        videoPlayerController.value.errorDescription != null);
    isPlaying.updateValueNotEquate(videoPlayerController.value.isPlaying);
    isBuffering.updateValueNotEquate(videoPlayerController.value.isBuffering);
    isVertical.updateValueNotEquate(videoPlayerController.value.size.width <
        videoPlayerController.value.size.height);
  }

  @override
  Future<void> pause() async {
    return chewieController.value.pause();
  }

  @override
  Future<void> play() {
    return chewieController.value.play();
  }

  @override
  void setVideoFit(BoxFit fit) {
    // chewieController.value.aspectRatio = 1.0;
  }

  @override
  bool get supportPip => true;

  @override
  Future<void> enterPipMode(BuildContext context) async {
    // await chewieController.value.();
  }

  @override
  List<String> get supportPlatformList =>
      ["linux", "macos", "windows", "android", "ios"];

  @override
  Widget getVideoPlayerWidget() {
    return Obx(() => Chewie(
          controller: chewieController.value,
        ));
  }

  @override
  Future<void> toggleFullScreen() async {
    isFullscreen.toggle();
    chewieController.value.toggleFullScreen();
  }

  @override
  Future<void> toggleWindowFullScreen() async {
    return toggleFullScreen();
  }

  @override
  Future<void> togglePlayPause() async {
    chewieController.value.togglePause();
  }

  @override
  Future<void> setLandscapeOrientation() async {
    super.setLandscapeOrientation();
    // chewieController.value.resolveByClick();
  }

  @override
  Future<void> setPortraitOrientation() async {
    super.setPortraitOrientation();
    // chewieController.value.backToProtVideo();
  }

  @override
  void disableRotation() {
    // chewieController.value.disableRotation();
  }

  @override
  void enableRotation() {
    // chewieController.value.enableRotation();
  }
}
