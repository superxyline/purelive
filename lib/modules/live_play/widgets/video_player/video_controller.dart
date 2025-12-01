import 'dart:io';
import 'dart:async';
import 'package:get/get.dart';
import 'video_controller_panel.dart';
import 'package:flutter/services.dart';
import 'package:floating/floating.dart';
import 'package:pure_live/common/index.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:pure_live/modules/live_play/load_type.dart';
import 'package:pure_live/pkg/canvas_danmaku/danmaku_controller.dart';
import 'package:pure_live/modules/live_play/live_play_controller.dart';
import 'package:pure_live/pkg/canvas_danmaku/models/danmaku_option.dart';
import 'package:media_kit_video/media_kit_video.dart' as media_kit_video;
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:pure_live/pkg/canvas_danmaku/models/danmaku_content_item.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/fullscreen.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/fijk_helper.dart';

class VideoController with ChangeNotifier {
  final LiveRoom room;
  final String datasourceType;
  String datasource;
  final bool allowBackgroundPlay;
  final bool allowScreenKeepOn;
  final bool allowFullScreen;
  final bool fullScreenByDefault;
  final bool autoPlay;
  final Map<String, String> headers;

  final int videoPlayerIndex;
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

  final videoSizeWidth = 0.0.obs;

  final videoSizeHeight = 0.0.obs;

  // ignore: prefer_typing_uninitialized_variables
  late final Floating pip;
  // Video player status
  // A [GlobalKey<VideoState>] is required to access the programmatic fullscreen interface.
  late final GlobalKey<media_kit_video.VideoState> key = GlobalKey<media_kit_video.VideoState>();

  // Create a [Player] to control playback.
  late Player player;
  // CeoController] to handle video output from [Player].
  late media_kit_video.VideoController mediaPlayerController;

  late FijkPlayer ijkPlayer;

  GlobalKey<BrightnessVolumnDargAreaState> brightnessKey = GlobalKey<BrightnessVolumnDargAreaState>();

  LivePlayController livePlayController = Get.find<LivePlayController>();

  final SettingsService settings = Get.find<SettingsService>();

  bool enableCodec = true;

  bool playerCompatMode = false;

  Timer? showControllerTimer;
  final showController = true.obs;
  final showSettting = false.obs;
  final showLocked = false.obs;
  final danmuKey = GlobalKey();

  GlobalKey playerKey = GlobalKey();
  List<Map<String, dynamic>> videoFitType = [
    {'attr': BoxFit.contain, 'desc': '包含'},
    {'attr': BoxFit.cover, 'desc': '覆盖'},
    {'attr': BoxFit.fill, 'desc': '填充'},
    {'attr': BoxFit.fitHeight, 'desc': '高度适应'},
    {'attr': BoxFit.fitWidth, 'desc': '宽度适应'},
    {'attr': BoxFit.scaleDown, 'desc': '缩小适应'},
  ];
  Timer? _debounceTimer;
  StreamSubscription? _widthSubscription;
  StreamSubscription? _heightSubscription;

  void enableController() {
    showControllerTimer?.cancel();
    showControllerTimer = Timer(const Duration(seconds: 2), () {
      showController.value = false;
    });
    showController.value = true;
  }

  final hideDanmaku = false.obs;
  final danmakuArea = 1.0.obs;
  final danmakuTopArea = 0.0.obs;
  final danmakuBottomArea = 0.0.obs;
  final danmakuSpeed = 8.0.obs;
  final danmakuFontSize = 16.0.obs;
  final danmakuFontBorder = 4.0.obs;
  final danmakuOpacity = 1.0.obs;
  Timer? hasErrorTimer;
  VideoController({
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
    required this.videoPlayerIndex,
  }) {
    danmakuController = DanmakuController(
      onAddDanmaku: (item) {},
      onUpdateOption: (option) {},
      onPause: () {},
      onResume: () {},
      onClear: () {},
    );

    videoFitIndex.value = settings.videoFitIndex.value;
    videoFit.value = settings.videofitArrary[videoFitIndex.value];
    hideDanmaku.value = settings.hideDanmaku.value;
    danmakuTopArea.value = settings.danmakuTopArea.value;
    danmakuBottomArea.value = settings.danmakuBottomArea.value;
    danmakuSpeed.value = settings.danmakuSpeed.value;
    danmakuFontSize.value = settings.danmakuFontSize.value;
    danmakuFontBorder.value = settings.danmakuFontBorder.value;
    danmakuOpacity.value = settings.danmakuOpacity.value;
    initPagesConfig();
  }

