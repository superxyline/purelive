import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:get/get.dart';
import 'package:gsy_video_player/gsy_video_player.dart';
import 'package:media_kit_video/media_kit_video.dart' as media_kit_video;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/common/core_log.dart';
import 'package:pure_live/modules/live_play/live_play_controller.dart';
import 'package:pure_live/modules/live_play/load_type.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/danmaku_text.dart';
import 'package:pure_live/plugins/barrage.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'fix_gsy_video_player_controller.dart';
import 'video_controller_panel.dart';

class VideoController with ChangeNotifier {
  final GlobalKey playerKey;
  final LiveRoom room;
  final String datasourceType;
  String datasource;
  final bool allowBackgroundPlay;
  final bool allowScreenKeepOn;
  final bool allowFullScreen;
  final bool fullScreenByDefault;
  final bool autoPlay;
  final Map<String, String> headers;

  /// 是否为竖屏直播间
  final isVertical = false.obs;
  final videoFitIndex = 0.obs;
  final videoFit = BoxFit.contain.obs;
  final mediaPlayerControllerInitialized = false.obs;

  ScreenBrightness brightnessController = ScreenBrightness();

  double initBrightness = 0.0;

  String qualiteName;

  int currentLineIndex;

  int currentQuality;

  final hasError = false.obs;

  final isPlaying = false.obs;

  final isBuffering = false.obs;

  final isPipMode = false.obs;

  final isFullscreen = false.obs;

  final isWindowFullscreen = false.obs;

  bool hasDestory = false;

  bool get supportPip => Platform.isAndroid;

  bool get supportWindowFull => Platform.isWindows || Platform.isLinux;

  bool get fullscreenUI => isFullscreen.value || isWindowFullscreen.value;

  final refreshCompleted = true.obs;

  // Video player status
  // A [GlobalKey<VideoState>] is required to access the programmatic fullscreen interface.
  late final GlobalKey<media_kit_video.VideoState> key =
      GlobalKey<media_kit_video.VideoState>();

  // Create a [Player] to control playback.
  late Player player;

  // CeoController] to handle video output from [Player].
  late media_kit_video.VideoController mediaPlayerController;

  // Video player control
  late GsyVideoPlayerController gsyVideoPlayerController;

  late ChewieController chewieController;

  final playerRefresh = false.obs;

  GlobalKey<BrightnessVolumnDargAreaState> brightnessKey =
      GlobalKey<BrightnessVolumnDargAreaState>();

  // LivePlayController livePlayController = Get.find<LivePlayController>();

  final SettingsService settings = Get.find<SettingsService>();

  int videoPlayerIndex = 4;

  bool enableCodec = true;

  // 是否手动暂停
  var isActivePause = true.obs;

  Timer? hasActivePause;

  // Controller ui status
  ///State of navigator on widget created
  late NavigatorState navigatorState;

  ///Flag which determines if widget has initialized

  Timer? showControllerTimer;
  final showController = true.obs;
  final showSettting = false.obs;
  final showLocked = false.obs;
  final danmuKey = GlobalKey();
  double volume = 0.0;

  Timer? _debounceTimer;

  void enableController() {
    showControllerTimer?.cancel();
    showControllerTimer = Timer(const Duration(seconds: 2), () {
      showController.value = false;
    });
    showController.value = true;
  }

  // Danmaku player control
  BarrageWallController danmakuController = BarrageWallController();
  final hideDanmaku = false.obs;
  final danmakuArea = 1.0.obs;
  final danmakuSpeed = 8.0.obs;
  final danmakuFontSize = 16.0.obs;
  final danmakuFontBorder = 0.5.obs;
  final danmakuOpacity = 1.0.obs;
  final mergeDanmuRating = 0.0.obs;

  /// 存储 Stream 流监听
  /// 默认视频 MPV 视频监听流
  final defaultVideoStreamSubscriptionList = <StreamSubscription>[];

  // GSY 视频监听流
  final gsyStreamSubscriptionList = <StreamSubscription>[];

  // 其他类型 监听流
  final otherStreamSubscriptionList = <StreamSubscription>[];

