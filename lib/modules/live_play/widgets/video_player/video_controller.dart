import 'dart:io';
import 'dart:async';
import 'dart:developer';
import 'package:get/get.dart';
import 'video_controller_panel.dart';
import 'package:flutter/services.dart';
import 'package:pure_live/common/index.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:pure_live/plugins/barrage.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:gsy_video_player/gsy_video_player.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:pure_live/modules/live_play/load_type.dart';
import 'package:pure_live/modules/live_play/live_play_controller.dart';
import 'package:media_kit_video/media_kit_video.dart' as media_kit_video;
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/danmaku_text.dart';

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
  final isVertical = false.obs;
  final videoFitIndex = 0.obs;
  final videoFit = BoxFit.contain.obs;
  final mediaPlayerControllerInitialized = false.obs;

  ScreenBrightness brightnessController = ScreenBrightness();

  double initBrightness = 0.0;

  final String qualiteName;

  final int currentLineIndex;

  final int currentQuality;

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
  late final GlobalKey<media_kit_video.VideoState> key = GlobalKey<media_kit_video.VideoState>();

  // Create a [Player] to control playback.
  late Player player;
  // CeoController] to handle video output from [Player].
  late media_kit_video.VideoController mediaPlayerController;

  // Video player control
  late GsyVideoPlayerController gsyVideoPlayerController;

  late ChewieController chewieController;

  final playerRefresh = false.obs;

  GlobalKey<BrightnessVolumnDargAreaState> brightnessKey = GlobalKey<BrightnessVolumnDargAreaState>();

  LivePlayController livePlayController = Get.find<LivePlayController>();

  final SettingsService settings = Get.find<SettingsService>();

  int videoPlayerIndex = 0;

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
      _battery.onBatteryStateChanged.listen((BatteryState state) async {
        batteryLevel.value = await _battery.batteryLevel;
      });
    }
  }

  void initVideoController() async {
    FlutterVolumeController.updateShowSystemUI(false);
    videoPlayerIndex = settings.videoPlayerIndex.value;
    enableCodec = settings.enableCodec.value;
    if (Platform.isWindows || Platform.isLinux || videoPlayerIndex == 4) {
      player = Player();
      if (player.platform is NativePlayer) {
        (player.platform as dynamic).setProperty('cache', 'no'); // --cache=<yes|no|auto>
        (player.platform as dynamic).setProperty('cache-secs', '0'); // --cache-secs=<seconds> with cache but why not.
        (player.platform as dynamic).setProperty(
            'demuxer-seekable-cache', 'no'); // --demuxer-seekable-cache=<yes|no|auto> Redundant with cache but why not.
        (player.platform as dynamic).setProperty('demuxer-max-back-bytes', '0'); // --demuxer-max-back-bytes=<bytesize>
        (player.platform as dynamic).setProperty('demuxer-donate-buffer', 'no'); // --demuxer-donate-buffer==<yes|no>
      }
      mediaPlayerController = media_kit_video.VideoController(player);
      setDataSource(datasource);
      mediaPlayerController.player.stream.playing.listen((bool playing) {
        if (playing) {
          if (!mediaPlayerControllerInitialized.value) {
            mediaPlayerControllerInitialized.value = true;
          }
          isPlaying.value = true;
        } else {
          isPlaying.value = false;
        }
      });
      mediaPlayerController.player.stream.error.listen((event) {
        if (event.toString().contains('Failed to open')) {
          hasError.value = true;
          isPlaying.value = false;
        }
      });
    } else if (Platform.isAndroid || Platform.isIOS) {
      gsyVideoPlayerController = GsyVideoPlayerController(
          allowBackgroundPlayback: allowBackgroundPlay, player: getVideoPlayerType(videoPlayerIndex));
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
      gsyVideoPlayerController.setRenderType(GsyVideoPlayerRenderType.surfaceView);
      gsyVideoPlayerController.setTimeOut(4000);
      gsyVideoPlayerController.setMediaCodec(enableCodec);
      gsyVideoPlayerController.setMediaCodecTexture(enableCodec);
      gsyVideoPlayerController.setNetWorkBuilder(
        datasource,
        mapHeadData: headers,
        cacheWithPlay: false,
        useDefaultIjkOptions: true,
      );
      gsyVideoPlayerController.addEventsListener((VideoEventType event) {
        if (event == VideoEventType.onError) {
          hasError.value = true;
          isPlaying.value = false;
          log('video error ${gsyVideoPlayerController.value.what}', name: 'video_player');
        } else {
          mediaPlayerControllerInitialized.value = gsyVideoPlayerController.value.onVideoPlayerInitialized;
          if (mediaPlayerControllerInitialized.value) {
            isPlaying.value = gsyVideoPlayerController.value.isPlaying;
          }
        }
      });
    }
    debounce(hasError, (callback) {
      if (hasError.value && !livePlayController.isLastLine.value) {
        SmartDialog.showToast("视频播放失败,正在为您切换线路");
        changeLine();
      }
    }, time: const Duration(seconds: 2));

    showController.listen((p0) {
      if (showController.value) {
        if (isPlaying.value) {
          // 取消手动暂停

          isActivePause.value = false;
        }
      }
      if (isPlaying.value) {
        hasActivePause?.cancel();
      }
    });

    isPlaying.listen((p0) {
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
    });

    mediaPlayerControllerInitialized.listen((value) {
      // fix auto fullscreen
      if (fullScreenByDefault && datasource.isNotEmpty && value) {
        Timer(const Duration(milliseconds: 500), () => toggleFullScreen());
      }
    });
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
      brightnessKey = GlobalKey<BrightnessVolumnDargAreaState>();
      refreshCompleted.value = true;
    });
  }

  void initDanmaku() {
    hideDanmaku.value = PrefUtil.getBool('hideDanmaku') ?? false;
    hideDanmaku.listen((data) {
      PrefUtil.setBool('hideDanmaku', data);
    });
    danmakuArea.value = PrefUtil.getDouble('danmakuArea') ?? 1.0;
    danmakuArea.listen((data) {
      PrefUtil.setDouble('danmakuArea', data);
    });
    danmakuSpeed.value = PrefUtil.getDouble('danmakuSpeed') ?? 8;
    danmakuSpeed.listen((data) {
      PrefUtil.setDouble('danmakuSpeed', data);
    });
    danmakuFontSize.value = PrefUtil.getDouble('danmakuFontSize') ?? 16;
    danmakuFontSize.listen((data) {
      PrefUtil.setDouble('danmakuFontSize', data);
    });
    danmakuFontBorder.value = PrefUtil.getDouble('danmakuFontBorder') ?? 0.5;
    danmakuFontBorder.listen((data) {
      PrefUtil.setDouble('danmakuFontBorder', data);
    });
    danmakuOpacity.value = PrefUtil.getDouble('danmakuOpacity') ?? 1.0;
    danmakuOpacity.listen((data) {
      PrefUtil.setDouble('danmakuOpacity', data);
    });
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
    livePlayController.onInitPlayerState(reloadDataType: ReloadDataType.refreash);
  }

  void changeLine({bool active = false}) async {
    // 播放错误 不一定是线路问题 先切换路线解决 后面尝试通知用户切换播放器
    await destory();
    livePlayController.onInitPlayerState(
      reloadDataType: ReloadDataType.changeLine,
      line: currentLineIndex,
      active: active,
    );
  }

  destory() async {
    danmakuController.disable();
    await danmakuController.dispose();
    isPlaying.value = false;
    hasError.value = false;
    livePlayController.success.value = false;
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
        chewieController.dispose();
        gsyVideoPlayerController.dispose();
      }
    } else {
      if (key.currentState?.isFullscreen() ?? false) {
        key.currentState?.exitFullscreen();
      }
      player.dispose();
    }
  }

  void setDataSource(String url) async {
    datasource = url;
    // fix datasource empty error
    if (datasource.isEmpty) {
      hasError.value = true;
      return;
    } else {
      hasError.value = false;
    }
    if (Platform.isWindows || Platform.isLinux || videoPlayerIndex == 4) {
      player.pause();
      player.open(Media(datasource, httpHeaders: headers));
    }
    notifyListeners();
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

  exitFullScreen() {
    if (Platform.isAndroid) {
      if (videoPlayerIndex == 4) {
        isFullscreen.value = false;
        if (key.currentState?.isFullscreen() ?? false) {
          key.currentState?.exitFullscreen();
        }
      } else {
        if (isFullscreen.value) {
          isVertical.value = false;
          gsyVideoPlayerController.exitFullScreen();
          isFullscreen.value = false;
        }
      }
      showSettting.value = false;
    }
  }

  /// 设置横屏
  Future setLandscapeOrientation() async {
    isVertical.value = false;
    if (videoPlayerIndex == 4) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      gsyVideoPlayerController.resolveByClick();
    }
  }

  /// 设置竖屏
  Future setPortraitOrientation() async {
    isVertical.value = true;
    if (videoPlayerIndex == 4) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      gsyVideoPlayerController.backToProtVideo();
    }
  }

  void toggleFullScreen() async {
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
        key.currentState?.exitFullscreen();
      } else {
        key.currentState?.enterFullscreen();
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
                  fit: controller.settings.videofitArrary[controller.videoFitIndex.value],
                  controls: (state) => VideoControllerPanel(controller: controller),
                ))
          ],
        ),
      ),
    );
  }
}

// use fullscreen with controller provider