  void initPagesConfig() {
    if (allowScreenKeepOn) WakelockPlus.enable();
    initVideoController();
    initDanmaku();
    initBattery();
    hasError.listen((p0) {
      if (hasError.value && !livePlayController.isLastLine.value) {
        hasErrorTimer?.cancel();
        hasErrorTimer = Timer(const Duration(milliseconds: 2000), () {
          SmartDialog.showToast("当前视频播放出错,正在为您切换路线");
          changeLine();
          hasErrorTimer?.cancel();
        });
      }
    });
  }

  // Battery level control
  final Battery _battery = Battery();
  final batteryLevel = 100.obs;

  late DanmakuController danmakuController;
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
    registerVolumeListener();
    if (videoPlayerIndex == 0 || Platform.isWindows) {
      enableCodec = settings.enableCodec.value;
      playerCompatMode = settings.playerCompatMode.value;
      player = Player();

      if (settings.customPlayerOutput.value) {
        (player.platform as dynamic).setProperty('ao', settings.audioOutputDriver.value);
      }
      var pp = player.platform as NativePlayer;
      if (Platform.isAndroid) {
        await pp.setProperty('force-seekable', 'yes');
      }
      mediaPlayerController = media_kit_video.VideoController(
        player,
        configuration: settings.customPlayerOutput.value
            ? VideoControllerConfiguration(
                vo: settings.videoOutputDriver.value,
                hwdec: settings.videoHardwareDecoder.value,
              )
            : playerCompatMode
            ? VideoControllerConfiguration(vo: 'mediacodec_embed', hwdec: 'mediacodec')
            : VideoControllerConfiguration(
                enableHardwareAcceleration: enableCodec,
                androidAttachSurfaceAfterVideoParameters: false,
              ),
      );
      setDataSource(datasource);
      mediaPlayerController.player.stream.playing.listen((bool playing) {
        isPlaying.value = playing;
        if (playing && mediaPlayerControllerInitialized.value == false) {
          mediaPlayerControllerInitialized.value = true;
          setVolume(settings.volume.value);
        }
      });
      mediaPlayerController.player.stream.error.listen((event) {
        if (event.toString().contains('Failed to open')) {
          hasError.value = true;
          isPlaying.value = false;
        }
      });
      _widthSubscription = player.stream.width.listen((event) {
        isVertical.value = (player.state.height ?? 9) > (player.state.width ?? 16);
      });
      _heightSubscription = player.stream.height.listen((event) {
        isVertical.value = (player.state.height ?? 9) > (player.state.width ?? 16);
      });

      mediaPlayerControllerInitialized.listen((value) {
        if (fullScreenByDefault && datasource.isNotEmpty && value) {
          Timer(const Duration(milliseconds: 500), () => toggleFullScreen());
        }
      });
      if (Platform.isAndroid) {
        pip = Floating();
        pip.pipStatusStream.listen((status) async {
          if (status == PiPStatus.enabled) {
            isPipMode.value = true;
          } else {
            isPipMode.value = false;
            isFullscreen.value = false;
            doExitFullScreen();
          }
        });
      }
    } else {
      ijkPlayer = FijkPlayer();
      setDataSource(datasource);
    }
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