  VideoController({
    required this.playerKey,
    required this.room,
    required this.datasourceType,
    required this.datasource,
    required this.headers,
    this.allowBackgroundPlay = false,
    this.allowScreenKeepOn = false,
    this.allowFullScreen = true,
    this.fullScreenByDefault = false,
    this.autoPlay = true,
    BoxFit fitMode = BoxFit.contain,
    required this.qualiteName,
    required this.currentLineIndex,
    required this.currentQuality,
  }) {
    videoFitIndex.value = settings.videoFitIndex.value;
    videoFit.value = settings.videofitArrary[videoFitIndex.value];
    hideDanmaku.value = settings.hideDanmaku.value;
    danmakuArea.value = settings.danmakuArea.value;
    danmakuSpeed.value = settings.danmakuSpeed.value;
    danmakuFontSize.value = settings.danmakuFontSize.value;
    danmakuFontBorder.value = settings.danmakuFontBorder.value;
    danmakuOpacity.value = settings.danmakuOpacity.value;
    mergeDanmuRating.value = settings.mergeDanmuRating.value;
    initPagesConfig();
  }

  initPagesConfig() {
    if (allowScreenKeepOn) WakelockPlus.enable();
    initVideoController();
    initDanmaku();
    initBattery();
  }

  // Battery level control
  final Battery _battery = Battery();
  final batteryLevel = 100.obs;

  void initBattery() {
    if (Platform.isAndroid || Platform.isIOS) {
      _battery.batteryLevel.then((value) => batteryLevel.value = value);
      otherStreamSubscriptionList.add(
          _battery.onBatteryStateChanged.listen((BatteryState state) async {
        batteryLevel.value = await _battery.batteryLevel;
      }));
    }
  }

  void initVideoController() async {
    FlutterVolumeController.updateShowSystemUI(false);
    videoPlayerIndex = settings.videoPlayerIndex.value;
    enableCodec = settings.enableCodec.value;
    if (Platform.isWindows || Platform.isLinux || videoPlayerIndex == 4) {
      player = Player();
      if (player.platform is NativePlayer) {
        (player.platform as dynamic)
            .setProperty('cache', 'no'); // --cache=<yes|no|auto>
        (player.platform as dynamic).setProperty('cache-secs',
            '0'); // --cache-secs=<seconds> with cache but why not.
        (player.platform as dynamic).setProperty(
            'demuxer-donate-buffer', 'no'); // --demuxer-donate-buffer==<yes|no>
      }
      var conf = VideoControllerConfiguration(
        enableHardwareAcceleration: enableCodec,
      );
      if (Platform.isAndroid || Platform.isIOS) {
        conf = VideoControllerConfiguration(
          vo: 'mediacodec_embed',
          hwdec: 'mediacodec',
          enableHardwareAcceleration: enableCodec,
        );
      }
      mediaPlayerController =
          media_kit_video.VideoController(player, configuration: conf);
      setDataSource(datasource);
      defaultVideoStreamSubscriptionList.add(
          mediaPlayerController.player.stream.playing.listen((bool playing) {
        if (playing) {
          if (!mediaPlayerControllerInitialized.value) {
            mediaPlayerControllerInitialized.value = true;
          }
          isPlaying.value = true;
        } else {
          isPlaying.value = false;
        }
      }));
      defaultVideoStreamSubscriptionList
          .add(mediaPlayerController.player.stream.error.listen((event) {
        if (event.toString().contains('Failed to open')) {
          hasError.value = true;
          isPlaying.value = false;
        }
      }));
      defaultVideoStreamSubscriptionList
          .add(mediaPlayerController.player.stream.buffering.listen((e) {
        isBuffering.value = e;
      }));

      defaultVideoStreamSubscriptionList
          .add(player.stream.width.listen((event) {
        CoreLog.d('Video width:$event  W:${(player.state.width)}  H:${(player.state.height)}');
        isVertical.value =
            (player.state.height ?? 9) > (player.state.width ?? 16);
      }));
      defaultVideoStreamSubscriptionList
          .add(player.stream.height.listen((event) {
        CoreLog.d('height:$event  W:${(player.state.width)}  H:${(player.state.height)}');
        isVertical.value =
            (player.state.height ?? 9) > (player.state.width ?? 16);
      }));
    } else if (Platform.isAndroid || Platform.isIOS) {
      initGSYVideoPlayer();
      setDataSource(datasource);
    }
    otherStreamSubscriptionList.add(hasError.listen((p0){
      try {
        LivePlayController livePlayController = Get.find<LivePlayController>();
        if (hasError.value && !livePlayController.isLastLine.value) {
          SmartDialog.showToast("视频播放失败,正在为您切换线路");
          changeLine();
        }
      } catch (e) {
        CoreLog.error(e);
      }
    }));
    /*debounce(hasError, (callback) {
      try {
        LivePlayController livePlayController = Get.find<LivePlayController>();
        if (hasError.value && !livePlayController.isLastLine.value) {
          SmartDialog.showToast("视频播放失败,正在为您切换线路");
          changeLine();
        }
      } catch (e) {
        CoreLog.error(e);
      }
    }, time: const Duration(seconds: 2));*/

    otherStreamSubscriptionList.add(showController.listen((p0) {
      if (showController.value) {
        if (isPlaying.value) {
          // 取消手动暂停

          isActivePause.value = false;
        }
      }
      if (isPlaying.value) {
        hasActivePause?.cancel();
      }
    }));

    otherStreamSubscriptionList.add(isPlaying.listen((p0) {
      // 代表手动暂停了
      if (!isPlaying.value) {
        if (showController.value) {
          isActivePause.value = true;
          hasActivePause?.cancel();
        } else {
          if (isActivePause.value) {
            hasActivePause = Timer(const Duration(seconds: 20), () {
              // 暂停了
              SmartDialog.showToast("系统监测视频已停止播放,正在为您刷新视频");
              isActivePause.value = false;
              refresh();
            });
          }
        }
      } else {
        hasActivePause?.cancel();
        isActivePause.value = false;
      }
    }));

    otherStreamSubscriptionList
        .add(mediaPlayerControllerInitialized.listen((value) {
      // fix auto fullscreen
      if (fullScreenByDefault && datasource.isNotEmpty && value) {
        Timer(const Duration(milliseconds: 500), () => toggleFullScreen());
      }
    }));
  }

