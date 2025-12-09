import 'dart:io';
import 'dart:async';
import 'dart:developer';
import 'package:get/get.dart';
import 'video_controller_panel.dart';
import 'package:pure_live/common/index.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:pure_live/modules/live_play/load_type.dart';
import 'package:pure_live/player/switchable_global_player.dart';
import 'package:pure_live/pkg/canvas_danmaku/danmaku_controller.dart';
import 'package:pure_live/modules/live_play/live_play_controller.dart';
import 'package:pure_live/pkg/canvas_danmaku/models/danmaku_option.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:pure_live/pkg/canvas_danmaku/models/danmaku_content_item.dart';
import 'package:pure_live/modules/live_play/widgets/video_player/fullscreen.dart';

class VideoController with ChangeNotifier {
  final LiveRoom room;
  final String datasourceType;
  String datasource;
  final bool allowBackgroundPlay;
  final bool allowScreenKeepOn;
  final bool allowFullScreen;
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

  final isFullscreen = false.obs;

  final isWindowFullscreen = false.obs;

  bool get supportPip => Platform.isAndroid;

  bool get supportWindowFull => Platform.isWindows || Platform.isLinux;

  bool get fullscreenUI => isFullscreen.value || isWindowFullscreen.value;

  GlobalKey<BrightnessVolumnDargAreaState> brightnessKey = GlobalKey<BrightnessVolumnDargAreaState>();

  LivePlayController livePlayController = Get.find<LivePlayController>();

  final SettingsService settings = Get.find<SettingsService>();

  bool enableCodec = true;

  bool playerCompatMode = false;

  final globalPlayer = SwitchableGlobalPlayer();

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
  VideoController({
    required this.room,
    required this.datasourceType,
    required this.datasource,
    required this.headers,
    this.allowBackgroundPlay = false,
    this.allowScreenKeepOn = false,
    this.allowFullScreen = true,
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
    globalPlayer.setDataSource(datasource, headers);
    globalPlayer.onError.listen((error) {
      if (error != null) {
        log("An error occured while loading the stream: $error", error: error, name: "VideoController");
        if (error.contains("Failed to open")) {
          SmartDialog.showToast("当前视频播放出错,正在切换线路");
          changeLine();
        }
      }
    });
    Future.delayed(Duration(milliseconds: 1000), () {
      if (settings.enableFullScreenDefault.value) {
        livePlayController.setFullScreen();
        enterFullScreen();
        isFullscreen.value = true;
        enableController();
      }
    });
  }

  void retryRoom() async {
    var liveRoom = await Sites.of(
      room.platform!,
    ).liveSite.getRoomDetail(roomId: room.roomId!, platform: room.platform!);
    if (liveRoom.liveStatus == LiveStatus.offline) {
      livePlayController.setNormalScreen();
      SmartDialog.showToast("该房间已下播", displayTime: const Duration(seconds: 2));
    } else {
      changeLine();
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

    globalPlayer.isInPipMode.listen((isInPip) {
      if (isInPip) {
        livePlayController.setFullScreen();
      } else {
        livePlayController.setNormalScreen();
      }
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
    if (globalPlayer.isPlaying.value) {
      danmakuController.addDanmaku(
        DanmakuContentItem(msg.message, color: Color.fromARGB(255, msg.color.r, msg.color.g, msg.color.b)),
      );
    }
  }

  @override
  void dispose() async {
    await destory();
    super.dispose();
  }

  void refresh() async {
    await destory();
    Timer(const Duration(seconds: 2), () {
      livePlayController.onInitPlayerState(reloadDataType: ReloadDataType.refreash);
    });
  }

  void changeLine() async {
    await destory();
    Timer(const Duration(seconds: 2), () {
      livePlayController.onInitPlayerState(reloadDataType: ReloadDataType.changeLine, line: currentLineIndex);
    });
  }

  Future<void> destory() async {
    if (allowScreenKeepOn) WakelockPlus.disable();
    FlutterVolumeController.removeListener();
    if (Platform.isAndroid || Platform.isIOS) {
      brightnessController.resetApplicationScreenBrightness();
    }
  }

  void setVideoFit(BoxFit fit) {
    var index = settings.videofitArrary.indexOf(fit);
    globalPlayer.changeVideoFit(index);
  }

  void exitFullScreen() async {
    isFullscreen.value = false;
    showSettting.value = false;
    doExitFullScreen();
  }

  void toggleFullScreen() async {
    showLocked.value = false;
    showControllerTimer?.cancel();
    Timer(const Duration(seconds: 2), () {
      enableController();
    });
    if (isFullscreen.value) {
      livePlayController.setNormalScreen();
      doExitFullScreen();
    } else {
      livePlayController.setFullScreen();
      enterFullScreen();
    }
    isFullscreen.toggle();
    enableController();
  }

  void enterFullScreen() {
    doEnterFullScreen();
    if (globalPlayer.isVerticalVideo.value) {
      verticalScreen();
    } else {
      landScape();
    }
  }

  void toggleWindowFullScreen() {
    showLocked.value = false;
    showControllerTimer?.cancel();
    Timer(const Duration(seconds: 2), () {
      enableController();
    });
    if (isWindowFullscreen.value) {
      livePlayController.setNormalScreen();
    } else {
      livePlayController.setWidescreen();
    }
    isWindowFullscreen.toggle();
    enableController();
  }

  // 注册音量变化监听器
  void registerVolumeListener() {
    FlutterVolumeController.addListener((volume) {
      if (Platform.isAndroid) {
        settings.volume.value = volume;
      }
    });
  }

  // volume & brightness
  Future<double?> volume() async {
    if (Platform.isWindows) {
      return globalPlayer.currentVolume.value / 100;
    }
    return await FlutterVolumeController.getVolume();
  }

  Future<double> brightness() async {
    return await brightnessController.application;
  }

  void setVolume(double value) async {
    if (Platform.isWindows) {
      globalPlayer.setVolume(value);
    } else {
      await FlutterVolumeController.setVolume(value);
    }
    globalPlayer.currentVolume.value = value;
    settings.volume.value = value;
  }

  void setBrightness(double value) async {
    if (Platform.isAndroid || Platform.isIOS) {
      await brightnessController.setApplicationScreenBrightness(value);
    }
  }
}