  void initDanmaku() {
    hideDanmaku.value = PrefUtil.getBool('hideDanmaku') ?? false;
    hideDanmaku.listen((data) {
      if (data) {
        danmakuController.clear();
      }
      PrefUtil.setBool('hideDanmaku', data);
      settings.hideDanmaku.value = data;
    });
    danmakuArea.value = PrefUtil.getDouble('danmakuArea') ?? 0.0;
    danmakuArea.listen((data) {
      PrefUtil.setDouble('danmakuArea', data);
      settings.danmakuArea.value = data;
      updateDanmaku();
    });
    danmakuTopArea.value = PrefUtil.getDouble('danmakuTopArea') ?? 0.0;
    danmakuTopArea.listen((data) {
      PrefUtil.setDouble('danmakuTopArea', data);
      settings.danmakuTopArea.value = data;
      updateDanmaku();
    });
    danmakuBottomArea.value = PrefUtil.getDouble('danmakuBottomArea') ?? 0.0;
    danmakuBottomArea.listen((data) {
      PrefUtil.setDouble('danmakuBottomArea', data);
      settings.danmakuBottomArea.value = data;
      updateDanmaku();
    });
    danmakuSpeed.value = PrefUtil.getDouble('danmakuSpeed') ?? 8;
    danmakuSpeed.listen((data) {
      PrefUtil.setDouble('danmakuSpeed', data);
      settings.danmakuSpeed.value = data;
      updateDanmaku();
    });
    danmakuFontSize.value = PrefUtil.getDouble('danmakuFontSize') ?? 16;
    danmakuFontSize.listen((data) {
      PrefUtil.setDouble('danmakuFontSize', data);
      settings.danmakuFontSize.value = data;
      updateDanmaku();
    });
    danmakuFontBorder.value = PrefUtil.getDouble('danmakuFontBorder') ?? 4.0;
    danmakuFontBorder.listen((data) {
      PrefUtil.setDouble('danmakuFontBorder', data);
      settings.danmakuFontBorder.value = data;
      updateDanmaku();
    });
    danmakuOpacity.value = PrefUtil.getDouble('danmakuOpacity') ?? 1.0;
    danmakuOpacity.listen((data) {
      PrefUtil.setDouble('danmakuOpacity', data);
      settings.danmakuOpacity.value = data;
      updateDanmaku();
    });
  }

  void updateDanmaku() {
    danmakuController.updateOption(
      DanmakuOption(
        fontSize: danmakuFontSize.value,
        area: danmakuArea.value,
        topAreaDistance: danmakuTopArea.value,
        bottomAreaDistance: danmakuBottomArea.value,
        duration: danmakuSpeed.value.toInt(),
        opacity: danmakuOpacity.value,
        fontWeight: danmakuFontBorder.value.toInt(),
      ),
    );
  }

  void sendDanmaku(LiveMessage msg) {
    if (hideDanmaku.value) return;
    if (isPlaying.value) {
      danmakuController.addDanmaku(
        DanmakuContentItem(msg.message, color: Color.fromARGB(255, msg.color.r, msg.color.g, msg.color.b)),
      );
    }
  }

  @override
  void dispose() async {
    if (hasDestory == false) {
      await destory();
    }
    super.dispose();
  }

  void refresh() async {
    await destory();
    Timer(const Duration(seconds: 2), () {
      livePlayController.onInitPlayerState(reloadDataType: ReloadDataType.refreash);
    });
  }

  void changeLine({bool active = false}) async {
    // 播放错误 不一定是线路问题 先切换路线解决 后面尝试通知用户切换播放器
    await destory();
    Timer(const Duration(seconds: 2), () {
      livePlayController.onInitPlayerState(
        reloadDataType: ReloadDataType.changeLine,
        line: currentLineIndex,
        active: active,
      );
    });
  }