  void debounceListen(Function? func, [int delay = 1000]) {
    if (_debounceTimer != null) {
      _debounceTimer?.cancel();
    }
    _debounceTimer = Timer(Duration(milliseconds: delay), () {
      func?.call();
      _debounceTimer = null;
    });
  }

  refreshView() {
    refreshCompleted.value = false;
    Timer(const Duration(microseconds: 200), () {
      brightnessKey.currentState?.dispose();
      brightnessKey = GlobalKey<BrightnessVolumnDargAreaState>();
      refreshCompleted.value = true;
    });
  }

  void initDanmaku() {
    hideDanmaku.value = PrefUtil.getBool('hideDanmaku') ?? false;
    otherStreamSubscriptionList.add(hideDanmaku.listen((data) {
      PrefUtil.setBool('hideDanmaku', data);
    }));
    danmakuArea.value = PrefUtil.getDouble('danmakuArea') ?? 1.0;
    otherStreamSubscriptionList.add(danmakuArea.listen((data) {
      PrefUtil.setDouble('danmakuArea', data);
    }));
    danmakuSpeed.value = PrefUtil.getDouble('danmakuSpeed') ?? 8;
    otherStreamSubscriptionList.add(danmakuSpeed.listen((data) {
      PrefUtil.setDouble('danmakuSpeed', data);
    }));
    danmakuFontSize.value = PrefUtil.getDouble('danmakuFontSize') ?? 16;
    otherStreamSubscriptionList.add(danmakuFontSize.listen((data) {
      PrefUtil.setDouble('danmakuFontSize', data);
    }));
    danmakuFontBorder.value = PrefUtil.getDouble('danmakuFontBorder') ?? 0.5;
    otherStreamSubscriptionList.add(danmakuFontBorder.listen((data) {
      PrefUtil.setDouble('danmakuFontBorder', data);
    }));
    danmakuOpacity.value = PrefUtil.getDouble('danmakuOpacity') ?? 1.0;
    otherStreamSubscriptionList.add(danmakuOpacity.listen((data) {
      PrefUtil.setDouble('danmakuOpacity', data);
    }));
  }

