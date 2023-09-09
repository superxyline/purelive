import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_barrage/flutter_barrage.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart' as media_kit_video;
import 'package:pure_live/common/index.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:better_player_v3/better_player.dart';
import 'danmaku_text.dart';
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
  final videoFit = BoxFit.contain.obs;

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
  // Video player status
  // A [GlobalKey<VideoState>] is required to access the programmatic fullscreen interface.
  late final GlobalKey<media_kit_video.VideoState> key =
      GlobalKey<media_kit_video.VideoState>();
  // Create a [Player] to control playback.
  late Player player;
  // Create a [VideoController] to handle video output from [Player].
  late media_kit_video.VideoController desktopController;
  BetterPlayerController? mobileController;
  // Controller ui status
  Timer? showControllerTimer;
  final showController = true.obs;
  final showSettting = false.obs;
  final showLocked = false.obs;
  bool playBackisPlaying = false;

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
    if (Platform.isWindows || Platform.isLinux) {
      player = Player();
      desktopController = media_kit_video.VideoController(player);
      setDataSource(datasource);
      desktopController.player.stream.playing.listen((bool playing) {
        if (playing) {
          isPlaying.value = true;
        } else {
          isPlaying.value = false;
        }
      });
    } else if (Platform.isAndroid || Platform.isIOS) {
      mobileController = BetterPlayerController(
        BetterPlayerConfiguration(
          autoPlay: true,
          fit: videoFit.value,
          allowedScreenSleep: !allowScreenKeepOn,
          autoDetectFullscreenDeviceOrientation: true,
          autoDetectFullscreenAspectRatio: true,
          errorBuilder: (context, errorMessage) => Container(),
          routePageBuilder: (context, animation, second, controllerProvider) =>
              AnimatedBuilder(
            animation: animation,
            builder: (context, child) => MobileFullscreen(
              controller: this,
              controllerProvider: controllerProvider,
            ),
          ),
        ),
      );
      mobileController?.setControlsEnabled(false);
      setDataSource(datasource);
      mobileController?.addEventsListener(mobileStateListener);
    } else {
      throw UnimplementedError('Unsupported Platform');
    }

    // fix auto fullscreen
    if (fullScreenByDefault && datasource.isNotEmpty) {
      Timer(const Duration(milliseconds: 500), () => toggleFullScreen());
    }
  }

  dynamic mobileStateListener(dynamic state) {
    if (mobileController?.videoPlayerController != null) {
      hasError.value =
          mobileController?.videoPlayerController?.value.hasError ?? true;
      isPlaying.value = mobileController?.isPlaying() ?? false;
      isBuffering.value = mobileController?.isBuffering() ?? false;
      isPipMode.value =
          mobileController?.videoPlayerController?.value.isPip ?? false;
    }
  }

  // Danmaku player control
  final danmakuController = BarrageWallController();
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
    danmakuController.dispose();
    if (Platform.isAndroid || Platform.isIOS) {
      mobileController?.removeEventsListener(mobileStateListener);
      mobileController?.dispose();
      mobileController = null;
    } else {
      player.dispose();
    }
    super.dispose();
  }

  void refresh() {
    if (Platform.isWindows || Platform.isLinux) {
      setDataSource(datasource);
    } else if (Platform.isAndroid || Platform.isIOS) {
      if (mobileController?.videoPlayerController != null) {
        mobileController?.retryDataSource();
      }
    }
    setDataSource(datasource);
  }

  void setDataSource(String url) async {
    datasource = url;
    // fix datasource empty error
    if (datasource.isEmpty) {
      hasError.value = true;
      return;
    }
    if (Platform.isWindows || Platform.isLinux) {
      player.open(Media(datasource));
    } else if (Platform.isAndroid || Platform.isIOS) {
      mobileController?.setupDataSource(BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        url,
        liveStream: true,
        notificationConfiguration: allowBackgroundPlay
            ? BetterPlayerNotificationConfiguration(
                showNotification: true,
                title: room.title,
                imageUrl: room.avatar,
                author: room.nick,
                activityName: "MainActivity",
              )
            : null,
      ));
      mobileController?.pause();
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
  }

  void setVideoFit(BoxFit fit) {
    videoFit.value = fit;
    if (Platform.isWindows || Platform.isLinux) {
    } else if (Platform.isAndroid || Platform.isIOS) {
      mobileController?.setOverriddenFit(videoFit.value);
      mobileController?.retryDataSource();
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
    notifyListeners();
  }

  void togglePlayPause() {
    if (Platform.isWindows || Platform.isLinux) {
      player.playOrPause();
    } else if (Platform.isAndroid || Platform.isIOS) {
      isPlaying.value ? mobileController!.pause() : mobileController!.play();
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
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

    if (Platform.isWindows || Platform.isLinux) {
      if (key.currentState?.isFullscreen() ?? false) {
        key.currentState?.exitFullscreen();
      } else {
        key.currentState?.enterFullscreen();
      }
      isFullscreen.toggle();
    } else if (Platform.isAndroid || Platform.isIOS) {
      mobileController?.toggleFullScreen();
      Timer(const Duration(milliseconds: 400), () {
        isFullscreen.toggle();
        // fix immersion status bar problem
        if (Platform.isAndroid) {
          SystemChrome.setEnabledSystemUIMode(!isFullscreen.value
              ? SystemUiMode.edgeToEdge
              : SystemUiMode.immersiveSticky);
        }
      });
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
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
        Get.to(() => DesktopFullscreen(controller: this));
      } else {
        Get.back();
      }
      isWindowFullscreen.toggle();
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
    enableController();
  }

  void enterPipMode(BuildContext context) async {
    if ((Platform.isAndroid || Platform.isIOS)) {
      if (await mobileController?.isPictureInPictureSupported() ?? false) {
        isPipMode.value = true;
        mobileController?.enablePictureInPicture(playerKey);
      } else {
        SnackBarUtil.error('暂不支持画中画');
      }
    } else {
      throw UnimplementedError('Unsupported Platform');
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
class MobileFullscreen extends StatefulWidget {
  const MobileFullscreen({
    Key? key,
    required this.controller,
    required this.controllerProvider,
  }) : super(key: key);

  final VideoController controller;
  final BetterPlayerControllerProvider controllerProvider;

  @override
  State<MobileFullscreen> createState() => _MobileFullscreenState();
}

class _MobileFullscreenState extends State<MobileFullscreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    WidgetsBinding.instance.addObserver(this);
    super.initState();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (Platform.isAndroid || Platform.isIOS) {
        widget.controller.refresh();
      }
    }
  }

  @override
  dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: WillPopScope(
        onWillPop: () {
          widget.controller.toggleFullScreen();
          return Future(() => true);
        },
        child: Container(
          alignment: Alignment.center,
          color: Colors.black,
          child: Stack(
            alignment: Alignment.center,
            children: [
              widget.controllerProvider,
              VideoControllerPanel(controller: widget.controller),
            ],
          ),
        ),
      ),
    );
  }
}