  Future<void> destory() async {
    isPlaying.value = false;
    hasError.value = false;
    livePlayController.success.value = false;
    hasDestory = true;
    _widthSubscription?.cancel();
    _heightSubscription?.cancel();
    if (allowScreenKeepOn) WakelockPlus.disable();

    FlutterVolumeController.removeListener();
    if (Platform.isAndroid || Platform.isIOS) {
      brightnessController.resetApplicationScreenBrightness();
      if (isFullscreen.value) {
        if (videoPlayerIndex == 1) {
          await Future.delayed(Duration(milliseconds: 100));
          ijkPlayer.exitFullScreen();
          Navigator.of(Get.context!).pop();
          doExitFullScreen();
          verticalScreen();
        } else {
          doExitFullScreen();
        }
      }
      if (videoPlayerIndex == 0) {
        player.dispose();
      } else {
        ijkPlayer.release();
      }
    } else {
      if (isFullscreen.value) {
        doExitFullScreen();
      }
      player.dispose();
    }
    isFullscreen.value = false;
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
    if (Platform.isWindows || videoPlayerIndex == 0) {
      player.pause();
      player.open(Media(datasource, httpHeaders: headers));
    } else {
      await FijkHelper.setFijkOption(ijkPlayer, enableCodec: enableCodec, headers: headers);
      ijkPlayer.setDataSource(url, autoPlay: autoPlay);
      ijkPlayer.addListener(_playerListener);
    }
    notifyListeners();
  }

  void _playerListener() {
    isPlaying.value = ijkPlayer.state == FijkState.started;
    hasError.value = ijkPlayer.state == FijkState.error;
  }

  void setVideoFit(BoxFit fit) {
    videoFit.value = fit;
    settings.videoFitIndex.value = videoFitIndex.value;
  }

  void togglePlayPause() {
    if (Platform.isWindows || videoPlayerIndex == 0) {
      mediaPlayerController.player.playOrPause();
    } else {
      isPlaying.value ? ijkPlayer.pause() : ijkPlayer.start();
    }
  }

  void exitFullScreen() async {
    if (videoPlayerIndex == 1) {
      await Future.delayed(Duration(milliseconds: 100));
      ijkPlayer.exitFullScreen();
      Navigator.of(Get.context!).pop();
      doExitFullScreen();
      verticalScreen();
    } else {
      doExitFullScreen();
    }
    isFullscreen.value = false;
    showSettting.value = false;
  }

  /// 设置横屏
  Future setLandscapeOrientation() async {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  }