  void sendDanmaku(LiveMessage msg) {
    if (hideDanmaku.value) return;

    danmakuController.send([
      Bullet(
        child: DanmakuText(
          msg.message,
          fontSize: danmakuFontSize.value,
          strokeWidth: danmakuFontBorder.value,
          color: Color.fromARGB(255, msg.color.r, msg.color.g, msg.color.b),
        ),
      ),
    ]);
  }

  @override
  void dispose() async {
    if (hasDestory == false) {
      await destory();
    }

    super.dispose();
  }

  void refresh() {
    destory();
    Timer(const Duration(seconds: 2), () {
      try {
        LivePlayController livePlayController = Get.find<LivePlayController>();
        livePlayController.playUrls.value = [];
        livePlayController.qualites.value = [];
        livePlayController.onInitPlayerState(
            reloadDataType: ReloadDataType.refreash, firstLoad: true);
      } catch (e) {
        CoreLog.error(e);
      }
    });
  }

  void changeLine({bool active = false}) async {
    // 播放错误 不一定是线路问题 先切换路线解决 后面尝试通知用户切换播放器
    await destory();
    Timer(const Duration(seconds: 2), () {
      try {
        LivePlayController livePlayController = Get.find<LivePlayController>();
        livePlayController.onInitPlayerState(
          reloadDataType: ReloadDataType.changeLine,
          line: currentLineIndex,
          active: active,
        );
      } catch (e) {
        CoreLog.error(e);
      }
    });
  }

  destory() async {
    disposeAllStream();
    danmakuController.disable();
    await danmakuController.dispose();
    isPlaying.value = false;
    hasError.value = false;
    try {
      LivePlayController? livePlayController = Get.findOrNull<LivePlayController>();
      if(livePlayController != null) {
        livePlayController.success.value = false;
      }
    } catch (e) {
      CoreLog.error(e);
    }
    hasDestory = true;
    if (allowScreenKeepOn) WakelockPlus.disable();
    if (Platform.isAndroid || Platform.isIOS) {
      brightnessController.resetScreenBrightness();
      if (videoPlayerIndex == 4) {
        if (key.currentState?.isFullscreen() ?? false) {
          key.currentState?.exitFullscreen();
        }
        player.dispose();
      } else {
        if (gsyVideoPlayerController.value.isFullScreen) {
          gsyVideoPlayerController.exitFullScreen();
        }
        disposeGSYVideoPlayer();
      }
    } else {
      if (key.currentState?.isFullscreen() ?? false) {
        key.currentState?.exitFullscreen();
      }
      player.dispose();
    }
  }

  void setDataSource(String url) async {
    CoreLog.d("play url: $url");
    datasource = url;
    // fix datasource empty error
    if (datasource.isEmpty) {
      hasError.value = true;
      return;
    } else {
      hasError.value = false;
    }
    if (Platform.isWindows || Platform.isLinux || videoPlayerIndex == 4) {
      // player.pause();
      player.open(Media(datasource, httpHeaders: headers));
    } else if (Platform.isAndroid || Platform.isIOS) {
      gsyVideoPlayerController.dispose();
      chewieController.dispose();
      initGSYVideoPlayer();
      gsyVideoPlayerController
          .setRenderType(GsyVideoPlayerRenderType.surfaceView);
      gsyVideoPlayerController.setTimeOut(4000);
      gsyVideoPlayerController.setMediaCodec(enableCodec);
      gsyVideoPlayerController.setMediaCodecTexture(enableCodec);
      gsyVideoPlayerController.setNetWorkBuilder(
        datasource,
        mapHeadData: headers,
        cacheWithPlay: false,
        useDefaultIjkOptions: true,
      );
      gsyStreamSubscriptionList.add(gsyVideoPlayerController
          .videoEventStreamController.stream
          .listen((e) {
        switch (e.playState) {
          case VideoPlayState.playing:
          case VideoPlayState.playingBufferingStart:
          case VideoPlayState.pause:
          case VideoPlayState.completed:
            isBuffering.value = true;
            break;

          case VideoPlayState.normal:
          case VideoPlayState.prepareing:
          case VideoPlayState.error:
          case VideoPlayState.unknown:
            isBuffering.value = false;
            break;
          default:
            isBuffering.value = false;
            break;
        }
        var size = e.size;
        if (size != null) {
          isVertical.value = (size.height) > (size.width);
        }
      }));
      gsyVideoPlayerController.addEventsListener(gsyEventsListener);
    }
    notifyListeners();
  }