class DesktopFullscreen extends StatelessWidget {
  const DesktopFullscreen({Key? key, required this.controller})
      : super(key: key);

  final VideoController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          CallbackShortcuts(
            bindings: {
              // Default key-board shortcuts.
              // https://support.google.com/youtube/answer/7631406
              const SingleActivator(LogicalKeyboardKey.mediaPlay): () =>
                  controller.desktopController.player.play(),
              const SingleActivator(LogicalKeyboardKey.mediaPause): () =>
                  controller.desktopController.player.pause(),
              const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () =>
                  controller.desktopController.player.playOrPause(),
              const SingleActivator(LogicalKeyboardKey.space): () =>
                  controller.desktopController.player.playOrPause(),

              const SingleActivator(LogicalKeyboardKey.arrowUp): () {
                final volume =
                    controller.desktopController.player.state.volume + 5.0;
                controller.desktopController.player
                    .setVolume(volume.clamp(0.0, 100.0));
              },
              const SingleActivator(LogicalKeyboardKey.arrowDown): () {
                final volume =
                    controller.desktopController.player.state.volume - 5.0;
                controller.desktopController.player
                    .setVolume(volume.clamp(0.0, 100.0));
              },
              const SingleActivator(LogicalKeyboardKey.keyF): () =>
                  controller.toggleFullScreen(),
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  controller.toggleFullScreen(),
            },
            child: Focus(
              autofocus: true,
              child: Obx(() => media_kit_video.Video(
                    controller: controller.desktopController,
                    fit: controller.videoFit.value,
                    controls: (state) =>
                        VideoControllerPanel(controller: controller),
                  )),
            ),
          )
        ],
      ),
    );
  }
}