  /// 设置竖屏
  Future setPortraitOrientation() async {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  void toggleFullScreen() async {
    showLocked.value = false;
    showControllerTimer?.cancel();
    Timer(const Duration(seconds: 2), () {
      enableController();
    });
    bool isIjkPlayer = videoPlayerIndex == 1;
    if (isIjkPlayer) {
      if (isFullscreen.value) {
        await Future.delayed(Duration(milliseconds: 100));
        ijkPlayer.exitFullScreen();
        Navigator.of(Get.context!).pop();
        doExitFullScreen();
        verticalScreen();
      } else {
        await Future.delayed(Duration(milliseconds: 100));
        ijkPlayer.enterFullScreen();
        Navigator.push(Get.context!, MaterialPageRoute(builder: (_) => IjkPlayerFullscreen(controller: this)));
      }
    } else {
      if (isFullscreen.value) {
        await Future.delayed(Duration(milliseconds: 100));
        Navigator.of(Get.context!).pop();
        doExitFullScreen();
        verticalScreen();
      } else {
        await Future.delayed(Duration(milliseconds: 100));
        doEnterFullScreen();
        Navigator.push(Get.context!, MaterialPageRoute(builder: (_) => MediaPlayerFullscreen(controller: this)));
      }
    }
    isFullscreen.toggle();
  }

  void toggleWindowFullScreen() {
    // disable locked
    showLocked.value = false;
    // fix obx setstate when build
    showControllerTimer?.cancel();
    Timer(const Duration(seconds: 2), () {
      enableController();
    });

    if (Platform.isWindows || Platform.isLinux) {
      if (!isWindowFullscreen.value) {
        Get.to(() => DesktopFullscreen(controller: this, key: UniqueKey()));
      } else {
        Navigator.of(Get.context!).pop();
      }
      isWindowFullscreen.toggle();
    } else {
      throw UnimplementedError('Unsupported Platform');
    }
    enableController();
  }

  void enterPipMode(BuildContext context) async {
    if ((Platform.isAndroid || Platform.isIOS)) {
      danmakuController.clear();
      danmakuController.resume();
      if (Platform.isWindows || videoPlayerIndex == 0) {
        isFullscreen.toggle();
        if (isVertical.value) {
          await verticalScreen();
        }
        await Future.delayed(Duration(milliseconds: 100));
        doEnterFullScreen();
        await pip.enable(ImmediatePiP());
      } else {}
    }
  }

  // 注册音量变化监听器
  void registerVolumeListener() {
    FlutterVolumeController.addListener((volume) {
      // 音量变化时的回调
      if (Platform.isAndroid) {
        settings.volume.value = volume;
      }
    });
  }

  // volume & brightness
  Future<double?> volume() async {
    if (Platform.isWindows) {
      return mediaPlayerController.player.state.volume / 100;
    }
    return await FlutterVolumeController.getVolume();
  }

  Future<double> brightness() async {
    return await brightnessController.application;
  }

  void setVolume(double value) async {
    if (Platform.isWindows) {
      mediaPlayerController.player.setVolume(value * 100);
    } else {
      await FlutterVolumeController.setVolume(value);
    }
    settings.volume.value = value;
  }

  void setBrightness(double value) async {
    if (Platform.isAndroid || Platform.isIOS) {
      await brightnessController.setApplicationScreenBrightness(value);
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
          fit: StackFit.passthrough, // 使Stack填充整个父容器
          children: [
            Container(
              color: Colors.black, // 设置你想要的背景色
            ),
            Obx(
              () => media_kit_video.Video(
                key: ValueKey(controller.videoFit.value),
                pauseUponEnteringBackgroundMode: !controller.settings.enableBackgroundPlay.value,
                resumeUponEnteringForegroundMode: !controller.settings.enableBackgroundPlay.value,
                controller: controller.mediaPlayerController,
                fit: controller.videoFit.value,
                controls: controller.room.platform == Sites.iptvSite
                    ? media_kit_video.MaterialVideoControls
                    : (state) => VideoControllerPanel(controller: controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// use fullscreen with controller provider

class IjkPlayerFullscreen extends StatefulWidget {
  const IjkPlayerFullscreen({super.key, required this.controller});
  final VideoController controller;

  @override
  State<IjkPlayerFullscreen> createState() => _IjkPlayerFullscreenState();
}

class _IjkPlayerFullscreenState extends State<IjkPlayerFullscreen> {
  @override
  void initState() {
    super.initState();
    landScape();
    doEnterFullScreen();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          fit: StackFit.passthrough, // 使Stack填充整个父容器
          children: [
            Container(
              color: Colors.black, // 设置你想要的背景色
            ),
            Obx(
              () => FijkView(
                player: widget.controller.ijkPlayer,
                fit: FijkHelper.getIjkBoxFit(widget.controller.videoFit.value),
                fs: false,
                color: Colors.black,
                panelBuilder:
                    (FijkPlayer fijkPlayer, FijkData fijkData, BuildContext context, Size viewSize, Rect texturePos) =>
                        Container(),
              ),
            ),
            VideoControllerPanel(controller: widget.controller),
          ],
        ),
      ),
    );
  }
}

class MediaPlayerFullscreen extends StatefulWidget {
  const MediaPlayerFullscreen({super.key, required this.controller});
  final VideoController controller;

  @override
  State<MediaPlayerFullscreen> createState() => _MediaPlayerFullscreenState();
}

class _MediaPlayerFullscreenState extends State<MediaPlayerFullscreen> {
  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid || Platform.isIOS) {
      landScape();
      doEnterFullScreen();
    }
  }

  VideoController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          fit: StackFit.passthrough, // 使Stack填充整个父容器
          children: [
            Container(
              color: Colors.black, // 设置你想要的背景色
            ),
            Obx(
              () => media_kit_video.Video(
                key: ValueKey(controller.videoFit.value),
                pauseUponEnteringBackgroundMode: !controller.settings.enableBackgroundPlay.value,
                resumeUponEnteringForegroundMode: !controller.settings.enableBackgroundPlay.value,
                controller: controller.mediaPlayerController,
                fit: controller.videoFit.value,
                controls: controller.room.platform == Sites.iptvSite
                    ? media_kit_video.MaterialVideoControls
                    : (state) => VideoControllerPanel(controller: controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