  void clearStreamSubscription(List<StreamSubscription> list) {
    for (var s in list) {
      s.cancel();
    }
    list.clear();
  }

  /// 释放 默认 播放器 Stream 流监听
  void disposeDefaultVideoStream() {
    clearStreamSubscription(defaultVideoStreamSubscriptionList);
  }

  /// 释放 Gsy Stream 流监听
  void disposeGsyStream() {
    clearStreamSubscription(gsyStreamSubscriptionList);
  }

  /// 释放 所有 Stream 流监听
  void disposeAllStream() {
    disposeGsyStream();
    disposeDefaultVideoStream();
    clearStreamSubscription(otherStreamSubscriptionList);
    brightnessKey.currentState?.dispose();
  }

  void gsyEventsListener(VideoEventType event) {
    if (event == VideoEventType.onError) {
      hasError.value = true;
      isPlaying.value = false;
      CoreLog.d('gsyVideoPlayer error ${gsyVideoPlayerController.value.what}');
    } else {
      mediaPlayerControllerInitialized.value =
          gsyVideoPlayerController.value.onVideoPlayerInitialized;
      if (mediaPlayerControllerInitialized.value) {
        isPlaying.value = gsyVideoPlayerController.value.isPlaying;
      }
    }
  }

  /// GSYVideoPlayer 释放监听
  void disposeGSYVideoPlayerListener() {
    gsyVideoPlayerController.removeEventsListener(gsyEventsListener);
  }

  void disposeGSYVideoPlayer() {
    disposeGSYVideoPlayerListener();
    disposeGsyStream();
    gsyVideoPlayerController.dispose();
    chewieController.dispose();
  }

  void initGSYVideoPlayer() {
    gsyVideoPlayerController = FixGsyVideoPlayerController(
        allowBackgroundPlayback: allowBackgroundPlay,
        player: getVideoPlayerType(videoPlayerIndex));
    chewieController = ChewieController(
      videoPlayerController: gsyVideoPlayerController,
      autoPlay: false,
      looping: false,
      draggableProgressBar: false,
      overlay: VideoControllerPanel(
        controller: this,
      ),
      showControls: false,
      useRootNavigator: true,
      showOptions: false,
      rotateWithSystem: settings.enableRotateScreenWithSystem.value,
    );
  }

  void setVideoFit(BoxFit fit) {
    videoFit.value = fit;
    if (Platform.isWindows || Platform.isLinux || videoPlayerIndex == 4) {
      key.currentState?.update(fit: fit);
    } else if (Platform.isAndroid || Platform.isIOS) {
      gsyVideoPlayerController.setBoxFit(fit);
    }
  }

  void togglePlayPause() {
    if (Platform.isWindows || Platform.isLinux || videoPlayerIndex == 4) {
      mediaPlayerController.player.playOrPause();
    } else if (Platform.isAndroid || Platform.isIOS) {
      if (isPlaying.value) {
        gsyVideoPlayerController.pause();
      } else {
        gsyVideoPlayerController.resume();
      }
    }
  }

  void play() {
    if (Platform.isWindows || Platform.isLinux || videoPlayerIndex == 4) {
      mediaPlayerController.player.play();
    } else if (Platform.isAndroid || Platform.isIOS) {
      gsyVideoPlayerController.resume();
    }
  }

  Future<void> pause() async {
    if (Platform.isWindows || Platform.isLinux || videoPlayerIndex == 4) {
      await mediaPlayerController.player.pause();
    } else if (Platform.isAndroid || Platform.isIOS) {
      await gsyVideoPlayerController.pause();
    }
  }

  exitFullScreen() {
    if (Platform.isAndroid) {
      if (videoPlayerIndex == 4) {
        isFullscreen.value = false;
        if (key.currentState?.isFullscreen() ?? false) {
          key.currentState?.exitFullscreen();
        }
      } else {
        if (isFullscreen.value) {
          // isVertical.value = false;
          setLandscapeOrientation();
          gsyVideoPlayerController.exitFullScreen();
          isFullscreen.value = false;
        }
      }
      showSettting.value = false;
    }
  }

