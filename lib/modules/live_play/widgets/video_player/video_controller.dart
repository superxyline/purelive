import 'dart:async';
import 'dart:developer';
import 'dart:io';


import 'package:better_player/better_player.dart';
import 'package:dart_vlc/dart_vlc.dart';
import 'package:flutter/services.dart';
import 'package:flutter_barrage/flutter_barrage.dart';
import 'package:get/get.dart';
import 'package:pure_live/common/index.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock/wakelock.dart';
import 'package:window_manager/window_manager.dart';

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

  // Video player status
  Player? desktopController;
  BetterPlayerController? mobileController;
  VolumeController volumeController = VolumeController()..showSystemUI = false;
  ScreenBrightness brightnessController = ScreenBrightness();

  final hasError = false.obs;
  final isPlaying = false.obs;
  final isBuffering = false.obs;
  final isPipMode = false.obs;
  final isFullscreen = false.obs;
  final isWindowFullscreen = false.obs;
  bool get supportPip => Platform.isAndroid;
  bool get supportWindowFull => Platform.isWindows || Platform.isLinux;

  bool get fullscreenUI => isFullscreen.value || isWindowFullscreen.value;

  // Controller ui status
  Timer? showControllerTimer;
  final showController = true.obs;
  final showSettting = false.obs;
  final showLocked = false.obs;

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
    if (allowScreenKeepOn) Wakelock.enable();
    initVideoController();
    initDanmaku();
  }

  void initVideoController() {
    if (Platform.isWindows || Platform.isLinux) {
      desktopController = Player(id: 100);
      setDataSource(datasource);
      desktopController?.playbackStream.listen(desktopStateListener);
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

      // fix auto fullscreen
      if (fullScreenByDefault && datasource.isNotEmpty) {
        Timer(const Duration(milliseconds: 500), () => toggleFullScreen());
      }
      mobileController?.addEventsListener(mobileStateListener);
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
  }

  dynamic desktopStateListener(PlaybackState state) {
    hasError.value = state.isCompleted;
    if(state.isPlaying){
      Timer(const Duration(seconds: 4), () {
    isPlaying.value = state.isPlaying;
       });
    }

    isBuffering.value = (desktopController?.bufferingProgress ?? 1.0) < 1.0;
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
    if (allowScreenKeepOn) Wakelock.disable();
    _shutdownTimer?.cancel();
    brightnessController.resetScreenBrightness();
    danmakuController.dispose();
    desktopController?.dispose();
    mobileController?.removeEventsListener(mobileStateListener);
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
  }

  void setDataSource(String url) {
    datasource = url;
    // fix datasource empty error
    if (datasource.isEmpty) {
      hasError.value = true;
      return;
    }

    if (Platform.isWindows || Platform.isLinux) {
      desktopController?.pause();
      desktopController?.open(
        Media.directShow(rawUrl: datasource),
        autoStart: true,
      );
    } else if (Platform.isAndroid || Platform.isIOS) {
      mobileController?.setupDataSource(BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        url,
        liveStream: true,
        notificationConfiguration: allowBackgroundPlay
            ? BetterPlayerNotificationConfiguration(
                showNotification: true,
                title: room.title,
                author: room.nick,
                imageUrl: room.avatar,
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
      isPlaying.value ? desktopController!.pause() : desktopController!.play();
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
      if (!isFullscreen.value) {
        WindowManager.instance.setFullScreen(true);
        Get.to(() => DesktopFullscreen(controller: this));
      } else {
        WindowManager.instance.setFullScreen(false);
        Get.back();
        // 重设大小，修复窗口大小BUG
        WindowManager.instance.getSize().then((value) => WindowManager.instance
            .setSize(Size(value.width + 1, value.height + 1)));
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
  Future<double> volumn() async {
    if (Platform.isWindows || Platform.isLinux) {
      return Future(() => desktopController?.general.volume ?? 1);
    } else if (Platform.isAndroid || Platform.isIOS) {
      return await volumeController.getVolume();
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
  }

  Future<double> brightness() async {
    if (Platform.isWindows || Platform.isLinux) {
      return await brightnessController.current;
    } else if (Platform.isAndroid || Platform.isIOS) {
      return await brightnessController.current;
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
  }

  void setVolumn(double value) async {
    if (Platform.isWindows || Platform.isLinux) {
      desktopController?.setVolume(value);
    } else if (Platform.isAndroid || Platform.isIOS) {
      volumeController.setVolume(value);
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
  }

  void setBrightness(double value) async {
    if (Platform.isWindows || Platform.isLinux) {
      brightnessController.setScreenBrightness(value);
    } else if (Platform.isAndroid || Platform.isIOS) {
      brightnessController.setScreenBrightness(value);
    } else {
      throw UnimplementedError('Unsupported Platform');
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
      widget.controller.refresh();
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
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Obx(() => Video(
                player: controller.desktopController,
                fit: controller.videoFit.value,
              )),
          VideoControllerPanel(controller: controller),
        ],
      ),
    );
  }
}
