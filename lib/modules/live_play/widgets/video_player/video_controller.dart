import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:floating/floating.dart';
import 'package:flutter/services.dart';
import 'package:flutter_barrage/flutter_barrage.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart' as media_kit_video;
import 'package:pure_live/common/index.dart';
import 'package:pure_live/modules/live_play/live_play_controller.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/danmaku_text.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
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
  bool isVertical = false;
  final videoFit = BoxFit.contain.obs;
  final floating = Floating();
  StreamSubscription<PiPStatus>? _pipSubscription;
  ScreenBrightness brightnessController = ScreenBrightness();
  double initBrightness = 0.0;
  final hasError = false.obs;
  final isPlaying = false.obs;
  final isBuffering = false.obs;
  final isPipMode = false.obs;
  final isFullscreen = false.obs;
  final isWindowFullscreen = false.obs;
  bool get supportPip => Platform.isAndroid;
  bool get supportWindowFull => Platform.isWindows || Platform.isLinux;
  bool get fullscreenUI => isFullscreen.value || isWindowFullscreen.value;
  final refreshCompleted = true.obs;
  // Video player status
  // A [GlobalKey<VideoState>] is required to access the programmatic fullscreen interface.
  late final GlobalKey<media_kit_video.VideoState> key =
      GlobalKey<media_kit_video.VideoState>();

  GlobalKey<BrightnessVolumnDargAreaState> brightnessKey =
      GlobalKey<BrightnessVolumnDargAreaState>();
  // Create a [Player] to control playback.
  late Player player;
  // Create a [VideoController] to handle video output from [Player].
  late media_kit_video.VideoController mediaPlayerController;
  LivePlayController livePlayController = Get.find<LivePlayController>();
  // Controller ui status
  Timer? showControllerTimer;
  final showController = true.obs;
  final showSettting = false.obs;
  final showLocked = false.obs;
  bool playBackisPlaying = false;
  final danmuKey = GlobalKey();
  double volume = 0.0;
  void enableController() {
    showControllerTimer?.cancel();
    showControllerTimer = Timer(const Duration(seconds: 2), () {
      showController.value = false;
    });
    showController.value = true;
  }

  // Timed shutdown control
  final shutdownMinute = 0.obs;
  Timer? _shutdownTimer;
  void setShutdownTimer(int minutes) {
    showControllerTimer?.cancel();
    _shutdownTimer?.cancel();
    shutdownMinute.value = minutes;
    if (minutes == 0) return;
    _shutdownTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      shutdownMinute.value--;
      if (shutdownMinute.value == 0) exit(0);
    });
  }

  VideoController({
    required this.playerKey,
    required this.room,
    required this.datasourceType,
    required this.datasource,
    this.allowBackgroundPlay = false,
    this.allowScreenKeepOn = false,
    this.allowFullScreen = true,
    this.fullScreenByDefault = false,
    this.autoPlay = true,
    BoxFit fitMode = BoxFit.contain,
  }) {
    videoFit.value = fitMode;
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

  void initVideoController() {
    FlutterVolumeController.showSystemUI = false;
    player = Player();
    bool enableHardwareAcceleration = Platform.isAndroid ? false : true;
    mediaPlayerController = media_kit_video.VideoController(
      player,
      configuration: media_kit_video.VideoControllerConfiguration(
          androidAttachSurfaceAfterVideoParameters: false,
          enableHardwareAcceleration: enableHardwareAcceleration),
    );
    setDataSource(datasource);
    mediaPlayerController.player.stream.playing.listen((bool playing) {
      if (playing) {
        isPlaying.value = true;
      } else {
        isPlaying.value = false;
      }
    });

    // fix auto fullscreen
    if (fullScreenByDefault && datasource.isNotEmpty) {
      Timer(const Duration(milliseconds: 500), () => toggleFullScreen());
    }
  }

  refreshView() {
    refreshCompleted.value = false;
    Timer(const Duration(microseconds: 200), () {
      brightnessKey = GlobalKey<BrightnessVolumnDargAreaState>();
      refreshCompleted.value = true;
    });
  }

  // Danmaku player control
  BarrageWallController danmakuController = BarrageWallController();
  final hideDanmaku = false.obs;
  final danmakuArea = 1.0.obs;
  final danmakuSpeed = 8.0.obs;
  final danmakuFontSize = 16.0.obs;
  final danmakuFontBorder = 0.5.obs;
  final danmakuOpacity = 1.0.obs;

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
  void dispose() {
    if (allowScreenKeepOn) WakelockPlus.disable();
    _shutdownTimer?.cancel();
    if (Platform.isAndroid || Platform.isIOS) {
      brightnessController.resetScreenBrightness();
    }
    if (key.currentState?.isFullscreen() ?? false) {
      key.currentState?.exitFullscreen();
    }
    player.pause();
    player.dispose();
    floating.dispose();
    _pipSubscription?.cancel();
    super.dispose();
  }

  void refresh() {
    setDataSource(datasource);
  }

  void setDataSource(String url) async {
    datasource = url;
    // fix datasource empty error
    if (datasource.isEmpty) {
      hasError.value = true;
      return;
    }
    player.open(Media(datasource));
  }

  void setVideoFit(BoxFit fit) {
    videoFit.value = fit;
  }

  void togglePlayPause() {
    player.playOrPause();
  }

  Future<void> exitFullScreen() async {
    if (key.currentState?.isFullscreen() ?? false) {
      await key.currentState?.exitFullscreen();
    }
  }

  /// 设置横屏
  Future setLandscapeOrientation() async {
    isVertical = false;
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  /// 设置竖屏
  Future setPortraitOrientation() async {
    isVertical = true;
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  void toggleFullScreen() {
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

    if (key.currentState?.isFullscreen() ?? false) {
      key.currentState?.exitFullscreen();
    } else {
      key.currentState?.enterFullscreen();
    }
    isFullscreen.toggle();
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
        Get.back();
      }
      isWindowFullscreen.toggle();
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
    enableController();
    refreshView();
  }

  void enterPipMode(BuildContext context) async {
    if (supportPip) {
      final canUsePiP = await floating.isPipAvailable;
      if (canUsePiP) {
        Rational ratio = const Rational.landscape();
        await floating.enable(aspectRatio: ratio);
        //监听事件
        _pipSubscription ??= floating.pipStatus$.listen((event) {
          if (event == PiPStatus.enabled) {
            if (Platform.isAndroid) {
              isPipMode.value = true;
            }
          } else {
            isPipMode.value = false;
          }
        });
      }
    }
  }

  // volumn & brightness
  Future<double?> volumn() async {
    return await FlutterVolumeController.getVolume();
  }

  Future<double> brightness() async {
    return await brightnessController.current;
  }

  void setVolumn(double value) async {
    await FlutterVolumeController.setVolume(value);
  }

  void setBrightness(double value) async {
    if (Platform.isAndroid || Platform.isIOS) {
      await brightnessController.setScreenBrightness(value);
    }
  }
}

// use fullscreen with controller provider

class DesktopFullscreen extends StatelessWidget {
  const DesktopFullscreen({Key? key, required this.controller})
      : super(key: key);

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
                  fit: controller.videoFit.value,
                  controls: (state) =>
                      VideoControllerPanel(controller: controller),
                ))
          ],
        ),
      ),
    );
  }
}