  /// 设置横屏
  Future setLandscapeOrientation() async {
    // isVertical.value = false;
    if (Platform.isWindows || Platform.isLinux || videoPlayerIndex == 4) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      gsyVideoPlayerController.resolveByClick();
    }
  }

  /// 设置竖屏
  Future setPortraitOrientation() async {
    // isVertical.value = true;
    if (Platform.isWindows || Platform.isLinux || videoPlayerIndex == 4) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge,
          overlays: SystemUiOverlay.values);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge,
          overlays: SystemUiOverlay.values);
      gsyVideoPlayerController.backToProtVideo();
    }
  }

  void toggleFullScreen() async {
    CoreLog.d("toggleFullScreen");
    // disable locked
    showLocked.value = false;
    // fix danmaku overlap bug
    if (!hideDanmaku.value) {
      hideDanmaku.value = true;
      Timer(const Duration(milliseconds: 500), () {
        hideDanmaku.value = false;
      });
    }
    // fix obx setstate when build
    showControllerTimer?.cancel();
    Timer(const Duration(milliseconds: 500), () {
      enableController();
    });

    if (Platform.isWindows || Platform.isLinux || videoPlayerIndex == 4) {
      if (isFullscreen.value) {
        await key.currentState?.exitFullscreen();
      } else {
        await key.currentState?.enterFullscreen();
        CoreLog.d("isVertical: $isVertical");
        if (isVertical.value) {
          // 竖屏
          // setPortraitOrientation();
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ]);
        }
      }
      isFullscreen.toggle();
    } else {
      isFullscreen.toggle();
      gsyVideoPlayerController.toggleFullScreen();
    }
    refreshView();
  }

  void toggleWindowFullScreen() {
    // disable locked
    showLocked.value = false;
    // fix danmaku overlap bug
    if (!hideDanmaku.value) {
      hideDanmaku.value = true;
      Timer(const Duration(milliseconds: 500), () {
        hideDanmaku.value = false;
      });
    }
    // fix obx setstate when build
    showControllerTimer?.cancel();
    Timer(const Duration(milliseconds: 500), () {
      enableController();
    });

    if (Platform.isWindows || Platform.isLinux) {
      if (!isWindowFullscreen.value) {
        Get.to(() => DesktopFullscreen(
              controller: this,
              key: UniqueKey(),
            ));
      } else {
        Navigator.of(Get.context!).pop();
      }
      isWindowFullscreen.toggle();
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
    enableController();
    refreshView();
  }

  void enterPipMode(BuildContext context) async {
    if ((Platform.isAndroid || Platform.isIOS)) {
      if (videoPlayerIndex != 4) {
        showController.value = false;
        await gsyVideoPlayerController.enablePictureInPicture();
      }
    }
  }

  // volumn & brightness
  Future<double?> volumn() async {
    if (Platform.isWindows) {
      return mediaPlayerController.player.state.volume / 100;
    }
    return await FlutterVolumeController.getVolume();
  }

  Future<double> brightness() async {
    return await brightnessController.current;
  }

  void setVolumn(double value) async {
    if (Platform.isWindows) {
      mediaPlayerController.player.setVolume(value * 100);
    } else {
      await FlutterVolumeController.setVolume(value);
    }
  }

  void setBrightness(double value) async {
    if (Platform.isAndroid || Platform.isIOS) {
      await brightnessController.setScreenBrightness(value);
    }
  }
}

// use fullscreen with controller provider

class DesktopFullscreen extends StatelessWidget {
  const DesktopFullscreen({super.key, required this.controller});

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            Obx(() => media_kit_video.Video(
                  controller: controller.mediaPlayerController,
                  fit: controller
                      .settings.videofitArrary[controller.videoFitIndex.value],
                  pauseUponEnteringBackgroundMode:
                      !controller.settings.enableBackgroundPlay.value,
                  // 进入背景模式时暂停
                  resumeUponEnteringForegroundMode: true,
                  // 进入前景模式后恢复
                  controls: (state) =>
                      VideoControllerPanel(controller: controller),
                ))
          ],
        ),
      ),
    );
  }
}

// use fullscreen with controller provider
